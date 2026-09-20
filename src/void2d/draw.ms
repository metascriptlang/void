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
	void2dSetup, void2dWhiteView, void2dFontView, void2dSetDpiScale, void2dFrameBegin,
	void2dTextBegin, void2dTextNext, void2dTextSyncAtlas, void2dTextWidth, void2dLineHeight,
	void2dTextSpacing, void2dAtlasGen, void2dAddFont, void2dSelectFont,
	void2dReplay, void2dLayoutCheck,
	void2dDrawCallCount, void2dUploadCount, void2dUploadBytes, void2dBuffersAlive,
	void2dInstanceBufferBytes, void2dDroppedFrames,
} from "./batcher.h";
import {
	CommandKind, BreakReason,
	COMMAND_FLOATS, EFFECT_FLOATS, VERTEX_FLOATS, NO_EFFECT,
	CMD_KIND, CMD_BREAK, CMD_VERTEX_OFFSET, CMD_VERTEX_COUNT, CMD_VIEW, CMD_BLEND, CMD_SMOOTH,
	CMD_EFFECT, CMD_CLIP_X, CMD_ARG0, CMD_RT_MODE,
	commands, effects, vertices,
	resetList, commandCount, effectCount, vertexCount, drawCommandCount, setRenderTargetMode,
	pushVertex, pushEffect, recordDraw, recordClip, recordBlur,
} from "./displayList";
import { Vec2, Color, Tile, Transform2D, BlendMode, rgba } from "./types";
import { makeRenderTarget, destroyRenderTarget, renderTargetView, beginRenderTargetPass, endPass } from "../sokol/gpu";

export function allocRenderTarget(w: int32, h: int32): uint32 { return makeRenderTarget(w, h); }
export function freeRenderTarget(rt: uint32): void { destroyRenderTarget(rt); }
export function rtViewId(rt: uint32): uint32 { return renderTargetView(rt); }
export function beginRT(rt: uint32, r: float32, g: float32, b: float32, a: float32): void { beginRenderTargetPass(rt, r, g, b, a); }
export function endRT(): void { endPass(); }

// The batch the emitter is accumulating: a run of vertices that share every piece of state
// the replay would otherwise have to change between them.
let runStart: int32 = 0;
let runOpen: boolean = false;
let runReason: BreakReason = BreakReason.First;
let curView: uint32 = 0;
let curBlend: BlendMode = BlendMode.Alpha;
let curSmooth: boolean = true;
let curEffect: int32 = NO_EFFECT;
let fbW: float32 = 0.0;
let fbH: float32 = 0.0;

export function drawCallCount(): int32 { return void2dDrawCallCount(); }
export function uploadCount(): int32 { return void2dUploadCount(); }
export function uploadBytes(): int32 { return void2dUploadBytes(); }
export function buffersAlive(): int32 { return void2dBuffersAlive(); }
export function instanceBufferBytes(): int32 { return void2dInstanceBufferBytes(); }
export function droppedFrames(): int32 { return void2dDroppedFrames(); }

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

// h2d.Mask clip stack: each push intersects with the enclosing zone (Heaps clipRenderZone
// semantics). Intersecting rather than replacing is what makes a nested Mask clip to both.
const clipX0: Vec<float32> = new Array(16);
const clipY0: Vec<float32> = new Array(16);
const clipX1: Vec<float32> = new Array(16);
const clipY1: Vec<float32> = new Array(16);
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
	const count: int32 = vertexCount() - runStart;
	if (count > 0) {
		recordDraw(runReason, runStart, count, curView, curBlend, curSmooth, curEffect);
	}
	runOpen = false;
}

function openRun(reason: BreakReason): void {
	runStart = vertexCount();
	runReason = reason;
	runOpen = true;
}

function useState(view: uint32, blend: BlendMode): void {
	if (runOpen && view == curView && blend == curBlend) { return; }
	const reason: BreakReason = !runOpen ? BreakReason.First
		: (view != curView ? BreakReason.View : BreakReason.Blend);
	closeRun();
	curView = view;
	curBlend = blend;
	openRun(reason);
}

export function setup2d(): void {
	void2dSetup();
	// The emitter and the replay are two hand-written readers of one byte layout, so they
	// are made to agree out loud rather than by inspection.
	if (void2dLayoutCheck(
		COMMAND_FLOATS, EFFECT_FLOATS, VERTEX_FLOATS,
		CMD_KIND, CMD_BREAK, CMD_VERTEX_OFFSET, CMD_VERTEX_COUNT,
		CMD_VIEW, CMD_BLEND, CMD_SMOOTH, CMD_EFFECT,
		CMD_CLIP_X, CMD_ARG0, CMD_RT_MODE,
		CommandKind.Draw as int32, CommandKind.Scissor as int32, CommandKind.Blur as int32,
	) == 0) {
		console.log("void2d: the display-list layout in displayList.ms and batcher.c disagree");
	}
}

// The glyph atlas view, so render.ms can emit a Label's mesh against it without reaching
// into batcher.h itself.
export function fontView(): uint32 { return void2dFontView(); }

export function atlasGen(): int32 { return void2dAtlasGen(); }
export function addFont(path: string): int32 { return void2dAddFont(path); }

// h2d has no DPI concept; void2d needs one because snapping and the pixel-exact text regime
// are stated per device pixel. The logical size is a float — the `as int32` truncation that
// put every glyph off-grid at DPI 1.25 and 1.5 is gone (VOID2D.md "Known defects").
export function begin2d(w: float32, h: float32, dpi: float32): void {
	void2dSetDpiScale(dpi);
	void2dFrameBegin();
	fbW = w;
	fbH = h;
	resetList();
	runOpen = false;
	runStart = 0;
	curView = void2dWhiteView();
	curBlend = BlendMode.Alpha;
	curSmooth = true;
	curEffect = NO_EFFECT;
	setIdentityMat();
	curAdd = rgba(0.0, 0.0, 0.0, 0.0);
	curKey = rgba(0.0, 0.0, 0.0, 0.0);
	curHasEffect = false;
	clipDepth = 0;
}

// Replay the frame into the pass the caller already has open. This is the only place the GPU
// is touched, and it happens after the walk has finished.
export function end2d(): void {
	closeRun();
	if (commandCount() == 0) { return; }
	void2dReplay(
		commands[0], commandCount(),
		effects[0], effectCount(),
		vertices[0], vertexCount(),
		fbW, fbH,
	);
}

function applyClip(x0: float32, y0: float32, x1: float32, y1: float32): void {
	let ix: float32 = x0;
	let iy: float32 = y0;
	let iw: float32 = x1 - x0;
	let ih: float32 = y1 - y0;
	if (ix < 0.0) { iw = iw + ix; ix = 0.0; }
	if (iy < 0.0) { ih = ih + iy; iy = 0.0; }
	if (iw < 0.0) { iw = 0.0; }
	if (ih < 0.0) { ih = 0.0; }
	closeRun();
	recordClip(ix, iy, iw, ih);
	openRun(BreakReason.Clip);
}

export function pushClip(minX: float32, minY: float32, maxX: float32, maxY: float32): void {
	let x0: float32 = minX;
	let y0: float32 = minY;
	let x1: float32 = maxX;
	let y1: float32 = maxY;
	if (clipDepth > 0) {
		const d: int32 = clipDepth - 1;
		if (clipX0[d] > x0) { x0 = clipX0[d]; }
		if (clipY0[d] > y0) { y0 = clipY0[d]; }
		if (clipX1[d] < x1) { x1 = clipX1[d]; }
		if (clipY1[d] < y1) { y1 = clipY1[d]; }
	}
	while (clipDepth >= clipX0.length as int32) {
		clipX0.push(0.0 as float32);
		clipY0.push(0.0 as float32);
		clipX1.push(0.0 as float32);
		clipY1.push(0.0 as float32);
	}
	clipX0[clipDepth] = x0;
	clipY0[clipDepth] = y0;
	clipX1[clipDepth] = x1;
	clipY1[clipDepth] = y1;
	clipDepth = clipDepth + 1;
	applyClip(x0, y0, x1, y1);
}

export function popClip(): void {
	if (clipDepth > 0) { clipDepth = clipDepth - 1; }
	if (clipDepth > 0) {
		const d: int32 = clipDepth - 1;
		applyClip(clipX0[d], clipY0[d], clipX1[d], clipY1[d]);
	} else {
		closeRun();
		recordClip(0.0, 0.0, 0.0, 0.0);
		openRun(BreakReason.Clip);
	}
}

// h2d.Drawable colour pipeline → batch state. mat = 16-float column-major colorMatrix
// (empty/<16 = identity); add = rgba added after; key = chroma colorKey (a>0 enables,
// matching texels go transparent).
export function setEffect(mat: float32[], add: Color, key: Color): void {
	const hasMat: boolean = (mat.length as int32) >= 16;
	const wantsEffect: boolean = hasMat || add.r != 0.0 || add.g != 0.0 || add.b != 0.0 || add.a != 0.0 || key.a > 0.0;
	if (!wantsEffect && !curHasEffect) { return; }
	if (wantsEffect && curHasEffect
		&& add.r == curAdd.r && add.g == curAdd.g && add.b == curAdd.b && add.a == curAdd.a
		&& key.r == curKey.r && key.g == curKey.g && key.b == curKey.b && key.a == curKey.a
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

// h2d.Drawable.smooth — linear (true) vs nearest (false) sampling; batch state.
export function setSmooth(s: boolean): void {
	if (s == curSmooth) { return; }
	closeRun();
	curSmooth = s;
	openRun(BreakReason.Smooth);
}

function quad(view: uint32, blend: BlendMode, x: float32, y: float32, w: float32, h: float32, c: Color, u0: float32, v0: float32, u1: float32, v1: float32): void {
	useState(view, blend);
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

// `size` is the FIXED rasterization size (stable atlas — never animate it, or fontstash
// re-rasterizes every frame → atlas churn/flicker). `scale` transforms the glyph quads.
export function drawText(pos: Vec2, size: float32, scale: float32, text: string, color: Color, blend: BlendMode): void {
	useState(void2dFontView(), blend);
	void2dTextBegin(0.0, 0.0, size, text);
	let q: Ptr<float32> = void2dTextNext();
	while (q !== null) {
		const x0: float32 = pos.x + q[0] * scale;
		const y0: float32 = pos.y + q[1] * scale;
		const s0: float32 = q[2];
		const t0: float32 = q[3];
		const x1: float32 = pos.x + q[4] * scale;
		const y1: float32 = pos.y + q[5] * scale;
		const s1: float32 = q[6];
		const t1: float32 = q[7];
		pushVertex(x0, y0, s0, t0, color.r, color.g, color.b, color.a);
		pushVertex(x1, y0, s1, t0, color.r, color.g, color.b, color.a);
		pushVertex(x1, y1, s1, t1, color.r, color.g, color.b, color.a);
		pushVertex(x0, y0, s0, t0, color.r, color.g, color.b, color.a);
		pushVertex(x1, y1, s1, t1, color.r, color.g, color.b, color.a);
		pushVertex(x0, y1, s0, t1, color.r, color.g, color.b, color.a);
		q = void2dTextNext();
	}
	void2dTextSyncAtlas();
}

// Which pipeline set the following draws need: the offscreen one (single sample, no depth)
// or the swapchain one. Recorded per command rather than flipped here, because the replay
// runs after the recording has finished — the demo caught this the moment the display list
// landed, with every render-target draw replaying under the swapchain set.
export function setRTMode(on: boolean): void {
	closeRun();
	setRenderTargetMode(on);
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
export function drawMesh(
	mesh: float32[],
	view: uint32,
	blend: BlendMode,
	m: Transform2D,
	tint: Color,
	alpha: float32,
): void {
	const total: int32 = mesh.length as int32;
	if (total < VERTEX_FLOATS) { return; }
	useState(view == 0 ? void2dWhiteView() : view, blend);
	for (let i: int32 = 0; i + VERTEX_FLOATS <= total; i = i + VERTEX_FLOATS) {
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

// ===== arbitrary-corner quads (for rotated/affine nodes; a=TL b=TR c=BR d=BL) =====

function quad4(view: uint32, blend: BlendMode, a: Vec2, b: Vec2, c: Vec2, d: Vec2, u0: float32, v0: float32, u1: float32, v1: float32, color: Color): void {
	useState(view, blend);
	pushVertex(a.x, a.y, u0, v0, color.r, color.g, color.b, color.a);
	pushVertex(b.x, b.y, u1, v0, color.r, color.g, color.b, color.a);
	pushVertex(c.x, c.y, u1, v1, color.r, color.g, color.b, color.a);
	pushVertex(a.x, a.y, u0, v0, color.r, color.g, color.b, color.a);
	pushVertex(c.x, c.y, u1, v1, color.r, color.g, color.b, color.a);
	pushVertex(d.x, d.y, u0, v1, color.r, color.g, color.b, color.a);
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
