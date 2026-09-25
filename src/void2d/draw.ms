// Void 2D emitter — turns the tree walk into a display list and nothing else.
//
// Before P1 this file issued sokol calls as the tree was walked: every state change was a
// flush, every Label and Graphics owned an sg_buffer, and a Mask applied a scissor on the
// spot. Now it appends to the two streams in displayList.ms and `end2d()` hands the whole
// frame to `void2dReplay` once. The only sokol calls left here are the ones that are not
// drawing — creating a render target, opening a pass — and those are the host's, not the
// walk's.
//
// A batch ends when the state the replay would have to change ends: a different view, blend,
// sampler or colour pipeline. The reason is recorded with the command, so a T1 snapshot says
// `break: view` rather than leaving a count to be explained.

import {
	void2dSetup, void2dWhiteView, void2dSetDpiScale, void2dFrameBegin,
	void2dGlyphPageView, void2dGlyphUploadCount, void2dGlyphUploadBytes, void2dSetTextGamma,
	void2dReplay, void2dReplayTargets, void2dLayoutCheck,
	void2dDrawCallCount, void2dUploadCount, void2dUploadBytes, void2dBuffersAlive,
	void2dVertexBufferBytes, void2dDroppedFrames, void2dGrowthTarget,
	void2dAtlasImagesAlive, void2dFrameEnd, void2dFrameSerial, void2dFailPendingTargets,
	void2dScissorMin, void2dScissorMax,
	void2dUiInstanceStride, void2dSpriteInstanceStride, void2dInstanceLayoutCheck,
	void2dPackChannel,
} from "./batcher.h";
import { void2dGlyphPageCount } from "./glyph.h";
import { beginGlyphFrame } from "./labelText";
import { GlyphPageHandle } from "./glyphAtlas";
import { gammaRatios, DEFAULT_TEXT_GAMMA, DEFAULT_TEXT_CONTRAST } from "./textGamma";
import {
	UI_STRIDE, UI_AFFINE, UI_ORIGIN_SIZE, UI_UV_RADII, UI_BORDERS, UI_PARAMS0, UI_PARAMS1,
	UI_COLOR_FILL, UI_COLOR_BORDER, UI_COLOR_EXTRA, InstanceMode,
	SPRITE_STRIDE, SPRITE_AFFINE, SPRITE_ORIGIN_SIZE, SPRITE_UV, SPRITE_COLOR,
} from "./instance";
import {
	CommandKind, BreakReason,
	COMMAND_FLOATS, EFFECT_FLOATS, VERTEX_FLOATS, NO_EFFECT,
	CMD_KIND, CMD_BREAK, CMD_VERTEX_OFFSET, CMD_VERTEX_COUNT, CMD_VIEW, CMD_BLEND, CMD_SAMPLER,
	CMD_EFFECT, CMD_CLIP_X, CMD_CLIP_U_X, CMD_ARG0, CMD_RT_MODE, CMD_CLEAR_R,
	EFFECT_GRADIENT_META, EFFECT_GRADIENT_PARAMS, EFFECT_GRADIENT_COLOR0,
	EFFECT_GRADIENT_COLOR1, EFFECT_GRADIENT_COLOR2,
	SAMPLER_COUNT, samplerIndex,
	commands, effects, vertices, targetCommands, spriteInstances, spriteInstanceCount,
	uiInstances, uiInstanceCount, pushUiInstance, recordUiDraw,
	resetList, commandCount, targetCommandCount, effectCount, vertexCount, drawCommandCount,
	targetDepth, targetStackOverflowed, renderTargetScaleNow, beginTargetList, endTargetList,
	pushVertex as pushVertexRaw, pushEffect, pushGradientEffect, recordDraw, recordClip, recordBlur,
	Pipeline, NO_CLIP,
	pushSpriteInstance, recordSpriteDraw,
} from "./displayList";
import { Vec2, Color, Tile, Transform2D, BlendMode, Smooth, rgba } from "./types";
import { makeRenderTarget, destroyRenderTarget, renderTargetView } from "../sokol/gpu";

export function allocRenderTarget(w: int32, h: int32): uint32 { return makeRenderTarget(w, h); }
export function freeRenderTarget(rt: uint32): void { destroyRenderTarget(rt); }
export function rtViewId(rt: uint32): uint32 { return renderTargetView(rt); }

// h2d puts a filtered subtree into its target through a filter matrix rather than re-syncing
// the subtree against a second world matrix (`h2d/Object.hx:896-956`). The matrix is a pure
// translation here, so it is one subtraction at the point a vertex is recorded - and because
// it is applied to the *stream* rather than to the tree, the subtree keeps the single sync it
// already had and `localToGlobal` keeps answering in screen coordinates.
let originX: float32 = 0.0;
let originY: float32 = 0.0;

function pushVertex(
	x: float32, y: float32, u: float32, v: float32,
	r: float32, g: float32, b: float32, a: float32,
): void {
	pushVertexRaw(x - originX, y - originY, u, v, r, g, b, a);
}

// The batch the emitter is accumulating: a run of vertices that share every piece of state
// the replay would otherwise have to change between them.
let runStart: int32 = 0;
let runOpen: boolean = false;
// Which stream the open run is accumulating into. It is batch state like the view or the
// blend: the two pipelines read different streams and bind different programs, so a change
// here can only ever end the run.
let curPipeline: Pipeline = Pipeline.Vertex;
let runReason: BreakReason = BreakReason.First;
let curView: uint32 = 0;
let curBlend: BlendMode = BlendMode.Alpha;
// The sampler this run wants, packed by `samplerIndex`. Its default is the scene default
// with clamp, which is what a node that sets neither `smooth` nor `tileWrap` asks for.
let curSampler: int32 = 0;
// h2d resolves a node's null `smooth` against the scene. h2d's own default is nearest
// (`h2d/RenderContext.hx:52`), which HEAPS.md "Do not copy from h2d" rejects: text and
// scaled UI are the common case here, so the default is linear.
let sceneSmooth: boolean = true;
let curEffect: int32 = NO_EFFECT;
// False when the frame's geometry blew the cap: the swapchain list must not draw either.
let frameLive: boolean = true;
let fbW: float32 = 0.0;
let fbH: float32 = 0.0;
let frameDpi: float32 = 1.0;
let targetsFlushed: boolean = false;

// The emitter state each open target has to give back. Same depth as displayList.ms's stack;
// past it `beginTarget` still brackets the list correctly, it just stops restoring, and the
// list's own overflow flag is what reports it.
const TARGET_SAVE_SLOTS: int32 = 8;
const savedView: Vec<float32> = new Array(TARGET_SAVE_SLOTS * 4);
const savedSize: Vec<float32> = new Array(TARGET_SAVE_SLOTS * 4);

export function drawCallCount(): int32 { return void2dDrawCallCount(); }
export function uploadCount(): int32 { return void2dUploadCount(); }
export function uploadBytes(): int32 { return void2dUploadBytes(); }
export function buffersAlive(): int32 { return void2dBuffersAlive(); }
export function vertexBufferBytes(): int32 { return void2dVertexBufferBytes(); }
export function droppedFrames(): int32 { return void2dDroppedFrames(); }
export function currentRenderScale(): float32 {
	const targetScale: float32 = renderTargetScaleNow();
	return targetScale != 0.0 ? targetScale : frameDpi;
}

export function scissorMinDevice(edge: float32, scale: float32): int32 {
	return void2dScissorMin(edge, scale);
}
export function scissorMaxDevice(edge: float32, scale: float32): int32 {
	return void2dScissorMax(edge, scale);
}

export function atlasImagesAlive(): int32 { return void2dAtlasImagesAlive(); }
export function glyphUploadCount(): int32 { return void2dGlyphUploadCount(); }
export function glyphUploadBytes(): int32 { return void2dGlyphUploadBytes(); }
export function glyphPageView(handle: GlyphPageHandle): uint32 {
	return void2dGlyphPageView(handle as int32);
}
export function glyphPageCount(): int32 { return void2dGlyphPageCount(); }

export function setTextGamma(gamma: float32, contrast: float32): void {
	const r = gammaRatios(gamma);
	void2dSetTextGamma(r.r0, r.r1, r.r2, r.r3, contrast);
}

// `setup2d` registers this as the bridge's commit hook, so `commit()` already runs it and no
// frame has to call it. Exported so a test can close a frame it never committed.
export function frameEnd(): void { void2dFrameEnd(); }

// The vertex-buffer growth policy, as pure arithmetic. Re-exported rather than imported from
// `batcher.h` directly, because a header imported from a second directory compiles its `.c`
// a second time and the link fails on duplicate symbols - `src/void2d/` owns batcher.h.
export function growthTarget(have: int32, need: int32): int32 {
	return void2dGrowthTarget(have, need);
}

// Counted from the stream rather than from the GPU, so T1 can read them with no GPU at all.
export function recordedDrawCount(): int32 { return drawCommandCount(); }
export function recordedCommandCount(): int32 { return commandCount(); }
export function recordedVertexCount(): int32 { return vertexCount(); }

// h2d.Drawable colour pipeline as batch state. An identity matrix with a zero add and no key
// is `NO_EFFECT`, so effect-free nodes — almost all of them — share one batch and cost no
// row in the effect table.
const curMat: Vec<float32> = [
	1.0, 0.0, 0.0, 0.0,
	0.0, 1.0, 0.0, 0.0,
	0.0, 0.0, 1.0, 0.0,
	0.0, 0.0, 0.0, 1.0,
];
let curAdd: Color = rgba(0.0, 0.0, 0.0, 0.0);
let curKey: Color = rgba(0.0, 0.0, 0.0, 0.0);
let curHasEffect: boolean = false;

// The hardware scissor carries the intersection AABB. A rotated Mask additionally carries
// one pair of projection intervals: four exact edges, interpolated by the vertex shader.
struct MaskClip {
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

const NO_MASK_CLIP: MaskClip = {
	x0: 0.0, y0: 0.0, x1: 0.0, y1: 0.0,
	ux: 0.0, uy: 0.0, uMin: 0.0, uMax: 0.0,
	vx: 0.0, vy: 0.0, vMin: 0.0, vMax: 0.0,
};

const clipStack: Vec<MaskClip> = new Array(16);
let clipDepth: int32 = 0;

function setIdentityMat(): void {
	for (let i: int32 = 0; i < 16; i++) { curMat[i] = i % 5 == 0 ? 1.0 : 0.0; }
}

function effectMatrixSame(mat: float32[], hasMat: boolean): boolean {
	if (hasMat) {
		for (let i: int32 = 0; i < 16; i++) { if (mat[i] != curMat[i]) { return false; } }
		return true;
	}
	for (let i: int32 = 0; i < 16; i++) {
		if (curMat[i] != (i % 5 == 0 ? 1.0 : 0.0)) { return false; }
	}
	return true;
}

// Close the open run as one Draw command. Called when the state changes, when a clip moves,
// and at the end of the bracket — never in the middle of a primitive.
function closeRun(): void {
	if (!runOpen) { return; }
	match (curPipeline) {
		Pipeline.Sprite => {
			const instances: int32 = spriteInstanceCount() - runStart;
			if (instances > 0) {
				recordSpriteDraw(runReason, runStart, instances, curView, curBlend, curSampler);
			}
		},
		Pipeline.Ui => {
			const instances: int32 = uiInstanceCount() - runStart;
			if (instances > 0) {
				recordUiDraw(runReason, runStart, instances, curView, curBlend, curSampler);
			}
		},
		Pipeline.Vertex => {
			const count: int32 = vertexCount() - runStart;
			if (count > 0) {
				recordDraw(runReason, runStart, count, curView, curBlend, curSampler, curEffect);
			}
		},
	}
	runOpen = false;
}

// Close the open run so the streams are final. Naming the step separates *recording is
// finished* from *the GPU is told about it*: `flushTargets` and `end2d` both start with it,
// and T1 uses it on its own, because a display list is assertable with no GPU at all and the
// replay is the one part that is not.
export function finishRecording(): void {
	closeRun();
}

function openRun(reason: BreakReason): void {
	runStart = match (curPipeline) {
		Pipeline.Sprite => spriteInstanceCount(),
		Pipeline.Ui => uiInstanceCount(),
		Pipeline.Vertex => vertexCount(),
	};
	runReason = reason;
	runOpen = true;
}

function useRun(pipeline: Pipeline, view: uint32, blend: BlendMode): void {
	if (runOpen && view == curView && blend == curBlend && curPipeline == pipeline) { return; }
	const reason: BreakReason = !runOpen ? BreakReason.First
		: (curPipeline != pipeline ? BreakReason.Pipeline
		: (view != curView ? BreakReason.View : BreakReason.Blend));
	closeRun();
	curView = view;
	curBlend = blend;
	curPipeline = pipeline;
	openRun(reason);
}

export function setup2d(): void {
	void2dSetup();
	setTextGamma(DEFAULT_TEXT_GAMMA, DEFAULT_TEXT_CONTRAST);
	// The emitter and the replay are two hand-written readers of one byte layout, so they
	// are made to agree out loud rather than by inspection.
	if (void2dLayoutCheck(
		COMMAND_FLOATS, EFFECT_FLOATS, VERTEX_FLOATS,
		CMD_KIND, CMD_BREAK, CMD_VERTEX_OFFSET, CMD_VERTEX_COUNT,
		CMD_VIEW, CMD_BLEND, CMD_SAMPLER, CMD_EFFECT, SAMPLER_COUNT, TARGET_SAVE_SLOTS, CMD_CLEAR_R,
		CMD_CLIP_X, CMD_CLIP_U_X, CMD_ARG0, CMD_RT_MODE,
		CommandKind.Draw as int32, CommandKind.Scissor as int32, CommandKind.Blur as int32,
		CommandKind.TargetBegin as int32, CommandKind.TargetEnd as int32,
	) == 0) {
		console.log("void2d: the display-list layout in displayList.ms and batcher.c disagree");
	}
	if (void2dInstanceLayoutCheck(
		UI_STRIDE, UI_AFFINE, UI_ORIGIN_SIZE, UI_UV_RADII, UI_BORDERS, UI_PARAMS0, UI_PARAMS1,
		UI_COLOR_FILL, UI_COLOR_BORDER, UI_COLOR_EXTRA,
		SPRITE_STRIDE, SPRITE_AFFINE, SPRITE_ORIGIN_SIZE, SPRITE_UV, SPRITE_COLOR,
	) == 0) {
		console.log("void2d: the instance layout in instance.ms and batcher.c disagree");
	}
}

// The strides sokol is handed, from sizeof. Re-exported rather than reached through
// `batcher.h` from a second directory, which would compile `batcher.c` twice.
export function uiInstanceStride(): int32 { return void2dUiInstanceStride(); }

// The colour pack as C does it on the way into the GPU buffer. Re-exported so T0 can hold it
// against `instance.ms`'s `packChannel` rather than letting guardrail 9 rest on two copies
// that look alike - src/void2d/ owns batcher.h, so a test cannot import it directly.
export function packChannelC(value: float32): int32 { return void2dPackChannel(value); }
export function spriteInstanceStride(): int32 { return void2dSpriteInstanceStride(); }


// h2d has no DPI concept; void2d needs one because snapping and the pixel-exact text regime
// are stated per device pixel. The logical size is a float — the `as int32` truncation that
// put every glyph off-grid at DPI 1.25 and 1.5 is gone (VOID2D.md "Known defects").
export function begin2d(w: float32, h: float32, dpi: float32): void {
	void2dSetDpiScale(dpi);
	void2dFrameBegin();
	beginGlyphFrame(void2dFrameSerial());
	frameDpi = dpi;
	fbW = w;
	fbH = h;
	targetsFlushed = false;
	resetList();
	frameLive = true;
	originX = 0.0;
	originY = 0.0;
	runOpen = false;
	runStart = 0;
	curView = void2dWhiteView();
	curBlend = BlendMode.Alpha;
	curSampler = samplerIndex(sceneSmooth, false);
	curEffect = NO_EFFECT;
	setIdentityMat();
	curAdd = rgba(0.0, 0.0, 0.0, 0.0);
	curKey = rgba(0.0, 0.0, 0.0, 0.0);
	curHasEffect = false;
	clipDepth = 0;
}

// Upload the frame and run every render-target pass. Called with NO pass open, before the
// swapchain pass is begun: that ordering is the phase's whole point, because a target pass
// opened inside the swapchain pass is what sokol asserts on.
export function flushTargets(): void {
	finishRecording();
	if (targetStackOverflowed()) {
		console.log("void2d: filter nesting deeper than 8 - the innermost targets were recorded into their parent");
	}
	frameLive = void2dReplayTargets(
		targetCommands[0], targetCommandCount(),
		effects[0], effectCount(),
		vertices[0], vertexCount(),
		spriteInstances[0], spriteInstanceCount(),
		uiInstances[0], uiInstanceCount(),
	) != 0;
	targetsFlushed = true;
}

// Replay the swapchain list into the pass the caller already has open. Together with
// `flushTargets` this is the only place the GPU is touched, and both happen after the walk.
export function end2d(): void {
	finishRecording();
	// A caller that opened render targets and forgot `flushTargets()` used to get silence: the
	// hoisted blocks sat in `targetCommands` and the next `resetList()` threw them away, so a
	// filtered subtree simply did not appear and nothing said why.
	if (targetCommandCount() > 0 && !targetsFlushed) {
		void2dFailPendingTargets();
		return;
	}
	if (!frameLive || commandCount() == 0) { return; }
	void2dReplay(
		commands[0], commandCount(),
		effects[0], effectCount(),
		fbW, fbH,
	);
}

function absf(v: float32): float32 { return v < 0.0 ? -v : v; }

function minFour(a: float32, b: float32, c: float32, d: float32): float32 {
	let out: float32 = a < b ? a : b;
	if (c < out) { out = c; }
	if (d < out) { out = d; }
	return out;
}

function maxFour(a: float32, b: float32, c: float32, d: float32): float32 {
	let out: float32 = a > b ? a : b;
	if (c > out) { out = c; }
	if (d > out) { out = d; }
	return out;
}

function applyClip(d: int32): void {
	const c: MaskClip = clipStack[d];
	let ix: float32 = c.x0;
	let iy: float32 = c.y0;
	let iw: float32 = c.x1 - c.x0;
	let ih: float32 = c.y1 - c.y0;
	if (ix < 0.0) { iw = iw + ix; ix = 0.0; }
	if (iy < 0.0) { ih = ih + iy; iy = 0.0; }
	if (iw < 0.0) { iw = 0.0; }
	if (ih < 0.0) { ih = 0.0; }
	const uShift: float32 = originX * c.ux + originY * c.uy;
	const vShift: float32 = originX * c.vx + originY * c.vy;
	closeRun();
	recordClip({
		x: ix - originX, y: iy - originY, w: iw, h: ih,
		ux: c.ux, uy: c.uy, uMin: c.uMin - uShift, uMax: c.uMax - uShift,
		vx: c.vx, vy: c.vy, vMin: c.vMin - vShift, vMax: c.vMax - vShift,
	});
	openRun(BreakReason.Clip);
}

export function clipIntersectsQuad(tl: Vec2, tr: Vec2, br: Vec2, bl: Vec2): boolean {
	if (clipDepth <= 0) { return true; }
	const c: MaskClip = clipStack[clipDepth - 1];
	if (maxFour(tl.x, tr.x, br.x, bl.x) <= c.x0
		|| minFour(tl.x, tr.x, br.x, bl.x) >= c.x1
		|| maxFour(tl.y, tr.y, br.y, bl.y) <= c.y0
		|| minFour(tl.y, tr.y, br.y, bl.y) >= c.y1) { return false; }
	if (c.uMax <= c.uMin) { return true; }
	const u0: float32 = tl.x * c.ux + tl.y * c.uy;
	const u1: float32 = tr.x * c.ux + tr.y * c.uy;
	const u2: float32 = br.x * c.ux + br.y * c.uy;
	const u3: float32 = bl.x * c.ux + bl.y * c.uy;
	if (maxFour(u0, u1, u2, u3) <= c.uMin
		|| minFour(u0, u1, u2, u3) >= c.uMax) { return false; }
	const v0: float32 = tl.x * c.vx + tl.y * c.vy;
	const v1: float32 = tr.x * c.vx + tr.y * c.vy;
	const v2: float32 = br.x * c.vx + br.y * c.vy;
	const v3: float32 = bl.x * c.vx + bl.y * c.vy;
	return maxFour(v0, v1, v2, v3) > c.vMin
		&& minFour(v0, v1, v2, v3) < c.vMax;
}

export function pushClip(tl: Vec2, tr: Vec2, br: Vec2, bl: Vec2): boolean {
	let x0: float32 = minFour(tl.x, tr.x, br.x, bl.x);
	let y0: float32 = minFour(tl.y, tr.y, br.y, bl.y);
	let x1: float32 = maxFour(tl.x, tr.x, br.x, bl.x);
	let y1: float32 = maxFour(tl.y, tr.y, br.y, bl.y);
	const parent: int32 = clipDepth - 1;
	let next: MaskClip = NO_MASK_CLIP;
	if (parent >= 0) {
		next = clipStack[parent];
		if (next.x0 > x0) { x0 = next.x0; }
		if (next.y0 > y0) { y0 = next.y0; }
		if (next.x1 < x1) { x1 = next.x1; }
		if (next.y1 < y1) { y1 = next.y1; }
	}
	while (clipDepth >= clipStack.length as int32) { clipStack.push(NO_MASK_CLIP); }
	const d: int32 = clipDepth;

	const ex: float32 = tr.x - tl.x;
	const ey: float32 = tr.y - tl.y;
	const fx: float32 = bl.x - tl.x;
	const fy: float32 = bl.y - tl.y;
	const exLen: float32 = Math.sqrt((ex * ex + ey * ey) as float64) as float32;
	const fLen: float32 = Math.sqrt((fx * fx + fy * fy) as float64) as float32;
	let supported: boolean = true;
	const axisAligned: boolean = (absf(ey) < 0.0001 && absf(fx) < 0.0001)
		|| (absf(ex) < 0.0001 && absf(fy) < 0.0001);
	if (!axisAligned && exLen > 0.0 && fLen > 0.0) {
		const ux: float32 = ex / exLen;
		const uy: float32 = ey / exLen;
		const vx: float32 = fx / fLen;
		const vy: float32 = fy / fLen;
		if (next.uMax > next.uMin) {
			const same: boolean =
				(absf(next.ux * ux + next.uy * uy) > 0.9999
					&& absf(next.vx * vx + next.vy * vy) > 0.9999)
				|| (absf(next.ux * vx + next.uy * vy) > 0.9999
					&& absf(next.vx * ux + next.vy * uy) > 0.9999);
			if (!same) {
				console.log("void2d: nested rotated Masks use different edge axes");
				x1 = x0;
				y1 = y0;
				supported = false;
			} else {
				const pu0: float32 = tl.x * next.ux + tl.y * next.uy;
				const pu1: float32 = tr.x * next.ux + tr.y * next.uy;
				const pu2: float32 = br.x * next.ux + br.y * next.uy;
				const pu3: float32 = bl.x * next.ux + bl.y * next.uy;
				const pv0: float32 = tl.x * next.vx + tl.y * next.vy;
				const pv1: float32 = tr.x * next.vx + tr.y * next.vy;
				const pv2: float32 = br.x * next.vx + br.y * next.vy;
				const pv3: float32 = bl.x * next.vx + bl.y * next.vy;
				const uMin: float32 = minFour(pu0, pu1, pu2, pu3);
				const uMax: float32 = maxFour(pu0, pu1, pu2, pu3);
				const vMin: float32 = minFour(pv0, pv1, pv2, pv3);
				const vMax: float32 = maxFour(pv0, pv1, pv2, pv3);
				if (uMin > next.uMin) { next.uMin = uMin; }
				if (uMax < next.uMax) { next.uMax = uMax; }
				if (vMin > next.vMin) { next.vMin = vMin; }
				if (vMax < next.vMax) { next.vMax = vMax; }
			}
		} else {
			const u0: float32 = tl.x * ux + tl.y * uy;
			const u1: float32 = tr.x * ux + tr.y * uy;
			const u2: float32 = br.x * ux + br.y * uy;
			const u3: float32 = bl.x * ux + bl.y * uy;
			const v0: float32 = tl.x * vx + tl.y * vy;
			const v1: float32 = tr.x * vx + tr.y * vy;
			const v2: float32 = br.x * vx + br.y * vy;
			const v3: float32 = bl.x * vx + bl.y * vy;
			next = {
				...next,
				ux: ux, uy: uy, vx: vx, vy: vy,
				uMin: minFour(u0, u1, u2, u3), uMax: maxFour(u0, u1, u2, u3),
				vMin: minFour(v0, v1, v2, v3), vMax: maxFour(v0, v1, v2, v3),
			};
		}
	}
	clipStack[d] = { ...next, x0: x0, y0: y0, x1: x1, y1: y1 };
	clipDepth = clipDepth + 1;
	applyClip(d);
	return supported;
}

export function popClip(): void {
	if (clipDepth > 0) { clipDepth = clipDepth - 1; }
	if (clipDepth > 0) {
		applyClip(clipDepth - 1);
	} else {
		closeRun();
		recordClip(NO_CLIP);
		openRun(BreakReason.Clip);
	}
}

// h2d.Drawable colour pipeline → batch state. mat = 16-float column-major colorMatrix
// (empty/<16 = identity); add = rgba added after; key = chroma colorKey (a>0 enables,
// matching texels go transparent).
function currentGradientKind(): int32 {
	if (curEffect == NO_EFFECT) { return 0; }
	return effects[curEffect * EFFECT_FLOATS + EFFECT_GRADIENT_META] as int32;
}
export function setEffect(mat: float32[], add: Color, key: Color): void {
	const hasMat: boolean = (mat.length as int32) >= 16;
	const wantsEffect: boolean = hasMat || add.r != 0.0 || add.g != 0.0 || add.b != 0.0 || add.a != 0.0 || key.a > 0.0;
	if (!wantsEffect && !curHasEffect) { return; }
	if (wantsEffect && curHasEffect && currentGradientKind() == 0
		&& add == curAdd && key == curKey
		&& effectMatrixSame(mat, hasMat)) { return; }
	closeRun();
	if (hasMat) {
		for (let i: int32 = 0; i < 16; i++) { curMat[i] = mat[i]; }
	} else {
		setIdentityMat();
	}
	curAdd = add;
	curKey = key;
	curHasEffect = wantsEffect;
	curEffect = wantsEffect ? pushEffect(mat, add, key) : NO_EFFECT;
	openRun(BreakReason.Effect);
}
export function setGradientEffect(
	mat: float32[],
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
): void {
	const hasMat: boolean = (mat.length as int32) >= 16;
	const base: int32 = curEffect * EFFECT_FLOATS;
	if (curHasEffect && curEffect != NO_EFFECT
		&& (effects[base + EFFECT_GRADIENT_META] as int32) == kind
		&& (effects[base + EFFECT_GRADIENT_META + 1] as int32) == space
		&& effects[base + EFFECT_GRADIENT_META + 2] == (dither ? 1.0 : 0.0)
		&& effects[base + EFFECT_GRADIENT_META + 3] == middle
		&& effects[base + EFFECT_GRADIENT_PARAMS] == p0
		&& effects[base + EFFECT_GRADIENT_PARAMS + 1] == p1
		&& effects[base + EFFECT_GRADIENT_PARAMS + 2] == p2
		&& effects[base + EFFECT_GRADIENT_PARAMS + 3] == p3
		&& effects[base + EFFECT_GRADIENT_COLOR0] == c0.r
		&& effects[base + EFFECT_GRADIENT_COLOR0 + 1] == c0.g
		&& effects[base + EFFECT_GRADIENT_COLOR0 + 2] == c0.b
		&& effects[base + EFFECT_GRADIENT_COLOR0 + 3] == c0.a
		&& effects[base + EFFECT_GRADIENT_COLOR1] == c1.r
		&& effects[base + EFFECT_GRADIENT_COLOR1 + 1] == c1.g
		&& effects[base + EFFECT_GRADIENT_COLOR1 + 2] == c1.b
		&& effects[base + EFFECT_GRADIENT_COLOR1 + 3] == c1.a
		&& effects[base + EFFECT_GRADIENT_COLOR2] == c2.r
		&& effects[base + EFFECT_GRADIENT_COLOR2 + 1] == c2.g
		&& effects[base + EFFECT_GRADIENT_COLOR2 + 2] == c2.b
		&& effects[base + EFFECT_GRADIENT_COLOR2 + 3] == c2.a
		&& add == curAdd && key == curKey
		&& effectMatrixSame(mat, hasMat)) { return; }
	closeRun();
	if (hasMat) {
		for (let i: int32 = 0; i < 16; i++) { curMat[i] = mat[i]; }
	} else {
		setIdentityMat();
	}
	curAdd = add;
	curKey = key;
	curHasEffect = true;
	curEffect = pushGradientEffect(mat, add, key, kind, space, dither, middle,
		p0, p1, p2, p3, c0, c1, c2);
	openRun(BreakReason.Effect);
}

// The scene's default for nodes whose `smooth` is `Smooth.Inherit`. Set once per bracket by
// `Scene.present`, before the walk; changing it mid-walk would make two nodes with identical
// state sample differently, which is exactly the bug a tri-state invites.
export function setSceneSmooth(s: boolean): void {
	sceneSmooth = s;
}

export function sceneSmoothDefault(): boolean {
	return sceneSmooth;
}

// h2d.Drawable.smooth and h2d.Drawable.tileWrap, resolved: linear vs nearest sampling, and
// repeat vs clamp at the tile's edge. Batch state — a change closes the run, because a
// sampler is bound per draw.
export function setSampler(smooth: Smooth, tileWrap: boolean): void {
	const on: boolean = smooth == Smooth.Inherit ? sceneSmooth : smooth == Smooth.On;
	const want: int32 = samplerIndex(on, tileWrap);
	if (want == curSampler) { return; }
	closeRun();
	curSampler = want;
	openRun(BreakReason.Sampler);
}

function quad(view: uint32, blend: BlendMode, x: float32, y: float32, w: float32, h: float32, c: Color, u0: float32, v0: float32, u1: float32, v1: float32): void {
	useRun(Pipeline.Vertex, view, blend);
	const x1: float32 = x + w;
	const y1: float32 = y + h;
	pushVertex(x, y, u0, v0, c.r, c.g, c.b, c.a);
	pushVertex(x1, y, u1, v0, c.r, c.g, c.b, c.a);
	pushVertex(x1, y1, u1, v1, c.r, c.g, c.b, c.a);
	pushVertex(x, y, u0, v0, c.r, c.g, c.b, c.a);
	pushVertex(x1, y1, u1, v1, c.r, c.g, c.b, c.a);
	pushVertex(x, y1, u0, v1, c.r, c.g, c.b, c.a);
}

export function drawRect(pos: Vec2, size: Vec2, color: Color, blend: BlendMode): void {
	quad(void2dWhiteView(), blend, pos.x, pos.y, size.x, size.y, color, 0.0, 0.0, 1.0, 1.0);
}

export function drawImage(t: Tile, pos: Vec2, size: Vec2, tint: Color, blend: BlendMode): void {
	quad(t.view, blend, pos.x, pos.y, size.x, size.y, tint, t.u0, t.v0, t.u1, t.v1);
}

// Which pipeline set the following draws need: the offscreen one (single sample, no depth)
// or the swapchain one. Recorded per command rather than flipped here, because the replay
// runs after the recording has finished — the demo caught this the moment the display list
// landed, with every render-target draw replaying under the swapchain set.
// Open a render-target bracket. Nothing touches the GPU here: the commands that follow are
// moved into the hoisted target list when `endTarget` closes them, and the pass itself is
// opened by the replay, outside the swapchain pass. The emitter's run state is saved because
// the target has its own viewport and its own idea of what is already bound.
export function beginTarget(
	rt: uint32,
	w: float32,
	h: float32,
	scale: float32,
	ox: float32,
	oy: float32,
	clear: Color,
): void {
	targetsFlushed = false;
	if (targetDepth() >= TARGET_SAVE_SLOTS) {
		beginTargetList(rt, w, h, scale, clear.r, clear.g, clear.b, clear.a);
		return;
	}
	closeRun();
	const slot: int32 = targetDepth() * 4;
	savedView[slot] = curView as float32;
	savedView[slot + 1] = (curBlend as int32) as float32;
	savedView[slot + 2] = curSampler as float32;
	savedView[slot + 3] = curEffect as float32;
	savedSize[targetDepth() * 4] = fbW;
	savedSize[targetDepth() * 4 + 1] = fbH;
	savedSize[targetDepth() * 4 + 2] = originX;
	savedSize[targetDepth() * 4 + 3] = originY;
	beginTargetList(rt, w, h, scale, clear.r, clear.g, clear.b, clear.a);
	fbW = w;
	fbH = h;
	originX = ox;
	originY = oy;
	// A fresh pass has nothing bound, so the first draw in it must not be told it can skip a
	// bind it never made.
	curView = void2dWhiteView();
	curBlend = BlendMode.Alpha;
	curSampler = samplerIndex(sceneSmooth, false);
	curEffect = NO_EFFECT;
	openRun(BreakReason.Barrier);
}

export function endTarget(): void {
	closeRun();
	const depth: int32 = targetDepth();
	endTargetList();
	if (depth > TARGET_SAVE_SLOTS || depth <= 0) { return; }
	const slot: int32 = (depth - 1) * 4;
	curView = savedView[slot] as uint32;
	curBlend = (savedView[slot + 1] as int32) as BlendMode;
	curSampler = savedView[slot + 2] as int32;
	curEffect = savedView[slot + 3] as int32;
	fbW = savedSize[(depth - 1) * 4];
	fbH = savedSize[(depth - 1) * 4 + 1];
	originX = savedSize[(depth - 1) * 4 + 2];
	originY = savedSize[(depth - 1) * 4 + 3];
	openRun(BreakReason.Barrier);
}

// One separable-blur tap pass (h2d.filter.Blur) recorded into the stream. `step` is the
// per-tap UV offset; run horizontal (step,0) then vertical (0,step) ping-ponging two RTs.
export function blurPass(srcView: uint32, stepX: float32, stepY: float32): void {
	closeRun();
	recordBlur(srcView, stepX, stepY);
	openRun(BreakReason.Barrier);
}

// ===== world-space geometry from a retained local-space mesh =====

// A Label's glyphs and a Graphics' triangles are built once in LOCAL space and kept on the
// node. Before P1 each owned an sg_buffer and was drawn with an object matrix in the shader,
// which is why at most about 126 of them could exist at all. Now the mesh is transformed
// here and appended to the frame's stream, so any number of them share one buffer and one
// draw per state run. P2 gives the transform back to the GPU as a per-instance affine; until
// then the CPU does it, which is what the old dynamic path already did for every Rect.
export function drawMeshRange(
	mesh: float32[],
	vertexOffset: int32,
	vertexTotal: int32,
	view: uint32,
	blend: BlendMode,
	m: Transform2D,
	tint: Color,
	alpha: float32,
): void {
	const first: int32 = vertexOffset * VERTEX_FLOATS;
	let upto: int32 = first + vertexTotal * VERTEX_FLOATS;
	if (first < 0 || first >= (mesh.length as int32)) { return; }
	if (upto > (mesh.length as int32)) { upto = mesh.length as int32; }
	useRun(Pipeline.Vertex, view == 0 ? void2dWhiteView() : view, blend);
	for (let i: int32 = first; i + VERTEX_FLOATS <= upto; i = i + VERTEX_FLOATS) {
		const lx: float32 = mesh[i];
		const ly: float32 = mesh[i + 1];
		pushVertex(
			m.a * lx + m.c * ly + m.tx,
			m.b * lx + m.d * ly + m.ty,
			mesh[i + 2],
			mesh[i + 3],
			mesh[i + 4] * tint.r,
			mesh[i + 5] * tint.g,
			mesh[i + 6] * tint.b,
			mesh[i + 7] * tint.a * alpha,
		);
	}
}

export function drawMesh(
	mesh: float32[],
	view: uint32,
	blend: BlendMode,
	m: Transform2D,
	tint: Color,
	alpha: float32,
): void {
	drawMeshRange(mesh, 0, (mesh.length as int32) / VERTEX_FLOATS,
		view, blend, m, tint, alpha);
}

// ===== arbitrary-corner quads (for rotated/affine nodes; a=TL b=TR c=BR d=BL) =====

function quad4(view: uint32, blend: BlendMode, a: Vec2, b: Vec2, c: Vec2, d: Vec2, u0: float32, v0: float32, u1: float32, v1: float32, color: Color): void {
	useRun(Pipeline.Vertex, view, blend);
	pushVertex(a.x, a.y, u0, v0, color.r, color.g, color.b, color.a);
	pushVertex(b.x, b.y, u1, v0, color.r, color.g, color.b, color.a);
	pushVertex(c.x, c.y, u1, v1, color.r, color.g, color.b, color.a);
	pushVertex(a.x, a.y, u0, v0, color.r, color.g, color.b, color.a);
	pushVertex(c.x, c.y, u1, v1, color.r, color.g, color.b, color.a);
	pushVertex(d.x, d.y, u0, v1, color.r, color.g, color.b, color.a);
}

// One instanced sprite: the node's world affine, the origin its local bounds map to, and
// its local size. The shader rebuilds the corners, so the walk stops writing six transformed
// vertices and writes 64 unchanged bytes instead.
//
// `curEffect` is the gate. The sprite program carries no colour pipeline - no colorMatrix, no
// colorAdd, no colorKey - so a node with one stays on the vertex path. That is a decision the
// caller makes, not a silent fallback: `spriteInstancingAvailable` is what render.ms asks.
export function drawSpriteAffine(
	view: uint32,
	blend: BlendMode,
	world: Transform2D,
	originX: float32,
	originY: float32,
	sizeX: float32,
	sizeY: float32,
	u0: float32, v0: float32, u1: float32, v1: float32,
	color: Color,
): void {
	useRun(Pipeline.Sprite, view == 0 ? void2dWhiteView() : view, blend);
	pushSpriteInstance(
		world.a, world.b, world.c, world.d,
		originX - originXOffset(), originY - originYOffset(), sizeX, sizeY,
		u0, v0, u1, v1,
		color,
	);
}

// One unified-UI instance: the node's world affine, the origin its local bounds map to, its
// local size, and the six lanes the modes share. The fragment stage re-derives the SDF in
// local space from these, so a rounded, bordered card at 37 degrees keeps its corner radius
// and its edge softness instead of having them baked in here.
//
// `mode` is a lane and not a pipeline - that is P2's whole thesis. A card, its label and its
// image differ by one float and stay in one run; the alternative is GPUI's per-kind pipelines,
// which is what forces its BoundsTree (guardrail 1).
//
// Every lane is a parameter rather than a struct because a struct over 24 bytes has no `==`
// on this compiler and would be copied at every call; the modes that leave a lane unused
// pass zeros and `instance.ms` says which lane means what.
export function drawUiInstance(
	mode: InstanceMode,
	view: uint32,
	blend: BlendMode,
	world: Transform2D,
	originX: float32,
	originY: float32,
	sizeX: float32,
	sizeY: float32,
	uvr0: float32, uvr1: float32, uvr2: float32, uvr3: float32,
	borderL: float32, borderT: float32, borderR: float32, borderB: float32,
	p1: float32, p2: float32, p3: float32,
	q0: float32, q1: float32, q2: float32, q3: float32,
	fill: Color,
	border: Color,
	extra: Color,
): void {
	useRun(Pipeline.Ui, view == 0 ? void2dWhiteView() : view, blend);
	pushUiInstance(
		world.a, world.b, world.c, world.d,
		originX - originXOffset(), originY - originYOffset(), sizeX, sizeY,
		uvr0, uvr1, uvr2, uvr3,
		borderL, borderT, borderR, borderB,
		(mode as int32) as float32, p1, p2, p3,
		q0, q1, q2, q3,
		fill, border, extra,
	);
}

// True when the unified UI pipeline is legal for the state the emitter is in. Same single
// disqualifier as the sprite path: the UI program carries no colour pipeline either, so a
// node with a colorMatrix, colorAdd or colorKey stays on the vertex path - a decision the
// caller makes, never a silent fallback.
export function uiInstancingAvailable(): boolean {
	return curEffect == NO_EFFECT;
}

// Counted from the stream rather than from the GPU, so T1 reads them with no GPU at all.
export function recordedUiInstanceCount(): int32 { return uiInstanceCount(); }
export function recordedSpriteInstanceCount(): int32 { return spriteInstanceCount(); }

// A filter records its subtree into an object-local target by subtracting the target's
// origin as each vertex is written. An instance carries its origin once, so the same
// subtraction applies there - and it has to be the same two numbers, or a filtered sprite
// lands somewhere else than a filtered anything else.
function originXOffset(): float32 { return originX; }
function originYOffset(): float32 { return originY; }

// True when the instanced path is legal for the state the emitter is in. The only thing that
// disqualifies it is a colour pipeline, which the sprite program does not have.
export function spriteInstancingAvailable(): boolean {
	return curEffect == NO_EFFECT;
}

export function fillQuad(a: Vec2, b: Vec2, c: Vec2, d: Vec2, color: Color, blend: BlendMode): void {
	quad4(void2dWhiteView(), blend, a, b, c, d, 0.0, 0.0, 1.0, 1.0, color);
}

export function imageQuad(t: Tile, a: Vec2, b: Vec2, c: Vec2, d: Vec2, color: Color, blend: BlendMode): void {
	quad4(t.view, blend, a, b, c, d, t.u0, t.v0, t.u1, t.v1, color);
}

// explicit-UV textured quad — ScaleGrid 9-slice cells carry their own UV sub-rect.
export function imageQuadUV(view: uint32, u0: float32, v0: float32, u1: float32, v1: float32, a: Vec2, b: Vec2, c: Vec2, d: Vec2, color: Color, blend: BlendMode): void {
	quad4(view, blend, a, b, c, d, u0, v0, u1, v1, color);
}
