// void3d's fullscreen passes written as MetaScript shader functions: tone map, bloom and outline.
// tools/genShaders.ms writes their GLSL into shader3dGen.glsl; src/test/post3dCheck.ms runs them on
// the CPU.

import {
	Sampler,
	Texture2d,
	Vec2f,
	Vec2i,
	Vec3f,
	Vec4f,
	abs,
	binding,
	builtin,
	clamp,
	cos,
	dot,
	max,
	min,
	mix,
	normalize,
	round,
	sampleType,
	samplerType,
	sin,
	textureDimensions,
	textureLoad,
	textureSample,
	vec2f,
	vec2i,
	vec3f,
	vec4f,
} from "../shader/std";
import { linearToSrgb, toneCurved } from "./shader3d";

export struct FullscreenAttributes {
	position: Vec2f;
}

export struct FullscreenVaryings {
	@builtin(position) clip: Vec4f;
}

export function fullscreenVs(input: FullscreenAttributes): FullscreenVaryings {
	return { clip: vec4f(input.position, 0.5, 1.0) };
}

export struct PostInput {
	@builtin(position) position: Vec4f;
}

export struct ToneMapParams {
	toneMap: Vec4f;
}

export struct ToneMapBindings {
	@binding(0) hdrTexture: Texture2d;
	@binding(0) pointSampler: Sampler;
	@binding(0) toneMapParams: ToneMapParams;
}

// h3d.shader.pbr.ToneMapping over the HDR target: the linear colour times the exposure multiplier
// (toneMap.x), through the curve toneMap.y names, then encoded as the LDR target stores it. The
// target holds colour premultiplied by its alpha (a blend over a transparent clear), so the curve
// and the encode run on the straight colour and the result is premultiplied again, as the LDR
// presets store it; the alpha passes through for a caller compositing the target. An Rgba8 target
// saturates alpha at 1 (an additive layer adds to it); the HDR one does not, hence the clamp.
export function toneMapFs(input: PostInput, b: ToneMapBindings): Vec4f {
	const size = textureDimensions(b.hdrTexture, b.pointSampler, 0);
	const p = clamp(vec2i(input.position.xy), vec2i(0, 0), size - vec2i(1, 1));
	const texel = textureLoad(b.hdrTexture, b.pointSampler, p, 0);
	const alpha = clamp(texel.w, 0.0, 1.0);
	if (alpha <= 0.0) {
		return vec4f(0.0);
	}
	const straight = texel.xyz / alpha;
	const tone = b.toneMapParams.toneMap;
	return vec4f(linearToSrgb(toneCurved(straight * tone.x, tone.y)) * alpha, alpha);
}

// Bevy 157e1ce6 bevy_post_process bloom.wesl BloomUniforms, for a fullscreen pass of one mip:
// bloomTexel.xy one texel of the source, .zw one texel of the target; bloomBlend.x the upsample's
// blend factor (mod.rs compute_blend_factor); bloomThreshold the soft threshold's precomputations
// (settings.rs), x above 0 when the prefilter is on.
export struct BloomParams {
	bloomTexel: Vec4f;
	bloomBlend: Vec4f;
	bloomThreshold: Vec4f;
}

export struct BloomBindings {
	@binding(0) bloomSource: Texture2d;
	@binding(0) bloomSampler: Sampler;
	@binding(0) bloomParams: BloomParams;
}

function bloomTap(b: BloomBindings, uv: Vec2f, offset: Vec2f): Vec3f {
	const at = uv + offset * b.bloomParams.bloomTexel.xy;
	return textureSample(b.bloomSource, b.bloomSampler, at).xyz;
}

// bloom.wesl karis_average, Rec. 709 luminance.
function bloomKaris(color: Vec3f): float32 {
	const luma = dot(color, vec3f(0.2126, 0.7152, 0.0722)) / 4.0;
	return 1.0 / (1.0 + luma);
}

// bloom.wesl sample_input_13_tap ([COD] slide 153), the uniform-scale offsets; with karis, [COD]
// slide 168's firefly reduction, per group, in linear light.
function bloom13(b: BloomBindings, uv: Vec2f, karis: boolean): Vec3f {
	const a = bloomTap(b, uv, vec2f(-2.0, 2.0));
	const bb = bloomTap(b, uv, vec2f(0.0, 2.0));
	const c = bloomTap(b, uv, vec2f(2.0, 2.0));
	const d = bloomTap(b, uv, vec2f(-2.0, 0.0));
	const e = bloomTap(b, uv, vec2f(0.0, 0.0));
	const f = bloomTap(b, uv, vec2f(2.0, 0.0));
	const g = bloomTap(b, uv, vec2f(-2.0, -2.0));
	const h = bloomTap(b, uv, vec2f(0.0, -2.0));
	const i = bloomTap(b, uv, vec2f(2.0, -2.0));
	const j = bloomTap(b, uv, vec2f(-1.0, 1.0));
	const k = bloomTap(b, uv, vec2f(1.0, 1.0));
	const l = bloomTap(b, uv, vec2f(-1.0, -1.0));
	const m = bloomTap(b, uv, vec2f(1.0, -1.0));
	if (karis) {
		let group0 = (a + bb + d + e) * (0.125 / 4.0);
		let group1 = (bb + c + e + f) * (0.125 / 4.0);
		let group2 = (d + e + g + h) * (0.125 / 4.0);
		let group3 = (e + f + h + i) * (0.125 / 4.0);
		let group4 = (j + k + l + m) * (0.5 / 4.0);
		group0 = group0 * bloomKaris(group0);
		group1 = group1 * bloomKaris(group1);
		group2 = group2 * bloomKaris(group2);
		group3 = group3 * bloomKaris(group3);
		group4 = group4 * bloomKaris(group4);
		return group0 + group1 + group2 + group3 + group4;
	}
	let sum = (a + c + g + i) * 0.03125;
	sum = sum + (bb + d + f + h) * 0.0625;
	sum = sum + (e + j + k + l + m) * 0.125;
	return sum;
}

function softThreshold(b: BloomBindings, color: Vec3f): Vec3f {
	const threshold = b.bloomParams.bloomThreshold;
	const brightness = max(color.x, max(color.y, color.z));
	let softness = clamp(brightness - threshold.y, 0.0, threshold.z);
	softness = softness * softness * threshold.w;
	const contribution = max(brightness - threshold.x, softness);
	return color * (contribution / max(brightness, 0.00001));
}

// bloom.wesl downsample_first: the HDR target into mip 0, fireflies averaged out, floored at
// 0.0001 so a black region does not stay black through the chain, then the soft threshold.
export function bloomDownsampleFirstFs(input: PostInput, b: BloomBindings): Vec4f {
	const uv = input.position.xy * b.bloomParams.bloomTexel.zw;
	let sum = clamp(bloom13(b, uv, true), vec3f(0.0001), vec3f(3.40282347e37));
	if (b.bloomParams.bloomThreshold.x > 0.0) {
		sum = softThreshold(b, sum);
	}
	return vec4f(sum, 1.0);
}

// bloom.wesl downsample: mip i-1 into mip i.
export function bloomDownsampleFs(input: PostInput, b: BloomBindings): Vec4f {
	return vec4f(bloom13(b, input.position.xy * b.bloomParams.bloomTexel.zw, false), 1.0);
}

// bloom.wesl upsample ([COD] slide 162, the 3x3 tent), mip i onto mip i-1 or the HDR target. The
// blend factor rides in alpha in place of Bevy's blend constant (upsampling_pipeline.rs TODO): the
// pipeline blends One / OneMinusSrcAlpha (energy conserving) or One / One (additive) on colour,
// and leaves the target's alpha as it is.
export function bloomUpsampleFs(input: PostInput, b: BloomBindings): Vec4f {
	const uv = input.position.xy * b.bloomParams.bloomTexel.zw;
	let sum = bloomTap(b, uv, vec2f(0.0, 0.0)) * 0.25;
	sum = sum + (bloomTap(b, uv, vec2f(0.0, 1.0)) + bloomTap(b, uv, vec2f(-1.0, 0.0)) +
		bloomTap(b, uv, vec2f(1.0, 0.0)) + bloomTap(b, uv, vec2f(0.0, -1.0))) * 0.125;
	sum = sum + (bloomTap(b, uv, vec2f(-1.0, 1.0)) + bloomTap(b, uv, vec2f(1.0, 1.0)) +
		bloomTap(b, uv, vec2f(-1.0, -1.0)) + bloomTap(b, uv, vec2f(1.0, -1.0))) * 0.0625;
	const factor = b.bloomParams.bloomBlend.x;
	return vec4f(sum * factor, factor);
}

// outlineEdge: width, clip-depth threshold, normal dot threshold, stored-depth scale;
// outlineDepthMap.x: stored-depth bias.
export struct OutlineMaskParams {
	outlineEdge: Vec4f;
	outlineDepthMap: Vec4f;
}

export struct OutlineMaskBindings {
	@binding(0) outlineNormal: Texture2d;
	@binding(1) @sampleType(unfilterable_float) outlineDepth: Texture2d;
	@binding(0) outlinePointSampler: Sampler;
	@binding(1) @samplerType(nonfiltering) outlineDepthSampler: Sampler;
	@binding(0) outlineMaskParams: OutlineMaskParams;
}

const OUTLINE_OFFSETS: Vec2i[4] = [vec2i(1, 0), vec2i(-1, 0), vec2i(0, 1), vec2i(0, -1)];

function outlinePixel(p: Vec2i, size: Vec2i): Vec2i {
	return clamp(p, vec2i(0, 0), size - vec2i(1, 1));
}

function outlineDepthAt(b: OutlineMaskBindings, p: Vec2i, size: Vec2i): float32 {
	return textureLoad(b.outlineDepth, b.outlineDepthSampler, outlinePixel(p, size), 0).x *
		b.outlineMaskParams.outlineEdge.w + b.outlineMaskParams.outlineDepthMap.x;
}

function outlineNormalAt(b: OutlineMaskBindings, p: Vec2i): Vec4f {
	return textureLoad(b.outlineNormal, b.outlinePointSampler, p, 0);
}

// Visible opaque normal/depth only, so no discarded face can expose a second depth layer. A
// silhouette is inside the nearest surface; a crease straddles two visible normals.
export function outlineMaskFs(input: PostInput, b: OutlineMaskBindings): Vec4f {
	const edge = b.outlineMaskParams.outlineEdge;
	const size = textureDimensions(b.outlineNormal, b.outlinePointSampler, 0);
	const p = vec2i(input.position.xy);
	const center = outlineNormalAt(b, p);
	let coverage: float32 = 0.0;
	const n = center.w > 0.5 ? normalize(center.xyz * 2.0 - 1.0) : vec3f(0.0);
	const depth = outlineDepthAt(b, p, size);
	for (let i = 0; i < 4; i++) {
		const silhouette = p + vec2i(round(vec2f(OUTLINE_OFFSETS[i]) * edge.x));
		const silhouetteDelta = outlineDepthAt(b, silhouette, size) - depth;
		const silhouetteNormal = outlineNormalAt(b, outlinePixel(silhouette, size));
		const crease = p + vec2i(round(vec2f(OUTLINE_OFFSETS[i]) * max(1.0, edge.x * 0.5)));
		const neighbor = outlineNormalAt(b, outlinePixel(crease, size));
		const creaseDelta = outlineDepthAt(b, crease, size) - depth;
		const nq = neighbor.w > 0.5 ? normalize(neighbor.xyz * 2.0 - 1.0) : vec3f(0.0);
		const distinctNormal = center.x != neighbor.x || center.y != neighbor.y ||
			center.z != neighbor.z;
		if (center.w > 0.5 && (silhouetteNormal.w < 0.5 || silhouetteDelta > edge.y ||
			neighbor.w > 0.5 && abs(creaseDelta) < edge.y && distinctNormal &&
				dot(n, nq) < edge.z)) {
			coverage = 1.0;
		}
	}
	return vec4f(coverage);
}

// outlineColor premultiplied RGBA; outlineMix.x the blend.
export struct OutlineMixParams {
	outlineColor: Vec4f;
	outlineMix: Vec4f;
}

export struct OutlineMixBindings {
	@binding(0) outlineLit: Texture2d;
	@binding(1) outlineMask: Texture2d;
	@binding(0) outlineLitSampler: Sampler;
	@binding(1) outlineLinearSampler: Sampler;
	@binding(0) outlineMixParams: OutlineMixParams;
}

function maskTap(b: OutlineMixBindings, uv: Vec2f): Vec3f {
	return textureSample(b.outlineMask, b.outlineLinearSampler, uv).xyz;
}

// Heaps pass/FXAA.hx's direction, taps and range selection, unchanged, on grayscale coverage.
export function outlineMixFs(input: PostInput, b: OutlineMixBindings): Vec4f {
	const size = textureDimensions(b.outlineMask, b.outlineLinearSampler, 0);
	const delta = 1.0 / vec2f(size);
	const tuv = input.position.xy * delta;
	const nw = maskTap(b, tuv + vec2f(-1.0, -1.0) * delta);
	const ne = maskTap(b, tuv + vec2f(1.0, -1.0) * delta);
	const sw = maskTap(b, tuv + vec2f(-1.0, 1.0) * delta);
	const se = maskTap(b, tuv + vec2f(1.0, 1.0) * delta);
	const mid = maskTap(b, tuv);
	const lumA = vec3f(0.299, 0.587, 0.114);
	const lumNW = dot(nw, lumA);
	const lumNE = dot(ne, lumA);
	const lumSW = dot(sw, lumA);
	const lumSE = dot(se, lumA);
	const lumMid = dot(mid, lumA);
	const lumMin = min(lumMid, min(min(lumNW, lumNE), min(lumSW, lumSE)));
	const lumMax = max(lumMid, max(max(lumNW, lumNE), max(lumSW, lumSE)));
	let dir = vec2f(-(lumNW + lumNE - (lumSW + lumSE)), lumNW + lumSW - (lumNE + lumSE));
	const dirReduce = max((lumNW + lumNE + lumSW + lumSE) * (0.25 / 128.0), 1.0 / 8.0);
	const rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
	dir = min(vec2f(8.0), max(vec2f(-8.0), dir * rcpDirMin)) * delta;
	const rgbA = (maskTap(b, tuv + dir * (1.0 / 3.0 - 0.5)) +
		maskTap(b, tuv + dir * (2.0 / 3.0 - 0.5))) * 0.5;
	const rgbB = rgbA * 0.5 + (maskTap(b, tuv + dir * -0.5) + maskTap(b, tuv + dir * 0.5)) * 0.25;
	const lumB = dot(rgbB, lumA);
	const inRange: float32 = lumB > lumMin && -lumB > -lumMax ? 1.0 : 0.0;
	const filtered = mix(rgbA, rgbB, inRange);
	const lit = textureLoad(b.outlineLit, b.outlineLitSampler, vec2i(input.position.xy), 0);
	return mix(lit, b.outlineMixParams.outlineColor * filtered.x, b.outlineMixParams.outlineMix.x);
}

// outlineWidth.x the radius in pixels, .y above 0.5 to grow the uncovered side instead.
export struct OutlineWidthParams {
	outlineWidth: Vec4f;
}

export struct OutlineWidthBindings {
	@binding(0) outlineWidthMask: Texture2d;
	@binding(0) outlineWidthSampler: Sampler;
	@binding(0) outlineWidthParams: OutlineWidthParams;
}

export function outlineWidthFs(input: PostInput, b: OutlineWidthBindings): Vec4f {
	const width = b.outlineWidthParams.outlineWidth;
	const delta = 1.0 / vec2f(textureDimensions(b.outlineWidthMask, b.outlineWidthSampler, 0));
	const uv = input.position.xy * delta;
	const own = textureSample(b.outlineWidthMask, b.outlineWidthSampler, uv).x;
	let maximum = width.y > 0.5 ? 1.0 - own : own;
	let angle: float32 = 0.0;
	for (let i = 0; i < 48; i++) {
		angle += 6.283185307179586 / 48.0;
		const displacement = vec2f(cos(angle), sin(angle)) * width.x * delta;
		const current =
			textureSample(b.outlineWidthMask, b.outlineWidthSampler, uv + displacement).x;
		maximum = max(maximum, width.y > 0.5 ? 1.0 - current : current);
	}
	const coverage = width.y > 0.5 ? 1.0 - maximum : maximum;
	return vec4f(coverage);
}
