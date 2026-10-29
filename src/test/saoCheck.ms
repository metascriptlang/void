// ScalableAoPass's CPU side: Heaps' SAO defaults, the uniform block ScalableAO.apply fills, and
// the noise texture, none of which needs a GPU.

import { approx } from "./helpers";
import { vec3, Vec3 } from "../math/math3d";
import { Camera3D, CameraView, CameraError, ProjectionKind } from "../void3d/camera";
import {
	SAO_EYE,
	SAO_FADE,
	SAO_INVERSE_VIEW_PROJ,
	SAO_NOISE,
	SAO_RADIUS,
	SAO_TAPS,
	SAO_UNIFORM_LENGTH,
	SAO_VIEW_DEPTH,
} from "../void3d/gpu3d";
import { saoFaded } from "../void3d/post3d";
import {
	ScalableAoSettings,
	SAO_NOISE_SIZE,
	saoNoisePixels,
	writeSaoBlock,
} from "../void3d/sao";

function perspective(): Camera3D {
	return {
		position: vec3(1.0, 2.0, 3.0),
		yaw: 0.5,
		pitch: -0.25,
		orientation: null,
		nearPlane: 1.0,
		farPlane: 11.0,
		projection: { kind: ProjectionKind.Perspective, fovY: 1.5707963267948966 },
	};
}

function resolvedView(camera: Camera3D): CameraView {
	let result: Result<CameraView, CameraError> = camera.resolve(320, 180);
	if (result.ok) { return result.value; }
	unreachable;
}

function blockOf(settings: ScalableAoSettings, camera: Camera3D, zeroToOne: boolean): Vec<float32> {
	let out: Vec<float32> = new Array(SAO_UNIFORM_LENGTH);
	writeSaoBlock(settings, camera, resolvedView(camera), zeroToOne, out);
	return out;
}

function accepts(settings: ScalableAoSettings): boolean {
	return settings.valid();
}

test "the settings start as SAO.new's and are refused past SAO's sample and turn bounds" {
	const settings: ScalableAoSettings = ScalableAoSettings.defaults();
	assert settings.numSamples == 20 && settings.numSpiralTurns == 7;
	assert settings.sampleRadius == 1.0 && settings.intensity == 1.0;
	assert approx(settings.bias, 0.01) && settings.noiseScaleX == 10.0;
	assert settings.noiseScaleY == 10.0 && !settings.scalableBias;
	assert settings.startFade === null && settings.fade === null && settings.valid();
	assert !accepts({ ...settings, numSamples: 0 }) && !accepts({ ...settings, numSamples: 128 });
	assert accepts({ ...settings, numSamples: 127 });
	assert !accepts({ ...settings, numSpiralTurns: 16 });
	assert !accepts({ ...settings, sampleRadius: 0.0 });
	assert !accepts({ ...settings, intensity: -1.0 });
	assert !accepts({ ...settings, fade: { start: 5.0, end: 5.0 } });
	assert accepts({ ...settings, startFade: { start: 1.0, end: 2.0 } });
}

test "the block carries the inverse viewProj, the view depth row and half the y scale as fovTan" {
	const camera: Camera3D = perspective();
	const view: CameraView = resolvedView(camera);
	const out: Vec<float32> = blockOf(ScalableAoSettings.defaults(), camera, false);
	let matrix: Vec<float32> = new Array(16);
	view.inverseViewProj.writeTo(matrix, 0);
	for (let i = 0; i < 16; i++) { assert out[SAO_INVERSE_VIEW_PROJ + i] == matrix[i]; }
	const forward: Vec3 = view.basis.forward;
	const ahead: Vec3 = vec3(1.0 + forward.x * 3.0, 2.0 + forward.y * 3.0, 3.0 + forward.z * 3.0);
	const depth: float32 = out[SAO_VIEW_DEPTH] * ahead.x + out[SAO_VIEW_DEPTH + 1] * ahead.y +
		out[SAO_VIEW_DEPTH + 2] * ahead.z + out[SAO_VIEW_DEPTH + 3];
	assert approx(depth, 3.0);
	assert out[SAO_RADIUS] == 1.0 && out[SAO_RADIUS + 1] == 1.0;
	assert approx(out[SAO_RADIUS + 2], 0.01) && approx(view.projectionY, 1.0);
	assert approx(out[SAO_RADIUS + 3], 0.5);
	assert out[SAO_TAPS] == 20.0 && out[SAO_TAPS + 1] == 7.0;
	assert out[SAO_TAPS + 2] == 0.0 && out[SAO_TAPS + 3] == 0.0;
	assert out[SAO_NOISE] == 10.0 && out[SAO_NOISE + 1] == 10.0 && out[SAO_NOISE + 2] == 0.0;
	assert out[SAO_EYE] == 1.0 && out[SAO_EYE + 1] == 2.0 && out[SAO_EYE + 2] == 3.0;
}

test "an orthographic camera, the scalable bias and a zero-to-one depth set their flags" {
	const ortho: Camera3D = {
		...perspective(),
		projection: { kind: ProjectionKind.Orthographic, worldPerTexel: 0.1, snap: false },
	};
	const settings: ScalableAoSettings = { ...ScalableAoSettings.defaults(), scalableBias: true };
	const out: Vec<float32> = blockOf(settings, ortho, true);
	assert out[SAO_TAPS + 2] == 1.0 && out[SAO_TAPS + 3] == 1.0 && out[SAO_NOISE + 2] == 1.0;
	assert approx(out[SAO_RADIUS + 3], resolvedView(ortho).projectionY * 0.5);
}

test "a fade left off leaves the occlusion as it is, at any distance" {
	const out: Vec<float32> = blockOf(ScalableAoSettings.defaults(), perspective(), false);
	const fade = (distance: float32): float32 => saoFaded(0.25, distance, out[SAO_FADE],
		out[SAO_FADE + 1], out[SAO_FADE + 2], out[SAO_FADE + 3]);
	assert fade(0.0) == 0.25 && fade(1.0) == 0.25 && fade(1000.0) == 0.25;
	assert fade(1000000.0) == 0.25;
	const faded: ScalableAoSettings = {
		...ScalableAoSettings.defaults(),
		startFade: { start: 1.0, end: 2.0 },
		fade: { start: 10.0, end: 20.0 },
	};
	const set: Vec<float32> = blockOf(faded, perspective(), false);
	assert set[SAO_FADE] == 1.0 && set[SAO_FADE + 1] == 2.0;
	assert set[SAO_FADE + 2] == 10.0 && set[SAO_FADE + 3] == 20.0;
}

test "the noise is genNoise(128)'s grey opaque texels, the same on every run" {
	const pixels: Vec<uint32> = saoNoisePixels();
	assert pixels.length == SAO_NOISE_SIZE * SAO_NOISE_SIZE && SAO_NOISE_SIZE == 128;
	const again: Vec<uint32> = saoNoisePixels();
	let sum: float64 = 0.0;
	let distinct: boolean = false;
	for (let i = 0; i < pixels.length; i++) {
		const texel: uint32 = pixels[i];
		const n: uint32 = texel & 255;
		assert texel == again[i] && (texel >> 24) == 255;
		assert ((texel >> 8) & 255) == n && ((texel >> 16) & 255) == n;
		if (texel != pixels[0]) { distinct = true; }
		sum = sum + (n as float64);
	}
	const mean: float64 = sum / (pixels.length as float64);
	assert distinct && mean > 120.0 && mean < 135.0;
}
