// WGSL's texture_multisampled_2d<f32> with textureLoad(t, coords, sample_index),
// textureDimensions(t)
// and textureNumSamples(t): each entry runs on the CPU, is pinned as GLSL and printed for every
// target into out/<target>Probe/ for scripts/validateWgsl.sh, scripts/validateHlsl.sh and
// spirv-val.

import { mkdir, writeFile } from "std/fs";
import { programModule, stageSource } from "../shader/descriptor";
import { glsl, glslIr } from "../shader/emit";
import { Intrinsic, ShaderModule, irErrors } from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import { reflectProgram } from "../shader/reflect";
import { opcodeOf, spirvProbe } from "./shaderProbeModules";
import {
	TextureMultisampled2d,
	Vec2f,
	Vec4f,
	binding,
	builtin,
	textureDimensions,
	textureLoad,
	textureNumSamples,
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

export struct Targets {
	@binding(0) scene: TextureMultisampled2d;
}

export function quadVs(input: Corner): Placed {
	return { clip: vec4f(input.position.x, input.position.y, 0.0, 1.0) };
}

export function resolveFs(input: Pixel, b: Targets): Vec4f {
	const size = textureDimensions(b.scene);
	const count = textureNumSamples(b.scene);
	const first = textureLoad(b.scene, vec2i(1, 0), 0);
	const last = textureLoad(b.scene, vec2i(size.x - 1, 0), count - 1);
	return vec4f(first.x, last.x, (size.y + count) as float32, 1.0);
}

function scene(): TextureMultisampled2d {
	let texels: float32[] = [];
	for (let s = 0; s < 4; s++) {
		for (let x = 0; x < 2; x++) {
			texels.push((s * 10 + x) as float32);
			texels.push(0.0);
			texels.push(0.0);
			texels.push(1.0);
		}
	}
	return { width: 2, height: 1, samples: 4, texels };
}

test "a multisampled texture loads each sample of a texel and reports its size and sample count" {
	const t = scene();
	assert textureNumSamples(t) == 4;
	assert textureDimensions(t).x == 2 && textureDimensions(t).y == 1;
	assert textureLoad(t, vec2i(0, 0), 0).x == 0.0;
	assert textureLoad(t, vec2i(1, 0), 0).x == 1.0;
	assert textureLoad(t, vec2i(0, 0), 2).x == 20.0;
	assert textureLoad(t, vec2i(1, 0), 3).x == 31.0;
	assert textureLoad(t, vec2i(1, 0), 3).w == 1.0;
	const out = resolveFs({ position: vec4f(0.0, 0.0, 0.0, 1.0) }, { scene: t });
	assert out.x == 1.0 && out.y == 31.0 && out.z == 5.0;
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
	const m = programModule(glslIr(quadVs), glslIr(resolveFs), []);
	if (!m.ok) { throw new Error("programOf: " + m.error); }
	return m.value;
}

test "GLSL 450 spells the multisampled texture as texture2DMS, its fetch and its queries" {
	assert glsl(resolveFs) ==
		"#extension GL_EXT_samplerless_texture_functions : require\n" +
		"@image_sample_type scene unfilterable_float\n" +
		"layout(binding=0) uniform texture2DMS scene;\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    ivec2 size = textureSize(scene);\n" +
		"    int count = textureSamples(scene);\n" +
		"    vec4 first = texelFetch(scene, ivec2(1, 0), 0);\n" +
		"    vec4 last = texelFetch(scene, ivec2((size.x - 1), 0), (count - 1));\n" +
		"    fragColor = vec4(first.x, last.x, float(size.y + count), 1.0);\n" +
		"    return;\n" +
		"}\n";
}

test "every target prints the multisampled fetch and queries" {
	const m = programOf();
	assert irErrors(m).length == 0;
	const wgsl = printedFor(m, 1, ShaderTarget.Wgsl, "multisampled");
	assert wgsl.includes("var scene : texture_multisampled_2d<f32>;");
	assert wgsl.includes("textureLoad(scene, vec2i(1i, 0i), 0i)");
	assert wgsl.includes("i32(textureNumSamples(scene))");
	const hlsl = printedFor(m, 1, ShaderTarget.Hlsl5, "multisampled");
	assert hlsl.includes("Texture2DMS<float4> scene");
	assert hlsl.includes("scene.Load(int2(int2(1, 0)), 0)");
	assert hlsl.includes("GetDimensions(");
	const gl = printedFor(m, 1, ShaderTarget.Glsl430, "multisampled");
	assert gl.includes("#extension GL_ARB_shader_texture_image_samples : require\n");
	assert gl.includes("sampler2DMS");
	assert gl.includes("texelFetch(scene_SPIRV_Cross_DummySampler, ivec2(1, 0), 0)");
	assert gl.includes("textureSamples(scene_SPIRV_Cross_DummySampler)");
	const msl = printedFor(m, 1, ShaderTarget.Msl, "multisampled");
	assert msl.includes("texture2d_ms<float> scene");
	assert msl.includes("scene.read(uint2(int2(1, 0)), uint(0))");
	assert msl.includes("int(scene.get_num_samples())");
}

test "GLSL ES has no multisampled sampler and refuses it by name" {
	const es = stageSource(programOf(), 1, ShaderTarget.Glsl300es);
	assert !es.ok && es.error.includes("sampler2DMS"), es.ok ? "printed" : es.error;
}

test "SPIR-V fetches the multisampled image with a Sample operand and queries its samples" {
	const fs = spirvProbe(programOf(), 1, "multisampled");
	assert fs.filter((i) => opcodeOf(i) == 95 && (i[5] & 64) != 0).length == 2;
	assert fs.filter((i) => opcodeOf(i) == 107).length == 1;
}

test "reflection reports the multisampled texture as unfilterable-float and multisampled" {
	const r = reflectProgram(programOf(), 0, 1, ShaderTarget.Wgsl);
	assert r.ok;
	const b = r.value.bindings.filter((x) => x.kind == "texture")[0];
	assert b.multisampled;
	const sampleType: string = b.sampleType;
	assert sampleType == "unfilterable-float", sampleType;
}

test "a multisampled query of the wrong shape is refused by name" {
	let bad = programOf();
	const body = bad.functions[bad.entries[1].functionIndex].body;
	const counted = body.filter((s) => s.expr.intrinsic == Intrinsic.TextureLoad)[0].expr;
	counted.operands.pop();
	assert irErrors(bad).some((e) => e.includes(
		"of a multisampled texture takes coordinates and an i32 or u32 sample index, as WGSL's"));
}
