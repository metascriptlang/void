// Port of h3d.col.Cylinder: a flat-capped cylinder of radius `radius` around the axis a..b.

import { Vec3, vec3 } from "../math/math3d";
import { Ray } from "./ray";
import { Sphere3D, overlaps } from "./sphere";
import { Frustum3D, intersectsSphere } from "./frustum";
import {
	Wide3, wide, wideSub, wideAdd, wideScaled, wideDot, finiteVec, FLOAT32_LIMIT,
} from "./colliderMath";

export struct Cylinder3D {
	a: Vec3;
	b: Vec3;
	radius: float32;
}

export enum CylinderError { NonFinite, NegativeRadius, ZeroLengthAxis, OutOfRange }

// sin^2 of the angle below which the ray counts as parallel to the axis.
// PENDING3D: cylinder-ray-parallel-to-axis
const PARALLEL: float64 = 1.0e-12;

function validate(cylinder: Cylinder3D): Result<int32, CylinderError> {
	if (!finiteVec(cylinder.a) || !finiteVec(cylinder.b) || !Number.isFinite(cylinder.radius)) {
		return Result.err(CylinderError.NonFinite);
	}
	if (cylinder.radius < 0.0) { return Result.err(CylinderError.NegativeRadius); }
	const axis: Wide3 = wideSub(wide(cylinder.b), wide(cylinder.a));
	if (wideDot(axis, axis) == 0.0) { return Result.err(CylinderError.ZeroLengthAxis); }
	return Result.ok(0);
}

// Cylinder.hx:46-51. Heaps divides by |b - a|^2 here, so a zero-length axis never contains.
export function contains(this cylinder: Cylinder3D, point: Vec3): Result<boolean, CylinderError> {
	const _valid: int32 = try validate(cylinder);
	if (!finiteVec(point)) { return Result.err(CylinderError.NonFinite); }
	const a: Wide3 = wide(cylinder.a);
	const axis: Wide3 = wideSub(wide(cylinder.b), a);
	const p: Wide3 = wide(point);
	const t: float64 = wideDot(wideSub(p, a), axis) / wideDot(axis, axis);
	if (t < 0.0 || t > 1.0) { return Result.ok(false); }
	const offset: Wide3 = wideSub(p, wideAdd(a, wideScaled(axis, t)));
	const radius: float64 = cylinder.radius as float64;
	return Result.ok(wideDot(offset, offset) < radius * radius);
}

// Cylinder.hx:16-44. A ray parallel to the axis makes Heaps divide by a = 0, and the cap test
// `|b + a t| < hs` then compares |b| with |b|, so such a ray never hits a cap. That case hits the
// nearer cap plane when the ray runs inside the radius. As in Heaps an origin inside is a miss.
export function rayIntersection(
	this cylinder: Cylinder3D, ray: Ray,
): Result<float32, CylinderError> {
	const _valid: int32 = try validate(cylinder);
	if (!finiteVec(ray.origin) || !finiteVec(ray.direction)) {
		return Result.err(CylinderError.NonFinite);
	}
	const ro: Wide3 = wide(ray.origin);
	const rd: Wide3 = wide(ray.direction);
	const ra: float64 = cylinder.radius as float64;
	const pa: Wide3 = wide(cylinder.a);
	const ba: Wide3 = wideSub(wide(cylinder.b), pa);
	const oa: Wide3 = wideSub(ro, pa);
	const baba: float64 = wideDot(ba, ba);
	const bard: float64 = wideDot(ba, rd);
	const baoa: float64 = wideDot(ba, oa);
	const rdoa: float64 = wideDot(rd, oa);
	const oaoa: float64 = wideDot(oa, oa);
	const a: float64 = baba - bard * bard;
	const b: float64 = baba * rdoa - baoa * bard;
	const c: float64 = baba * oaoa - baoa * baoa - ra * ra * baba;
	let result: float64 = -1.0;
	if (a <= PARALLEL * baba) {
		if (c <= 0.0 && bard != 0.0) {
			const toA: float64 = -baoa / bard;
			const toB: float64 = (baba - baoa) / bard;
			const entry: float64 = Math.min(toA, toB);
			if (entry >= 0.0) { result = entry; }
		}
	} else {
		const h: float64 = b * b - a * c;
		if (h >= 0.0) {
			const hs: float64 = Math.sqrt(h);
			const t: float64 = (-b - hs) / a;
			const y: float64 = baoa + t * bard;
			if (y > 0.0 && y < baba) {
				result = t;
			} else if (bard != 0.0) {
				const cap: float64 = ((y < 0.0 ? 0.0 : baba) - baoa) / bard;
				if (Math.abs(b + a * cap) < hs) { result = cap; }
			}
		}
	}
	if (result > FLOAT32_LIMIT) { return Result.err(CylinderError.OutOfRange); }
	return Result.ok(result as float32);
}

// Cylinder.hx:69-72: the diameter of the sphere through a rim point of each cap.
export function dimension(this cylinder: Cylinder3D): Result<float64, CylinderError> {
	const _valid: int32 = try validate(cylinder);
	const axis: Wide3 = wideSub(wide(cylinder.b), wide(cylinder.a));
	const half: float64 = Math.sqrt(wideDot(axis, axis)) * 0.5;
	const radius: float64 = cylinder.radius as float64;
	return Result.ok(2.0 * Math.sqrt(half * half + radius * radius));
}

// Cylinder.hx:53-58 and 60-63 load a sphere at a + (b - a), which is b, with radius
// dimension() / 2. That radius bounds a sphere at the midpoint, so the centre here is the
// midpoint.
// PENDING3D: cylinder-bounding-sphere-centre-at-b
export function boundingSphere(this cylinder: Cylinder3D): Result<Sphere3D, CylinderError> {
	const size: float64 = try cylinder.dimension();
	const a: Wide3 = wide(cylinder.a);
	const mid: Wide3 = wideAdd(a, wideScaled(wideSub(wide(cylinder.b), a), 0.5));
	const radius: float64 = size * 0.5;
	if (Math.abs(mid.x) > FLOAT32_LIMIT || Math.abs(mid.y) > FLOAT32_LIMIT ||
		Math.abs(mid.z) > FLOAT32_LIMIT || radius > FLOAT32_LIMIT) {
		return Result.err(CylinderError.OutOfRange);
	}
	return Result.ok({
		center: vec3(mid.x as float32, mid.y as float32, mid.z as float32),
		radius: radius as float32,
	});
}

export function inFrustum(
	this cylinder: Cylinder3D, frustum: Frustum3D,
): Result<boolean, CylinderError> {
	const sphere: Sphere3D = try cylinder.boundingSphere();
	return Result.ok(frustum.intersectsSphere(sphere.center, sphere.radius));
}

export function inSphere(
	this cylinder: Cylinder3D, other: Sphere3D,
): Result<boolean, CylinderError> {
	const sphere: Sphere3D = try cylinder.boundingSphere();
	if (!finiteVec(other.center) || !Number.isFinite(other.radius)) {
		return Result.err(CylinderError.NonFinite);
	}
	return Result.ok(sphere.overlaps(other));
}
