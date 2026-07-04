// Void 2D Graphics — h2d.Graphics-style vector drawing as a RETAINED mesh on a
// DrawKind.Graphics node. Builder methods append triangles in LOCAL space to n.mesh
// (packed 6 floats/vertex: x y r g b a, 3 verts/tri); node.render transforms them
// through the world matrix each frame. Fills use the white view (no texture).
// fillPolygon handles concave shapes (ear-clip); strokePoly uses miter joins with a
// bevel-style clamp at sharp angles (correct for any alpha — no overlapping geometry).

import { Node2D } from "./node";
import { Vec2, Color, Tile, vec2, rgba } from "./types";
import { sinf, cosf, sqrtf } from "../math/mat4";

const TAU: float32 = 6.2831853;
const CIRCLE_MAX_SEG: int32 = 64;
const DEGENERATE_LEN: float32 = 0.0001;
const MITER_LIMIT: float32 = 4.0;

function vtx(n: Node2D, x: float32, y: float32, u: float32, v: float32, c: Color): void {
	n.mesh.push(x);
	n.mesh.push(y);
	n.mesh.push(u);
	n.mesh.push(v);
	n.mesh.push(c.r);
	n.mesh.push(c.g);
	n.mesh.push(c.b);
	n.mesh.push(c.a);
	n.gfxDirty = true;
}

function tri(n: Node2D, a: Vec2, b: Vec2, c: Vec2, col: Color): void {
	vtx(n, a.x, a.y, 0.0, 0.0, col);
	vtx(n, b.x, b.y, 0.0, 0.0, col);
	vtx(n, c.x, c.y, 0.0, 0.0, col);
}

function triUV(n: Node2D, a: Vec2, ua: float32, va: float32, b: Vec2, ub: float32, vb: float32, c: Vec2, uc: float32, vc: float32, col: Color): void {
	vtx(n, a.x, a.y, ua, va, col);
	vtx(n, b.x, b.y, ub, vb, col);
	vtx(n, c.x, c.y, uc, vc, col);
}

function lerpColor(a: Color, b: Color, t: float32): Color {
	return rgba(a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t, a.a + (b.a - a.a) * t);
}

function triCol(n: Node2D, a: Vec2, ca: Color, b: Vec2, cb: Color, c: Vec2, cc: Color): void {
	vtx(n, a.x, a.y, 0.0, 0.0, ca);
	vtx(n, b.x, b.y, 0.0, 0.0, cb);
	vtx(n, c.x, c.y, 0.0, 0.0, cc);
}

function gradColorAt(p: Vec2, ax: float32, ay: float32, minP: float32, span: float32, c0: Color, c1: Color): Color {
	let t: float32 = span > DEGENERATE_LEN ? (p.x * ax + p.y * ay - minP) / span : 0.0;
	if (t < 0.0) { t = 0.0; }
	if (t > 1.0) { t = 1.0; }
	return lerpColor(c0, c1, t);
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

// left-hand unit normal of segment a→b (zero vector if degenerate).
function segNormal(ax: float32, ay: float32, bx: float32, by: float32): Vec2 {
	const dx: float32 = bx - ax;
	const dy: float32 = by - ay;
	const len: float32 = sqrtf(dx * dx + dy * dy);
	if (len < DEGENERATE_LEN) { return vec2(0.0, 0.0); }
	return vec2(-dy / len, dx / len);
}

export function clear(this g: Node2D): Node2D {
	g.mesh = [];
	g.gfxView = 0;
	g.gfxDirty = true;
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

function polyArea2(pts: Vec2[]): float32 {
	const m: int32 = pts.length as int32;
	let a: float32 = 0.0;
	let i: int32 = 0;
	while (i < m) {
		const j: int32 = (i + 1) % m;
		a = a + pts[i].x * pts[j].y - pts[j].x * pts[i].y;
		i = i + 1;
	}
	return a;
}

function cross3(ax: float32, ay: float32, bx: float32, by: float32, cx: float32, cy: float32): float32 {
	return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
}

function pointInTri(px: float32, py: float32, ax: float32, ay: float32, bx: float32, by: float32, cx: float32, cy: float32): boolean {
	const d1: float32 = cross3(ax, ay, bx, by, px, py);
	const d2: float32 = cross3(bx, by, cx, cy, px, py);
	const d3: float32 = cross3(cx, cy, ax, ay, px, py);
	const hasNeg: boolean = d1 < 0.0 || d2 < 0.0 || d3 < 0.0;
	const hasPos: boolean = d1 > 0.0 || d2 > 0.0 || d3 > 0.0;
	return !(hasNeg && hasPos);
}

function isEar(pts: Vec2[], next: int32[], u: int32, v: int32, w: int32, ccw: boolean): boolean {
	const cr: float32 = cross3(pts[u].x, pts[u].y, pts[v].x, pts[v].y, pts[w].x, pts[w].y);
	if (ccw) { if (cr <= 0.0) { return false; } } else { if (cr >= 0.0) { return false; } }
	let p: int32 = next[w];
	while (p != u) {
		if (pointInTri(pts[p].x, pts[p].y, pts[u].x, pts[u].y, pts[v].x, pts[v].y, pts[w].x, pts[w].y)) {
			return false;
		}
		p = next[p];
	}
	return true;
}

// ear-clipping triangulation → flat index triples (handles CONCAVE simple polygons;
// self-intersecting outlines are undefined).
function triangulate(pts: Vec2[]): int32[] {
	const out: int32[] = [];
	const n: int32 = pts.length as int32;
	if (n < 3) { return out; }
	const prev: int32[] = [];
	const next: int32[] = [];
	let i: int32 = 0;
	while (i < n) {
		prev.push((i - 1 + n) % n);
		next.push((i + 1) % n);
		i = i + 1;
	}
	const ccw: boolean = polyArea2(pts) > 0.0;
	let remaining: int32 = n;
	let v: int32 = 0;
	let guard: int32 = 0;
	while (remaining > 3) {
		const u: int32 = prev[v];
		const w: int32 = next[v];
		if (isEar(pts, next, u, v, w, ccw)) {
			out.push(u);
			out.push(v);
			out.push(w);
			next[u] = w;
			prev[w] = u;
			remaining = remaining - 1;
			guard = 0;
			v = u;
		} else {
			v = next[v];
			guard = guard + 1;
			if (guard > remaining) { return out; }
		}
	}
	out.push(prev[v]);
	out.push(v);
	out.push(next[v]);
	return out;
}

// h2d.Graphics arbitrary solid fill (convex shapes can use the cheaper fillConvex fan).
export function fillPolygon(this g: Node2D, pts: Vec2[], color: Color): Node2D {
	const idx: int32[] = triangulate(pts);
	const tc: int32 = idx.length as int32;
	let k: int32 = 0;
	while (k + 3 <= tc) {
		tri(g, pts[idx[k]], pts[idx[k + 1]], pts[idx[k + 2]], color);
		k = k + 3;
	}
	return g;
}

// h2d.Graphics.beginGradientFill(Linear) — color lerps c0→c1 along `angle` (rad; 0 = +x)
// across the shape's projected extent. Concave-safe (ear-clip); color is per-vertex.
export function fillGradientPolygon(this g: Node2D, pts: Vec2[], c0: Color, c1: Color, angle: float32): Node2D {
	const m: int32 = pts.length as int32;
	if (m < 3) { return g; }
	const ax: float32 = cosf(angle);
	const ay: float32 = sinf(angle);
	let minP: float32 = pts[0].x * ax + pts[0].y * ay;
	let maxP: float32 = minP;
	let i: int32 = 1;
	while (i < m) {
		const pp: float32 = pts[i].x * ax + pts[i].y * ay;
		if (pp < minP) { minP = pp; }
		if (pp > maxP) { maxP = pp; }
		i = i + 1;
	}
	const span: float32 = maxP - minP;
	const idx: int32[] = triangulate(pts);
	const tc: int32 = idx.length as int32;
	let k: int32 = 0;
	while (k + 3 <= tc) {
		const pa = pts[idx[k]];
		const pb = pts[idx[k + 1]];
		const pc = pts[idx[k + 2]];
		triCol(g, pa, gradColorAt(pa, ax, ay, minP, span, c0, c1),
			pb, gradColorAt(pb, ax, ay, minP, span, c0, c1),
			pc, gradColorAt(pc, ax, ay, minP, span, c0, c1));
		k = k + 3;
	}
	return g;
}

// h2d.Graphics.beginGradientFill(Linear) over an axis-aligned rect.
export function fillGradientRect(this g: Node2D, x: float32, y: float32, w: float32, h: float32, c0: Color, c1: Color, angle: float32): Node2D {
	const pts: Vec2[] = [vec2(x, y), vec2(x + w, y), vec2(x + w, y + h), vec2(x, y + h)];
	return g.fillGradientPolygon(pts, c0, c1, angle);
}

// h2d.Graphics.beginGradientFill(Radial) — fan with center=cInner, rim=cOuter.
export function fillRadialGradient(this g: Node2D, cx: float32, cy: float32, r: float32, cInner: Color, cOuter: Color): Node2D {
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
		triCol(g, center, cInner, p0, cOuter, p1, cOuter);
		i = i + 1;
	}
	return g;
}

// h2d.Graphics.drawTile — textured rect (tile mapped to the rect). Sets the node's view.
export function fillTexRect(this g: Node2D, t: Tile, x: float32, y: float32, w: float32, h: float32, color: Color): Node2D {
	g.gfxView = t.view;
	const a = vec2(x, y);
	const b = vec2(x + w, y);
	const c = vec2(x + w, y + h);
	const d = vec2(x, y + h);
	triUV(g, a, t.u0, t.v0, b, t.u1, t.v0, c, t.u1, t.v1, color);
	triUV(g, a, t.u0, t.v0, c, t.u1, t.v1, d, t.u0, t.v1, color);
	return g;
}

// h2d.Graphics.beginTileFill — fill an arbitrary shape with a tile; UV maps the tile
// across the shape from (originX,originY) over (tileW,tileH) px (REPEAT sampler tiles it).
// One view per Graphics node: don't mix textured + solid fills on the same node.
export function fillTexPolygon(this g: Node2D, t: Tile, pts: Vec2[], originX: float32, originY: float32, tileW: float32, tileH: float32, color: Color): Node2D {
	g.gfxView = t.view;
	const idx: int32[] = triangulate(pts);
	const tc: int32 = idx.length as int32;
	const du: float32 = t.u1 - t.u0;
	const dv: float32 = t.v1 - t.v0;
	let k: int32 = 0;
	while (k + 3 <= tc) {
		const pa = pts[idx[k]];
		const pb = pts[idx[k + 1]];
		const pc = pts[idx[k + 2]];
		triUV(g, pa, t.u0 + (pa.x - originX) / tileW * du, t.v0 + (pa.y - originY) / tileH * dv,
			pb, t.u0 + (pb.x - originX) / tileW * du, t.v0 + (pb.y - originY) / tileH * dv,
			pc, t.u0 + (pc.x - originX) / tileW * du, t.v0 + (pc.y - originY) / tileH * dv, color);
		k = k + 3;
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
	if (m < 2) { return g; }
	const hw: float32 = width * 0.5;
	// per-vertex outer offsets: butt at open ends, miter (clamped) at joints.
	const lx: float32[] = [];
	const ly: float32[] = [];
	const rx: float32[] = [];
	const ry: float32[] = [];
	let i: int32 = 0;
	while (i < m) {
		const hasPrev: boolean = closed || i > 0;
		const hasNext: boolean = closed || i < m - 1;
		let nx: float32 = 0.0;
		let ny: float32 = 0.0;
		if (hasPrev && hasNext) {
			const pi: int32 = (i - 1 + m) % m;
			const ni: int32 = (i + 1) % m;
			const n1 = segNormal(pts[pi].x, pts[pi].y, pts[i].x, pts[i].y);
			const n2 = segNormal(pts[i].x, pts[i].y, pts[ni].x, pts[ni].y);
			let mxn: float32 = n1.x + n2.x;
			let myn: float32 = n1.y + n2.y;
			const ml: float32 = sqrtf(mxn * mxn + myn * myn);
			if (ml < DEGENERATE_LEN) { mxn = n1.x; myn = n1.y; }
			else { mxn = mxn / ml; myn = myn / ml; }
			const d: float32 = mxn * n1.x + myn * n1.y;
			let scale: float32 = d > 0.1 ? 1.0 / d : MITER_LIMIT;
			if (scale > MITER_LIMIT) { scale = MITER_LIMIT; }
			nx = mxn * hw * scale;
			ny = myn * hw * scale;
		} else if (hasNext) {
			const ni: int32 = (i + 1) % m;
			const n2 = segNormal(pts[i].x, pts[i].y, pts[ni].x, pts[ni].y);
			nx = n2.x * hw;
			ny = n2.y * hw;
		} else {
			const pi: int32 = (i - 1 + m) % m;
			const n1 = segNormal(pts[pi].x, pts[pi].y, pts[i].x, pts[i].y);
			nx = n1.x * hw;
			ny = n1.y * hw;
		}
		lx.push(pts[i].x + nx);
		ly.push(pts[i].y + ny);
		rx.push(pts[i].x - nx);
		ry.push(pts[i].y - ny);
		i = i + 1;
	}
	const segs: int32 = closed ? m : (m - 1);
	let s: int32 = 0;
	while (s < segs) {
		const a: int32 = s;
		const b: int32 = (s + 1) % m;
		tri(g, vec2(lx[a], ly[a]), vec2(rx[a], ry[a]), vec2(rx[b], ry[b]), color);
		tri(g, vec2(lx[a], ly[a]), vec2(rx[b], ry[b]), vec2(lx[b], ly[b]), color);
		s = s + 1;
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
