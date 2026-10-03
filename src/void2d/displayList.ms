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

import { Color, rgba } from "./types";
import { Mat4 } from "../math/math3d";
import { NO_COLOR_MATRIX, writeColorMatrix, readColorMatrix } from "./effect";
import { BlendMode } from "../gpu/state";
import { void2dCommandView, void2dCopyFloats } from "./batcher.h";
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
export const CMD_SAMPLER: int32 = 6;
export const SAMPLER_COUNT: int32 = 4;
export const SOURCE_PREMULTIPLIED: int32 = SAMPLER_COUNT;
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
export const CMD_SCOPE: int32 = 31;
export const SCOPE_FLOATS: int32 = 8;
export const NO_SCOPE: int32 = -1;
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

export enum Program2D {
	Vertex,
	Sprite,
	Ui,
	Blur,
}

export const PROGRAMS_2D: int32 = (Program2D.Blur as int32) + 1;
export const BLEND_MODES: int32 = (BlendMode.Min as int32) + 1;
export const PIPELINE_SLOTS: int32 = PROGRAMS_2D * 2 * BLEND_MODES;

export function noPipelines(): Vec<boolean> {
	let slots: Vec<boolean> = [];
	for (let i: int32 = 0; i < PIPELINE_SLOTS; i++) { slots.push(false); }
	return slots;
}

let wantedPipelines: Vec<boolean> = noPipelines();

export function pipelineSlot(program: int32, target: int32, blend: int32): int32 {
	return (program * 2 + target) * BLEND_MODES + blend;
}

export function pipelineWanted(slot: int32): boolean { return wantedPipelines[slot]; }

export function wantPipelineSlot(slot: int32): void { wantedPipelines[slot] = true; }

function wantPipeline(program: Program2D, blend: BlendMode): void {
	const target: int32 = activeContext.renderTargetScale != 0.0 ? 1 : 0;
	wantedPipelines[pipelineSlot(program as int32, target, blend as int32)] = true;
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
	InLanes,
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
	scope: int32;
}

export struct ScopeRecord {
	row: int32;
	parent: int32;
	scale: float32;
	dx: float32;
	dy: float32;
	x: float32;
	y: float32;
	w: float32;
	h: float32;
}

export const NO_PAINT: PaintIndex = {
	commands: 0, effects: 0, vertices: 0, uiInstances: 0, spriteInstances: 0,
	runOpen: false, runStart: 0, pipeline: Pipeline.Vertex, reason: BreakReason.First, view: 0,
	blend: BlendMode.Alpha, sampler: 0, effect: NO_EFFECT, hasEffect: false, mask: NO_MASK,
	scope: NO_SCOPE,
};

export const MAX_TARGET_DEPTH: int32 = 8;

export interface DrawContext2D {
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
	unrecordedTargets: int32;
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
	targetsPending: boolean;
	uploadAll: boolean;
	dirtyVertices: boolean;
	dirtySprites: boolean;
	dirtyUi: Vec<int32>;
	dirtyUiTotal: int32;
	limited: boolean;
	limit: PaintIndex;
	spill: PaintIndex;
	scopes: Vec<ScopeRecord>;
	scopeTotal: int32;
	scopeNow: int32;
	cameraScope: int32;
	scopeValues: Vec<float32>;
	targetScopeSaves: Vec<int32>;
	originX: float32;
	originY: float32;
	runStart: int32;
	runOpen: boolean;
	curPipeline: Pipeline;
	runReason: BreakReason;
	curView: uint32;
	curBlend: BlendMode;
	curSampler: int32;
	sceneSmooth: boolean;
	curEffect: int32;
	frameLive: boolean;
	fbW: float32;
	fbH: float32;
	frameDpi: float32;
	targetsFlushed: boolean;
	prepared: boolean;
	preparedFrame: uint32;
	savedView: Vec<uint32>;
	savedRun: Vec<float32>;
	savedSize: Vec<float32>;
	curMat: Mat4;
	curAdd: Color;
	curKey: Color;
	curHasEffect: boolean;
	clipStack: Vec<MaskClip>;
	maskIndices: Vec<int32>;
	clipDepth: int32;
	laneRunWasOpen: boolean;
	scopeDepths: Vec<int32>;
	saved: Vec<float32>;
	effectBase: int32;
	laneOrder: Vec<int32>;
	laneSourceOffsets: Vec<int32>;
	laneSourceCounts: Vec<int32>;
	laneOutputs: Vec<int32>;
	laneOffsets: Vec<int32>;
	laneOut: Vec<float32>;
	laneScratch: Vec<float32>;
	laneBySprite: Vec<int32>;
	laneByUi: Vec<int32>;
	laneByVertex: Vec<int32>;
}

let serials: Vec<int32> = [];

// Each starts with one record's worth of zeros so that `arr[0]` is always in bounds: a
// frame that records no effect at all would otherwise index an empty array to take its
// address. Counts come from the `*Total` variables, never from `.length`, so the seed is
// invisible to every reader.
export function create(this typeof DrawContext2D): DrawContext2D {
	serials.push(0);
	return DrawContext2D.twin((serials.length as int32) - 1);
}

export function twin(this typeof DrawContext2D, id: int32): DrawContext2D {
	return {
		id: id,
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
		unrecordedTargets: 0,
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
		targetsPending: false,
		uploadAll: false,
		dirtyVertices: false,
		dirtySprites: false,
		dirtyUi: new Array(2),
		dirtyUiTotal: 0,
		limited: false,
		limit: NO_PAINT,
		spill: NO_PAINT,
		scopes: [],
		scopeTotal: 0,
		scopeNow: NO_SCOPE,
		cameraScope: NO_SCOPE,
		scopeValues: new Array(SCOPE_FLOATS),
		targetScopeSaves: new Array(MAX_TARGET_DEPTH),
		originX: 0.0,
		originY: 0.0,
		runStart: 0,
		runOpen: false,
		curPipeline: Pipeline.Vertex,
		runReason: BreakReason.First,
		curView: 0,
		curBlend: BlendMode.Alpha,
		curSampler: 0,
		sceneSmooth: true,
		curEffect: NO_EFFECT,
		frameLive: true,
		fbW: 0.0,
		fbH: 0.0,
		frameDpi: 1.0,
		targetsFlushed: false,
		prepared: false,
		preparedFrame: 0,
		savedView: new Array(MAX_TARGET_DEPTH),
		savedRun: new Array(MAX_TARGET_DEPTH * 3),
		savedSize: new Array(MAX_TARGET_DEPTH * 4),
		curMat: NO_COLOR_MATRIX,
		curAdd: rgba(0.0, 0.0, 0.0, 0.0),
		curKey: rgba(0.0, 0.0, 0.0, 0.0),
		curHasEffect: false,
		clipStack: new Array(16),
		maskIndices: new Array(16),
		clipDepth: 0,
		laneRunWasOpen: false,
		scopeDepths: [],
		saved: [],
		effectBase: 0,
		laneOrder: [],
		laneSourceOffsets: [],
		laneSourceCounts: [],
		laneOutputs: [],
		laneOffsets: [],
		laneOut: [],
		laneScratch: [],
		laneBySprite: [],
		laneByUi: [],
		laneByVertex: [],
	};
}

const defaultContext: DrawContext2D = DrawContext2D.create();
let activeContext: DrawContext2D = defaultContext;

export function useContext(next: DrawContext2D): void { activeContext = next; }
export function isDefaultContext(context: DrawContext2D): boolean { return context === defaultContext; }
export function useDefaultContext(): void { activeContext = defaultContext; }
export function currentContext(): DrawContext2D { return activeContext; }

export function resetContext(): void {
	activeContext.commandTotal = 0;
	activeContext.targetCommandTotal = 0;
	activeContext.effectTotal = 0;
	activeContext.vertexTotal = 0;
	activeContext.uiInstanceTotal = 0;
	activeContext.spriteInstanceTotal = 0;
	activeContext.clipRecorded = false;
	// The rect too, not only the flag. Leaving it meant the first command of a new frame
	// carried the last clip of the previous one; `popClip` records (0,0,0,0) at depth zero so
	// a balanced frame always ended clear and production never noticed, but an unbalanced one
	// would have scissored to a stale rect - and T1 found it at once, because a snapshot then
	// depended on which test had run before it in the same process.
	activeContext.clip = NO_CLIP;
	activeContext.renderTargetScale = 0.0;
	activeContext.targetDepthNow = 0;
	activeContext.targetOverflowed = false;
	activeContext.unrecordedTargets = 0;
	activeContext.maskTotal = 0;
	activeContext.targetsPending = true;
	activeContext.uploadAll = true;
	activeContext.limited = false;
	activeContext.scopeTotal = 0;
	activeContext.scopeNow = NO_SCOPE;
	activeContext.cameraScope = NO_SCOPE;
	activeContext.dirtyVertices = false;
	activeContext.dirtySprites = false;
	activeContext.dirtyUiTotal = 0;
	serials[activeContext.id] = serials[activeContext.id] + 1;
}

export function contextSerial(id: int32): int32 { return serials[id]; }

export function pushScope(record: ScopeRecord): int32 {
	const at: int32 = activeContext.scopeTotal;
	if (at < (activeContext.scopes.length as int32)) {
		activeContext.scopes[at] = record;
	} else {
		activeContext.scopes.push(record);
	}
	activeContext.scopeTotal = at + 1;
	return at;
}

export function resolveScopes(): void {
	const floats: int32 = activeContext.scopeTotal * SCOPE_FLOATS;
	while ((activeContext.scopeValues.length as int32) < floats) { activeContext.scopeValues.push(0.0); }
	for (let k: int32 = 0; k < activeContext.scopeTotal; k++) {
		const r: ScopeRecord = activeContext.scopes[k];
		const base: int32 = k * SCOPE_FLOATS;
		let x: float32 = r.x;
		let y: float32 = r.y;
		let right: float32 = r.x + r.w;
		let bottom: float32 = r.y + r.h;
		let sx: float32 = r.dx;
		let sy: float32 = r.dy;
		if (r.parent != NO_SCOPE) {
			const up: int32 = r.parent * SCOPE_FLOATS;
			const px: float32 = activeContext.scopeValues[up];
			const py: float32 = activeContext.scopeValues[up + 1];
			x = x + px;
			y = y + py;
			right = right + px;
			bottom = bottom + py;
			const vx: float32 = activeContext.scopeValues[up + 2];
			const vy: float32 = activeContext.scopeValues[up + 3];
			if (vx > x) { x = vx; }
			if (vy > y) { y = vy; }
			if (vx + activeContext.scopeValues[up + 4] < right) { right = vx + activeContext.scopeValues[up + 4]; }
			if (vy + activeContext.scopeValues[up + 5] < bottom) { bottom = vy + activeContext.scopeValues[up + 5]; }
			sx = sx + px;
			sy = sy + py;
		}
		activeContext.scopeValues[base] = sx;
		activeContext.scopeValues[base + 1] = sy;
		activeContext.scopeValues[base + 2] = x;
		activeContext.scopeValues[base + 3] = y;
		activeContext.scopeValues[base + 4] = right > x ? right - x : 0.0;
		activeContext.scopeValues[base + 5] = bottom > y ? bottom - y : 0.0;
	}
}

export function scopeRow(l: DrawContext2D, scope: int32): int32 {
	return scope == NO_SCOPE ? NO_SCOPE : l.scopes[scope].row;
}

export function pushMaskClip(c: MaskClip): int32 {
	const at: int32 = activeContext.maskTotal;
	if (at < (activeContext.masks.length as int32)) {
		activeContext.masks[at] = c;
	} else {
		activeContext.masks.push(c);
	}
	activeContext.maskTotal = at + 1;
	return at;
}

export function maskClipAt(index: int32): MaskClip { return activeContext.masks[index]; }

function growPaint(row: int32): void {
	while ((activeContext.paintStates.length as int32) <= row) {
		activeContext.paintStarts.push(NO_PAINT);
		activeContext.paintEnds.push(NO_PAINT);
		activeContext.paintStates.push(PaintState.Unpainted);
	}
}

export function recordPaint(row: int32, start: PaintIndex, end: PaintIndex): void {
	growPaint(row);
	activeContext.paintStarts[row] = start;
	activeContext.paintEnds[row] = end;
	activeContext.paintStates[row] = PaintState.Painted;
}

export function markPaintState(row: int32, state: PaintState): void {
	growPaint(row);
	activeContext.paintStates[row] = state;
}

export function paintStateOf(row: int32): PaintState {
	if (row >= (activeContext.paintStates.length as int32)) { return PaintState.Unpainted; }
	return activeContext.paintStates[row];
}

export function paintStartOf(row: int32): PaintIndex { return activeContext.paintStarts[row]; }

export function uploaded(): void {
	activeContext.uploadAll = false;
	activeContext.dirtyVertices = false;
	activeContext.dirtySprites = false;
	activeContext.dirtyUiTotal = 0;
}


function keep(at: int32, value: float32): void {
	if (at < (activeContext.saved.length as int32)) {
		activeContext.saved[at] = value;
	} else {
		activeContext.saved.push(value);
	}
}

export function saveRange(a: PaintIndex, b: PaintIndex): void {
	let k: int32 = 0;
	for (let i: int32 = a.uiInstances * REC_UI_FLOATS; i < b.uiInstances * REC_UI_FLOATS; i++) {
		keep(k, activeContext.uiInstances[i]);
		k = k + 1;
	}
	for (let i: int32 = a.spriteInstances * REC_SPRITE_FLOATS; i < b.spriteInstances * REC_SPRITE_FLOATS; i++) {
		keep(k, activeContext.spriteInstances[i]);
		k = k + 1;
	}
	for (let i: int32 = a.vertices * VERTEX_FLOATS; i < b.vertices * VERTEX_FLOATS; i++) {
		keep(k, activeContext.vertices[i]);
		k = k + 1;
	}
}

function addDirtyUi(from: int32, to: int32): void {
	const pairs: int32 = activeContext.dirtyUiTotal;
	if (pairs > 0 && activeContext.dirtyUi[pairs * 2 - 1] == from) {
		activeContext.dirtyUi[pairs * 2 - 1] = to;
		return;
	}
	while ((activeContext.dirtyUi.length as int32) < (pairs + 1) * 2) { activeContext.dirtyUi.push(0); }
	activeContext.dirtyUi[pairs * 2] = from;
	activeContext.dirtyUi[pairs * 2 + 1] = to;
	activeContext.dirtyUiTotal = pairs + 1;
}

export function noteRange(a: PaintIndex, b: PaintIndex): void {
	let k: int32 = 0;
	let first: int32 = -1;
	let last: int32 = -1;
	for (let r: int32 = a.uiInstances; r < b.uiInstances; r++) {
		for (let f: int32 = 0; f < REC_UI_FLOATS; f++) {
			if (activeContext.saved[k] != activeContext.uiInstances[r * REC_UI_FLOATS + f]) {
				if (first < 0) { first = r; }
				last = r;
			}
			k = k + 1;
		}
	}
	if (first >= 0) { addDirtyUi(first, last + 1); }
	let changed: boolean = false;
	for (let i: int32 = a.spriteInstances * REC_SPRITE_FLOATS; i < b.spriteInstances * REC_SPRITE_FLOATS; i++) {
		if (activeContext.saved[k] != activeContext.spriteInstances[i]) { changed = true; }
		k = k + 1;
	}
	if (changed) { activeContext.dirtySprites = true; }
	changed = false;
	for (let i: int32 = a.vertices * VERTEX_FLOATS; i < b.vertices * VERTEX_FLOATS; i++) {
		if (activeContext.saved[k] != activeContext.vertices[i]) { changed = true; }
		k = k + 1;
	}
	if (changed) { activeContext.dirtyVertices = true; }
}
export function paintEndOf(row: int32): PaintIndex { return activeContext.paintEnds[row]; }

// Which pipeline set and device scale every command recorded from here will ask the replay
// to use. A zero scale is the swapchain, whose scale belongs to the frame.
export function setRenderTargetMode(on: boolean): void { activeContext.renderTargetScale = on ? 1.0 : 0.0; }
export function renderTargetScaleNow(): float32 { return activeContext.renderTargetScale; }

export function commandCount(): int32 { return activeContext.commandTotal; }
export function targetCommandCount(): int32 { return activeContext.targetCommandTotal; }
export function targetDepth(): int32 { return activeContext.targetDepthNow; }
export function targetStackOverflowed(): boolean { return activeContext.targetOverflowed; }

export function targetCommandField(index: int32, field: int32): float32 {
	return activeContext.targetCommands[index * COMMAND_FLOATS + field];
}
export function effectCount(): int32 { return activeContext.effectTotal; }
export function vertexCount(): int32 { return activeContext.vertexTotal; }

export function commandField(index: int32, field: int32): float32 {
	return activeContext.commands[index * COMMAND_FLOATS + field];
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
	activeContext.commands[base + CMD_VIEW] = (view & 0xFFFF) as float32;
	activeContext.commands[base + CMD_VIEW_HIGH] = (view >> 16) as float32;
}

export function effectField(index: int32, field: int32): float32 {
	return activeContext.effects[index * EFFECT_FLOATS + field];
}

export function effectMatrix(index: int32): Mat4 {
	return readColorMatrix(activeContext.effects, index * EFFECT_FLOATS);
}

export function vertexField(index: int32, field: int32): float32 {
	return activeContext.vertices[index * VERTEX_FLOATS + field];
}

// Grown in place and never shrunk, so a frame that peaked once does not reallocate again.
export function copyPainted(old: DrawContext2D, a: PaintIndex, b: PaintIndex): void {
	const ui: int32 = b.uiInstances - a.uiInstances;
	if (ui > 0) {
		const to: int32 = activeContext.uiInstanceTotal * REC_UI_FLOATS;
		const from: int32 = a.uiInstances * REC_UI_FLOATS;
		growTo(activeContext.uiInstances, to + ui * REC_UI_FLOATS);
		void2dCopyFloats(activeContext.uiInstances[to], old.uiInstances[from], ui * REC_UI_FLOATS);
		activeContext.uiInstanceTotal = activeContext.uiInstanceTotal + ui;
	}
	const sprites: int32 = b.spriteInstances - a.spriteInstances;
	if (sprites > 0) {
		const to: int32 = activeContext.spriteInstanceTotal * REC_SPRITE_FLOATS;
		const from: int32 = a.spriteInstances * REC_SPRITE_FLOATS;
		growTo(activeContext.spriteInstances, to + sprites * REC_SPRITE_FLOATS);
		void2dCopyFloats(activeContext.spriteInstances[to], old.spriteInstances[from], sprites * REC_SPRITE_FLOATS);
		activeContext.spriteInstanceTotal = activeContext.spriteInstanceTotal + sprites;
	}
	const vertices: int32 = b.vertices - a.vertices;
	if (vertices > 0) {
		const to: int32 = activeContext.vertexTotal * VERTEX_FLOATS;
		const from: int32 = a.vertices * VERTEX_FLOATS;
		growTo(activeContext.vertices, to + vertices * VERTEX_FLOATS);
		void2dCopyFloats(activeContext.vertices[to], old.vertices[from], vertices * VERTEX_FLOATS);
		activeContext.vertexTotal = activeContext.vertexTotal + vertices;
	}
}

export function limitWrites(end: PaintIndex): void {
	activeContext.limited = true;
	activeContext.limit = end;
	activeContext.spill = activeContext.paintEnd;
}

export function unlimitWrites(): void { activeContext.limited = false; }

function vertexSlot(): int32 {
	if (!activeContext.limited || activeContext.vertexTotal < activeContext.limit.vertices) { return activeContext.vertexTotal; }
	const at: int32 = activeContext.spill.vertices;
	activeContext.spill = { ...activeContext.spill, vertices: at + 1 };
	return at;
}

function uiSlot(): int32 {
	if (!activeContext.limited || activeContext.uiInstanceTotal < activeContext.limit.uiInstances) { return activeContext.uiInstanceTotal; }
	const at: int32 = activeContext.spill.uiInstances;
	activeContext.spill = { ...activeContext.spill, uiInstances: at + 1 };
	return at;
}

function spriteSlot(): int32 {
	if (!activeContext.limited || activeContext.spriteInstanceTotal < activeContext.limit.spriteInstances) {
		return activeContext.spriteInstanceTotal;
	}
	const at: int32 = activeContext.spill.spriteInstances;
	activeContext.spill = { ...activeContext.spill, spriteInstances: at + 1 };
	return at;
}

function effectSlot(): int32 {
	if (!activeContext.limited || activeContext.effectTotal < activeContext.limit.effects) { return activeContext.effectTotal; }
	const at: int32 = activeContext.spill.effects;
	activeContext.spill = { ...activeContext.spill, effects: at + 1 };
	return at;
}

function commandSlot(): int32 {
	if (!activeContext.limited || activeContext.commandTotal < activeContext.limit.commands) { return activeContext.commandTotal; }
	const at: int32 = activeContext.spill.commands;
	activeContext.spill = { ...activeContext.spill, commands: at + 1 };
	return at;
}

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
	const base: int32 = vertexSlot() * VERTEX_FLOATS;
	growTo(activeContext.vertices, base + VERTEX_FLOATS);
	activeContext.vertices[base] = x;
	activeContext.vertices[base + 1] = y;
	activeContext.vertices[base + 2] = u;
	activeContext.vertices[base + 3] = v;
	activeContext.vertices[base + 4] = r;
	activeContext.vertices[base + 5] = g;
	activeContext.vertices[base + 6] = b;
	activeContext.vertices[base + 7] = a;
	activeContext.vertexTotal = activeContext.vertexTotal + 1;
}

// Append one UI instance. The caller passes the six float4 lanes and three colours; the
// packing to UBYTE4N happens in `batcher.c` on the way to the GPU (instance.ms, "the RECORD
// layout").
export function pushUiInstance(inst: UiInstance, originX: float32, originY: float32): void {
	const base: int32 = uiSlot() * REC_UI_FLOATS;
	growTo(activeContext.uiInstances, base + REC_UI_FLOATS);
	const [u0, u1, u2, u3] = inst.uvRadii;
	const [bl, bt, br, bb] = inst.borders;
	const [p1, p2, p3] = inst.params;
	const [q0, q1, q2, q3] = inst.params1;
	activeContext.uiInstances[base + REC_UI_AFFINE] = inst.affine.a;
	activeContext.uiInstances[base + REC_UI_AFFINE + 1] = inst.affine.b;
	activeContext.uiInstances[base + REC_UI_AFFINE + 2] = inst.affine.c;
	activeContext.uiInstances[base + REC_UI_AFFINE + 3] = inst.affine.d;
	activeContext.uiInstances[base + REC_UI_ORIGIN_SIZE] = inst.x - originX;
	activeContext.uiInstances[base + REC_UI_ORIGIN_SIZE + 1] = inst.y - originY;
	activeContext.uiInstances[base + REC_UI_ORIGIN_SIZE + 2] = inst.w;
	activeContext.uiInstances[base + REC_UI_ORIGIN_SIZE + 3] = inst.h;
	activeContext.uiInstances[base + REC_UI_UV_RADII] = u0;
	activeContext.uiInstances[base + REC_UI_UV_RADII + 1] = u1;
	activeContext.uiInstances[base + REC_UI_UV_RADII + 2] = u2;
	activeContext.uiInstances[base + REC_UI_UV_RADII + 3] = u3;
	activeContext.uiInstances[base + REC_UI_BORDERS] = bl;
	activeContext.uiInstances[base + REC_UI_BORDERS + 1] = bt;
	activeContext.uiInstances[base + REC_UI_BORDERS + 2] = br;
	activeContext.uiInstances[base + REC_UI_BORDERS + 3] = bb;
	activeContext.uiInstances[base + REC_UI_PARAMS0] = (inst.mode as int32) as float32;
	activeContext.uiInstances[base + REC_UI_PARAMS0 + 1] = p1;
	activeContext.uiInstances[base + REC_UI_PARAMS0 + 2] = p2;
	activeContext.uiInstances[base + REC_UI_PARAMS0 + 3] = p3;
	activeContext.uiInstances[base + REC_UI_PARAMS1] = q0;
	activeContext.uiInstances[base + REC_UI_PARAMS1 + 1] = q1;
	activeContext.uiInstances[base + REC_UI_PARAMS1 + 2] = q2;
	activeContext.uiInstances[base + REC_UI_PARAMS1 + 3] = q3;
	activeContext.uiInstances[base + REC_UI_COLOR_FILL] = inst.fill.r;
	activeContext.uiInstances[base + REC_UI_COLOR_FILL + 1] = inst.fill.g;
	activeContext.uiInstances[base + REC_UI_COLOR_FILL + 2] = inst.fill.b;
	activeContext.uiInstances[base + REC_UI_COLOR_FILL + 3] = inst.fill.a;
	activeContext.uiInstances[base + REC_UI_COLOR_BORDER] = inst.border.r;
	activeContext.uiInstances[base + REC_UI_COLOR_BORDER + 1] = inst.border.g;
	activeContext.uiInstances[base + REC_UI_COLOR_BORDER + 2] = inst.border.b;
	activeContext.uiInstances[base + REC_UI_COLOR_BORDER + 3] = inst.border.a;
	activeContext.uiInstances[base + REC_UI_COLOR_EXTRA] = inst.extra.r;
	activeContext.uiInstances[base + REC_UI_COLOR_EXTRA + 1] = inst.extra.g;
	activeContext.uiInstances[base + REC_UI_COLOR_EXTRA + 2] = inst.extra.b;
	activeContext.uiInstances[base + REC_UI_COLOR_EXTRA + 3] = inst.extra.a;
	activeContext.uiInstanceTotal = activeContext.uiInstanceTotal + 1;
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
	const at: int32 = spriteSlot();
	growTo(activeContext.spriteInstances, (at + 1) * REC_SPRITE_FLOATS);
	putSpriteInstance(at, a, b, c, d, tx, ty, w, h, u0, v0, u1, v1, color);
	activeContext.spriteInstanceTotal = activeContext.spriteInstanceTotal + 1;
}

export function putSpriteInstance(
	index: int32,
	a: float32, b: float32, c: float32, d: float32,
	tx: float32, ty: float32, w: float32, h: float32,
	u0: float32, v0: float32, u1: float32, v1: float32,
	color: Color,
): void {
	const base: int32 = index * REC_SPRITE_FLOATS;
	activeContext.spriteInstances[base + REC_SPRITE_AFFINE] = a;
	activeContext.spriteInstances[base + REC_SPRITE_AFFINE + 1] = b;
	activeContext.spriteInstances[base + REC_SPRITE_AFFINE + 2] = c;
	activeContext.spriteInstances[base + REC_SPRITE_AFFINE + 3] = d;
	activeContext.spriteInstances[base + REC_SPRITE_ORIGIN_SIZE] = tx;
	activeContext.spriteInstances[base + REC_SPRITE_ORIGIN_SIZE + 1] = ty;
	activeContext.spriteInstances[base + REC_SPRITE_ORIGIN_SIZE + 2] = w;
	activeContext.spriteInstances[base + REC_SPRITE_ORIGIN_SIZE + 3] = h;
	activeContext.spriteInstances[base + REC_SPRITE_UV] = u0;
	activeContext.spriteInstances[base + REC_SPRITE_UV + 1] = v0;
	activeContext.spriteInstances[base + REC_SPRITE_UV + 2] = u1;
	activeContext.spriteInstances[base + REC_SPRITE_UV + 3] = v1;
	activeContext.spriteInstances[base + REC_SPRITE_COLOR] = color.r;
	activeContext.spriteInstances[base + REC_SPRITE_COLOR + 1] = color.g;
	activeContext.spriteInstances[base + REC_SPRITE_COLOR + 2] = color.b;
	activeContext.spriteInstances[base + REC_SPRITE_COLOR + 3] = color.a;
}

export function uiInstanceCount(): int32 { return activeContext.uiInstanceTotal; }
export function spriteInstanceCount(): int32 { return activeContext.spriteInstanceTotal; }

export function uiInstanceField(index: int32, field: int32): float32 {
	return activeContext.uiInstances[index * REC_UI_FLOATS + field];
}

export function spriteInstanceField(index: int32, field: int32): float32 {
	return activeContext.spriteInstances[index * REC_SPRITE_FLOATS + field];
}

// What the frame will upload for its instances, in GPU bytes rather than record floats.
export function instanceUploadBytes(): int32 {
	return activeContext.uiInstanceTotal * UI_STRIDE + activeContext.spriteInstanceTotal * SPRITE_STRIDE;
}

// How many instances carry each mode. The counter A4 asks for a negative control on: it
// moves when an emitter changes mode, and a sprite-only frame reads zero across the board.
export function uiModeCount(mode: int32): int32 {
	let n: int32 = 0;
	for (let i: int32 = 0; i < activeContext.uiInstanceTotal; i++) {
		const m: float32 = activeContext.uiInstances[i * REC_UI_FLOATS + REC_UI_PARAMS0 + UI_PARAM_MODE];
		if ((m as int32) == mode) { n = n + 1; }
	}
	return n;
}

// The colour pipeline as a row of its own. Returns the index a command should carry.

export function pushEffect(matrix: Mat4, add: Color, key: Color): int32 {
	const base: int32 = effectSlot() * EFFECT_FLOATS;
	activeContext.effectBase = base;
	growTo(activeContext.effects, base + EFFECT_FLOATS);
	for (let i: int32 = 0; i < EFFECT_FLOATS; i++) { activeContext.effects[base + i] = 0.0; }
	writeColorMatrix(matrix, activeContext.effects, base);
	activeContext.effects[base + 16] = add.r;
	activeContext.effects[base + 17] = add.g;
	activeContext.effects[base + 18] = add.b;
	activeContext.effects[base + 19] = add.a;
	activeContext.effects[base + 20] = key.r;
	activeContext.effects[base + 21] = key.g;
	activeContext.effects[base + 22] = key.b;
	activeContext.effects[base + 23] = key.a;
	activeContext.effectTotal = activeContext.effectTotal + 1;
	return activeContext.effectTotal - 1;
}

export function pushGradientEffect(
	matrix: Mat4,
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
	const base: int32 = activeContext.effectBase;
	activeContext.effects[base + EFFECT_GRADIENT_META] = kind as float32;
	activeContext.effects[base + EFFECT_GRADIENT_META + 1] = space as float32;
	activeContext.effects[base + EFFECT_GRADIENT_META + 2] = dither ? 1.0 : 0.0;
	activeContext.effects[base + EFFECT_GRADIENT_META + 3] = middle;
	activeContext.effects[base + EFFECT_GRADIENT_PARAMS] = p0;
	activeContext.effects[base + EFFECT_GRADIENT_PARAMS + 1] = p1;
	activeContext.effects[base + EFFECT_GRADIENT_PARAMS + 2] = p2;
	activeContext.effects[base + EFFECT_GRADIENT_PARAMS + 3] = p3;
	activeContext.effects[base + EFFECT_GRADIENT_COLOR0] = c0.r;
	activeContext.effects[base + EFFECT_GRADIENT_COLOR0 + 1] = c0.g;
	activeContext.effects[base + EFFECT_GRADIENT_COLOR0 + 2] = c0.b;
	activeContext.effects[base + EFFECT_GRADIENT_COLOR0 + 3] = c0.a;
	activeContext.effects[base + EFFECT_GRADIENT_COLOR1] = c1.r;
	activeContext.effects[base + EFFECT_GRADIENT_COLOR1 + 1] = c1.g;
	activeContext.effects[base + EFFECT_GRADIENT_COLOR1 + 2] = c1.b;
	activeContext.effects[base + EFFECT_GRADIENT_COLOR1 + 3] = c1.a;
	activeContext.effects[base + EFFECT_GRADIENT_COLOR2] = c2.r;
	activeContext.effects[base + EFFECT_GRADIENT_COLOR2 + 1] = c2.g;
	activeContext.effects[base + EFFECT_GRADIENT_COLOR2 + 2] = c2.b;
	activeContext.effects[base + EFFECT_GRADIENT_COLOR2 + 3] = c2.a;
	return index;
}

function startCommand(kind: CommandKind, reason: BreakReason): int32 {
	const base: int32 = commandSlot() * COMMAND_FLOATS;
	growTo(activeContext.commands, base + COMMAND_FLOATS);
	for (let i: int32 = 0; i < COMMAND_FLOATS; i++) { activeContext.commands[base + i] = 0.0; }
	activeContext.commands[base + CMD_KIND] = (kind as int32) as float32;
	activeContext.commands[base + CMD_EFFECT] = NO_EFFECT as float32;
	activeContext.commands[base + CMD_BREAK] = (reason as int32) as float32;
	activeContext.commands[base + CMD_CLIP_X] = activeContext.clip.x;
	activeContext.commands[base + CMD_CLIP_Y] = activeContext.clip.y;
	activeContext.commands[base + CMD_CLIP_W] = activeContext.clip.w;
	activeContext.commands[base + CMD_CLIP_H] = activeContext.clip.h;
	activeContext.commands[base + CMD_CLIP_U_X] = activeContext.clip.ux;
	activeContext.commands[base + CMD_CLIP_U_Y] = activeContext.clip.uy;
	activeContext.commands[base + CMD_CLIP_U_MIN] = activeContext.clip.uMin;
	activeContext.commands[base + CMD_CLIP_U_MAX] = activeContext.clip.uMax;
	activeContext.commands[base + CMD_CLIP_V_X] = activeContext.clip.vx;
	activeContext.commands[base + CMD_CLIP_V_Y] = activeContext.clip.vy;
	activeContext.commands[base + CMD_CLIP_V_MIN] = activeContext.clip.vMin;
	activeContext.commands[base + CMD_CLIP_V_MAX] = activeContext.clip.vMax;
	activeContext.commands[base + CMD_RT_MODE] = activeContext.renderTargetScale;
	activeContext.commands[base + CMD_SCOPE] = activeContext.scopeNow as float32;
	activeContext.commandTotal = activeContext.commandTotal + 1;
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
	activeContext.commands[base + CMD_VERTEX_OFFSET] = vertexOffset as float32;
	activeContext.commands[base + CMD_VERTEX_COUNT] = count as float32;
	writeView(base, view);
	activeContext.commands[base + CMD_BLEND] = (blend as int32) as float32;
	activeContext.commands[base + CMD_SAMPLER] = sampler as float32;
	activeContext.commands[base + CMD_EFFECT] = effectIndex as float32;
	wantPipeline(Program2D.Vertex, blend);
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
	activeContext.commands[base + CMD_PIPELINE] = (Pipeline.Ui as int32) as float32;
	wantPipeline(Program2D.Ui, blend);
	activeContext.commands[base + CMD_INSTANCE_OFFSET] = instanceOffset as float32;
	activeContext.commands[base + CMD_INSTANCE_COUNT] = count as float32;
	activeContext.commands[base + CMD_VERTEX_COUNT] = 0.0;
	writeView(base, view);
	activeContext.commands[base + CMD_BLEND] = (blend as int32) as float32;
	activeContext.commands[base + CMD_SAMPLER] = sampler as float32;
	activeContext.commands[base + CMD_EFFECT] = NO_EFFECT as float32;
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
	activeContext.commands[base + CMD_PIPELINE] = (Pipeline.Sprite as int32) as float32;
	wantPipeline(Program2D.Sprite, blend);
	activeContext.commands[base + CMD_INSTANCE_OFFSET] = instanceOffset as float32;
	activeContext.commands[base + CMD_INSTANCE_COUNT] = count as float32;
	activeContext.commands[base + CMD_VERTEX_COUNT] = 0.0;
	writeView(base, view);
	activeContext.commands[base + CMD_BLEND] = (blend as int32) as float32;
	activeContext.commands[base + CMD_SAMPLER] = sampler as float32;
	activeContext.commands[base + CMD_EFFECT] = NO_EFFECT as float32;
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
	if (activeContext.targetDepthNow >= MAX_TARGET_DEPTH) {
		// Recording into the parent is wrong, but it is visibly wrong rather than a stack
		// smash, and the flag makes the frame say so instead of the picture.
		activeContext.targetOverflowed = true;
		activeContext.unrecordedTargets = activeContext.unrecordedTargets + 1;
		return;
	}
	activeContext.targetMarks[activeContext.targetDepthNow] = activeContext.commandTotal;
	activeContext.targetScaleSaves[activeContext.targetDepthNow] = activeContext.renderTargetScale;
	activeContext.targetScopeSaves[activeContext.targetDepthNow] = activeContext.scopeNow;
	activeContext.targetClipSaves[activeContext.targetDepthNow] = activeContext.clip;
	activeContext.targetClipRecordedSaves[activeContext.targetDepthNow] = activeContext.clipRecorded;
	activeContext.targetDepthNow = activeContext.targetDepthNow + 1;
	const base: int32 = startCommand(CommandKind.TargetBegin, BreakReason.Barrier);
	writeView(base, rt);
	activeContext.commands[base + CMD_ARG0] = w;
	activeContext.commands[base + CMD_ARG1] = h;
	activeContext.commands[base + CMD_CLEAR_R] = clearR;
	activeContext.commands[base + CMD_CLEAR_G] = clearG;
	activeContext.commands[base + CMD_CLEAR_B] = clearB;
	activeContext.commands[base + CMD_CLEAR_A] = clearA;
	// Inside a target the clip starts empty and the offscreen pipeline set applies.
	activeContext.clipRecorded = false;
	activeContext.clip = NO_CLIP;
	activeContext.renderTargetScale = scale;
	activeContext.scopeNow = NO_SCOPE;
}

// in LIFO order the block is the tail of `commands`, so this is a copy of a few records and
// a count, and an inner target has already moved ahead of its consumer.
export function endTargetList(): boolean {
	if (activeContext.unrecordedTargets > 0) {
		activeContext.unrecordedTargets = activeContext.unrecordedTargets - 1;
		return false;
	}
	if (activeContext.targetDepthNow <= 0) { return false; }
	startCommand(CommandKind.TargetEnd, BreakReason.Barrier);
	activeContext.targetDepthNow = activeContext.targetDepthNow - 1;
	const mark: int32 = activeContext.targetMarks[activeContext.targetDepthNow];
	const from: int32 = mark * COMMAND_FLOATS;
	const upto: int32 = activeContext.commandTotal * COMMAND_FLOATS;
	let write: int32 = activeContext.targetCommandTotal * COMMAND_FLOATS;
	growTo(activeContext.targetCommands, write + (upto - from));
	for (let i: int32 = from; i < upto; i++) {
		activeContext.targetCommands[write] = activeContext.commands[i];
		write = write + 1;
	}
	activeContext.targetCommandTotal = activeContext.targetCommandTotal + (activeContext.commandTotal - mark);
	activeContext.commandTotal = mark;
	activeContext.clip = activeContext.targetClipSaves[activeContext.targetDepthNow];
	activeContext.clipRecorded = activeContext.targetClipRecordedSaves[activeContext.targetDepthNow];
	activeContext.renderTargetScale = activeContext.targetScaleSaves[activeContext.targetDepthNow];
	activeContext.scopeNow = activeContext.targetScopeSaves[activeContext.targetDepthNow];
	return true;
}

// The clip the replay should be under from here on. The rect is a coarse hardware scissor;
// the two projection intervals are the exact four edges of a rotated Mask.
export function recordClip(next: Clip): void {
	if (activeContext.clipRecorded && next == activeContext.clip) { return; }
	activeContext.clip = next;
	activeContext.clipRecorded = true;
	startCommand(CommandKind.Scissor, BreakReason.Clip);
}

export function recordBlur(view: uint32, dirX: float32, dirY: float32): void {
	const base: int32 = startCommand(CommandKind.Blur, BreakReason.Barrier);
	writeView(base, view);
	activeContext.commands[base + CMD_ARG0] = dirX;
	activeContext.commands[base + CMD_ARG1] = dirY;
	activeContext.commands[base + CMD_BLEND] = (BlendMode.None as int32) as float32;
	wantedPipelines[pipelineSlot(Program2D.Blur as int32, 1, BlendMode.None as int32)] = true;
}

const RUN_FIELDS: int32[] = [
	CMD_PIPELINE, CMD_VIEW, CMD_VIEW_HIGH, CMD_BLEND, CMD_SAMPLER, CMD_EFFECT, CMD_CLIP_X,
	CMD_CLIP_Y, CMD_CLIP_W, CMD_CLIP_H, CMD_RT_MODE, CMD_CLIP_U_X, CMD_CLIP_U_Y, CMD_CLIP_U_MIN,
	CMD_CLIP_U_MAX, CMD_CLIP_V_X, CMD_CLIP_V_Y, CMD_CLIP_V_MIN, CMD_CLIP_V_MAX, CMD_SCOPE,
];
const PLACE_FIELDS: int32[] = [
	CMD_CLIP_X, CMD_CLIP_Y, CMD_CLIP_W, CMD_CLIP_H, CMD_RT_MODE, CMD_CLIP_U_X, CMD_CLIP_U_Y,
	CMD_CLIP_U_MIN, CMD_CLIP_U_MAX, CMD_CLIP_V_X, CMD_CLIP_V_Y, CMD_CLIP_V_MIN, CMD_CLIP_V_MAX,
	CMD_SCOPE,
];


function isDraw(cmds: Span<float32>, base: int32): boolean {
	return (cmds[base + CMD_KIND] as int32) == (CommandKind.Draw as int32);
}

export function pipelineAt(cmds: Span<float32>, base: int32): Pipeline {
	return (cmds[base + CMD_PIPELINE] as int32) as Pipeline;
}

function offsetField(cmds: Span<float32>, base: int32): int32 {
	return pipelineAt(cmds, base) == Pipeline.Vertex ? CMD_VERTEX_OFFSET : CMD_INSTANCE_OFFSET;
}

function countField(cmds: Span<float32>, base: int32): int32 {
	return pipelineAt(cmds, base) == Pipeline.Vertex ? CMD_VERTEX_COUNT : CMD_INSTANCE_COUNT;
}

export function runOffset(cmds: Span<float32>, base: int32): int32 {
	return cmds[base + offsetField(cmds, base)] as int32;
}

export function runCount(cmds: Span<float32>, base: int32): int32 {
	return cmds[base + countField(cmds, base)] as int32;
}

function sameRun(a: Span<float32>, ab: int32, b: Span<float32>, bb: int32): boolean {
	if (!isDraw(a, ab) || !isDraw(b, bb)) { return false; }
	for (const f of RUN_FIELDS) {
		if (a[ab + f] != b[bb + f]) { return false; }
	}
	return true;
}

function breakBetween(prev: Span<float32>, pb: int32, next: Span<float32>, nb: int32): float32 {
	if (prev[pb + CMD_PIPELINE] != next[nb + CMD_PIPELINE]) {
		return (BreakReason.Pipeline as int32) as float32;
	}
	if (prev[pb + CMD_VIEW] != next[nb + CMD_VIEW] || prev[pb + CMD_VIEW_HIGH] != next[nb + CMD_VIEW_HIGH]) {
		return (BreakReason.View as int32) as float32;
	}
	if (prev[pb + CMD_BLEND] != next[nb + CMD_BLEND]) {
		return (BreakReason.Blend as int32) as float32;
	}
	if (prev[pb + CMD_SAMPLER] != next[nb + CMD_SAMPLER]) {
		return (BreakReason.Sampler as int32) as float32;
	}
	return next[nb + CMD_BREAK];
}

function floatsOf(pipeline: Pipeline): int32 {
	return match (pipeline) {
		Pipeline.Sprite => REC_SPRITE_FLOATS,
		Pipeline.Ui => REC_UI_FLOATS,
		Pipeline.Vertex => VERTEX_FLOATS,
	};
}

function streamTotal(pipeline: Pipeline): int32 {
	return match (pipeline) {
		Pipeline.Sprite => activeContext.spriteInstanceTotal,
		Pipeline.Ui => activeContext.uiInstanceTotal,
		Pipeline.Vertex => activeContext.vertexTotal,
	};
}

function sized(ref v: Vec<int32>, n: int32): void {
	while ((v.length as int32) < n) { v.push(0); }
}

export function lanesReorderable(c0: int32, c1: int32): boolean {
	if (c1 <= c0) { return false; }
	for (let c: int32 = c0; c < c1; c++) {
		const base: int32 = c * COMMAND_FLOATS;
		if (!isDraw(activeContext.commands, base)) { return false; }
		if ((activeContext.commands[base + CMD_EFFECT] as int32) != NO_EFFECT) { return false; }
		for (const f of PLACE_FIELDS) {
			if (activeContext.commands[base + f] != activeContext.commands[c0 * COMMAND_FLOATS + f]) { return false; }
		}
	}
	return true;
}

function orderLanes(c0: int32, c1: int32, marks: Span<int32>, reorder: boolean): void {
	while ((activeContext.laneOrder.length as int32) > 0) { activeContext.laneOrder.pop(); }
	if (!reorder) {
		for (let c: int32 = c0; c < c1; c++) { activeContext.laneOrder.push(c); }
		return;
	}
	const children: int32 = marks.length as int32;
	let lane: int32 = 0;
	let any: boolean = true;
	while (any) {
		any = false;
		for (let k: int32 = 0; k < children; k++) {
			const to: int32 = k + 1 < children ? marks[k + 1] : c1;
			if (marks[k] + lane < to) {
				activeContext.laneOrder.push(marks[k] + lane);
				any = true;
			}
		}
		lane = lane + 1;
	}
}

function permuteStream(pipeline: Pipeline, lo: int32, c0: int32): void {
	const width: int32 = floatsOf(pipeline);
	const total: int32 = streamTotal(pipeline);
	if (total <= lo) { return; }
	const span: int32 = (total - lo) * width;
	while ((activeContext.laneScratch.length as int32) < span) { activeContext.laneScratch.push(0.0 as float32); }
	let covered: int32 = 0;
	for (const src of activeContext.laneOrder) {
		if (pipelineAt(activeContext.commands, src * COMMAND_FLOATS) == pipeline) {
			covered = covered + activeContext.laneSourceCounts[src - c0];
		}
	}
	if (covered != total - lo) {
		console.log(
			`void2d: a lane region's ${pipeline.toString()} runs cover ${covered} of its ` +
			`${total - lo} records`,
		);
		unreachable;
	}
	match (pipeline) {
		Pipeline.Sprite => { void2dCopyFloats(activeContext.laneScratch[0], activeContext.spriteInstances[lo * width], span); },
		Pipeline.Ui => { void2dCopyFloats(activeContext.laneScratch[0], activeContext.uiInstances[lo * width], span); },
		Pipeline.Vertex => { void2dCopyFloats(activeContext.laneScratch[0], activeContext.vertices[lo * width], span); },
	}
	for (const src of activeContext.laneOrder) {
		if (pipelineAt(activeContext.commands, src * COMMAND_FLOATS) != pipeline) { continue; }
		const n: int32 = activeContext.laneSourceCounts[src - c0] * width;
		if (n == 0) { continue; }
		const from: int32 = (activeContext.laneSourceOffsets[src - c0] - lo) * width;
		const to: int32 = activeContext.laneOffsets[src - c0] * width;
		match (pipeline) {
			Pipeline.Sprite => { void2dCopyFloats(activeContext.spriteInstances[to], activeContext.laneScratch[from], n); },
			Pipeline.Ui => { void2dCopyFloats(activeContext.uiInstances[to], activeContext.laneScratch[from], n); },
			Pipeline.Vertex => { void2dCopyFloats(activeContext.vertices[to], activeContext.laneScratch[from], n); },
		}
	}
}

export function layLanes(
	c0: int32, c1: int32, marks: Span<int32>, reorder: boolean, pred: int32, lo: PaintIndex,
): void {
	const sources: int32 = c1 - c0;
	sized(activeContext.laneSourceOffsets, sources);
	sized(activeContext.laneSourceCounts, sources);
	sized(activeContext.laneOutputs, sources);
	sized(activeContext.laneOffsets, sources);
	while ((activeContext.laneOut.length as int32) < sources * COMMAND_FLOATS) { activeContext.laneOut.push(0.0 as float32); }
	while ((activeContext.laneBySprite.length as int32) > 0) { activeContext.laneBySprite.pop(); }
	while ((activeContext.laneByUi.length as int32) > 0) { activeContext.laneByUi.pop(); }
	while ((activeContext.laneByVertex.length as int32) > 0) { activeContext.laneByVertex.pop(); }
	for (let c: int32 = c0; c < c1; c++) {
		const base: int32 = c * COMMAND_FLOATS;
		const drawn: boolean = isDraw(activeContext.commands, base);
		activeContext.laneSourceOffsets[c - c0] = drawn ? runOffset(activeContext.commands, base) : 0;
		activeContext.laneSourceCounts[c - c0] = drawn ? runCount(activeContext.commands, base) : 0;
		if (drawn) {
			match (pipelineAt(activeContext.commands, base)) {
				Pipeline.Sprite => { activeContext.laneBySprite.push(c); },
				Pipeline.Ui => { activeContext.laneByUi.push(c); },
				Pipeline.Vertex => { activeContext.laneByVertex.push(c); },
			}
		}
	}
	orderLanes(c0, c1, marks, reorder);
	let cursorSprite: int32 = lo.spriteInstances;
	let cursorUi: int32 = lo.uiInstances;
	let cursorVertex: int32 = lo.vertices;
	let outputs: int32 = 0;
	let previous: int32 = -1;
	for (const src of activeContext.laneOrder) {
		const sb: int32 = src * COMMAND_FLOATS;
		const count: int32 = activeContext.laneSourceCounts[src - c0];
		const pipeline: Pipeline = pipelineAt(activeContext.commands, sb);
		let at: int32 = activeContext.laneSourceOffsets[src - c0];
		if (reorder) {
			at = match (pipeline) {
				Pipeline.Sprite => cursorSprite,
				Pipeline.Ui => cursorUi,
				Pipeline.Vertex => cursorVertex,
			};
			match (pipeline) {
				Pipeline.Sprite => { cursorSprite = cursorSprite + count; },
				Pipeline.Ui => { cursorUi = cursorUi + count; },
				Pipeline.Vertex => { cursorVertex = cursorVertex + count; },
			}
		}
		activeContext.laneOffsets[src - c0] = at;
		const last: int32 = (outputs - 1) * COMMAND_FLOATS;
		if (outputs > 0 && sameRun(activeContext.laneOut, last, activeContext.commands, sb)
			&& runOffset(activeContext.laneOut, last) + runCount(activeContext.laneOut, last) == at) {
			activeContext.laneOut[last + countField(activeContext.laneOut, last)] = (runCount(activeContext.laneOut, last) + count) as float32;
			activeContext.laneOutputs[src - c0] = c0 + outputs - 1;
		} else {
			const ob: int32 = outputs * COMMAND_FLOATS;
			for (let f: int32 = 0; f < COMMAND_FLOATS; f++) { activeContext.laneOut[ob + f] = activeContext.commands[sb + f]; }
			if (isDraw(activeContext.commands, sb)) { activeContext.laneOut[ob + offsetField(activeContext.laneOut, ob)] = at as float32; }
			if (outputs > 0 && previous != src - 1 && isDraw(activeContext.laneOut, last) && isDraw(activeContext.laneOut, ob)) {
				activeContext.laneOut[ob + CMD_BREAK] = breakBetween(activeContext.laneOut, last, activeContext.laneOut, ob);
			}
			activeContext.laneOutputs[src - c0] = c0 + outputs;
			outputs = outputs + 1;
		}
		previous = src;
	}
	if (reorder) {
		permuteStream(Pipeline.Sprite, lo.spriteInstances, c0);
		permuteStream(Pipeline.Ui, lo.uiInstances, c0);
		permuteStream(Pipeline.Vertex, lo.vertices, c0);
	}
	let skip: int32 = 0;
	if (pred >= 0 && outputs > 0) {
		const pb: int32 = pred * COMMAND_FLOATS;
		if (sameRun(activeContext.commands, pb, activeContext.laneOut, 0)
			&& runOffset(activeContext.commands, pb) + runCount(activeContext.commands, pb) == runOffset(activeContext.laneOut, 0)) {
			activeContext.commands[pb + countField(activeContext.commands, pb)] =
				(runCount(activeContext.commands, pb) + runCount(activeContext.laneOut, 0)) as float32;
			skip = 1;
			for (let k: int32 = 0; k < sources; k++) {
				activeContext.laneOutputs[k] = activeContext.laneOutputs[k] == c0 ? pred : activeContext.laneOutputs[k] - 1;
			}
		}
	}
	for (let o: int32 = skip; o < outputs; o++) {
		for (let f: int32 = 0; f < COMMAND_FLOATS; f++) {
			activeContext.commands[(c0 + o - skip) * COMMAND_FLOATS + f] = activeContext.laneOut[o * COMMAND_FLOATS + f];
		}
	}
	activeContext.commandTotal = c0 + outputs - skip;
}

function holding(ids: Span<int32>, at: int32, count: int32, c0: int32): int32 {
	let low: int32 = 0;
	let high: int32 = (ids.length as int32) - 1;
	let found: int32 = -1;
	while (low <= high) {
		const middle: int32 = (low + high) / 2;
		if (activeContext.laneSourceOffsets[ids[middle] - c0] <= at) {
			found = middle;
			low = middle + 1;
		} else {
			high = middle - 1;
		}
	}
	if (found < 0) { return -1; }
	const src: int32 = ids[found];
	const end: int32 = activeContext.laneSourceOffsets[src - c0] + activeContext.laneSourceCounts[src - c0];
	return at + count <= end ? src : -1;
}

export function laneSourceHolding(pipeline: Pipeline, at: int32, count: int32, c0: int32): int32 {
	return match (pipeline) {
		Pipeline.Sprite => holding(activeContext.laneBySprite, at, count, c0),
		Pipeline.Ui => holding(activeContext.laneByUi, at, count, c0),
		Pipeline.Vertex => holding(activeContext.laneByVertex, at, count, c0),
	};
}

export function laneOutputOf(command: int32, c0: int32): int32 { return activeContext.laneOutputs[command - c0]; }
export function laneOffsetOf(command: int32, c0: int32): int32 { return activeContext.laneOffsets[command - c0]; }
export function laneSourceOffsetOf(command: int32, c0: int32): int32 {
	return activeContext.laneSourceOffsets[command - c0];
}

// How many Draw commands are in the stream — the draw-call count, known before a single
// sg_* call is made, which is what lets T4 gate it with no GPU.
export function drawCommandCount(): int32 {
	let count: int32 = 0;
	for (let i: int32 = 0; i < activeContext.commandTotal; i++) {
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

test "a fresh activeContext is empty" {
	resetContext();
	assert commandCount() == 0;
	assert vertexCount() == 0;
	assert effectCount() == 0;
}

test "a view id past 2^24 reaches the replay whole, in the stream and in a target" {
	const view: uint32 = (291 << 16) | 5;
	const oneFloat: float32 = view as float32;
	assert view > 16777216;
	assert (oneFloat as uint32) != view;
	resetContext();
	recordDraw(BreakReason.View, 0, 6, view, BlendMode.Alpha, samplerIndex(true, false), NO_EFFECT);
	recordBlur(view, 1.0, 0.0);
	assert commandView(0) == view;
	assert commandView(1) == view;
	assert void2dCommandView(activeContext.commands[0]) == view;
	assert void2dCommandView(activeContext.commands[COMMAND_FLOATS]) == view;
	resetContext();
	beginTargetList(view, 64.0, 32.0, 1.0, 0.0, 0.0, 0.0, 0.0);
	recordDraw(BreakReason.First, 0, 6, view, BlendMode.Alpha, samplerIndex(true, false), NO_EFFECT);
	endTargetList();
	assert targetCommandView(0) == view;
	assert targetCommandView(1) == view;
}

test "a draw command carries its range and its reason" {
	resetContext();
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

test "a closed target block leaves the swapchain activeContext and lands in the target activeContext" {
	resetContext();
	recordDraw(BreakReason.First, 0, 6, 1, BlendMode.Alpha, samplerIndex(true, false), NO_EFFECT);
	beginTargetList(7, 64.0, 32.0, 1.0, 0.0, 0.0, 0.0, 0.0);
	recordDraw(BreakReason.First, 6, 6, 2, BlendMode.Alpha, samplerIndex(true, false), NO_EFFECT);
	endTargetList();
	recordDraw(BreakReason.View, 12, 6, 3, BlendMode.Alpha, samplerIndex(true, false), NO_EFFECT);
	assert commandCount() == 2;
	assert commandView(0) == 1;
	assert commandView(1) == 3;
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
	resetContext();
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
	resetContext();
	recordClip({ ...NO_CLIP, x: 5.0, y: 6.0, w: 7.0, h: 8.0 });
	beginTargetList(3, 16.0, 16.0, 1.0, 0.0, 0.0, 0.0, 0.0);
	// The outer Mask must not scissor the target: its coordinates are the target's own.
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
	resetContext();
	for (let i: int32 = 0; i < 9; i++) {
		beginTargetList(1, 4.0, 4.0, 1.0, 0.0, 0.0, 0.0, 0.0);
	}
	assert targetStackOverflowed();
	assert targetDepth() == 8;
	assert !endTargetList();
	assert targetDepth() == 8;
	for (let i: int32 = 0; i < 8; i++) { assert endTargetList(); }
	assert targetDepth() == 0;
}

test "recording the same clip twice records one scissor" {
	resetContext();
	recordClip({ ...NO_CLIP, w: 10.0, h: 10.0 });
	recordClip({ ...NO_CLIP, w: 10.0, h: 10.0 });
	assert commandCount() == 1;
	recordClip({ ...NO_CLIP, x: 1.0, w: 10.0, h: 10.0 });
	assert commandCount() == 2;
}

test "a draw inherits the clip that was recorded before it" {
	resetContext();
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

test "no color matrix records the identity" {
	resetContext();
	const none: Color = { r: 0.0, g: 0.0, b: 0.0, a: 0.0 };
	const index: int32 = pushEffect(NO_COLOR_MATRIX, none, none);
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
	resetContext();
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
	resetContext();
	recordClip({ ...NO_CLIP, w: 8.0, h: 8.0 });
	recordDraw(BreakReason.First, 0, 6, 1, BlendMode.Alpha, samplerIndex(true, false), NO_EFFECT);
	recordDraw(BreakReason.View, 6, 6, 2, BlendMode.Alpha, samplerIndex(true, false), NO_EFFECT);
	assert commandCount() == 3;
	assert drawCommandCount() == 2;
}

test "a command carries the pipeline set the replay must bind" {
	resetContext();
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
