// The display list: the flat POD stream the tree walk writes and the GPU replays.
//
// Nothing here touches the GPU. `draw.ms` records into these two arrays while the tree is
// walked, and `batcher.c` replays them once, at the end of the bracket. That is the whole
// point of the layer: a frame becomes data, so every claim in VOID2D.md "Frame shape" and
// "Order and batching" — painter's order, one upload per bracket, what broke a batch, what
// a culled subtree contributed — is a statement about an array that can be asserted with no
// GPU at all (docs/TESTING.md "T1").
//
// The streams:
//   - `vertices`, 8 floats per vertex (x y u v r g b a) in WORLD space, shared by every
//     command in the frame, so the whole frame is one upload and a command is a range.
//   - `uiInstances` and `spriteInstances`, P2's two instance streams, in LOCAL space with the
//     affine carried per instance — which is what lets the SDF be re-derived in local space
//     and survive rotation. Separate rather than one wide record, because guardrail 8 says a
//     sprite must not pay for the UI pipeline, and 36 floats to record 16 is paying.
//   - `commands`, COMMAND_FLOATS floats per command, fixed width. A fixed width costs a few
//     zero fields on a scissor and buys an index that is arithmetic rather than a scan —
//     and a snapshot whose lines are all the same shape.
//
// The colour pipeline (a 4x4 matrix, an add and a chroma key: 24 floats) is the bulk of a
// command and is the identity almost everywhere, so it lives in its own table and a command
// carries an index into it, or NO_EFFECT. The active rotated clip adds two projection
// intervals; axis-aligned clips stay in the hardware scissor.

import { Color, BlendMode } from "./types";
import { void2dCommandView } from "./batcher.h";
import { UI_PARAM_MODE, UiInstance } from "./instance";
import {
	UI_STRIDE, SPRITE_STRIDE,
	REC_UI_AFFINE, REC_UI_ORIGIN_SIZE, REC_UI_UV_RADII, REC_UI_BORDERS, REC_UI_PARAMS0,
	REC_UI_PARAMS1, REC_UI_COLOR_FILL, REC_UI_COLOR_BORDER, REC_UI_COLOR_EXTRA,
	REC_UI_FLOATS,
	REC_SPRITE_AFFINE, REC_SPRITE_ORIGIN_SIZE, REC_SPRITE_UV, REC_SPRITE_COLOR,
	REC_SPRITE_FLOATS,
} from "./instanceLayout";

export enum CommandKind {
	Draw,
	Scissor,
	Blur,
	// A render-target pass. These never appear in the swapchain list: a closed target block
	// is moved out of it into `targetCommands`, so the replay opens every target pass before
	// the swapchain pass and no pass is ever nested inside another (sokol asserts on that).
	TargetBegin,
	TargetEnd,
}

// Why this command could not join the one before it. Recorded so a T1 snapshot names its
// own cause: `break: view` is a finding, `break: 300 times` is a mystery.
export enum BreakReason {
	First,
	View,
	Blend,
	Sampler,
	Effect,
	Clip,
	Barrier,
	// P2: the run changed pipeline. A sprite run and a vertex run read different streams
	// and bind different programs, so they can never be one draw - and a T1 snapshot that
	// says `break: pipeline` names that, instead of leaving a count to be explained.
	Pipeline,
}

export const COMMAND_FLOATS: int32 = 32;
export const EFFECT_FLOATS: int32 = 44;
export const VERTEX_FLOATS: int32 = 8;
export const NO_EFFECT: int32 = -1;

// Field offsets inside one command record. Named, because `commands[base + 7]` in the
// emitter and `cmd[7]` in the replay is exactly how the two drift apart.
export const CMD_KIND: int32 = 0;
export const CMD_BREAK: int32 = 1;
export const CMD_VERTEX_OFFSET: int32 = 2;
export const CMD_VERTEX_COUNT: int32 = 3;
export const CMD_VIEW: int32 = 4;
export const CMD_BLEND: int32 = 5;
// Which of the four samplers the draw wants: `smooth * 2 + tileWrap`. It stopped being a
// single bit when `tileWrap` arrived, so it is an index and not a flag.
export const CMD_SAMPLER: int32 = 6;
export const SAMPLER_COUNT: int32 = 4;
export const CMD_EFFECT: int32 = 7;
export const CMD_CLIP_X: int32 = 8;
export const CMD_CLIP_Y: int32 = 9;
export const CMD_CLIP_W: int32 = 10;
export const CMD_CLIP_H: int32 = 11;
export const CMD_ARG0: int32 = 12;
export const CMD_ARG1: int32 = 13;
export const CMD_RT_MODE: int32 = 14;
// Zero for the swapchain; otherwise the render target's physical-pixels-per-logical-pixel
// scale. The replay uses nonzero to choose the offscreen pipeline and the value to scale
// logical scissors.
export const CMD_CLEAR_R: int32 = 15;
export const CMD_CLEAR_G: int32 = 16;
export const CMD_CLEAR_B: int32 = 17;
export const CMD_CLEAR_A: int32 = 18;
// Which of P2's two pipelines the run wants, and the instance range inside the stream that
// pipeline reads. A Draw carries either a vertex range or an instance range, never both;
// the field says which, so the replay branches on the record rather than on a guess about
// whether a count is zero.
export const CMD_PIPELINE: int32 = 19;
export const CMD_INSTANCE_OFFSET: int32 = 20;
export const CMD_INSTANCE_COUNT: int32 = 21;
export const CMD_CLIP_U_X: int32 = 22;
export const CMD_CLIP_U_Y: int32 = 23;
export const CMD_CLIP_U_MIN: int32 = 24;
export const CMD_CLIP_U_MAX: int32 = 25;
export const CMD_CLIP_V_X: int32 = 26;
export const CMD_CLIP_V_Y: int32 = 27;
export const CMD_CLIP_V_MIN: int32 = 28;
export const CMD_CLIP_V_MAX: int32 = 29;
export const CMD_VIEW_HIGH: int32 = 30;
export const EFFECT_GRADIENT_META: int32 = 24;
export const EFFECT_GRADIENT_PARAMS: int32 = 28;
export const EFFECT_GRADIENT_COLOR0: int32 = 32;
export const EFFECT_GRADIENT_COLOR1: int32 = 36;
export const EFFECT_GRADIENT_COLOR2: int32 = 40;

export enum Pipeline {
	Vertex,
	Sprite,
	Ui,
}

export struct Clip {
	x: float32;
	y: float32;
	w: float32;
	h: float32;
	ux: float32;
	uy: float32;
	uMin: float32;
	uMax: float32;
	vx: float32;
	vy: float32;
	vMin: float32;
	vMax: float32;
}

export const NO_CLIP: Clip = {
	x: 0.0, y: 0.0, w: 0.0, h: 0.0,
	ux: 0.0, uy: 0.0, uMin: 0.0, uMax: 0.0,
	vx: 0.0, vy: 0.0, vMin: 0.0, vMax: 0.0,
};

export struct MaskClip {
	x0: float32;
	y0: float32;
	x1: float32;
	y1: float32;
	ux: float32;
	uy: float32;
	uMin: float32;
	uMax: float32;
	vx: float32;
	vy: float32;
	vMin: float32;
	vMax: float32;
}

export const NO_MASK_CLIP: MaskClip = {
	x0: 0.0, y0: 0.0, x1: 0.0, y1: 0.0,
	ux: 0.0, uy: 0.0, uMin: 0.0, uMax: 0.0,
	vx: 0.0, vy: 0.0, vMin: 0.0, vMax: 0.0,
};

export const NO_MASK: int32 = -1;
export const NO_REPAINT: int32 = -1;

export enum PaintState {
	Unpainted,
	Painted,
	InTarget,
}

export struct PaintIndex {
	commands: int32;
	effects: int32;
	vertices: int32;
	uiInstances: int32;
	spriteInstances: int32;
	runOpen: boolean;
	runStart: int32;
	pipeline: Pipeline;
	reason: BreakReason;
	view: uint32;
	blend: BlendMode;
	sampler: int32;
	effect: int32;
	hasEffect: boolean;
	mask: int32;
}

export const NO_PAINT: PaintIndex = {
	commands: 0, effects: 0, vertices: 0, uiInstances: 0, spriteInstances: 0,
	runOpen: false, runStart: 0, pipeline: Pipeline.Vertex, reason: BreakReason.First, view: 0,
	blend: BlendMode.Alpha, sampler: 0, effect: NO_EFFECT, hasEffect: false, mask: NO_MASK,
};

const MAX_TARGET_DEPTH: int32 = 8;

export interface DisplayList {
	id: int32;
	commands: Vec<float32>;
	effects: Vec<float32>;
	vertices: Vec<float32>;
	uiInstances: Vec<float32>;
	spriteInstances: Vec<float32>;
	targetCommands: Vec<float32>;
	commandTotal: int32;
	targetCommandTotal: int32;
	effectTotal: int32;
	vertexTotal: int32;
	uiInstanceTotal: int32;
	spriteInstanceTotal: int32;
	targetMarks: Vec<int32>;
	targetClipSaves: Vec<Clip>;
	targetClipRecordedSaves: Vec<boolean>;
	targetScaleSaves: Vec<float32>;
	targetDepthNow: int32;
	targetOverflowed: boolean;
	// The clip the replay is under. A scissor is a command, not a call, so the emitter tracks
	// what it last recorded and only records a change.
	clip: Clip;
	clipRecorded: boolean;
	renderTargetScale: float32;
	masks: Vec<MaskClip>;
	maskTotal: int32;
	paintStarts: Vec<PaintIndex>;
	paintEnds: Vec<PaintIndex>;
	paintStates: Vec<PaintState>;
	paintEnd: PaintIndex;
	painted: boolean;
	paintedW: float32;
	paintedH: float32;
	paintedDpi: float32;
	paintedSmooth: boolean;
	patches: int32;
	repainted: int32;
	targetsPending: boolean;
	uploadAll: boolean;
	dirtyVertices: boolean;
	dirtySprites: boolean;
	dirtyUi: Vec<int32>;
	dirtyUiTotal: int32;
}

let serials: Vec<int32> = [];

// Each starts with one record's worth of zeros so that `arr[0]` is always in bounds: a
// frame that records no effect at all would otherwise index an empty array to take its
// address. Counts come from the `*Total` variables, never from `.length`, so the seed is
// invisible to every reader.
export function displayList(): DisplayList {
	serials.push(0);
	return {
		id: (serials.length as int32) - 1,
		commands: new Array(COMMAND_FLOATS),
		effects: new Array(EFFECT_FLOATS),
		vertices: new Array(VERTEX_FLOATS),
		uiInstances: new Array(REC_UI_FLOATS),
		spriteInstances: new Array(REC_SPRITE_FLOATS),
		targetCommands: new Array(COMMAND_FLOATS),
		commandTotal: 0,
		targetCommandTotal: 0,
		effectTotal: 0,
		vertexTotal: 0,
		uiInstanceTotal: 0,
		spriteInstanceTotal: 0,
		targetMarks: new Array(MAX_TARGET_DEPTH),
		targetClipSaves: new Array(MAX_TARGET_DEPTH),
		targetClipRecordedSaves: new Array(MAX_TARGET_DEPTH),
		targetScaleSaves: new Array(MAX_TARGET_DEPTH),
		targetDepthNow: 0,
		targetOverflowed: false,
		clip: NO_CLIP,
		clipRecorded: false,
		renderTargetScale: 0.0,
		masks: [],
		maskTotal: 0,
		paintStarts: [],
		paintEnds: [],
		paintStates: [],
		paintEnd: NO_PAINT,
		painted: false,
		paintedW: 0.0,
		paintedH: 0.0,
		paintedDpi: 0.0,
		paintedSmooth: false,
		patches: 0,
		repainted: 0,
		targetsPending: false,
		uploadAll: false,
		dirtyVertices: false,
		dirtySprites: false,
		dirtyUi: new Array(2),
		dirtyUiTotal: 0,
	};
}

const defaultList: DisplayList = displayList();
let list: DisplayList = defaultList;

export function useList(next: DisplayList): void { list = next; }
export function isDefaultList(l: DisplayList): boolean { return l === defaultList; }
export function useDefaultList(): void { list = defaultList; }
export function currentList(): DisplayList { return list; }

export function resetList(): void {
	list.commandTotal = 0;
	list.targetCommandTotal = 0;
	list.effectTotal = 0;
	list.vertexTotal = 0;
	list.uiInstanceTotal = 0;
	list.spriteInstanceTotal = 0;
	list.clipRecorded = false;
	// The rect too, not only the flag. Leaving it meant the first command of a new frame
	// carried the last clip of the previous one; `popClip` records (0,0,0,0) at depth zero so
	// a balanced frame always ended clear and production never noticed, but an unbalanced one
	// would have scissored to a stale rect - and T1 found it at once, because a snapshot then
	// depended on which test had run before it in the same process.
	list.clip = NO_CLIP;
	list.renderTargetScale = 0.0;
	list.targetDepthNow = 0;
	list.targetOverflowed = false;
	list.maskTotal = 0;
	list.targetsPending = true;
	list.uploadAll = true;
	list.dirtyVertices = false;
	list.dirtySprites = false;
	list.dirtyUiTotal = 0;
	serials[list.id] = serials[list.id] + 1;
}

export function listSerial(id: int32): int32 { return serials[id]; }

export function pushMaskClip(c: MaskClip): int32 {
	const at: int32 = list.maskTotal;
	if (at < (list.masks.length as int32)) {
		list.masks[at] = c;
	} else {
		list.masks.push(c);
	}
	list.maskTotal = at + 1;
	return at;
}

export function maskClipAt(index: int32): MaskClip { return list.masks[index]; }

function growPaint(row: int32): void {
	while ((list.paintStates.length as int32) <= row) {
		list.paintStarts.push(NO_PAINT);
		list.paintEnds.push(NO_PAINT);
		list.paintStates.push(PaintState.Unpainted);
	}
}

export function recordPaint(row: int32, start: PaintIndex, end: PaintIndex): void {
	growPaint(row);
	list.paintStarts[row] = start;
	list.paintEnds[row] = end;
	list.paintStates[row] = PaintState.Painted;
}

export function markPaintState(row: int32, state: PaintState): void {
	growPaint(row);
	list.paintStates[row] = state;
}

export function paintStateOf(row: int32): PaintState {
	if (row >= (list.paintStates.length as int32)) { return PaintState.Unpainted; }
	return list.paintStates[row];
}

export function paintStartOf(row: int32): PaintIndex { return list.paintStarts[row]; }

export function uploaded(): void {
	list.uploadAll = false;
	list.dirtyVertices = false;
	list.dirtySprites = false;
	list.dirtyUiTotal = 0;
}

let saved: Vec<float32> = [];

function keep(at: int32, value: float32): void {
	if (at < (saved.length as int32)) {
		saved[at] = value;
	} else {
		saved.push(value);
	}
}

export function saveRange(a: PaintIndex, b: PaintIndex): void {
	let k: int32 = 0;
	for (let i: int32 = a.uiInstances * REC_UI_FLOATS; i < b.uiInstances * REC_UI_FLOATS; i++) {
		keep(k, list.uiInstances[i]);
		k = k + 1;
	}
	for (let i: int32 = a.spriteInstances * REC_SPRITE_FLOATS; i < b.spriteInstances * REC_SPRITE_FLOATS; i++) {
		keep(k, list.spriteInstances[i]);
		k = k + 1;
	}
	for (let i: int32 = a.vertices * VERTEX_FLOATS; i < b.vertices * VERTEX_FLOATS; i++) {
		keep(k, list.vertices[i]);
		k = k + 1;
	}
}

function addDirtyUi(from: int32, to: int32): void {
	const pairs: int32 = list.dirtyUiTotal;
	if (pairs > 0 && list.dirtyUi[pairs * 2 - 1] == from) {
		list.dirtyUi[pairs * 2 - 1] = to;
		return;
	}
	while ((list.dirtyUi.length as int32) < (pairs + 1) * 2) { list.dirtyUi.push(0); }
	list.dirtyUi[pairs * 2] = from;
	list.dirtyUi[pairs * 2 + 1] = to;
	list.dirtyUiTotal = pairs + 1;
}

export function noteRange(a: PaintIndex, b: PaintIndex): void {
	let k: int32 = 0;
	let changed: boolean = false;
	for (let i: int32 = a.uiInstances * REC_UI_FLOATS; i < b.uiInstances * REC_UI_FLOATS; i++) {
		if (saved[k] != list.uiInstances[i]) { changed = true; }
		k = k + 1;
	}
	if (changed) { addDirtyUi(a.uiInstances, b.uiInstances); }
	changed = false;
	for (let i: int32 = a.spriteInstances * REC_SPRITE_FLOATS; i < b.spriteInstances * REC_SPRITE_FLOATS; i++) {
		if (saved[k] != list.spriteInstances[i]) { changed = true; }
		k = k + 1;
	}
	if (changed) { list.dirtySprites = true; }
	changed = false;
	for (let i: int32 = a.vertices * VERTEX_FLOATS; i < b.vertices * VERTEX_FLOATS; i++) {
		if (saved[k] != list.vertices[i]) { changed = true; }
		k = k + 1;
	}
	if (changed) { list.dirtyVertices = true; }
}
export function paintEndOf(row: int32): PaintIndex { return list.paintEnds[row]; }

// Which pipeline set and device scale every command recorded from here will ask the replay
// to use. A zero scale is the swapchain, whose scale belongs to the frame.
export function setRenderTargetMode(on: boolean): void { list.renderTargetScale = on ? 1.0 : 0.0; }
export function renderTargetScaleNow(): float32 { return list.renderTargetScale; }

export function commandCount(): int32 { return list.commandTotal; }
export function targetCommandCount(): int32 { return list.targetCommandTotal; }
export function targetDepth(): int32 { return list.targetDepthNow; }
export function targetStackOverflowed(): boolean { return list.targetOverflowed; }

export function targetCommandField(index: int32, field: int32): float32 {
	return list.targetCommands[index * COMMAND_FLOATS + field];
}
export function effectCount(): int32 { return list.effectTotal; }
export function vertexCount(): int32 { return list.vertexTotal; }

export function commandField(index: int32, field: int32): float32 {
	return list.commands[index * COMMAND_FLOATS + field];
}

export function commandView(index: int32): uint32 {
	return joinView(commandField(index, CMD_VIEW), commandField(index, CMD_VIEW_HIGH));
}

export function targetCommandView(index: int32): uint32 {
	return joinView(targetCommandField(index, CMD_VIEW), targetCommandField(index, CMD_VIEW_HIGH));
}

function joinView(low: float32, high: float32): uint32 {
	return ((high as uint32) << 16) | (low as uint32);
}

function writeView(base: int32, view: uint32): void {
	list.commands[base + CMD_VIEW] = (view & 0xFFFF) as float32;
	list.commands[base + CMD_VIEW_HIGH] = (view >> 16) as float32;
}

export function effectField(index: int32, field: int32): float32 {
	return list.effects[index * EFFECT_FLOATS + field];
}

export function vertexField(index: int32, field: int32): float32 {
	return list.vertices[index * VERTEX_FLOATS + field];
}

// Grown in place and never shrunk, so a frame that peaked once does not reallocate again.
function growTo(ref stream: Vec<float32>, length: int32): void {
	while ((stream.length as int32) < length) { stream.push(0.0 as float32); }
}

// Append one vertex to the frame's stream and answer nothing — the caller already knows
// where it landed, because it asked for the offset before it started.
export function pushVertex(
	x: float32,
	y: float32,
	u: float32,
	v: float32,
	r: float32,
	g: float32,
	b: float32,
	a: float32,
): void {
	const base: int32 = list.vertexTotal * VERTEX_FLOATS;
	growTo(list.vertices, base + VERTEX_FLOATS);
	list.vertices[base] = x;
	list.vertices[base + 1] = y;
	list.vertices[base + 2] = u;
	list.vertices[base + 3] = v;
	list.vertices[base + 4] = r;
	list.vertices[base + 5] = g;
	list.vertices[base + 6] = b;
	list.vertices[base + 7] = a;
	list.vertexTotal = list.vertexTotal + 1;
}

// Append one UI instance. The caller passes the six float4 lanes and three colours; the
// packing to UBYTE4N happens in `batcher.c` on the way to the GPU (instance.ms, "the RECORD
// layout").
export function pushUiInstance(inst: UiInstance, originX: float32, originY: float32): void {
	const base: int32 = list.uiInstanceTotal * REC_UI_FLOATS;
	growTo(list.uiInstances, base + REC_UI_FLOATS);
	const [u0, u1, u2, u3] = inst.uvRadii;
	const [bl, bt, br, bb] = inst.borders;
	const [p1, p2, p3] = inst.params;
	const [q0, q1, q2, q3] = inst.params1;
	list.uiInstances[base + REC_UI_AFFINE] = inst.affine.a;
	list.uiInstances[base + REC_UI_AFFINE + 1] = inst.affine.b;
	list.uiInstances[base + REC_UI_AFFINE + 2] = inst.affine.c;
	list.uiInstances[base + REC_UI_AFFINE + 3] = inst.affine.d;
	list.uiInstances[base + REC_UI_ORIGIN_SIZE] = inst.x - originX;
	list.uiInstances[base + REC_UI_ORIGIN_SIZE + 1] = inst.y - originY;
	list.uiInstances[base + REC_UI_ORIGIN_SIZE + 2] = inst.w;
	list.uiInstances[base + REC_UI_ORIGIN_SIZE + 3] = inst.h;
	list.uiInstances[base + REC_UI_UV_RADII] = u0;
	list.uiInstances[base + REC_UI_UV_RADII + 1] = u1;
	list.uiInstances[base + REC_UI_UV_RADII + 2] = u2;
	list.uiInstances[base + REC_UI_UV_RADII + 3] = u3;
	list.uiInstances[base + REC_UI_BORDERS] = bl;
	list.uiInstances[base + REC_UI_BORDERS + 1] = bt;
	list.uiInstances[base + REC_UI_BORDERS + 2] = br;
	list.uiInstances[base + REC_UI_BORDERS + 3] = bb;
	list.uiInstances[base + REC_UI_PARAMS0] = (inst.mode as int32) as float32;
	list.uiInstances[base + REC_UI_PARAMS0 + 1] = p1;
	list.uiInstances[base + REC_UI_PARAMS0 + 2] = p2;
	list.uiInstances[base + REC_UI_PARAMS0 + 3] = p3;
	list.uiInstances[base + REC_UI_PARAMS1] = q0;
	list.uiInstances[base + REC_UI_PARAMS1 + 1] = q1;
	list.uiInstances[base + REC_UI_PARAMS1 + 2] = q2;
	list.uiInstances[base + REC_UI_PARAMS1 + 3] = q3;
	list.uiInstances[base + REC_UI_COLOR_FILL] = inst.fill.r;
	list.uiInstances[base + REC_UI_COLOR_FILL + 1] = inst.fill.g;
	list.uiInstances[base + REC_UI_COLOR_FILL + 2] = inst.fill.b;
	list.uiInstances[base + REC_UI_COLOR_FILL + 3] = inst.fill.a;
	list.uiInstances[base + REC_UI_COLOR_BORDER] = inst.border.r;
	list.uiInstances[base + REC_UI_COLOR_BORDER + 1] = inst.border.g;
	list.uiInstances[base + REC_UI_COLOR_BORDER + 2] = inst.border.b;
	list.uiInstances[base + REC_UI_COLOR_BORDER + 3] = inst.border.a;
	list.uiInstances[base + REC_UI_COLOR_EXTRA] = inst.extra.r;
	list.uiInstances[base + REC_UI_COLOR_EXTRA + 1] = inst.extra.g;
	list.uiInstances[base + REC_UI_COLOR_EXTRA + 2] = inst.extra.b;
	list.uiInstances[base + REC_UI_COLOR_EXTRA + 3] = inst.extra.a;
	list.uiInstanceTotal = list.uiInstanceTotal + 1;
}

// The sprite stream is separate rather than a wide record with unused lanes: guardrail 8
// says a sprite-only scene must not pay for the UI pipeline, and paying 36 floats to record
// 16 is exactly that. It is also what makes B5 assertable - a sprite-only frame has
// uiInstanceCount() == 0, which no mode count could prove.
export function pushSpriteInstance(
	a: float32, b: float32, c: float32, d: float32,
	tx: float32, ty: float32, w: float32, h: float32,
	u0: float32, v0: float32, u1: float32, v1: float32,
	color: Color,
): void {
	const base: int32 = list.spriteInstanceTotal * REC_SPRITE_FLOATS;
	growTo(list.spriteInstances, base + REC_SPRITE_FLOATS);
	list.spriteInstances[base + REC_SPRITE_AFFINE] = a;
	list.spriteInstances[base + REC_SPRITE_AFFINE + 1] = b;
	list.spriteInstances[base + REC_SPRITE_AFFINE + 2] = c;
	list.spriteInstances[base + REC_SPRITE_AFFINE + 3] = d;
	list.spriteInstances[base + REC_SPRITE_ORIGIN_SIZE] = tx;
	list.spriteInstances[base + REC_SPRITE_ORIGIN_SIZE + 1] = ty;
	list.spriteInstances[base + REC_SPRITE_ORIGIN_SIZE + 2] = w;
	list.spriteInstances[base + REC_SPRITE_ORIGIN_SIZE + 3] = h;
	list.spriteInstances[base + REC_SPRITE_UV] = u0;
	list.spriteInstances[base + REC_SPRITE_UV + 1] = v0;
	list.spriteInstances[base + REC_SPRITE_UV + 2] = u1;
	list.spriteInstances[base + REC_SPRITE_UV + 3] = v1;
	list.spriteInstances[base + REC_SPRITE_COLOR] = color.r;
	list.spriteInstances[base + REC_SPRITE_COLOR + 1] = color.g;
	list.spriteInstances[base + REC_SPRITE_COLOR + 2] = color.b;
	list.spriteInstances[base + REC_SPRITE_COLOR + 3] = color.a;
	list.spriteInstanceTotal = list.spriteInstanceTotal + 1;
}

export function uiInstanceCount(): int32 { return list.uiInstanceTotal; }
export function spriteInstanceCount(): int32 { return list.spriteInstanceTotal; }

export function uiInstanceField(index: int32, field: int32): float32 {
	return list.uiInstances[index * REC_UI_FLOATS + field];
}

export function spriteInstanceField(index: int32, field: int32): float32 {
	return list.spriteInstances[index * REC_SPRITE_FLOATS + field];
}

// What the frame will upload for its instances, in GPU bytes rather than record floats.
export function instanceUploadBytes(): int32 {
	return list.uiInstanceTotal * UI_STRIDE + list.spriteInstanceTotal * SPRITE_STRIDE;
}

// How many instances carry each mode. The counter A4 asks for a negative control on: it
// moves when an emitter changes mode, and a sprite-only frame reads zero across the board.
export function uiModeCount(mode: int32): int32 {
	let n: int32 = 0;
	for (let i: int32 = 0; i < list.uiInstanceTotal; i++) {
		const m: float32 = list.uiInstances[i * REC_UI_FLOATS + REC_UI_PARAMS0 + UI_PARAM_MODE];
		if ((m as int32) == mode) { n = n + 1; }
	}
	return n;
}

// The colour pipeline as a row of its own. Returns the index a command should carry.
export function pushEffect(matrix: Span<float32>, add: Color, key: Color): int32 {
	const base: int32 = list.effectTotal * EFFECT_FLOATS;
	growTo(list.effects, base + EFFECT_FLOATS);
	for (let i: int32 = 0; i < EFFECT_FLOATS; i++) { list.effects[base + i] = 0.0; }
	const hasMatrix: boolean = (matrix.length as int32) >= 16;
	for (let i: int32 = 0; i < 16; i++) {
		list.effects[base + i] = hasMatrix ? matrix[i] : (i % 5 == 0 ? 1.0 : 0.0);
	}
	list.effects[base + 16] = add.r;
	list.effects[base + 17] = add.g;
	list.effects[base + 18] = add.b;
	list.effects[base + 19] = add.a;
	list.effects[base + 20] = key.r;
	list.effects[base + 21] = key.g;
	list.effects[base + 22] = key.b;
	list.effects[base + 23] = key.a;
	list.effectTotal = list.effectTotal + 1;
	return list.effectTotal - 1;
}

export function pushGradientEffect(
	matrix: Span<float32>,
	add: Color,
	key: Color,
	kind: int32,
	space: int32,
	dither: boolean,
	middle: float32,
	p0: float32,
	p1: float32,
	p2: float32,
	p3: float32,
	c0: Color,
	c1: Color,
	c2: Color,
): int32 {
	const index: int32 = pushEffect(matrix, add, key);
	const base: int32 = index * EFFECT_FLOATS;
	list.effects[base + EFFECT_GRADIENT_META] = kind as float32;
	list.effects[base + EFFECT_GRADIENT_META + 1] = space as float32;
	list.effects[base + EFFECT_GRADIENT_META + 2] = dither ? 1.0 : 0.0;
	list.effects[base + EFFECT_GRADIENT_META + 3] = middle;
	list.effects[base + EFFECT_GRADIENT_PARAMS] = p0;
	list.effects[base + EFFECT_GRADIENT_PARAMS + 1] = p1;
	list.effects[base + EFFECT_GRADIENT_PARAMS + 2] = p2;
	list.effects[base + EFFECT_GRADIENT_PARAMS + 3] = p3;
	list.effects[base + EFFECT_GRADIENT_COLOR0] = c0.r;
	list.effects[base + EFFECT_GRADIENT_COLOR0 + 1] = c0.g;
	list.effects[base + EFFECT_GRADIENT_COLOR0 + 2] = c0.b;
	list.effects[base + EFFECT_GRADIENT_COLOR0 + 3] = c0.a;
	list.effects[base + EFFECT_GRADIENT_COLOR1] = c1.r;
	list.effects[base + EFFECT_GRADIENT_COLOR1 + 1] = c1.g;
	list.effects[base + EFFECT_GRADIENT_COLOR1 + 2] = c1.b;
	list.effects[base + EFFECT_GRADIENT_COLOR1 + 3] = c1.a;
	list.effects[base + EFFECT_GRADIENT_COLOR2] = c2.r;
	list.effects[base + EFFECT_GRADIENT_COLOR2 + 1] = c2.g;
	list.effects[base + EFFECT_GRADIENT_COLOR2 + 2] = c2.b;
	list.effects[base + EFFECT_GRADIENT_COLOR2 + 3] = c2.a;
	return index;
}

function startCommand(kind: CommandKind, reason: BreakReason): int32 {
	const base: int32 = list.commandTotal * COMMAND_FLOATS;
	growTo(list.commands, base + COMMAND_FLOATS);
	for (let i: int32 = 0; i < COMMAND_FLOATS; i++) { list.commands[base + i] = 0.0; }
	list.commands[base + CMD_KIND] = (kind as int32) as float32;
	list.commands[base + CMD_EFFECT] = NO_EFFECT as float32;
	list.commands[base + CMD_BREAK] = (reason as int32) as float32;
	list.commands[base + CMD_CLIP_X] = list.clip.x;
	list.commands[base + CMD_CLIP_Y] = list.clip.y;
	list.commands[base + CMD_CLIP_W] = list.clip.w;
	list.commands[base + CMD_CLIP_H] = list.clip.h;
	list.commands[base + CMD_CLIP_U_X] = list.clip.ux;
	list.commands[base + CMD_CLIP_U_Y] = list.clip.uy;
	list.commands[base + CMD_CLIP_U_MIN] = list.clip.uMin;
	list.commands[base + CMD_CLIP_U_MAX] = list.clip.uMax;
	list.commands[base + CMD_CLIP_V_X] = list.clip.vx;
	list.commands[base + CMD_CLIP_V_Y] = list.clip.vy;
	list.commands[base + CMD_CLIP_V_MIN] = list.clip.vMin;
	list.commands[base + CMD_CLIP_V_MAX] = list.clip.vMax;
	list.commands[base + CMD_RT_MODE] = list.renderTargetScale;
	list.commandTotal = list.commandTotal + 1;
	return base;
}

// smooth * 2 + tileWrap. One function, because a packing that is open-coded in the emitter
// and re-derived in a test is a packing with two definitions.
export function samplerIndex(smooth: boolean, tileWrap: boolean): int32 {
	return (smooth ? 2 : 0) + (tileWrap ? 1 : 0);
}

export function recordDraw(
	reason: BreakReason,
	vertexOffset: int32,
	count: int32,
	view: uint32,
	blend: BlendMode,
	sampler: int32,
	effectIndex: int32,
): void {
	const base: int32 = startCommand(CommandKind.Draw, reason);
	list.commands[base + CMD_VERTEX_OFFSET] = vertexOffset as float32;
	list.commands[base + CMD_VERTEX_COUNT] = count as float32;
	writeView(base, view);
	list.commands[base + CMD_BLEND] = (blend as int32) as float32;
	list.commands[base + CMD_SAMPLER] = sampler as float32;
	list.commands[base + CMD_EFFECT] = effectIndex as float32;
}

// A run of unified-UI instances. Same shape as a sprite run - an instance range and a zero
// vertex count - because a third pipeline needs no new machinery, only its own record
// function and its own branch in the replay. What differs is the stream the offset indexes
// and the program the replay binds, and CMD_PIPELINE is what says which.
export function recordUiDraw(
	reason: BreakReason,
	instanceOffset: int32,
	count: int32,
	view: uint32,
	blend: BlendMode,
	sampler: int32,
): void {
	const base: int32 = startCommand(CommandKind.Draw, reason);
	list.commands[base + CMD_PIPELINE] = (Pipeline.Ui as int32) as float32;
	list.commands[base + CMD_INSTANCE_OFFSET] = instanceOffset as float32;
	list.commands[base + CMD_INSTANCE_COUNT] = count as float32;
	list.commands[base + CMD_VERTEX_COUNT] = 0.0;
	writeView(base, view);
	list.commands[base + CMD_BLEND] = (blend as int32) as float32;
	list.commands[base + CMD_SAMPLER] = sampler as float32;
	list.commands[base + CMD_EFFECT] = NO_EFFECT as float32;
}

// A run of instanced sprites. It carries an instance range and a vertex count of zero; the
// replay branches on CMD_PIPELINE before it looks at the vertex count, which is what stops
// a zero there from silently dropping the run.
export function recordSpriteDraw(
	reason: BreakReason,
	instanceOffset: int32,
	count: int32,
	view: uint32,
	blend: BlendMode,
	sampler: int32,
): void {
	const base: int32 = startCommand(CommandKind.Draw, reason);
	list.commands[base + CMD_PIPELINE] = (Pipeline.Sprite as int32) as float32;
	list.commands[base + CMD_INSTANCE_OFFSET] = instanceOffset as float32;
	list.commands[base + CMD_INSTANCE_COUNT] = count as float32;
	list.commands[base + CMD_VERTEX_COUNT] = 0.0;
	writeView(base, view);
	list.commands[base + CMD_BLEND] = (blend as int32) as float32;
	list.commands[base + CMD_SAMPLER] = sampler as float32;
	list.commands[base + CMD_EFFECT] = NO_EFFECT as float32;
}

// Open a render-target pass. Everything recorded until the matching `endTargetList` belongs
// to it. h2d saves and clears the clip per target (`h2d/Object.hx:896-956`): a Mask outside
// the filter must not scissor the target, whose coordinates are its own.
export function beginTargetList(
	rt: uint32,
	w: float32,
	h: float32,
	scale: float32,
	clearR: float32,
	clearG: float32,
	clearB: float32,
	clearA: float32,
): void {
	if (list.targetDepthNow >= MAX_TARGET_DEPTH) {
		// Recording into the parent is wrong, but it is visibly wrong rather than a stack
		// smash, and the flag makes the frame say so instead of the picture.
		list.targetOverflowed = true;
		return;
	}
	list.targetMarks[list.targetDepthNow] = list.commandTotal;
	list.targetScaleSaves[list.targetDepthNow] = list.renderTargetScale;
	list.targetClipSaves[list.targetDepthNow] = list.clip;
	list.targetClipRecordedSaves[list.targetDepthNow] = list.clipRecorded;
	list.targetDepthNow = list.targetDepthNow + 1;
	const base: int32 = startCommand(CommandKind.TargetBegin, BreakReason.Barrier);
	writeView(base, rt);
	list.commands[base + CMD_ARG0] = w;
	list.commands[base + CMD_ARG1] = h;
	list.commands[base + CMD_CLEAR_R] = clearR;
	list.commands[base + CMD_CLEAR_G] = clearG;
	list.commands[base + CMD_CLEAR_B] = clearB;
	list.commands[base + CMD_CLEAR_A] = clearA;
	// Inside a target the clip starts empty and the offscreen pipeline set applies.
	list.clipRecorded = false;
	list.clip = NO_CLIP;
	list.renderTargetScale = scale;
}

// Close the open target and move its block out of the swapchain list. Because targets close
// in LIFO order the block is the tail of `commands`, so this is a copy of a few records and
// a count, and an inner target has already moved ahead of its consumer.
export function endTargetList(): void {
	if (list.targetDepthNow <= 0) { return; }
	startCommand(CommandKind.TargetEnd, BreakReason.Barrier);
	list.targetDepthNow = list.targetDepthNow - 1;
	const mark: int32 = list.targetMarks[list.targetDepthNow];
	const from: int32 = mark * COMMAND_FLOATS;
	const upto: int32 = list.commandTotal * COMMAND_FLOATS;
	let write: int32 = list.targetCommandTotal * COMMAND_FLOATS;
	growTo(list.targetCommands, write + (upto - from));
	for (let i: int32 = from; i < upto; i++) {
		list.targetCommands[write] = list.commands[i];
		write = write + 1;
	}
	list.targetCommandTotal = list.targetCommandTotal + (list.commandTotal - mark);
	list.commandTotal = mark;
	list.clip = list.targetClipSaves[list.targetDepthNow];
	list.clipRecorded = list.targetClipRecordedSaves[list.targetDepthNow];
	list.renderTargetScale = list.targetScaleSaves[list.targetDepthNow];
}

// The clip the replay should be under from here on. The rect is a coarse hardware scissor;
// the two projection intervals are the exact four edges of a rotated Mask.
export function recordClip(next: Clip): void {
	if (list.clipRecorded && next == list.clip) { return; }
	list.clip = next;
	list.clipRecorded = true;
	startCommand(CommandKind.Scissor, BreakReason.Clip);
}

export function recordBlur(view: uint32, dirX: float32, dirY: float32): void {
	const base: int32 = startCommand(CommandKind.Blur, BreakReason.Barrier);
	writeView(base, view);
	list.commands[base + CMD_ARG0] = dirX;
	list.commands[base + CMD_ARG1] = dirY;
}

// How many Draw commands are in the stream — the draw-call count, known before a single
// sg_* call is made, which is what lets T4 gate it with no GPU.
export function drawCommandCount(): int32 {
	let count: int32 = 0;
	for (let i: int32 = 0; i < list.commandTotal; i++) {
		if ((commandField(i, CMD_KIND) as int32) == (CommandKind.Draw as int32)) { count = count + 1; }
	}
	return count;
}

export function breakReasonName(reason: int32): string {
	return match (reason as BreakReason) {
		BreakReason.First => "first",
		BreakReason.View => "view",
		BreakReason.Blend => "blend",
		BreakReason.Sampler => "sampler",
		BreakReason.Effect => "effect",
		BreakReason.Clip => "clip",
		BreakReason.Barrier => "barrier",
		BreakReason.Pipeline => "pipeline",
	};
}

export function commandKindName(kind: int32): string {
	return match (kind as CommandKind) {
		CommandKind.Draw => "draw",
		CommandKind.Scissor => "scissor",
		CommandKind.Blur => "blur",
		CommandKind.TargetBegin => "target-begin",
		CommandKind.TargetEnd => "target-end",
	};
}

test "a fresh list is empty" {
	resetList();
	assert commandCount() == 0;
	assert vertexCount() == 0;
	assert effectCount() == 0;
}

test "a view id past 2^24 reaches the replay whole, in the stream and in a target" {
	const view: uint32 = (291 << 16) | 5;
	const oneFloat: float32 = view as float32;
	assert view > 16777216;
	assert (oneFloat as uint32) != view;
	resetList();
	recordDraw(BreakReason.View, 0, 6, view, BlendMode.Alpha, samplerIndex(true, false), NO_EFFECT);
	recordBlur(view, 1.0, 0.0);
	assert commandView(0) == view;
	assert commandView(1) == view;
	assert void2dCommandView(list.commands[0]) == view;
	assert void2dCommandView(list.commands[COMMAND_FLOATS]) == view;
	resetList();
	beginTargetList(view, 64.0, 32.0, 1.0, 0.0, 0.0, 0.0, 0.0);
	recordDraw(BreakReason.First, 0, 6, view, BlendMode.Alpha, samplerIndex(true, false), NO_EFFECT);
	endTargetList();
	assert targetCommandView(0) == view;
	assert targetCommandView(1) == view;
}

test "a draw command carries its range and its reason" {
	resetList();
	recordDraw(BreakReason.View, 12, 6, 3, BlendMode.Add, samplerIndex(false, true), NO_EFFECT);
	assert commandCount() == 1;
	assert (commandField(0, CMD_KIND) as int32) == (CommandKind.Draw as int32);
	assert (commandField(0, CMD_BREAK) as int32) == (BreakReason.View as int32);
	assert (commandField(0, CMD_VERTEX_OFFSET) as int32) == 12;
	assert (commandField(0, CMD_VERTEX_COUNT) as int32) == 6;
	assert commandView(0) == 3;
	assert (commandField(0, CMD_BLEND) as int32) == (BlendMode.Add as int32);
	assert (commandField(0, CMD_SAMPLER) as int32) == 1;
	assert (commandField(0, CMD_EFFECT) as int32) == NO_EFFECT;
}

test "the sampler index packs smooth and tileWrap into the four combinations" {
	assert samplerIndex(false, false) == 0;
	assert samplerIndex(false, true) == 1;
	assert samplerIndex(true, false) == 2;
	assert samplerIndex(true, true) == 3;
	// Every combination is a distinct slot, and there are exactly as many as batcher.c makes.
	assert samplerIndex(true, true) + 1 == SAMPLER_COUNT;
}

test "a closed target block leaves the swapchain list and lands in the target list" {
	resetList();
	recordDraw(BreakReason.First, 0, 6, 1, BlendMode.Alpha, samplerIndex(true, false), NO_EFFECT);
	beginTargetList(7, 64.0, 32.0, 1.0, 0.0, 0.0, 0.0, 0.0);
	recordDraw(BreakReason.First, 6, 6, 2, BlendMode.Alpha, samplerIndex(true, false), NO_EFFECT);
	endTargetList();
	recordDraw(BreakReason.View, 12, 6, 3, BlendMode.Alpha, samplerIndex(true, false), NO_EFFECT);
	// The swapchain list kept only the sibling before and the consumer after it.
	assert commandCount() == 2;
	assert commandView(0) == 1;
	assert commandView(1) == 3;
	// The target's own pass went to the other list, wrapped in its markers.
	assert targetCommandCount() == 3;
	assert (targetCommandField(0, CMD_KIND) as int32) == (CommandKind.TargetBegin as int32);
	assert targetCommandView(0) == 7;
	assert targetCommandField(0, CMD_ARG0) == 64.0;
	assert targetCommandField(0, CMD_ARG1) == 32.0;
	assert targetCommandView(1) == 2;
	assert (targetCommandField(2, CMD_KIND) as int32) == (CommandKind.TargetEnd as int32);
	assert targetDepth() == 0;
}

test "a nested target is replayed before the target that consumes it" {
	resetList();
	beginTargetList(10, 8.0, 8.0, 1.0, 0.0, 0.0, 0.0, 0.0);
	recordDraw(BreakReason.First, 0, 6, 100, BlendMode.Alpha, samplerIndex(true, false), NO_EFFECT);
	beginTargetList(11, 4.0, 4.0, 1.0, 0.0, 0.0, 0.0, 0.0);
	recordDraw(BreakReason.First, 6, 6, 200, BlendMode.Alpha, samplerIndex(true, false), NO_EFFECT);
	endTargetList();
	recordDraw(BreakReason.View, 12, 6, 300, BlendMode.Alpha, samplerIndex(true, false), NO_EFFECT);
	endTargetList();
	assert commandCount() == 0;
	// inner: begin(11), draw 200, end — then outer: begin(10), draw 100, draw 300, end.
	assert (targetCommandField(0, CMD_KIND) as int32) == (CommandKind.TargetBegin as int32);
	assert targetCommandView(0) == 11;
	assert targetCommandView(1) == 200;
	assert (targetCommandField(2, CMD_KIND) as int32) == (CommandKind.TargetEnd as int32);
	assert (targetCommandField(3, CMD_KIND) as int32) == (CommandKind.TargetBegin as int32);
	assert targetCommandView(3) == 10;
	assert targetCommandView(4) == 100;
	assert targetCommandView(5) == 300;
	assert (targetCommandField(6, CMD_KIND) as int32) == (CommandKind.TargetEnd as int32);
	assert targetCommandCount() == 7;
}

test "a target starts with no clip and gives the outer clip back when it closes" {
	resetList();
	recordClip({ ...NO_CLIP, x: 5.0, y: 6.0, w: 7.0, h: 8.0 });
	beginTargetList(3, 16.0, 16.0, 1.0, 0.0, 0.0, 0.0, 0.0);
	// The outer Mask must not scissor the target: its coordinates are the target's own.
	// Recording the same rect the outer list holds therefore has to emit a real scissor.
	recordClip({ ...NO_CLIP, x: 5.0, y: 6.0, w: 7.0, h: 8.0 });
	endTargetList();
	// And back outside, the outer clip is current again, so re-recording it is a no-op.
	recordClip({ ...NO_CLIP, x: 5.0, y: 6.0, w: 7.0, h: 8.0 });
	assert commandCount() == 1;
	assert targetCommandCount() == 3;
	assert (targetCommandField(1, CMD_KIND) as int32) == (CommandKind.Scissor as int32);
	assert (targetCommandField(1, CMD_EFFECT) as int32) == NO_EFFECT;
}

test "the target stack refuses to overflow and says so" {
	resetList();
	for (let i: int32 = 0; i < 9; i++) {
		beginTargetList(1, 4.0, 4.0, 1.0, 0.0, 0.0, 0.0, 0.0);
	}
	assert targetStackOverflowed();
	assert targetDepth() == 8;
	for (let i: int32 = 0; i < 8; i++) { endTargetList(); }
	assert targetDepth() == 0;
}

test "recording the same clip twice records one scissor" {
	resetList();
	recordClip({ ...NO_CLIP, w: 10.0, h: 10.0 });
	recordClip({ ...NO_CLIP, w: 10.0, h: 10.0 });
	assert commandCount() == 1;
	recordClip({ ...NO_CLIP, x: 1.0, w: 10.0, h: 10.0 });
	assert commandCount() == 2;
}

test "a draw inherits the clip that was recorded before it" {
	resetList();
	recordClip({
		x: 4.0, y: 5.0, w: 6.0, h: 7.0,
		ux: 1.0, uy: 0.0, uMin: 4.0, uMax: 10.0,
		vx: 0.0, vy: 1.0, vMin: 5.0, vMax: 12.0,
	});
	recordDraw(BreakReason.First, 0, 6, 1, BlendMode.Alpha, samplerIndex(true, false), NO_EFFECT);
	assert commandField(1, CMD_CLIP_X) == 4.0;
	assert commandField(1, CMD_CLIP_Y) == 5.0;
	assert commandField(1, CMD_CLIP_W) == 6.0;
	assert commandField(1, CMD_CLIP_H) == 7.0;
	assert commandField(1, CMD_CLIP_U_X) == 1.0;
	assert commandField(1, CMD_CLIP_U_MIN) == 4.0;
	assert commandField(1, CMD_CLIP_V_Y) == 1.0;
	assert commandField(1, CMD_CLIP_V_MAX) == 12.0;
}

test "an empty matrix records the identity" {
	resetList();
	const index: int32 = pushEffect([], { r: 0.0, g: 0.0, b: 0.0, a: 0.0 }, { r: 0.0, g: 0.0, b: 0.0, a: 0.0 });
	assert index == 0;
	assert effectField(0, 0) == 1.0;
	assert effectField(0, 5) == 1.0;
	assert effectField(0, 10) == 1.0;
	assert effectField(0, 15) == 1.0;
	assert effectField(0, 1) == 0.0;
	assert effectField(0, 4) == 0.0;
}

// Exact binary fractions only: a float32 field compared against a float64 literal such as
// 0.4 fails on the last bit, and a harness test that fails for its own reasons is worse than
// no test.
test "vertices land where the offset says" {
	resetList();
	pushVertex(1.0, 2.0, 0.25, 0.5, 0.125, 0.375, 0.625, 0.875);
	assert vertexCount() == 1;
	assert vertexField(0, 0) == 1.0;
	assert vertexField(0, 1) == 2.0;
	assert vertexField(0, 2) == 0.25;
	assert vertexField(0, 3) == 0.5;
	assert vertexField(0, 4) == 0.125;
	assert vertexField(0, 7) == 0.875;
}

test "drawCommandCount counts draws and not scissors" {
	resetList();
	recordClip({ ...NO_CLIP, w: 8.0, h: 8.0 });
	recordDraw(BreakReason.First, 0, 6, 1, BlendMode.Alpha, samplerIndex(true, false), NO_EFFECT);
	recordDraw(BreakReason.View, 6, 6, 2, BlendMode.Alpha, samplerIndex(true, false), NO_EFFECT);
	assert commandCount() == 3;
	assert drawCommandCount() == 2;
}

test "a command carries the pipeline set the replay must bind" {
	resetList();
	recordDraw(BreakReason.First, 0, 6, 1, BlendMode.Alpha, samplerIndex(true, false), NO_EFFECT);
	assert commandField(0, CMD_RT_MODE) == 0.0;
	setRenderTargetMode(true);
	recordDraw(BreakReason.Barrier, 6, 6, 1, BlendMode.Alpha, samplerIndex(true, false), NO_EFFECT);
	assert commandField(1, CMD_RT_MODE) == 1.0;
	setRenderTargetMode(false);
}

test "every break reason and command kind has a name" {
	assert breakReasonName(BreakReason.View as int32).equals("view");
	assert breakReasonName(BreakReason.Sampler as int32).equals("sampler");
	assert breakReasonName(BreakReason.Barrier as int32).equals("barrier");
	assert commandKindName(CommandKind.Scissor as int32).equals("scissor");
	assert commandKindName(CommandKind.TargetBegin as int32).equals("target-begin");
}

test "every break reason an emitter can produce is one this module still defines" {
	// `BreakReason.Capacity` used to be here, produced by nothing and asserted only by a test
	// that named it - a value that could never appear in a stream, with a test that could
	// never fail. The recording side has no capacity limit at all: the streams are `Vec`s that
	// grow, and the only cap is on the GPU buffer, which is the replay's business and reports
	// itself by dropping the frame with an error.
	//
	// This is TESTING.md's "every command kind has a batch-break rule" cross-check in the one
	// direction that is assertable here: every reason still named is one `draw.ms` passes to
	// `recordDraw` or `startCommand`. If a reason is added and never emitted, the grep in that
	// file's review catches it; if one is emitted and not named, `commandKindName`'s match is
	// non-exhaustive and the compiler refuses to build.
	assert breakReasonName(BreakReason.First as int32).equals("first");
	assert breakReasonName(BreakReason.View as int32).equals("view");
	assert breakReasonName(BreakReason.Blend as int32).equals("blend");
	assert breakReasonName(BreakReason.Sampler as int32).equals("sampler");
	assert breakReasonName(BreakReason.Effect as int32).equals("effect");
	assert breakReasonName(BreakReason.Clip as int32).equals("clip");
	assert breakReasonName(BreakReason.Barrier as int32).equals("barrier");
	assert breakReasonName(BreakReason.Pipeline as int32).equals("pipeline");
}
