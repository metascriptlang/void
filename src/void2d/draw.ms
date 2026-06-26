// Void 2D batcher — LOGIC in MetaScript. Owns the packed vertex buffer (Vec<float32>)
// and builds quad/glyph geometry; C (batcher.c) only does sokol uploads + fontstash layout.
// Public API takes value types (Vec2/Color). import-from-.h auto-compiles batcher.c + maps
// the string param of void2dTextBegin.

import {
	void2dSetup, void2dWhiteView, void2dFontView, void2dUploadDraw,
	void2dTextBegin, void2dTextNext, void2dTextSyncAtlas
} from "./batcher.h";
import { Vec2, Color, Tile, Transform2D, BlendMode, vec2, rgba } from "./types";

const MAX_VERTS: int32 = 32768;
const verts: Vec<float32> = new Array(MAX_VERTS * 8);
let vertCount: int32 = 0;
let curView: uint32 = 0;
let curBlend: BlendMode = BlendMode.Alpha;
let fbW: float32 = 0.0;
let fbH: float32 = 0.0;

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
let curHasEffect: boolean = false;

function setIdentityMat(): void {
	let i: int32 = 0;
	while (i < 16) { curMat[i] = 0.0; i = i + 1; }
	curMat[0] = 1.0; curMat[5] = 1.0; curMat[10] = 1.0; curMat[15] = 1.0;
}

function flush(): void {
	if (vertCount == 0) { return; }
	void2dUploadDraw(verts[0], vertCount, curView, curBlend as int32, fbW, fbH, curMat[0], curAdd.r, curAdd.g, curAdd.b, curAdd.a);
	vertCount = 0;
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

export function begin2d(w: int32, h: int32): void {
	fbW = w as float32;
	fbH = h as float32;
	vertCount = 0;
	curView = void2dWhiteView();
	curBlend = BlendMode.Alpha;
	setIdentityMat();
	curAdd = rgba(0.0, 0.0, 0.0, 0.0);
	curHasEffect = false;
}

// h2d.Drawable color/colorAdd → batch state. mat = 16-float column-major colorMatrix
// (empty/<16 = identity); add = rgba added after. Flushes when switching off the
// effect-free batch (or onto a different effect).
export function setEffect(mat: float32[], add: Color): void {
	const hasMat: boolean = (mat.length as int32) >= 16;
	const wantsEffect: boolean = hasMat || add.r != 0.0 || add.g != 0.0 || add.b != 0.0 || add.a != 0.0;
	if (!wantsEffect && !curHasEffect) { return; }
	flush();
	if (hasMat) {
		let i: int32 = 0;
		while (i < 16) { curMat[i] = mat[i]; i = i + 1; }
	} else {
		setIdentityMat();
	}
	curAdd = add;
	curHasEffect = wantsEffect;
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

// solid triangle, per-vertex colour (Graphics fills/strokes; white view, no texture).
export function fillTri(a: Vec2, ca: Color, b: Vec2, cb: Color, c: Vec2, cc: Color, blend: BlendMode): void {
	useState(void2dWhiteView(), blend);
	if (vertCount + 3 > MAX_VERTS) { flush(); }
	pushVert(a.x, a.y, 0.0, 0.0, ca.r, ca.g, ca.b, ca.a);
	pushVert(b.x, b.y, 0.0, 0.0, cb.r, cb.g, cb.b, cb.a);
	pushVert(c.x, c.y, 0.0, 0.0, cc.r, cc.g, cc.b, cc.a);
}

// Text under a full affine — glyphs laid out at origin (fixed size → stable atlas), each
// quad corner pushed through `m` (so rotation/scale/translate apply, no font-size churn).
export function drawTextXform(m: Transform2D, size: float32, text: string, color: Color, blend: BlendMode): void {
	useState(void2dFontView(), blend);
	void2dTextBegin(0.0, 0.0, size, text);
	let q: Ptr<float32> = void2dTextNext();
	while (q !== null) {
		if (vertCount + 6 > MAX_VERTS) { flush(); }
		const tl = vec2(q[0], q[1]) * m;
		const tr = vec2(q[4], q[1]) * m;
		const br = vec2(q[4], q[5]) * m;
		const bl = vec2(q[0], q[5]) * m;
		const s0: float32 = q[2];
		const t0: float32 = q[3];
		const s1: float32 = q[6];
		const t1: float32 = q[7];
		pushVert(tl.x, tl.y, s0, t0, color.r, color.g, color.b, color.a);
		pushVert(tr.x, tr.y, s1, t0, color.r, color.g, color.b, color.a);
		pushVert(br.x, br.y, s1, t1, color.r, color.g, color.b, color.a);
		pushVert(tl.x, tl.y, s0, t0, color.r, color.g, color.b, color.a);
		pushVert(br.x, br.y, s1, t1, color.r, color.g, color.b, color.a);
		pushVert(bl.x, bl.y, s0, t1, color.r, color.g, color.b, color.a);
		q = void2dTextNext();
	}
	void2dTextSyncAtlas();
}
