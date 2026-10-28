// textureSampleCompare and textureSampleCompareLevel authored in MetaScript on depth textures and
// a comparison sampler, and @builtin(fragDepth): each entry runs on the CPU, is pinned as GLSL and
// printed for every target into out/<target>Probe/ for scripts/validateWgsl.sh,
// scripts/validateHlsl.sh and the GLSL validator.

import { mkdir, writeFile } from "std/fs";
import { Compare, Wrap } from "../gpu/state";
import { programModule, stageSource } from "../shader/descriptor";
import { glsl, glslIr } from "../shader/emit";
import { Intrinsic, ShaderModule, TextureShape, irErrors } from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import { reflectProgram } from "../shader/reflect";
import { opcodeOf, spirvProbe } from "./shaderProbeModules";
import {
	Sampler,
	SamplerComparison,
	Texture2d,
	TextureDepth2d,
	TextureDepth2dArray,
	TextureDepthCube,
	Vec2f,
	Vec4f,
	binding,
	builtin,
	textureSampleCompare,
	textureSampleCompareLevel,
	textureSampleGrad,
	vec2f,
	vec3f,
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

export struct Shadows {
	@binding(0) shadowMap: TextureDepth2d;
	@binding(1) shadowLayers: TextureDepth2dArray;
	@binding(2) shadowCube: TextureDepthCube;
	@binding(0) shadowSampler: SamplerComparison;
}

export struct HeightMap {
	@binding(3) heightMap: TextureDepth2d;
	@binding(1) heightSampler: SamplerComparison;
}

export function liftedVs(input: Corner, b: HeightMap): Placed {
	const lift = textureSampleCompareLevel(b.heightMap, b.heightSampler, input.position, 0.5);
	return { clip: vec4f(input.position.x, input.position.y, lift, 1.0) };
}

export function shadowFs(input: Pixel, b: Shadows): Vec4f {
	const uv = vec2f(0.25, 0.75);
	const flat = textureSampleCompare(b.shadowMap, b.shadowSampler, uv, 0.5);
	const layer = textureSampleCompare(b.shadowLayers, b.shadowSampler, uv, 1, 0.5);
	const cube = textureSampleCompare(b.shadowCube, b.shadowSampler, vec3f(uv.x, uv.y, 1.0), 0.5);
	const level = textureSampleCompareLevel(b.shadowLayers, b.shadowSampler, uv, 0, 0.5);
	return vec4f(flat, layer, cube, level);
}

function sampler(nearest: boolean, compare: Compare): SamplerComparison {
	return { nearest, wrap: Wrap.Clamp, compare };
}

function shadowsOf(nearest: boolean, compare: Compare): Shadows {
	return {
		shadowMap: { width: 2, height: 2, texels: [0.2, 0.6, 0.8, 0.4] },
		shadowLayers: { width: 2, height: 2, layers: 2,
			texels: [0.2, 0.2, 0.7, 0.2, 0.9, 0.1, 0.8, 0.1] },
		shadowCube: { size: 1, texels: [0.1, 0.2, 0.3, 0.4, 0.9, 0.6] },
		shadowSampler: sampler(nearest, compare),
	};
}

test "a depth texture compares the reference with a texel: nearest picks one, linear mixes four" {
	const nearest = shadowFs({ position: vec4f(0.0) }, shadowsOf(true, Compare.Less));
	assert nearest.x == 1.0;
	assert nearest.y == 1.0;
	assert nearest.z == 1.0;
	assert nearest.w == 1.0;
	const never = shadowFs({ position: vec4f(0.0) }, shadowsOf(true, Compare.Greater));
	assert never.x == 0.0 && never.y == 0.0 && never.z == 0.0 && never.w == 0.0;
	const b = shadowsOf(false, Compare.Less);
	assert textureSampleCompare(b.shadowMap, b.shadowSampler, vec2f(0.5, 0.5), 0.5) == 0.5;
	assert textureSampleCompare(b.shadowMap, b.shadowSampler, vec2f(0.5, 0.5), 0.1) == 1.0;
	assert textureSampleCompare(b.shadowMap, b.shadowSampler, vec2f(0.5, 0.5), 0.9) == 0.0;
	const down = shadowsOf(true, Compare.Less);
	assert textureSampleCompare(down.shadowCube, down.shadowSampler, vec3f(0.0, -1.0, 0.0),
		0.5) == 0.0;
	assert textureSampleCompare(down.shadowCube, down.shadowSampler, vec3f(0.0, 0.0, 1.0),
		0.5) == 1.0;
	assert textureSampleCompare(down.shadowCube, down.shadowSampler, vec3f(1.0, 0.0, 0.0),
		0.5) == 0.0;
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
	const m = programModule(glslIr(liftedVs), glslIr(shadowFs), []);
	if (!m.ok) { return new ShaderModule(); }
	return m.value;
}

test "GLSL 450 spells the comparison through a shadow sampler" {
	assert glsl(shadowFs) ==
		"@image_sample_type shadowMap depth\n" +
		"layout(binding=0) uniform texture2D shadowMap;\n" +
		"@image_sample_type shadowLayers depth\n" +
		"layout(binding=1) uniform texture2DArray shadowLayers;\n" +
		"@image_sample_type shadowCube depth\n" +
		"layout(binding=2) uniform textureCube shadowCube;\n" +
		"@sampler_type shadowSampler comparison\n" +
		"layout(binding=0) uniform sampler shadowSampler;\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    vec2 uv = vec2(0.25, 0.75);\n" +
		"    float flat_1 = texture(sampler2DShadow(shadowMap, shadowSampler), vec3(uv, 0.5));\n" +
		"    float layer = texture(sampler2DArrayShadow(shadowLayers, shadowSampler), vec4(uv, " +
		"float(1), 0.5));\n" +
		"    float cube = texture(samplerCubeShadow(shadowCube, shadowSampler), vec4(vec3(uv.x, " +
		"uv.y, 1.0), 0.5));\n" +
		"    float level = textureGrad(sampler2DArrayShadow(shadowLayers, shadowSampler), " +
		"vec4(uv, float(0), 0.5), vec2(0.0), vec2(0.0));\n" +
		"    fragColor = vec4(flat_1, layer, cube, level);\n" +
		"    return;\n" +
		"}\n";
}

test "every target spells textureSampleCompare and textureSampleCompareLevel" {
	const m = programOf();
	assert irErrors(m).length == 0;
	const wgsl = printedFor(m, 1, ShaderTarget.Wgsl, "shadow");
	assert wgsl.includes("@binding(0) @group(1) var shadowMap : texture_depth_2d;\n") &&
		wgsl.includes("@binding(1) @group(1) var shadowLayers : texture_depth_2d_array;\n") &&
		wgsl.includes("@binding(2) @group(1) var shadowCube : texture_depth_cube;\n") &&
		wgsl.includes("var shadowSampler : sampler_comparison;\n");
	assert wgsl.includes(
		"  var flat : f32 = textureSampleCompare(shadowMap, shadowSampler, uv, 0.5f);\n" +
		"  var layer : f32 = textureSampleCompare(shadowLayers, shadowSampler, uv, 1i, 0.5f);\n" +
		"  var cube : f32 = textureSampleCompare(shadowCube, shadowSampler, vec3f(uv.x, uv.y, " +
		"1f), 0.5f);\n" +
		"  var level : f32 = textureSampleCompareLevel(shadowLayers, shadowSampler, uv, 0i, " +
		"0.5f);\n");
	assert printedFor(m, 0, ShaderTarget.Wgsl, "shadow").includes(
		"  var lift : f32 = textureSampleCompareLevel(heightMap, heightSampler, position, " +
		"0.5f);\n");
	const hlsl = printedFor(m, 1, ShaderTarget.Hlsl5, "shadow");
	assert hlsl.startsWith("Texture2D<float> shadowMap : register(t0);\n" +
		"Texture2DArray<float> shadowLayers : register(t1);\n" +
		"TextureCube<float> shadowCube : register(t2);\n" +
		"SamplerComparisonState shadowSampler : register(s0);\n");
	assert hlsl.includes("    float flat = shadowMap.SampleCmp(shadowSampler, uv, 0.5);\n" +
		"    float layer = shadowLayers.SampleCmp(shadowSampler, float3(uv, float(1)), 0.5);\n" +
		"    float cube = shadowCube.SampleCmp(shadowSampler, float3(uv.x, uv.y, 1.0), 0.5);\n" +
		"    float level = shadowLayers.SampleCmpLevelZero(shadowSampler, float3(uv, float(0)), " +
		"0.5);\n");
	assert printedFor(m, 0, ShaderTarget.Hlsl5, "shadow").includes(
		"    float lift = heightMap.SampleCmpLevelZero(heightSampler, position, 0.5);\n");
	const gl = printedFor(m, 1, ShaderTarget.Glsl430, "shadow");
	assert gl.includes("layout(binding = 0) uniform sampler2DShadow shadowMap_shadowSampler;\n") &&
		gl.includes("layout(binding = 1) uniform sampler2DArrayShadow " +
		"shadowLayers_shadowSampler;\n") &&
		gl.includes("layout(binding = 2) uniform samplerCubeShadow shadowCube_shadowSampler;\n");
	assert gl.includes("    float flat_1 = texture(shadowMap_shadowSampler, vec3(uv, 0.5));\n" +
		"    float layer = texture(shadowLayers_shadowSampler, vec4(uv, float(1), 0.5));\n" +
		"    float cube = texture(shadowCube_shadowSampler, vec4(vec3(uv.x, uv.y, 1.0), 0.5));\n" +
		"    float level = textureGrad(shadowLayers_shadowSampler, vec4(uv, float(0), 0.5), " +
		"vec2(0.0), vec2(0.0));\n");
	assert printedFor(m, 0, ShaderTarget.Glsl300es, "shadow").includes(
		"    float lift = textureLod(heightMap_heightSampler, vec3(position, 0.5), 0.0);\n");
	const msl = printedFor(m, 1, ShaderTarget.Msl, "shadow");
	assert msl.includes("  float flat = shadowMap.sample_compare(shadowSampler, uv, 0.5);\n" +
		"  float layer = shadowLayers.sample_compare(shadowSampler, uv, uint(1), 0.5);\n" +
		"  float cube = shadowCube.sample_compare(shadowSampler, float3(uv.x, uv.y, 1.0), 0.5);\n" +
		"  float level_1 = shadowLayers.sample_compare(shadowSampler, uv, uint(0), 0.5, " +
		"level(0.0));\n");
}

test "the reflection names a depth texture and a comparison sampler" {
	const reflected = reflectProgram(programOf(), 0, 1, ShaderTarget.Wgsl);
	assert reflected.ok;
	const texture = reflected.value.bindings.filter((b) => b.kind == "texture");
	assert texture.length == 4 && texture.filter((b) => b.sampleType == "depth").length == 4;
	assert texture.map((b) => b.viewDimension).join("|") == "|2d-array|cube|";
	const samplers = reflected.value.bindings.filter((b) => b.kind == "sampler");
	assert samplers.length == 2 &&
		samplers.filter((b) => b.samplerType == "comparison").length == 2;
}

export function plainVs(input: Corner): Placed {
	return { clip: vec4f(input.position.x, input.position.y, 0.0, 1.0) };
}

export struct Colours {
	@binding(0) atlas: Texture2d;
	@binding(0) atlasSampler: Sampler;
}

export function gradedFs(input: Pixel, b: Colours): Vec4f {
	return textureSampleGrad(b.atlas, b.atlasSampler, vec2f(0.5), vec2f(0.01), vec2f(0.01));
}

test "a gradient sample of a depth texture is refused by the IR and by every printer alone" {
	for (const shape of [TextureShape.Depth2d, TextureShape.Depth2dArray, TextureShape.DepthCube]) {
		let m = gradedProgram();
		const graded = m.functions[m.entries[1].functionIndex].body.filter((s) =>
			s.expr.intrinsic == Intrinsic.TextureSampleGrad)[0].expr;
		graded.operands[0].type.shape = shape;
		const refusal = "function 'gradedFs': TextureSampleGrad of a " + shape.toString() +
			" texture of F32: it samples a float color texture here";
		assert irErrors(m).includes(refusal);
		for (const target of [ShaderTarget.Wgsl, ShaderTarget.Hlsl5, ShaderTarget.Glsl430,
			ShaderTarget.Glsl300es, ShaderTarget.Msl]) {
			const text = stageSource(m, 1, target);
			assert !text.ok && text.error.includes(refusal);
		}
	}
}

function gradedProgram(): ShaderModule {
	const m = programModule(glslIr(plainVs), glslIr(gradedFs), []);
	if (!m.ok) { return new ShaderModule(); }
	return m.value;
}

test "SPIR-V compares with the implicit level in the fragment and level 0 in the vertex stage" {
	const vs = spirvProbe(programOf(), 0, "shadow");
	const fs = spirvProbe(programOf(), 1, "shadow");
	assert fs.filter(i => opcodeOf(i) == 89).length > 0;
	assert vs.filter(i => opcodeOf(i) == 90).length > 0 &&
		vs.filter(i => opcodeOf(i) == 89).length == 0;
}
