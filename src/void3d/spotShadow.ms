// The light-space camera of h3d.pass.SpotShadowMap.updateCamera (SpotShadowMap.hx:127-137) from
// the shadowing spot's record in collectLights' span: the spot's position and forward, fovY its
// full angle, near range / 20 (the first 5% outside of range, as Heaps writes it), far range,
// square. The pass itself is dirShadowMap.ms drawShadows, into the spot's own map (createSpot).
import {
	LIGHT_UNIFORM_LENGTH,
	LIGHT_RECORD_LENGTH,
	LIGHT_RECORD_COLOR,
	LIGHT_RECORD_SHAPE,
	LIGHT_KIND_SPOT,
} from "./gpu3d";
import { Vec3, vec3 } from "../math/math3d";
import { SpotLightShape, LightShapeError, perspectiveCamera } from "./lightShape";
import { Camera3D, CameraView, CameraError, resolve } from "./camera";

export enum SpotShadowError {
	BadSpot,
	BadCamera,
}

const CONE: int32 = LIGHT_RECORD_SHAPE + 4;
const CASTS: int32 = 2;
const FULL_ANGLE: int32 = 3;

function recordAt(light: int32): int32 {
	return LIGHT_UNIFORM_LENGTH + light * LIGHT_RECORD_LENGTH;
}

export function recordCount(lights: Readonly<Span<float32>>): int32 {
	return ((lights.length as int32) - LIGHT_UNIFORM_LENGTH) / LIGHT_RECORD_LENGTH;
}

function casts(lights: Readonly<Span<float32>>, light: int32): boolean {
	const at: int32 = recordAt(light);
	return lights[at + LIGHT_RECORD_SHAPE + 3] == LIGHT_KIND_SPOT &&
		lights[at + CONE + CASTS] > 0.5;
}

export function shadowedSpotCount(lights: Readonly<Span<float32>>): int32 {
	let count: int32 = 0;
	for (let light = 0; light < recordCount(lights); light++) {
		if (casts(lights, light)) { count = count + 1; }
	}
	return count;
}

// The record of the first shadowing spot, or -1.
export function firstShadowedSpot(lights: Readonly<Span<float32>>): int32 {
	for (let light = 0; light < recordCount(lights); light++) {
		if (casts(lights, light)) { return light; }
	}
	return -1;
}

// The reference axis and the right and up it gives are lightBasis's (dirShadowMap.ms), so the
// map's roll is the sun's: the square frustum holds the whole cone at any roll.
export function spotShadowView(
	lights: Readonly<Span<float32>>,
	light: int32,
): Result<CameraView, SpotShadowError> {
	const at: int32 = recordAt(light);
	const forward: Vec3 = vec3(
		lights[at + LIGHT_RECORD_SHAPE],
		lights[at + LIGHT_RECORD_SHAPE + 1],
		lights[at + LIGHT_RECORD_SHAPE + 2],
	);
	const reference: Vec3 = forward.y > 0.99 || forward.y < -0.99 ?
		vec3(0.0, 0.0, -1.0) : vec3(0.0, 1.0, 0.0);
	const right: Vec3 = forward.cross(reference).normalized();
	const spot: SpotLightShape = {
		position: vec3(lights[at], lights[at + 1], lights[at + 2]),
		forward: forward,
		range: lights[at + LIGHT_RECORD_COLOR + 3],
		cone: { fullAngleRadians: lights[at + CONE + FULL_ANGLE], falloffRadians: 0.0 },
	};
	const camera: Result<Camera3D, LightShapeError> = spot.perspectiveCamera(right.cross(forward));
	if (!camera.ok) { return Result.err(SpotShadowError.BadSpot); }
	const view: Result<CameraView, CameraError> = camera.value.resolve(1, 1);
	if (!view.ok) { return Result.err(SpotShadowError.BadCamera); }
	return Result.ok(view.value);
}
