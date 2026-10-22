import { Vec3 } from "../math/math3d";

export struct OrientedBounds3D {
	center: Vec3;
	axisX: Vec3;
	axisY: Vec3;
	axisZ: Vec3;
	halfSize: Vec3;
}

export enum OrientedBoundsError { NonFinite, NegativeHalfSize, NonOrthonormalAxes }

function finitePoint(p: Vec3): boolean {
	return Number.isFinite(p.x) && Number.isFinite(p.y) && Number.isFinite(p.z);
}

function finiteBounds(b: OrientedBounds3D): boolean {
	return finitePoint(b.center) && finitePoint(b.axisX) && finitePoint(b.axisY) &&
		finitePoint(b.axisZ) && finitePoint(b.halfSize);
}

function wideDot(a: Vec3, b: Vec3): float64 {
	return (a.x as float64) * b.x + (a.y as float64) * b.y + (a.z as float64) * b.z;
}

function orthonormal(b: OrientedBounds3D): boolean {
	const tolerance: float64 = 0.00001;
	return Math.abs(wideDot(b.axisX, b.axisX) - 1) <= tolerance &&
		Math.abs(wideDot(b.axisY, b.axisY) - 1) <= tolerance &&
		Math.abs(wideDot(b.axisZ, b.axisZ) - 1) <= tolerance &&
		Math.abs(wideDot(b.axisX, b.axisY)) <= tolerance &&
		Math.abs(wideDot(b.axisX, b.axisZ)) <= tolerance &&
		Math.abs(wideDot(b.axisY, b.axisZ)) <= tolerance;
}

export function validateOrientedBounds(b: OrientedBounds3D): Result<int32, OrientedBoundsError> {
	if (!finiteBounds(b)) { return Result.err(OrientedBoundsError.NonFinite); }
	if (b.halfSize.x < 0 || b.halfSize.y < 0 || b.halfSize.z < 0) {
		return Result.err(OrientedBoundsError.NegativeHalfSize);
	}
	if (!orthonormal(b)) { return Result.err(OrientedBoundsError.NonOrthonormalAxes); }
	return Result.ok(0);
}

export function overlapsOrientedBounds(
	a: OrientedBounds3D, b: OrientedBounds3D,
): Result<boolean, OrientedBoundsError> {
	if (!finiteBounds(a) || !finiteBounds(b)) { return Result.err(OrientedBoundsError.NonFinite); }
	if (a.halfSize.x < 0 || a.halfSize.y < 0 || a.halfSize.z < 0 ||
		b.halfSize.x < 0 || b.halfSize.y < 0 || b.halfSize.z < 0) {
		return Result.err(OrientedBoundsError.NegativeHalfSize);
	}
	if (!orthonormal(a) || !orthonormal(b)) {
		return Result.err(OrientedBoundsError.NonOrthonormalAxes);
	}
	const r00: float64 = wideDot(a.axisX, b.axisX);
	const r01: float64 = wideDot(a.axisX, b.axisY);
	const r02: float64 = wideDot(a.axisX, b.axisZ);
	const r10: float64 = wideDot(a.axisY, b.axisX);
	const r11: float64 = wideDot(a.axisY, b.axisY);
	const r12: float64 = wideDot(a.axisY, b.axisZ);
	const r20: float64 = wideDot(a.axisZ, b.axisX);
	const r21: float64 = wideDot(a.axisZ, b.axisY);
	const r22: float64 = wideDot(a.axisZ, b.axisZ);
	const dx: float64 = (b.center.x as float64) - a.center.x;
	const dy: float64 = (b.center.y as float64) - a.center.y;
	const dz: float64 = (b.center.z as float64) - a.center.z;
	const tx: float64 = dx * a.axisX.x + dy * a.axisX.y + dz * a.axisX.z;
	const ty: float64 = dx * a.axisY.x + dy * a.axisY.y + dz * a.axisY.z;
	const tz: float64 = dx * a.axisZ.x + dy * a.axisZ.y + dz * a.axisZ.z;
	const epsilon: float64 = 1.0e-10;
	const abs00: float64 = Math.abs(r00) + epsilon;
	const abs01: float64 = Math.abs(r01) + epsilon;
	const abs02: float64 = Math.abs(r02) + epsilon;
	const abs10: float64 = Math.abs(r10) + epsilon;
	const abs11: float64 = Math.abs(r11) + epsilon;
	const abs12: float64 = Math.abs(r12) + epsilon;
	const abs20: float64 = Math.abs(r20) + epsilon;
	const abs21: float64 = Math.abs(r21) + epsilon;
	const abs22: float64 = Math.abs(r22) + epsilon;
	let radiusA: float64 = a.halfSize.x;
	let radiusB: float64 = b.halfSize.x * abs00 + b.halfSize.y * abs01 + b.halfSize.z * abs02;
	if (Math.abs(tx) > radiusA + radiusB) { return Result.ok(false); }
	radiusA = a.halfSize.y;
	radiusB = b.halfSize.x * abs10 + b.halfSize.y * abs11 + b.halfSize.z * abs12;
	if (Math.abs(ty) > radiusA + radiusB) { return Result.ok(false); }
	radiusA = a.halfSize.z;
	radiusB = b.halfSize.x * abs20 + b.halfSize.y * abs21 + b.halfSize.z * abs22;
	if (Math.abs(tz) > radiusA + radiusB) { return Result.ok(false); }
	radiusA = a.halfSize.x * abs00 + a.halfSize.y * abs10 + a.halfSize.z * abs20;
	radiusB = b.halfSize.x;
	if (Math.abs(tx * r00 + ty * r10 + tz * r20) > radiusA + radiusB) { return Result.ok(false); }
	radiusA = a.halfSize.x * abs01 + a.halfSize.y * abs11 + a.halfSize.z * abs21;
	radiusB = b.halfSize.y;
	if (Math.abs(tx * r01 + ty * r11 + tz * r21) > radiusA + radiusB) { return Result.ok(false); }
	radiusA = a.halfSize.x * abs02 + a.halfSize.y * abs12 + a.halfSize.z * abs22;
	radiusB = b.halfSize.z;
	if (Math.abs(tx * r02 + ty * r12 + tz * r22) > radiusA + radiusB) { return Result.ok(false); }
	radiusA = a.halfSize.y * abs20 + a.halfSize.z * abs10;
	radiusB = b.halfSize.y * abs02 + b.halfSize.z * abs01;
	if (Math.abs(tz * r10 - ty * r20) > radiusA + radiusB) { return Result.ok(false); }
	radiusA = a.halfSize.y * abs21 + a.halfSize.z * abs11;
	radiusB = b.halfSize.x * abs02 + b.halfSize.z * abs00;
	if (Math.abs(tz * r11 - ty * r21) > radiusA + radiusB) { return Result.ok(false); }
	radiusA = a.halfSize.y * abs22 + a.halfSize.z * abs12;
	radiusB = b.halfSize.x * abs01 + b.halfSize.y * abs00;
	if (Math.abs(tz * r12 - ty * r22) > radiusA + radiusB) { return Result.ok(false); }
	radiusA = a.halfSize.x * abs20 + a.halfSize.z * abs00;
	radiusB = b.halfSize.y * abs12 + b.halfSize.z * abs11;
	if (Math.abs(tx * r20 - tz * r00) > radiusA + radiusB) { return Result.ok(false); }
	radiusA = a.halfSize.x * abs21 + a.halfSize.z * abs01;
	radiusB = b.halfSize.x * abs12 + b.halfSize.z * abs10;
	if (Math.abs(tx * r21 - tz * r01) > radiusA + radiusB) { return Result.ok(false); }
	radiusA = a.halfSize.x * abs22 + a.halfSize.z * abs02;
	radiusB = b.halfSize.x * abs11 + b.halfSize.y * abs10;
	if (Math.abs(tx * r22 - tz * r02) > radiusA + radiusB) { return Result.ok(false); }
	radiusA = a.halfSize.x * abs10 + a.halfSize.y * abs00;
	radiusB = b.halfSize.y * abs22 + b.halfSize.z * abs21;
	if (Math.abs(ty * r00 - tx * r10) > radiusA + radiusB) { return Result.ok(false); }
	radiusA = a.halfSize.x * abs11 + a.halfSize.y * abs01;
	radiusB = b.halfSize.x * abs22 + b.halfSize.z * abs20;
	if (Math.abs(ty * r01 - tx * r11) > radiusA + radiusB) { return Result.ok(false); }
	radiusA = a.halfSize.x * abs12 + a.halfSize.y * abs02;
	radiusB = b.halfSize.x * abs21 + b.halfSize.y * abs20;
	if (Math.abs(ty * r02 - tx * r12) > radiusA + radiusB) { return Result.ok(false); }
	return Result.ok(true);
}
