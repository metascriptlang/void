import { Vec3, vec3 } from "../math/math3d";

export struct Sphere3D {
	center: Vec3;
	radius: float32;
}

export enum SpherePointError {
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

export function contains(this sphere: Sphere3D, point: Vec3): boolean {
	const radius: float64 = sphere.radius as float64;
	return distanceSquared(sphere.center, point) - radius * radius < 0.0;
}

export function overlaps(this sphere: Sphere3D, other: Sphere3D): boolean {
	const radius: float64 = (sphere.radius as float64) + (other.radius as float64);
	return distanceSquared(sphere.center, other.center) < radius * radius;
}
