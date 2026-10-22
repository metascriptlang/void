// Port of h3d.col.OptimizedCollider and GroupCollider (Collider.hx): a cheap collider asked first,
// the precise one only when it passes. The wrapped colliders are any of the colliders here, so
// each query takes them as closures over their own shape. `contains`, `inFrustum` and `inSphere`
// are `a && b` in OptimizedCollider (hx:42-52) and `||` over the list in GroupCollider
// (hx:97-113), which a caller writes as that expression; `closestPoint` is b's alone (hx:59-61).

import { Vec3 } from "../math/math3d";
import { Ray, pointAt } from "./ray";

export enum OptimizedColliderError { NonFinite }

// OptimizedCollider.rayIntersection, Collider.hx:33-41. `a` is cast without bestMatch; a miss
// there ends the query unless checkInside is set and the origin is inside `a`, because a ray
// starting inside a box has no entry distance. Heaps lets a NaN from `a` through to `b` (NaN < 0
// is false) and returns a NaN from `b`; a NaN from either is NonFinite.
export function optimizedRayIntersection(
	coarse: (ray: Ray) => float32, coarseContains: (point: Vec3) => boolean,
	precise: (ray: Ray) => float32, checkInside: boolean, ray: Ray,
): Result<float32, OptimizedColliderError> {
	const near: float32 = coarse(ray);
	if (Number.isNaN(near)) { return Result.err(OptimizedColliderError.NonFinite); }
	if (near < 0.0) {
		if (!checkInside) { return Result.ok(-1.0); }
		if (!coarseContains(ray.pointAt(0.0))) { return Result.ok(-1.0); }
	}
	const hit: float32 = precise(ray);
	if (Number.isNaN(hit)) { return Result.err(OptimizedColliderError.NonFinite); }
	return Result.ok(hit);
}

// OptimizedCollider.dimension, Collider.hx:55-57.
export function optimizedDimension(first: float32, second: float32): Result<float32, OptimizedColliderError> {
	if (Number.isNaN(first) || Number.isNaN(second)) { return Result.err(OptimizedColliderError.NonFinite); }
	return Result.ok(Math.max(first, second));
}

// GroupCollider.rayIntersection, Collider.hx:88-101: the first hit when bestMatch is false, else
// the nearest; an empty group is a miss.
export function groupRayIntersection(
	casts: Readonly<Span<(ray: Ray) => float32>>, bestMatch: boolean, ray: Ray,
): Result<float32, OptimizedColliderError> {
	let best: float32 = -1.0;
	for (const cast of casts) {
		const d: float32 = cast(ray);
		if (Number.isNaN(d)) { return Result.err(OptimizedColliderError.NonFinite); }
		if (d >= 0.0) {
			if (!bestMatch) { return Result.ok(d); }
			if (best < 0.0 || d < best) { best = d; }
		}
	}
	return Result.ok(best);
}
