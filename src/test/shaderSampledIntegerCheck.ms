// WGSL's texture_2d_array and texture_3d of u32 and i32 texels beside texture_2d: textureLoad
// returns vec4u or vec4i, and no sampling builtin takes them. Each entry runs on the CPU, is pinned
// as GLSL and printed for every target into out/<target>Probe/ for scripts/validateWgsl.sh,
// scripts/validateHlsl.sh, naga and spirv-val.

import { mkdir, writeFile } from "std/fs";
import { programModule, stageSource } from "../shader/descriptor";
import { glsl, glslIr } from "../shader/emit";
import { ShaderModule, irErrors } from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import { reflectProgram } from "../shader/reflect";
import { opcodeOf, spirvProbe } from "./shaderProbeModules";
import {
	Texture2dArrayI32,
	Texture2dArrayU32,
	Texture2dU32,
	Texture3dI32,
	Texture3dU32,
	Vec2f,
	Vec4f,
	binding,
	builtin,
	textureLoad,
	vec2i,
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

export struct Integers {
	@binding(0) plain: Texture2dU32;
	@binding(1) layersU: Texture2dArrayU32;
	@binding(2) layersI: Texture2dArrayI32;
	@binding(3) gridU: Texture3dU32;
	@binding(4) gridI: Texture3dI32;
}

export function plainVs(input: Corner): Placed {
	return { clip: vec4f(input.position.x, input.position.y, 0.0, 1.0) };
}

export function integerFs(input: Pixel, b: Integers): Vec4f {
	const plainTexel = textureLoad(b.plain, vec2i(1, 0), 0);
	const unsignedLayer = textureLoad(b.layersU, vec2i(1, 0), 1, 0);
	const signedLayer = textureLoad(b.layersI, vec2i(0, 1), 0, 0);
	const unsignedCell = textureLoad(b.gridU, vec3i(1, 1, 0), 0);
	const signedCell = textureLoad(b.gridI, vec3i(0, 1, 1), 0);
	return vec4f(vec4f(unsignedLayer).x + vec4f(signedLayer).y, vec4f(unsignedCell).z,
		vec4f(signedCell).w, vec4f(plainTexel).x);
}

function counted(count: int32): uint32[] {
	let texels: uint32[] = [];
	for (let i = 0; i < count; i++) { texels.push(i as uint32); }
	return texels;
}

function signed(count: int32): int32[] {
	let texels: int32[] = [];
	for (let i = 0; i < count; i++) { texels.push(i * 3 - 40); }
	return texels;
}

function integers(): Integers {
	return {
		plain: { width: 2, height: 2, texels: counted(16) },
		layersU: { width: 2, height: 2, layers: 2, texels: counted(32) },
		layersI: { width: 2, height: 2, layers: 2, texels: signed(32) },
		gridU: { width: 2, height: 2, depth: 2, texels: counted(32) },
		gridI: { width: 2, height: 2, depth: 2, texels: signed(32) },
	};
}

test "an array and a 3D texture of integer texels load a texel as vec4u or vec4i" {
	const b = integers();
	const layer = textureLoad(b.layersU, vec2i(1, 0), 1, 0);
	assert layer.x == 20 && layer.y == 21 && layer.z == 22 && layer.w == 23;
	const signedLayer = textureLoad(b.layersI, vec2i(0, 1), 0, 0);
	assert signedLayer.x == -16 && signedLayer.y == -13;
	const cell = textureLoad(b.gridU, vec3i(1, 1, 0), 0);
	assert cell.x == 12 && cell.z == 14;
	const signedCell = textureLoad(b.gridI, vec3i(0, 1, 1), 0);
	assert signedCell.x == 32 && signedCell.w == 41;
	const out = integerFs({ position: vec4f(0.0) }, b);
	assert out.x == 7.0 && out.y == 14.0 && out.z == 41.0 && out.w == 4.0;
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
	const m = programModule(glslIr(plainVs), glslIr(integerFs), []);
	if (!m.ok) { throw new Error("programOf: " + m.error); }
	return m.value;
}

test "GLSL 450 spells each integer texture with its channel type and fetches by layer or depth" {
	assert glsl(integerFs) ==
		"#extension GL_EXT_samplerless_texture_functions : require\n" +
		"@image_sample_type plain uint\n" +
		"layout(binding=0) uniform utexture2D plain;\n" +
		"@image_sample_type layersU uint\n" +
		"layout(binding=1) uniform utexture2DArray layersU;\n" +
		"@image_sample_type layersI sint\n" +
		"layout(binding=2) uniform itexture2DArray layersI;\n" +
		"@image_sample_type gridU uint\n" +
		"layout(binding=3) uniform utexture3D gridU;\n" +
		"@image_sample_type gridI sint\n" +
		"layout(binding=4) uniform itexture3D gridI;\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    uvec4 plainTexel = texelFetch(plain, ivec2(1, 0), 0);\n" +
		"    uvec4 unsignedLayer = texelFetch(layersU, ivec3(ivec2(1, 0), 1), 0);\n" +
		"    ivec4 signedLayer = texelFetch(layersI, ivec3(ivec2(0, 1), 0), 0);\n" +
		"    uvec4 unsignedCell = texelFetch(gridU, ivec3(1, 1, 0), 0);\n" +
		"    ivec4 signedCell = texelFetch(gridI, ivec3(0, 1, 1), 0);\n" +
		"    fragColor = vec4((vec4(unsignedLayer).x + vec4(signedLayer).y), vec4(unsignedCell).z, " +
		"vec4(signedCell).w, vec4(plainTexel).x);\n" +
		"    return;\n" +
		"}\n";
}

test "every target spells the integer array and 3D textures" {
	const m = programOf();
	assert irErrors(m).length == 0;
	const wgsl = printedFor(m, 1, ShaderTarget.Wgsl, "sampledInteger");
	assert wgsl.includes("var plain : texture_2d<u32>;\n");
	assert wgsl.includes("var layersU : texture_2d_array<u32>;\n");
	assert wgsl.includes("var layersI : texture_2d_array<i32>;\n");
	assert wgsl.includes("var gridU : texture_3d<u32>;\n");
	assert wgsl.includes("var gridI : texture_3d<i32>;\n");
	assert wgsl.includes("var unsignedLayer : vec4u = textureLoad(layersU, vec2i(1i, 0i), 1i, 0i);\n");
	assert wgsl.includes("var signedCell : vec4i = textureLoad(gridI, vec3i(0i, 1i, 1i), 0i);\n");
	const hlsl = printedFor(m, 1, ShaderTarget.Hlsl5, "sampledInteger");
	assert hlsl.includes("Texture2D<uint4> plain : register(t0);\n");
	assert hlsl.includes("Texture2DArray<uint4> layersU : register(t1);\n");
	assert hlsl.includes("Texture2DArray<int4> layersI : register(t2);\n");
	assert hlsl.includes("Texture3D<uint4> gridU : register(t3);\n");
	assert hlsl.includes("Texture3D<int4> gridI : register(t4);\n");
	assert hlsl.includes("uint4 unsignedLayer = layersU.Load(int4(int2(1, 0), 1, 0));\n");
	assert hlsl.includes("int4 signedCell = gridI.Load(int4(int3(0, 1, 1), 0));\n");
	const msl = printedFor(m, 1, ShaderTarget.Msl, "sampledInteger");
	assert msl.includes("texture2d_array<uint> layersU [[texture(1)]]");
	assert msl.includes("texture3d<int> gridI [[texture(4)]]");
	assert msl.includes("uint4 unsignedLayer = layersU.read(uint2(int2(1, 0)), uint(1), uint(0));\n");
	for (const target of [ShaderTarget.Glsl430, ShaderTarget.Glsl300es]) {
		const gl = printedFor(m, 1, target, "sampledInteger");
		assert gl.includes(" usampler2DArray layersU_SPIRV_Cross_DummySampler;\n");
		assert gl.includes(" isampler3D gridI_SPIRV_Cross_DummySampler;\n");
		assert gl.includes("uvec4 unsignedLayer = texelFetch(layersU_SPIRV_Cross_DummySampler, " +
			"ivec3(ivec2(1, 0), 1), 0);\n");
		assert gl.includes("ivec4 signedCell = texelFetch(gridI_SPIRV_Cross_DummySampler, " +
			"ivec3(0, 1, 1), 0);\n");
	}
}

test "reflection reports the sample type and view dimension of each integer texture" {
	const r = reflectProgram(programOf(), 0, 1, ShaderTarget.Wgsl);
	assert r.ok;
	const textures = r.value.bindings.filter((b) => b.kind == "texture");
	assert textures.map((b) => b.viewDimension + ":" + b.sampleType).join("|") ==
		":uint|2d-array:uint|2d-array:sint|3d:uint|3d:sint";
}

test "SPIR-V declares each integer image and fetches it" {
	const fs = spirvProbe(programOf(), 1, "sampledInteger");
	assert fs.filter((i) => opcodeOf(i) == 25).length >= 5;
	assert fs.filter((i) => opcodeOf(i) == 95).length == 5;
}
