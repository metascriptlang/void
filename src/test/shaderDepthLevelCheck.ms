// textureSampleLevel on depth textures authored in MetaScript, WGSL's `textureSampleLevel(t:
// texture_depth_2d | texture_depth_2d_array | texture_depth_cube, s: sampler, coords, [layer,]
// level: i32) -> f32`: each entry runs on the CPU, is pinned as GLSL and printed for every target
// into out/<target>Probe/ for scripts/validateWgsl.sh, scripts/validateHlsl.sh and spirv-val.

import { mkdir, writeFile } from "std/fs";
import { Wrap } from "../gpu/state";
import { programModule, stageSource, stageWords } from "../shader/descriptor";
import { glsl, glslIr } from "../shader/emit";
import { Intrinsic, ScalarKind, ShaderModule, irErrors, scalarType } from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import { reflectProgram } from "../shader/reflect";
import { opcodeOf, spirvProbe } from "./shaderProbeModules";
import {
	Sampler,
	TextureDepth2d,
	TextureDepth2dArray,
	TextureDepthCube,
	Vec2f,
	Vec4f,
	binding,
	builtin,
	samplerType,
	textureSampleLevel,
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

export struct Depths {
	@binding(0) shadowMap: TextureDepth2d;
	@binding(1) shadowLayers: TextureDepth2dArray;
	@binding(2) shadowCube: TextureDepthCube;
	@binding(0) @samplerType(nonfiltering) rawSampler: Sampler;
}

export struct HeightMap {
	@binding(3) heightMap: TextureDepth2d;
	@binding(1) @samplerType(nonfiltering) heightSampler: Sampler;
}

export function liftedVs(input: Corner, b: HeightMap): Placed {
	const lift = textureSampleLevel(b.heightMap, b.heightSampler, input.position, 1);
	return { clip: vec4f(input.position.x, input.position.y, lift, 1.0) };
}

export function levelFs(input: Pixel, b: Depths): Vec4f {
	const uv = vec2f(0.25, 0.75);
	const flat = textureSampleLevel(b.shadowMap, b.rawSampler, uv, 0);
	const layer = textureSampleLevel(b.shadowLayers, b.rawSampler, uv, 1, 2);
	const cube = textureSampleLevel(b.shadowCube, b.rawSampler, vec3f(uv.x, uv.y, 1.0), 1);
	return vec4f(flat, layer, cube, 0.0);
}

function depthsOf(nearest: boolean): Depths {
	return {
		shadowMap: { width: 2, height: 2, texels: [0.2, 0.6, 0.8, 0.4] },
		shadowLayers: { width: 2, height: 2, layers: 2,
			texels: [0.2, 0.2, 0.7, 0.2, 0.9, 0.1, 0.8, 0.1] },
		shadowCube: { size: 1, texels: [0.1, 0.2, 0.3, 0.4, 0.9, 0.6] },
		rawSampler: { nearest, wrap: Wrap.Clamp },
	};
}

test "a depth texture samples a texel as a number: nearest picks one, linear mixes four, a level past the last clamps to it" {
	const nearest = depthsOf(true);
	const out = levelFs({ position: vec4f(0.0) }, nearest);
	assert out.x == 0.8 && out.y == 0.8 && out.z == 0.9 && out.w == 0.0;
	assert textureSampleLevel(nearest.shadowCube, nearest.rawSampler, vec3f(1.0, 0.0, 0.0), 0) == 0.1;
	const linear = depthsOf(false);
	const mixed = textureSampleLevel(linear.shadowMap, linear.rawSampler, vec2f(0.5, 0.5), 0);
	assert Math.abs(mixed - 0.5) < 0.0001;
	assert textureSampleLevel(linear.shadowMap, linear.rawSampler, vec2f(0.5, 0.5), 7) == mixed;
}

function probePath(name: string, target: ShaderTarget, stage: string): string {
	return match (target) {
		ShaderTarget.Wgsl => "out/wgslProbe/" + name + stage + ".wgsl",
		ShaderTarget.Hlsl5 => "out/hlslProbe/" + name + "." + (stage == "Vs" ? "vs" : "ps") + ".hlsl",
		ShaderTarget.Glsl430 => "out/glslProbe/" + name + ".430." + (stage == "Vs" ? "vert" : "frag"),
		ShaderTarget.Glsl300es => "out/glslProbe/" + name + ".es." + (stage == "Vs" ? "vert" : "frag"),
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
	const m = programModule(glslIr(liftedVs), glslIr(levelFs), []);
	if (!m.ok) { throw new Error("programOf: " + m.error); }
	return m.value;
}

test "GLSL 450 samples a depth texture through a plain sampler and reads its first lane" {
	assert glsl(levelFs) ==
		"@image_sample_type shadowMap depth\n" +
		"layout(binding=0) uniform texture2D shadowMap;\n" +
		"@image_sample_type shadowLayers depth\n" +
		"layout(binding=1) uniform texture2DArray shadowLayers;\n" +
		"@image_sample_type shadowCube depth\n" +
		"layout(binding=2) uniform textureCube shadowCube;\n" +
		"@sampler_type rawSampler nonfiltering\n" +
		"layout(binding=0) uniform sampler rawSampler;\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    vec2 uv = vec2(0.25, 0.75);\n" +
		"    float flat_1 = textureLod(sampler2D(shadowMap, rawSampler), uv, float(0)).x;\n" +
		"    float layer = textureLod(sampler2DArray(shadowLayers, rawSampler), vec3(uv, float(1)), float(2)).x;\n" +
		"    float cube = textureLod(samplerCube(shadowCube, rawSampler), vec3(uv.x, uv.y, 1.0), float(1)).x;\n" +
		"    fragColor = vec4(flat_1, layer, cube, 0.0);\n" +
		"    return;\n" +
		"}\n";
}

test "every target spells textureSampleLevel on a depth texture" {
	const m = programOf();
	assert irErrors(m).length == 0;
	assert printedFor(m, 0, ShaderTarget.Wgsl, "depthLevel").includes(
		"  var lift : f32 = textureSampleLevel(heightMap, heightSampler, position, 1i);\n");
	const wgsl = printedFor(m, 1, ShaderTarget.Wgsl, "depthLevel");
	assert wgsl.includes("@binding(0) @group(1) var shadowMap : texture_depth_2d;\n");
	assert wgsl.includes("  var flat : f32 = textureSampleLevel(shadowMap, rawSampler, uv, 0i);\n" +
		"  var layer : f32 = textureSampleLevel(shadowLayers, rawSampler, uv, 1i, 2i);\n" +
		"  var cube : f32 = textureSampleLevel(shadowCube, rawSampler, vec3f(uv.x, uv.y, 1f), 1i);\n");
	assert printedFor(m, 0, ShaderTarget.Hlsl5, "depthLevel").includes(
		"    float lift = heightMap.SampleLevel(heightSampler, position, 1);\n");
	const hlsl = printedFor(m, 1, ShaderTarget.Hlsl5, "depthLevel");
	assert hlsl.includes("    float flat = shadowMap.SampleLevel(rawSampler, uv, 0);\n" +
		"    float layer = shadowLayers.SampleLevel(rawSampler, float3(uv, float(1)), 2);\n" +
		"    float cube = shadowCube.SampleLevel(rawSampler, float3(uv.x, uv.y, 1.0), 1);\n");
	for (const target of [ShaderTarget.Glsl430, ShaderTarget.Glsl300es]) {
		assert printedFor(m, 0, target, "depthLevel").includes(
			"    float lift = textureLod(heightMap_heightSampler, position, float(1)).x;\n");
		const gl = printedFor(m, 1, target, "depthLevel");
		assert gl.includes(" sampler2D shadowMap_rawSampler;\n");
		assert gl.includes(" flat_1 = textureLod(shadowMap_rawSampler, uv, float(0)).x;\n");
		assert gl.includes(" layer = textureLod(shadowLayers_rawSampler, vec3(uv, float(1)), float(2)).x;\n");
		assert gl.includes(" cube = textureLod(shadowCube_rawSampler, vec3(uv.x, uv.y, 1.0), float(1)).x;\n");
	}
	assert printedFor(m, 0, ShaderTarget.Msl, "depthLevel").includes(
		"  float lift = heightMap.sample(heightSampler, in.position, level(1));\n");
	assert printedFor(m, 1, ShaderTarget.Msl, "depthLevel").includes(
		"  float flat = shadowMap.sample(rawSampler, uv, level(0));\n" +
		"  float layer = shadowLayers.sample(rawSampler, uv, uint(1), level(2));\n" +
		"  float cube = shadowCube.sample(rawSampler, float3(uv.x, uv.y, 1.0), level(1));\n");
}

test "the reflection names a depth texture and a non-filtering sampler" {
	const reflected = reflectProgram(programOf(), 0, 1, ShaderTarget.Wgsl);
	assert reflected.ok;
	const texture = reflected.value.bindings.filter((b) => b.kind == "texture");
	assert texture.length == 4 && texture.filter((b) => b.sampleType == "depth").length == 4;
	const samplers = reflected.value.bindings.filter((b) => b.kind == "sampler");
	assert samplers.length == 2 && samplers.filter((b) => b.samplerType == "non-filtering").length == 2;
}

test "SPIR-V samples a depth image with an explicit level and keeps its first lane" {
	const vs = spirvProbe(programOf(), 0, "depthLevel");
	const fs = spirvProbe(programOf(), 1, "depthLevel");
	assert vs.filter((i) => opcodeOf(i) == 88).length == 1;
	assert fs.filter((i) => opcodeOf(i) == 88).length == 3;
	assert fs.filter((i) => opcodeOf(i) == 90).length == 0;
}

test "only textureSampleLevel samples a depth texture without a reference, and its level is an integer" {
	let m = programOf();
	const sampled = m.functions[m.entries[1].functionIndex].body.filter((s) =>
		s.expr.intrinsic == Intrinsic.TextureSampleLevel)[0].expr;
	sampled.operands[3].type = scalarType(ScalarKind.F32);
	const refusal = "function 'levelFs': TextureSampleLevel of a Depth2d texture takes an i32 or " +
		"u32 level, as WGSL's";
	assert irErrors(m).includes(refusal);
	for (const target of [ShaderTarget.Wgsl, ShaderTarget.Hlsl5, ShaderTarget.Glsl430,
		ShaderTarget.Glsl300es, ShaderTarget.Msl]) {
		const text = stageSource(m, 1, target);
		assert !text.ok && text.error.includes(refusal), text.ok ? "printed" : text.error;
	}
	const words = stageWords(m, 1);
	assert !words.ok && words.error.includes(refusal), words.ok ? "printed" : words.error;
	let biased = programOf();
	const bias = biased.functions[biased.entries[1].functionIndex].body.filter((s) =>
		s.expr.intrinsic == Intrinsic.TextureSampleLevel)[0].expr;
	bias.intrinsic = Intrinsic.TextureSampleBias;
	assert irErrors(biased).includes("function 'levelFs': TextureSampleBias of a Depth2d texture " +
		"of F32: it samples a float color texture here");
}
