import { Vec3, EPSILON } from "../math/math3d";
import { Camera3D, CameraBasis, ProjectionKind } from "./camera";

const STRAIGHT_ANGLE: float32 = 3.141592653589793;

export enum LightShapeError {
	NonFiniteInput,
	BadAxes,
	BadRange,
	BadDimensions,
	BadAngle,
	SingularAngle,
	UndefinedDirection,
	ParallelPlane,
	ParallelSegmentRay,
	ZeroRayOffset,
	NonFiniteCalculation,
}

export struct LightConeAngle {
	fullAngleRadians: float32;
	// Inner angle in radians, not a transition width: cos(min(fullAngle / 2, falloff)).
	falloffRadians: float32;
}

export struct SpotLightShape {
	position: Vec3;
	// Outgoing direction (Heaps Matrix.front()); supplied Void +Z means light-forward, not -Z.
	forward: Vec3;
	range: float32;
	cone: LightConeAngle;
}

export struct RectangleLightShape {
	position: Vec3;
	forward: Vec3;
	right: Vec3;
	up: Vec3;
	// World-scaled half-extents, unlike CapsuleLight's unscaled producer half-length.
	halfWidth: float32;
	halfHeight: float32;
	horizontal: LightConeAngle;
	vertical: LightConeAngle;
	range: float32;
}

export struct CapsuleLightShape {
	position: Vec3;
	// Heaps calls this normalized Matrix.front() axis left; it is not rectangle.right.
	axis: Vec3;
	halfLength: float32;
	radius: float32;
	range: float32;
}

export struct LightShapePoint {
	point: Vec3;
	delta: Vec3;
	direction: Vec3;
}

struct ConeCosines {
	outer: float32;
	inner: float32;
}

function finiteVector(value: Vec3): boolean {
	return Number.isFinite(value.x) && Number.isFinite(value.y) && Number.isFinite(value.z);
}

function unitAxis(value: Vec3): boolean {
	return finiteVector(value) && Math.abs(value.lengthSquared() - 1.0) <= 1e-4;
}

function validRange(range: float32): boolean {
	return Number.isFinite(range) && range > 0.0;
}

function saturate(value: float32): float32 {
	return Math.max(0.0, Math.min(1.0, value)) as float32;
}

function coneCosines(this cone: LightConeAngle): Result<ConeCosines, LightShapeError> {
	if (!Number.isFinite(cone.fullAngleRadians) || !Number.isFinite(cone.falloffRadians)) {
		return Result.err(LightShapeError.NonFiniteInput);
	}
	if (cone.fullAngleRadians <= 0.0 || cone.fullAngleRadians > STRAIGHT_ANGLE ||
		cone.falloffRadians < 0.0) {
		return Result.err(LightShapeError.BadAngle);
	}
	const halfAngle: float32 = cone.fullAngleRadians * 0.5;
	return Result.ok({
		outer: Math.cos(halfAngle) as float32,
		inner: Math.cos(Math.min(halfAngle, cone.falloffRadians)) as float32,
	});
}

function checkedDirection(delta: Vec3): Result<Vec3, LightShapeError> {
	const squared: float32 = delta.lengthSquared();
	if (!finiteVector(delta) || !Number.isFinite(squared)) {
		return Result.err(LightShapeError.NonFiniteCalculation);
	}
	if (squared < EPSILON) { return Result.err(LightShapeError.UndefinedDirection); }
	return Result.ok(delta.normalized());
}

function shapePoint(point: Vec3, position: Vec3): Result<LightShapePoint, LightShapeError> {
	const delta: Vec3 = point - position;
	const direction: Vec3 = try checkedDirection(delta);
	return Result.ok({ point: point, delta: delta, direction: direction });
}

function validateSpot(this light: SpotLightShape): Result<ConeCosines, LightShapeError> {
	if (!finiteVector(light.position)) { return Result.err(LightShapeError.NonFiniteInput); }
	if (!unitAxis(light.forward)) { return Result.err(LightShapeError.BadAxes); }
	if (!validRange(light.range)) { return Result.err(LightShapeError.BadRange); }
	const angles: ConeCosines = try light.cone.coneCosines();
	if (light.cone.fullAngleRadians >= STRAIGHT_ANGLE) {
		return Result.err(LightShapeError.BadAngle);
	}
	if (angles.inner <= angles.outer) { return Result.err(LightShapeError.SingularAngle); }
	return Result.ok(angles);
}

export function angularWeight(
	this light: SpotLightShape,
	position: Vec3,
): Result<float32, LightShapeError> {
	const angles: ConeCosines = try light.validateSpot();
	if (!finiteVector(position)) { return Result.err(LightShapeError.NonFiniteInput); }
	const towardLight: Vec3 = try checkedDirection(light.position - position);
	const theta: float32 = towardLight.dot(light.forward.scaled(-1.0));
	return Result.ok(saturate((theta - angles.outer) / (angles.inner - angles.outer)));
}

// Heaps SpotShadowMap: FOV=full angle, near=range/20, far=range, square aspect=1.
// Resolve this Camera3D with square dimensions. Basis.forward is outgoing, not fromWorld's -Z.
export function perspectiveCamera(
	this light: SpotLightShape,
	up: Vec3,
): Result<Camera3D, LightShapeError> {
	const _angles: ConeCosines = try light.validateSpot();
	if (!unitAxis(up) || Math.abs(up.dot(light.forward)) > 1e-4) {
		return Result.err(LightShapeError.BadAxes);
	}
	const nearPlane: float32 = light.range * 0.05;
	if (nearPlane <= 0.0) { return Result.err(LightShapeError.BadRange); }
	const right: Vec3 = light.forward.cross(up).normalized();
	const basis: CameraBasis = {
		right: right,
		up: right.cross(light.forward),
		forward: light.forward,
	};
	return Result.ok({
		position: light.position,
		yaw: 0.0,
		pitch: 0.0,
		orientation: basis,
		nearPlane: nearPlane,
		farPlane: light.range,
		projection: { kind: ProjectionKind.Perspective, fovY: light.cone.fullAngleRadians },
	});
}

function validateRectangle(this light: RectangleLightShape): Result<void, LightShapeError> {
	if (!finiteVector(light.position)) { return Result.err(LightShapeError.NonFiniteInput); }
	if (!unitAxis(light.forward) || !unitAxis(light.right) || !unitAxis(light.up) ||
		Math.abs(light.right.dot(light.up)) > 1e-4 ||
		Math.abs(light.forward.dot(light.right)) > 1e-4 ||
		Math.abs(light.forward.dot(light.up)) > 1e-4) {
		return Result.err(LightShapeError.BadAxes);
	}
	if (!validRange(light.range)) { return Result.err(LightShapeError.BadRange); }
	if (!Number.isFinite(light.halfWidth) || !Number.isFinite(light.halfHeight) ||
		light.halfWidth < 0.0 || light.halfHeight < 0.0) {
		return Result.err(LightShapeError.BadDimensions);
	}
	const _horizontal: ConeCosines = try light.horizontal.coneCosines();
	const _vertical: ConeCosines = try light.vertical.coneCosines();
	return Result.ok(null);
}

function closestRectanglePoint(
	this light: RectangleLightShape,
	position: Vec3,
	ray: Vec3,
): Result<LightShapePoint, LightShapeError> {
	const _valid = try light.validateRectangle();
	if (!finiteVector(position)) { return Result.err(LightShapeError.NonFiniteInput); }
	if (!unitAxis(ray)) { return Result.err(LightShapeError.BadAxes); }
	const denominator: float32 = light.forward.dot(ray);
	if (denominator == 0.0) { return Result.err(LightShapeError.ParallelPlane); }
	const distance: float32 = light.forward.dot(light.position - position) / denominator;
	const offset: Vec3 = position + ray.scaled(distance) - light.position;
	if (!Number.isFinite(distance) || !finiteVector(offset)) {
		return Result.err(LightShapeError.NonFiniteCalculation);
	}
	const projectedRight: float32 = offset.dot(light.right);
	const projectedUp: float32 = offset.dot(light.up);
	if (!Number.isFinite(projectedRight) || !Number.isFinite(projectedUp)) {
		return Result.err(LightShapeError.NonFiniteCalculation);
	}
	const across: float32 = Math.max(-light.halfWidth,
		Math.min(light.halfWidth, projectedRight)) as float32;
	const above: float32 = Math.max(-light.halfHeight,
		Math.min(light.halfHeight, projectedUp)) as float32;
	const point: Vec3 = light.position + light.right.scaled(across) + light.up.scaled(above);
	return shapePoint(point, position);
}

export function diffusePoint(
	this light: RectangleLightShape,
	position: Vec3,
	surfaceNormal: Vec3,
): Result<LightShapePoint, LightShapeError> {
	return light.closestRectanglePoint(position, surfaceNormal);
}

export function specularPoint(
	this light: RectangleLightShape,
	position: Vec3,
	reflectedViewRay: Vec3,
): Result<LightShapePoint, LightShapeError> {
	return light.closestRectanglePoint(position, reflectedViewRay);
}

function projectedAngularWeight(
	delta: Vec3,
	forward: Vec3,
	excludedAxis: Vec3,
	angles: ConeCosines,
): Result<float32, LightShapeError> {
	const projectedDelta: Vec3 = delta - excludedAxis.scaled(delta.dot(excludedAxis));
	const inverseForward: Vec3 = forward.scaled(-1.0);
	const projectedForward: Vec3 = inverseForward -
		excludedAxis.scaled(inverseForward.dot(excludedAxis));
	const deltaDirection: Vec3 = try checkedDirection(projectedDelta);
	const lightDirection: Vec3 = try checkedDirection(projectedForward);
	const epsilon: float32 = angles.inner - angles.outer + 0.00001;
	return Result.ok(saturate((deltaDirection.dot(lightDirection) - angles.outer) / epsilon));
}

// towardLightDelta is the closest diffuse point minus the receiver, not the center delta.
export function angularWeight(
	this light: RectangleLightShape,
	towardLightDelta: Vec3,
): Result<float32, LightShapeError> {
	const _valid = try light.validateRectangle();
	if (!finiteVector(towardLightDelta)) { return Result.err(LightShapeError.NonFiniteInput); }
	const horizontalAngles: ConeCosines = try light.horizontal.coneCosines();
	const verticalAngles: ConeCosines = try light.vertical.coneCosines();
	const horizontal: float32 = try projectedAngularWeight(
		towardLightDelta, light.forward, light.up, horizontalAngles,
	);
	const vertical: float32 = try projectedAngularWeight(
		towardLightDelta, light.forward, light.right, verticalAngles,
	);
	return Result.ok(horizontal * vertical);
}

function validateCapsule(this light: CapsuleLightShape): Result<void, LightShapeError> {
	if (!finiteVector(light.position)) { return Result.err(LightShapeError.NonFiniteInput); }
	if (!unitAxis(light.axis)) { return Result.err(LightShapeError.BadAxes); }
	if (!validRange(light.range)) { return Result.err(LightShapeError.BadRange); }
	if (!Number.isFinite(light.halfLength) || !Number.isFinite(light.radius) ||
		light.halfLength <= 0.0 || light.radius < 0.0) {
		return Result.err(LightShapeError.BadDimensions);
	}
	return Result.ok(null);
}

export function diffusePoint(
	this light: CapsuleLightShape,
	position: Vec3,
): Result<LightShapePoint, LightShapeError> {
	const _valid = try light.validateCapsule();
	if (!finiteVector(position)) { return Result.err(LightShapeError.NonFiniteInput); }
	const start: Vec3 = light.position - light.axis.scaled(light.halfLength);
	const end: Vec3 = light.position + light.axis.scaled(light.halfLength);
	const segment: Vec3 = end - start;
	const squared: float32 = segment.lengthSquared();
	if (!Number.isFinite(squared)) { return Result.err(LightShapeError.NonFiniteCalculation); }
	if (squared == 0.0) { return Result.err(LightShapeError.BadDimensions); }
	const t: float32 = (position - start).dot(segment) / squared;
	if (!Number.isFinite(t)) { return Result.err(LightShapeError.NonFiniteCalculation); }
	return shapePoint(start + segment.scaled(saturate(t)), position);
}

// reflectedViewRay = reflect(-normalize(cameraPosition - position), surfaceNormal).
export function specularDirection(
	this light: CapsuleLightShape,
	position: Vec3,
	reflectedViewRay: Vec3,
): Result<Vec3, LightShapeError> {
	const _valid = try light.validateCapsule();
	if (!finiteVector(position)) { return Result.err(LightShapeError.NonFiniteInput); }
	if (!unitAxis(reflectedViewRay)) { return Result.err(LightShapeError.BadAxes); }
	const start: Vec3 = light.position - light.axis.scaled(light.halfLength) - position;
	const end: Vec3 = light.position + light.axis.scaled(light.halfLength) - position;
	const segment: Vec3 = end - start;
	const squared: float32 = segment.lengthSquared();
	const alongRay: float32 = reflectedViewRay.dot(segment);
	const denominator: float32 = squared - alongRay * alongRay;
	if (!Number.isFinite(denominator) || !Number.isFinite(squared)) {
		return Result.err(LightShapeError.NonFiniteCalculation);
	}
	if (squared == 0.0) { return Result.err(LightShapeError.BadDimensions); }
	if (denominator <= 0.0) { return Result.err(LightShapeError.ParallelSegmentRay); }
	const t: float32 = start.dot(reflectedViewRay.scaled(alongRay) - segment) / denominator;
	if (!Number.isFinite(t)) { return Result.err(LightShapeError.NonFiniteCalculation); }
	const closest: Vec3 = start + segment.scaled(saturate(t));
	const centerToRay: Vec3 = reflectedViewRay.scaled(closest.dot(reflectedViewRay)) - closest;
	const offsetLength: float32 = centerToRay.length();
	if (!Number.isFinite(offsetLength)) {
		return Result.err(LightShapeError.NonFiniteCalculation);
	}
	if (offsetLength == 0.0) { return Result.err(LightShapeError.ZeroRayOffset); }
	const radius: float32 = Math.min(light.radius, light.range) as float32;
	const adjusted: Vec3 = closest + centerToRay.scaled(saturate(radius / offsetLength));
	return checkedDirection(adjusted);
}
