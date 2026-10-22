import { Vec3, vec3 } from "../math/math3d";

export struct Wide3 {
	x: float64;
	y: float64;
	z: float64;
}

export const FLOAT32_LIMIT: float64 = 3.4028234663852886e38;

export function wide(v: Vec3): Wide3 {
	return { x: v.x as float64, y: v.y as float64, z: v.z as float64 };
}

export function wideSub(a: Wide3, b: Wide3): Wide3 {
	return { x: a.x - b.x, y: a.y - b.y, z: a.z - b.z };
}

export function wideAdd(a: Wide3, b: Wide3): Wide3 {
	return { x: a.x + b.x, y: a.y + b.y, z: a.z + b.z };
}

export function wideScaled(a: Wide3, k: float64): Wide3 {
	return { x: a.x * k, y: a.y * k, z: a.z * k };
}

export function wideDot(a: Wide3, b: Wide3): float64 {
	return a.x * b.x + a.y * b.y + a.z * b.z;
}

export function wideCross(a: Wide3, b: Wide3): Wide3 {
	return { x: a.y * b.z - a.z * b.y, y: a.z * b.x - a.x * b.z, z: a.x * b.y - a.y * b.x };
}

export function finiteVec(v: Vec3): boolean {
	return Number.isFinite(v.x) && Number.isFinite(v.y) && Number.isFinite(v.z);
}

export function fitsFloat32(v: Wide3): boolean {
	return Math.abs(v.x) <= FLOAT32_LIMIT && Math.abs(v.y) <= FLOAT32_LIMIT &&
		Math.abs(v.z) <= FLOAT32_LIMIT;
}

export function narrowed(v: Wide3): Vec3 {
	return vec3(v.x as float32, v.y as float32, v.z as float32);
}
