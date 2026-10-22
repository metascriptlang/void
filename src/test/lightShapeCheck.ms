import {
	Vec3,
	Vec4,
	Mat4,
	vec3,
	vec4,
	rotationY,
	scaling,
	translation,
} from "../math/math3d";
import { CameraBasis, ProjectionKind } from "../void3d/camera";
import {
	SpotLightShape,
	RectangleLightShape,
	CapsuleLightShape,
	LightShapeError,
} from "../void3d/lightShape";

function closeFloat(a: float32, b: float32): boolean {
	return Math.abs(a - b) < 0.00002;
}

function closeVector(a: Vec3, b: Vec3): boolean {
	return closeFloat(a.x, b.x) && closeFloat(a.y, b.y) && closeFloat(a.z, b.z);
}

function spotX(): SpotLightShape {
	const world: Mat4 = scaling(2.0, 3.0, 4.0)
		.multiplyAffine(rotationY(1.5707963268))
		.multiplyAffine(translation(3.0, -2.0, 5.0));
	return {
		position: vec3(0.0, 0.0, 0.0) * world,
		forward: vec3(0.0, 0.0, 1.0).transformDirection(world).normalized(),
		range: 20.0,
		cone: { fullAngleRadians: 1.5707963268, falloffRadians: 0.0 },
	};
}

function spotNegativeZ(): SpotLightShape {
	return {
		position: vec3(-4.0, 3.0, 2.0),
		forward: vec3(0.0, 0.0, -1.0),
		range: 40.0,
		cone: { fullAngleRadians: 1.0471975512, falloffRadians: 0.2617993878 },
	};
}

function rectangleZ(): RectangleLightShape {
	return {
		position: vec3(10.0, 2.0, -3.0),
		forward: vec3(0.0, 0.0, 1.0),
		right: vec3(1.0, 0.0, 0.0),
		up: vec3(0.0, 1.0, 0.0),
		halfWidth: 2.0,
		halfHeight: 0.5,
		horizontal: { fullAngleRadians: 1.5707963268, falloffRadians: 0.0 },
		vertical: { fullAngleRadians: 1.0471975512, falloffRadians: 0.0 },
		range: 8.0,
	};
}

function rectangleX(): RectangleLightShape {
	return {
		position: vec3(-1.0, 5.0, 2.0),
		forward: vec3(1.0, 0.0, 0.0),
		right: vec3(0.0, 0.0, -1.0),
		up: vec3(0.0, 1.0, 0.0),
		halfWidth: 0.75,
		halfHeight: 3.0,
		horizontal: { fullAngleRadians: 2.0943951024, falloffRadians: 0.0 },
		vertical: { fullAngleRadians: 1.5707963268, falloffRadians: 0.0 },
		range: 12.0,
	};
}

function capsuleX(): CapsuleLightShape {
	return {
		position: vec3(2.0, -1.0, 3.0),
		axis: vec3(1.0, 0.0, 0.0),
		halfLength: 2.0,
		radius: 0.1,
		range: 4.0,
	};
}

function capsuleZ(): CapsuleLightShape {
	return {
		position: vec3(-2.0, 4.0, -1.0),
		axis: vec3(0.0, 0.0, 1.0),
		halfLength: 1.5,
		radius: 0.25,
		range: 6.0,
	};
}

test "lightShape spot translated +X angle uses outgoing forward and cosine half angle" {
	const light: SpotLightShape = spotX();
	const center = light.angularWeight(vec3(8.0, -2.0, 5.0));
	const edge = light.angularWeight(vec3(8.0, -2.0, 10.0));
	const outside = light.angularWeight(vec3(8.0, -2.0, 11.0));
	const behind = light.angularWeight(vec3(-2.0, -2.0, 5.0));
	const middle = light.angularWeight(vec3(11.5, -2.0, 10.2678268764));
	assert center.ok && edge.ok && outside.ok && behind.ok && middle.ok;
	if (center.ok) { assert closeFloat(center.value, 1.0); }
	if (edge.ok) { assert closeFloat(edge.value, 0.0); }
	if (outside.ok) { assert outside.value == 0.0; }
	if (behind.ok) { assert behind.value == 0.0; }
	if (middle.ok) { assert closeFloat(middle.value, 0.4878679656); }
}

test "lightShape rotated -Z spot inner falloff is radians not full cone angle" {
	const light: SpotLightShape = spotNegativeZ();
	const middle = light.angularWeight(vec3(0.3588989435, 3.0, -7.0));
	const inner = light.angularWeight(vec3(-4.0, 3.0, -8.0));
	assert middle.ok && inner.ok;
	if (middle.ok) { assert closeFloat(middle.value, 0.3400846099); }
	if (inner.ok) { assert inner.value == 1.0; }
}

test "lightShape +X spot square perspective has forward +X and projective W" {
	const light: SpotLightShape = spotX();
	const camera = light.perspectiveCamera(vec3(0.0, 1.0, 0.0));
	assert camera.ok;
	if (camera.ok) {
		assert camera.value.nearPlane == 1.0 && camera.value.farPlane == 20.0;
		assert camera.value.projection.kind == ProjectionKind.Perspective;
		const basis: CameraBasis = camera.value.basisOf();
		assert closeVector(basis.forward, vec3(1.0, 0.0, 0.0));
		assert closeVector(basis.right, vec3(0.0, 0.0, 1.0));
		const view = camera.value.resolve(256, 256);
		assert view.ok;
		if (view.ok) {
			const clip: Vec4 = vec4(8.0, -1.0, 7.0, 1.0) * view.value.viewProj;
			assert closeFloat(clip.w, 5.0);
			assert closeFloat(clip.x / clip.w, 0.4);
			assert closeFloat(clip.y / clip.w, 0.2);
			assert closeFloat(clip.z / clip.w, 0.8421052632);
			assert closeFloat(vec3(4.0, -2.0, 5.0).project(view.value.viewProj).z, 0.0);
			assert closeFloat(vec3(23.0, -2.0, 5.0).project(view.value.viewProj).z, 1.0);
		}
	}
}

test "lightShape -Z spot second perspective range and FOV are independent" {
	const camera = spotNegativeZ().perspectiveCamera(vec3(0.0, 1.0, 0.0));
	assert camera.ok;
	if (camera.ok) {
		assert camera.value.nearPlane == 2.0 && camera.value.farPlane == 40.0;
		const view = camera.value.resolve(128, 128);
		assert view.ok;
		if (view.ok) {
			const clip: Vec4 = vec4(-1.0, 4.0, -8.0, 1.0) * view.value.viewProj;
			assert closeFloat(clip.w, 10.0);
			assert closeFloat(clip.x / clip.w, 0.5196152423);
			assert closeFloat(clip.y / clip.w, 0.1732050808);
			assert closeFloat(clip.z / clip.w, 0.8421052632);
		}
	}
}

test "lightShape non-square rectangle diffuse and specular choose different clamped points" {
	const light: RectangleLightShape = rectangleZ();
	const diffuse = light.diffusePoint(vec3(13.0, 4.0, 1.0), vec3(0.0, 0.0, -1.0));
	const specular = light.specularPoint(
		vec3(13.0, 4.0, 1.0), vec3(-0.4472135955, 0.0, -0.8944271910),
	);
	assert diffuse.ok && specular.ok;
	if (diffuse.ok) {
		assert closeVector(diffuse.value.point, vec3(12.0, 2.5, -3.0));
		assert closeVector(diffuse.value.direction,
			vec3(-0.2279211529, -0.3418817294, -0.9116846117));
		const angle = light.angularWeight(diffuse.value.delta);
		assert angle.ok;
		if (angle.ok) { assert closeFloat(angle.value, 0.4712098381); }
	}
	if (specular.ok) {
		assert closeVector(specular.value.point, vec3(11.0, 2.5, -3.0));
		assert closeVector(specular.value.direction,
			vec3(-0.4239991520, -0.3179993640, -0.8479983040));
	}
}

test "lightShape rotated rectangle keeps world-scaled width separate from height" {
	const light: RectangleLightShape = rectangleX();
	const diffuse = light.diffusePoint(vec3(3.0, 9.0, 4.0), vec3(-1.0, 0.0, 0.0));
	const specular = light.specularPoint(
		vec3(3.0, 9.0, 4.0), vec3(-0.8164965809, -0.4082482905, -0.4082482905),
	);
	assert diffuse.ok && specular.ok;
	if (diffuse.ok) {
		assert closeVector(diffuse.value.point, vec3(-1.0, 8.0, 2.75));
		assert closeVector(diffuse.value.direction,
			vec3(-0.9284141651, -0.2321035413, -0.2901294266));
		const angle = light.angularWeight(diffuse.value.delta);
		assert angle.ok;
		if (angle.ok) { assert closeFloat(angle.value, 0.8162564919); }
	}
	if (specular.ok) { assert closeVector(specular.value.point, vec3(-1.0, 7.0, 2.0)); }
}

test "lightShape finite capsule interior diffuse and radius-adjusted specular are not center" {
	const light: CapsuleLightShape = capsuleX();
	const diffuse = light.diffusePoint(vec3(3.0, 2.0, 4.0));
	const specular = light.specularDirection(
		vec3(3.0, 2.0, 4.0), vec3(-0.4082482905, -0.8164965809, -0.4082482905),
	);
	assert diffuse.ok && specular.ok;
	if (diffuse.ok) {
		assert closeVector(diffuse.value.point, vec3(3.0, -1.0, 3.0));
		assert closeVector(diffuse.value.direction, vec3(0.0, -0.9486832981, -0.3162277660));
	}
	if (specular.ok) {
		assert closeVector(specular.value, vec3(-0.4061716708, -0.8573931878, -0.3160719781));
	}
}

test "lightShape rotated finite capsule clamps endpoint not infinite axis" {
	const light: CapsuleLightShape = capsuleZ();
	const diffuse = light.diffusePoint(vec3(2.0, 5.0, 3.0));
	const specular = light.specularDirection(
		vec3(2.0, 5.0, 3.0), vec3(-0.8164965809, -0.4082482905, -0.4082482905),
	);
	assert diffuse.ok && specular.ok;
	if (diffuse.ok) {
		assert closeVector(diffuse.value.point, vec3(-2.0, 4.0, 0.5));
		assert closeVector(diffuse.value.direction,
			vec3(-0.8295613558, -0.2073903389, -0.5184758474));
	}
	if (specular.ok) {
		assert closeVector(specular.value, vec3(-0.8304458155, -0.2532939295, -0.4961873969));
	}
}

test "lightShape capsule radius clamps to range while zero radius stays finite off ray" {
	let light: CapsuleLightShape = capsuleX();
	light.radius = 9.0;
	light.range = 0.1;
	const clamped = light.specularDirection(
		vec3(3.0, 2.0, 4.0), vec3(-0.4082482905, -0.8164965809, -0.4082482905),
	);
	assert clamped.ok;
	if (clamped.ok) {
		assert closeVector(clamped.value, vec3(-0.4061716708, -0.8573931878, -0.3160719781));
	}
	light.radius = 0.0;
	const zero = light.specularDirection(
		vec3(3.0, 2.0, 4.0), vec3(-0.4082482905, -0.8164965809, -0.4082482905),
	);
	assert zero.ok;
	if (zero.ok) {
		assert closeVector(zero.value, vec3(-0.4048204524, -0.8674723980, -0.2891574660));
	}
}

test "lightShape singular queries refuse without repaired axes or guessed limits" {
	let spot: SpotLightShape = spotX();
	const coincident = spot.angularWeight(spot.position);
	assert !coincident.ok;
	if (!coincident.ok) { assert coincident.error == LightShapeError.UndefinedDirection; }
	spot.cone.falloffRadians = 0.7853981634;
	const hard = spot.angularWeight(vec3(8.0, -2.0, 5.0));
	assert !hard.ok;
	if (!hard.ok) { assert hard.error == LightShapeError.SingularAngle; }
	const badUp = spotX().perspectiveCamera(vec3(1.0, 0.0, 0.0));
	assert !badUp.ok;
	if (!badUp.ok) { assert badUp.error == LightShapeError.BadAxes; }
	const parallelPlane = rectangleZ().diffusePoint(vec3(13.0, 4.0, 1.0), vec3(1.0, 0.0, 0.0));
	assert !parallelPlane.ok;
	if (!parallelPlane.ok) { assert parallelPlane.error == LightShapeError.ParallelPlane; }
	let capsule: CapsuleLightShape = capsuleX();
	const parallelSegment = capsule.specularDirection(vec3(3.0, 2.0, 4.0), vec3(1.0, 0.0, 0.0));
	assert !parallelSegment.ok;
	if (!parallelSegment.ok) { assert parallelSegment.error == LightShapeError.ParallelSegmentRay; }
	const onRay = capsule.specularDirection(vec3(2.0, 2.0, 3.0), vec3(0.0, -1.0, 0.0));
	assert !onRay.ok;
	if (!onRay.ok) { assert onRay.error == LightShapeError.ZeroRayOffset; }
	capsule.halfLength = 0.0;
	const noSegment = capsule.diffusePoint(vec3(3.0, 2.0, 4.0));
	assert !noSegment.ok;
	if (!noSegment.ok) { assert noSegment.error == LightShapeError.BadDimensions; }
}

test "lightShape finite declarations reject non-unit sheared and invalid dimensional inputs" {
	let spot: SpotLightShape = spotX();
	spot.forward = vec3(2.0, 0.0, 0.0);
	assert !spot.angularWeight(vec3(8.0, -2.0, 5.0)).ok;
	spot = spotX();
	spot.range = 0.0;
	assert !spot.perspectiveCamera(vec3(0.0, 1.0, 0.0)).ok;
	spot = spotX();
	spot.position.x = NaN as float32;
	assert !spot.angularWeight(vec3(8.0, -2.0, 5.0)).ok;
	spot = spotX();
	spot.cone.fullAngleRadians = 3.1415926536;
	assert !spot.angularWeight(vec3(8.0, -2.0, 5.0)).ok;
	let rectangle: RectangleLightShape = rectangleZ();
	rectangle.up = vec3(0.6, 0.8, 0.0);
	assert !rectangle.diffusePoint(vec3(13.0, 4.0, 1.0), vec3(0.0, 0.0, -1.0)).ok;
	rectangle = rectangleZ();
	rectangle.halfWidth = -1.0;
	assert !rectangle.specularPoint(vec3(13.0, 4.0, 1.0), vec3(0.0, 0.0, -1.0)).ok;
	let capsule: CapsuleLightShape = capsuleZ();
	capsule.radius = -0.1;
	assert !capsule.diffusePoint(vec3(2.0, 5.0, 3.0)).ok;
	capsule = capsuleZ();
	capsule.range = NaN as float32;
	assert !capsule.diffusePoint(vec3(2.0, 5.0, 3.0)).ok;
}

test "lightShape finite capsule specular keeps shader line projection and saturates radius" {
	let light: CapsuleLightShape = capsuleX();
	light.radius = 0.5;
	const reversedRay = light.specularDirection(
		vec3(3.0, 2.0, 4.0), vec3(0.4082482905, 0.8164965809, 0.4082482905),
	);
	assert reversedRay.ok;
	if (reversedRay.ok) {
		assert closeVector(reversedRay.value, vec3(-0.4082482905, -0.8164965809, -0.4082482905));
	}
}

test "lightShape rectangle plane trace is signed and equal angle keeps reference epsilon" {
	let light: RectangleLightShape = rectangleZ();
	light.horizontal.falloffRadians = 2.0;
	light.vertical.falloffRadians = 2.0;
	const awayNormal = light.diffusePoint(vec3(13.0, 4.0, 1.0), vec3(0.0, 0.0, 1.0));
	assert awayNormal.ok;
	if (awayNormal.ok) {
		assert closeVector(awayNormal.value.point, vec3(12.0, 2.5, -3.0));
		const angle = light.angularWeight(awayNormal.value.delta);
		assert angle.ok;
		if (angle.ok) { assert angle.value == 1.0; }
	}
}

test "lightShape undefined output and projected directions refuse on valid emitter dimensions" {
	const rectangle: RectangleLightShape = rectangleZ();
	const inPlane = rectangle.specularPoint(vec3(11.0, 2.0, -3.0), vec3(0.0, 0.0, 1.0));
	assert !inPlane.ok;
	if (!inPlane.ok) { assert inPlane.error == LightShapeError.UndefinedDirection; }
	const projectedZero = rectangle.angularWeight(vec3(0.0, 1.0, 0.0));
	assert !projectedZero.ok;
	if (!projectedZero.ok) { assert projectedZero.error == LightShapeError.UndefinedDirection; }
	const capsule: CapsuleLightShape = capsuleX();
	const onSegment = capsule.diffusePoint(vec3(3.0, -1.0, 3.0));
	assert !onSegment.ok;
	if (!onSegment.ok) { assert onSegment.error == LightShapeError.UndefinedDirection; }
	let zeroRadius: CapsuleLightShape = capsule;
	zeroRadius.radius = 0.0;
	const onRay = zeroRadius.specularDirection(vec3(2.0, 2.0, 3.0), vec3(0.0, -1.0, 0.0));
	assert !onRay.ok;
	if (!onRay.ok) { assert onRay.error == LightShapeError.ZeroRayOffset; }
}

test "lightShape named finite angle range axis and arithmetic errors are observable" {
	let spot: SpotLightShape = spotX();
	const nonfinite = spot.angularWeight(vec3(NaN as float32, 0.0, 0.0));
	assert !nonfinite.ok;
	if (!nonfinite.ok) { assert nonfinite.error == LightShapeError.NonFiniteInput; }
	spot.cone.falloffRadians = -0.1;
	const badAngle = spot.angularWeight(vec3(8.0, -2.0, 5.0));
	assert !badAngle.ok;
	if (!badAngle.ok) { assert badAngle.error == LightShapeError.BadAngle; }
	spot = spotX();
	spot.range = 0.0;
	const badRange = spot.angularWeight(vec3(8.0, -2.0, 5.0));
	assert !badRange.ok;
	if (!badRange.ok) { assert badRange.error == LightShapeError.BadRange; }
	spot = spotX();
	spot.forward = vec3(2.0, 0.0, 0.0);
	const badAxis = spot.angularWeight(vec3(8.0, -2.0, 5.0));
	assert !badAxis.ok;
	if (!badAxis.ok) { assert badAxis.error == LightShapeError.BadAxes; }
	spot = spotX();
	const overflow = spot.angularWeight(vec3(3e38, 3e38, 3e38));
	assert !overflow.ok;
	if (!overflow.ok) { assert overflow.error == LightShapeError.NonFiniteCalculation; }
}

test "lightShape default outgoing +Z is not generic camera node back +Z" {
	let light: SpotLightShape = spotX();
	light.position = vec3(2.0, 1.0, -3.0);
	light.forward = vec3(0.0, 0.0, 1.0);
	const center = light.angularWeight(vec3(2.0, 1.0, 2.0));
	assert center.ok;
	if (center.ok) { assert center.value == 1.0; }
	const camera = light.perspectiveCamera(vec3(0.0, 1.0, 0.0));
	assert camera.ok;
	if (camera.ok) {
		const basis: CameraBasis = camera.value.basisOf();
		assert closeVector(basis.right, vec3(-1.0, 0.0, 0.0));
		assert closeVector(basis.forward, vec3(0.0, 0.0, 1.0));
		const view = camera.value.resolve(64, 64);
		assert view.ok;
		if (view.ok) {
			const clip: Vec4 = vec4(1.0, 1.0, 2.0, 1.0) * view.value.viewProj;
			assert closeFloat(clip.w, 5.0);
			assert closeFloat(clip.x / clip.w, 0.2);
		}
	}
}


test "lightShape zero-width rectangle retains finite height clamp" {
	let light: RectangleLightShape = rectangleZ();
	light.halfWidth = 0.0;
	const point = light.diffusePoint(vec3(13.0, 4.0, 1.0), vec3(0.0, 0.0, -1.0));
	assert point.ok;
	if (point.ok) { assert closeVector(point.value.point, vec3(10.0, 2.5, -3.0)); }
}

test "lightShape zero-height rectangle retains finite width clamp" {
	let light: RectangleLightShape = rectangleZ();
	light.halfHeight = 0.0;
	const point = light.specularPoint(
		vec3(13.0, 4.0, 1.0), vec3(-0.4472135955, 0.0, -0.8944271910),
	);
	assert point.ok;
	if (point.ok) { assert closeVector(point.value.point, vec3(11.0, 2.0, -3.0)); }
}

test "lightShape reflected orthonormal rectangle basis does not change symmetric footprint" {
	let light: RectangleLightShape = rectangleZ();
	light.right = vec3(-1.0, 0.0, 0.0);
	const point = light.diffusePoint(vec3(13.0, 4.0, 1.0), vec3(0.0, 0.0, -1.0));
	assert point.ok;
	if (point.ok) { assert closeVector(point.value.point, vec3(12.0, 2.5, -3.0)); }
}

test "lightShape rectangle angle pi stays finite independently of spot perspective" {
	let rectangle: RectangleLightShape = rectangleZ();
	rectangle.horizontal.fullAngleRadians = 3.1415926536;
	rectangle.vertical.fullAngleRadians = 3.1415926536;
	const angle = rectangle.angularWeight(vec3(-1.0, -1.5, -4.0));
	assert angle.ok;
	if (angle.ok) { assert closeFloat(angle.value, 0.9083545621); }
	let spot: SpotLightShape = spotX();
	spot.cone.fullAngleRadians = 3.1415926536;
	const camera = spot.perspectiveCamera(vec3(0.0, 1.0, 0.0));
	assert !camera.ok;
	if (!camera.ok) { assert camera.error == LightShapeError.BadAngle; }
}
