// The cascades' split and matrices, held to Bevy's calculate_cascade_bounds and
// calculate_cascade: arithmetic only, so none of it needs a GPU.

import { Vec3, vec3 } from "../math/math3d";
import { Camera3D, CameraView, ProjectionKind } from "../void3d/camera";
import { lightBasis } from "../void3d/dirShadowMap";
import {
	Cascade,
	CascadeConfig,
	CascadeError,
	MAX_CASCADES,
	cascadeBounds,
	cascadeOf,
	cascadesOf,
	sliceCorners,
} from "../void3d/cascades";
import { approx } from "./helpers";

const MAP_SIZE: int32 = 2048;
const TO_LIGHT: Vec3 = vec3(0.3, 1.0, 0.2);
const NO_CASTER: float32 = 1e20;

function camera(yaw: float32, position: Vec3): CameraView {
	const made: Camera3D = {
		position: position,
		yaw: yaw,
		pitch: 0.3,
		projection: { kind: ProjectionKind.Perspective, fovY: 0.8 },
		nearPlane: 0.1,
		farPlane: 500.0,
	};
	const view = made.resolve(1920, 1080);
	if (!view.ok) { unreachable; }
	return view.value;
}

function bevyConfig(): CascadeConfig {
	return { bounds: cascadeBounds(4, 10.0, 150.0), overlap: 0.2, minimumDistance: 0.1 };
}

function inside(cascade: Cascade, point: Vec3): boolean {
	const clip: Vec3 = point.project(cascade.clipFromWorld);
	const e: float32 = 1e-4;
	return clip.x >= -1.0 - e && clip.x <= 1.0 + e && clip.y >= -1.0 - e && clip.y <= 1.0 + e
		&& clip.z >= -e && clip.z <= 1.0 + e;
}

test "the far bounds grow by one ratio up to the maximum, and a lone cascade sits at it" {
	const bounds: Vec<float32> = cascadeBounds(4, 10.0, 150.0);
	assert bounds.length == 4;
	const ratio: float32 = Math.pow(15.0, 1.0 / 3.0) as float32;
	assert approx(bounds[0], 10.0) && approx(bounds[1], 10.0 * ratio);
	assert approx(bounds[2], 10.0 * ratio * ratio) && approx(bounds[3], 150.0);
	const one: Vec<float32> = cascadeBounds(1, 10.0, 150.0);
	assert one.length == 1 && one[0] == 150.0;
}

function refusal(config: CascadeConfig): CascadeError {
	const checked = config.validate();
	if (checked.ok) { unreachable; }
	return checked.error;
}

test "a config Bevy's builder refuses, or with more cascades than the shaders hold, is refused" {
	const good: CascadeConfig = bevyConfig();
	assert good.validate().ok && MAX_CASCADES == 4;
	assert refusal({ ...good, bounds: [] }) == CascadeError.Count;
	assert refusal({ ...good, bounds: [1.0, 2.0, 3.0, 4.0, 5.0] }) == CascadeError.Count;
	assert refusal({ ...good, bounds: [10.0, 10.0] }) == CascadeError.Bounds;
	assert refusal({ ...good, bounds: [0.05, 10.0] }) == CascadeError.Bounds;
	assert refusal({ ...good, overlap: 1.0 }) == CascadeError.Overlap;
	assert refusal({ ...good, overlap: -0.1 }) == CascadeError.Overlap;
	assert refusal({ ...good, minimumDistance: -1.0 }) == CascadeError.MinimumDistance;
	const view: CameraView = camera(0.5, vec3(0.0, 2.0, 0.0));
	const sized = cascadesOf(good, view.inverseViewProj, view.eye, lightBasis(TO_LIGHT), 0,
		NO_CASTER);
	assert !sized.ok && sized.error == CascadeError.MapSize;
}

test "a slice's corners sit at its two view depths, near plane first" {
	const view: CameraView = camera(0.5, vec3(3.0, 2.0, -4.0));
	const corners: Vec<Vec3> = sliceCorners(view.inverseViewProj, view.eye, 10.0, 24.0);
	assert corners.length == 8;
	for (let k = 0; k < 8; k++) {
		const depth: float32 = (corners[k] - view.eye).dot(view.basis.forward);
		assert approx(depth, k < 4 ? 10.0 : 24.0);
	}
	assert (corners[4] - corners[6]).length() > (corners[0] - corners[2]).length();
}

test "each cascade's map holds its slice, from its far bound back past the overlap" {
	const view: CameraView = camera(0.5, vec3(3.0, 2.0, -4.0));
	const config: CascadeConfig = bevyConfig();
	const made = cascadesOf(config, view.inverseViewProj, view.eye, lightBasis(TO_LIGHT),
		MAP_SIZE, NO_CASTER);
	assert made.ok;
	if (!made.ok) { return; }
	assert made.value.length == 4;
	let near: float32 = config.minimumDistance;
	for (let i = 0; i < 4; i++) {
		const cascade: Cascade = made.value[i];
		assert cascade.farBound == config.bounds[i];
		for (const corner of sliceCorners(view.inverseViewProj, view.eye, near, cascade.farBound)) {
			assert inside(cascade, corner);
		}
		near = 0.8 * cascade.farBound;
		if (i > 0) { assert cascade.texelSize > made.value[i - 1].texelSize; }
	}
}

test "turning the view keeps the texel size, and moving it moves the box a whole texel at a time" {
	const basis = lightBasis(TO_LIGHT);
	const a: CameraView = camera(0.5, vec3(0.0, 2.0, 0.0));
	const b: CameraView = camera(1.7, vec3(0.0, 2.0, 0.0));
	const corners = sliceCorners(a.inverseViewProj, a.eye, 10.0, 24.0);
	const first: Cascade = cascadeOf(corners, MAP_SIZE, basis, NO_CASTER, 24.0);
	const turned: Cascade = cascadeOf(sliceCorners(b.inverseViewProj, b.eye, 10.0, 24.0),
		MAP_SIZE, basis, NO_CASTER, 24.0);
	assert first.texelSize == turned.texelSize;
	assert first.texelSize * (MAP_SIZE as float32) == Math.ceil(first.texelSize * MAP_SIZE);
	for (const cascade of [first, turned]) {
		const origin: Vec3 = vec3(0.0, 0.0, 0.0).project(cascade.clipFromWorld);
		const stepsX: float32 = -origin.x * 0.5 * (MAP_SIZE as float32);
		const stepsY: float32 = -origin.y * 0.5 * (MAP_SIZE as float32);
		assert Math.abs(stepsX - Math.round(stepsX)) < 1e-3;
		assert Math.abs(stepsY - Math.round(stepsY)) < 1e-3;
	}
}

test "a caster nearer the light than the slice widens the map's depth back to it" {
	const basis = lightBasis(TO_LIGHT);
	const view: CameraView = camera(0.5, vec3(0.0, 2.0, 0.0));
	const corners = sliceCorners(view.inverseViewProj, view.eye, 10.0, 24.0);
	const open: Cascade = cascadeOf(corners, MAP_SIZE, basis, NO_CASTER, 24.0);
	let nearest: float32 = NO_CASTER;
	for (const corner of corners) {
		const depth: float32 = corner.dot(basis.forward);
		if (depth < nearest) { nearest = depth; }
	}
	const caster: float32 = nearest - 40.0;
	const reached: Cascade = cascadeOf(corners, MAP_SIZE, basis, caster, 24.0);
	const above: Vec3 = (corners[0] + basis.forward.scaled(-30.0));
	assert !inside(open, above) && inside(reached, above);
	assert approx(basis.forward.scaled(caster).project(reached.clipFromWorld).z, 0.0);
}
