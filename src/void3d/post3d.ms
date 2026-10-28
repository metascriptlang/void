// void3d's fullscreen passes written as MetaScript shader functions: tone map, bloom, outline and
// ambient occlusion.
// tools/genShaders.ms writes their GLSL into shader3dGen.glsl; src/test/post3dCheck.ms runs them on
// the CPU.

import {
	Mat4x4f,
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
	distance,
	dot,
	dpdx,
	dpdy,
	log,
	max,
	min,
	mix,
	normalize,
	pow,
	round,
	sampleType,
	samplerType,
	saturate,
	sin,
	textureDimensions,
	textureLoad,
	textureSample,
	vec2f,
	vec2i,
	vec3f,
	vec4f,
} from "../shader/std";
import { linearToSrgb, ndcDepthOf, toneCurved } from "./shader3d";

// ScalableAO's shader (h3d/shader/SAO.hx, McGuire's Scalable Ambient Obscurance): one tap's
// obscurance, from the tapped point's offset to the shaded point, against the shaded normal.
export function saoTap(offset: Vec3f, normal: Vec3f, radius: float32, bias: float32): float32 {
	const vv = dot(offset, offset);
	const vn = dot(offset, normal) - bias * radius;
	const radius2 = radius * radius;
	const f = max(radius2 - vv, 0.0) / radius2;
	return f * f * f * max(vn / (0.01 + vv), 0.0);
}

// SAO.sampleAO: where tap `tap` of `samples` lands on a spiral of `spiralTurns` turns turned by
// `rotation`, as a fraction of the screen radius. 6.28 is SAO's turn, kept so the taps match.
export function saoTapOffset(
	tap: int32, samples: int32, spiralTurns: int32, rotation: float32,
): Vec2f {
	const alpha = ((tap as float32) + 0.5) / (samples as float32);
	const angle = alpha * ((spiralTurns as float32) * 6.28) + rotation;
	return vec2f(cos(angle), sin(angle)) * alpha;
}

// SAO.fragment: the world radius as a fraction of the screen height at `viewDepth`, where
// `fovTan` is 1 / (2 tan(fovY / 2)).
export function saoScreenRadius(
	sampleRadius: float32, fovTan: float32, viewDepth: float32,
): float32 {
	return sampleRadius * fovTan / viewDepth;
}

// SAO's USE_SCALABLE_BIAS: the tap radius grows with the log of the tapped point's view depth.
export function saoScalableRadius(sampleRadius: float32, viewDepth: float32): float32 {
	return sampleRadius * (max(0.0, log(1.0 + viewDepth)) + 1.0);
}

// SAO.fragment: the taps' mean obscurance as the light left, sharpened by `intensity`. SAO raises
// 1 - mean before it saturates, which a mean past 1 leaves undefined; the base is clamped first.
export function saoOcclusion(sum: float32, samples: int32, intensity: float32): float32 {
	return pow(saturate(1.0 - sum / (samples as float32)), 1.0 + intensity);
}

// SAO's USE_START_FADE and USE_FADE: no occlusion nearer than `startFadeStart` or past
// `fadeEnd`, eased in over the start range and out over the end range.
export function saoFaded(
	occlusion: float32, distance: float32, startFadeStart: float32, startFadeEnd: float32,
	fadeStart: float32, fadeEnd: float32,
): float32 {
	const started = mix(1.0, occlusion,
		saturate((distance - startFadeStart) / (startFadeEnd - startFadeStart)));
	return mix(started, 1.0, saturate((distance - fadeStart) / (fadeEnd - fadeStart)));
}

// gpu3d.ms SAO_* offsets: the inverse viewProj; the camera row whose dot with a world point is
// its view depth; sampleRadius, intensity, bias and fovTan (1 / ortho height when ORTHO);
// numSamples, numSpiralTurns, ORTHO and USE_SCALABLE_BIAS; noiseScale and the door's
// depthZeroToOne; the camera position; startFadeStart, startFadeEnd, fadeStart and fadeEnd.
export struct SaoParams {
	saoInverseViewProj: Mat4x4f;
	saoViewDepth: Vec4f;
	saoRadius: Vec4f;
	saoTaps: Vec4f;
	saoNoise: Vec4f;
	saoEye: Vec4f;
	saoFade: Vec4f;
}

export struct SaoBindings {
	@binding(0) @sampleType(unfilterable_float) saoDepth: Texture2d;
	@binding(1) saoNormal: Texture2d;
	@binding(2) saoNoiseTexture: Texture2d;
	@binding(0) @samplerType(nonfiltering) saoPointSampler: Sampler;
	@binding(1) saoNoiseSampler: Sampler;
	@binding(0) saoParams: SaoParams;
}

// SAO.getPosition on the stored depth under `pixel`, whose NDC is `ndc`.
function saoPositionAt(b: SaoBindings, pixel: Vec2i, ndc: Vec2f): Vec3f {
	const stored = textureLoad(b.saoDepth, b.saoPointSampler, pixel, 0).x;
	const depth = ndcDepthOf(stored, b.saoParams.saoNoise.z);
	const world = b.saoParams.saoInverseViewProj * vec4f(ndc.x, ndc.y, depth, 1.0);
	return world.xyz / world.w;
}

function saoViewDepthOf(b: SaoBindings, at: Vec3f): float32 {
	return dot(b.saoParams.saoViewDepth, vec4f(at, 1.0));
}

// SAO.fragment over the normal target the forward outline MRT writes as n * 0.5 + 0.5. A tap
// reads the depth at the nearest pixel, as the depth is unfilterable here, and finds its NDC
// along dpdx and dpdy, which run the way the pixel rows do on every backend.
export function saoFs(input: SaoInput, b: SaoBindings): Vec4f {
	const size = textureDimensions(b.saoDepth, b.saoPointSampler, 0);
	const pixel = vec2i(input.position.xy);
	const ndc = input.ndc.xy;
	const ndcDx = dpdx(ndc);
	const ndcDy = dpdy(ndc);
	const origin = saoPositionAt(b, pixel, ndc);
	const normal = textureLoad(b.saoNormal, b.saoPointSampler, pixel, 0).xyz * 2.0 - vec3f(1.0);
	const height = size.y as float32;
	const noiseUv = input.position.xy / height * b.saoParams.saoNoise.xy;
	const noise = textureSample(b.saoNoiseTexture, b.saoNoiseSampler, noiseUv).x;
	const rotation = 2.0 * 3.14159265358979 * noise;
	const radius = b.saoParams.saoRadius;
	const taps = b.saoParams.saoTaps;
	const radiusSS = taps.z == 1.0 ? radius.x * radius.w :
		saoScreenRadius(radius.x, radius.w, saoViewDepthOf(b, origin));
	const samples = taps.x as int32;
	const turns = taps.y as int32;
	let sum: float32 = 0.0;
	for (let tap = 0; tap < samples; tap++) {
		const offset = round(saoTapOffset(tap, samples, turns, rotation) * (radiusSS * height));
		const at = clamp(pixel + vec2i(offset), vec2i(0, 0), size - vec2i(1, 1));
		const q = saoPositionAt(b, at, ndc + ndcDx * offset.x + ndcDy * offset.y);
		const tapRadius = taps.w == 1.0 ? saoScalableRadius(radius.x, saoViewDepthOf(b, q)) :
			radius.x;
		sum = sum + saoTap(q - origin, normal, tapRadius, radius.z);
	}
	const fade = b.saoParams.saoFade;
	const occlusion = saoFaded(saoOcclusion(sum, samples, radius.y),
		distance(origin, b.saoParams.saoEye.xyz), fade.x, fade.y, fade.z, fade.w);
	return vec4f(occlusion, occlusion, occlusion, 1.0);
}

// blur.ms BLUR_*: the step between taps in UV with the weight count; per tap, its weight and its
// offset in steps per tap index.
export struct BlurParams {
	blurPixel: Vec4f;
	blurTaps: Vec4f[16];
}

export struct BlurBindings {
	@binding(0) blurSource: Texture2d;
	@binding(0) blurSampler: Sampler;
	@binding(0) blurParams: BlurParams;
}

// h3d.shader.Blur's plain branch: one direction of the separable blur over a source the target's
// size, each tap weighted and placed by Blur.calcValues.
export function blurFs(input: PostInput, b: BlurBindings): Vec4f {
	const size = textureDimensions(b.blurSource, b.blurSampler, 0);
	const uv = input.position.xy / vec2f(size.x as float32, size.y as float32);
	const count = b.blurParams.blurPixel.z as int32;
	let color = vec4f(0.0, 0.0, 0.0, 0.0);
	for (let i = 1 - count; i < count; i++) {
		const tap = b.blurParams.blurTaps[i < 0 ? -i : i];
		const at = uv + b.blurParams.blurPixel.xy * (tap.y * (i as float32));
		color = color + textureSample(b.blurSource, b.blurSampler, at) * tap.x;
	}
	return color;
}

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

// The fullscreen triangle's NDC as a varying, for a pass that rebuilds positions off the screen.
export struct SaoVaryings {
	ndc: Vec4f;
	@builtin(position) clip: Vec4f;
}

export struct SaoInput {
	ndc: Vec4f;
	@builtin(position) position: Vec4f;
}

export function saoVs(input: FullscreenAttributes): SaoVaryings {
	return { ndc: vec4f(input.position, 0.0, 0.0), clip: vec4f(input.position, 0.5, 1.0) };
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

export const OUTLINE_OFFSETS: Vec2i[4] = [vec2i(1, 0), vec2i(-1, 0), vec2i(0, 1), vec2i(0, -1)];

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
