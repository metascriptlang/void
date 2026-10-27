// The fullscreen passes of src/void3d/post3d.ms run on the CPU, as the oracle for what their
// emitted GLSL draws.

import { Wrap } from "../gpu/state";
import { Texture2d, Vec2f, Vec4f, vec2f, vec3f, vec4f } from "../shader/std";
import {
	BloomBindings,
	OutlineMaskBindings,
	PostInput,
	bloomDownsampleFirstFs,
	bloomDownsampleFs,
	bloomUpsampleFs,
	fullscreenVs,
	outlineMaskFs,
	outlineMixFs,
	outlineWidthFs,
	saoFaded,
	saoOcclusion,
	saoScalableRadius,
	saoScreenRadius,
	saoTap,
	saoTapOffset,
	toneMapFs,
} from "../void3d/post3d";
import { approx } from "./helpers";

function at(x: float32, y: float32): PostInput {
	return { position: { x, y, z: 0.5, w: 1.0 } };
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

function near(a: float32, b: float32): boolean { return Math.abs(a - b) < 1.0e-5; }

function near(a: Vec4f, b: Vec4f): boolean {
	return near(a.x, b.x) && near(a.y, b.y) && near(a.z, b.z) && near(a.w, b.w);
}

test "the fullscreen triangle's corner is its clip position at depth 0.5" {
	assert fullscreenVs({ position: vec2f(-1.0, 3.0) }).clip == vec4f(-1.0, 3.0, 0.5, 1.0);
}

function toneMapOf(hdr: Texture2d, exposure: float32, mode: float32, x: float32): Vec4f {
	return toneMapFs(at(x, 0.5), {
		hdrTexture: hdr,
		pointSampler: { nearest: true, wrap: Wrap.Clamp },
		toneMapParams: { toneMap: vec4f(exposure, mode, 0.0, 0.0) },
	});
}

test "tone map keeps a transparent texel transparent and premultiplies its result again" {
	assert toneMapOf(filled(1, 1, vec4f(0.3, 0.2, 0.1, 0.0)), 1.0, 0.0, 0.5) == vec4f(0.0);
	assert near(toneMapOf(filled(1, 1, vec4f(0.5, 0.5, 0.5, 0.5)), 1.0, 0.0, 0.5), vec4f(0.5));
	const reinhard = toneMapOf(filled(1, 1, vec4f(1.0, 1.0, 1.0, 1.0)), 1.0, 1.0, 0.5);
	assert near(reinhard.x, 0.735356) && reinhard.w == 1.0;
}

test "tone map saturates an additive alpha at 1 and clamps a pixel past the target" {
	const c = toneMapOf(filled(2, 1, vec4f(2.0, 2.0, 2.0, 2.0)), 1.0, 0.0, 9.5);
	assert near(c, vec4f(1.0));
}

function bloomOf(source: Texture2d, threshold: Vec4f, blend: float32): BloomBindings {
	return {
		bloomSource: source,
		bloomSampler: { nearest: false, wrap: Wrap.Clamp },
		bloomParams: {
			bloomTexel: vec4f(0.25, 0.25, 0.25, 0.25),
			bloomBlend: vec4f(blend, 0.0, 0.0, 0.0),
			bloomThreshold: threshold,
		},
	};
}

test "bloom's 13 taps and 3x3 tent keep a flat colour's energy" {
	const flat = filled(4, 4, vec4f(0.6, 0.3, 0.1, 1.0));
	const down = bloomDownsampleFs(at(1.5, 1.5), bloomOf(flat, vec4f(0.0), 0.0));
	assert near(down, vec4f(0.6, 0.3, 0.1, 1.0));
	const up = bloomUpsampleFs(at(1.5, 1.5), bloomOf(flat, vec4f(0.0), 0.5));
	assert near(up, vec4f(0.3, 0.15, 0.05, 0.5));
}

test "bloom's first downsample averages fireflies per group, then thresholds" {
	const white = filled(4, 4, vec4f(1.0, 1.0, 1.0, 1.0));
	const karis = bloomDownsampleFirstFs(at(1.5, 1.5), bloomOf(white, vec4f(0.0), 0.0));
	const expected = (4.0 * 0.125 / (1.0 + 0.125 / 4.0) + 0.5 / (1.0 + 0.5 / 4.0)) as float32;
	assert near(karis, vec4f(expected, expected, expected, 1.0));
	const thresholded = bloomOf(white, vec4f(10.0, 9.0, 0.0, 0.0), 0.0);
	const above = bloomDownsampleFirstFs(at(1.5, 1.5), thresholded);
	assert near(above, vec4f(0.0, 0.0, 0.0, 1.0));
}

function leftSurfaceOf(width: float32): OutlineMaskBindings {
	let normal = filled(4, 1, vec4f(0.5, 0.5, 1.0, 1.0));
	for (let i = 8; i < 16; i++) { normal.texels[i] = 0.0; }
	return {
		outlineNormal: normal,
		outlineDepth: filled(4, 1, vec4f(0.5, 0.0, 0.0, 1.0)),
		outlinePointSampler: { nearest: true, wrap: Wrap.Clamp },
		outlineDepthSampler: { nearest: true, wrap: Wrap.Clamp },
		outlineMaskParams: {
			outlineEdge: vec4f(width, 0.01, 0.9, 1.0),
			outlineDepthMap: vec4f(0.0),
		},
	};
}

test "the outline mask covers a surface pixel whose neighbour is empty, and no other" {
	assert outlineMaskFs(at(1.5, 0.5), leftSurfaceOf(1.0)) == vec4f(1.0);
	assert outlineMaskFs(at(0.5, 0.5), leftSurfaceOf(1.0)) == vec4f(0.0);
	assert outlineMaskFs(at(2.5, 0.5), leftSurfaceOf(1.0)) == vec4f(0.0);
	assert outlineMaskFs(at(0.5, 0.5), leftSurfaceOf(2.0)) == vec4f(1.0);
}

function mixOf(blend: float32): Vec4f {
	return outlineMixFs(at(0.5, 0.5), {
		outlineLit: filled(2, 2, vec4f(0.2, 0.4, 0.6, 1.0)),
		outlineMask: filled(2, 2, vec4f(1.0, 1.0, 1.0, 1.0)),
		outlineLitSampler: { nearest: true, wrap: Wrap.Clamp },
		outlineLinearSampler: { nearest: false, wrap: Wrap.Clamp },
		outlineMixParams: {
			outlineColor: vec4f(1.0, 0.0, 0.0, 1.0),
			outlineMix: vec4f(blend, 0.0, 0.0, 0.0),
		},
	});
}

function facesMeetingAt4Of(width: float32): OutlineMaskBindings {
	let normal = filled(8, 1, vec4f(0.5, 0.5, 1.0, 1.0));
	for (let i = 4; i < 8; i++) {
		normal.texels[i * 4] = 1.0;
		normal.texels[i * 4 + 2] = 0.5;
	}
	let b = leftSurfaceOf(width);
	b.outlineNormal = normal;
	b.outlineDepth = filled(8, 1, vec4f(0.5, 0.0, 0.0, 1.0));
	return b;
}

test "the outline's crease reach rounds a tie to even, as WGSL's round does" {
	assert outlineMaskFs(at(1.5, 0.5), facesMeetingAt4Of(5.0)) == vec4f(0.0);
	assert outlineMaskFs(at(1.5, 0.5), facesMeetingAt4Of(6.0)) == vec4f(1.0);
	assert outlineMaskFs(at(2.5, 0.5), facesMeetingAt4Of(5.0)) == vec4f(1.0);
}

test "the outline mix blends the outline colour over the lit target by the mask" {
	assert near(mixOf(0.0), vec4f(0.2, 0.4, 0.6, 1.0));
	assert near(mixOf(1.0), vec4f(1.0, 0.0, 0.0, 1.0));
	assert near(mixOf(0.5), vec4f(0.6, 0.2, 0.3, 1.0));
}

function widthOf(invert: float32): Vec4f {
	return outlineWidthFs(at(1.5, 1.5), {
		outlineWidthMask: filled(4, 4, vec4f(0.25, 0.25, 0.25, 0.25)),
		outlineWidthSampler: { nearest: false, wrap: Wrap.Clamp },
		outlineWidthParams: { outlineWidth: vec4f(1.0, invert, 0.0, 0.0) },
	});
}

test "the outline width grows the covered side, or the uncovered one when inverted" {
	assert near(widthOf(0.0), vec4f(0.25));
	assert near(widthOf(1.0), vec4f(0.25));
}

function nearVec2(actual: Vec2f, x: float32, y: float32): boolean {
	return approx(actual.x, x) && approx(actual.y, y);
}

test "an SAO tap obscures by its offset along the normal, nothing past the radius or behind" {
	const up = vec3f(0.0, 0.0, 1.0);
	assert approx(saoTap(vec3f(0.0, 0.0, 0.5), up, 1.0, 0.01), 0.795072);
	assert approx(saoTap(vec3f(0.3, 0.0, 0.4), up, 1.0, 0.01), 0.632813);
	assert approx(saoTap(vec3f(0.0, 0.0, 0.5), up, 2.0, 0.01), 1.521184);
	assert saoTap(vec3f(0.0, 0.0, 2.0), up, 1.0, 0.01) == 0.0;
	assert saoTap(vec3f(0.0, 0.0, -0.5), up, 1.0, 0.01) == 0.0;
	assert saoTap(vec3f(0.5, 0.0, 0.0), up, 1.0, 0.01) == 0.0;
}

test "SAO taps walk a spiral outward, turned by the noise rotation" {
	assert nearVec2(saoTapOffset(0, 20, 7, 0.0), 0.011362, 0.022269);
	assert nearVec2(saoTapOffset(19, 20, 7, 1.0), 0.967836, -0.117975);
}

test "the SAO radius, occlusion and fades follow ScalableAO's" {
	assert approx(saoScreenRadius(1.0, 0.866025, 2.0), 0.433013);
	assert approx(saoScalableRadius(1.0, 1.718282), 2.0);
	assert approx(saoScalableRadius(0.5, 3.0), 1.193147);
	assert saoScalableRadius(1.0, 0.0) == 1.0;
	assert saoOcclusion(0.0, 20, 1.0) == 1.0;
	assert approx(saoOcclusion(10.0, 20, 1.0), 0.25);
	assert approx(saoOcclusion(5.0, 20, 0.5), 0.649519);
	assert saoOcclusion(30.0, 20, 1.0) == 0.0;
	assert saoFaded(0.25, 0.5, 1.0, 2.0, 10.0, 20.0) == 1.0;
	assert approx(saoFaded(0.25, 1.5, 1.0, 2.0, 10.0, 20.0), 0.625);
	assert saoFaded(0.25, 5.0, 1.0, 2.0, 10.0, 20.0) == 0.25;
	assert approx(saoFaded(0.25, 15.0, 1.0, 2.0, 10.0, 20.0), 0.625);
	assert saoFaded(0.25, 25.0, 1.0, 2.0, 10.0, 20.0) == 1.0;
}
