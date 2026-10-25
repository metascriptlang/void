// A 3D texture (textureSample, textureSampleLevel, textureLoad, textureDimensions) and a texture of
// int32 texels (textureLoad returning vec4i) authored in MetaScript: each entry runs on the CPU, is
// pinned as GLSL and printed for every target into out/<target>Probe/ for scripts/validateWgsl.sh,
// scripts/validateHlsl.sh and naga's GLSL front end.

import { mkdir, writeFile } from "std/fs";
import { Wrap } from "../gpu/state";
import { programModule, stageSource } from "../shader/descriptor";
import { glsl, glslIr } from "../shader/emit";
import { ShaderModule, irErrors } from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import { reflectProgram } from "../shader/reflect";
import {
	Sampler,
	Texture2dI32,
	Texture3d,
	Vec2f,

	Vec4f,
	binding,
	builtin,
	textureDimensions,
	textureLoad,
	textureSample,
	textureSampleLevel,

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

export struct Volume {
	@binding(0) volume: Texture3d;
	@binding(1) counts: Texture2dI32;
	@binding(0) volumeSampler: Sampler;
}

export function plainVs(input: Corner): Placed {
	return { clip: vec4f(input.position.x, input.position.y, 0.0, 1.0) };
}

export function volumeFs(input: Pixel, b: Volume): Vec4f {
	const at = vec3f(0.25, 0.75, 0.5);
	const smooth = textureSample(b.volume, b.volumeSampler, at);
	const level = textureSampleLevel(b.volume, b.volumeSampler, at, 1.0);
	const size = textureDimensions(b.volume, 0);
	const texel = textureLoad(b.volume, vec3i(1, 0, 1), 0);
	const count = textureLoad(b.counts, vec2i(1, 1), 0);
	return vec4f(smooth.x + level.y, texel.z + (size.z as float32), vec4f(count).y, vec4f(count).w);
}

function volumeOf(nearest: boolean, wrap: Wrap): Volume {
	let texels: float32[] = [];
	for (let i = 0; i < 8; i++) {
		texels.push(i as float32);
		texels.push(10.0 + (i as float32));
		texels.push(20.0 + (i as float32));
		texels.push(30.0 + (i as float32));
	}
	let counts: int32[] = [];
	for (let i = 0; i < 16; i++) { counts.push(i * 3 - 5); }
	return {
		volume: { width: 2, height: 2, depth: 2, texels },
		counts: { width: 2, height: 2, texels: counts },
		volumeSampler: { nearest, wrap },
	};
}

test "a 3D texture samples nearest, or trilinear across two slices, and loads a texel" {
	const at = vec3f(0.25, 0.75, 0.5);
	const nearest = volumeOf(true, Wrap.Clamp);
	assert textureSample(nearest.volume, nearest.volumeSampler, at).x == 6.0;
	assert textureSample(nearest.volume, nearest.volumeSampler, at).w == 36.0;
	const linear = volumeOf(false, Wrap.Clamp);
	assert textureSample(linear.volume, linear.volumeSampler, at).x == 4.0;
	assert textureSample(linear.volume, linear.volumeSampler, vec3f(0.25, 0.75, 0.99)).x == 6.0;
	const repeated = volumeOf(true, Wrap.Repeat);
	assert textureSample(repeated.volume, repeated.volumeSampler, vec3f(0.25, 0.75, 1.25)).x == 2.0;
	const size = textureDimensions(nearest.volume, 0);
	assert size.x == 2 && size.y == 2 && size.z == 2;
	assert textureLoad(nearest.volume, vec3i(1, 0, 1), 0).z == 25.0;
	const out = volumeFs({ position: vec4f(0.0) }, nearest);
	assert out.x == 6.0 + 16.0;
	assert out.y == 25.0 + 2.0;
	assert out.z == 34.0;
	assert out.w == 40.0;
}

test "an int32 texture fetches signed texels" {
	const b = volumeOf(true, Wrap.Clamp);
	const first = textureLoad(b.counts, vec2i(0, 0), 0);
	assert first.x == -5 && first.w == 4;
}

function probePath(name: string, target: ShaderTarget, stage: string): string {
	return match (target) {
		ShaderTarget.Wgsl => "out/wgslProbe/" + name + stage + ".wgsl",
		ShaderTarget.Hlsl5 => "out/hlslProbe/" + name + "." + (stage == "Vs" ? "vs" : "ps") + ".hlsl",
		ShaderTarget.Glsl430 => "out/glslProbe/" + name + ".430." + (stage == "Vs" ? "vert" : "frag"),
		ShaderTarget.Glsl300es => "out/glslProbe/" + name + ".es." + (stage == "Vs" ? "vert" : "frag"),
		ShaderTarget.Msl => "out/mslProbe/" + name + stage + ".metal",
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
	const m = programModule(glslIr(plainVs), glslIr(volumeFs), []);
	if (!m.ok) { return new ShaderModule(); }
	return m.value;
}

test "GLSL 450 spells the 3D texture and the int32 texture" {
	assert glsl(volumeFs) ==
		"#extension GL_EXT_samplerless_texture_functions : require\n" +
		"layout(binding=0) uniform texture3D volume;\n" +
		"@image_sample_type counts sint\n" +
		"layout(binding=1) uniform itexture2D counts;\n" +
		"layout(binding=0) uniform sampler volumeSampler;\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    vec3 at = vec3(0.25, 0.75, 0.5);\n" +
		"    vec4 smooth_1 = texture(sampler3D(volume, volumeSampler), at);\n" +
		"    vec4 level = textureLod(sampler3D(volume, volumeSampler), at, 1.0);\n" +
		"    ivec3 size = textureSize(volume, 0);\n" +
		"    vec4 texel = texelFetch(volume, ivec3(1, 0, 1), 0);\n" +
		"    ivec4 count = texelFetch(counts, ivec2(1, 1), 0);\n" +
		"    fragColor = vec4((smooth_1.x + level.y), (texel.z + float(size.z)), vec4(count).y, vec4(count).w);\n" +
		"    return;\n" +
		"}\n";
}

test "every target spells the 3D texture and the int32 texture" {
	const m = programOf();
	assert irErrors(m).length == 0;
	const wgsl = printedFor(m, 1, ShaderTarget.Wgsl, "volume");
	assert wgsl.includes("@binding(0) @group(1) var volume : texture_3d<f32>;\n") &&
		wgsl.includes("@binding(1) @group(1) var counts : texture_2d<i32>;\n");
	assert wgsl.includes("  var smooth_1 : vec4f = textureSample(volume, volumeSampler, at);\n" +
		"  var level : vec4f = textureSampleLevel(volume, volumeSampler, at, 1f);\n" +
		"  var size : vec3i = vec3i(textureDimensions(volume, 0i));\n" +
		"  var texel : vec4f = textureLoad(volume, vec3i(1i, 0i, 1i), 0i);\n" +
		"  var count : vec4i = textureLoad(counts, vec2i(1i, 1i), 0i);\n");
	const hlsl = printedFor(m, 1, ShaderTarget.Hlsl5, "volume");
	assert hlsl.startsWith("Texture3D<float4> volume : register(t0);\n" +
		"Texture2D<int4> counts : register(t1);\n");
	assert hlsl.includes("    float4 smooth = volume.Sample(volumeSampler, at);\n" +
		"    float4 level = volume.SampleLevel(volumeSampler, at, 1.0);\n" +
		"    int3 size = int3(textureSize(volume, uint(0)));\n" +
		"    float4 texel = volume.Load(int4(int3(1, 0, 1), 0));\n" +
		"    int4 count = counts.Load(int3(int2(1, 1), 0));\n");
	for (const target of [ShaderTarget.Glsl430, ShaderTarget.Glsl300es]) {
		const gl = printedFor(m, 1, target, "volume");
		assert gl.includes(" sampler3D volume_volumeSampler;\n") &&
			gl.includes(" isampler2D counts_SPIRV_Cross_DummySampler;\n");
		assert gl.includes(" smooth_1 = texture(volume_volumeSampler, at);\n") &&
			gl.includes(" level = textureLod(volume_volumeSampler, at, 1.0);\n") &&
			gl.includes(" size = textureSize(volume_volumeSampler, 0);\n") &&
			gl.includes(" texel = texelFetch(volume_volumeSampler, ivec3(1, 0, 1), 0);\n") &&
			gl.includes(" count = texelFetch(counts_SPIRV_Cross_DummySampler, ivec2(1, 1), 0);\n");
	}
	const msl = printedFor(m, 1, ShaderTarget.Msl, "volume");
	assert msl.includes("texture3d<float> volume [[texture(0)]], texture2d<int> counts [[texture(1)]]");
	assert msl.includes("  float4 smooth = volume.sample(volumeSampler, at);\n" +
		"  float4 level_1 = volume.sample(volumeSampler, at, level(1.0));\n" +
		"  int3 size = int3(volume.get_width(uint(0)), volume.get_height(uint(0)), volume.get_depth(uint(0)));\n" +
		"  float4 texel = volume.read(uint3(int3(1, 0, 1)), uint(0));\n" +
		"  int4 count = counts.read(uint2(int2(1, 1)), uint(0));\n");
}

test "the reflection names a 3D view and a sint texture" {
	const reflected = reflectProgram(programOf(), 0, 1, ShaderTarget.Wgsl);
	assert reflected.ok;
	const texture = reflected.value.bindings.filter((b) => b.kind == "texture");
	assert texture.map((b) => b.viewDimension + ":" + b.sampleType).join("|") == "3d:float|:sint";
}
