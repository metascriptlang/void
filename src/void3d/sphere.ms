import { Vec3 } from "../math/math3d";

export struct Sphere3D {
	center: Vec3;
	radius: float32;
}

function distanceSquared(first: Vec3, second: Vec3): float64 {
	const dx: float64 = (first.x as float64) - (second.x as float64);
	const dy: float64 = (first.y as float64) - (second.y as float64);
	const dz: float64 = (first.z as float64) - (second.z as float64);
	return dx * dx + dy * dy + dz * dz;
}

export function contains(this sphere: Sphere3D, point: Vec3): boolean {
	const radius: float64 = sphere.radius as float64;
	return distanceSquared(sphere.center, point) - radius * radius < 0.0;
}

export function overlaps(this sphere: Sphere3D, other: Sphere3D): boolean {
	const radius: float64 = (sphere.radius as float64) + (other.radius as float64);
	return distanceSquared(sphere.center, other.center) < radius * radius;
}
