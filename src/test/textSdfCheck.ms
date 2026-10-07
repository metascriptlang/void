import {
	SDF_EDGE,
	fieldByte,
	sdfCoverage,
	sampleField,
} from "../void2d/textSdf";
import { gammaRatios, correctCoverage } from "../void2d/textGamma";
import { approx } from "./helpers";

const EDGE_UNIT: float32 = (191.0 / 255.0) as float32;

function sampleAt(outwardTexels: float32): float32 {
	return (EDGE_UNIT - outwardTexels * 0.125) as float32;
}

test "the outline encodes as byte 191 and a texel of distance is 31.875 bytes" {
	assert SDF_EDGE == 191;
	assert fieldByte(0.0) == 191;
	assert fieldByte(-1.0) == 222;
	assert fieldByte(1.0) == 159;
	assert fieldByte(-2.0) == 254;
	assert fieldByte(-2.1) == 255;
	assert fieldByte(6.0) == 0;
	assert fieldByte(100.0) == 0;
	assert fieldByte(-100.0) == 255;
}

test "a sample on the outline covers half a pixel at any magnification" {
	for (const texels of [0.25, 1.0, 2.4, 8.0]) {
		const tpp: float32 = texels as float32;
		assert approx(sdfCoverage(EDGE_UNIT, tpp), 0.5);
	}
}

test "half a pixel in or out of the outline is full or empty coverage" {
	for (const texels of [0.25, 1.0, 2.4]) {
		const tpp: float32 = texels as float32;
		const half: float32 = (tpp * 0.5) as float32;
		assert approx(sdfCoverage(sampleAt(-half), tpp), 1.0);
		assert approx(sdfCoverage(sampleAt(half), tpp), 0.0);
		assert approx(sdfCoverage(sampleAt(-half * 0.5), tpp), 0.75);
		assert approx(sdfCoverage(sampleAt(half * 0.5), tpp), 0.25);
	}
}

test "coverage never falls as the field byte rises" {
	for (const texels of [0.25, 1.0, 2.4]) {
		const tpp: float32 = texels as float32;
		let last: float32 = -1.0;
		for (let b = 0; b < 256; b++) {
			const c: float32 = sdfCoverage((b as float32) / 255.0, tpp);
			assert c >= last;
			assert c >= 0.0 && c <= 1.0;
			last = c;
		}
	}
}

test "coverage is symmetric about the outline" {
	for (const texels of [0.25, 1.0, 2.4]) {
		const tpp: float32 = texels as float32;
		for (let step = 1; step < 8; step++) {
			const d: float32 = ((step as float32) * 0.1 * tpp) as float32;
			const inside: float32 = sdfCoverage(sampleAt(-d), tpp);
			const outside: float32 = sdfCoverage(sampleAt(d), tpp);
			assert approx(inside + outside, 1.0);
		}
	}
}

test "an empty field is empty and a deep interior is full" {
	assert sdfCoverage(0.0, 1.0) == 0.0;
	assert sdfCoverage(1.0, 1.0) == 1.0;
	assert sdfCoverage(0.0, 0.25) == 0.0;
	assert sdfCoverage(1.0, 100.0) > 0.5;
}

test "the weight correction after the ramp is the coverage layer's, one rule for both regimes" {
	const ratios = gammaRatios(1.8);
	const ramp: float32 = sdfCoverage(EDGE_UNIT, 1.0);
	const corrected: float32 = correctCoverage(ramp, 1.0, 1.0, 1.0, 1.0, ratios);
	assert corrected > 0.69 && corrected < 0.70;
	assert correctCoverage(sdfCoverage(0.0, 1.0), 1.0, 1.0, 1.0, 1.0, ratios) == 0.0;
}

test "a bilinear sample reads texel centres exactly and blends between them" {
	const grid: uint8[4] = [0, 100, 200, 40];
	assert approx(sampleField(grid, 2, 2, 2, 0.5, 0.5), 0.0);
	assert approx(sampleField(grid, 2, 2, 2, 1.5, 0.5), (100.0 / 255.0) as float32);
	assert approx(sampleField(grid, 2, 2, 2, 0.5, 1.5), (200.0 / 255.0) as float32);
	assert approx(sampleField(grid, 2, 2, 2, 1.0, 0.5), (50.0 / 255.0) as float32);
	assert approx(sampleField(grid, 2, 2, 2, 1.0, 1.0), (85.0 / 255.0) as float32);
}

test "outside the grid the field is zero, far outside" {
	const grid: uint8[4] = [255, 255, 255, 255];
	assert approx(sampleField(grid, 2, 2, 2, -5.0, 0.5), 0.0);
	assert approx(sampleField(grid, 2, 2, 2, 0.5, 9.0), 0.0);
	assert approx(sampleField(grid, 2, 2, 2, 0.0, 0.5), 0.5);
	assert approx(sampleField(grid, 2, 2, 2, 1.0, 1.0), 1.0);
}
