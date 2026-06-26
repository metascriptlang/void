// Void 2D Graphics — h2d.Graphics-style vector drawing as a RETAINED mesh on a
// DrawKind.Graphics node. Builder methods append triangles in LOCAL space to n.mesh
// (packed 6 floats/vertex: x y r g b a, 3 verts/tri); node.render transforms them
// through the world matrix each frame. Fills use the white view (no texture).
// Limits: fills triangulate by fan (CONVEX only — pre-split concave); strokes are
// butt-cap segments with round joints (opaque only — translucent strokes keep corner gaps).

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

function arcSegs(r: float32, sweep: float32): int32 {
	const s: float32 = sweep < 0.0 ? -sweep : sweep;
	let n: int32 = ((r * s * 0.3) as int32) + 3;
	if (n > CIRCLE_MAX_SEG) { n = CIRCLE_MAX_SEG; }
	return n;
}

function cornerArc(n: Node2D, pts: Vec2[], ccx: float32, ccy: float32, r: float32, a0: float32, seg: int32): void {
	let i: int32 = 0;
	while (i <= seg) {
		const a: float32 = a0 + TAU * 0.25 * ((i as float32) / (seg as float32));
		pts.push(vec2(ccx + cosf(a) * r, ccy + sinf(a) * r));
		i = i + 1;
	}
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
	// round joints fill the wedge between consecutive butt-cap segments; opaque only,
	// since translucent discs would double-blend over the segment ends.
	if (width > 1.0 && color.a >= 1.0) {
		const jr: float32 = width * 0.5;
		let j: int32 = closed ? 0 : 1;
		const jend: int32 = closed ? m : (m - 1);
		while (j < jend) {
			g.fillCircle(pts[j].x, pts[j].y, jr, color);
			j = j + 1;
		}
	}
	return g;
}

export function strokeRect(this g: Node2D, x: float32, y: float32, w: float32, h: float32, width: float32, color: Color): Node2D {
	const pts: Vec2[] = [vec2(x, y), vec2(x + w, y), vec2(x + w, y + h), vec2(x, y + h)];
	return g.strokePoly(pts, width, color, true);
}

// h2d.Graphics.drawRoundedRect — convex perimeter (4 corner arcs + edges) → fan fill.
export function fillRoundedRect(this g: Node2D, x: float32, y: float32, w: float32, h: float32, radius: float32, color: Color): Node2D {
	const maxR: float32 = (w < h ? w : h) * 0.5;
	let r: float32 = radius;
	if (r > maxR) { r = maxR; }
	if (r <= 0.0) { return g.fillRect(x, y, w, h, color); }
	const seg: int32 = arcSegs(r, TAU * 0.25);
	const pts: Vec2[] = [];
	cornerArc(g, pts, x + r,     y + r,     r, TAU * 0.5,  seg);
	cornerArc(g, pts, x + w - r, y + r,     r, TAU * 0.75, seg);
	cornerArc(g, pts, x + w - r, y + h - r, r, 0.0,        seg);
	cornerArc(g, pts, x + r,     y + h - r, r, TAU * 0.25, seg);
	return g.fillConvex(pts, color);
}

// h2d.Graphics.drawEllipse — fan from centre with independent x/y radii.
export function fillEllipse(this g: Node2D, cx: float32, cy: float32, rx: float32, ry: float32, color: Color): Node2D {
	const rr: float32 = rx > ry ? rx : ry;
	const seg: int32 = arcSegs(rr, TAU);
	const step: float32 = TAU / (seg as float32);
	const center = vec2(cx, cy);
	let i: int32 = 0;
	while (i < seg) {
		const a0: float32 = step * (i as float32);
		const a1: float32 = step * ((i + 1) as float32);
		const p0 = vec2(cx + cosf(a0) * rx, cy + sinf(a0) * ry);
		const p1 = vec2(cx + cosf(a1) * rx, cy + sinf(a1) * ry);
		tri(g, center, p0, p1, color);
		i = i + 1;
	}
	return g;
}

// h2d.Graphics.drawPie — fan slice over [angleStart, angleStart+angleLength] (radians).
export function fillPie(this g: Node2D, cx: float32, cy: float32, r: float32, angleStart: float32, angleLength: float32, color: Color): Node2D {
	const seg: int32 = arcSegs(r, angleLength);
	const step: float32 = angleLength / (seg as float32);
	const center = vec2(cx, cy);
	let i: int32 = 0;
	while (i < seg) {
		const a0: float32 = angleStart + step * (i as float32);
		const a1: float32 = angleStart + step * ((i + 1) as float32);
		const p0 = vec2(cx + cosf(a0) * r, cy + sinf(a0) * r);
		const p1 = vec2(cx + cosf(a1) * r, cy + sinf(a1) * r);
		tri(g, center, p0, p1, color);
		i = i + 1;
	}
	return g;
}

// h2d.Graphics.drawPieInner — annular sector (ring slice) between innerR and outerR.
export function fillRing(this g: Node2D, cx: float32, cy: float32, outerR: float32, innerR: float32, angleStart: float32, angleLength: float32, color: Color): Node2D {
	const seg: int32 = arcSegs(outerR, angleLength);
	const step: float32 = angleLength / (seg as float32);
	let i: int32 = 0;
	while (i < seg) {
		const a0: float32 = angleStart + step * (i as float32);
		const a1: float32 = angleStart + step * ((i + 1) as float32);
		const o0 = vec2(cx + cosf(a0) * outerR, cy + sinf(a0) * outerR);
		const o1 = vec2(cx + cosf(a1) * outerR, cy + sinf(a1) * outerR);
		const i0 = vec2(cx + cosf(a0) * innerR, cy + sinf(a0) * innerR);
		const i1 = vec2(cx + cosf(a1) * innerR, cy + sinf(a1) * innerR);
		tri(g, i0, o0, o1, color);
		tri(g, i0, o1, i1, color);
		i = i + 1;
	}
	return g;
}

// h2d.Graphics.curveTo — quadratic Bézier flattened to points (compose with stroke/fill).
export function quadBezier(a: Vec2, ctrl: Vec2, b: Vec2, segments: int32): Vec2[] {
	let seg: int32 = segments;
	if (seg < 1) { seg = 1; }
	const pts: Vec2[] = [];
	let i: int32 = 0;
	while (i <= seg) {
		const t: float32 = (i as float32) / (seg as float32);
		const u: float32 = 1.0 - t;
		const x: float32 = u * u * a.x + 2.0 * u * t * ctrl.x + t * t * b.x;
		const y: float32 = u * u * a.y + 2.0 * u * t * ctrl.y + t * t * b.y;
		pts.push(vec2(x, y));
		i = i + 1;
	}
	return pts;
}

// h2d.Graphics.cubicCurveTo — cubic Bézier flattened to points.
export function cubicBezier(a: Vec2, c1: Vec2, c2: Vec2, b: Vec2, segments: int32): Vec2[] {
	let seg: int32 = segments;
	if (seg < 1) { seg = 1; }
	const pts: Vec2[] = [];
	let i: int32 = 0;
	while (i <= seg) {
		const t: float32 = (i as float32) / (seg as float32);
		const u: float32 = 1.0 - t;
		const x: float32 = u * u * u * a.x + 3.0 * u * u * t * c1.x + 3.0 * u * t * t * c2.x + t * t * t * b.x;
		const y: float32 = u * u * u * a.y + 3.0 * u * u * t * c1.y + 3.0 * u * t * t * c2.y + t * t * t * b.y;
		pts.push(vec2(x, y));
		i = i + 1;
	}
	return pts;
}
