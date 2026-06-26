// Void 2D value types — small POD structs (value semantics), MetaScript-side only.
// At the C/FFI boundary the draw wrappers unpack these into flat floats.

import { sinf, cosf } from "../math/mat4";

export struct Vec2 {
	x: float32;
	y: float32;
}

export struct Color {
	r: float32;
	g: float32;
	b: float32;
	a: float32;
}

export function vec2(x: float32, y: float32): Vec2 {
	return { x: x, y: y };
}

export function rgba(r: float32, g: float32, b: float32, a: float32): Color {
	return { r: r, g: g, b: b, a: a };
}

// h2d.BlendMode — fixed-function blend (one sokol pipeline per mode). Order MUST match
// the pipeline table in batcher.c (Alpha=0..None=4).
export enum BlendMode { Alpha, Add, Multiply, Screen, None }

// h2d.Tile — a texture region (view + UV rect + draw size). texW/texH = backing texture
// pixel size, so `.sub` can turn a pixel sub-rect into UVs.
export struct Tile {
	view: uint32;
	u0: float32;
	v0: float32;
	u1: float32;
	v1: float32;
	w: float32;
	h: float32;
	texW: float32;
	texH: float32;
}

export function tile(view: uint32, w: float32, h: float32): Tile {
	return { view: view, u0: 0.0, v0: 0.0, u1: 1.0, v1: 1.0, w: w, h: h, texW: w, texH: h };
}

// h2d.Tile.sub — a sub-region (pixel coords on the same texture) → new Tile with UVs.
export function sub(this t: Tile, x: float32, y: float32, w: float32, h: float32): Tile {
	return {
		view: t.view,
		u0: x / t.texW, v0: y / t.texH,
		u1: (x + w) / t.texW, v1: (y + h) / t.texH,
		w: w, h: h, texW: t.texW, texH: t.texH,
	};
}

// h2d.Tile.flipX / flipY — mirror the UV rect (returns a new Tile, value semantics).
export function flipX(this t: Tile): Tile {
	return { view: t.view, u0: t.u1, v0: t.v0, u1: t.u0, v1: t.v1, w: t.w, h: t.h, texW: t.texW, texH: t.texH };
}
export function flipY(this t: Tile): Tile {
	return { view: t.view, u0: t.u0, v0: t.v1, u1: t.u1, v1: t.v0, w: t.w, h: t.h, texW: t.texW, texH: t.texH };
}

// 2D affine transform [a c tx ; b d ty] — point (x,y) → (a·x + c·y + tx, b·x + d·y + ty).
export struct Transform2D {
	a: float32;
	b: float32;
	c: float32;
	d: float32;
	tx: float32;
	ty: float32;
}

export function identity2d(): Transform2D {
	return { a: 1.0, b: 0.0, c: 0.0, d: 1.0, tx: 0.0, ty: 0.0 };
}

// compose: parent ∘ local (apply n first, then m). `world = parent * local`
export function `*`(this m: Transform2D, n: Transform2D): Transform2D {
	return {
		a: m.a * n.a + m.c * n.b,
		b: m.b * n.a + m.d * n.b,
		c: m.a * n.c + m.c * n.d,
		d: m.b * n.c + m.d * n.d,
		tx: m.a * n.tx + m.c * n.ty + m.tx,
		ty: m.b * n.tx + m.d * n.ty + m.ty,
	};
}

// apply: transform a point. `corner = vec2(x, y) * world`  (point on the left → no clash with compose)
export function `*`(this p: Vec2, m: Transform2D): Vec2 {
	return vec2(m.a * p.x + m.c * p.y + m.tx, m.b * p.x + m.d * p.y + m.ty);
}

// translate(x,y) ∘ rotate(rot) ∘ scale(sx,sy)
export function trs2d(x: float32, y: float32, rot: float32, sx: float32, sy: float32): Transform2D {
	const co: float32 = cosf(rot);
	const si: float32 = sinf(rot);
	return { a: co * sx, b: si * sx, c: -si * sy, d: co * sy, tx: x, ty: y };
}

// h2d.Camera — a view transform over the whole scene. (x,y) is the world point shown at
// the viewport anchor (anchorX/Y as 0..1 of framebuffer); zoom + rotation around it.
// Defaults (x=y=0, zoom=1, anchor=0) → identity, so a scene with no camera move is unchanged.
export struct Camera {
	x: float32;
	y: float32;
	zoom: float32;
	rotation: float32;
	anchorX: float32;
	anchorY: float32;
}

export function camera(): Camera {
	return { x: 0.0, y: 0.0, zoom: 1.0, rotation: 0.0, anchorX: 0.0, anchorY: 0.0 };
}

// world → screen: translate(anchor px) ∘ rotate ∘ zoom ∘ translate(-x,-y)
export function viewMatrix(this c: Camera, fbW: float32, fbH: float32): Transform2D {
	return trs2d(c.anchorX * fbW, c.anchorY * fbH, c.rotation, c.zoom, c.zoom) * trs2d(-c.x, -c.y, 0.0, 1.0, 1.0);
}
