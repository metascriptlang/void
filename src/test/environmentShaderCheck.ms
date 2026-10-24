import { Vec3, vec3 } from "../math/math3d";
import { Wrap } from "../gpu/state";
import { Sampler, Texture2d, TextureCube, Vec3f, Vec4f, vec3f, vec4f } from "../shader/std";
import {
	CubeBakeBindings,
	EnvironmentInput,
	PanoramaBindings,
	cosineWeightedSample,
	environmentIrradianceFs,
	environmentPanoramaFs,
	environmentRadianceFs,
	environmentResampleFs,
	faceDirection,
	hammersley,
	importanceSampleGgx,
	sampleLod,
} from "../void3d/environmentShader";
import {
	HammersleyForm,
	cosineWeightedSample as referenceCosineSample,
	cubeFaceDirection,
	hammersley as referenceHammersley,
	importanceSampleGgx as referenceGgx,
} from "../void3d/pbrEnvironment";

function close(actual: float32, expected: float32, tolerance: float32 = 0.00001): boolean {
	return Math.abs(actual - expected) < tolerance;
}

function closeTo(actual: Vec3f, expected: Vec3, tolerance: float32 = 0.00001): boolean {
	return close(actual.x, expected.x, tolerance) && close(actual.y, expected.y, tolerance) &&
		close(actual.z, expected.z, tolerance);
}

function asVec3(v: Vec3): Vec3f { return vec3f(v.x, v.y, v.z); }

// Environment.hx getCubeMatrix, the rows environment.ms writes into envFaceX..Z.
function faceRows(face: int32): Vec4f[] {
	return match (face) {
		0 => [vec4f(0.0, 0.0, -1.0, 0.0), vec4f(0.0, -1.0, 0.0, 0.0), vec4f(1.0, 0.0, 0.0, 0.0)],
		1 => [vec4f(0.0, 0.0, 1.0, 0.0), vec4f(0.0, -1.0, 0.0, 0.0), vec4f(-1.0, 0.0, 0.0, 0.0)],
		2 => [vec4f(1.0, 0.0, 0.0, 0.0), vec4f(0.0, 0.0, 1.0, 0.0), vec4f(0.0, 1.0, 0.0, 0.0)],
		3 => [vec4f(1.0, 0.0, 0.0, 0.0), vec4f(0.0, 0.0, -1.0, 0.0), vec4f(0.0, -1.0, 0.0, 0.0)],
		4 => [vec4f(1.0, 0.0, 0.0, 0.0), vec4f(0.0, -1.0, 0.0, 0.0), vec4f(0.0, 0.0, 1.0, 0.0)],
		_ => [vec4f(-1.0, 0.0, 0.0, 0.0), vec4f(0.0, -1.0, 0.0, 0.0), vec4f(0.0, 0.0, -1.0, 0.0)],
	};
}

function texelDirection(face: int32, x: int32, y: int32, size: int32): Vec3f {
	const rows = faceRows(face);
	const position = vec4f((x as float32) + 0.5, (y as float32) + 0.5, 0.5, 1.0);
	return faceDirection(position, size as float32, rows[0], rows[1], rows[2]);
}

// A cube of `size` whose every texel holds face * 100 + its row-major index in red.
function numberedCube(size: int32): TextureCube {
	let texels: float32[] = [];
	for (let face = 0; face < 6; face++) {
		for (let i = 0; i < size * size; i++) {
			texels.push((face * 100 + i) as float32);
			texels.push(0.0);
			texels.push(0.0);
			texels.push(1.0);
		}
	}
	return { size, texels };
}

function constantCube(size: int32, value: float32): TextureCube {
	let texels: float32[] = [];
	for (let i = 0; i < 6 * size * size; i++) {
		texels.push(value);
		texels.push(value);
		texels.push(value);
		texels.push(1.0);
	}
	return { size, texels };
}

const NEAREST: Sampler = { nearest: true, wrap: Wrap.Clamp };

function drawn(x: int32, y: int32): EnvironmentInput {
	return { position: vec4f((x as float32) + 0.5, (y as float32) + 0.5, 0.5, 1.0) };
}

function bake(
	source: TextureCube, face: int32, bakeX: float32, count: float32, drawnSize: int32,
	hdrMax: float32,
): CubeBakeBindings {
	const rows = faceRows(face);
	return {
		sourceCube: source,
		environmentSampler: NEAREST,
		environmentParams: {
			envFaceX: rows[0],
			envFaceY: rows[1],
			envFaceZ: rows[2],
			envBake: vec4f(bakeX, count, source.size as float32, drawnSize as float32),
			envSource: vec4f(1.0, 1.0, hdrMax, 0.0),
		},
	};
}

test "a baked texel's direction reads back that texel through the cube sampler" {
	const size = 4;
	const cube = numberedCube(size);
	for (let face = 0; face < 6; face++) {
		for (let y = 0; y < size; y++) {
			for (let x = 0; x < size; x++) {
				const expected = (face * 100 + y * size + x) as float32;
				const out = environmentResampleFs(drawn(x, y),
					bake(cube, face, 0.0, 1.0, size, 100.0));
				assert out.x == expected;
			}
		}
	}
}

test "faceDirection is cubeFaceDirection at the texel centre" {
	const size = 8;
	for (let face = 0; face < 6; face++) {
		for (const at of [0, 3, 7]) {
			const u = ((at as float32) + 0.5) / (size as float32);
			const v = ((7 - at) as float32 + 0.5) / (size as float32);
			const reference = cubeFaceDirection(face, u, v);
			assert reference.ok;
			if (reference.ok) {
				assert closeTo(texelDirection(face, at, 7 - at, size), reference.value);
			}
		}
	}
}

test "hammersley is the unit radical inverse set" {
	for (let i = 0; i < 64; i++) {
		const reference = referenceHammersley(i, 64, HammersleyForm.Unit);
		assert reference.ok;
		if (reference.ok) {
			const point = hammersley(i as uint32, 64 as uint32);
			assert close(point.x, reference.value.x, 0.000001);
			assert close(point.y, reference.value.y, 0.000001);
		}
	}
}

test "the GGX and cosine samples are pbrEnvironment's" {
	const n: Vec3 = vec3(0.3, -0.5, 0.8).normalized();
	for (let i = 0; i < 16; i++) {
		const point = hammersley(i as uint32, 16 as uint32);
		const ggx = referenceGgx(0.6, { x: point.x, y: point.y }, n);
		assert ggx.ok;
		if (ggx.ok) { assert closeTo(importanceSampleGgx(0.6, point, asVec3(n)), ggx.value); }
		const cosine = referenceCosineSample({ x: point.x, y: point.y }, n);
		assert cosine.ok;
		if (cosine.ok) { assert closeTo(cosineWeightedSample(point, asVec3(n)), cosine.value); }
	}
}

test "a sample reads the mip whose texel covers its solid angle, never finer than mip 0" {
	const texel: float32 = 4.0 * 3.14159265358979 / (6.0 * 8.0 * 8.0);
	assert close(sampleLod(1.0 / texel, 8.0, 1.0), 0.0, 0.0001);
	assert close(sampleLod(1.0 / (4.0 * texel), 8.0, 1.0), 1.0, 0.0001);
	assert close(sampleLod(1.0 / (16.0 * texel), 8.0, 4.0), 1.0, 0.0001);
	assert sampleLod(100.0 / texel, 8.0, 1.0) == 0.0;
}

test "radiance and irradiance of a constant environment are that constant, clamped to hdrMax" {
	const cube = constantCube(2, 3.0);
	for (const face of [0, 3, 5]) {
		const rough = environmentRadianceFs(drawn(1, 0), bake(cube, face, 0.5, 32.0, 4, 10.0));
		assert close(rough.x, 3.0, 0.0001) && close(rough.z, 3.0, 0.0001);
		const sharp = environmentRadianceFs(drawn(0, 1), bake(cube, face, 0.1, 32.0, 4, 10.0));
		assert close(sharp.y, 3.0, 0.0001);
		const diffuse = environmentIrradianceFs(drawn(2, 3),
			bake(cube, face, 0.0, 64.0, 4, 10.0));
		assert close(diffuse.x, 3.0, 0.0001);
	}
	const bright = constantCube(2, 20.0);
	const clamped = environmentIrradianceFs(drawn(0, 0), bake(bright, 2, 0.0, 64.0, 2, 10.0));
	assert close(clamped.x, 10.0, 0.0001);
}

test "radiance at a near-mirror roughness is the source along the texel's direction" {
	const cube = numberedCube(4);
	const out = environmentRadianceFs(drawn(1, 2), bake(cube, 4, 0.01, 8.0, 4, 1000.0));
	assert close(out.x, 400.0 + 9.0, 0.001);
}

function panorama(): Texture2d {
	const rows: float32[] = [1.0, 1.0, 0.25, 0.25];
	let texels: float32[] = [];
	for (const value of rows) {
		texels.push(value);
		texels.push(value * 0.5);
		texels.push(0.0);
		texels.push(1.0);
	}
	return { width: 2, height: 2, texels };
}

function panoramaBindings(face: int32, threshold: float32, scale: float32): PanoramaBindings {
	const rows = faceRows(face);
	return {
		panorama: panorama(),
		environmentSampler: NEAREST,
		environmentParams: {
			envFaceX: rows[0],
			envFaceY: rows[1],
			envFaceZ: rows[2],
			envBake: vec4f(0.0, 0.0, 2.0, 2.0),
			envSource: vec4f(threshold, scale, 10.0, 0.0),
		},
	};
}

test "the panorama's top row is the sky, its bottom row the ground" {
	const up = environmentPanoramaFs(drawn(0, 0), panoramaBindings(2, 2.0, 1.0));
	assert up.x == 1.0 && up.y == 0.5;
	const down = environmentPanoramaFs(drawn(0, 0), panoramaBindings(3, 2.0, 1.0));
	assert down.x == 0.25;
}

test "a panorama texel above the threshold is scaled, as Heaps fakes HDR" {
	const up = environmentPanoramaFs(drawn(0, 0), panoramaBindings(2, 0.5, 4.0));
	assert up.x == 4.0 && up.y == 2.0;
	const down = environmentPanoramaFs(drawn(0, 0), panoramaBindings(3, 0.5, 4.0));
	assert down.x == 0.25;
}
