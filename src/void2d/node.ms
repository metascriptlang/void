// Void 2D scene — functional take on h2d (no classes/OOP): a data Node2D + a `kind`
// tag + extension methods (n.addChild / n.at / n.render). Node2D ≈ h2d.Object;
// kind = Group/Rect/Sprite/Label ≈ h2d.Bitmap/Text/Graphics; Tile ≈ h2d.Tile.
// (A discriminated-union payload hit a C-codegen issue when used as an interface field —
//  flat tag + fields is the robust shape; revisit the union later.)

import { fillQuad, imageQuad, drawTextXform, fillTri, setEffect, pushClip, popClip } from "./draw";
import { Color, Tile, Transform2D, BlendMode, vec2, rgba, tile, trs2d } from "./types";

export enum DrawKind { Group, Rect, Sprite, Label, Anim, Graphics, Mask }

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
	blend: BlendMode;
	zIndex: int32;
	w: float32;
	h: float32;
	color: Color;
	colorAdd: Color;
	colorMatrix: float32[];
	sheet: Tile;
	text: string;
	size: float32;
	frames: Tile[];
	fps: float32;
	clock: float32;
	mesh: float32[];
	children: Node2D[];
}

function base(kind: DrawKind): Node2D {
	return {
		kind: kind, x: 0.0, y: 0.0, scaleX: 1.0, scaleY: 1.0, rotation: 0.0, pivotX: 0.0, pivotY: 0.0, alpha: 1.0, visible: true, blend: BlendMode.Alpha, zIndex: 0,
		w: 0.0, h: 0.0, color: rgba(1.0, 1.0, 1.0, 1.0), colorAdd: rgba(0.0, 0.0, 0.0, 0.0), colorMatrix: [], sheet: tile(0, 0.0, 0.0), text: "", size: 0.0, frames: [], fps: 0.0, clock: 0.0, mesh: [], children: [],
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
// h2d.Anim — cycles `frames` (tiles, e.g. via Tile.sub) at `fps`; advanced by update(dt).
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
// h2d.Graphics — retained vector mesh (local-space tris); build via graphics.ms methods.
export function graphics(): Node2D {
	return base(DrawKind.Graphics);
}
// h2d.Mask — clips its children to a (w,h) rect (axis-aligned scissor of the world box).
export function mask(w: float32, h: float32): Node2D {
	const n = base(DrawKind.Mask);
	n.w = w;
	n.h = h;
	return n;
}

// ===== extension methods (reads OO, is FP) =====

export function addChild(this n: Node2D, c: Node2D): Node2D {
	n.children.push(c);
	return n;
}

export function at(this n: Node2D, x: float32, y: float32): Node2D {
	n.x = x;
	n.y = y;
	return n;
}

// h2d Object.sync — advance time-based state (Anim clocks) down the tree.
export function update(this n: Node2D, dt: float32): void {
	if (n.kind === DrawKind.Anim) {
		n.clock = n.clock + dt;
	}
	for (const ch of n.children) {
		ch.update(dt);
	}
}

// h2d.Layers — order children by zIndex; stable (equal zIndex keep insertion order),
// in-place insertion sort (≈O(n) once settled, no per-frame alloc).
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

export function render(this n: Node2D, parent: Transform2D, a: float32): void {
	if (!n.visible) { return; }
	const world = parent * trs2d(n.x, n.y, n.rotation, n.scaleX, n.scaleY);
	const na: float32 = a * n.alpha;
	const col = rgba(n.color.r, n.color.g, n.color.b, n.color.a * na);
	const px: float32 = n.pivotX;
	const py: float32 = n.pivotY;
	const tl = vec2(-px, -py) * world;
	const tr = vec2(n.w - px, -py) * world;
	const br = vec2(n.w - px, n.h - py) * world;
	const bl = vec2(-px, n.h - py) * world;
	setEffect(n.colorMatrix, n.colorAdd);
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
		drawTextXform(world, n.size, n.text, col, n.blend);
	} else if (n.kind === DrawKind.Graphics) {
		// mesh: packed 6 floats/vertex (x y r g b a), 3 verts per triangle = 18-float stride.
		const mv = n.mesh;
		const total: int32 = mv.length as int32;
		let i: int32 = 0;
		while (i + 18 <= total) {
			const pa = vec2(mv[i], mv[i + 1]) * world;
			const ca = rgba(mv[i + 2], mv[i + 3], mv[i + 4], mv[i + 5] * na);
			const pb = vec2(mv[i + 6], mv[i + 7]) * world;
			const cb = rgba(mv[i + 8], mv[i + 9], mv[i + 10], mv[i + 11] * na);
			const pc = vec2(mv[i + 12], mv[i + 13]) * world;
			const cc = rgba(mv[i + 14], mv[i + 15], mv[i + 16], mv[i + 17] * na);
			fillTri(pa, ca, pb, cb, pc, cc, n.blend);
			i = i + 18;
		}
	}
	const masking: boolean = n.kind === DrawKind.Mask;
	if (masking) {
		pushClip(fmin4(tl.x, tr.x, br.x, bl.x), fmin4(tl.y, tr.y, br.y, bl.y),
			fmax4(tl.x, tr.x, br.x, bl.x), fmax4(tl.y, tr.y, br.y, bl.y));
	}
	sortByZ(n.children);
	for (const ch of n.children) {
		ch.render(world, na);
	}
	if (masking) {
		popClip();
	}
}
