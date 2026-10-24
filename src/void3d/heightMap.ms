// Port of h3d.col.HeightMap: a collider over a height function z = getZ(x, y), cast by marching.

import { Vec3 } from "../math/math3d";
import { Ray } from "./ray";
import { finiteVec } from "./colliderMath";

export enum HeightMapError {
	NonFinite,
	InvalidStep,
	InvalidPrecision,
	InvalidRange,
	NonFiniteHeight,
}

// HeightMap.hx:29-31.
export function heightMapContains(getZ: (x: float32, y: float32) => float32, point: Vec3): boolean {
	return getZ(point.x, point.y) > point.z;
}

// HeightMap.hx:45-89. Marches `step` at a time along the ray until the surface is above the ray,
// then bisects the last interval to `precision`. Two things differ from Heaps:
//  - its bisection reads the height at the interval's end (`dist`) instead of the midpoint `d`,
//    so it always narrows toward the last sample before the surface and answers up to one step
//    short; this evaluates at the midpoint;
//  - its march has no end (a flat or rising surface below a falling ray is the only exit, and a
//    NaN height never exits), so the march stops at `maxDistance` and answers a miss.
// A ray looking up or nearly level, or starting under the surface, is a miss as in Heaps.
// PENDING3D: heightmap-bisect-at-interval-end
export function heightMapRayIntersection(
	getZ: (x: float32, y: float32) => float32, ray: Ray,
	step: float32, precision: float32, maxDistance: float32,
): Result<float32, HeightMapError> {
	if (!finiteVec(ray.origin) || !finiteVec(ray.direction)) {
		return Result.err(HeightMapError.NonFinite);
	}
	if (!Number.isFinite(step) || step <= 0.0) { return Result.err(HeightMapError.InvalidStep); }
	if (!Number.isFinite(precision) || precision <= 0.0) {
		return Result.err(HeightMapError.InvalidPrecision);
	}
	if (!Number.isFinite(maxDistance) || maxDistance <= 0.0) {
		return Result.err(HeightMapError.InvalidRange);
	}
	const px: float64 = ray.origin.x as float64;
	const py: float64 = ray.origin.y as float64;
	const pz: float64 = ray.origin.z as float64;
	const lx: float64 = ray.direction.x as float64;
	const ly: float64 = ray.direction.y as float64;
	const lz: float64 = ray.direction.z as float64;
	if (lz >= -(precision as float64)) { return Result.ok(-1.0); }
	const start: float32 = getZ(ray.origin.x, ray.origin.y);
	if (!Number.isFinite(start)) { return Result.err(HeightMapError.NonFiniteHeight); }
	if (start > ray.origin.z) { return Result.ok(-1.0); }
	const stride: float64 = step as float64;
	const limit: float64 = maxDistance as float64;
	let dist: float64 = stride;
	let found: boolean = false;
	while (dist <= limit + stride) {
		const h: float32 = getZ((px + lx * dist) as float32, (py + ly * dist) as float32);
		if (!Number.isFinite(h)) { return Result.err(HeightMapError.NonFiniteHeight); }
		if ((h as float64) > pz + lz * dist) { found = true; break; }
		dist += stride;
	}
	if (!found) { return Result.ok(-1.0); }
	let dmin: float64 = dist - stride;
	let dmax: float64 = dist;
	const prec: float64 = precision as float64;
	while (true) {
		const d: float64 = (dmin + dmax) * 0.5;
		if (dmax - dmin < prec) { return Result.ok(d as float32); }
		const h: float32 = getZ((px + lx * d) as float32, (py + ly * d) as float32);
		if (!Number.isFinite(h)) { return Result.err(HeightMapError.NonFiniteHeight); }
		if ((h as float64) > pz + lz * d) { dmax = d; } else { dmin = d; }
	}
}
