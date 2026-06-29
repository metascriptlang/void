// Node2D is a flat tag + fields, not a discriminated union: a union payload as an interface
// field hits a C-codegen bug. Revisit the union once the compiler handles it.

import { fillQuad, imageQuad, imageQuadUV, layoutText, drawGlyphCache, fillTriTex, setEffect, setSmooth, pushClip, popClip } from "./draw";
import { Vec2, Color, Tile, Transform2D, BlendMode, vec2, rgba, tile, trs2d, identity2d } from "./types";

export enum DrawKind { Group, Rect, Sprite, Label, Anim, Graphics, Mask, ScaleGrid }

export interface Node2D {
	kind: DrawKind;
	x: float32;
	y: float32;
	scaleX: float32;
	scaleY: float32;
	rotation: float32;
	pivotX: float32;
	pivotY: float32;
	alpha: float32;
	visible: boolean;
	smooth: boolean;
	blend: BlendMode;
	zIndex: int32;
	w: float32;
	h: float32;
	color: Color;
	colorAdd: Color;
	colorKey: Color;
	colorMatrix: float32[];
	sheet: Tile;
	borderL: float32;
	borderT: float32;
	borderR: float32;
	borderB: float32;
	text: string;
	size: float32;
	align: float32;
	letterSpacing: float32;
	lineSpacing: float32;
	maxWidth: float32;
	frames: Tile[];
	fps: float32;
	clock: float32;
	mesh: float32[];
	gfxView: uint32;
	children: Node2D[];
	childrenDirty: boolean;
	cachedLocal: Transform2D;
	cachedWorld: Transform2D;
	lastX: float32;
	lastY: float32;
	lastSX: float32;
	lastSY: float32;
	lastRot: float32;
	dirty: boolean;
	glyphCache: float32[];
	textDirty: boolean;
	lastText: string;
	lastSize: float32;
	lastAlign: float32;
	lastLetterSpacing: float32;
	lastLineSpacing: float32;
	lastMaxWidth: float32;
}

function base(kind: DrawKind): Node2D {
	return {
		kind: kind, x: 0.0, y: 0.0, scaleX: 1.0, scaleY: 1.0, rotation: 0.0, pivotX: 0.0, pivotY: 0.0, alpha: 1.0, visible: true, smooth: true, blend: BlendMode.Alpha, zIndex: 0,
		w: 0.0, h: 0.0, color: rgba(1.0, 1.0, 1.0, 1.0), colorAdd: rgba(0.0, 0.0, 0.0, 0.0), colorKey: rgba(0.0, 0.0, 0.0, 0.0), colorMatrix: [], sheet: tile(0, 0.0, 0.0), borderL: 0.0, borderT: 0.0, borderR: 0.0, borderB: 0.0, text: "", size: 0.0, align: 0.0, letterSpacing: 0.0, lineSpacing: 1.0, maxWidth: 0.0, frames: [], fps: 0.0, clock: 0.0, mesh: [], gfxView: 0, children: [], childrenDirty: true,
		cachedLocal: identity2d(), cachedWorld: identity2d(), lastX: 0.0, lastY: 0.0, lastSX: 0.0, lastSY: 0.0, lastRot: 0.0, dirty: true,
		glyphCache: [], textDirty: true, lastText: "", lastSize: 0.0, lastAlign: 0.0, lastLetterSpacing: 0.0, lastLineSpacing: 0.0, lastMaxWidth: 0.0,
	};
}

// ===== factories (≈ new Bitmap/Text, functional) =====

export function group(): Node2D {
	return base(DrawKind.Group);
}
export function rect(w: float32, h: float32, color: Color): Node2D {
	const n = base(DrawKind.Rect);
	n.w = w;
	n.h = h;
	n.color = color;
	return n;
}
export function sprite(t: Tile): Node2D {
	const n = base(DrawKind.Sprite);
	n.sheet = t;
	n.w = t.w;
	n.h = t.h;
	return n;
}
export function label(text: string, size: float32, color: Color): Node2D {
	const n = base(DrawKind.Label);
	n.text = text;
	n.size = size;
	n.color = color;
	return n;
}
export function anim(frames: Tile[], fps: float32): Node2D {
	const n = base(DrawKind.Anim);
	n.frames = frames;
	n.fps = fps;
	if (frames.length > 0) {
		n.w = frames[0].w;
		n.h = frames[0].h;
	}
	return n;
}
export function graphics(): Node2D {
	return base(DrawKind.Graphics);
}
export function mask(w: float32, h: float32): Node2D {
	const n = base(DrawKind.Mask);
	n.w = w;
	n.h = h;
	return n;
}
export function scaleGrid(t: Tile, borderL: float32, borderT: float32, borderR: float32, borderB: float32): Node2D {
	const n = base(DrawKind.ScaleGrid);
	n.sheet = t;
	n.w = t.w;
	n.h = t.h;
	n.borderL = borderL;
	n.borderT = borderT;
	n.borderR = borderR;
	n.borderB = borderB;
	return n;
}

// ===== extension methods (reads OO, is FP) =====

export function addChild(this n: Node2D, c: Node2D): Node2D {
	n.children.push(c);
	n.childrenDirty = true;
	return n;
}

export function at(this n: Node2D, x: float32, y: float32): Node2D {
	n.x = x;
	n.y = y;
	return n;
}

export function update(this n: Node2D, dt: float32): void {
	if (n.kind === DrawKind.Anim) {
		n.clock = n.clock + dt;
	}
	for (const ch of n.children) {
		ch.update(dt);
	}
}

// Stable sort by zIndex (equal zIndex keep insertion order). Runs only when childrenDirty.
function sortByZ(cs: Node2D[]): void {
	const m: int32 = cs.length as int32;
	let i: int32 = 1;
	while (i < m) {
		const cur = cs[i];
		let j: int32 = i - 1;
		while (j >= 0 && cs[j].zIndex > cur.zIndex) {
			cs[j + 1] = cs[j];
			j = j - 1;
		}
		cs[j + 1] = cur;
		i = i + 1;
	}
}

function renderScaleGrid(n: Node2D, world: Transform2D, col: Color): void {
	const t = n.sheet;
	const srcW: float32 = t.w;
	const srcH: float32 = t.h;
	if (srcW <= 0.0 || srcH <= 0.0) { return; }
	const sx: float32[] = [0.0, n.borderL, srcW - n.borderR, srcW];
	const sy: float32[] = [0.0, n.borderT, srcH - n.borderB, srcH];
	const dx: float32[] = [0.0, n.borderL, n.w - n.borderR, n.w];
	const dy: float32[] = [0.0, n.borderT, n.h - n.borderB, n.h];
	const du: float32 = t.u1 - t.u0;
	const dv: float32 = t.v1 - t.v0;
	let cj: int32 = 0;
	while (cj < 3) {
		let ci: int32 = 0;
		while (ci < 3) {
			const u0: float32 = t.u0 + (sx[ci] / srcW) * du;
			const u1: float32 = t.u0 + (sx[ci + 1] / srcW) * du;
			const v0: float32 = t.v0 + (sy[cj] / srcH) * dv;
			const v1: float32 = t.v0 + (sy[cj + 1] / srcH) * dv;
			const a = vec2(dx[ci], dy[cj]) * world;
			const b = vec2(dx[ci + 1], dy[cj]) * world;
			const c = vec2(dx[ci + 1], dy[cj + 1]) * world;
			const d = vec2(dx[ci], dy[cj + 1]) * world;
			imageQuadUV(t.view, u0, v0, u1, v1, a, b, c, d, col, n.blend);
			ci = ci + 1;
		}
		cj = cj + 1;
	}
}

function fmin4(a: float32, b: float32, c: float32, d: float32): float32 {
	let m: float32 = a;
	if (b < m) { m = b; }
	if (c < m) { m = c; }
	if (d < m) { m = d; }
	return m;
}

function fmax4(a: float32, b: float32, c: float32, d: float32): float32 {
	let m: float32 = a;
	if (b > m) { m = b; }
	if (c > m) { m = c; }
	if (d > m) { m = d; }
	return m;
}

// Dirty is value-compared, not setter-tracked (this FP API has no setters): trs2d (sinf/cosf)
// runs only when the local transform changed; cachedWorld recomputes when local OR an ancestor
// changed. Walks all children incl. invisible — visibility is a draw-only concern.
export function sync(this n: Node2D, parentWorld: Transform2D, parentChanged: boolean): void {
	const localChanged: boolean = n.dirty || n.x != n.lastX || n.y != n.lastY || n.scaleX != n.lastSX || n.scaleY != n.lastSY || n.rotation != n.lastRot;
	if (localChanged) {
		n.cachedLocal = trs2d(n.x, n.y, n.rotation, n.scaleX, n.scaleY);
		n.lastX = n.x;
		n.lastY = n.y;
		n.lastSX = n.scaleX;
		n.lastSY = n.scaleY;
		n.lastRot = n.rotation;
		n.dirty = false;
	}
	const worldChanged: boolean = localChanged || parentChanged;
	if (worldChanged) {
		n.cachedWorld = parentWorld * n.cachedLocal;
	}
	if (n.kind === DrawKind.Label) {
		const textChanged: boolean = n.textDirty || n.size != n.lastSize || n.align != n.lastAlign
			|| n.letterSpacing != n.lastLetterSpacing || n.lineSpacing != n.lastLineSpacing
			|| n.maxWidth != n.lastMaxWidth || !n.text.equals(n.lastText);
		if (textChanged) {
			n.glyphCache = layoutText(n.size, n.text, n.align, n.letterSpacing, n.lineSpacing, n.maxWidth);
			n.lastText = n.text;
			n.lastSize = n.size;
			n.lastAlign = n.align;
			n.lastLetterSpacing = n.letterSpacing;
			n.lastLineSpacing = n.lineSpacing;
			n.lastMaxWidth = n.maxWidth;
			n.textDirty = false;
		}
	}
	for (const ch of n.children) {
		ch.sync(n.cachedWorld, worldChanged);
	}
}

function emitNode(n: Node2D, world: Transform2D, na: float32, col: Color, tl: Vec2, tr: Vec2, br: Vec2, bl: Vec2): void {
	setEffect(n.colorMatrix, n.colorAdd, n.colorKey);
	setSmooth(n.smooth);
	if (n.kind === DrawKind.Rect) {
		fillQuad(tl, tr, br, bl, col, n.blend);
	} else if (n.kind === DrawKind.Sprite) {
		imageQuad(n.sheet, tl, tr, br, bl, col, n.blend);
	} else if (n.kind === DrawKind.Anim) {
		const len: int32 = n.frames.length as int32;
		if (len > 0) {
			const fi: int32 = ((n.clock * n.fps) as int32) % len;
			imageQuad(n.frames[fi], tl, tr, br, bl, col, n.blend);
		}
	} else if (n.kind === DrawKind.Label) {
		drawGlyphCache(world, n.glyphCache, col, n.blend);
	} else if (n.kind === DrawKind.Graphics) {
		// mesh: packed 8 floats/vertex (x y u v r g b a), 3 verts per triangle = 24-float stride.
		const mv = n.mesh;
		const total: int32 = mv.length as int32;
		let i: int32 = 0;
		while (i + 24 <= total) {
			const pa = vec2(mv[i], mv[i + 1]) * world;
			const ca = rgba(mv[i + 4], mv[i + 5], mv[i + 6], mv[i + 7] * na);
			const pb = vec2(mv[i + 8], mv[i + 9]) * world;
			const cb = rgba(mv[i + 12], mv[i + 13], mv[i + 14], mv[i + 15] * na);
			const pc = vec2(mv[i + 16], mv[i + 17]) * world;
			const cc = rgba(mv[i + 20], mv[i + 21], mv[i + 22], mv[i + 23] * na);
			fillTriTex(n.gfxView, pa, mv[i + 2], mv[i + 3], ca, pb, mv[i + 10], mv[i + 11], cb, pc, mv[i + 18], mv[i + 19], cc, n.blend);
			i = i + 24;
		}
	} else if (n.kind === DrawKind.ScaleGrid) {
		renderScaleGrid(n, world, col);
	}
}

// Walk the synced tree (no transform recompute). visible=false skips the whole subtree;
// off-screen nodes skip their own emit but children still recurse (no subtree cull).
export function draw(this n: Node2D, a: float32, vw: float32, vh: float32): void {
	if (!n.visible) { return; }
	const world = n.cachedWorld;
	const na: float32 = a * n.alpha;
	const col = rgba(n.color.r, n.color.g, n.color.b, n.color.a * na);
	const px: float32 = n.pivotX;
	const py: float32 = n.pivotY;
	const tl = vec2(-px, -py) * world;
	const tr = vec2(n.w - px, -py) * world;
	const br = vec2(n.w - px, n.h - py) * world;
	const bl = vec2(-px, n.h - py) * world;
	// Graphics/Label hold content outside the (w,h) box (mesh/glyphs), so they can't cull on it yet.
	const cullable: boolean = n.kind !== DrawKind.Graphics && n.kind !== DrawKind.Label;
	const onscreen: boolean = !cullable
		|| (fmax4(tl.x, tr.x, br.x, bl.x) >= 0.0 && fmin4(tl.x, tr.x, br.x, bl.x) <= vw
			&& fmax4(tl.y, tr.y, br.y, bl.y) >= 0.0 && fmin4(tl.y, tr.y, br.y, bl.y) <= vh);
	if (onscreen) {
		emitNode(n, world, na, col, tl, tr, br, bl);
	}
	const masking: boolean = n.kind === DrawKind.Mask;
	if (masking) {
		pushClip(fmin4(tl.x, tr.x, br.x, bl.x), fmin4(tl.y, tr.y, br.y, bl.y),
			fmax4(tl.x, tr.x, br.x, bl.x), fmax4(tl.y, tr.y, br.y, bl.y));
	}
	if (n.childrenDirty) { sortByZ(n.children); n.childrenDirty = false; }
	for (const ch of n.children) {
		ch.draw(na, vw, vh);
	}
	if (masking) {
		popClip();
	}
}
