// WGSL's texture_1d<f32> (textureSample, textureSampleLevel, textureLoad, textureDimensions) and
// texture_storage_1d (textureLoad, textureStore, textureDimensions): each entry runs on the CPU, is
// pinned as GLSL and printed for every target into out/<target>Probe/ for scripts/validateWgsl.sh,
// scripts/validateHlsl.sh, naga and spirv-val.

import { mkdir, writeFile } from "std/fs";
import { Wrap } from "../gpu/state";
import { computeModule, programModule, stageSource, stageWords, wordsBase64 } from "../shader/descriptor";
import { Buffer } from "std/core/buffer";
import { glsl, glslCompute, glslComputeIr, glslIr } from "../shader/emit";
import { Intrinsic, ShaderModule, irErrors } from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import { reflectCompute, reflectProgram } from "../shader/reflect";
import { opcodeOf, spirvProbe } from "./shaderProbeModules";
import {
	Sampler,
	StorageTexture1d,
	Texture1d,
	Vec2f,
	Vec3u,
	Vec4f,
	access,
	binding,
	builtin,
	format,
	textureDimensions,
	textureLoad,
	textureSample,
	textureSampleLevel,
	textureStore,
	vec2i,
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

export struct Ids {
	@builtin(globalInvocationId) id: Vec3u;
}

export struct Line {
	@binding(0) ramp: Texture1d;
	@binding(0) rampSampler: Sampler;
}

export struct Strip {
	@binding(0) @format(r32float) @access(read_write) strip: StorageTexture1d;
}

export function plainVs(input: Corner): Placed {
	return { clip: vec4f(input.position.x, input.position.y, 0.0, 1.0) };
}

export function lineFs(input: Pixel, b: Line): Vec4f {
	const smooth = textureSample(b.ramp, b.rampSampler, 0.25);
	const level = textureSampleLevel(b.ramp, b.rampSampler, 0.75, 0.0);
	const size = textureDimensions(b.ramp, 0);
	const texel = textureLoad(b.ramp, 1, 0);
	return vec4f(smooth.x + level.y, texel.z, size as float32, texel.w);
}

export function stripCs(input: Ids, b: Strip): void {
	const x = vec2i(input.id.xy).x;
	const size = textureDimensions(b.strip);
	const seen = textureLoad(b.strip, x);
	textureStore(b.strip, x, vec4f(seen.x + 1.0, seen.y, seen.z, size as float32));
}

function lineOf(nearest: boolean, wrap: Wrap): Line {
	let texels: float32[] = [];
	for (let i = 0; i < 4; i++) {
		texels.push((i * 10) as float32);
		texels.push((i * 10 + 1) as float32);
		texels.push((i * 10 + 2) as float32);
		texels.push((i * 10 + 3) as float32);
	}
	return { ramp: { width: 4, texels }, rampSampler: { nearest, wrap } };
}

test "a 1D texture samples nearest or linear along its line, loads a texel and reports its width" {
	const nearest = lineOf(true, Wrap.Clamp);
	assert textureSample(nearest.ramp, nearest.rampSampler, 0.25).x == 10.0;
	assert textureSample(nearest.ramp, nearest.rampSampler, 0.9).w == 33.0;
	assert textureSampleLevel(nearest.ramp, nearest.rampSampler, 0.75, 0.0).y == 31.0;
	const linear = lineOf(false, Wrap.Clamp);
	assert textureSample(linear.ramp, linear.rampSampler, 0.5).x == 15.0;
	assert textureSample(linear.ramp, linear.rampSampler, 0.0).x == 0.0;
	const repeated = lineOf(true, Wrap.Repeat);
	assert textureSample(repeated.ramp, repeated.rampSampler, 1.25).x == 10.0;
	assert textureDimensions(nearest.ramp, 0) == 4;
	assert textureLoad(nearest.ramp, 2, 0).z == 22.0;
	const out = lineFs({ position: vec4f(0.0) }, nearest);
	assert out.x == 10.0 + 31.0 && out.y == 12.0 && out.z == 4.0 && out.w == 13.0;
}

test "a 1D storage texture loads and stores a texel and reports its width" {
	const b: Strip = { strip: { width: 3, texels: [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12] } };
	assert textureDimensions(b.strip) == 3;
	stripCs({ id: { x: 1, y: 0, z: 0 } }, b);
	assert b.strip.texels[4] == 6.0 && b.strip.texels[5] == 6.0 && b.strip.texels[7] == 3.0;
	assert b.strip.texels[0] == 1.0;
}

function probePath(name: string, target: ShaderTarget, stage: string): string {
	return match (target) {
		ShaderTarget.Wgsl => "out/wgslProbe/" + name + stage + ".wgsl",
		ShaderTarget.Hlsl5 => "out/hlslProbe/" + name + "." + (stage == "Cs" ? "cs" : "ps") + ".hlsl",
		ShaderTarget.Glsl430 => "out/glslProbe/" + name + ".430." + (stage == "Cs" ? "comp" : "frag"),
		ShaderTarget.Glsl300es => "out/glslProbe/" + name + ".es." + (stage == "Cs" ? "comp" : "frag"),
		ShaderTarget.Msl => "out/mslProbe/" + name + stage + ".metal",
		ShaderTarget.Spirv => "out/spirvProbe/" + name + stage + ".spv",
	};
}

function printedFor(m: ShaderModule, entry: int32, target: ShaderTarget, name: string,
	stage: string): string {
	const text = stageSource(m, entry, target);
	if (!text.ok) { return text.error; }
	const path = probePath(name, target, stage);
	const _out = mkdir("out");
	const _folder = mkdir(path.slice(0, path.lastIndexOf("/")));
	const _written = writeFile(path, text.value);
	return text.value;
}

function programOf(): ShaderModule {
	const m = programModule(glslIr(plainVs), glslIr(lineFs), []);
	if (!m.ok) { throw new Error("programOf: " + m.error); }
	return m.value;
}

function computeOf(): ShaderModule {
	const m = computeModule(glslComputeIr(stripCs, [8, 1, 1]), []);
	if (!m.ok) { throw new Error("computeOf: " + m.error); }
	return m.value;
}

test "GLSL 450 spells the 1D texture as texture1D and the 1D storage texture as image1D" {
	assert glsl(lineFs) ==
		"#extension GL_EXT_samplerless_texture_functions : require\n" +
		"layout(binding=0) uniform texture1D ramp;\n" +
		"layout(binding=0) uniform sampler rampSampler;\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    vec4 smooth_1 = texture(sampler1D(ramp, rampSampler), 0.25);\n" +
		"    vec4 level = textureLod(sampler1D(ramp, rampSampler), 0.75, 0.0);\n" +
		"    int size = textureSize(ramp, 0);\n" +
		"    vec4 texel = texelFetch(ramp, 1, 0);\n" +
		"    fragColor = vec4((smooth_1.x + level.y), texel.z, float(size), texel.w);\n" +
		"    return;\n" +
		"}\n";
	assert glslCompute(stripCs, [8, 1, 1]) ==
		"layout(local_size_x=8, local_size_y=1, local_size_z=1) in;\n" +
		"layout(binding=0, r32f) uniform image1D strip;\n" +
		"void main() {\n" +
		"    int x = ivec2(gl_GlobalInvocationID.xy).x;\n" +
		"    int size = imageSize(strip);\n" +
		"    vec4 seen = imageLoad(strip, x);\n" +
		"    imageStore(strip, x, vec4((seen.x + 1.0), seen.y, seen.z, float(size)));\n" +
		"}\n";
}

test "every target spells the 1D texture" {
	const m = programOf();
	assert irErrors(m).length == 0;
	const wgsl = printedFor(m, 1, ShaderTarget.Wgsl, "line", "Fs");
	assert wgsl.includes("var ramp : texture_1d<f32>;\n");
	assert wgsl.includes("var smooth_1 : vec4f = textureSample(ramp, rampSampler, 0.25f);\n");
	assert wgsl.includes("var level : vec4f = textureSampleLevel(ramp, rampSampler, 0.75f, 0f);\n");
	assert wgsl.includes("var size : i32 = i32(textureDimensions(ramp, 0i));\n");
	assert wgsl.includes("var texel : vec4f = textureLoad(ramp, 1i, 0i);\n");
	const hlsl = printedFor(m, 1, ShaderTarget.Hlsl5, "line", "Fs");
	assert hlsl.includes("Texture1D<float4> ramp : register(t0);\n");
	assert hlsl.includes("    float4 smooth = ramp.Sample(rampSampler, 0.25);\n" +
		"    float4 level = ramp.SampleLevel(rampSampler, 0.75, 0.0);\n" +
		"    int size = int(textureSize(ramp, uint(0)));\n" +
		"    float4 texel = ramp.Load(int2(1, 0));\n");
	assert hlsl.includes("    t.GetDimensions(level, width, levels);\n    return width;\n");
	const msl = printedFor(m, 1, ShaderTarget.Msl, "line", "Fs");
	assert msl.includes("texture1d<float> ramp [[texture(0)]]");
	assert msl.includes("  float4 smooth = ramp.sample(rampSampler, 0.25);\n" +
		"  float4 level_1 = ramp.sample(rampSampler, 0.75);\n" +
		"  int size = int(ramp.get_width());\n" +
		"  float4 texel = ramp.read(uint(1));\n");
	const desktop = printedFor(m, 1, ShaderTarget.Glsl430, "line", "Fs");
	assert desktop.includes("layout(binding = 0) uniform sampler1D ramp_rampSampler;\n");
	assert desktop.includes("    vec4 smooth_1 = texture(ramp_rampSampler, 0.25);\n" +
		"    vec4 level = textureLod(ramp_rampSampler, 0.75, 0.0);\n" +
		"    int size = textureSize(ramp_rampSampler, 0);\n" +
		"    vec4 texel = texelFetch(ramp_rampSampler, 1, 0);\n");
	const es = printedFor(m, 1, ShaderTarget.Glsl300es, "line", "Fs");
	assert es.includes("uniform highp sampler2D ramp_rampSampler;\n");
	assert es.includes("    highp vec4 smooth_1 = texture(ramp_rampSampler, vec2(0.25, 0.0));\n" +
		"    highp vec4 level = textureLod(ramp_rampSampler, vec2(0.75, 0.0), 0.0);\n" +
		"    highp int size = textureSize(ramp_rampSampler, 0).x;\n" +
		"    highp vec4 texel = texelFetch(ramp_rampSampler, ivec2(1, 0), 0);\n");
}

test "every target spells the 1D storage texture" {
	const m = computeOf();
	assert irErrors(m).length == 0;
	const wgsl = printedFor(m, 0, ShaderTarget.Wgsl, "strip", "Cs");
	assert wgsl.includes("var strip : texture_storage_1d<r32float, read_write>;\n");
	assert wgsl.includes("var seen : vec4f = textureLoad(strip, x);\n");
	const hlsl = printedFor(m, 0, ShaderTarget.Hlsl5, "strip", "Cs");
	assert hlsl.includes("RWTexture1D<float> strip : register(u0);\n");
	assert hlsl.includes("    int size = int(imageSize(strip));\n" +
		"    float4 seen = float4(strip[uint(x)], 0.0, 0.0, 1.0);\n" +
		"    strip[uint(x)] = float4(seen.x + 1.0, seen.y, seen.z, float(size)).x;\n");
	const gl = printedFor(m, 0, ShaderTarget.Glsl430, "strip", "Cs");
	assert gl.includes("layout(binding = 0, r32f) uniform image1D strip;\n");
	const msl = printedFor(m, 0, ShaderTarget.Msl, "strip", "Cs");
	assert msl.includes("texture1d<float, access::read_write> strip");
	assert msl.includes("  int size = int(strip.get_width());\n" +
		"  float4 seen = strip.read(uint(x));\n" +
		"  strip.write(float4((seen.x + 1.0), seen.y, seen.z, float(size)), uint(x));\n");
	const es = stageSource(m, 0, ShaderTarget.Glsl300es);
	assert !es.ok && es.error.includes("GLSL ES 3.0 has no storage"), es.ok ? "printed" : es.error;
}

test "SPIR-V declares a Dim1D image under the 1D capabilities" {
	const fs = spirvProbe(programOf(), 1, "line");
	assert fs.filter((i) => opcodeOf(i) == 25 && i[3] == 0).length == 1;
	assert fs.filter((i) => opcodeOf(i) == 17 && (i[1] == 43)).length == 1;
	const m = computeOf();
	const words = stageWords(m, 0);
	assert words.ok;
	let capabilities: uint32[] = [];
	let at = 5;
	while (at < words.value.length) {
		const count = (words.value[at] >> 16) as int32;
		if ((words.value[at] & 65535) == 17) { capabilities.push(words.value[at + 1]); }
		at += count;
	}
	assert capabilities.includes(44) && !capabilities.includes(43), capabilities.join(",");
	const _out = mkdir("out");
	const _folder = mkdir("out/spirvProbe");
	const _written = writeFile(probePath("strip", ShaderTarget.Spirv, "Cs"),
		Buffer.fromString(wordsBase64(words.value), "base64"));
}

test "reflection refuses a 1D view by name until the door can name one" {
	const r = reflectProgram(programOf(), 0, 1, ShaderTarget.Wgsl);
	assert !r.ok && r.error.includes("D1 is no GPUTextureViewDimension"), r.ok ? "reflected" : r.error;
	const c = reflectCompute(computeOf(), 0, ShaderTarget.Wgsl);
	assert !c.ok && c.error.includes("D1 is no GPUTextureViewDimension"), c.ok ? "reflected" : c.error;
}

test "a 1D texture takes no offset, bias or derivative sample, as WGSL's" {
	let m = programOf();
	const body = m.functions[m.entries[1].functionIndex].body;
	const sampled = body.filter((s) => s.expr.intrinsic == Intrinsic.TextureSampleLevel)[0].expr;
	sampled.intrinsic = Intrinsic.TextureSampleBias;
	assert irErrors(m).some((e) => e.includes("TextureSampleBias of a D1 texture"));
}
