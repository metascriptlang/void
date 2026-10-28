// textureSampleLevel, textureSampleBias and textureSampleGrad authored in MetaScript: each entry
// runs on the CPU, is pinned as GLSL, and is printed for every target into out/<target>Probe/ for
// scripts/validateWgsl.sh, scripts/validateHlsl.sh and naga's GLSL front end.

import { mkdir, writeFile } from "std/fs";
import { Wrap } from "../gpu/state";
import { programModule, stageSource } from "../shader/descriptor";
import { glsl, glslIr, glslLinkedIr } from "../shader/emit";
import {
	Intrinsic,
	SamplerType,
	ShaderExpr,
	ShaderModule,
	StmtKind,
	TextureShape,
	irErrors,
} from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import { reflectProgram } from "../shader/reflect";
import { GPUShaderStage } from "../webgpu/types.ms";
import {
	Sampler,
	Texture2d,
	Texture2dArray,
	TextureCube,
	Vec2f,
	Vec3f,
	Vec4f,
	binding,
	builtin,
	textureSample,
	textureSampleBias,
	textureSampleGrad,
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

export struct Atlas {
	@binding(0) atlas: Texture2d;
	@binding(1) layers: Texture2dArray;
	@binding(0) atlasSampler: Sampler;
}

export struct Terrain {
	@binding(2) height: Texture2d;
	@binding(1) heightSampler: Sampler;
}

export function liftedVs(input: Corner, b: Terrain): Placed {
	const height = textureSampleLevel(b.height, b.heightSampler, input.position, 0.0);
	return { clip: vec4f(input.position.x, input.position.y, height.x, 1.0) };
}

export function mippedFs(input: Pixel, b: Atlas): Vec4f {
	const uv = vec2f(0.25, 0.75);
	const level = textureSampleLevel(b.atlas, b.atlasSampler, uv, 2.0);
	const biased = textureSampleBias(b.atlas, b.atlasSampler, uv, -1.0);
	const graded = textureSampleGrad(b.atlas, b.atlasSampler, uv, vec2f(0.01, 0.0),
		vec2f(0.0, 0.01));
	const layer = textureSampleLevel(b.layers, b.atlasSampler, uv, 1, 0.0);
	const layerBiased = textureSampleBias(b.layers, b.atlasSampler, uv, 0, 0.5);
	const layerGraded = textureSampleGrad(b.layers, b.atlasSampler, uv, 1, vec2f(0.0, 0.0),
		vec2f(0.0, 0.0));
	return vec4f(level.x + biased.y, graded.z, layer.x + layerBiased.y, layerGraded.w);
}

function atlasOf(): Atlas {
	let texels: float32[] = [];
	for (let i = 0; i < 4; i++) {
		texels.push(i as float32);
		texels.push(10.0 + (i as float32));
		texels.push(20.0 + (i as float32));
		texels.push(30.0 + (i as float32));
	}
	let layered: float32[] = [];
	for (let i = 0; i < 8; i++) {
		layered.push(100.0 * (i as float32));
		layered.push(1.0);
		layered.push(2.0);
		layered.push(3.0 + (i as float32));
	}
	return {
		atlas: { width: 2, height: 2, texels },
		layers: { width: 2, height: 2, layers: 2, texels: layered },
		atlasSampler: { nearest: true, wrap: Wrap.Clamp },
	};
}

test "a CPU texture has one level, so every explicit level samples it as textureSample" {
	const b = atlasOf();
	const out = mippedFs({ position: vec4f(0.0) }, b);
	assert out.x == 2.0 + 12.0;
	assert out.y == 22.0;
	assert out.z == 600.0 + 1.0;
	assert out.w == 9.0;
	const placed = liftedVs({ position: vec2f(0.75, 0.25) },
		{ height: b.atlas, heightSampler: b.atlasSampler });
	assert placed.clip.z == 1.0;
}

test "GLSL 450 spells the explicit samples through a combined sampler" {
	assert glsl(mippedFs) ==
		"layout(binding=0) uniform texture2D atlas;\n" +
		"layout(binding=1) uniform texture2DArray layers;\n" +
		"layout(binding=0) uniform sampler atlasSampler;\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    vec2 uv = vec2(0.25, 0.75);\n" +
		"    vec4 level = textureLod(sampler2D(atlas, atlasSampler), uv, 2.0);\n" +
		"    vec4 biased = texture(sampler2D(atlas, atlasSampler), uv, -1.0);\n" +
		"    vec4 graded = textureGrad(sampler2D(atlas, atlasSampler), uv, vec2(0.01, 0.0), vec2(0.0, 0.01));\n" +
		"    vec4 layer = textureLod(sampler2DArray(layers, atlasSampler), vec3(uv, float(1)), 0.0);\n" +
		"    vec4 layerBiased = texture(sampler2DArray(layers, atlasSampler), vec3(uv, float(0)), 0.5);\n" +
		"    vec4 layerGraded = textureGrad(sampler2DArray(layers, atlasSampler), vec3(uv, float(1)), vec2(0.0, 0.0), vec2(0.0, 0.0));\n" +
		"    fragColor = vec4((level.x + biased.y), graded.z, (layer.x + layerBiased.y), layerGraded.w);\n" +
		"    return;\n" +
		"}\n";
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
	const m = programModule(glslIr(liftedVs), glslIr(mippedFs), []);
	if (!m.ok) { return new ShaderModule(); }
	return m.value;
}

test "every target spells textureSampleLevel, textureSampleBias and textureSampleGrad" {
	const m = programOf();
	assert irErrors(m).length == 0;
	assert printedFor(m, 0, ShaderTarget.Wgsl, "mipped").includes(
		"  var height_1 : vec4f = textureSampleLevel(height, heightSampler, position, 0f);\n");
	const wgsl = printedFor(m, 1, ShaderTarget.Wgsl, "mipped");
	assert wgsl.startsWith("diagnostic(off, derivative_uniformity);\n");
	assert wgsl.includes("  var biased : vec4f = textureSampleBias(atlas, atlasSampler, uv, (-1f));\n" +
		"  var graded : vec4f = textureSampleGrad(atlas, atlasSampler, uv, vec2f(0.01f, 0f), " +
		"vec2f(0f, 0.01f));\n" +
		"  var layer : vec4f = textureSampleLevel(layers, atlasSampler, uv, 1i, 0f);\n");
	assert printedFor(m, 0, ShaderTarget.Hlsl5, "mipped").includes(
		"    float4 height_1 = height.SampleLevel(heightSampler, position, 0.0);\n");
	const hlsl = printedFor(m, 1, ShaderTarget.Hlsl5, "mipped");
	assert hlsl.includes("    float4 biased = atlas.SampleBias(atlasSampler, uv, -1.0);\n" +
		"    float4 graded = atlas.SampleGrad(atlasSampler, uv, float2(0.01, 0.0), " +
		"float2(0.0, 0.01));\n" +
		"    float4 layer = layers.SampleLevel(atlasSampler, float3(uv, float(1)), 0.0);\n");
	for (const target of [ShaderTarget.Glsl430, ShaderTarget.Glsl300es]) {
		assert printedFor(m, 0, target, "mipped").includes(
			"    vec4 height = textureLod(height_heightSampler, position, 0.0);\n");
		const gl = printedFor(m, 1, target, "mipped");
		assert gl.includes(" biased = texture(atlas_atlasSampler, uv, -1.0);\n");
		assert gl.includes(" graded = textureGrad(atlas_atlasSampler, uv, vec2(0.01, 0.0), " +
			"vec2(0.0, 0.01));\n");
		assert gl.includes(" layer = textureLod(layers_atlasSampler, vec3(uv, float(1)), 0.0);\n");
	}
	assert printedFor(m, 0, ShaderTarget.Msl, "mipped").includes(
		"  float4 height_1 = height.sample(heightSampler, in.position, level(0.0));\n");
	const msl = printedFor(m, 1, ShaderTarget.Msl, "mipped");
	assert msl.includes("  float4 level_1 = atlas.sample(atlasSampler, uv, level(2.0));\n" +
		"  float4 biased = atlas.sample(atlasSampler, uv, bias((-1.0)));\n" +
		"  float4 graded = atlas.sample(atlasSampler, uv, gradient2d(float2(0.01, 0.0), " +
		"float2(0.0, 0.01)));\n" +
		"  float4 layer = layers.sample(atlasSampler, uv, uint(1), level(0.0));\n");
}

test "an explicit sample of a depth texture with a float level, or without its level, is refused by name" {
	let depth = programOf();
	const lifted = depth.functions[depth.entries[0].functionIndex].body[0].expr;
	lifted.operands[0].type.shape = TextureShape.Depth2d;
	assert irErrors(depth).includes("function 'liftedVs': TextureSampleLevel of a Depth2d " +
		"texture takes an i32 or u32 level, as WGSL's");
	let short = programOf();
	const body = short.functions[short.entries[1].functionIndex].body;
	const graded = body.filter((s) => s.kind == StmtKind.Let &&
		s.expr.intrinsic == Intrinsic.TextureSampleGrad)[0].expr;
	graded.operands.pop();
	assert irErrors(short).includes("function 'mippedFs': TextureSampleGrad takes a texture, a " +
		"sampler, coordinates, a layer of an array, and two derivatives, as WGSL's");
}

function gradedOf(m: ShaderModule): ShaderExpr {
	const body = m.functions[m.entries[1].functionIndex].body;
	return body.filter((s) => s.kind == StmtKind.Let &&
		s.expr.intrinsic == Intrinsic.TextureSampleGrad)[0].expr;
}

test "a sample through a comparison sampler, of a multisampled texture, or with the wrong operands is refused for every target" {
	let comparison = programOf();
	comparison.resources[gradedOf(comparison).operands[1].index].samplerType = SamplerType.Comparison;
	assert irErrors(comparison).join("
").includes("TextureSampleGrad through a comparison " +
		"sampler, which needs a depth reference");

	let plain = programOf();
	const sample = gradedOf(plain);
	sample.intrinsic = Intrinsic.TextureSample;
	sample.operands = sample.operands.slice(0, 3);
	assert irErrors(plain).length == 0;
	plain.resources[sample.operands[1].index].samplerType = SamplerType.Comparison;
	assert irErrors(plain).join("
").includes("TextureSample through a comparison sampler, " +
		"which needs a depth reference");
	plain.resources[sample.operands[1].index].samplerType = SamplerType.Filtering;

	sample.operands[0].type.shape = TextureShape.Multisampled2d;
	assert irErrors(plain).join("
").includes("TextureSample of a multisampled texture");
	sample.operands[0].type.shape = TextureShape.D2;

	sample.operands = sample.operands.slice(0, 2);
	assert irErrors(plain).join("
").includes("TextureSample takes a texture, a sampler, " +
		"coordinates and, for an array texture, a layer, and an optional constant offset");
}

export struct Sky {
	@binding(0) sky: TextureCube;
	@binding(0) skySampler: Sampler;
}

export struct Horizon {
	@binding(1) horizon: TextureCube;
	@binding(1) horizonSampler: Sampler;
}

export struct SkyRay {
	@builtin(position) clip: Vec4f;
	direction: Vec3f;
}

export function skyVs(input: Corner, b: Horizon): SkyRay {
	const direction = vec3f(input.position.x, input.position.y, 1.0);
	const glow = textureSampleLevel(b.horizon, b.horizonSampler, direction, 0.0);
	return { clip: vec4f(input.position.x, input.position.y, glow.x, 1.0), direction };
}

export function skyFs(input: SkyRay, b: Sky): Vec4f {
	return textureSample(b.sky, b.skySampler, input.direction) +
		textureSampleLevel(b.sky, b.skySampler, input.direction, 2.0);
}

test "every target samples a cube texture along a direction" {
	const linked = programModule(glslIr(skyVs), glslLinkedIr(skyFs, skyVs), []);
	assert linked.ok;
	const m = linked.value;
	assert irErrors(m).length == 0;
	assert printedFor(m, 0, ShaderTarget.Wgsl, "sky").includes(
		"  var glow : vec4f = textureSampleLevel(horizon, horizonSampler, direction_1, 0f);\n");
	const wgsl = printedFor(m, 1, ShaderTarget.Wgsl, "sky");
	assert wgsl.includes("@binding(0) @group(1) var sky : texture_cube<f32>;\n");
	assert wgsl.includes("  fragColor = (textureSample(sky, skySampler, direction) + " +
		"textureSampleLevel(sky, skySampler, direction, 2f));\n");
	assert printedFor(m, 0, ShaderTarget.Hlsl5, "sky").includes(
		"    float4 glow = horizon.SampleLevel(horizonSampler, direction_1, 0.0);\n");
	const hlsl = printedFor(m, 1, ShaderTarget.Hlsl5, "sky");
	assert hlsl.startsWith("TextureCube<float4> sky : register(t0);\n");
	assert hlsl.includes("    fragColor = sky.Sample(skySampler, direction) + " +
		"sky.SampleLevel(skySampler, direction, 2.0);\n");
	for (const target of [ShaderTarget.Glsl430, ShaderTarget.Glsl300es]) {
		assert printedFor(m, 0, target, "sky").includes(
			"    vec4 glow = textureLod(horizon_horizonSampler, direction_1, 0.0);\n");
		const gl = printedFor(m, 1, target, "sky");
		assert gl.includes(" samplerCube sky_skySampler;\n");
		assert gl.includes("    fragColor = texture(sky_skySampler, direction) + " +
			"textureLod(sky_skySampler, direction, 2.0);\n");
	}
	assert printedFor(m, 0, ShaderTarget.Msl, "sky").includes(
		"  float4 glow = horizon.sample(horizonSampler, direction_1, level(0.0));\n");
	assert printedFor(m, 1, ShaderTarget.Msl, "sky").includes(
		"  out.fragColor = (sky.sample(skySampler, in.direction) + " +
		"sky.sample(skySampler, in.direction, level(2.0)));\n");
	const reflected = reflectProgram(m, 0, 1, ShaderTarget.Wgsl);
	assert reflected.ok && reflected.value.bindings.filter((b) => b.kind == "texture" &&
		b.viewDimension == "cube").length == 2;
}

export function domeVs(input: Corner, b: Sky): SkyRay {
	const direction = vec3f(input.position.x, input.position.y, 1.0);
	const glow = textureSampleLevel(b.sky, b.skySampler, direction, 0.0);
	return { clip: vec4f(input.position.x, input.position.y, glow.x, 1.0), direction };
}

test "a texture and sampler both stages read are one binding, at one native slot" {
	const linked = programModule(glslIr(domeVs), glslLinkedIr(skyFs, domeVs), []);
	assert linked.ok;
	const m = linked.value;
	assert irErrors(m).length == 0 && m.resources.length == 2;
	const both = (GPUShaderStage.VERTEX as int32) | (GPUShaderStage.FRAGMENT as int32);
	for (const target of [ShaderTarget.Hlsl5, ShaderTarget.Wgsl, ShaderTarget.Msl]) {
		const reflected = reflectProgram(m, 0, 1, target);
		assert reflected.ok && reflected.value.bindings.length == 2 &&
			reflected.value.bindings.filter((b) => b.visibility == both).length == 2;
	}
	for (const entry of [0, 1]) {
		const wgsl = printedFor(m, entry, ShaderTarget.Wgsl, "dome");
		assert wgsl.includes("@binding(0) @group(1) var sky : texture_cube<f32>;") &&
			wgsl.includes("@binding(32) @group(1) var skySampler : sampler;");
		const hlsl = printedFor(m, entry, ShaderTarget.Hlsl5, "dome");
		assert hlsl.includes("TextureCube<float4> sky : register(t0);") &&
			hlsl.includes("SamplerState skySampler : register(s0);");
		assert printedFor(m, entry, ShaderTarget.Glsl430, "dome").includes(
			"layout(binding = 0) uniform samplerCube sky_skySampler;");
		assert printedFor(m, entry, ShaderTarget.Glsl300es, "dome").includes(
			"uniform highp samplerCube sky_skySampler;");
		assert printedFor(m, entry, ShaderTarget.Msl, "dome").includes(
			"texturecube<float> sky [[texture(0)]], sampler skySampler [[sampler(0)]]");
	}
}

export struct Rim {
	@binding(1) horizon: TextureCube;
	@binding(2) rim: TextureCube;
	@binding(1) horizonSampler: Sampler;
}

export struct RimOnly {
	@binding(2) rim: TextureCube;
	@binding(1) horizonSampler: Sampler;
}

export function rimVs(input: Corner, b: Rim): SkyRay {
	const direction = vec3f(input.position.x, input.position.y, 1.0);
	const glow = textureSampleLevel(b.horizon, b.horizonSampler, direction, 0.0) +
		textureSampleLevel(b.rim, b.horizonSampler, direction, 0.0);
	return { clip: vec4f(input.position.x, input.position.y, glow.x, 1.0), direction };
}

export function rimFs(input: SkyRay, b: RimOnly): Vec4f {
	return textureSample(b.rim, b.horizonSampler, input.direction);
}

test "a shared view takes the first native slot free in every stage that reads it" {
	const linked = programModule(glslIr(rimVs), glslLinkedIr(rimFs, rimVs), []);
	assert linked.ok;
	const m = linked.value;
	assert m.resources.length == 3;
	const reflected = reflectProgram(m, 0, 1, ShaderTarget.Hlsl5);
	assert reflected.ok;
	const visible = reflected.value.bindings.map((b) => String(b.binding) + ":" + String(b.visibility));
	assert visible.join(" ") == "1:1 2:3 33:3";
	for (const entry of [0, 1]) {
		const hlsl = printedFor(m, entry, ShaderTarget.Hlsl5, "rim");
		assert hlsl.includes("TextureCube<float4> rim : register(t1);") &&
			hlsl.includes("SamplerState horizonSampler : register(s1);");
		assert printedFor(m, entry, ShaderTarget.Msl, "rim").includes(
			"texturecube<float> rim [[texture(1)]], sampler horizonSampler [[sampler(1)]]");
		assert printedFor(m, entry, ShaderTarget.Glsl430, "rim").includes(
			"layout(binding = 1) uniform samplerCube rim_horizonSampler;");
	}
	assert printedFor(m, 0, ShaderTarget.Hlsl5, "rim").startsWith(
		"TextureCube<float4> horizon : register(t0);");
}

