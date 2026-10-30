// WGSL's core storage texel formats  authored in MetaScript: the channel
// type of a format (f32, u32, i32) is the texel type textureLoad returns and textureStore takes,
// and
// each channel type has its own storage texture struct. Each entry runs on the CPU, is pinned as
// GLSL
// and is printed for every target into out/<target>Probe/ for scripts/validateWgsl.sh,
// scripts/validateHlsl.sh and spirv-val.

import { mkdir, writeFile } from "std/fs";
import { Buffer } from "std/core/buffer";
import { computeModule, stageSource, stageWords, wordsBase64 } from "../shader/descriptor";
import { glslCompute, glslComputeIr } from "../shader/emit";
import {
	Intrinsic,
	ScalarKind,
	ShaderModule,
	TexelFormat,
	irErrors,
	vectorType,
} from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import { reflectCompute } from "../shader/reflect";
import { opcodeOf } from "./shaderProbeModules";
import {
	StorageTexture2d,
	StorageTexture2dArrayI32,
	StorageTexture2dArrayU32,
	StorageTexture2dI32,
	StorageTexture2dU32,
	StorageTexture3dI32,
	Vec3u,
	access,
	binding,
	builtin,
	format,
	textureDimensions,
	textureLoad,
	textureStore,
	vec2i,
	vec2u,
	vec3i,
	vec4f,
	vec4i,
	vec4u,
} from "../shader/std";

export struct Ids {
	@builtin(globalInvocationId) id: Vec3u;
}

export struct UnsignedImages {
	@binding(0) @format(r32uint) @access(read_write) counts: StorageTexture2dU32;
	@binding(1) @format(rgba16uint) @access(write) wide: StorageTexture2dU32;
	@binding(2) @format(rg32uint) @access(write) pairs: StorageTexture2dU32;
	@binding(3) @format(rgba32uint) @access(write) full: StorageTexture2dU32;
	@binding(4) @format(rgba8uint) @access(write) bytes: StorageTexture2dArrayU32;
}

export function unsignedCs(input: Ids, b: UnsignedImages): void {
	const at = vec2i(input.id.xy);
	const size = textureDimensions(b.wide);
	const seen = textureLoad(b.counts, at);
	textureStore(b.counts, at, vec4u(seen.x + 1, 0, 0, 0));
	textureStore(b.wide, at, vec4u(seen.x, seen.y + 7, 3, vec2u(size).x));
	textureStore(b.pairs, at, vec4u(seen.x * 2, 5, 0, 0));
	textureStore(b.full, at, vec4u(seen.x, seen.x, seen.x, seen.x));
	textureStore(b.bytes, at, 1, vec4u(255, 0, 0, 0));
}

export struct SignedImages {
	@binding(0) @format(r32sint) @access(read_write) levels: StorageTexture2dI32;
	@binding(1) @format(rgba8sint) @access(write) small: StorageTexture3dI32;
	@binding(2) @format(rgba16sint) @access(write) mid: StorageTexture2dI32;
	@binding(3) @format(rg32sint) @access(write) pairs: StorageTexture2dI32;
	@binding(4) @format(rgba32sint) @access(write) full: StorageTexture2dArrayI32;
}

export function signedCs(input: Ids, b: SignedImages): void {
	const at = vec2i(input.id.xy);
	const seen = textureLoad(b.levels, at);
	textureStore(b.levels, at, vec4i(seen.x - 1, 0, 0, 0));
	textureStore(b.small, vec3i(at.x, at.y, 0), vec4i(seen.x, -128, 127, 1));
	textureStore(b.mid, at, vec4i(seen.x, seen.x * 2, -32768, 32767));
	textureStore(b.pairs, at, vec4i(seen.x, -seen.x, 0, 0));
	textureStore(b.full, at, 0, vec4i(seen.x, 0, 0, 0));
}

export struct SwizzledImages {
	@binding(0) @format(bgra8unorm) @access(write) image: StorageTexture2d;
}

export function swizzledCs(input: Ids, b: SwizzledImages): void {
	textureStore(b.image, vec2i(input.id.xy), vec4f(1.0, 0.0, 0.0, 1.0));
}

function unsignedImages(): UnsignedImages {
	return {
		counts: { width: 2, height: 1, texels: [4, 0, 0, 0, 5, 0, 0, 0] },
		wide: { width: 2, height: 1, texels: [0, 0, 0, 0, 0, 0, 0, 0] },
		pairs: { width: 2, height: 1, texels: [0, 0, 0, 0, 0, 0, 0, 0] },
		full: { width: 2, height: 1, texels: [0, 0, 0, 0, 0, 0, 0, 0] },
		bytes: { width: 2, height: 1, layers: 2,
		texels: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0] },
	};
}

function signedImages(): SignedImages {
	return {
		levels: { width: 2, height: 1, texels: [-4, 0, 0, 0, -5, 0, 0, 0] },
		small: { width: 2, height: 1, depth: 1, texels: [0, 0, 0, 0, 0, 0, 0, 0] },
		mid: { width: 2, height: 1, texels: [0, 0, 0, 0, 0, 0, 0, 0] },
		pairs: { width: 2, height: 1, texels: [0, 0, 0, 0, 0, 0, 0, 0] },
		full: { width: 2, height: 1, layers: 1, texels: [0, 0, 0, 0, 0, 0, 0, 0] },
	};
}

test "an unsigned storage texture loads and stores a Vec4u, a texel of four uint32" {
	const b = unsignedImages();
	unsignedCs({ id: { x: 1, y: 0, z: 0 } }, b);
	assert b.counts.texels[4] == 6 && b.counts.texels[0] == 4;
	assert b.wide.texels[4] == 5 && b.wide.texels[5] == 7 && b.wide.texels[7] == 2;
	assert b.pairs.texels[4] == 10 && b.pairs.texels[5] == 5;
	assert b.full.texels[7] == 5;
	assert b.bytes.texels[8 + 4] == 255;
}

test "a signed storage texture loads and stores a Vec4i, a texel of four int32" {
	const b = signedImages();
	signedCs({ id: { x: 1, y: 0, z: 0 } }, b);
	assert b.levels.texels[4] == -6 && b.levels.texels[0] == -4;
	assert b.small.texels[4] == -5 && b.small.texels[5] == -128 && b.small.texels[6] == 127;
	assert b.mid.texels[5] == -10 && b.mid.texels[6] == -32768;
	assert b.pairs.texels[4] == -5 && b.pairs.texels[5] == 5;
	assert b.full.texels[4] == -5;
}

function probePath(target: ShaderTarget, name: string): string {
	return match (target) {
		ShaderTarget.Wgsl => "out/wgslProbe/" + name + ".wgsl",
		ShaderTarget.Hlsl5 => "out/hlslProbe/" + name + ".cs.hlsl",
		ShaderTarget.Glsl430 => "out/glslProbe/" + name + ".430.comp",
		ShaderTarget.Glsl300es => "out/glslProbe/" + name + ".es.comp",
		ShaderTarget.Msl => "out/mslProbe/" + name + ".metal",
		ShaderTarget.Spirv => "out/spirvProbe/" + name + ".spv",
	};
}

function printedFor(m: ShaderModule, target: ShaderTarget, name: string): string {
	const text = stageSource(m, 0, target);
	if (!text.ok) { return text.error; }
	const path = probePath(target, name);
	const _out = mkdir("out");
	const _folder = mkdir(path.slice(0, path.lastIndexOf("/")));
	const _written = writeFile(path, text.value);
	return text.value;
}

function computeOf(text: string): ShaderModule {
	const m = computeModule(text, []);
	if (!m.ok) { throw new Error("computeOf: " + m.error); }
	return m.value;
}

function spirvOf(m: ShaderModule, name: string): uint32[][] {
	const printed = stageWords(m, 0);
	if (!printed.ok) { throw new Error(name + " prints no SPIR-V: " + printed.error); }
	const words = printed.value;
	const _out = mkdir("out");
	const _folder = mkdir("out/spirvProbe");
	const _written = writeFile(probePath(ShaderTarget.Spirv, name),
		Buffer.fromString(wordsBase64(words), "base64"));
	let out: uint32[][] = [];
	let at = 5;
	while (at < words.length) {
		const count = (words[at] >> 16) as int32;
		out.push(words.slice(at, at + count));
		at += count;
	}
	return out;
}

test "GLSL 430 spells each format's qualifier and the image of its channel type" {
	assert glslCompute(unsignedCs, [8, 1, 1]) ==
		"layout(local_size_x=8, local_size_y=1, local_size_z=1) in;\n" +
		"layout(binding=0, r32ui) uniform uimage2D counts;\n" +
		"layout(binding=1, rgba16ui) uniform writeonly uimage2D wide;\n" +
		"layout(binding=2, rg32ui) uniform writeonly uimage2D pairs;\n" +
		"layout(binding=3, rgba32ui) uniform writeonly uimage2D full;\n" +
		"layout(binding=4, rgba8ui) uniform writeonly uimage2DArray bytes;\n" +
		"void main() {\n" +
		"    ivec2 at = ivec2(gl_GlobalInvocationID.xy);\n" +
		"    ivec2 size = imageSize(wide);\n" +
		"    uvec4 seen = imageLoad(counts, at);\n" +
		"    imageStore(counts, at, uvec4((seen.x + 1), 0, 0, 0));\n" +
		"    imageStore(wide, at, uvec4(seen.x, (seen.y + 7), 3, uvec2(size).x));\n" +
		"    imageStore(pairs, at, uvec4((seen.x * 2), 5, 0, 0));\n" +
		"    imageStore(full, at, uvec4(seen.x, seen.x, seen.x, seen.x));\n" +
		"    imageStore(bytes, ivec3(at, 1), uvec4(255, 0, 0, 0));\n" +
		"}\n";
	assert glslCompute(signedCs, [8, 1, 1]) ==
		"layout(local_size_x=8, local_size_y=1, local_size_z=1) in;\n" +
		"layout(binding=0, r32i) uniform iimage2D levels;\n" +
		"layout(binding=1, rgba8i) uniform writeonly iimage3D small;\n" +
		"layout(binding=2, rgba16i) uniform writeonly iimage2D mid;\n" +
		"layout(binding=3, rg32i) uniform writeonly iimage2D pairs;\n" +
		"layout(binding=4, rgba32i) uniform writeonly iimage2DArray full;\n" +
		"void main() {\n" +
		"    ivec2 at = ivec2(gl_GlobalInvocationID.xy);\n" +
		"    ivec4 seen = imageLoad(levels, at);\n" +
		"    imageStore(levels, at, ivec4((seen.x - 1), 0, 0, 0));\n" +
		"    imageStore(small, ivec3(at.x, at.y, 0), ivec4(seen.x, -128, 127, 1));\n" +
		"    imageStore(mid, at, ivec4(seen.x, (seen.x * 2), -32768, 32767));\n" +
		"    imageStore(pairs, at, ivec4(seen.x, (-seen.x), 0, 0));\n" +
		"    imageStore(full, ivec3(at, 0), ivec4(seen.x, 0, 0, 0));\n" +
		"}\n";
}

test "every target spells the unsigned formats" {
	const m = computeOf(glslComputeIr(unsignedCs, [8, 1, 1]));
	assert irErrors(m).length == 0;
	const wgsl = printedFor(m, ShaderTarget.Wgsl, "unsignedFormats");
	assert wgsl.includes("var counts : texture_storage_2d<r32uint, read_write>;\n");
	assert wgsl.includes("var wide : texture_storage_2d<rgba16uint, write>;\n");
	assert wgsl.includes("var pairs : texture_storage_2d<rg32uint, write>;\n");
	assert wgsl.includes("var full : texture_storage_2d<rgba32uint, write>;\n");
	assert wgsl.includes("var bytes : texture_storage_2d_array<rgba8uint, write>;\n");
	assert wgsl.includes("var seen : vec4u = textureLoad(counts, at);\n");
	const hlsl = printedFor(m, ShaderTarget.Hlsl5, "unsignedFormats");
	assert hlsl.includes("RWTexture2D<uint> counts : register(u0);\n");
	assert hlsl.includes("RWTexture2D<uint4> wide : register(u1);\n");
	assert hlsl.includes("RWTexture2D<uint2> pairs : register(u2);\n");
	assert hlsl.includes("RWTexture2D<uint4> full : register(u3);\n");
	assert hlsl.includes("RWTexture2DArray<uint4> bytes : register(u4);\n");
	assert hlsl.includes("uint4 seen = uint4(counts[uint2(at)], 0u, 0u, 1u);\n");
	assert hlsl.includes("pairs[uint2(at)] = uint4(seen.x * 2u, 5u, 0u, 0u).xy;\n");
	assert hlsl.includes("counts[uint2(at)] = uint4(seen.x + 1u, 0u, 0u, 0u).x;\n");
	const gl = printedFor(m, ShaderTarget.Glsl430, "unsignedFormats");
	assert gl.includes("layout(binding = 4, rgba8ui) uniform writeonly uimage2DArray bytes;\n");
	assert gl.includes("uvec4 seen = imageLoad(counts, at);\n");
	const msl = printedFor(m, ShaderTarget.Msl, "unsignedFormats");
	assert msl.includes("texture2d<uint, access::read_write> counts");
	assert msl.includes("texture2d<uint, access::write> wide");
	assert msl.includes("texture2d_array<uint, access::write> bytes");
	assert msl.includes("uint4 seen = counts.read(uint2(at));\n");
	const es = stageSource(m, 0, ShaderTarget.Glsl300es);
	assert !es.ok && es.error.includes("GLSL ES 3.0 has no storage"), es.ok ? "printed" : es.error;
}

test "every target spells the signed formats" {
	const m = computeOf(glslComputeIr(signedCs, [8, 1, 1]));
	assert irErrors(m).length == 0;
	const wgsl = printedFor(m, ShaderTarget.Wgsl, "signedFormats");
	assert wgsl.includes("var levels : texture_storage_2d<r32sint, read_write>;\n");
	assert wgsl.includes("var small : texture_storage_3d<rgba8sint, write>;\n");
	assert wgsl.includes("var mid : texture_storage_2d<rgba16sint, write>;\n");
	assert wgsl.includes("var pairs : texture_storage_2d<rg32sint, write>;\n");
	assert wgsl.includes("var full : texture_storage_2d_array<rgba32sint, write>;\n");
	assert wgsl.includes("var seen : vec4i = textureLoad(levels, at);\n");
	const hlsl = printedFor(m, ShaderTarget.Hlsl5, "signedFormats");
	assert hlsl.includes("RWTexture2D<int> levels : register(u0);\n" +
		"RWTexture3D<int4> small : register(u1);\n" +
		"RWTexture2D<int4> mid : register(u2);\n" +
		"RWTexture2D<int2> pairs : register(u3);\n" +
		"RWTexture2DArray<int4> full : register(u4);\n");
	assert hlsl.includes("int4 seen = int4(levels[uint2(at)], 0, 0, 1);\n");
	const gl = printedFor(m, ShaderTarget.Glsl430, "signedFormats");
	assert gl.includes("layout(binding = 0, r32i) uniform iimage2D levels;\n");
	assert gl.includes("ivec4 seen = imageLoad(levels, at);\n");
	const msl = printedFor(m, ShaderTarget.Msl, "signedFormats");
	assert msl.includes("texture3d<int, access::write> small");
	assert msl.includes("int4 seen = levels.read(uint2(at));\n");
}

test "bgra8unorm prints where the target names it and is refused by name where it cannot" {
	const m = computeOf(glslComputeIr(swizzledCs, [8, 1, 1]));
	assert irErrors(m).length == 0;
	const wgsl = printedFor(m, ShaderTarget.Wgsl, "swizzledFormat");
	assert wgsl.includes("var image : texture_storage_2d<bgra8unorm, write>;\n");
	const hlsl = printedFor(m, ShaderTarget.Hlsl5, "swizzledFormat");
	assert hlsl.includes("RWTexture2D<unorm float4> image : register(u0);\n");
	const msl = printedFor(m, ShaderTarget.Msl, "swizzledFormat");
	assert msl.includes("texture2d<float, access::write> image");
	const gl = stageSource(m, 0, ShaderTarget.Glsl430);
	assert !gl.ok && gl.error.includes("bgra8unorm has no GLSL image format"),
		gl.ok ? "printed" : gl.error;
}

test "SPIR-V names each format, its sampled type and the capability it needs" {
	const unsigned = spirvOf(computeOf(glslComputeIr(unsignedCs, [8, 1, 1])), "unsignedFormats");
	const images = unsigned.filter((i) => opcodeOf(i) == 25);
	const formats = images.map((i) => i[8]);
	assert formats.includes(33) && formats.includes(31) && formats.includes(35) &&
		formats.includes(30) && formats.includes(32), formats.join(",");
	assert unsigned.some((i) => opcodeOf(i) == 17 && i[1] == 49);
	const signed = spirvOf(computeOf(glslComputeIr(signedCs, [8, 1, 1])), "signedFormats");
	const signedFormats = signed.filter((i) => opcodeOf(i) == 25).map((i) => i[8]);
	assert signedFormats.includes(24) && signedFormats.includes(23) && signedFormats.includes(22) &&
		signedFormats.includes(25) && signedFormats.includes(21), signedFormats.join(",");
	const swizzled = spirvOf(computeOf(glslComputeIr(swizzledCs, [8, 1, 1])), "swizzledFormat");
	assert swizzled.filter((i) => opcodeOf(i) == 25).map((i) => i[8]).includes(0);
	assert swizzled.some((i) => opcodeOf(i) == 17 && i[1] == 56);
}

function reflectedFormat(format: TexelFormat): string {
	let m = computeOf(glslComputeIr(swizzledCs, [8, 1, 1]));
	m.resources[0].type.format = format;
	const r = reflectCompute(m, 0, ShaderTarget.Wgsl);
	if (!r.ok) { return r.error; }
	const name: string = r.value.bindings[0].storageFormat;
	return name;
}

test "reflection names the GPUTextureFormat of each storage format the door's type holds" {
	assert reflectedFormat(TexelFormat.Rgba8unorm) == "rgba8unorm";
	assert reflectedFormat(TexelFormat.Rgba8uint) == "rgba8uint";
	assert reflectedFormat(TexelFormat.Rgba8sint) == "rgba8sint";
	assert reflectedFormat(TexelFormat.Rgba16uint) == "rgba16uint";
	assert reflectedFormat(TexelFormat.Rgba16float) == "rgba16float";
	assert reflectedFormat(TexelFormat.Rgba32uint) == "rgba32uint";
	assert reflectedFormat(TexelFormat.Rgba32float) == "rgba32float";
	assert reflectedFormat(TexelFormat.R32float) == "r32float";
	assert reflectedFormat(TexelFormat.R32uint) == "r32uint";
	assert reflectedFormat(TexelFormat.Rg32float) == "rg32float";
	assert reflectedFormat(TexelFormat.Bgra8unorm) == "bgra8unorm";
}

test "a storage format GPUTextureFormat lacks is refused by name" {
	assert reflectedFormat(TexelFormat.Rgba8snorm) ==
		"storage texture 'image': Rgba8snorm is no GPUTextureFormat";
	assert reflectedFormat(TexelFormat.Rgba16sint) ==
		"storage texture 'image': Rgba16sint is no GPUTextureFormat";
	assert reflectedFormat(TexelFormat.Rgba32sint) ==
		"storage texture 'image': Rgba32sint is no GPUTextureFormat";
	assert reflectedFormat(TexelFormat.R32sint) ==
		"storage texture 'image': R32sint is no GPUTextureFormat";
	assert reflectedFormat(TexelFormat.Rg32uint) ==
		"storage texture 'image': Rg32uint is no GPUTextureFormat";
	assert reflectedFormat(TexelFormat.Rg32sint) ==
		"storage texture 'image': Rg32sint is no GPUTextureFormat";
}

test "a texel of another channel type than the format's is refused by name" {
	let m = computeOf(glslComputeIr(unsignedCs, [8, 1, 1]));
	const body = m.functions[m.entries[0].functionIndex].body;
	const loaded = body.filter((s) => s.expr.intrinsic == Intrinsic.TextureLoad)[0].expr;
	loaded.type = vectorType(ScalarKind.F32, 4);
	const stored = body.filter((s) => s.expr.intrinsic == Intrinsic.TextureStore)[0].expr;
	stored.operands[stored.operands.length - 1].type = vectorType(ScalarKind.I32, 4);
	const errors = irErrors(m);
	assert errors.includes("function 'unsignedCs': TextureLoad of a R32uint storage texture " +
		"takes a vec4 of U32, as WGSL's"), errors.join("|");
	assert errors.includes("function 'unsignedCs': TextureStore of a R32uint storage texture " +
		"takes a vec4 of U32, as WGSL's"), errors.join("|");
}
