// The six light-space cameras of h3d.pass.CubeShadowMap (CubeShadowMap.hx draw, Camera.hx
// setCubeMap) from the casting record in collectLights' span, a point, rectangle or capsule as
// PointShadowMap, RectangleShadowMap and CapsuleShadowMap all extend it: fovY 90, square, near the
// kind's, far the range, one per face in sokol's order, around the light's position. The pass
// draws each face into one layer of the cube map (dirShadowMap.ms createCube), and shader3d.ms
// cubeShadowAt picks the face by the largest axis.
import {
	LIGHT_UNIFORM_LENGTH,
	LIGHT_RECORD_LENGTH,
	LIGHT_RECORD_COLOR,
	LIGHT_KIND_SPOT,
	LIGHT_KIND_RECTANGLE,
	LIGHT_CUBE_CASTER,
	SHADOW_CUBE_FACES,
} from "./gpu3d";
import { NOT_A_RECORD, casterRecord, recordKind } from "./spotShadow";
import { Vec3, vec3 } from "../math/math3d";
import { Camera3D, CameraView, CameraError, ProjectionKind, resolve } from "./camera";

export enum CubeShadowError {
	BadRange,
	BadCamera,
	// The light block's header names a record that is not a point, rectangle or capsule.
	BadCaster,
}

// h3d.scene.pbr.PointLight.zNear and CapsuleLight.zNear.
export const POINT_SHADOW_NEAR: float32 = 0.02;
// RectangleShadowMap.updateLightCameraNearFar.
export const RECTANGLE_SHADOW_NEAR: float32 = 0.01;

function recordAt(light: int32): int32 {
	return LIGHT_UNIFORM_LENGTH + light * LIGHT_RECORD_LENGTH;
}

// The record that casts the cube map, or -1.
export function cubeCaster(lights: Readonly<Span<float32>>): Result<int32, CubeShadowError> {
	const light: int32 = casterRecord(lights, LIGHT_CUBE_CASTER);
	if (light == -1) { return Result.ok(-1); }
	if (light == NOT_A_RECORD || recordKind(lights, light) == LIGHT_KIND_SPOT) {
		return Result.err(CubeShadowError.BadCaster);
	}
	return Result.ok(light);
}

export function cubeNear(lights: Readonly<Span<float32>>, light: int32): float32 {
	return recordKind(lights, light) == LIGHT_KIND_RECTANGLE ?
		RECTANGLE_SHADOW_NEAR : POINT_SHADOW_NEAR;
}

export function cubeRange(lights: Readonly<Span<float32>>, light: int32): float32 {
	return lights[recordAt(light) + LIGHT_RECORD_COLOR + 3];
}

export function cubePosition(lights: Readonly<Span<float32>>, light: int32): Vec3 {
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

export function cubeShadowViews(
	lights: Readonly<Span<float32>>,
	light: int32,
): Result<Vec<CameraView>, CubeShadowError> {
	const range: float32 = cubeRange(lights, light);
	const near: float32 = cubeNear(lights, light);
	if (!(range > near) || !Number.isFinite(range)) {
		return Result.err(CubeShadowError.BadRange);
	}
	const position: Vec3 = cubePosition(lights, light);
	let views: Vec<CameraView> = [];
	for (let face = 0; face < SHADOW_CUBE_FACES; face++) {
		const forward: Vec3 = faceForward(face);
		const right: Vec3 = forward.cross(faceUp(face));
		const camera: Camera3D = {
			position: position,
			yaw: 0.0,
			pitch: 0.0,
			orientation: { right: right, up: right.cross(forward), forward: forward },
			nearPlane: near,
			farPlane: range,
			projection: { kind: ProjectionKind.Perspective, fovY: (Math.PI * 0.5) as float32 },
		};
		const view: Result<CameraView, CameraError> = camera.resolve(1, 1);
		if (!view.ok) { return Result.err(CubeShadowError.BadCamera); }
		views.push(view.value);
	}
	return Result.ok(views);
}
