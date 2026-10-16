// void2d's MetaScript shader stages on the CPU: their helpers against the T0 copies in sdf.ms,
// textGamma.ms, textSdf.ms and gradient.ms, and the stages a CPU can run (no derivatives).

import { Wrap } from "../gpu/state";
import { Texture2d, Vec4f, vec2f, vec4f } from "../shader/std";
import * as sdf from "../void2d/sdf";
import { dither4x4 } from "../void2d/gradient";
import { correctCoverage, gammaRatios } from "../void2d/textGamma";
import * as textSdf from "../void2d/textSdf";
import {
	applyContrastAndGamma,
	bayer4,
	blurFs,
	coverageFromDistance,
	erfApprox,
	gaussianPdf,
	roundedRectDistance,
	sdfCoverage,
	shadowCoverage,
	smoothUnionDistance,
	spriteFs,
	uiVs,
	underlineDistance,
} from "../void2d/shader2d";

function near(a: float32, b: float32): boolean { return Math.abs(a - b) < 1.0e-5; }

function near(a: Vec4f, b: Vec4f): boolean {
	return near(a.x, b.x) && near(a.y, b.y) && near(a.z, b.z) && near(a.w, b.w);
}

function filled(width: int32, height: int32, texel: Vec4f): Texture2d {
	let texels: float32[] = [];
	for (let i = 0; i < width * height; i++) {
		texels.push(texel.x);
		texels.push(texel.y);
		texels.push(texel.z);
		texels.push(texel.w);
	}
	return { width, height, texels };
}

const RADII: float32[] = [0.0, 1.5, 12.0];
const SIGMAS: float32[] = [0.0, 1.5, 4.0];
const SHADOW_POINTS: float32[] = [-9.0, -2.0, 0.5, 7.0];
const COVERAGES: float32[] = [0.0, 0.2, 0.5, 0.9, 1.0];

test "the SDF helpers agree with sdf.ms, where the coverage oracle judges them" {
	const points: float32[] = [-7.5, -3.0, 0.0, 2.25, 6.0, 9.5];
	for (const x of points) {
		for (const y of points) {
			for (const r of RADII) {
				const expected = sdf.roundedRectDistance(x, y, 6.0, 4.0, r);
				assert near(roundedRectDistance(vec2f(x, y), vec2f(6.0, 4.0), r), expected);
			}
		}
		assert near(coverageFromDistance(x * 0.1, 0.75), sdf.coverageFromDistance(x * 0.1, 0.75));
		assert near(erfApprox(x * 0.3), sdf.erfApprox(x * 0.3));
		assert near(gaussianPdf(x, 2.5), sdf.gaussianPdf(x, 2.5));
		assert near(smoothUnionDistance(x, 1.0, 2.0), sdf.smoothUnionDistance(x, 1.0, 2.0));
	}
	assert coverageFromDistance(0.0, 0.0) == 1.0 && coverageFromDistance(0.1, 0.0) == 0.0;
}

test "a shadow's coverage agrees with sdf.ms, hard and blurred" {
	const radii = vec4f(2.0, 3.0, 0.5, 9.0);
	for (const sigma of SIGMAS) {
		for (const x of SHADOW_POINTS) {
			const p = vec2f(x, x * 0.5 - 1.0);
			const expected = sdf.shadowCoverage(p.x, p.y, 6.0, 4.0, 2.0, 3.0, 0.5, 9.0, 1.0, -1.0,
				sigma, 0.5);
			const actual = shadowCoverage(p, vec2f(6.0, 4.0), radii, vec2f(1.0, -1.0), sigma, 0.5);
			assert Math.abs(actual - expected) < 1.0e-4;
		}
	}
}

test "text gamma and SDF coverage agree with their T0 copies" {
	const ratios = gammaRatios(1.8);
	const asVec = vec4f(ratios.r0, ratios.r1, ratios.r2, ratios.r3);
	for (const c of COVERAGES) {
		const expected = correctCoverage(c, 0.9, 0.2, 0.1, 1.0, ratios);
		assert near(applyContrastAndGamma(c, { x: 0.9, y: 0.2, z: 0.1 }, 1.0, asVec), expected);
		assert near(sdfCoverage(c, 1.3), textSdf.sdfCoverage(c, 1.3));
	}
}

test "the 4x4 Bayer threshold is gradient.ms's, floored at negative pixels as GLSL's mod is" {
	for (let y = -5; y < 6; y++) {
		for (let x = -5; x < 6; x++) {
			const noise = (bayer4(vec2f(x as float32 + 0.5, y as float32 + 0.5)) - 7.5) *
				(2.0 / (7.5 * 255.0));
			assert near(noise as float32, dither4x4(x, y));
		}
	}
}

function uiAt(mode: float32): Vec4f {
	const out = uiVs({
		corner: vec2f(0.0, 0.0),
		iAffine: vec4f(2.0, 0.0, 0.0, 2.0),
		iOriginSize: vec4f(10.0, 20.0, 8.0, 6.0),
		iUvRadii: vec4f(1.0, 2.0, 3.0, 4.0),
		iBorders: vec4f(0.0),
		iParams0: vec4f(mode, 0.0, 0.0, 0.0),
		iParams1: vec4f(0.0),
		iColorFill: vec4f(1.0),
		iColorBorder: vec4f(1.0),
		iColorExtra: vec4f(0.0),
	}, {
		ui_params: {
			viewport: vec4f(100.0, 100.0, 0.0, 1.0),
			clipU: vec4f(0.0),
			clipV: vec4f(0.0),
			shift: vec4f(0.0),
		},
	});
	return vec4f(out.vRadii.x, out.vUvAa.z, out.vLocalHalf.x, out.clipDistance.x);
}

test "a glyph keeps no radii and no antialiasing inflation; a box gets one device pixel" {
	assert uiAt(2.0) == vec4f(0.0, 0.0, -4.0, 1.0);
	assert uiAt(0.0) == vec4f(1.0, 0.5, -4.5, 1.0);
}

function spriteOf(premultiplied: float32): Vec4f {
	return spriteFs({
		uv: vec2f(0.5, 0.5),
		color: vec4f(1.0, 1.0, 1.0, 0.5),
		srcPremult: premultiplied,
		clipDistance: vec4f(1.0),
	}, {
		spriteTex: filled(1, 1, vec4f(0.8, 0.4, 0.2, 1.0)),
		spriteSmp: { nearest: true, wrap: Wrap.Clamp },
	});
}

test "the blur's taps sum to one and a sprite premultiplies a straight source" {
	const flat = filled(4, 4, vec4f(0.4, 0.2, 0.8, 1.0));
	const blurred = blurFs({ uv: vec2f(0.5, 0.5) }, {
		srcTex: flat,
		srcSmp: { nearest: false, wrap: Wrap.Clamp },
		blur_params: { dir: vec4f(0.25, 0.0, 0.0, 0.0) },
	});
	assert Math.abs(blurred.x - 0.4) < 1.0e-5 && Math.abs(blurred.w - 1.0) < 1.0e-5;
	assert near(spriteOf(0.0), vec4f(0.4, 0.2, 0.1, 0.5));
	assert near(spriteOf(1.0), vec4f(0.4, 0.2, 0.1, 0.5));
}

test "an underline is the straight bar, or a wave centred on the quad's left edge" {
	const half = vec2f(20.0, 3.0);
	const p = vec2f(4.0, 1.0);
	assert underlineDistance(p, half, vec4f(1.5, 0.0, 0.0, 0.0)) ==
		roundedRectDistance(p, half, 0.0);
	assert near(underlineDistance(vec2f(-20.0, 0.0), half, vec4f(1.5, 1.0, 0.0, 0.0)), -0.75);
}
