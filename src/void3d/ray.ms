// Port of h3d.col.Ray: an origin and a unit direction.

import { Vec3, Vec4, Mat4, vec3 } from "../math/math3d";

export struct Ray {
	origin: Vec3;
	direction: Vec3;
}

export function fromPoints(this typeof Ray, from: Vec3, to: Vec3): Ray {
	return { origin: from, direction: (to - from).normalized() };
}

// h3d.col.Ray.transform: the origin as a point, the direction as a vector, renormalized.
export function transformed(this ray: Ray, matrix: Mat4): Ray {
	return {
		origin: ray.origin * matrix,
		direction: ray.direction.transformDirection(matrix).normalized(),
	};
}

export function pointAt(this ray: Ray, distance: float32): Vec3 {
	return ray.origin + ray.direction.scaled(distance);
}

export enum RayPlaneError {
	NonFinite,
	OutOfRange,
}

const FLOAT32_MAX: float64 = 3.4028234663852886e38;

function finitePoint(point: Vec3): boolean {
	return Number.isFinite(point.x) && Number.isFinite(point.y) && Number.isFinite(point.z);
}

export function linePlaneIntersection(
	this ray: Ray,
	plane: Vec4,
): Result<Vec3 | null, RayPlaneError> {
	if (!finitePoint(ray.origin) || !finitePoint(ray.direction) ||
		!Number.isFinite(plane.x) || !Number.isFinite(plane.y) ||
		!Number.isFinite(plane.z) || !Number.isFinite(plane.w)) {
		return Result.err(RayPlaneError.NonFinite);
	}
	const denominator: float64 =
		(ray.direction.x as float64) * (plane.x as float64) +
		(ray.direction.y as float64) * (plane.y as float64) +
		(ray.direction.z as float64) * (plane.z as float64);
	const offset: float64 = -(plane.w as float64) - (
		(ray.origin.x as float64) * (plane.x as float64) +
		(ray.origin.y as float64) * (plane.y as float64) +
		(ray.origin.z as float64) * (plane.z as float64)
	);
	if (Math.abs(denominator) < 1.0e-10) {
		const hit: Vec3 | null = Math.abs(offset) < 1.0e-10 ? ray.origin : null;
		return Result.ok(hit);
	}
	const distance: float64 = offset / denominator;
	const x: float64 = (ray.origin.x as float64) + (ray.direction.x as float64) * distance;
	const y: float64 = (ray.origin.y as float64) + (ray.direction.y as float64) * distance;
	const z: float64 = (ray.origin.z as float64) + (ray.direction.z as float64) * distance;
	if (Math.abs(x) > FLOAT32_MAX || Math.abs(y) > FLOAT32_MAX || Math.abs(z) > FLOAT32_MAX) {
		return Result.err(RayPlaneError.OutOfRange);
	}
	const hit: Vec3 | null = vec3(x as float32, y as float32, z as float32);
	return Result.ok(hit);
}
