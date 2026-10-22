// Port of h3d.col.TransformCollider: a collider placed by a matrix. The wrapped collider is any of
// the colliders here; this carries the matrix pair and the conversions between its local space
// and the world, so a caller casts the local ray against the collider and converts the answer.

import { Vec3, Mat4, vec3, inverse, multiplyAffine } from "../math/math3d";
import { Ray, transformed } from "./ray";
import { Sphere3D } from "./sphere";
import { finiteVec, FLOAT32_LIMIT } from "./colliderMath";

export struct TransformFrame {
	mat: Mat4;
	invMat: Mat4;
}

export enum TransformError { NonFinite, Singular, OutOfRange }

function finiteMatrix(m: Mat4): boolean {
	return Number.isFinite(m.m11) && Number.isFinite(m.m12) && Number.isFinite(m.m13) &&
		Number.isFinite(m.m14) && Number.isFinite(m.m21) && Number.isFinite(m.m22) &&
		Number.isFinite(m.m23) && Number.isFinite(m.m24) && Number.isFinite(m.m31) &&
		Number.isFinite(m.m32) && Number.isFinite(m.m33) && Number.isFinite(m.m34) &&
		Number.isFinite(m.m41) && Number.isFinite(m.m42) && Number.isFinite(m.m43) &&
		Number.isFinite(m.m44);
}

function isZero(m: Mat4): boolean {
	return m.m11 == 0.0 && m.m12 == 0.0 && m.m13 == 0.0 && m.m14 == 0.0 &&
		m.m21 == 0.0 && m.m22 == 0.0 && m.m23 == 0.0 && m.m24 == 0.0 &&
		m.m31 == 0.0 && m.m32 == 0.0 && m.m33 == 0.0 && m.m34 == 0.0 &&
		m.m41 == 0.0 && m.m42 == 0.0 && m.m43 == 0.0 && m.m44 == 0.0;
}

// TransformCollider.set_mat, TransformCollider.hx:18-22. A singular matrix inverts to zero in
// Heaps and every query then runs against a collapsed ray; here it is Singular.
export function transformFrame(mat: Mat4): Result<TransformFrame, TransformError> {
	if (!finiteMatrix(mat)) { return Result.err(TransformError.NonFinite); }
	const inv: Mat4 = inverse(mat);
	if (isZero(inv)) { return Result.err(TransformError.Singular); }
	return Result.ok({ mat: mat, invMat: inv });
}

// Matrix.isIdentityEpsilon, Matrix.hx:82-94, which `TransformCollider.make` uses to return the
// bare collider for an identity placement.
export function isIdentityEpsilon(m: Mat4, epsilon: float32): boolean {
	return Math.abs(m.m41) <= epsilon && Math.abs(m.m42) <= epsilon && Math.abs(m.m43) <= epsilon &&
		Math.abs(m.m11 - 1.0) <= epsilon && Math.abs(m.m22 - 1.0) <= epsilon &&
		Math.abs(m.m33 - 1.0) <= epsilon && Math.abs(m.m12) <= epsilon &&
		Math.abs(m.m13) <= epsilon && Math.abs(m.m14) <= epsilon && Math.abs(m.m21) <= epsilon &&
		Math.abs(m.m23) <= epsilon && Math.abs(m.m24) <= epsilon && Math.abs(m.m31) <= epsilon &&
		Math.abs(m.m32) <= epsilon && Math.abs(m.m34) <= epsilon &&
		Math.abs(m.m44 - 1.0) <= epsilon;
}

// TransformCollider.transform, TransformCollider.hx:24-28.
export function composed(this frame: TransformFrame, m: Mat4): Result<TransformFrame, TransformError> {
	if (!finiteMatrix(m)) { return Result.err(TransformError.NonFinite); }
	return transformFrame(multiplyAffine(m, frame.mat));
}

// The ray in the collider's space, TransformCollider.hx:30-33.
export function localRay(this frame: TransformFrame, ray: Ray): Ray {
	return ray.transformed(frame.invMat);
}

// TransformCollider.hx:34-46: the local hit distance back to the world, measured from the world ray's origin to
// the hit point carried through the matrix, so a scale in the matrix scales the distance.
// A negative `hit` is a miss and passes through.
export function worldHitDistance(
	this frame: TransformFrame, local: Ray, hit: float32, world: Ray,
): Result<float32, TransformError> {
	if (hit < 0.0) { return Result.ok(hit); }
	const point: Vec3 = local.pointAt(hit) * frame.mat;
	const dx: float64 = (point.x as float64) - (world.origin.x as float64);
	const dy: float64 = (point.y as float64) - (world.origin.y as float64);
	const dz: float64 = (point.z as float64) - (world.origin.z as float64);
	const distance: float64 = Math.sqrt(dx * dx + dy * dy + dz * dz);
	if (distance > FLOAT32_LIMIT) { return Result.err(TransformError.OutOfRange); }
	return Result.ok(distance as float32);
}

// TransformCollider.contains, hx:48-54: the point in the collider's space.
export function localPoint(this frame: TransformFrame, point: Vec3): Vec3 {
	return point * frame.invMat;
}

function axisScale(m: Mat4): Vec3 {
	return vec3(
		Math.sqrt(m.m11 * m.m11 + m.m12 * m.m12 + m.m13 * m.m13) as float32,
		Math.sqrt(m.m21 * m.m21 + m.m22 * m.m22 + m.m23 * m.m23) as float32,
		Math.sqrt(m.m31 * m.m31 + m.m32 * m.m32 + m.m33 * m.m33) as float32,
	);
}

function largest(v: Vec3): float32 {
	return Math.max(v.x, Math.max(v.y, v.z));
}

// TransformCollider.inSphere, hx:64-79: the world sphere carried into the collider's space, its
// radius grown by the largest axis scale of the inverse. Heaps takes that scale from
// Matrix.getScale, which negates all three for a mirrored matrix, so a mirrored placement gets a
// negative radius there; the scale used here is the axis length.
// PENDING3D: transform-collider-mirrored-scale-negative
export function localSphere(this frame: TransformFrame, sphere: Sphere3D): Result<Sphere3D, TransformError> {
	if (!finiteVec(sphere.center) || !Number.isFinite(sphere.radius)) {
		return Result.err(TransformError.NonFinite);
	}
	const radius: float64 = (sphere.radius as float64) * (largest(axisScale(frame.invMat)) as float64);
	if (Math.abs(radius) > FLOAT32_LIMIT) { return Result.err(TransformError.OutOfRange); }
	return Result.ok({ center: sphere.center * frame.invMat, radius: radius as float32 });
}

// Sphere.inFrustumMatrix, Sphere.hx:61-76, which `TransformCollider.inFrustum` reaches through
// a collider's bounding sphere: the collider's sphere placed in the world by `mat`, radius grown
// by the largest axis scale.
export function worldSphere(this frame: TransformFrame, sphere: Sphere3D): Result<Sphere3D, TransformError> {
	if (!finiteVec(sphere.center) || !Number.isFinite(sphere.radius)) {
		return Result.err(TransformError.NonFinite);
	}
	const radius: float64 = (sphere.radius as float64) * (largest(axisScale(frame.mat)) as float64);
	if (Math.abs(radius) > FLOAT32_LIMIT) { return Result.err(TransformError.OutOfRange); }
	return Result.ok({ center: sphere.center * frame.mat, radius: radius as float32 });
}

// TransformCollider.dimension, hx:81-85, with the axis lengths for the scale, so a mirrored
// placement does not negate it.
export function scaledDimension(this frame: TransformFrame, dimension: float32): Result<float32, TransformError> {
	if (!Number.isFinite(dimension)) { return Result.err(TransformError.NonFinite); }
	const scaled: float64 = (dimension as float64) * (largest(axisScale(frame.mat)) as float64);
	if (Math.abs(scaled) > FLOAT32_LIMIT) { return Result.err(TransformError.OutOfRange); }
	return Result.ok(scaled as float32);
}
