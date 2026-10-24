// Port of h3d.col.Capsule: the segment a..b swept by a sphere of radius `radius`.

import { Vec3, vec3 } from "../math/math3d";
import { Ray } from "./ray";
import { Sphere3D, overlaps } from "./sphere";
import { Frustum3D, intersectsSphere } from "./frustum";
import { Segment3D, distanceSquared } from "./segment";
import {
	Wide3, wide, wideSub, wideAdd, wideScaled, wideDot, finiteVec, FLOAT32_LIMIT,
} from "./colliderMath";

export struct Capsule3D {
	a: Vec3;
	b: Vec3;
	radius: float32;
}

export enum CapsuleError { NonFinite, NegativeRadius, ZeroLengthAxis, OutOfRange }

// sin^2 of the angle below which the ray counts as parallel to the axis.
// PENDING3D: capsule-ray-parallel-to-axis
const PARALLEL: float64 = 1.0e-12;

function validate(capsule: Capsule3D): Result<int32, CapsuleError> {
	if (!finiteVec(capsule.a) || !finiteVec(capsule.b) || !Number.isFinite(capsule.radius)) {
		return Result.err(CapsuleError.NonFinite);
	}
	if (capsule.radius < 0.0) { return Result.err(CapsuleError.NegativeRadius); }
	const axis: Wide3 = wideSub(wide(capsule.b), wide(capsule.a));
	if (wideDot(axis, axis) == 0.0) { return Result.err(CapsuleError.ZeroLengthAxis); }
	return Result.ok(0);
}

function axisLength(capsule: Capsule3D): float64 {
	const axis: Wide3 = wideSub(wide(capsule.b), wide(capsule.a));
	return Math.sqrt(wideDot(axis, axis));
}

// Capsule.hx:16-18.
export function contains(this capsule: Capsule3D, point: Vec3): Result<boolean, CapsuleError> {
	const _valid: int32 = try validate(capsule);
	const seg: Segment3D = { p1: capsule.a, p2: capsule.b };
	const squared = seg.distanceSquared(point);
	if (!squared.ok) { return Result.err(CapsuleError.NonFinite); }
	const radius: float64 = capsule.radius as float64;
	return Result.ok(squared.value < radius * radius);
}

function sphereEntry(offset: Wide3, direction: Wide3, radius: float64): float64 {
	const b: float64 = wideDot(direction, offset);
	const c: float64 = wideDot(offset, offset) - radius * radius;
	const h: float64 = b * b - c;
	if (h > 0.0) { return -b - Math.sqrt(h); }
	return -1.0;
}

// Capsule.hx:20-50, after iquilezles.org/articles/intersectors. A ray parallel to the axis makes
// Heaps divide by a = 0; along the axis the cylinder term is 0/0, so only the cap at b is ever
// tested and a ray entering at a reports the far cap or a miss. That case tests both end spheres
// and takes the nearer entry. As in Heaps an origin inside the capsule is a miss (negative).
export function rayIntersection(this capsule: Capsule3D, ray: Ray): Result<float32, CapsuleError> {
	const _valid: int32 = try validate(capsule);
	if (!finiteVec(ray.origin) || !finiteVec(ray.direction)) {
		return Result.err(CapsuleError.NonFinite);
	}
	const ro: Wide3 = wide(ray.origin);
	const rd: Wide3 = wide(ray.direction);
	const ra: float64 = capsule.radius as float64;
	const pa: Wide3 = wide(capsule.a);
	const pb: Wide3 = wide(capsule.b);
	const ba: Wide3 = wideSub(pb, pa);
	const oa: Wide3 = wideSub(ro, pa);
	const baba: float64 = wideDot(ba, ba);
	const bard: float64 = wideDot(ba, rd);
	const baoa: float64 = wideDot(ba, oa);
	const rdoa: float64 = wideDot(rd, oa);
	const oaoa: float64 = wideDot(oa, oa);
	const a: float64 = baba - bard * bard;
	let result: float64 = -1.0;
	if (a <= PARALLEL * baba) {
		const inside = capsule.contains(ray.origin);
		if (inside.ok && !inside.value) {
			const toA: float64 = sphereEntry(oa, rd, ra);
			const toB: float64 = sphereEntry(wideSub(ro, pb), rd, ra);
			if (toA >= 0.0) { result = toA; }
			if (toB >= 0.0 && (result < 0.0 || toB < result)) { result = toB; }
		}
	} else {
		const b: float64 = baba * rdoa - baoa * bard;
		const c: float64 = baba * oaoa - baoa * baoa - ra * ra * baba;
		const h: float64 = b * b - a * c;
		if (h >= 0.0) {
			const t: float64 = (-b - Math.sqrt(h)) / a;
			const y: float64 = baoa + t * bard;
			if (y > 0.0 && y < baba) {
				result = t;
			} else {
				result = sphereEntry(y <= 0.0 ? oa : wideSub(ro, pb), rd, ra);
			}
		}
	}
	if (result > FLOAT32_LIMIT) { return Result.err(CapsuleError.OutOfRange); }
	return Result.ok(result as float32);
}

// Capsule.hx:69-71.
export function dimension(this capsule: Capsule3D): Result<float64, CapsuleError> {
	const _valid: int32 = try validate(capsule);
	return Result.ok(axisLength(capsule) + 2.0 * (capsule.radius as float64));
}

// Capsule.hx:53-57 and 60-63 load a sphere at a + (b - a), which is b, with radius
// |b - a| / 2 + r. The radius bounds a sphere at the midpoint, so the centre here is the
// midpoint; centred on b the sphere misses the half of the capsule around a.
// PENDING3D: capsule-bounding-sphere-centre-at-b
export function boundingSphere(this capsule: Capsule3D): Result<Sphere3D, CapsuleError> {
	const _valid: int32 = try validate(capsule);
	const delta: Wide3 = wideSub(wide(capsule.b), wide(capsule.a));
	const mid: Wide3 = wideAdd(wide(capsule.a), wideScaled(delta, 0.5));
	const radius: float64 = axisLength(capsule) * 0.5 + (capsule.radius as float64);
	if (Math.abs(mid.x) > FLOAT32_LIMIT || Math.abs(mid.y) > FLOAT32_LIMIT ||
		Math.abs(mid.z) > FLOAT32_LIMIT || radius > FLOAT32_LIMIT) {
		return Result.err(CapsuleError.OutOfRange);
	}
	return Result.ok({
		center: vec3(mid.x as float32, mid.y as float32, mid.z as float32),
		radius: radius as float32,
	});
}

export function inFrustum(
	this capsule: Capsule3D, frustum: Frustum3D,
): Result<boolean, CapsuleError> {
	const sphere: Sphere3D = try capsule.boundingSphere();
	return Result.ok(frustum.intersectsSphere(sphere.center, sphere.radius));
}

export function inSphere(this capsule: Capsule3D, other: Sphere3D): Result<boolean, CapsuleError> {
	const sphere: Sphere3D = try capsule.boundingSphere();
	if (!finiteVec(other.center) || !Number.isFinite(other.radius)) {
		return Result.err(CapsuleError.NonFinite);
	}
	return Result.ok(sphere.overlaps(other));
}
