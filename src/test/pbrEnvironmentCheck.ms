import { Vec3, vec3 } from "../math/math3d";
import { float32At } from "../void3d/gltfDecode";
import {
	PbrEnvironmentError,
	HammersleyForm,
	Point2,
	RadianceSample,
	PbrIndirectInput,
	hammersley,
	cosineWeightedSample,
	importanceSampleGgx,
	cubeFaceDirection,
	directionToCubeTexel,
	splitSumLut,
	splitSumAnalytic,
	pbrIndirect,
	projectSh,
	shIrradiance,
} from "../void3d/pbrEnvironment";

function close(actual: float32, expected: float64, tolerance: float64 = 0.000001): boolean {
	return Math.abs((actual as float64) - expected) < tolerance;
}

function closeVector(
	actual: Vec3, x: float64, y: float64, z: float64, tolerance: float64 = 0.000001,
): boolean {
	return close(actual.x, x, tolerance) && close(actual.y, y, tolerance) &&
		close(actual.z, z, tolerance);
}

function nan(): float32 { return float32At([0, 0, 192, 127], 0); }

test "hammersley second coordinate is Heaps' signed bit reversal or the unit set" {
	const one = hammersley(1, 4);
	assert one.ok;
	if (one.ok) { assert one.value.x == 0.25; assert one.value.y == -0.5; }
	const oneUnit = hammersley(1, 4, HammersleyForm.Unit);
	assert oneUnit.ok;
	if (oneUnit.ok) { assert oneUnit.value.y == 0.5; }
	const two = hammersley(2, 4);
	assert two.ok;
	if (two.ok) { assert two.value.x == 0.5; assert two.value.y == 0.25; }
	const three = hammersley(3, 4);
	assert three.ok;
	if (three.ok) { assert three.value.y == -0.25; }
	const zero = hammersley(0, 4);
	assert zero.ok;
	if (zero.ok) { assert zero.value.x == 0.0 && zero.value.y == 0.0; }
}

test "hammersley refuses a zero count and an index outside it" {
	const none = hammersley(0, 0);
	assert !none.ok;
	if (!none.ok) { assert none.error == PbrEnvironmentError.ZeroSamples; }
	const past = hammersley(4, 4);
	assert !past.ok;
	if (!past.ok) { assert past.error == PbrEnvironmentError.OutOfRange; }
	assert !hammersley(-1, 4).ok;
}

test "cosine sample hand value and unit length" {
	const up = vec3(0.0, 0.0, 1.0);
	const hand = cosineWeightedSample({ x: 0.75, y: 0.0 }, up);
	assert hand.ok;
	if (hand.ok) { assert closeVector(hand.value, 0.0, -0.5, 0.8660254); }
	const tilted = cosineWeightedSample({ x: 0.3, y: 0.7 }, vec3(2.0, -1.0, 0.5));
	assert tilted.ok;
	if (tilted.ok) {
		assert close(tilted.value.dot(tilted.value), 1.0, 0.00001);
		assert tilted.value.dot(vec3(2.0, -1.0, 0.5).normalized()) > 0.0;
	}
}

test "ggx sample hand values; roughness zero returns the normal as Heaps does" {
	const up = vec3(0.0, 0.0, 1.0);
	const rough = importanceSampleGgx(1.0, { x: 0.25, y: 0.75 }, up);
	assert rough.ok;
	if (rough.ok) { assert closeVector(rough.value, 0.8660254, 0.0, 0.5); }
	const mirror = importanceSampleGgx(0.0, { x: 0.25, y: 0.75 }, up);
	assert mirror.ok;
	if (mirror.ok) { assert closeVector(mirror.value, 0.0, 0.0, 1.0); }
	const heapsOdd = importanceSampleGgx(0.5, { x: 0.25, y: -0.5 }, up);
	assert heapsOdd.ok;
	if (heapsOdd.ok) { assert closeVector(heapsOdd.value, 0.0, 0.0, 1.0); }
}

test "sampling refuses non-finite, out of range and zero directions" {
	const up = vec3(0.0, 0.0, 1.0);
	const p: Point2 = { x: 0.5, y: 0.5 };
	const bad = importanceSampleGgx(1.5, p, up);
	assert !bad.ok;
	if (!bad.ok) { assert bad.error == PbrEnvironmentError.OutOfRange; }
	const notNumber = importanceSampleGgx(nan(), p, up);
	assert !notNumber.ok;
	if (!notNumber.ok) { assert notNumber.error == PbrEnvironmentError.NonFinite; }
	const flat = cosineWeightedSample(p, vec3(0.0, 0.0, 0.0));
	assert !flat.ok;
	if (!flat.ok) { assert flat.error == PbrEnvironmentError.ZeroDirection; }
	assert !cosineWeightedSample({ x: 1.5, y: 0.0 }, up).ok;
	assert !importanceSampleGgx(0.5, { x: 0.5, y: 1.0 }, up).ok;
}

test "cube faces follow +X -X +Y -Y +Z -Z and the GL (s, t) table" {
	const centres = [
		vec3(1.0, 0.0, 0.0), vec3(-1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0),
		vec3(0.0, -1.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, -1.0),
	];
	for (let face = 0; face < 6; face++) {
		const centre = cubeFaceDirection(face, 0.5, 0.5);
		assert centre.ok;
		if (centre.ok) { assert closeVector(centre.value, centres[face].x, centres[face].y, centres[face].z); }
		const texel = directionToCubeTexel(centres[face]);
		assert texel.ok;
		if (texel.ok) { assert texel.value.face == face; assert close(texel.value.u, 0.5); }
	}
	const corner = directionToCubeTexel(vec3(1.0, -0.5, -0.25));
	assert corner.ok;
	if (corner.ok) {
		assert corner.value.face == 0;
		assert close(corner.value.u, 0.625);
		assert close(corner.value.v, 0.75);
	}
}

test "cube texel round trip over every face" {
	for (let face = 0; face < 6; face++) {
		for (let i = 0; i < 5; i++) {
			const u: float32 = 0.1 + (i as float32) * 0.2;
			const v: float32 = 0.9 - (i as float32) * 0.15;
			const direction = cubeFaceDirection(face, u, v);
			assert direction.ok;
			if (direction.ok) {
				const texel = directionToCubeTexel(direction.value);
				assert texel.ok;
				if (texel.ok) {
					assert texel.value.face == face;
					assert close(texel.value.u, u as float64, 0.00001);
					assert close(texel.value.v, v as float64, 0.00001);
				}
			}
		}
	}
	assert !cubeFaceDirection(6, 0.5, 0.5).ok;
	assert !cubeFaceDirection(0, 1.5, 0.5).ok;
	assert !directionToCubeTexel(vec3(0.0, 0.0, 0.0)).ok;
}

test "lut at roughness zero is a hand value for both sample forms" {
	const head = splitSumLut(0.0, 1.0, 64);
	assert head.ok;
	if (head.ok) { assert close(head.value.scale, 1.0, 0.00001); assert close(head.value.bias, 0.0, 0.00001); }
	const oblique = splitSumLut(0.0, 0.6, 64, HammersleyForm.Unit);
	assert oblique.ok;
	if (oblique.ok) {
		assert close(oblique.value.scale, 0.98976, 0.00001);
		assert close(oblique.value.bias, 0.01024, 0.00001);
	}
}

test "lut energy never exceeds one and the unit set sits near the analytic fit" {
	const roughnesses: float32[] = [0.1, 0.5, 0.9];
	const views: float32[] = [0.2, 0.6, 1.0];
	for (const roughness of roughnesses) {
		for (const view of views) {
			const heaps = splitSumLut(roughness, view, 1024);
			const unit = splitSumLut(roughness, view, 1024, HammersleyForm.Unit);
			const fit = splitSumAnalytic(roughness, view);
			assert heaps.ok && unit.ok && fit.ok;
			if (heaps.ok && unit.ok && fit.ok) {
				assert heaps.value.scale + heaps.value.bias <= 1.0001;
				assert unit.value.scale + unit.value.bias <= 1.0001;
				assert unit.value.scale >= 0.0 && unit.value.bias >= 0.0;
				assert close(unit.value.scale, fit.value.scale as float64, 0.2);
				assert close(unit.value.bias, fit.value.bias as float64, 0.07);
			}
		}
	}
}

test "lut with Heaps' signed second coordinate differs from the unit set" {
	const heaps = splitSumLut(0.9, 1.0, 4096);
	const unit = splitSumLut(0.9, 1.0, 4096, HammersleyForm.Unit);
	assert heaps.ok && unit.ok;
	if (heaps.ok && unit.ok) {
		assert Math.abs((heaps.value.scale - unit.value.scale) as float64) > 0.4;
	}
}

test "lut and analytic fit refuse bad input by name" {
	const zeroSamples = splitSumLut(0.5, 0.5, 0);
	assert !zeroSamples.ok;
	if (!zeroSamples.ok) { assert zeroSamples.error == PbrEnvironmentError.ZeroSamples; }
	const grazing = splitSumLut(0.5, 0.0);
	assert !grazing.ok;
	if (!grazing.ok) { assert grazing.error == PbrEnvironmentError.OutOfRange; }
	assert !splitSumLut(1.5, 0.5).ok;
	const notNumber = splitSumLut(0.5, nan());
	assert !notNumber.ok;
	if (!notNumber.ok) { assert notNumber.error == PbrEnvironmentError.NonFinite; }
	assert !splitSumAnalytic(0.5, 1.5).ok;
	assert !splitSumAnalytic(nan(), 0.5).ok;
}

test "analytic fit hand values" {
	const head = splitSumAnalytic(0.0, 1.0);
	assert head.ok;
	if (head.ok) {
		assert close(head.value.scale, 0.9941270807, 0.000001);
		assert close(head.value.bias, 0.0058729193, 0.000001);
	}
	const middle = splitSumAnalytic(0.5, 0.5);
	assert middle.ok;
	if (middle.ok) {
		assert close(middle.value.scale, 0.7032443292, 0.000001);
		assert close(middle.value.bias, 0.0217556708, 0.000001);
	}
	const rough = splitSumAnalytic(1.0, 1.0);
	assert rough.ok;
	if (rough.ok) {
		assert close(rough.value.scale, 0.4524, 0.000001);
		assert close(rough.value.bias, 0.00005, 0.000001);
	}
}

function indirectInput(metalness: float32): PbrIndirectInput {
	return {
		diffuseIrradiance: vec3(0.5, 0.25, 0.125),
		specularRadiance: vec3(2.0, 1.0, 0.5),
		albedo: vec3(0.8, 0.4, 0.2),
		metalness: metalness,
		roughness: 0.5,
		occlusion: 0.5,
		normalView: 1.0,
		lut: { scale: 0.75, bias: 0.05 },
		power: 2.0,
	};
}

test "indirect hand values for a dielectric and a metal" {
	const dielectric = pbrIndirect(indirectInput(0.0));
	assert dielectric.ok;
	if (dielectric.ok) {
		assert close(dielectric.value.x, 0.5440851, 0.0001);
		assert close(dielectric.value.y, 0.1760503, 0.0001);
		assert close(dielectric.value.z, 0.0640271, 0.0001);
	}
	const metal = pbrIndirect(indirectInput(1.0));
	assert metal.ok;
	if (metal.ok) {
		assert close(metal.value.x, 1.3000000, 0.0001);
		assert close(metal.value.y, 0.3500126, 0.0001);
		assert close(metal.value.z, 0.1000189, 0.0001);
	}
}

test "indirect refuses out of range and non-finite inputs by name" {
	const base = indirectInput(0.0);
	const range = pbrIndirect({ ...base, roughness: 1.5 });
	assert !range.ok;
	if (!range.ok) { assert range.error == PbrEnvironmentError.OutOfRange; }
	const notNumber = pbrIndirect({ ...base, occlusion: nan() });
	assert !notNumber.ok;
	if (!notNumber.ok) { assert notNumber.error == PbrEnvironmentError.NonFinite; }
	assert !pbrIndirect({ ...base, diffuseIrradiance: vec3(-1.0, 0.0, 0.0) }).ok;
	assert !pbrIndirect({ ...base, lut: { scale: -0.1, bias: 0.0 } }).ok;
}

function latitudeLongitude(base: float32, slope: float32): Vec<RadianceSample> {
	let samples: Vec<RadianceSample> = [];
	const rings: int32 = 48;
	const sectors: int32 = 96;
	for (let i = 0; i < rings; i++) {
		const theta: float32 = ((i as float32) + 0.5) * (Math.PI as float32) / (rings as float32);
		const z: float32 = Math.cos(theta as float64) as float32;
		const s: float32 = Math.sin(theta as float64) as float32;
		const solidAngle: float32 = s * (Math.PI as float32) / (rings as float32) *
			2.0 * (Math.PI as float32) / (sectors as float32);
		for (let j = 0; j < sectors; j++) {
			const phi: float32 = ((j as float32) + 0.5) * 2.0 * (Math.PI as float32) / (sectors as float32);
			const level: float32 = base + slope * z;
			samples.push({
				direction: vec3(s * (Math.cos(phi as float64) as float32),
					s * (Math.sin(phi as float64) as float32), z),
				radiance: vec3(level, level * 0.5, 2.0),
				solidAngle: solidAngle,
			});
		}
	}
	return move samples;
}

test "sh of a constant environment reproduces pi times the radiance" {
	const samples = latitudeLongitude(3.0, 0.0);
	const projected = projectSh(samples);
	assert projected.ok;
	if (projected.ok) {
		const up = projected.value.shIrradiance(vec3(0.0, 0.0, 1.0));
		const side = projected.value.shIrradiance(vec3(1.0, 1.0, 0.0));
		assert up.ok && side.ok;
		if (up.ok && side.ok) {
			assert closeVector(up.value, 9.424778, 4.712389, 6.283185, 0.01);
			assert closeVector(side.value, 9.424778, 4.712389, 6.283185, 0.01);
		}
	}
}

test "sh of a linear environment matches the integral pi + 2 pi / 3 along the axis" {
	const samples = latitudeLongitude(1.0, 1.0);
	const projected = projectSh(samples);
	assert projected.ok;
	if (projected.ok) {
		const up = projected.value.shIrradiance(vec3(0.0, 0.0, 1.0));
		const down = projected.value.shIrradiance(vec3(0.0, 0.0, -1.0));
		assert up.ok && down.ok;
		if (up.ok && down.ok) {
			assert close(up.value.x, 5.235988, 0.01);
			assert close(down.value.x, 1.047198, 0.01);
		}
	}
}

test "sh refuses empty, negative and zero-direction samples by name" {
	let none: Vec<RadianceSample> = [];
	const empty = projectSh(none);
	assert !empty.ok;
	if (!empty.ok) { assert empty.error == PbrEnvironmentError.ZeroSamples; }
	let one: Vec<RadianceSample> = [{
		direction: vec3(0.0, 0.0, 1.0), radiance: vec3(-1.0, 0.0, 0.0), solidAngle: 1.0,
	}];
	assert !projectSh(one).ok;
	let flat: Vec<RadianceSample> = [{
		direction: vec3(0.0, 0.0, 0.0), radiance: vec3(1.0, 0.0, 0.0), solidAngle: 1.0,
	}];
	const zero = projectSh(flat);
	assert !zero.ok;
	if (!zero.ok) { assert zero.error == PbrEnvironmentError.ZeroDirection; }
}
