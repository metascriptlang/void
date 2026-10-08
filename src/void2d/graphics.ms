// Void 2D Graphics — h2d.Graphics-style vector drawing as a retained local-space mesh.
// Each vertex is x/y, u/v and rgba; an operation list preserves fill order while selecting
// texture, gradient or pattern state for contiguous vertex ranges.
// fillPolygon handles concave shapes (ear-clip); strokePoly uses miter joins with a
// bevel-style clamp at sharp angles (correct for any alpha — no overlapping geometry).

import { NodeRef, GraphicsMesh, DrawKind, Changed } from "./node";
import { Vec2, Color, Tile, vec2, rgba } from "./types";
import { GradientSpace } from "./gradient";
import { EDGE_FLOATS, FRINGE_HALF_WIDTH } from "./draw";
import { sinf, cosf, sqrtf } from "../math/mat4";

const TAU: float32 = 6.2831853;
const CIRCLE_MAX_SEG: int32 = 64;
const DEGENERATE_LEN: float32 = 0.0001;
const MITER_LIMIT: float32 = 4.0;
const white: Color = rgba(1.0, 1.0, 1.0, 1.0);
const NO_NORMAL: Vec2 = vec2(0.0, 0.0);

export enum GraphicsOpKind {
	Mesh,
	LinearGradient,
	RadialGradient,
	SlashPattern,
	CheckerPattern,
}

export const GRAPHICS_OP_FLOATS: int32 = 24;
export const GFX_OP_KIND: int32 = 0;
export const GFX_OP_VERTEX_OFFSET: int32 = 1;
export const GFX_OP_VERTEX_COUNT: int32 = 2;
export const GFX_OP_SPACE: int32 = 3;
export const GFX_OP_DITHER: int32 = 4;
export const GFX_OP_MIDDLE: int32 = 5;
export const GFX_OP_COLOR0: int32 = 8;
export const GFX_OP_COLOR1: int32 = 12;
export const GFX_OP_COLOR2: int32 = 16;
export const GFX_OP_PARAMS: int32 = 20;

struct UvMap {
	ux: float32;
	uy: float32;
	uc: float32;
	vx: float32;
	vy: float32;
	vc: float32;
}

const NO_UV: UvMap = { ux: 0.0, uy: 0.0, uc: 0.0, vx: 0.0, vy: 0.0, vc: 0.0 };

struct Corner {
	p: Vec2;
	before: Vec2;
	after: Vec2;
	limitBefore: float32;
	limitAfter: float32;
}

enum EdgeLimit {
	Parallel,
	Convex,
	Ring,
}

const EXACT_EDGE_WIDTHS_UP_TO: int32 = 256;

function pushMeshVertex(
	n: GraphicsMesh,
	x: float32,
	y: float32,
	u: float32,
	v: float32,
	c: Color,
): void {
	n.mesh.push(x);
	n.mesh.push(y);
	n.mesh.push(u);
	n.mesh.push(v);
	n.mesh.push(c.r);
	n.mesh.push(c.g);
	n.mesh.push(c.b);
	n.mesh.push(c.a);
	n.stale = true;
}

function rawVtx(n: GraphicsMesh, x: float32, y: float32, u: float32, v: float32, c: Color): void {
	pushMeshVertex(n, x, y, u, v, c);
	for (let k: int32 = 0; k < EDGE_FLOATS; k++) { n.edges.push(0.0 as float32); }
}

function beginMeshVertex(n: GraphicsMesh): int32 {
	const total: int32 = n.records.length as int32;
	let base: int32 = total - GRAPHICS_OP_FLOATS;
	if (base < 0 || (n.records[base + GFX_OP_KIND] as int32) != (GraphicsOpKind.Mesh as int32)) {
		base = total;
		for (let i: int32 = 0; i < GRAPHICS_OP_FLOATS; i++) { n.records.push(0.0 as float32); }
		n.records[base + GFX_OP_KIND] = (GraphicsOpKind.Mesh as int32) as float32;
		n.records[base + GFX_OP_VERTEX_OFFSET] = ((n.mesh.length as int32) / 8) as float32;
	}
	n.records[base + GFX_OP_VERTEX_COUNT] = n.records[base + GFX_OP_VERTEX_COUNT] + 1.0;
	return base;
}

function vtx(n: GraphicsMesh, x: float32, y: float32, u: float32, v: float32, c: Color): void {
	beginMeshVertex(n);
	rawVtx(n, x, y, u, v, c);
}
function tri(n: GraphicsMesh, a: Vec2, b: Vec2, c: Vec2, color: Color): void {
	vtx(n, a.x, a.y, 0.0, 0.0, color);
	vtx(n, b.x, b.y, 0.0, 0.0, color);
	vtx(n, c.x, c.y, 0.0, 0.0, color);
}

function mapU(map: UvMap, p: Vec2): float32 { return map.ux * p.x + map.uy * p.y + map.uc; }
function mapV(map: UvMap, p: Vec2): float32 { return map.vx * p.x + map.vy * p.y + map.vc; }

function plainVtx(n: GraphicsMesh, counted: boolean, p: Vec2, map: UvMap, c: Color): void {
	if (counted) { beginMeshVertex(n); }
	rawVtx(n, p.x, p.y, mapU(map, p), mapV(map, p), c);
}

function edgeVtx(
	n: GraphicsMesh,
	counted: boolean,
	corner: Corner,
	map: UvMap,
	c: Color,
	shift: float32,
): void {
	if (counted) { beginMeshVertex(n); }
	pushMeshVertex(n, corner.p.x, corner.p.y, mapU(map, corner.p), mapV(map, corner.p), c);
	n.edges.push(corner.before.x);
	n.edges.push(corner.before.y);
	n.edges.push(corner.after.x);
	n.edges.push(corner.after.y);
	n.edges.push(shift);
	n.edges.push(corner.limitBefore);
	n.edges.push(corner.limitAfter);
	n.edges.push(map.ux);
	n.edges.push(map.uy);
	n.edges.push(map.vx);
	n.edges.push(map.vy);
	n.fringed = true;
}

function transparent(c: Color): Color { return rgba(c.r, c.g, c.b, 0.0); }

function fringeQuad(
	n: GraphicsMesh,
	counted: boolean,
	a: Corner,
	b: Corner,
	map: UvMap,
	color: Color,
): void {
	const clear: Color = transparent(color);
	edgeVtx(n, counted, a, map, color, -FRINGE_HALF_WIDTH);
	edgeVtx(n, counted, a, map, clear, FRINGE_HALF_WIDTH);
	edgeVtx(n, counted, b, map, color, -FRINGE_HALF_WIDTH);
	edgeVtx(n, counted, a, map, clear, FRINGE_HALF_WIDTH);
	edgeVtx(n, counted, b, map, clear, FRINGE_HALF_WIDTH);
	edgeVtx(n, counted, b, map, color, -FRINGE_HALF_WIDTH);
}

function halfLength(a: Vec2, b: Vec2): float32 {
	const dx: float32 = b.x - a.x;
	const dy: float32 = b.y - a.y;
	return sqrtf(dx * dx + dy * dy) * 0.5;
}

function isNormal(v: Vec2): boolean { return v.x != 0.0 || v.y != 0.0; }

function loopStart(loopEnds: Readonly<Span<int32>>, k: int32): int32 {
	return k == 0 ? 0 : loopEnds[k - 1];
}

// A filled region bounded by `pts`: loop k ends before `loopEnds[k]`, a hole is wound against
// loop 0, and `tris` index `pts`. With antialias the body is drawn half a device pixel inside
// every edge and a fringe ramps coverage to zero half a pixel outside it.
function contourFill(
	n: GraphicsMesh,
	counted: boolean,
	pts: Readonly<Span<Vec2>>,
	loopEnds: Readonly<Span<int32>>,
	tris: Readonly<Span<int32>>,
	map: UvMap,
	color: Color,
	rule: EdgeLimit,
): void {
	const total: int32 = pts.length as int32;
	if (total < 3 || (loopEnds.length as int32) == 0) { return; }
	if (!n.antialias) {
		for (const k of tris) { plainVtx(n, counted, pts[k], map, color); }
		return;
	}
	let area: float32 = 0.0;
	const firstEnd: int32 = loopEnds[0];
	for (let i: int32 = 0; i < firstEnd; i++) {
		const j: int32 = i + 1 < firstEnd ? i + 1 : 0;
		area = area + pts[i].x * pts[j].y - pts[j].x * pts[i].y;
	}
	const outward: float32 = area > 0.0 ? -1.0 : 1.0;
	const edgeNormals: Vec2[] = [];
	const nextOf: int32[] = [];
	for (let k: int32 = 0; k < (loopEnds.length as int32); k++) {
		const start: int32 = loopStart(loopEnds, k);
		const end: int32 = loopEnds[k];
		for (let i: int32 = start; i < end; i++) {
			const j: int32 = i + 1 < end ? i + 1 : start;
			const left: Vec2 = segNormal(pts[i].x, pts[i].y, pts[j].x, pts[j].y);
			edgeNormals.push(vec2(left.x * outward, left.y * outward));
			nextOf.push(j);
		}
	}
	const edgeLimits: float32[] = edgeHalfWidths(pts, loopEnds, edgeNormals, rule);
	const corners: Corner[] = [];
	for (let k: int32 = 0; k < (loopEnds.length as int32); k++) {
		const start: int32 = loopStart(loopEnds, k);
		const end: int32 = loopEnds[k];
		const size: int32 = end - start;
		for (let i: int32 = start; i < end; i++) {
			let before: Vec2 = NO_NORMAL;
			let after: Vec2 = NO_NORMAL;
			let limitBefore: float32 = 0.0;
			let limitAfter: float32 = 0.0;
			for (let step: int32 = 1; step <= size; step++) {
				const edge: int32 = start + (i - start - step + size * 2) % size;
				if (isNormal(edgeNormals[edge])) {
					before = edgeNormals[edge];
					limitBefore = edgeLimits[edge];
					break;
				}
			}
			for (let step: int32 = 0; step < size; step++) {
				const edge: int32 = start + (i - start + step) % size;
				if (isNormal(edgeNormals[edge])) {
					after = edgeNormals[edge];
					limitAfter = edgeLimits[edge];
					break;
				}
			}
			corners.push({
				p: pts[i], before: before, after: after, limitBefore: limitBefore,
				limitAfter: limitAfter,
			});
		}
	}
	for (const k of tris) {
		edgeVtx(n, counted, corners[k], map, color, -FRINGE_HALF_WIDTH);
	}
	for (let i: int32 = 0; i < total; i++) {
		if (isNormal(edgeNormals[i])) {
			fringeQuad(n, counted, corners[i], corners[nextOf[i]], map, color);
		}
	}
}

function areaOverPerimeter(pts: Readonly<Span<Vec2>>, loopEnds: Readonly<Span<int32>>): float32 {
	let area: float32 = 0.0;
	let perimeter: float32 = 0.0;
	for (let k: int32 = 0; k < (loopEnds.length as int32); k++) {
		const start: int32 = loopStart(loopEnds, k);
		const end: int32 = loopEnds[k];
		let loopArea: float32 = 0.0;
		for (let i: int32 = start; i < end; i++) {
			const j: int32 = i + 1 < end ? i + 1 : start;
			loopArea = loopArea + pts[i].x * pts[j].y - pts[j].x * pts[i].y;
			const dx: float32 = pts[j].x - pts[i].x;
			const dy: float32 = pts[j].y - pts[i].y;
			perimeter = perimeter + sqrtf(dx * dx + dy * dy);
		}
		const half: float32 = (loopArea < 0.0 ? -loopArea : loopArea) * 0.5;
		area = k == 0 ? area + half : area - half;
	}
	return perimeter > 0.0 ? area / perimeter : 0.0;
}

// Each edge's inset limit, in local units along that edge's normal, so a non-uniform scale
// collapses the axis it compresses. Parallel: half the outline's inward extent, exact where
// each edge faces a parallel one (rects). Convex: that extent capped by 2A/P, the inradius of
// a triangle or a regular polygon, past which their insets cross. Ring, a contour with holes,
// or a loop longer than EXACT_EDGE_WIDTHS_UP_TO: area over perimeter, exact for a ring and the
// convex lower bound otherwise.
function edgeHalfWidths(
	pts: Readonly<Span<Vec2>>,
	loopEnds: Readonly<Span<int32>>,
	normals: Readonly<Span<Vec2>>,
	rule: EdgeLimit,
): float32[] {
	const out: float32[] = [];
	const total: int32 = pts.length as int32;
	const uniform: float32 = areaOverPerimeter(pts, loopEnds);
	const exact: boolean = rule != EdgeLimit.Ring && (loopEnds.length as int32) == 1
		&& total <= EXACT_EDGE_WIDTHS_UP_TO;
	if (!exact) {
		for (let i: int32 = 0; i < total; i++) { out.push(uniform); }
		return out;
	}
	const cap: float32 = rule == EdgeLimit.Convex ? 2.0 * uniform : -1.0;
	for (let i: int32 = 0; i < total; i++) {
		let deepest: float32 = 0.0;
		for (let v: int32 = 0; v < total; v++) {
			const inward: float32 = (pts[i].x - pts[v].x) * normals[i].x
				+ (pts[i].y - pts[v].y) * normals[i].y;
			if (inward > deepest) { deepest = inward; }
		}
		const half: float32 = deepest * 0.5;
		out.push(cap >= 0.0 && cap < half ? cap : half);
	}
	return out;
}

function fanTris(count: int32): int32[] {
	const out: int32[] = [];
	for (let i: int32 = 1; i + 1 < count; i++) {
		out.push(0);
		out.push(i);
		out.push(i + 1);
	}
	return out;
}

function arcSegs(r: float32, sweep: float32): int32 {
	const s: float32 = sweep < 0.0 ? -sweep : sweep;
	let n: int32 = ((r * s * 0.3) as int32) + 3;
	if (n > CIRCLE_MAX_SEG) { n = CIRCLE_MAX_SEG; }
	return n;
}

function circleSegs(r: float32): int32 {
	const seg: int32 = (r as int32) / 2 + 8;
	return seg > CIRCLE_MAX_SEG ? CIRCLE_MAX_SEG : seg;
}

function cornerArc(
	pts: Vec2[],
	ccx: float32,
	ccy: float32,
	r: float32,
	a0: float32,
	seg: int32,
): void {
	for (let i: int32 = 0; i <= seg; i++) {
		const a: float32 = a0 + TAU * 0.25 * ((i as float32) / (seg as float32));
		pts.push(vec2(ccx + cosf(a) * r, ccy + sinf(a) * r));
	}
}

function ellipsePoints(cx: float32, cy: float32, rx: float32, ry: float32, seg: int32): Vec2[] {
	const pts: Vec2[] = [];
	const step: float32 = TAU / (seg as float32);
	for (let i: int32 = 0; i < seg; i++) {
		const a: float32 = step * (i as float32);
		pts.push(vec2(cx + cosf(a) * rx, cy + sinf(a) * ry));
	}
	return pts;
}

// left-hand unit normal of segment a→b (zero vector if degenerate).
function segNormal(ax: float32, ay: float32, bx: float32, by: float32): Vec2 {
	const dx: float32 = bx - ax;
	const dy: float32 = by - ay;
	const len: float32 = sqrtf(dx * dx + dy * dy);
	if (len < DEGENERATE_LEN) { return vec2(0.0, 0.0); }
	return vec2(-dy / len, dx / len);
}

function meshOf(g: NodeRef, call: string): GraphicsMesh {
	const i: int32 = g.liveRow(call);
	const kind: DrawKind = g.scene.kinds[i];
	if (kind !== DrawKind.Graphics) {
		console.log(
			`void2d: ${call} asked of a ${kind.toString()} node; only a Graphics has a mesh`,
		);
		unreachable;
	}
	g.scene.markChanged(i, Changed.Content);
	return g.scene.meshes[g.scene.payloads[i]];
}

export function setAntialias(this g: NodeRef, on: boolean): NodeRef {
	const target: GraphicsMesh = meshOf(g, "setAntialias");
	target.antialias = on;
	return g;
}

export function fillTriangle(this g: NodeRef, a: Vec2, b: Vec2, c: Vec2, color: Color): NodeRef {
	const target: GraphicsMesh = meshOf(g, "fillTriangle");
	contourFill(target, true, [a, b, c], [3], [0, 1, 2], NO_UV, color, EdgeLimit.Convex);
	return g;
}

function rectPoints(x: float32, y: float32, w: float32, h: float32): Vec2[] {
	return [vec2(x, y), vec2(x + w, y), vec2(x + w, y + h), vec2(x, y + h)];
}

const RECT_TRIS: int32[] = [0, 1, 2, 0, 2, 3];

export function fillRect(
	this g: NodeRef,
	x: float32,
	y: float32,
	w: float32,
	h: float32,
	color: Color,
): NodeRef {
	const target: GraphicsMesh = meshOf(g, "fillRect");
	contourFill(target, true, rectPoints(x, y, w, h), [4], RECT_TRIS, NO_UV, color,
		EdgeLimit.Parallel);
	return g;
}

export function fillConvex(this g: NodeRef, pts: Vec2[], color: Color): NodeRef {
	const target: GraphicsMesh = meshOf(g, "fillConvex");
	const m: int32 = pts.length as int32;
	contourFill(target, true, pts, [m], fanTris(m), NO_UV, color, EdgeLimit.Convex);
	return g;
}

function appendOp(
	n: GraphicsMesh,
	kind: GraphicsOpKind,
	vertexOffset: int32,
	vertexCount: int32,
	space: GradientSpace,
	dither: boolean,
	middle: float32,
	c0: Color,
	c1: Color,
	c2: Color,
	p0: float32,
	p1: float32,
	p2: float32,
	p3: float32,
): void {
	const base: int32 = n.records.length as int32;
	for (let i: int32 = 0; i < GRAPHICS_OP_FLOATS; i++) { n.records.push(0.0 as float32); }
	n.records[base + GFX_OP_KIND] = (kind as int32) as float32;
	n.records[base + GFX_OP_VERTEX_OFFSET] = vertexOffset as float32;
	n.records[base + GFX_OP_VERTEX_COUNT] = vertexCount as float32;
	n.records[base + GFX_OP_SPACE] = (space as int32) as float32;
	n.records[base + GFX_OP_DITHER] = dither ? 1.0 : 0.0;
	n.records[base + GFX_OP_MIDDLE] = middle;
	n.records[base + GFX_OP_COLOR0] = c0.r;
	n.records[base + GFX_OP_COLOR0 + 1] = c0.g;
	n.records[base + GFX_OP_COLOR0 + 2] = c0.b;
	n.records[base + GFX_OP_COLOR0 + 3] = c0.a;
	n.records[base + GFX_OP_COLOR1] = c1.r;
	n.records[base + GFX_OP_COLOR1 + 1] = c1.g;
	n.records[base + GFX_OP_COLOR1 + 2] = c1.b;
	n.records[base + GFX_OP_COLOR1 + 3] = c1.a;
	n.records[base + GFX_OP_COLOR2] = c2.r;
	n.records[base + GFX_OP_COLOR2 + 1] = c2.g;
	n.records[base + GFX_OP_COLOR2 + 2] = c2.b;
	n.records[base + GFX_OP_COLOR2 + 3] = c2.a;
	n.records[base + GFX_OP_PARAMS] = p0;
	n.records[base + GFX_OP_PARAMS + 1] = p1;
	n.records[base + GFX_OP_PARAMS + 2] = p2;
	n.records[base + GFX_OP_PARAMS + 3] = p3;
}

function polyArea2(pts: Readonly<Span<Vec2>>): float32 {
	const m: int32 = pts.length as int32;
	let a: float32 = 0.0;
	for (let i: int32 = 0; i < m; i++) {
		const j: int32 = (i + 1) % m;
		a = a + pts[i].x * pts[j].y - pts[j].x * pts[i].y;
	}
	return a;
}

function cross3(
	ax: float32,
	ay: float32,
	bx: float32,
	by: float32,
	cx: float32,
	cy: float32,
): float32 {
	return (bx - ax) * (cy - ay) - (by - ay) * (cx - ax);
}

function pointInTri(
	px: float32,
	py: float32,
	ax: float32,
	ay: float32,
	bx: float32,
	by: float32,
	cx: float32,
	cy: float32,
): boolean {
	const d1: float32 = cross3(ax, ay, bx, by, px, py);
	const d2: float32 = cross3(bx, by, cx, cy, px, py);
	const d3: float32 = cross3(cx, cy, ax, ay, px, py);
	const hasNeg: boolean = d1 < 0.0 || d2 < 0.0 || d3 < 0.0;
	const hasPos: boolean = d1 > 0.0 || d2 > 0.0 || d3 > 0.0;
	return !(hasNeg && hasPos);
}

function isEar(
	pts: Readonly<Span<Vec2>>,
	next: Readonly<Span<int32>>,
	u: int32,
	v: int32,
	w: int32,
	ccw: boolean,
): boolean {
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
function triangulate(pts: Readonly<Span<Vec2>>): int32[] {
	const out: int32[] = [];
	const n: int32 = pts.length as int32;
	if (n < 3) { return out; }
	const prev: int32[] = [];
	const next: int32[] = [];
	for (let i: int32 = 0; i < n; i++) {
		prev.push((i - 1 + n) % n);
		next.push((i + 1) % n);
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
export function fillPolygon(this g: NodeRef, pts: Vec2[], color: Color): NodeRef {
	const target: GraphicsMesh = meshOf(g, "fillPolygon");
	contourFill(target, true, pts, [pts.length as int32], triangulate(pts), NO_UV, color,
		EdgeLimit.Convex);
	return g;
}

export function fillGradientPolygonStops(
	this g: NodeRef,
	pts: Vec2[],
	c0: Color,
	cMiddle: Color,
	c1: Color,
	middle: float32,
	angle: float32,
	space: GradientSpace,
): NodeRef {
	const target: GraphicsMesh = meshOf(g, "fillGradientPolygonStops");
	const m: int32 = pts.length as int32;
	if (m < 3) { return g; }
	const ax: float32 = cosf(angle);
	const ay: float32 = sinf(angle);
	let minP: float32 = pts[0].x * ax + pts[0].y * ay;
	let maxP: float32 = minP;
	for (let i: int32 = 1; i < m; i++) {
		const pp: float32 = pts[i].x * ax + pts[i].y * ay;
		if (pp < minP) { minP = pp; }
		if (pp > maxP) { maxP = pp; }
	}
	const span: float32 = maxP - minP;
	let map: UvMap = NO_UV;
	if (span > DEGENERATE_LEN) {
		map = { ux: ax / span, uy: ay / span, uc: -minP / span, vx: 0.0, vy: 0.0, vc: 0.0 };
	}
	const start: int32 = (target.mesh.length as int32) / 8;
	contourFill(target, false, pts, [m], triangulate(pts), map, white, EdgeLimit.Convex);
	const count: int32 = (target.mesh.length as int32) / 8 - start;
	if (count > 0) {
		appendOp(target, GraphicsOpKind.LinearGradient, start, count, space, true, middle,
			c0, cMiddle, c1, 0.0, 0.0, 0.0, 0.0);
	}
	return g;
}

export function fillGradientPolygon(
	this g: NodeRef,
	pts: Vec2[],
	c0: Color,
	c1: Color,
	angle: float32,
): NodeRef {
	return g.fillGradientPolygonStops(pts, c0, c1, c1, -1.0, angle, GradientSpace.Srgb);
}
export function fillGradientPolygonOklab(
	this g: NodeRef,
	pts: Vec2[],
	c0: Color,
	c1: Color,
	angle: float32,
): NodeRef {
	return g.fillGradientPolygonStops(pts, c0, c1, c1, -1.0, angle, GradientSpace.Oklab);
}

export function fillGradientRect(
	this g: NodeRef,
	x: float32,
	y: float32,
	w: float32,
	h: float32,
	c0: Color,
	c1: Color,
	angle: float32,
): NodeRef {
	const pts: Vec2[] = [vec2(x, y), vec2(x + w, y), vec2(x + w, y + h), vec2(x, y + h)];
	return g.fillGradientPolygon(pts, c0, c1, angle);
}

export function fillGradientRectOklab(
	this g: NodeRef,
	x: float32,
	y: float32,
	w: float32,
	h: float32,
	c0: Color,
	c1: Color,
	angle: float32,
): NodeRef {
	const pts: Vec2[] = [vec2(x, y), vec2(x + w, y), vec2(x + w, y + h), vec2(x, y + h)];
	return g.fillGradientPolygonStops(pts, c0, c1, c1, -1.0, angle, GradientSpace.Oklab);
}

export function fillGradientRectStops(
	this g: NodeRef,
	x: float32,
	y: float32,
	w: float32,
	h: float32,
	c0: Color,
	cMiddle: Color,
	c1: Color,
	middle: float32,
	angle: float32,
	space: GradientSpace,
): NodeRef {
	const pts: Vec2[] = [vec2(x, y), vec2(x + w, y), vec2(x + w, y + h), vec2(x, y + h)];
	return g.fillGradientPolygonStops(pts, c0, cMiddle, c1, middle, angle, space);
}

export function fillRadialGradientStops(
	this g: NodeRef,
	cx: float32,
	cy: float32,
	r: float32,
	c0: Color,
	cMiddle: Color,
	c1: Color,
	middle: float32,
	space: GradientSpace,
): NodeRef {
	const target: GraphicsMesh = meshOf(g, "fillRadialGradientStops");
	if (r <= 0.0) { return g; }
	const seg: int32 = circleSegs(r);
	const map: UvMap = { ux: 1.0 / r, uy: 0.0, uc: -cx / r, vx: 0.0, vy: 1.0 / r, vc: -cy / r };
	const start: int32 = (target.mesh.length as int32) / 8;
	contourFill(target, false, ellipsePoints(cx, cy, r, r, seg), [seg], fanTris(seg), map, white,
		EdgeLimit.Convex);
	const count: int32 = (target.mesh.length as int32) / 8 - start;
	appendOp(target, GraphicsOpKind.RadialGradient, start, count, space, true, middle,
		c0, cMiddle, c1, 0.0, 0.0, 0.0, 0.0);
	return g;
}

export function fillRadialGradient(
	this g: NodeRef,
	cx: float32,
	cy: float32,
	r: float32,
	cInner: Color,
	cOuter: Color,
): NodeRef {
	return g.fillRadialGradientStops(cx, cy, r, cInner, cOuter, cOuter, -1.0, GradientSpace.Srgb);
}

export function fillRadialGradientOklab(
	this g: NodeRef,
	cx: float32,
	cy: float32,
	r: float32,
	cInner: Color,
	cOuter: Color,
): NodeRef {
	return g.fillRadialGradientStops(cx, cy, r, cInner, cOuter, cOuter, -1.0, GradientSpace.Oklab);
}

function fillPatternRect(
	g: NodeRef,
	kind: GraphicsOpKind,
	x: float32,
	y: float32,
	w: float32,
	h: float32,
	c0: Color,
	c1: Color,
	p0: float32,
	p1: float32,
): NodeRef {
	const target: GraphicsMesh = meshOf(g, "fillPatternRect");
	const map: UvMap = { ux: 1.0, uy: 0.0, uc: -x, vx: 0.0, vy: 1.0, vc: -y };
	const start: int32 = (target.mesh.length as int32) / 8;
	contourFill(target, false, rectPoints(x, y, w, h), [4], RECT_TRIS, map, white,
		EdgeLimit.Parallel);
	const count: int32 = (target.mesh.length as int32) / 8 - start;
	appendOp(target, kind, start, count, GradientSpace.Srgb, false, -1.0,
		c0, c1, c1, p0, p1, 0.0, 0.0);
	return g;
}

export function fillSlashRect(
	this g: NodeRef,
	x: float32,
	y: float32,
	w: float32,
	h: float32,
	background: Color,
	stripe: Color,
	spacing: float32,
	width: float32,
): NodeRef {
	return fillPatternRect(g, GraphicsOpKind.SlashPattern, x, y, w, h,
		background, stripe, spacing, width);
}

export function fillCheckerRect(
	this g: NodeRef,
	x: float32,
	y: float32,
	w: float32,
	h: float32,
	a: Color,
	b: Color,
	cell: float32,
): NodeRef {
	return fillPatternRect(g, GraphicsOpKind.CheckerPattern, x, y, w, h,
		a, b, cell, 0.0);
}

// h2d.Graphics.drawTile — textured rect (tile mapped to the rect). Sets the node's view.
export function fillTexRect(
	this g: NodeRef,
	t: Tile,
	x: float32,
	y: float32,
	w: float32,
	h: float32,
	color: Color,
): NodeRef {
	const target: GraphicsMesh = meshOf(g, "fillTexRect");
	target.source = t.source;
	target.alphaPremultiplied = t.alphaPremultiplied;
	if (w == 0.0 || h == 0.0) { return g; }
	const du: float32 = (t.u1 - t.u0) / w;
	const dv: float32 = (t.v1 - t.v0) / h;
	const map: UvMap = { ux: du, uy: 0.0, uc: t.u0 - x * du, vx: 0.0, vy: dv, vc: t.v0 - y * dv };
	contourFill(target, true, rectPoints(x, y, w, h), [4], RECT_TRIS, map, color,
		EdgeLimit.Parallel);
	return g;
}

// h2d.Graphics.beginTileFill — fill an arbitrary shape with a tile; UV maps the tile
// across the shape from (originX,originY) over (tileW,tileH) px (REPEAT sampler tiles it).
// One view per Graphics node: don't mix textured + solid fills on the same node.
export function fillTexPolygon(
	this g: NodeRef,
	t: Tile,
	pts: Vec2[],
	originX: float32,
	originY: float32,
	tileW: float32,
	tileH: float32,
	color: Color,
): NodeRef {
	const target: GraphicsMesh = meshOf(g, "fillTexPolygon");
	target.source = t.source;
	target.alphaPremultiplied = t.alphaPremultiplied;
	const du: float32 = (t.u1 - t.u0) / tileW;
	const dv: float32 = (t.v1 - t.v0) / tileH;
	const map: UvMap = {
		ux: du, uy: 0.0, uc: t.u0 - originX * du,
		vx: 0.0, vy: dv, vc: t.v0 - originY * dv,
	};
	contourFill(target, true, pts, [pts.length as int32], triangulate(pts), map, color,
		EdgeLimit.Convex);
	return g;
}

export function fillCircle(
	this g: NodeRef,
	cx: float32,
	cy: float32,
	r: float32,
	color: Color,
): NodeRef {
	const target: GraphicsMesh = meshOf(g, "fillCircle");
	const seg: int32 = circleSegs(r);
	contourFill(target, true, ellipsePoints(cx, cy, r, r, seg), [seg], fanTris(seg), NO_UV, color,
		EdgeLimit.Convex);
	return g;
}

export function strokeLine(
	this g: NodeRef,
	a: Vec2,
	b: Vec2,
	width: float32,
	color: Color,
): NodeRef {
	meshOf(g, "strokeLine");
	const dx: float32 = b.x - a.x;
	const dy: float32 = b.y - a.y;
	if (sqrtf(dx * dx + dy * dy) < DEGENERATE_LEN) { return g; }
	return g.strokePoly([a, b], width, color, false);
}

function negated(v: Vec2): Vec2 { return vec2(-v.x, -v.y); }

export function strokePoly(
	this g: NodeRef,
	pts: Vec2[],
	width: float32,
	color: Color,
	closed: boolean,
): NodeRef {
	const target: GraphicsMesh = meshOf(g, "strokePoly");
	const m: int32 = pts.length as int32;
	if (m < 2) { return g; }
	const hw: float32 = width * 0.5;
	// per-vertex outer offsets: butt at open ends, miter (clamped) at joints.
	const left: Corner[] = [];
	const right: Corner[] = [];
	for (let i: int32 = 0; i < m; i++) {
		const hasPrev: boolean = closed || i > 0;
		const hasNext: boolean = closed || i < m - 1;
		const pi: int32 = (i - 1 + m) % m;
		const ni: int32 = (i + 1) % m;
		const n1 = hasPrev ? segNormal(pts[pi].x, pts[pi].y, pts[i].x, pts[i].y) : NO_NORMAL;
		const n2 = hasNext ? segNormal(pts[i].x, pts[i].y, pts[ni].x, pts[ni].y) : NO_NORMAL;
		let nx: float32 = 0.0;
		let ny: float32 = 0.0;
		let leftBefore: Vec2 = n1;
		let leftAfter: Vec2 = n2;
		let rightBefore: Vec2 = negated(n1);
		let rightAfter: Vec2 = negated(n2);
		let limitBefore: float32 = hw;
		let limitAfter: float32 = hw;
		if (hasPrev && hasNext) {
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
			nx = n2.x * hw;
			ny = n2.y * hw;
			const cap: Vec2 = vec2(-n2.y, n2.x);
			leftBefore = cap;
			rightBefore = cap;
			limitBefore = halfLength(pts[i], pts[ni]);
		} else {
			nx = n1.x * hw;
			ny = n1.y * hw;
			const cap: Vec2 = vec2(n1.y, -n1.x);
			leftAfter = cap;
			rightAfter = cap;
			limitAfter = halfLength(pts[pi], pts[i]);
		}
		left.push({
			p: vec2(pts[i].x + nx, pts[i].y + ny), before: leftBefore, after: leftAfter,
			limitBefore: limitBefore, limitAfter: limitAfter,
		});
		right.push({
			p: vec2(pts[i].x - nx, pts[i].y - ny), before: rightBefore, after: rightAfter,
			limitBefore: limitBefore, limitAfter: limitAfter,
		});
	}
	const segs: int32 = closed ? m : (m - 1);
	if (!target.antialias) {
		for (let s: int32 = 0; s < segs; s++) {
			const a: int32 = s;
			const b: int32 = (s + 1) % m;
			tri(target, left[a].p, right[a].p, right[b].p, color);
			tri(target, left[a].p, right[b].p, left[b].p, color);
		}
		return g;
	}
	for (let s: int32 = 0; s < segs; s++) {
		const a: int32 = s;
		const b: int32 = (s + 1) % m;
		edgeVtx(target, true, left[a], NO_UV, color, -FRINGE_HALF_WIDTH);
		edgeVtx(target, true, right[a], NO_UV, color, -FRINGE_HALF_WIDTH);
		edgeVtx(target, true, right[b], NO_UV, color, -FRINGE_HALF_WIDTH);
		edgeVtx(target, true, left[a], NO_UV, color, -FRINGE_HALF_WIDTH);
		edgeVtx(target, true, right[b], NO_UV, color, -FRINGE_HALF_WIDTH);
		edgeVtx(target, true, left[b], NO_UV, color, -FRINGE_HALF_WIDTH);
	}
	for (let s: int32 = 0; s < segs; s++) {
		const a: int32 = s;
		const b: int32 = (s + 1) % m;
		fringeQuad(target, true, left[a], left[b], NO_UV, color);
		fringeQuad(target, true, right[b], right[a], NO_UV, color);
	}
	if (!closed) {
		fringeQuad(target, true, right[0], left[0], NO_UV, color);
		fringeQuad(target, true, left[m - 1], right[m - 1], NO_UV, color);
	}
	return g;
}

export function strokeRect(
	this g: NodeRef,
	x: float32,
	y: float32,
	w: float32,
	h: float32,
	width: float32,
	color: Color,
): NodeRef {
	const pts: Vec2[] = [vec2(x, y), vec2(x + w, y), vec2(x + w, y + h), vec2(x, y + h)];
	return g.strokePoly(pts, width, color, true);
}

// h2d.Graphics.drawRoundedRect — convex perimeter (4 corner arcs + edges) → fan fill.
export function fillRoundedRect(
	this g: NodeRef,
	x: float32,
	y: float32,
	w: float32,
	h: float32,
	radius: float32,
	color: Color,
): NodeRef {
	const maxR: float32 = (w < h ? w : h) * 0.5;
	let r: float32 = radius;
	if (r > maxR) { r = maxR; }
	if (r <= 0.0) { return g.fillRect(x, y, w, h, color); }
	const seg: int32 = arcSegs(r, TAU * 0.25);
	const pts: Vec2[] = [];
	cornerArc(pts, x + r,     y + r,     r, TAU * 0.5,  seg);
	cornerArc(pts, x + w - r, y + r,     r, TAU * 0.75, seg);
	cornerArc(pts, x + w - r, y + h - r, r, 0.0,        seg);
	cornerArc(pts, x + r,     y + h - r, r, TAU * 0.25, seg);
	return g.fillConvex(pts, color);
}

// h2d.Graphics.drawEllipse — fan from centre with independent x/y radii.
export function fillEllipse(
	this g: NodeRef,
	cx: float32,
	cy: float32,
	rx: float32,
	ry: float32,
	color: Color,
): NodeRef {
	const target: GraphicsMesh = meshOf(g, "fillEllipse");
	const seg: int32 = arcSegs(rx > ry ? rx : ry, TAU);
	const pts: Vec2[] = ellipsePoints(cx, cy, rx, ry, seg);
	contourFill(target, true, pts, [seg], fanTris(seg), NO_UV, color, EdgeLimit.Convex);
	return g;
}

function isFullTurn(angleLength: float32): boolean {
	return angleLength >= TAU || angleLength <= -TAU;
}

// h2d.Graphics.drawPie — fan slice over [angleStart, angleStart+angleLength] (radians).
export function fillPie(
	this g: NodeRef,
	cx: float32,
	cy: float32,
	r: float32,
	angleStart: float32,
	angleLength: float32,
	color: Color,
): NodeRef {
	if (isFullTurn(angleLength)) { return g.fillCircle(cx, cy, r, color); }
	const target: GraphicsMesh = meshOf(g, "fillPie");
	if (angleLength == 0.0) { return g; }
	const seg: int32 = arcSegs(r, angleLength);
	const step: float32 = angleLength / (seg as float32);
	const pts: Vec2[] = [vec2(cx, cy)];
	for (let i: int32 = 0; i <= seg; i++) {
		const a: float32 = angleStart + step * (i as float32);
		pts.push(vec2(cx + cosf(a) * r, cy + sinf(a) * r));
	}
	contourFill(target, true, pts, [seg + 2], fanTris(seg + 2), NO_UV, color, EdgeLimit.Convex);
	return g;
}

// h2d.Graphics.drawPieInner — annular sector (ring slice) between innerR and outerR.
export function fillRing(
	this g: NodeRef,
	cx: float32,
	cy: float32,
	outerR: float32,
	innerR: float32,
	angleStart: float32,
	angleLength: float32,
	color: Color,
): NodeRef {
	const target: GraphicsMesh = meshOf(g, "fillRing");
	const full: boolean = isFullTurn(angleLength);
	const sweep: float32 = full ? TAU : angleLength;
	const seg: int32 = arcSegs(outerR, sweep);
	const step: float32 = sweep / (seg as float32);
	const rim: int32 = full ? seg : seg + 1;
	const pts: Vec2[] = [];
	for (let i: int32 = 0; i < rim; i++) {
		const a: float32 = angleStart + step * (i as float32);
		pts.push(vec2(cx + cosf(a) * outerR, cy + sinf(a) * outerR));
	}
	for (let i: int32 = rim - 1; i >= 0; i--) {
		const a: float32 = angleStart + step * (i as float32);
		pts.push(vec2(cx + cosf(a) * innerR, cy + sinf(a) * innerR));
	}
	const tris: int32[] = [];
	for (let i: int32 = 0; i < seg; i++) {
		const next: int32 = (i + 1) % rim;
		const inner: int32 = rim + (rim - 1 - i);
		const innerNext: int32 = rim + (rim - 1 - next);
		tris.push(inner);
		tris.push(i);
		tris.push(next);
		tris.push(inner);
		tris.push(next);
		tris.push(innerNext);
	}
	const loops: int32[] = full ? [rim, rim * 2] : [rim * 2];
	contourFill(target, true, pts, loops, tris, NO_UV, color, EdgeLimit.Ring);
	return g;
}

// h2d.Graphics.curveTo — quadratic Bézier flattened to points (compose with stroke/fill).
export function quadBezier(a: Vec2, ctrl: Vec2, b: Vec2, segments: int32): Vec2[] {
	let seg: int32 = segments;
	if (seg < 1) { seg = 1; }
	const pts: Vec2[] = [];
	for (let i: int32 = 0; i <= seg; i++) {
		const t: float32 = (i as float32) / (seg as float32);
		const u: float32 = 1.0 - t;
		const x: float32 = u * u * a.x + 2.0 * u * t * ctrl.x + t * t * b.x;
		const y: float32 = u * u * a.y + 2.0 * u * t * ctrl.y + t * t * b.y;
		pts.push(vec2(x, y));
	}
	return pts;
}

// h2d.Graphics.cubicCurveTo — cubic Bézier flattened to points.
export function cubicBezier(a: Vec2, c1: Vec2, c2: Vec2, b: Vec2, segments: int32): Vec2[] {
	let seg: int32 = segments;
	if (seg < 1) { seg = 1; }
	const pts: Vec2[] = [];
	for (let i: int32 = 0; i <= seg; i++) {
		const t: float32 = (i as float32) / (seg as float32);
		const u: float32 = 1.0 - t;
		const x: float32 = u * u * u * a.x + 3.0 * u * u * t * c1.x + 3.0 * u * t * t * c2.x +
			t * t * t * b.x;
		const y: float32 = u * u * u * a.y + 3.0 * u * u * t * c1.y + 3.0 * u * t * t * c2.y +
			t * t * t * b.y;
		pts.push(vec2(x, y));
	}
	return pts;
}
