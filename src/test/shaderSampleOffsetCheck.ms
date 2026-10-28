// The constant texel offset of textureSample, textureSampleLevel, textureSampleBias,
// textureSampleGrad, textureSampleCompare and textureSampleCompareLevel, WGSL's last argument:
// each entry runs on the CPU, is pinned as GLSL and printed for every target into
// out/<target>Probe/
// for scripts/validateWgsl.sh, scripts/validateHlsl.sh and spirv-val.

import { mkdir, writeFile } from "std/fs";
import { Compare, Wrap } from "../gpu/state";
import { programModule, stageSource, stageWords } from "../shader/descriptor";
import { glsl, glslIr } from "../shader/emit";
import {
	ExprKind,
	Intrinsic,
	ScalarKind,
	ShaderModule,
	TextureShape,
	irErrors,
	literal,
	scalarType,
	vectorType,
} from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import { opcodeOf, spirvProbe } from "./shaderProbeModules";
import {
	Sampler,
	SamplerComparison,
	Texture2d,
	Texture2dArray,
	Texture3d,
	TextureDepth2d,
	TextureDepth2dArray,
	Vec2f,
	Vec4f,
	binding,
	builtin,
	samplerType,
	textureSample,
	textureSampleBias,
	textureSampleCompare,
	textureSampleCompareLevel,
	textureSampleGrad,
	textureSampleLevel,
	vec2f,
	vec2i,
	vec3f,
	vec3i,
	vec4f,
} from "../shader/std";

export struct Pixel {
	@builtin(position) position: Vec4f;
}

export struct Corner {
	position: Vec2f;
}

export struct Placed {
	@builtin(position) clip: Vec4f;
}

export struct Surfaces {
	@binding(0) color: Texture2d;
	@binding(1) layers: Texture2dArray;
	@binding(2) volume: Texture3d;
	@binding(3) shadow: TextureDepth2d;
	@binding(4) shadowLayers: TextureDepth2dArray;
	@binding(0) linear: Sampler;
	@binding(1) @samplerType(nonfiltering) raw: Sampler;
	@binding(2) shadowSampler: SamplerComparison;
}

export struct Terrain {
	@binding(5) height: Texture2d;
	@binding(3) heightSampler: Sampler;
}

const NUDGE = vec2i(-1, 2);

export function liftedVs(input: Corner, b: Terrain): Placed {
	const height = textureSampleLevel(b.height, b.heightSampler, input.position, 0.0, vec2i(2, 3));
	return { clip: vec4f(input.position.x, input.position.y, height.x, 1.0) };
}

export function offsetFs(input: Pixel, b: Surfaces): Vec4f {
	const uv = vec2f(0.25, 0.75);
	const plain = textureSample(b.color, b.linear, uv, vec2i(1, 0));
	const nudged = textureSample(b.color, b.linear, uv, NUDGE);
	const layered = textureSample(b.layers, b.linear, uv, 1, vec2i(0, 2));
	const volume = textureSample(b.volume, b.linear, vec3f(uv.x, uv.y, 0.5), vec3i(1, 0, -1));
	const leveled = textureSampleLevel(b.color, b.linear, uv, 2.0, vec2i(-8, 7));
	const biased = textureSampleBias(b.color, b.linear, uv, 0.5, vec2i(2, 2));
	const graded = textureSampleGrad(b.layers, b.linear, uv, 1, vec2f(0.01, 0.0),
		vec2f(0.0, 0.01), vec2i(1, 1));
	const compared = textureSampleCompare(b.shadow, b.shadowSampler, uv, 0.5, vec2i(1, 0));
	const comparedLayer = textureSampleCompareLevel(b.shadowLayers, b.shadowSampler, uv, 1, 0.5,
		vec2i(0, 1));
	const comparedLevel = textureSampleCompareLevel(b.shadow, b.shadowSampler, uv, 0.5,
		vec2i(3, 3));
	const depth = textureSampleLevel(b.shadow, b.raw, uv, 0, vec2i(1, 1));
	const depthLayer = textureSampleLevel(b.shadowLayers, b.raw, uv, 1, 0, vec2i(1, 1));
	return vec4f(plain.x + nudged.y + layered.z + volume.w,
		leveled.x + biased.y + graded.z,
		compared + comparedLayer + comparedLevel,
		depth + depthLayer);
}

export struct Swatch {
	@binding(0) color: Texture2d;
	@binding(0) linear: Sampler;
}

export function localOffsetFs(input: Pixel, b: Swatch): Vec4f {
	const uv = vec2f(0.25, 0.75);
	const shift = vec2i(1, -1);
	const unit = 1;
	const built = vec2i(unit, -unit);
	const again = shift;
	return textureSample(b.color, b.linear, uv, shift) +
		textureSampleLevel(b.color, b.linear, uv, 0.0, built) +
		textureSampleBias(b.color, b.linear, uv, 0.5, again);
}

export function layeredCompareFs(input: Pixel, b: Surfaces): Vec4f {
	const uv = vec2f(0.25, 0.75);
	return vec4f(textureSampleCompare(b.shadowLayers, b.shadowSampler, uv, 1, 0.5, vec2i(0, 1)),
		0.0, 0.0, 1.0);
}

function ramp(): Texture2d {
	let texels: float32[] = [];
	for (let i = 0; i < 4; i++) {
		texels.push(i as float32);
		texels.push(10.0 + (i as float32));
		texels.push(0.0);
		texels.push(1.0);
	}
	return { width: 4, height: 1, texels };
}

function sampler(nearest: boolean, wrap: Wrap): Sampler {
	return { nearest, wrap };
}

test "an offset shifts the texel read, before the filter and the wrap act" {
	const at = vec2f(0.125, 0.5);
	const clamp = sampler(true, Wrap.Clamp);
	assert textureSample(ramp(), clamp, at).x == 0.0;
	assert textureSample(ramp(), clamp, at, vec2i(1, 0)).x == 1.0;
	assert textureSample(ramp(), clamp, at, vec2i(3, 0)).x == 3.0;
	assert textureSample(ramp(), clamp, at, vec2i(7, 0)).x == 3.0;
	assert textureSample(ramp(), clamp, at, vec2i(-1, 0)).x == 0.0;
	assert textureSample(ramp(), sampler(true, Wrap.Repeat), at, vec2i(-1, 0)).x == 3.0;
	assert textureSample(ramp(), sampler(true, Wrap.Mirror), at, vec2i(-1, 0)).x == 0.0;
	const linear = sampler(false, Wrap.Clamp);
	assert Math.abs(textureSample(ramp(), linear, vec2f(0.375, 0.5)).x - 1.0) < 0.0001;
	assert Math.abs(textureSample(ramp(), linear, vec2f(0.375, 0.5), vec2i(1, 0)).x - 2.0) < 0.0001;
	assert Math.abs(textureSample(ramp(), linear, vec2f(0.5, 0.5), vec2i(1, 0)).x - 2.5) < 0.0001;
	assert textureSampleLevel(ramp(), clamp, at, 0.0, vec2i(2, 0)).x == 2.0;
	assert textureSampleBias(ramp(), clamp, at, 0.0, vec2i(2, 0)).y == 12.0;
	assert textureSampleGrad(ramp(), clamp, at, vec2f(0.0, 0.0), vec2f(0.0, 0.0),
		vec2i(1, 0)).x == 1.0;
}

test "the offset reaches an array layer, a volume slice and a depth texel" {
	const clamp = sampler(true, Wrap.Clamp);
	const layers: Texture2dArray = { width: 2, height: 1, layers: 2,
		texels: [0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 2.0, 0.0, 0.0, 0.0, 3.0, 0.0, 0.0, 0.0] };
	assert textureSample(layers, clamp, vec2f(0.25, 0.5), 1, vec2i(1, 0)).x == 3.0;
	assert textureSampleLevel(layers, clamp, vec2f(0.25, 0.5), 1, 0.0, vec2i(1, 0)).x == 3.0;
	const volume: Texture3d = { width: 1, height: 1, depth: 3,
		texels: [0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 2.0, 0.0, 0.0, 0.0] };
	assert textureSample(volume, clamp, vec3f(0.5, 0.5, 0.1), vec3i(0, 0, 1)).x == 1.0;
	assert textureSample(volume, clamp, vec3f(0.5, 0.5, 0.1), vec3i(0, 0, 7)).x == 2.0;
	const shadow: TextureDepth2d = { width: 2, height: 1, texels: [0.2, 0.8] };
	assert textureSampleLevel(shadow, clamp, vec2f(0.25, 0.5), 0, vec2i(1, 0)) == 0.8;
	const less: SamplerComparison = { nearest: true, wrap: Wrap.Clamp, compare: Compare.Less };
	assert textureSampleCompare(shadow, less, vec2f(0.25, 0.5), 0.5) == 0.0;
	assert textureSampleCompare(shadow, less, vec2f(0.25, 0.5), 0.5, vec2i(1, 0)) == 1.0;
	assert textureSampleCompareLevel(shadow, less, vec2f(0.25, 0.5), 0.5, vec2i(1, 0)) == 1.0;
	const stack: TextureDepth2dArray = { width: 2, height: 1, layers: 2,
		texels: [0.2, 0.8, 0.8, 0.2] };
	assert textureSampleCompare(stack, less, vec2f(0.25, 0.5), 1, 0.5, vec2i(1, 0)) == 0.0;
	assert textureSampleLevel(stack, clamp, vec2f(0.25, 0.5), 1, 0, vec2i(1, 0)) == 0.2;
}

test "a function's const of constants is a const-expression, as WGSL's, and prints as the offset" {
	assert glsl(localOffsetFs) ==
		"layout(binding=0) uniform texture2D color;
" +
		"layout(binding=0) uniform sampler linear;
" +
		"layout(location=0) out vec4 fragColor;
" +
		"void main() {
" +
		"    vec2 uv = vec2(0.25, 0.75);
" +
		"    ivec2 shift = ivec2(1, -1);
" +
		"    int unit = 1;
" +
		"    ivec2 built = ivec2(1, -1);
" +
		"    ivec2 again = shift;
" +
		"    fragColor = (textureOffset(sampler2D(color, linear), uv, ivec2(1, -1)) + " +
		"textureLodOffset(sampler2D(color, linear), uv, 0.0, ivec2(1, -1))) + " +
		"textureOffset(sampler2D(color, linear), uv, ivec2(1, -1), 0.5);
" +
		"    return;
" +
		"}
";
}

function probePath(name: string, target: ShaderTarget, stage: string): string {
	return match (target) {
		ShaderTarget.Wgsl => "out/wgslProbe/" + name + stage + ".wgsl",
		ShaderTarget.Hlsl5 => "out/hlslProbe/" + name + "." + (stage == "Vs" ? "vs" : "ps") +
		".hlsl",
		ShaderTarget.Glsl430 => "out/glslProbe/" + name + ".430." +
		(stage == "Vs" ? "vert" : "frag"),
		ShaderTarget.Glsl300es => "out/glslProbe/" + name + ".es." +
		(stage == "Vs" ? "vert" : "frag"),
		ShaderTarget.Msl => "out/mslProbe/" + name + stage + ".metal",
		ShaderTarget.Spirv => "out/spirvProbe/" + name + stage + ".spv",
	};
}

function printedFor(m: ShaderModule, entry: int32, target: ShaderTarget, name: string): string {
	const text = stageSource(m, entry, target);
	if (!text.ok) { return text.error; }
	const path = probePath(name, target, entry == 0 ? "Vs" : "Fs");
	const _out = mkdir("out");
	const _folder = mkdir(path.slice(0, path.lastIndexOf("/")));
	const _written = writeFile(path, text.value);
	return text.value;
}

function programOf(): ShaderModule {
	const m = programModule(glslIr(liftedVs), glslIr(offsetFs), []);
	if (!m.ok) { throw new Error("programOf: " + m.error); }
	return m.value;
}

test "GLSL 450 spells every offset as the Offset form of the sample" {
	assert glsl(offsetFs) ==
		"layout(binding=0) uniform texture2D color;\n" +
		"layout(binding=1) uniform texture2DArray layers;\n" +
		"layout(binding=2) uniform texture3D volume;\n" +
		"@image_sample_type shadow depth\n" +
		"layout(binding=3) uniform texture2D shadow;\n" +
		"@image_sample_type shadowLayers depth\n" +
		"layout(binding=4) uniform texture2DArray shadowLayers;\n" +
		"layout(binding=0) uniform sampler linear;\n" +
		"@sampler_type raw nonfiltering\n" +
		"layout(binding=1) uniform sampler raw;\n" +
		"@sampler_type shadowSampler comparison\n" +
		"layout(binding=2) uniform sampler shadowSampler;\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"const ivec2 NUDGE = ivec2(-1, 2);\n" +
		"void main() {\n" +
		"    vec2 uv = vec2(0.25, 0.75);\n" +
		"    vec4 plain = textureOffset(sampler2D(color, linear), uv, ivec2(1, 0));\n" +
		"    vec4 nudged = textureOffset(sampler2D(color, linear), uv, ivec2(-1, 2));\n" +
		"    vec4 layered = textureOffset(sampler2DArray(layers, linear), vec3(uv, float(1)), " +
		"ivec2(0, 2));\n" +
		"    vec4 volume_1 = textureOffset(sampler3D(volume, linear), vec3(uv.x, uv.y, 0.5), " +
		"ivec3(1, 0, -1));\n" +
		"    vec4 leveled = textureLodOffset(sampler2D(color, linear), uv, 2.0, ivec2(-8, 7));\n" +
		"    vec4 biased = textureOffset(sampler2D(color, linear), uv, ivec2(2, 2), 0.5);\n" +
		"    vec4 graded = textureGradOffset(sampler2DArray(layers, linear), vec3(uv, float(1)), " +
		"vec2(0.01, 0.0), vec2(0.0, 0.01), ivec2(1, 1));\n" +
		"    float compared = textureOffset(sampler2DShadow(shadow, shadowSampler), vec3(uv, " +
		"0.5), ivec2(1, 0));\n" +
		"    float comparedLayer = textureGradOffset(sampler2DArrayShadow(shadowLayers, " +
		"shadowSampler), vec4(uv, float(1), 0.5), vec2(0.0), vec2(0.0), ivec2(0, 1));\n" +
		"    float comparedLevel = textureLodOffset(sampler2DShadow(shadow, shadowSampler), " +
		"vec3(uv, 0.5), 0.0, ivec2(3, 3));\n" +
		"    float depth = textureLodOffset(sampler2D(shadow, raw), uv, float(0), ivec2(1, " +
		"1)).x;\n" +
		"    float depthLayer = textureLodOffset(sampler2DArray(shadowLayers, raw), vec3(uv, " +
		"float(1)), float(0), ivec2(1, 1)).x;\n" +
		"    fragColor = vec4((((plain.x + nudged.y) + layered.z) + volume_1.w), ((leveled.x + " +
		"biased.y) + graded.z), ((compared + comparedLayer) + comparedLevel), (depth + " +
		"depthLayer));\n" +
		"    return;\n" +
		"}\n";
}

test "every target prints the offset as the last argument of the sample" {
	const m = programOf();
	assert irErrors(m).length == 0;
	assert printedFor(m, 0, ShaderTarget.Wgsl, "offset").includes(
		"  var height_1 : vec4f = textureSampleLevel(height, heightSampler, position, 0f, " +
		"vec2i(2i, 3i));\n");
	const wgsl = printedFor(m, 1, ShaderTarget.Wgsl, "offset");
	assert wgsl.includes(
		"  var plain : vec4f = textureSample(color, linear, uv, vec2i(1i, 0i));\n");
	assert wgsl.includes(
		"  var nudged : vec4f = textureSample(color, linear, uv, vec2i((-1i), 2i));\n");
	assert wgsl.includes(
		"  var layered : vec4f = textureSample(layers, linear, uv, 1i, vec2i(0i, 2i));\n");
	assert wgsl.includes(
		"  var biased : vec4f = textureSampleBias(color, linear, uv, 0.5f, vec2i(2i, 2i));\n");
	assert wgsl.includes(
		"  var compared : f32 = textureSampleCompare(shadow, shadowSampler, uv, 0.5f, vec2i(1i, " +
		"0i));\n");
	assert wgsl.includes(
		"  var comparedLayer : f32 = textureSampleCompareLevel(shadowLayers, shadowSampler, uv, " +
		"1i, 0.5f, vec2i(0i, 1i));\n");
	assert wgsl.includes(
		"  var depth : f32 = textureSampleLevel(shadow, raw, uv, 0i, vec2i(1i, 1i));\n");
	assert printedFor(m, 0, ShaderTarget.Hlsl5, "offset").includes(
		"    float4 height_1 = height.SampleLevel(heightSampler, position, 0.0, int2(2, 3));\n");
	const hlsl = printedFor(m, 1, ShaderTarget.Hlsl5, "offset");
	assert hlsl.includes("    float4 plain = color.Sample(linear_1, uv, int2(1, 0));\n");
	assert hlsl.includes(
		"    float4 layered = layers.Sample(linear_1, float3(uv, float(1)), int2(0, 2));\n");
	assert hlsl.includes(
		"    float4 volume_1 = volume.Sample(linear_1, float3(uv.x, uv.y, 0.5), int3(1, 0, " +
		"-1));\n");
	assert hlsl.includes("    float4 biased = color.SampleBias(linear_1, uv, 0.5, int2(2, 2));\n");
	assert hlsl.includes(
		"float4 graded = layers.SampleGrad(linear_1, float3(uv, float(1)), float2(0.01, 0.0), " +
		"float2(0.0, 0.01), int2(1, 1));\n");
	assert hlsl.includes(
		"    float compared = shadow.SampleCmp(shadowSampler, uv, 0.5, int2(1, 0));\n");
	assert hlsl.includes(
		"    float comparedLevel = shadow.SampleCmpLevelZero(shadowSampler, uv, 0.5, int2(3, " +
		"3));\n");
	assert hlsl.includes("    float depth = shadow.SampleLevel(raw, uv, 0, int2(1, 1));\n");
	for (const target of [ShaderTarget.Glsl430, ShaderTarget.Glsl300es]) {
		assert printedFor(m, 0, target, "offset").includes(
			"    vec4 height = textureLodOffset(height_heightSampler, position, 0.0, ivec2(2, " +
			"3));\n");
		const gl = printedFor(m, 1, target, "offset");
		assert gl.includes(" plain = textureOffset(color_linear, uv, ivec2(1, 0));\n");
		assert gl.includes(
			" layered = textureOffset(layers_linear, vec3(uv, float(1)), ivec2(0, 2));\n");
		assert gl.includes(" biased = textureOffset(color_linear, uv, ivec2(2, 2), 0.5);\n");
		assert gl.includes(
			" graded = textureGradOffset(layers_linear, vec3(uv, float(1)), vec2(0.01, 0.0), " +
			"vec2(0.0, 0.01), ivec2(1, 1));\n");
		assert gl.includes(
			" compared = textureOffset(shadow_shadowSampler, vec3(uv, 0.5), ivec2(1, 0));\n");
		assert gl.includes(
			" comparedLayer = textureGradOffset(shadowLayers_shadowSampler, vec4(uv, float(1), " +
			"0.5), vec2(0.0), vec2(0.0), ivec2(0, 1));\n");
		assert gl.includes(" depth = textureLodOffset(shadow_raw, uv, float(0), ivec2(1, 1)).x;\n");
	}
	assert printedFor(m, 0, ShaderTarget.Msl, "offset").includes(
		"  float4 height_1 = height.sample(heightSampler, in.position, level(0.0), int2(2, 3));\n");
	const msl = printedFor(m, 1, ShaderTarget.Msl, "offset");
	assert msl.includes("  float4 plain = color.sample(linear, uv, int2(1, 0));\n");
	assert msl.includes("  float4 nudged = color.sample(linear, uv, int2((-1), 2));\n");
	assert msl.includes("  float4 layered = layers.sample(linear, uv, uint(1), int2(0, 2));\n");
	assert msl.includes(
		"  float4 volume_1 = volume.sample(linear, float3(uv.x, uv.y, 0.5), int3(1, 0, (-1)));\n");
	assert msl.includes("  float4 biased = color.sample(linear, uv, bias(0.5), int2(2, 2));\n");
	assert msl.includes(
		"  float4 graded = layers.sample(linear, uv, uint(1), gradient2d(float2(0.01, 0.0), " +
		"float2(0.0, 0.01)), int2(1, 1));\n");
	assert msl.includes(
		"  float compared = shadow.sample_compare(shadowSampler, uv, 0.5, int2(1, 0));\n");
	assert msl.includes(
		"  float comparedLevel = shadow.sample_compare(shadowSampler, uv, 0.5, level(0.0), " +
		"int2(3, 3));\n");
	assert msl.includes("  float depth = shadow.sample(raw, uv, level(0), int2(1, 1));\n");
}

function layeredOf(): ShaderModule {
	const m = programModule(glslIr(liftedVs), glslIr(layeredCompareFs), []);
	if (!m.ok) { throw new Error("layeredOf: " + m.error); }
	return m.value;
}

test "an offset compare of a depth array is GLSL 4.30's textureOffset and has no GLSL ES form" {
	const m = layeredOf();
	assert printedFor(m, 1, ShaderTarget.Glsl430, "layered").includes(
		"textureOffset(shadowLayers_shadowSampler, vec4(uv, float(1), 0.5), ivec2(0, 1))");
	const es = stageSource(m, 1, ShaderTarget.Glsl300es);
	assert !es.ok &&
		es.error.includes("textureOffset on sampler2DArrayShadow is GLSL 4.30's, never ES's"),
		es.ok ? "printed" : es.error;
	assert printedFor(m, 1, ShaderTarget.Wgsl, "layered").includes(
		"textureSampleCompare(shadowLayers, shadowSampler, uv, 1i, 0.5f, vec2i(0i, 1i))");
	assert printedFor(m, 1, ShaderTarget.Hlsl5, "layered").includes(
		"shadowLayers.SampleCmp(shadowSampler, float3(uv, float(1)), 0.5, int2(0, 1))");
	assert printedFor(m, 1, ShaderTarget.Msl, "layered").includes(
		"shadowLayers.sample_compare(shadowSampler, uv, uint(1), 0.5, int2(0, 1))");
	const fs = spirvProbe(m, 1, "layered");
	assert constOffsets(fs, 89, 6) == 1 && samples(fs, 89) == 1;
}

function constOffsets(words: uint32[][], opcode: int32, maskAt: int32): int32 {
	let ids: int32[] = [];
	for (const i of words) { if (opcodeOf(i) == 44) { ids.push(i[2] as int32); } }
	let n = 0;
	for (const i of words) {
		if (opcodeOf(i) == opcode && (i[maskAt] & 8) != 0 &&
			ids.includes(i[i.length - 1] as int32)) {
			n++;
		}
	}
	return n;
}

function samples(words: uint32[][], opcode: int32): int32 {
	return words.filter((i) => opcodeOf(i) == opcode).length;
}

test "SPIR-V gives every offset as a ConstOffset image operand naming a constant composite" {
	const vs = spirvProbe(programOf(), 0, "offset");
	const fs = spirvProbe(programOf(), 1, "offset");
	assert constOffsets(vs, 88, 5) == 1 && samples(vs, 88) == 1;
	assert constOffsets(fs, 87, 5) == 5 && samples(fs, 87) == 5;
	assert constOffsets(fs, 88, 5) == 4 && samples(fs, 88) == 4;
	assert constOffsets(fs, 89, 6) == 1 && samples(fs, 89) == 1;
	assert constOffsets(fs, 90, 6) == 2 && samples(fs, 90) == 2;
}

test "an offset past WGSL's range, on a cube, or not a constant of the right shape is refused" {
	let past = programOf();
	const sampled = past.functions[past.entries[1].functionIndex].body.filter((s) =>
		s.expr.intrinsic == Intrinsic.TextureSample)[0].expr;
	sampled.operands[3].operands[0] = literal(scalarType(ScalarKind.I32), 8.0);
	const range = "function 'offsetFs': TextureSample takes a constant offset in [-8, 7], as " +
		"WGSL's";
	assert irErrors(past).includes(range);
	for (const target of [ShaderTarget.Wgsl, ShaderTarget.Hlsl5, ShaderTarget.Glsl430,
		ShaderTarget.Glsl300es, ShaderTarget.Msl]) {
		const text = stageSource(past, 1, target);
		assert !text.ok && text.error.includes(range), text.ok ? "printed" : text.error;
	}
	const words = stageWords(past, 1);
	assert !words.ok && words.error.includes(range), words.ok ? "printed" : words.error;
	let wide = programOf();
	const volume = wide.functions[wide.entries[1].functionIndex].body.filter((s) =>
		s.expr.intrinsic == Intrinsic.TextureSample)[3].expr;
	volume.operands[3].type = vectorType(ScalarKind.I32, 2);
	assert irErrors(wide).includes("function 'offsetFs': TextureSample takes a constant offset " +
		"of 3 i32 for a D3 texture, as WGSL's");
	let cube = programOf();
	const sky = cube.functions[cube.entries[1].functionIndex].body.filter((s) =>
		s.expr.intrinsic == Intrinsic.TextureSample)[0].expr;
	sky.operands[0].type.shape = TextureShape.Cube;
	assert irErrors(cube).includes("function 'offsetFs': TextureSample takes no offset on a Cube " +
		"texture, as WGSL's");
	let variable = programOf();
	const layered = variable.functions[variable.entries[1].functionIndex].body.filter((s) =>
		s.expr.intrinsic == Intrinsic.TextureSample)[2].expr;
	layered.operands[4].operands[0].kind = ExprKind.Local;
	assert irErrors(variable).includes(
		"function 'offsetFs': TextureSample takes a constant offset " +
		"in [-8, 7], as WGSL's");
}
