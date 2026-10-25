// The six light-space cameras of h3d.pass.PointShadowMap (CubeShadowMap.hx draw, Camera.hx
// setCubeMap) from the shadowing point's record in collectLights' span: fovY 90, square, near
// PointLight.zNear, far the range, one per face in sokol's order. The pass draws each face into
// one layer of the point's map (dirShadowMap.ms createPoint), and shader3d.ms pointShadowAt picks
// the face by the largest axis.
import {
	LIGHT_UNIFORM_LENGTH,
	LIGHT_RECORD_LENGTH,
	LIGHT_RECORD_COLOR,
	LIGHT_RECORD_SHAPE,
	LIGHT_KIND_POINT,
	SHADOW_POINT_FACES,
} from "./gpu3d";
import { Vec3, vec3 } from "../math/math3d";
import { Camera3D, CameraView, CameraError, ProjectionKind, resolve } from "./camera";

export enum PointShadowError {
	BadRange,
	BadCamera,
}

// h3d.scene.pbr.PointLight.zNear.
export const POINT_SHADOW_NEAR: float32 = 0.02;

const CASTS: int32 = LIGHT_RECORD_SHAPE + 6;

function recordAt(light: int32): int32 {
	return LIGHT_UNIFORM_LENGTH + light * LIGHT_RECORD_LENGTH;
}

function recordCount(lights: Readonly<Span<float32>>): int32 {
	return ((lights.length as int32) - LIGHT_UNIFORM_LENGTH) / LIGHT_RECORD_LENGTH;
}

function casts(lights: Readonly<Span<float32>>, light: int32): boolean {
	const at: int32 = recordAt(light);
	return lights[at + LIGHT_RECORD_SHAPE + 3] == LIGHT_KIND_POINT && lights[at + CASTS] > 0.5;
}

export function shadowedPointCount(lights: Readonly<Span<float32>>): int32 {
	let count: int32 = 0;
	for (let light = 0; light < recordCount(lights); light++) {
		if (casts(lights, light)) { count = count + 1; }
	}
	return count;
}

// The record of the first shadowing point, or -1.
export function firstShadowedPoint(lights: Readonly<Span<float32>>): int32 {
	for (let light = 0; light < recordCount(lights); light++) {
		if (casts(lights, light)) { return light; }
	}
	return -1;
}

export function pointPosition(lights: Readonly<Span<float32>>, light: int32): Vec3 {
	const at: int32 = recordAt(light);
	return vec3(lights[at], lights[at + 1], lights[at + 2]);
}

function faceForward(face: int32): Vec3 {
	return match (face) {
		0 => vec3(1.0, 0.0, 0.0),
		1 => vec3(-1.0, 0.0, 0.0),
		2 => vec3(0.0, 1.0, 0.0),
		3 => vec3(0.0, -1.0, 0.0),
		4 => vec3(0.0, 0.0, 1.0),
		_ => vec3(0.0, 0.0, -1.0),
	};
}

function faceUp(face: int32): Vec3 {
	return match (face) {
		2 => vec3(0.0, 0.0, -1.0),
		3 => vec3(0.0, 0.0, 1.0),
		_ => vec3(0.0, 1.0, 0.0),
	};
}

export function pointShadowViews(
	lights: Readonly<Span<float32>>,
	light: int32,
): Result<Vec<CameraView>, PointShadowError> {
	const range: float32 = lights[recordAt(light) + LIGHT_RECORD_COLOR + 3];
	if (!(range > POINT_SHADOW_NEAR) || !Number.isFinite(range)) {
		return Result.err(PointShadowError.BadRange);
	}
	const position: Vec3 = pointPosition(lights, light);
	let views: Vec<CameraView> = [];
	for (let face = 0; face < SHADOW_POINT_FACES; face++) {
		const forward: Vec3 = faceForward(face);
		const right: Vec3 = forward.cross(faceUp(face));
		const camera: Camera3D = {
			position: position,
			yaw: 0.0,
			pitch: 0.0,
			orientation: { right: right, up: right.cross(forward), forward: forward },
			nearPlane: POINT_SHADOW_NEAR,
			farPlane: range,
			projection: { kind: ProjectionKind.Perspective, fovY: (Math.PI * 0.5) as float32 },
		};
		const view: Result<CameraView, CameraError> = camera.resolve(1, 1);
		if (!view.ok) { return Result.err(PointShadowError.BadCamera); }
		views.push(view.value);
	}
	return Result.ok(views);
}
