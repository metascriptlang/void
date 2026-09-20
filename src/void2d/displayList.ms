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
// carries an index into it, or NO_EFFECT. That keeps a command at 24 floats.

import { Color, BlendMode } from "./types";
import {
	UI_STRIDE, SPRITE_STRIDE, UI_PARAM_MODE,
	REC_UI_AFFINE, REC_UI_ORIGIN_SIZE, REC_UI_UV_RADII, REC_UI_BORDERS, REC_UI_PARAMS0,
	REC_UI_PARAMS1, REC_UI_COLOR_FILL, REC_UI_COLOR_BORDER, REC_UI_COLOR_EXTRA,
	REC_UI_FLOATS,
	REC_SPRITE_AFFINE, REC_SPRITE_ORIGIN_SIZE, REC_SPRITE_UV, REC_SPRITE_COLOR,
	REC_SPRITE_FLOATS,
} from "./instance";

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
}

export const COMMAND_FLOATS: int32 = 24;
export const EFFECT_FLOATS: int32 = 24;
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
// Which pipeline set the replay must bind: the swapchain one, or the offscreen one (single
// sample, no depth). It is per command because it is state the replay needs, and the record
// is the only thing that reaches the replay.
export const CMD_RT_MODE: int32 = 14;
// TargetBegin only: what the pass clears its target to. A command record is 24 floats and
// only 15 were named, so this is four fields of its own rather than a reuse of the clip
// fields, which a TargetBegin does not carry but every other command does.
export const CMD_CLEAR_R: int32 = 15;
export const CMD_CLEAR_G: int32 = 16;
export const CMD_CLEAR_B: int32 = 17;
export const CMD_CLEAR_A: int32 = 18;

// Exported because `draw.ms` hands `commands[0]` to the replay as a `Borrow<float32>`, and
// there is no way to return a `Span` from a function on this compiler. Read them; only this
// module writes them.
//
// Each starts with one record's worth of zeros so that `arr[0]` is always in bounds: a
// frame that records no effect at all would otherwise index an empty array to take its
// address. Counts come from the `*Total` variables, never from `.length`, so the seed is
// invisible to every reader.
export const commands: Vec<float32> = new Array(COMMAND_FLOATS);
export const effects: Vec<float32> = new Array(EFFECT_FLOATS);
export const vertices: Vec<float32> = new Array(VERTEX_FLOATS);

// P2's two instance streams, seeded like the others so index 0 is always in bounds.
export const uiInstances: Vec<float32> = new Array(REC_UI_FLOATS);
export const spriteInstances: Vec<float32> = new Array(REC_SPRITE_FLOATS);

// Every closed render-target pass, in the order the replay must run them: a target's block
// is appended here when it closes, so an inner target lands ahead of the outer one that
// consumes it. The swapchain list in `commands` only ever holds the quad that samples the
// finished target.
export const targetCommands: Vec<float32> = new Array(COMMAND_FLOATS);

let commandTotal: int32 = 0;
let targetCommandTotal: int32 = 0;
let effectTotal: int32 = 0;
let vertexTotal: int32 = 0;
let uiInstanceTotal: int32 = 0;
let spriteInstanceTotal: int32 = 0;

// Where each open target's block starts inside `commands`. Targets close in the order they
// opened's reverse, so the open block is always the tail of `commands` and moving it out is
// a copy plus a count, never a hole. 8 is deeper than any filter tree h2d composes; going
// past it records into the parent instead of corrupting the stack, and says so.
const MAX_TARGET_DEPTH: int32 = 8;
const targetMarks: Vec<int32> = new Array(MAX_TARGET_DEPTH);
const targetClipSaves: Vec<float32> = new Array(MAX_TARGET_DEPTH * 5);
let targetDepthNow: int32 = 0;
let targetOverflowed: boolean = false;

// The clip the replay is under. A scissor is a command, not a call, so the emitter tracks
// what it last recorded and only records a change.
let clipX: float32 = 0.0;
let clipY: float32 = 0.0;
let clipW: float32 = 0.0;
let clipH: float32 = 0.0;
let clipRecorded: boolean = false;
let renderTargetMode: boolean = false;

export function resetList(): void {
	commandTotal = 0;
	targetCommandTotal = 0;
	effectTotal = 0;
	vertexTotal = 0;
	uiInstanceTotal = 0;
	spriteInstanceTotal = 0;
	clipRecorded = false;
	// The rect too, not only the flag. Leaving it meant the first command of a new frame
	// carried the last clip of the previous one; `popClip` records (0,0,0,0) at depth zero so
	// a balanced frame always ended clear and production never noticed, but an unbalanced one
	// would have scissored to a stale rect - and T1 found it at once, because a snapshot then
	// depended on which test had run before it in the same process.
	clipX = 0.0;
	clipY = 0.0;
	clipW = 0.0;
	clipH = 0.0;
	renderTargetMode = false;
	targetDepthNow = 0;
	targetOverflowed = false;
}

// Which pipeline set every command recorded from here on will ask the replay to bind.
export function setRenderTargetMode(on: boolean): void { renderTargetMode = on; }
export function renderTargetModeOn(): boolean { return renderTargetMode; }

export function commandCount(): int32 { return commandTotal; }
export function targetCommandCount(): int32 { return targetCommandTotal; }
export function targetDepth(): int32 { return targetDepthNow; }
export function targetStackOverflowed(): boolean { return targetOverflowed; }

export function targetCommandField(index: int32, field: int32): float32 {
	return targetCommands[index * COMMAND_FLOATS + field];
}
export function effectCount(): int32 { return effectTotal; }
export function vertexCount(): int32 { return vertexTotal; }

export function commandField(index: int32, field: int32): float32 {
	return commands[index * COMMAND_FLOATS + field];
}

export function effectField(index: int32, field: int32): float32 {
	return effects[index * EFFECT_FLOATS + field];
}

export function vertexField(index: int32, field: int32): float32 {
	return vertices[index * VERTEX_FLOATS + field];
}

// Grown in place and never shrunk, so a frame that peaked once does not reallocate again.
// Inlined at each of the three sites rather than shared: a `Vec<T>` parameter is a read-only
// copy on this compiler, so a helper taking one could not push through it.

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
	const base: int32 = vertexTotal * VERTEX_FLOATS;
	while ((vertices.length as int32) < base + VERTEX_FLOATS) { vertices.push(0.0 as float32); }
	vertices[base] = x;
	vertices[base + 1] = y;
	vertices[base + 2] = u;
	vertices[base + 3] = v;
	vertices[base + 4] = r;
	vertices[base + 5] = g;
	vertices[base + 6] = b;
	vertices[base + 7] = a;
	vertexTotal = vertexTotal + 1;
}

// Append one UI instance. The caller passes the six float4 lanes and three colours; the
// packing to UBYTE4N happens in `batcher.c` on the way to the GPU (instance.ms, "the RECORD
// layout").
export function pushUiInstance(
	a: float32, b: float32, c: float32, d: float32,
	tx: float32, ty: float32, w: float32, h: float32,
	uvr0: float32, uvr1: float32, uvr2: float32, uvr3: float32,
	borderL: float32, borderT: float32, borderR: float32, borderB: float32,
	mode: float32, p1: float32, p2: float32, p3: float32,
	q0: float32, q1: float32, q2: float32, q3: float32,
	fill: Color, border: Color, extra: Color,
): void {
	const base: int32 = uiInstanceTotal * REC_UI_FLOATS;
	while ((uiInstances.length as int32) < base + REC_UI_FLOATS) {
		uiInstances.push(0.0 as float32);
	}
	uiInstances[base + REC_UI_AFFINE] = a;
	uiInstances[base + REC_UI_AFFINE + 1] = b;
	uiInstances[base + REC_UI_AFFINE + 2] = c;
	uiInstances[base + REC_UI_AFFINE + 3] = d;
	uiInstances[base + REC_UI_ORIGIN_SIZE] = tx;
	uiInstances[base + REC_UI_ORIGIN_SIZE + 1] = ty;
	uiInstances[base + REC_UI_ORIGIN_SIZE + 2] = w;
	uiInstances[base + REC_UI_ORIGIN_SIZE + 3] = h;
	uiInstances[base + REC_UI_UV_RADII] = uvr0;
	uiInstances[base + REC_UI_UV_RADII + 1] = uvr1;
	uiInstances[base + REC_UI_UV_RADII + 2] = uvr2;
	uiInstances[base + REC_UI_UV_RADII + 3] = uvr3;
	uiInstances[base + REC_UI_BORDERS] = borderL;
	uiInstances[base + REC_UI_BORDERS + 1] = borderT;
	uiInstances[base + REC_UI_BORDERS + 2] = borderR;
	uiInstances[base + REC_UI_BORDERS + 3] = borderB;
	uiInstances[base + REC_UI_PARAMS0] = mode;
	uiInstances[base + REC_UI_PARAMS0 + 1] = p1;
	uiInstances[base + REC_UI_PARAMS0 + 2] = p2;
	uiInstances[base + REC_UI_PARAMS0 + 3] = p3;
	uiInstances[base + REC_UI_PARAMS1] = q0;
	uiInstances[base + REC_UI_PARAMS1 + 1] = q1;
	uiInstances[base + REC_UI_PARAMS1 + 2] = q2;
	uiInstances[base + REC_UI_PARAMS1 + 3] = q3;
	uiInstances[base + REC_UI_COLOR_FILL] = fill.r;
	uiInstances[base + REC_UI_COLOR_FILL + 1] = fill.g;
	uiInstances[base + REC_UI_COLOR_FILL + 2] = fill.b;
	uiInstances[base + REC_UI_COLOR_FILL + 3] = fill.a;
	uiInstances[base + REC_UI_COLOR_BORDER] = border.r;
	uiInstances[base + REC_UI_COLOR_BORDER + 1] = border.g;
	uiInstances[base + REC_UI_COLOR_BORDER + 2] = border.b;
	uiInstances[base + REC_UI_COLOR_BORDER + 3] = border.a;
	uiInstances[base + REC_UI_COLOR_EXTRA] = extra.r;
	uiInstances[base + REC_UI_COLOR_EXTRA + 1] = extra.g;
	uiInstances[base + REC_UI_COLOR_EXTRA + 2] = extra.b;
	uiInstances[base + REC_UI_COLOR_EXTRA + 3] = extra.a;
	uiInstanceTotal = uiInstanceTotal + 1;
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
	const base: int32 = spriteInstanceTotal * REC_SPRITE_FLOATS;
	while ((spriteInstances.length as int32) < base + REC_SPRITE_FLOATS) {
		spriteInstances.push(0.0 as float32);
	}
	spriteInstances[base + REC_SPRITE_AFFINE] = a;
	spriteInstances[base + REC_SPRITE_AFFINE + 1] = b;
	spriteInstances[base + REC_SPRITE_AFFINE + 2] = c;
	spriteInstances[base + REC_SPRITE_AFFINE + 3] = d;
	spriteInstances[base + REC_SPRITE_ORIGIN_SIZE] = tx;
	spriteInstances[base + REC_SPRITE_ORIGIN_SIZE + 1] = ty;
	spriteInstances[base + REC_SPRITE_ORIGIN_SIZE + 2] = w;
	spriteInstances[base + REC_SPRITE_ORIGIN_SIZE + 3] = h;
	spriteInstances[base + REC_SPRITE_UV] = u0;
	spriteInstances[base + REC_SPRITE_UV + 1] = v0;
	spriteInstances[base + REC_SPRITE_UV + 2] = u1;
	spriteInstances[base + REC_SPRITE_UV + 3] = v1;
	spriteInstances[base + REC_SPRITE_COLOR] = color.r;
	spriteInstances[base + REC_SPRITE_COLOR + 1] = color.g;
	spriteInstances[base + REC_SPRITE_COLOR + 2] = color.b;
	spriteInstances[base + REC_SPRITE_COLOR + 3] = color.a;
	spriteInstanceTotal = spriteInstanceTotal + 1;
}

export function uiInstanceCount(): int32 { return uiInstanceTotal; }
export function spriteInstanceCount(): int32 { return spriteInstanceTotal; }

export function uiInstanceField(index: int32, field: int32): float32 {
	return uiInstances[index * REC_UI_FLOATS + field];
}

export function spriteInstanceField(index: int32, field: int32): float32 {
	return spriteInstances[index * REC_SPRITE_FLOATS + field];
}

// What the frame will upload for its instances, in GPU bytes rather than record floats.
export function instanceUploadBytes(): int32 {
	return uiInstanceTotal * UI_STRIDE + spriteInstanceTotal * SPRITE_STRIDE;
}

// How many instances carry each mode. The counter A4 asks for a negative control on: it
// moves when an emitter changes mode, and a sprite-only frame reads zero across the board.
export function uiModeCount(mode: int32): int32 {
	let n: int32 = 0;
	for (let i: int32 = 0; i < uiInstanceTotal; i++) {
		const m: float32 = uiInstances[i * REC_UI_FLOATS + REC_UI_PARAMS0 + UI_PARAM_MODE];
		if ((m as int32) == mode) { n = n + 1; }
	}
	return n;
}

// The colour pipeline as a row of its own. Returns the index a command should carry.
export function pushEffect(matrix: float32[], add: Color, key: Color): int32 {
	const base: int32 = effectTotal * EFFECT_FLOATS;
	while ((effects.length as int32) < base + EFFECT_FLOATS) { effects.push(0.0 as float32); }
	const hasMatrix: boolean = (matrix.length as int32) >= 16;
	for (let i: int32 = 0; i < 16; i++) {
		effects[base + i] = hasMatrix ? matrix[i] : (i % 5 == 0 ? 1.0 : 0.0);
	}
	effects[base + 16] = add.r;
	effects[base + 17] = add.g;
	effects[base + 18] = add.b;
	effects[base + 19] = add.a;
	effects[base + 20] = key.r;
	effects[base + 21] = key.g;
	effects[base + 22] = key.b;
	effects[base + 23] = key.a;
	effectTotal = effectTotal + 1;
	return effectTotal - 1;
}

function startCommand(kind: CommandKind, reason: BreakReason): int32 {
	const base: int32 = commandTotal * COMMAND_FLOATS;
	while ((commands.length as int32) < base + COMMAND_FLOATS) { commands.push(0.0 as float32); }
	for (let i: int32 = 0; i < COMMAND_FLOATS; i++) { commands[base + i] = 0.0; }
	commands[base + CMD_KIND] = (kind as int32) as float32;
	commands[base + CMD_BREAK] = (reason as int32) as float32;
	commands[base + CMD_CLIP_X] = clipX;
	commands[base + CMD_CLIP_Y] = clipY;
	commands[base + CMD_CLIP_W] = clipW;
	commands[base + CMD_CLIP_H] = clipH;
	commands[base + CMD_RT_MODE] = renderTargetMode ? 1.0 : 0.0;
	commandTotal = commandTotal + 1;
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
	commands[base + CMD_VERTEX_OFFSET] = vertexOffset as float32;
	commands[base + CMD_VERTEX_COUNT] = count as float32;
	commands[base + CMD_VIEW] = view as float32;
	commands[base + CMD_BLEND] = (blend as int32) as float32;
	commands[base + CMD_SAMPLER] = sampler as float32;
	commands[base + CMD_EFFECT] = effectIndex as float32;
}

// Open a render-target pass. Everything recorded until the matching `endTargetList` belongs
// to it. h2d saves and clears the clip per target (`h2d/Object.hx:896-956`): a Mask outside
// the filter must not scissor the target, whose coordinates are its own.
export function beginTargetList(
	rt: uint32,
	w: float32,
	h: float32,
	clearR: float32,
	clearG: float32,
	clearB: float32,
	clearA: float32,
): void {
	if (targetDepthNow >= MAX_TARGET_DEPTH) {
		// Recording into the parent is wrong, but it is visibly wrong rather than a stack
		// smash, and the flag makes the frame say so instead of the picture.
		targetOverflowed = true;
		return;
	}
	targetMarks[targetDepthNow] = commandTotal;
	const cs: int32 = targetDepthNow * 5;
	targetClipSaves[cs] = clipX;
	targetClipSaves[cs + 1] = clipY;
	targetClipSaves[cs + 2] = clipW;
	targetClipSaves[cs + 3] = clipH;
	targetClipSaves[cs + 4] = clipRecorded ? 1.0 : 0.0;
	targetDepthNow = targetDepthNow + 1;
	const base: int32 = startCommand(CommandKind.TargetBegin, BreakReason.Barrier);
	commands[base + CMD_VIEW] = rt as float32;
	commands[base + CMD_ARG0] = w;
	commands[base + CMD_ARG1] = h;
	commands[base + CMD_CLEAR_R] = clearR;
	commands[base + CMD_CLEAR_G] = clearG;
	commands[base + CMD_CLEAR_B] = clearB;
	commands[base + CMD_CLEAR_A] = clearA;
	// Inside a target the clip starts empty and the offscreen pipeline set applies.
	clipRecorded = false;
	clipX = 0.0;
	clipY = 0.0;
	clipW = 0.0;
	clipH = 0.0;
	renderTargetMode = true;
}

// Close the open target and move its block out of the swapchain list. Because targets close
// in LIFO order the block is the tail of `commands`, so this is a copy of a few records and
// a count, and an inner target has already moved ahead of its consumer.
export function endTargetList(): void {
	if (targetDepthNow <= 0) { return; }
	startCommand(CommandKind.TargetEnd, BreakReason.Barrier);
	targetDepthNow = targetDepthNow - 1;
	const mark: int32 = targetMarks[targetDepthNow];
	const from: int32 = mark * COMMAND_FLOATS;
	const upto: int32 = commandTotal * COMMAND_FLOATS;
	let write: int32 = targetCommandTotal * COMMAND_FLOATS;
	while ((targetCommands.length as int32) < write + (upto - from)) {
		targetCommands.push(0.0 as float32);
	}
	for (let i: int32 = from; i < upto; i++) {
		targetCommands[write] = commands[i];
		write = write + 1;
	}
	targetCommandTotal = targetCommandTotal + (commandTotal - mark);
	commandTotal = mark;
	const cs: int32 = targetDepthNow * 5;
	clipX = targetClipSaves[cs];
	clipY = targetClipSaves[cs + 1];
	clipW = targetClipSaves[cs + 2];
	clipH = targetClipSaves[cs + 3];
	clipRecorded = targetClipSaves[cs + 4] != 0.0;
	renderTargetMode = targetDepthNow > 0;
}

// The clip the replay should be under from here on. Recording the same rect twice is a
// no-op, so a Mask that does not change the zone costs nothing in the stream.
export function recordClip(x: float32, y: float32, w: float32, h: float32): void {
	if (clipRecorded && x == clipX && y == clipY && w == clipW && h == clipH) { return; }
	clipX = x;
	clipY = y;
	clipW = w;
	clipH = h;
	clipRecorded = true;
	startCommand(CommandKind.Scissor, BreakReason.Clip);
}

export function recordBlur(view: uint32, dirX: float32, dirY: float32): void {
	const base: int32 = startCommand(CommandKind.Blur, BreakReason.Barrier);
	commands[base + CMD_VIEW] = view as float32;
	commands[base + CMD_ARG0] = dirX;
	commands[base + CMD_ARG1] = dirY;
}

// How many Draw commands are in the stream — the draw-call count, known before a single
// sg_* call is made, which is what lets T4 gate it with no GPU.
export function drawCommandCount(): int32 {
	let count: int32 = 0;
	for (let i: int32 = 0; i < commandTotal; i++) {
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

test "a draw command carries its range and its reason" {
	resetList();
	recordDraw(BreakReason.View, 12, 6, 3, BlendMode.Add, samplerIndex(false, true), NO_EFFECT);
	assert commandCount() == 1;
	assert (commandField(0, CMD_KIND) as int32) == (CommandKind.Draw as int32);
	assert (commandField(0, CMD_BREAK) as int32) == (BreakReason.View as int32);
	assert (commandField(0, CMD_VERTEX_OFFSET) as int32) == 12;
	assert (commandField(0, CMD_VERTEX_COUNT) as int32) == 6;
	assert (commandField(0, CMD_VIEW) as int32) == 3;
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
	beginTargetList(7, 64.0, 32.0, 0.0, 0.0, 0.0, 0.0);
	recordDraw(BreakReason.First, 6, 6, 2, BlendMode.Alpha, samplerIndex(true, false), NO_EFFECT);
	endTargetList();
	recordDraw(BreakReason.View, 12, 6, 3, BlendMode.Alpha, samplerIndex(true, false), NO_EFFECT);
	// The swapchain list kept only the sibling before and the consumer after it.
	assert commandCount() == 2;
	assert (commandField(0, CMD_VIEW) as int32) == 1;
	assert (commandField(1, CMD_VIEW) as int32) == 3;
	// The target's own pass went to the other list, wrapped in its markers.
	assert targetCommandCount() == 3;
	assert (targetCommandField(0, CMD_KIND) as int32) == (CommandKind.TargetBegin as int32);
	assert (targetCommandField(0, CMD_VIEW) as int32) == 7;
	assert targetCommandField(0, CMD_ARG0) == 64.0;
	assert targetCommandField(0, CMD_ARG1) == 32.0;
	assert (targetCommandField(1, CMD_VIEW) as int32) == 2;
	assert (targetCommandField(2, CMD_KIND) as int32) == (CommandKind.TargetEnd as int32);
	assert targetDepth() == 0;
}

test "a nested target is replayed before the target that consumes it" {
	resetList();
	beginTargetList(10, 8.0, 8.0, 0.0, 0.0, 0.0, 0.0);
	recordDraw(BreakReason.First, 0, 6, 100, BlendMode.Alpha, samplerIndex(true, false), NO_EFFECT);
	beginTargetList(11, 4.0, 4.0, 0.0, 0.0, 0.0, 0.0);
	recordDraw(BreakReason.First, 6, 6, 200, BlendMode.Alpha, samplerIndex(true, false), NO_EFFECT);
	endTargetList();
	recordDraw(BreakReason.View, 12, 6, 300, BlendMode.Alpha, samplerIndex(true, false), NO_EFFECT);
	endTargetList();
	assert commandCount() == 0;
	// inner: begin(11), draw 200, end — then outer: begin(10), draw 100, draw 300, end.
	assert (targetCommandField(0, CMD_KIND) as int32) == (CommandKind.TargetBegin as int32);
	assert (targetCommandField(0, CMD_VIEW) as int32) == 11;
	assert (targetCommandField(1, CMD_VIEW) as int32) == 200;
	assert (targetCommandField(2, CMD_KIND) as int32) == (CommandKind.TargetEnd as int32);
	assert (targetCommandField(3, CMD_KIND) as int32) == (CommandKind.TargetBegin as int32);
	assert (targetCommandField(3, CMD_VIEW) as int32) == 10;
	assert (targetCommandField(4, CMD_VIEW) as int32) == 100;
	assert (targetCommandField(5, CMD_VIEW) as int32) == 300;
	assert (targetCommandField(6, CMD_KIND) as int32) == (CommandKind.TargetEnd as int32);
	assert targetCommandCount() == 7;
}

test "a target starts with no clip and gives the outer clip back when it closes" {
	resetList();
	recordClip(5.0, 6.0, 7.0, 8.0);
	beginTargetList(3, 16.0, 16.0, 0.0, 0.0, 0.0, 0.0);
	// The outer Mask must not scissor the target: its coordinates are the target's own.
	// Recording the same rect the outer list holds therefore has to emit a real scissor.
	recordClip(5.0, 6.0, 7.0, 8.0);
	endTargetList();
	// And back outside, the outer clip is current again, so re-recording it is a no-op.
	recordClip(5.0, 6.0, 7.0, 8.0);
	assert commandCount() == 1;
	assert targetCommandCount() == 3;
	assert (targetCommandField(1, CMD_KIND) as int32) == (CommandKind.Scissor as int32);
}

test "the target stack refuses to overflow and says so" {
	resetList();
	for (let i: int32 = 0; i < 9; i++) { beginTargetList(1, 4.0, 4.0, 0.0, 0.0, 0.0, 0.0); }
	assert targetStackOverflowed();
	assert targetDepth() == 8;
	for (let i: int32 = 0; i < 8; i++) { endTargetList(); }
	assert targetDepth() == 0;
}

test "recording the same clip twice records one scissor" {
	resetList();
	recordClip(0.0, 0.0, 10.0, 10.0);
	recordClip(0.0, 0.0, 10.0, 10.0);
	assert commandCount() == 1;
	recordClip(1.0, 0.0, 10.0, 10.0);
	assert commandCount() == 2;
}

test "a draw inherits the clip that was recorded before it" {
	resetList();
	recordClip(4.0, 5.0, 6.0, 7.0);
	recordDraw(BreakReason.First, 0, 6, 1, BlendMode.Alpha, samplerIndex(true, false), NO_EFFECT);
	assert commandField(1, CMD_CLIP_X) == 4.0;
	assert commandField(1, CMD_CLIP_Y) == 5.0;
	assert commandField(1, CMD_CLIP_W) == 6.0;
	assert commandField(1, CMD_CLIP_H) == 7.0;
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
	recordClip(0.0, 0.0, 8.0, 8.0);
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
}
