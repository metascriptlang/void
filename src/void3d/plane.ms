import { Vec3, Vec4, vec3 } from "../math/math3d";

export enum PlaneError { NonFinite, NonUnitNormal, OutOfRange }

export function signedPlaneDistance(
	plane: Vec4, point: Vec3,
): Result<float64, PlaneError> {
	if (!Number.isFinite(plane.x) || !Number.isFinite(plane.y) || !Number.isFinite(plane.z) ||
		!Number.isFinite(plane.w) || !Number.isFinite(point.x) ||
		!Number.isFinite(point.y) || !Number.isFinite(point.z)) {
		return Result.err(PlaneError.NonFinite);
	}
	const lengthSquared: float64 = (plane.x as float64) * plane.x +
		(plane.y as float64) * plane.y + (plane.z as float64) * plane.z;
	if (Math.abs(lengthSquared - 1.0) > 0.00001) {
		return Result.err(PlaneError.NonUnitNormal);
	}
	const distance: float64 = (plane.x as float64) * point.x +
		(plane.y as float64) * point.y + (plane.z as float64) * point.z + plane.w;
	return Result.ok(distance);
}

export function projectPointToPlane(
	plane: Vec4, point: Vec3,
): Result<Vec3, PlaneError> {
	const distance: float64 = try signedPlaneDistance(plane, point);
	const x: float64 = (point.x as float64) - distance * plane.x;
	const y: float64 = (point.y as float64) - distance * plane.y;
	const z: float64 = (point.z as float64) - distance * plane.z;
	const float32Max: float64 = 3.4028234663852886e38;
	if (Math.abs(x) > float32Max || Math.abs(y) > float32Max || Math.abs(z) > float32Max) {
		return Result.err(PlaneError.OutOfRange);
	}
	return Result.ok(vec3(x as float32, y as float32, z as float32));
}
