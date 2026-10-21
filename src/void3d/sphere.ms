import { Vec3, vec3 } from "../math/math3d";
import { Ray } from "./ray";

export struct Sphere3D {
	center: Vec3;
	radius: float32;
}

export enum SpherePointError {
	NonFinite,
	OutOfRange,
}

export enum SphereRayError {
	NonFinite,
	OutOfRange,
}

function distanceSquared(first: Vec3, second: Vec3): float64 {
	const dx: float64 = (first.x as float64) - (second.x as float64);
	const dy: float64 = (first.y as float64) - (second.y as float64);
	const dz: float64 = (first.z as float64) - (second.z as float64);
	return dx * dx + dy * dy + dz * dz;
}

export function closestPoint(this sphere: Sphere3D, point: Vec3): Result<Vec3, SpherePointError> {
	if (!Number.isFinite(sphere.center.x) || !Number.isFinite(sphere.center.y)
		|| !Number.isFinite(sphere.center.z) || !Number.isFinite(sphere.radius)
		|| !Number.isFinite(point.x) || !Number.isFinite(point.y) || !Number.isFinite(point.z)) {
		return Result.err(SpherePointError.NonFinite);
	}
	const squared: float64 = distanceSquared(sphere.center, point);
	const inverse: float64 = squared < 1.0e-20 ? 0.0 : 1.0 / Math.sqrt(squared);
	const radius: float64 = sphere.radius as float64;
	const x: float64 = (sphere.center.x as float64)
		+ (((point.x as float64) - (sphere.center.x as float64)) * inverse) * radius;
	const y: float64 = (sphere.center.y as float64)
		+ (((point.y as float64) - (sphere.center.y as float64)) * inverse) * radius;
	const z: float64 = (sphere.center.z as float64)
		+ (((point.z as float64) - (sphere.center.z as float64)) * inverse) * radius;
	const limit: float64 = 3.4028234663852886e38;
	if (Math.abs(x) > limit || Math.abs(y) > limit || Math.abs(z) > limit) {
		return Result.err(SpherePointError.OutOfRange);
	}
	return Result.ok(vec3(x as float32, y as float32, z as float32));
}

export function rayIntersection(this sphere: Sphere3D, ray: Ray): Result<float32, SphereRayError> {
	if (!Number.isFinite(sphere.center.x) || !Number.isFinite(sphere.center.y)
		|| !Number.isFinite(sphere.center.z) || !Number.isFinite(sphere.radius)
		|| !Number.isFinite(ray.origin.x) || !Number.isFinite(ray.origin.y)
		|| !Number.isFinite(ray.origin.z) || !Number.isFinite(ray.direction.x)
		|| !Number.isFinite(ray.direction.y) || !Number.isFinite(ray.direction.z)) {
		return Result.err(SphereRayError.NonFinite);
	}
	const mx: float64 = (ray.origin.x as float64) - (sphere.center.x as float64);
	const my: float64 = (ray.origin.y as float64) - (sphere.center.y as float64);
	const mz: float64 = (ray.origin.z as float64) - (sphere.center.z as float64);
	const b: float64 = mx * (ray.direction.x as float64)
		+ my * (ray.direction.y as float64) + mz * (ray.direction.z as float64);
	const radius: float64 = sphere.radius as float64;
	const c: float64 = mx * mx + my * my + mz * mz - radius * radius;
	if (c > 0.0 && b > 0.0) { return Result.ok(-1.0); }
	const discriminant: float64 = b * b - c;
	if (discriminant < 0.0) { return Result.ok(-1.0); }
	const distance: float64 = Math.max(0.0, -b - Math.sqrt(discriminant));
	if (distance > 3.4028234663852886e38) { return Result.err(SphereRayError.OutOfRange); }
	return Result.ok(distance as float32);
}

export function contains(this sphere: Sphere3D, point: Vec3): boolean {
	const radius: float64 = sphere.radius as float64;
	return distanceSquared(sphere.center, point) - radius * radius < 0.0;
}

export function overlaps(this sphere: Sphere3D, other: Sphere3D): boolean {
	const radius: float64 = (sphere.radius as float64) + (other.radius as float64);
	return distanceSquared(sphere.center, other.center) < radius * radius;
}
