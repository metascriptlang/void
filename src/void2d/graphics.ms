// Void 2D Graphics — h2d.Graphics-style vector drawing as a RETAINED mesh on a
// DrawKind.Graphics node. Builder methods append triangles in LOCAL space to n.mesh
// (packed 6 floats/vertex: x y r g b a, 3 verts/tri); node.render transforms them
// through the world matrix each frame. Fills use the white view (no texture).
// Limits: fills triangulate by fan (CONVEX only — pre-split concave); strokes are
// independent butt-cap segments (no miter/round joins — sharp corners gap).

import { Node2D } from "./node";
import { Vec2, Color, vec2 } from "./types";
import { sinf, cosf, sqrtf } from "../math/mat4";

const TAU: float32 = 6.2831853;
const CIRCLE_MAX_SEG: int32 = 64;
const DEGENERATE_LEN: float32 = 0.0001;

function vtx(n: Node2D, x: float32, y: float32, c: Color): void {
	n.mesh.push(x);
	n.mesh.push(y);
	n.mesh.push(c.r);
	n.mesh.push(c.g);
	n.mesh.push(c.b);
	n.mesh.push(c.a);
}

function tri(n: Node2D, a: Vec2, b: Vec2, c: Vec2, col: Color): void {
	vtx(n, a.x, a.y, col);
	vtx(n, b.x, b.y, col);
	vtx(n, c.x, c.y, col);
}

export function clear(this g: Node2D): Node2D {
	g.mesh = [];
	return g;
}

export function fillTriangle(this g: Node2D, a: Vec2, b: Vec2, c: Vec2, color: Color): Node2D {
	tri(g, a, b, c, color);
	return g;
}

export function fillRect(this g: Node2D, x: float32, y: float32, w: float32, h: float32, color: Color): Node2D {
	const tl = vec2(x, y);
	const tr = vec2(x + w, y);
	const br = vec2(x + w, y + h);
	const bl = vec2(x, y + h);
	tri(g, tl, tr, br, color);
	tri(g, tl, br, bl, color);
	return g;
}

export function fillConvex(this g: Node2D, pts: Vec2[], color: Color): Node2D {
	const m: int32 = pts.length as int32;
	let i: int32 = 1;
	while (i + 1 < m) {
		tri(g, pts[0], pts[i], pts[i + 1], color);
		i = i + 1;
	}
	return g;
}

export function fillCircle(this g: Node2D, cx: float32, cy: float32, r: float32, color: Color): Node2D {
	let seg: int32 = (r as int32) / 2 + 8;
	if (seg > CIRCLE_MAX_SEG) { seg = CIRCLE_MAX_SEG; }
	const step: float32 = TAU / (seg as float32);
	const center = vec2(cx, cy);
	let i: int32 = 0;
	while (i < seg) {
		const a0: float32 = step * (i as float32);
		const a1: float32 = step * ((i + 1) as float32);
		const p0 = vec2(cx + cosf(a0) * r, cy + sinf(a0) * r);
		const p1 = vec2(cx + cosf(a1) * r, cy + sinf(a1) * r);
		tri(g, center, p0, p1, color);
		i = i + 1;
	}
	return g;
}

export function strokeLine(this g: Node2D, a: Vec2, b: Vec2, width: float32, color: Color): Node2D {
	const dx: float32 = b.x - a.x;
	const dy: float32 = b.y - a.y;
	const len: float32 = sqrtf(dx * dx + dy * dy);
	if (len < DEGENERATE_LEN) { return g; }
	const hw: float32 = width * 0.5;
	const nx: float32 = -dy / len * hw;
	const ny: float32 = dx / len * hw;
	const p0 = vec2(a.x + nx, a.y + ny);
	const p1 = vec2(b.x + nx, b.y + ny);
	const p2 = vec2(b.x - nx, b.y - ny);
	const p3 = vec2(a.x - nx, a.y - ny);
	tri(g, p0, p1, p2, color);
	tri(g, p0, p2, p3, color);
	return g;
}

export function strokePoly(this g: Node2D, pts: Vec2[], width: float32, color: Color, closed: boolean): Node2D {
	const m: int32 = pts.length as int32;
	let i: int32 = 0;
	while (i + 1 < m) {
		g.strokeLine(pts[i], pts[i + 1], width, color);
		i = i + 1;
	}
	if (closed && m > 2) {
		g.strokeLine(pts[m - 1], pts[0], width, color);
	}
	return g;
}
