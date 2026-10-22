// The light-space camera of h3d.pass.SpotShadowMap.updateCamera (SpotShadowMap.hx:127-137) from
// the light block's shadowing spot slot: the spot's position and forward, fovY its full angle,
// near range / 20 (the first 5% outside of range, as Heaps writes it), far range, square. The
// pass itself is dirShadowMap.ms drawShadows, into the spot's own map (createSpot).
import { MAX_POINT_LIGHTS, LIGHT_SHAPE_BASE, LIGHT_SHAPE_ARRAY_LENGTH, LIGHT_KIND_SPOT } from "./gpu3d";
import { Vec3, vec3 } from "../math/math3d";
import { SpotLightShape, LightShapeError, perspectiveCamera } from "./lightShape";
import { Camera3D, CameraView, CameraError, resolve } from "./camera";

export enum SpotShadowError {
	BadSpot,
	BadCamera,
}

const POSITION_BASE: int32 = 12;
const RANGE_BASE: int32 = POSITION_BASE + MAX_POINT_LIGHTS * 4;
const CONE_BASE: int32 = LIGHT_SHAPE_BASE + LIGHT_SHAPE_ARRAY_LENGTH;
const CASTS: int32 = 2;
const FULL_ANGLE: int32 = 3;

function casts(lights: Readonly<Span<float32>>, slot: int32): boolean {
	return lights[LIGHT_SHAPE_BASE + slot * 4 + 3] == LIGHT_KIND_SPOT &&
		lights[CONE_BASE + slot * 4 + CASTS] > 0.5;
}

export function shadowedSpotCount(lights: Readonly<Span<float32>>): int32 {
	let count: int32 = 0;
	for (let slot = 0; slot < MAX_POINT_LIGHTS; slot++) {
		if (casts(lights, slot)) { count = count + 1; }
	}
	return count;
}

// The slot of the first shadowing spot, or -1.
export function firstShadowedSpot(lights: Readonly<Span<float32>>): int32 {
	for (let slot = 0; slot < MAX_POINT_LIGHTS; slot++) {
		if (casts(lights, slot)) { return slot; }
	}
	return -1;
}

// The reference axis and the right and up it gives are lightBasis's (dirShadowMap.ms), so the
// map's roll is the sun's: the square frustum holds the whole cone at any roll.
export function spotShadowView(
	lights: Readonly<Span<float32>>,
	slot: int32,
): Result<CameraView, SpotShadowError> {
	const forward: Vec3 = vec3(
		lights[LIGHT_SHAPE_BASE + slot * 4],
		lights[LIGHT_SHAPE_BASE + slot * 4 + 1],
		lights[LIGHT_SHAPE_BASE + slot * 4 + 2],
	);
	const reference: Vec3 = forward.y > 0.99 || forward.y < -0.99 ?
		vec3(0.0, 0.0, -1.0) : vec3(0.0, 1.0, 0.0);
	const right: Vec3 = forward.cross(reference).normalized();
	const spot: SpotLightShape = {
		position: vec3(
			lights[POSITION_BASE + slot * 4],
			lights[POSITION_BASE + slot * 4 + 1],
			lights[POSITION_BASE + slot * 4 + 2],
		),
		forward: forward,
		range: lights[RANGE_BASE + slot * 4 + 3],
		cone: { fullAngleRadians: lights[CONE_BASE + slot * 4 + FULL_ANGLE], falloffRadians: 0.0 },
	};
	const camera: Result<Camera3D, LightShapeError> = spot.perspectiveCamera(right.cross(forward));
	if (!camera.ok) { return Result.err(SpotShadowError.BadSpot); }
	const view: Result<CameraView, CameraError> = camera.value.resolve(1, 1);
	if (!view.ok) { return Result.err(SpotShadowError.BadCamera); }
	return Result.ok(view.value);
}
