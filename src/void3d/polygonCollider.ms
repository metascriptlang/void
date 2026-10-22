// Port of h3d.col.Polygon / TriPlane and the convex and closest-point queries of
// h3d.col.PolygonBuffer: triangle colliders over a position array (xyz, stride 3) and a triangle
// index list. PolygonBuffer's Moller-Trumbore ray cast is meshData.ms rayIntersection; this is
// the plane-based, optionally two-sided cast of Polygon.

import { Vec3, vec3 } from "../math/math3d";
import { Ray } from "./ray";
import {
	Wide3, wide, wideSub, wideAdd, wideScaled, wideDot, wideCross, finiteVec, FLOAT32_LIMIT,
} from "./colliderMath";

export struct Triangle3D {
	p0: Vec3;
	p1: Vec3;
	p2: Vec3;
}

export enum PolygonError { NonFinite, NotTriangles, IndexRange, EmptyMesh, OutOfRange }

function finiteTriangle(tri: Triangle3D): boolean {
	return finiteVec(tri.p0) && finiteVec(tri.p1) && finiteVec(tri.p2);
}

// TriPlane.isPointInTriangle, Polygon.hx:172-184: barycentric coordinates of the point's offset
// from p0 in the basis of the two edges, so a point off the plane counts by its projection.
// A zero-area triangle has no basis (Heaps multiplies by 1/0) and contains nothing.
function inTriangle(p0: Wide3, d1: Wide3, d2: Wide3, point: Wide3): boolean {
	const dot00: float64 = wideDot(d1, d1);
	const dot01: float64 = wideDot(d1, d2);
	const dot11: float64 = wideDot(d2, d2);
	const denominator: float64 = dot00 * dot11 - dot01 * dot01;
	if (denominator == 0.0) { return false; }
	const invDenom: float64 = 1.0 / denominator;
	const v2: Wide3 = wideSub(point, p0);
	const dot02: float64 = wideDot(d1, v2);
	const dot12: float64 = wideDot(d2, v2);
	const u: float64 = (dot11 * dot02 - dot01 * dot12) * invDenom;
	const v: float64 = (dot00 * dot12 - dot01 * dot02) * invDenom;
	return u >= 0.0 && v >= 0.0 && u + v < 1.0;
}

function rayTriangle(tri: Triangle3D, ray: Ray, oriented: boolean): float64 {
	const p0: Wide3 = wide(tri.p0);
	const d1: Wide3 = wideSub(wide(tri.p1), p0);
	const d2: Wide3 = wideSub(wide(tri.p2), p0);
	const n: Wide3 = wideCross(d1, d2);
	const d: float64 = wideDot(n, p0);
	const ro: Wide3 = wide(ray.origin);
	const rd: Wide3 = wide(ray.direction);
	const dr: float64 = wideDot(rd, n);
	if (dr >= 0.0 && oriented) { return -1.0; }
	if (dr == 0.0) { return -1.0; }
	const k: float64 = (d - wideDot(ro, n)) / dr;
	if (k < 0.0 && oriented) { return -1.0; }
	if (!inTriangle(p0, d1, d2, wideAdd(ro, wideScaled(rd, k)))) { return -1.0; }
	return k;
}

// TriPlane.rayIntersection, Polygon.hx:156-170. The distance along the ray to the plane when
// the hit lies inside the triangle, else -1. `oriented` culls faces whose normal
// (p1 - p0) x (p2 - p0) does not oppose the ray, as the Polygon constructor flag does. Unoriented
// the ray is also allowed to hit behind its origin; a negative answer is a miss either way, and
// a ray parallel to the plane is a miss (Heaps divides by zero and the point test fails).
export function rayIntersection(
	this tri: Triangle3D, ray: Ray, oriented: boolean,
): Result<float32, PolygonError> {
	if (!finiteTriangle(tri) || !finiteVec(ray.origin) || !finiteVec(ray.direction)) {
		return Result.err(PolygonError.NonFinite);
	}
	const k: float64 = rayTriangle(tri, ray, oriented);
	if (Math.abs(k) > FLOAT32_LIMIT) { return Result.err(PolygonError.OutOfRange); }
	return Result.ok(k as float32);
}

// TriPlane.contains: the point lies inside the triangle's prism along its normal, so a point off
// the plane is tested by where it projects.
export function containsProjected(this tri: Triangle3D, point: Vec3): Result<boolean, PolygonError> {
	if (!finiteTriangle(tri) || !finiteVec(point)) { return Result.err(PolygonError.NonFinite); }
	const p0: Wide3 = wide(tri.p0);
	return Result.ok(inTriangle(p0, wideSub(wide(tri.p1), p0), wideSub(wide(tri.p2), p0), wide(point)));
}

// closestPointLine, Polygon.hx:127-130. A zero-length edge has no direction (Heaps divides 0/0);
// its closest point is its start.
function closestOnEdge(point: Wide3, start: Wide3, direction: Wide3): Wide3 {
	const lengthSquared: float64 = wideDot(direction, direction);
	if (lengthSquared == 0.0) { return start; }
	let t: float64 = wideDot(wideSub(point, start), direction) / lengthSquared;
	if (t < 0.0) { t = 0.0; }
	if (t > 1.0) { t = 1.0; }
	return wideAdd(start, wideScaled(direction, t));
}

function closestOnTriangle(tri: Triangle3D, point: Wide3): Wide3 {
	const p0: Wide3 = wide(tri.p0);
	const d1: Wide3 = wideSub(wide(tri.p1), p0);
	const d2: Wide3 = wideSub(wide(tri.p2), p0);
	if (inTriangle(p0, d1, d2, point)) {
		const n: Wide3 = wideCross(d1, d2);
		const unit: Wide3 = wideScaled(n, 1.0 / Math.sqrt(wideDot(n, n)));
		const d: Wide3 = wideSub(point, p0);
		return wideAdd(p0, wideSub(d, wideScaled(unit, wideDot(d, unit))));
	}
	const p1: Wide3 = wideAdd(p0, d1);
	const c1: Wide3 = closestOnEdge(point, p0, d1);
	const c2: Wide3 = closestOnEdge(point, p1, wideSub(d2, d1));
	const c3: Wide3 = closestOnEdge(point, p0, d2);
	const m1: Wide3 = wideSub(point, c1);
	const m2: Wide3 = wideSub(point, c2);
	const m3: Wide3 = wideSub(point, c3);
	let best: Wide3 = c1;
	let least: float64 = wideDot(m1, m1);
	if (wideDot(m2, m2) < least) { least = wideDot(m2, m2); best = c2; }
	if (wideDot(m3, m3) < least) { best = c3; }
	return best;
}

// TriPlane.closestPoint, Polygon.hx:116-154: the point itself projected onto the plane when it
// falls inside the triangle, else the nearest of the three edges.
export function closestPoint(this tri: Triangle3D, point: Vec3): Result<Vec3, PolygonError> {
	if (!finiteTriangle(tri) || !finiteVec(point)) { return Result.err(PolygonError.NonFinite); }
	const closest: Wide3 = closestOnTriangle(tri, wide(point));
	if (Math.abs(closest.x) > FLOAT32_LIMIT || Math.abs(closest.y) > FLOAT32_LIMIT ||
		Math.abs(closest.z) > FLOAT32_LIMIT) {
		return Result.err(PolygonError.OutOfRange);
	}
	return Result.ok(vec3(closest.x as float32, closest.y as float32, closest.z as float32));
}

function corner(positions: Readonly<Span<float32>>, index: uint32): Vec3 {
	const at: int32 = (index as int32) * 3;
	return vec3(positions[at], positions[at + 1], positions[at + 2]);
}

function soupError(
	positions: Readonly<Span<float32>>, indices: Readonly<Span<uint32>>,
): PolygonError | null {
	if (positions.length % 3 != 0 || indices.length % 3 != 0) { return PolygonError.NotTriangles; }
	for (let i = 0; i < indices.length; i++) {
		if ((indices[i] as int64) * 3 + 2 >= positions.length) { return PolygonError.IndexRange; }
	}
	for (let i = 0; i < positions.length; i++) {
		if (!Number.isFinite(positions[i])) { return PolygonError.NonFinite; }
	}
	return null;
}

function triangleAt(
	positions: Readonly<Span<float32>>, indices: Readonly<Span<uint32>>, triangle: int32,
): Triangle3D {
	const at: int32 = triangle * 3;
	return {
		p0: corner(positions, indices[at]),
		p1: corner(positions, indices[at + 1]),
		p2: corner(positions, indices[at + 2]),
	};
}

// Polygon.rayIntersection, Polygon.hx:293-305: the nearest hit over all triangles, or the first
// found when `bestMatch` is false. Polygon.addBuffers prepends each triangle, so Heaps walks them
// last to first and the first found is the last triangle's hit.
export function polygonRayIntersection(
	positions: Readonly<Span<float32>>, indices: Readonly<Span<uint32>>,
	ray: Ray, bestMatch: boolean, oriented: boolean,
): Result<float32, PolygonError> {
	const error: PolygonError | null = soupError(positions, indices);
	if (error !== null) { return Result.err(error); }
	if (!finiteVec(ray.origin) || !finiteVec(ray.direction)) {
		return Result.err(PolygonError.NonFinite);
	}
	let best: float64 = -1.0;
	for (let triangle = indices.length / 3 - 1; triangle >= 0; triangle--) {
		const d: float64 = rayTriangle(triangleAt(positions, indices, triangle), ray, oriented);
		if (d >= 0.0) {
			if (!bestMatch) { best = d; break; }
			if (best < 0.0 || d < best) { best = d; }
		}
	}
	if (best > FLOAT32_LIMIT) { return Result.err(PolygonError.OutOfRange); }
	return Result.ok(best as float32);
}

// PolygonBuffer.contains, PolygonBuffer.hx:56-76, and Polygon.contains: a point is inside a
// convex mesh when it lies behind every triangle plane (outward normal (p1 - p0) x (p2 - p0)).
// Heaps answers true for a mesh with no triangles; that is EmptyMesh here.
export function polygonContainsConvex(
	positions: Readonly<Span<float32>>, indices: Readonly<Span<uint32>>, point: Vec3,
): Result<boolean, PolygonError> {
	const error: PolygonError | null = soupError(positions, indices);
	if (error !== null) { return Result.err(error); }
	if (!finiteVec(point)) { return Result.err(PolygonError.NonFinite); }
	if (indices.length == 0) { return Result.err(PolygonError.EmptyMesh); }
	const p: Wide3 = wide(point);
	for (let triangle = 0; triangle < indices.length / 3; triangle++) {
		const tri: Triangle3D = triangleAt(positions, indices, triangle);
		const p0: Wide3 = wide(tri.p0);
		const n: Wide3 = wideCross(wideSub(wide(tri.p1), p0), wideSub(wide(tri.p2), p0));
		if (wideDot(n, p) >= wideDot(n, p0)) { return Result.ok(false); }
	}
	return Result.ok(true);
}

// PolygonBuffer.closestPoint, PolygonBuffer.hx:117-168, and Polygon.closestPoint: the nearest
// of the per-triangle closest points, the first triangle winning a tie (Polygon walks last to
// first, so it picks the last on a tie). Heaps dereferences null for a mesh with no triangles;
// that is EmptyMesh here.
export function polygonClosestPoint(
	positions: Readonly<Span<float32>>, indices: Readonly<Span<uint32>>, point: Vec3,
): Result<Vec3, PolygonError> {
	const error: PolygonError | null = soupError(positions, indices);
	if (error !== null) { return Result.err(error); }
	if (!finiteVec(point)) { return Result.err(PolygonError.NonFinite); }
	if (indices.length == 0) { return Result.err(PolygonError.EmptyMesh); }
	const p: Wide3 = wide(point);
	let best: Wide3 = p;
	let least: float64 = Infinity;
	for (let triangle = 0; triangle < indices.length / 3; triangle++) {
		const c: Wide3 = closestOnTriangle(triangleAt(positions, indices, triangle), p);
		const d: Wide3 = wideSub(p, c);
		const squared: float64 = wideDot(d, d);
		if (squared < least) { least = squared; best = c; }
	}
	return Result.ok(vec3(best.x as float32, best.y as float32, best.z as float32));
}
