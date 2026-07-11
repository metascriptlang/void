// Void 2D batcher — LOGIC in MetaScript. Owns the packed vertex buffer (Vec<float32>)
// and builds quad/glyph geometry; C (batcher.c) only does sokol uploads + fontstash layout.
// Public API takes value types (Vec2/Color). import-from-.h auto-compiles batcher.c + maps
// the string param of void2dTextBegin.

import {
	void2dSetup, void2dWhiteView, void2dFontView, void2dUploadDraw, void2dScissor, void2dSetRTMode, void2dSetDpiScale, void2dFrameBegin,
	void2dTextBegin, void2dTextNext, void2dTextSyncAtlas, void2dTextWidth, void2dLineHeight, void2dTextSpacing, void2dAtlasGen, void2dAddFont, void2dSelectFont,
	void2dMakeStaticBuffer, void2dDestroyStaticBuffer, void2dDrawStatic, void2dBlur
} from "./batcher.h";
import { Vec2, Color, Tile, Transform2D, BlendMode, rgba } from "./types";
import { makeRenderTarget, destroyRenderTarget, renderTargetView, beginRenderTargetPass, endPass } from "../sokol/gpu";

export function allocRenderTarget(w: int32, h: int32): uint32 { return makeRenderTarget(w, h); }
export function freeRenderTarget(rt: uint32): void { destroyRenderTarget(rt); }
export function rtViewId(rt: uint32): uint32 { return renderTargetView(rt); }
export function beginRT(rt: uint32, r: float32, g: float32, b: float32, a: float32): void { beginRenderTargetPass(rt, r, g, b, a); }
export function endRT(): void { endPass(); }

const MAX_VERTS: int32 = 65536;
const verts: Vec<float32> = new Array(MAX_VERTS * 8);
let vertCount: int32 = 0;
let curView: uint32 = 0;
let curBlend: BlendMode = BlendMode.Alpha;
let curSmooth: boolean = true;
let fbW: float32 = 0.0;
let fbH: float32 = 0.0;
let _drawCallCount: int32 = 0;

export function drawCallCount(): int32 { return _drawCallCount; }

// h2d.Drawable colour pipeline as batch state: identity matrix + zero add = no-op, so
// effect-free nodes batch together. A node with a distinct effect starts its own run
// (flush on change, like blend mode); identical-effect runs aren't deduped yet.
const curMat: Vec<float32> = [
	1.0, 0.0, 0.0, 0.0,
	0.0, 1.0, 0.0, 0.0,
	0.0, 0.0, 1.0, 0.0,
	0.0, 0.0, 0.0, 1.0,
];
let curAdd: Color = rgba(0.0, 0.0, 0.0, 0.0);
let curKey: Color = rgba(0.0, 0.0, 0.0, 0.0);
let curHasEffect: boolean = false;

// h2d.Mask clip stack: each pushClip intersects with the enclosing zone (Heaps
// clipRenderZone semantics) and flushes so the scissor only bounds the masked subtree.
const clipX0: Vec<float32> = new Array(16);
const clipY0: Vec<float32> = new Array(16);
const clipX1: Vec<float32> = new Array(16);
const clipY1: Vec<float32> = new Array(16);
let clipDepth: int32 = 0;

function setIdentityMat(): void {
	let i: int32 = 0;
	while (i < 16) { curMat[i] = 0.0; i = i + 1; }
	curMat[0] = 1.0; curMat[5] = 1.0; curMat[10] = 1.0; curMat[15] = 1.0;
}

function effectMatrixSame(mat: float32[], hasMat: boolean): boolean {
	if (hasMat) {
		let i: int32 = 0;
		while (i < 16) { if (mat[i] != curMat[i]) { return false; } i = i + 1; }
		return true;
	}
	return curMat[0] == 1.0 && curMat[5] == 1.0 && curMat[10] == 1.0 && curMat[15] == 1.0
		&& curMat[1] == 0.0 && curMat[2] == 0.0 && curMat[3] == 0.0 && curMat[4] == 0.0
		&& curMat[6] == 0.0 && curMat[7] == 0.0 && curMat[8] == 0.0 && curMat[9] == 0.0
		&& curMat[11] == 0.0 && curMat[12] == 0.0 && curMat[13] == 0.0 && curMat[14] == 0.0;
}

function flush(): void {
	if (vertCount == 0) { return; }
	const sm: int32 = curSmooth ? 1 : 0;
	void2dUploadDraw(verts[0], vertCount, curView, curBlend as int32, fbW, fbH, curMat[0], curAdd.r, curAdd.g, curAdd.b, curAdd.a, curKey.r, curKey.g, curKey.b, curKey.a, sm);
	vertCount = 0;
	_drawCallCount = _drawCallCount + 1;
}

function useState(v: uint32, b: BlendMode): void {
	if (v != curView || b != curBlend) { flush(); curView = v; curBlend = b; }
}

function pushVert(x: float32, y: float32, u: float32, v: float32, r: float32, g: float32, b: float32, a: float32): void {
	const o: int32 = vertCount * 8;
	verts[o] = x; verts[o + 1] = y; verts[o + 2] = u; verts[o + 3] = v;
	verts[o + 4] = r; verts[o + 5] = g; verts[o + 6] = b; verts[o + 7] = a;
	vertCount = vertCount + 1;
}

function quad(view: uint32, blend: BlendMode, x: float32, y: float32, w: float32, h: float32, c: Color, u0: float32, v0: float32, u1: float32, v1: float32): void {
	useState(view, blend);
	if (vertCount + 6 > MAX_VERTS) { flush(); }
	const x1: float32 = x + w;
	const y1: float32 = y + h;
	pushVert(x, y, u0, v0, c.r, c.g, c.b, c.a);
	pushVert(x1, y, u1, v0, c.r, c.g, c.b, c.a);
	pushVert(x1, y1, u1, v1, c.r, c.g, c.b, c.a);
	pushVert(x, y, u0, v0, c.r, c.g, c.b, c.a);
	pushVert(x1, y1, u1, v1, c.r, c.g, c.b, c.a);
	pushVert(x, y1, u0, v1, c.r, c.g, c.b, c.a);
}

export function setup2d(): void {
	void2dSetup();
}

export function atlasGen(): int32 { return void2dAtlasGen(); }
export function addFont(path: string): int32 { return void2dAddFont(path); }

export function begin2d(w: int32, h: int32, dpi: float32): void {
	void2dSetDpiScale(dpi);
	void2dFrameBegin();
	fbW = w as float32;
	fbH = h as float32;
	vertCount = 0;
	curView = void2dWhiteView();
	curBlend = BlendMode.Alpha;
	curSmooth = true;
	setIdentityMat();
	curAdd = rgba(0.0, 0.0, 0.0, 0.0);
	curKey = rgba(0.0, 0.0, 0.0, 0.0);
	curHasEffect = false;
	clipDepth = 0;
	_drawCallCount = 0;
}

function applyScissor(x0: float32, y0: float32, x1: float32, y1: float32): void {
	let ix: int32 = x0 as int32;
	let iy: int32 = y0 as int32;
	let iw: int32 = (x1 - x0) as int32;
	let ih: int32 = (y1 - y0) as int32;
	if (ix < 0) { iw = iw + ix; ix = 0; }
	if (iy < 0) { ih = ih + iy; iy = 0; }
	if (iw < 0) { iw = 0; }
	if (ih < 0) { ih = 0; }
	void2dScissor(ix, iy, iw, ih);
}

export function pushClip(minX: float32, minY: float32, maxX: float32, maxY: float32): void {
	flush();
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
		clipX0.push(0.0 as float32); clipY0.push(0.0 as float32); clipX1.push(0.0 as float32); clipY1.push(0.0 as float32);
	}
	clipX0[clipDepth] = x0;
	clipY0[clipDepth] = y0;
	clipX1[clipDepth] = x1;
	clipY1[clipDepth] = y1;
	clipDepth = clipDepth + 1;
	applyScissor(x0, y0, x1, y1);
}

export function popClip(): void {
	flush();
	if (clipDepth > 0) { clipDepth = clipDepth - 1; }
	if (clipDepth > 0) {
		const d: int32 = clipDepth - 1;
		applyScissor(clipX0[d], clipY0[d], clipX1[d], clipY1[d]);
	} else {
		void2dScissor(0, 0, fbW as int32, fbH as int32);
	}
}

// h2d.Drawable color pipeline → batch state. mat = 16-float column-major colorMatrix
// (empty/<16 = identity); add = rgba added after; key = chroma colorKey (a>0 enables,
// matching texels go transparent). Flushes when switching off the effect-free batch
// (or onto a different effect).
export function setEffect(mat: float32[], add: Color, key: Color): void {
	const hasMat: boolean = (mat.length as int32) >= 16;
	const wantsEffect: boolean = hasMat || add.r != 0.0 || add.g != 0.0 || add.b != 0.0 || add.a != 0.0 || key.a > 0.0;
	if (!wantsEffect && !curHasEffect) { return; }
	if (wantsEffect && curHasEffect
		&& add.r == curAdd.r && add.g == curAdd.g && add.b == curAdd.b && add.a == curAdd.a
		&& key.r == curKey.r && key.g == curKey.g && key.b == curKey.b && key.a == curKey.a
		&& effectMatrixSame(mat, hasMat)) { return; }
	flush();
	if (hasMat) {
		let i: int32 = 0;
		while (i < 16) { curMat[i] = mat[i]; i = i + 1; }
	} else {
		setIdentityMat();
	}
	curAdd = add;
	curKey = key;
	curHasEffect = wantsEffect;
}

// h2d.Drawable.smooth — pick linear (true) vs nearest (false) sampling; batch state.
export function setSmooth(s: boolean): void {
	if (s != curSmooth) { flush(); curSmooth = s; }
}

export function drawRect(pos: Vec2, size: Vec2, color: Color, blend: BlendMode): void {
	quad(void2dWhiteView(), blend, pos.x, pos.y, size.x, size.y, color, 0.0, 0.0, 1.0, 1.0);
}

export function drawImage(t: Tile, pos: Vec2, size: Vec2, tint: Color, blend: BlendMode): void {
	quad(t.view, blend, pos.x, pos.y, size.x, size.y, tint, t.u0, t.v0, t.u1, t.v1);
}

// `size` is the FIXED rasterization size (stable atlas — never animate it, or fontstash
// re-rasterizes every frame → atlas churn/flicker). `scale` transforms the glyph quads,
// so animated scaling stays crisp-enough and the atlas is untouched.
export function drawText(pos: Vec2, size: float32, scale: float32, text: string, color: Color, blend: BlendMode): void {
	useState(void2dFontView(), blend);
	void2dTextBegin(0.0, 0.0, size, text);   // layout at origin; pos+scale applied per-corner below
	let q: Ptr<float32> = void2dTextNext();
	while (q !== null) {
		if (vertCount + 6 > MAX_VERTS) { flush(); }
		const x0: float32 = pos.x + q[0] * scale;
		const y0: float32 = pos.y + q[1] * scale;
		const s0: float32 = q[2];
		const t0: float32 = q[3];
		const x1: float32 = pos.x + q[4] * scale;
		const y1: float32 = pos.y + q[5] * scale;
		const s1: float32 = q[6];
		const t1: float32 = q[7];
		pushVert(x0, y0, s0, t0, color.r, color.g, color.b, color.a);
		pushVert(x1, y0, s1, t0, color.r, color.g, color.b, color.a);
		pushVert(x1, y1, s1, t1, color.r, color.g, color.b, color.a);
		pushVert(x0, y0, s0, t0, color.r, color.g, color.b, color.a);
		pushVert(x1, y1, s1, t1, color.r, color.g, color.b, color.a);
		pushVert(x0, y1, s0, t1, color.r, color.g, color.b, color.a);
		q = void2dTextNext();
	}
	void2dTextSyncAtlas();
}

export function end2d(): void { flush(); }

// Toggle offscreen-RT pipeline routing (flush first — pipeline set changes at pass boundaries).
export function setRTMode(on: boolean): void { flush(); void2dSetRTMode(on ? 1 : 0); }

// One separable-blur tap pass (h2d.filter.Blur) into the active RT pass. `step` is the per-tap
// UV offset (radius/size); run horizontal (step,0) then vertical (0,step) ping-ponging two RTs.
export function blurPass(srcView: uint32, stepX: float32, stepY: float32): void {
	void2dBlur(srcView, stepX, stepY);
}

// ===== static (retained) geometry: local-space buffer + object matrix in the shader =====

const idMat16: float32[] = [1.0,0.0,0.0,0.0, 0.0,1.0,0.0,0.0, 0.0,0.0,1.0,0.0, 0.0,0.0,0.0,1.0];

export function uploadStaticMesh(mesh: float32[], vertCount: int32): uint32 {
	return void2dMakeStaticBuffer(mesh[0], vertCount);
}

export function destroyStaticMesh(buf: uint32): void {
	void2dDestroyStaticBuffer(buf);
}

// Draw a Graphics static buffer: flush the pending dynamic batch first (z-order), then one draw
// call with the object matrix (m) + accumulated alpha (na) + the node's colour pipeline.
export function drawStaticGraphics(buf: uint32, vertCount: int32, view: uint32, blend: BlendMode,
	m: Transform2D, na: float32, colorMatrix: float32[], colorAdd: Color, colorKey: Color, smooth: boolean): void {
	if (vertCount <= 0 || buf == 0) { return; }
	flush();
	const hasMat: boolean = (colorMatrix.length as int32) >= 16;
	const mat: float32[] = hasMat ? colorMatrix : idMat16;
	const sm: int32 = smooth ? 1 : 0;
	void2dDrawStatic(buf, vertCount, view, blend as int32, fbW, fbH,
		m.a, m.b, m.c, m.d, m.tx, m.ty,
		1.0, 1.0, 1.0, na,
		mat[0], colorAdd.r, colorAdd.g, colorAdd.b, colorAdd.a,
		colorKey.r, colorKey.g, colorKey.b, colorKey.a, sm);
	_drawCallCount = _drawCallCount + 1;
}

// ===== arbitrary-corner quads (for rotated/affine nodes; a=TL b=TR c=BR d=BL) =====

function quad4(view: uint32, blend: BlendMode, a: Vec2, b: Vec2, c: Vec2, d: Vec2, u0: float32, v0: float32, u1: float32, v1: float32, color: Color): void {
	useState(view, blend);
	if (vertCount + 6 > MAX_VERTS) { flush(); }
	pushVert(a.x, a.y, u0, v0, color.r, color.g, color.b, color.a);
	pushVert(b.x, b.y, u1, v0, color.r, color.g, color.b, color.a);
	pushVert(c.x, c.y, u1, v1, color.r, color.g, color.b, color.a);
	pushVert(a.x, a.y, u0, v0, color.r, color.g, color.b, color.a);
	pushVert(c.x, c.y, u1, v1, color.r, color.g, color.b, color.a);
	pushVert(d.x, d.y, u0, v1, color.r, color.g, color.b, color.a);
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

// Draw a Label static glyph buffer: flush first (z-order), then one draw call with the object
// matrix + the label colour×alpha as globalColor (glyphs are white) + the node's colour pipeline.
export function drawStaticText(buf: uint32, vertCount: int32, m: Transform2D, color: Color, na: float32,
	blend: BlendMode, colorMatrix: float32[], colorAdd: Color, colorKey: Color, smooth: boolean): void {
	if (vertCount <= 0 || buf == 0) { return; }
	flush();
	const hasMat: boolean = (colorMatrix.length as int32) >= 16;
	const mat: float32[] = hasMat ? colorMatrix : idMat16;
	const sm: int32 = smooth ? 1 : 0;
	void2dDrawStatic(buf, vertCount, void2dFontView(), blend as int32, fbW, fbH,
		m.a, m.b, m.c, m.d, m.tx, m.ty,
		color.r, color.g, color.b, color.a * na,
		mat[0], colorAdd.r, colorAdd.g, colorAdd.b, colorAdd.a,
		colorKey.r, colorKey.g, colorKey.b, colorKey.a, sm);
	_drawCallCount = _drawCallCount + 1;
}
