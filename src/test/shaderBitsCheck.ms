// WGSL's bit and data-packing builtins authored in MetaScript: the CPU oracle is checked against
// the WGSL specification's values, and an entry that calls each is pinned as GLSL and printed for
// every target into out/<target>Probe/ for scripts/validateWgsl.sh, scripts/validateHlsl.sh and
// the GLSL validator.

import { mkdir, writeFile } from "std/fs";
import { programModule, stageSource } from "../shader/descriptor";
import { glslIr, glslLinked, glslLinkedIr } from "../shader/emit";
import {
	Intrinsic,
	ScalarKind,
	ShaderModule,
	StmtKind,
	irErrors,
	scalarType,
} from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import {
	Vec2f,
	Vec4f,
	abs,
	builtin,
	countOneBits,
	extractBits,
	firstLeadingBit,
	firstTrailingBit,
	insertBits,
	pack2x16float,
	pack2x16snorm,
	pack2x16unorm,
	pack4x8snorm,
	pack4x8unorm,
	reverseBits,
	unpack2x16float,
	unpack2x16snorm,
	unpack2x16unorm,
	unpack4x8snorm,
	unpack4x8unorm,
	vec2f,
	vec2i,
	vec2u,
	vec3u,
	vec4f,
} from "../shader/std";

export struct Lanes {
	@builtin(position) position: Vec4f;
	word: uint32;
	signedWord: int32;
	unit: Vec4f;
	pair: Vec2f;
}

export struct Corner {
	position: Vec2f;
}

export struct Placed {
	@builtin(position) clip: Vec4f;
	word: uint32;
	signedWord: int32;
	unit: Vec4f;
	pair: Vec2f;
}

function u(x: uint32): uint32 { return x; }

export function bitsVs(input: Corner): Placed {
	return {
		clip: vec4f(input.position.x, input.position.y, 0.0, 1.0),
		word: 61680,
		signedWord: -3,
		unit: vec4f(1.0, 0.0, 0.5, 0.2),
		pair: vec2f(0.25, -0.5),
	};
}

export function bitsFs(input: Lanes): Vec4f {
	const counted = countOneBits(input.word);
	const reversed = reverseBits(input.signedWord);
	const high = firstLeadingBit(input.signedWord);
	const low = firstTrailingBit(vec2u(input.word, 8)).y;
	const field = extractBits(input.signedWord, 4 as uint32, 8 as uint32);
	const fields = extractBits(vec3u(input.word, 7, 9), 1 as uint32, 3 as uint32);
	const placed = insertBits(input.word, 5 as uint32, 4 as uint32, 8 as uint32);
	const bytes = pack4x8unorm(input.unit) + pack4x8snorm(input.unit);
	const shorts = pack2x16unorm(input.pair) + pack2x16snorm(input.pair);
	const a = unpack4x8unorm(bytes) + unpack4x8snorm(bytes);
	const b = unpack2x16unorm(shorts) + unpack2x16snorm(shorts);
	const half = unpack2x16float(pack2x16float(input.pair));
	return vec4f(
		(counted as float32) + (reversed as float32) + (high as float32) + (low as float32),
		(field as float32) + (fields.x as float32) + (placed as float32),
		a.x + a.w + b.x + half.x,
		a.y + a.z + b.y + half.y,
	);
}

test "countOneBits, reverseBits and the first bits match the WGSL specification" {
	assert countOneBits(u(61680)) == 8 && countOneBits(u(0)) == 0 &&
		countOneBits(u(0xFFFFFFFF)) == 32;
	assert countOneBits(-1 as int32) == 32 && countOneBits(vec2u(7, 255)).y == 8;
	assert reverseBits(u(1)) == 2147483648 && reverseBits(u(0xF0)) == 251658240;
	assert reverseBits(1 as int32) == -2147483648 && reverseBits(vec2i(0, -1)).y == -1;
	assert firstLeadingBit(u(0)) == 0xFFFFFFFF && firstLeadingBit(u(1)) == 0;
	assert firstLeadingBit(u(0x80000000)) == 31 && firstLeadingBit(u(61680)) == 15;
	assert firstLeadingBit(0 as int32) == -1 && firstLeadingBit(-1 as int32) == -1;
	assert firstLeadingBit(-3 as int32) == 1 && firstLeadingBit(-8 as int32) == 2;
	assert firstLeadingBit(5 as int32) == 2 && firstLeadingBit(-2147483648 as int32) == 30;
	assert firstTrailingBit(u(0)) == 0xFFFFFFFF && firstTrailingBit(u(8)) == 3;
	assert firstTrailingBit(u(61680)) == 4 && firstTrailingBit(0 as int32) == -1;
	assert firstTrailingBit(-2147483648 as int32) == 31 && firstTrailingBit(-3 as int32) == 0;
}

test "extractBits and insertBits clamp offset and count and sign-extend an i32" {
	assert extractBits(u(61680), 4, 8) == 15 && extractBits(u(0xF0000000), 28, 100) == 15;
	assert extractBits(u(61680), 40, 5) == 0 && extractBits(u(0xFFFFFFFF), 0, 32) == 0xFFFFFFFF;
	assert extractBits(112 as int32, 4, 4) == 7 && extractBits(240 as int32, 4, 4) == -1;
	assert extractBits(-5 as int32, 0, 32) == -5 && extractBits(-5 as int32, 3, 0) == 0;
	assert extractBits(vec2u(240, 61680), 4, 4).y == 15;
	assert insertBits(u(0), u(255), 4, 4) == 240 &&
		insertBits(u(0xFFFFFFFF), u(0), 8, 8) == 4294902015;
	assert insertBits(u(7), u(99), 0, 32) == 99 && insertBits(u(7), u(99), 40, 3) == 7;
	assert insertBits(0 as int32, -1 as int32, 28, 4) == -268435456;
	assert insertBits(vec2u(0, 1), vec2u(3, 3), 1, 2).y == 7;
}

test "the pack builtins match the WGSL specification" {
	assert pack4x8unorm(vec4f(1.0, 0.0, 0.5, 0.2)) == 864026879;
	assert pack4x8unorm(vec4f(2.0, -1.0, 0.0, 0.0)) == 255;
	assert pack4x8snorm(vec4f(1.0, -1.0, 0.0, -0.5)) == 0xC100817F;
	assert pack2x16unorm(vec2f(1.0, 0.5)) == 0x8000FFFF;
	assert pack2x16snorm(vec2f(-1.0, 1.0)) == 0x7FFF8001;
	assert pack2x16float(vec2f(1.0, -2.0)) == 0xC0003C00;
	assert pack2x16float(vec2f(0.5, 65504.0)) == 0x7BFF3800;
	assert pack2x16float(vec2f(0.000000059604645, -0.0)) == 0x80000001;
	assert pack2x16float(vec2f(1.0009766, 0.00006103515625)) == 0x04003C01;
}

test "the unpack builtins match the WGSL specification" {
	const bytes = unpack4x8unorm(864026879);
	assert bytes.x == 1.0 && bytes.y == 0.0;
	assert abs(bytes.z - 128.0 / 255.0) < 0.000001 && abs(bytes.w - 51.0 / 255.0) < 0.000001;
	const signed = unpack4x8snorm(0xC100817F);
	assert signed.x == 1.0 && signed.y == -1.0 && signed.z == 0.0;
	assert abs(signed.w + 63.0 / 127.0) < 0.000001;
	assert unpack4x8snorm(0x80).x == -1.0;
	const shorts = unpack2x16unorm(0x8000FFFF);
	assert shorts.x == 1.0 && abs(shorts.y - 32768.0 / 65535.0) < 0.000001;
	const snorm = unpack2x16snorm(0x7FFF8001);
	assert snorm.x == -1.0 && snorm.y == 1.0;
	const halves = unpack2x16float(0xC0003C00);
	assert halves.x == 1.0 && halves.y == -2.0;
	assert unpack2x16float(0x7BFF3800).x == 0.5 && unpack2x16float(0x7BFF3800).y == 65504.0;
	assert unpack2x16float(1).x == 0.000000059604645;
}

test "the entry runs on the CPU" {
	const out = bitsFs({
		position: vec4f(0.0),
		word: 61680,
		signedWord: -3,
		unit: vec4f(1.0, 0.0, 0.5, 0.2),
		pair: vec2f(0.25, -0.5),
	});
	assert out.x == 8.0 + (reverseBits(-3 as int32) as float32) + 1.0 + 3.0;
	assert out.y == 61519.0;
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
	const m = programModule(glslIr(bitsVs), glslLinkedIr(bitsFs, bitsVs), []);
	if (!m.ok) { return new ShaderModule(); }
	return m.value;
}

export struct Halves {
	@builtin(position) position: Vec4f;
	pair: Vec2f;
}

export struct PlacedHalves {
	@builtin(position) clip: Vec4f;
	pair: Vec2f;
}

export function halvesVs(input: Corner): PlacedHalves {
	return { clip: vec4f(input.position.x, input.position.y, 0.0, 1.0), pair: vec2f(0.25, -0.5) };
}

export function halvesFs(input: Halves): Vec4f {
	const shorts = pack2x16unorm(input.pair) + pack2x16snorm(input.pair) +
		pack2x16float(input.pair);
	const a = unpack2x16unorm(shorts) + unpack2x16snorm(shorts) + unpack2x16float(shorts);
	return vec4f(a.x, a.y, 0.0, 1.0);
}

function halvesOf(): ShaderModule {
	const m = programModule(glslIr(halvesVs), glslLinkedIr(halvesFs, halvesVs), []);
	if (!m.ok) { return new ShaderModule(); }
	return m.value;
}

test "GLSL 450 spells the bit and pack builtins" {
	assert glslLinked(bitsFs, bitsVs) ==
		"flat in uint word;\n" +
		"flat in int signedWord;\n" +
		"in vec4 unit;\n" +
		"in vec2 pair;\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"void main() {\n" +
		"    uint counted = uint(bitCount(word));\n" +
		"    int reversed = bitfieldReverse(signedWord);\n" +
		"    int high = findMSB(signedWord);\n" +
		"    uint low = uvec2(findLSB(uvec2(word, 8))).y;\n" +
		"    int field = bitfieldExtract(signedWord, int(min(4u, 32u)), int(min(8u, 32u - " +
		"min(4u, 32u))));\n" +
		"    uvec3 fields = bitfieldExtract(uvec3(word, 7, 9), int(min(1u, 32u)), int(min(3u, " +
		"32u - min(1u, 32u))));\n" +
		"    uint placed = bitfieldInsert(word, 5u, int(min(4u, 32u)), int(min(8u, 32u - min(4u, " +
		"32u))));\n" +
		"    uint bytes = packUnorm4x8(unit) + packSnorm4x8(unit);\n" +
		"    uint shorts = packUnorm2x16(pair) + packSnorm2x16(pair);\n" +
		"    vec4 a = unpackUnorm4x8(bytes) + unpackSnorm4x8(bytes);\n" +
		"    vec2 b = unpackUnorm2x16(shorts) + unpackSnorm2x16(shorts);\n" +
		"    vec2 half_1 = unpackHalf2x16(packHalf2x16(pair));\n" +
		"    fragColor = vec4((((float(counted) + float(reversed)) + float(high)) + float(low)), " +
		"((float(field) + float(fields.x)) + float(placed)), (((a.x + a.w) + b.x) + half_1.x), " +
		"(((a.y + a.z) + b.y) + half_1.y));\n" +
		"    return;\n" +
		"}\n";
}

test "WGSL and GLSL 430 spell the bit and pack builtins by their own names" {
	const m = programOf();
	assert irErrors(m).length == 0;
	const wgsl = printedFor(m, 1, ShaderTarget.Wgsl, "bits");
	assert wgsl.includes("  var counted : u32 = countOneBits(word);\n" +
		"  var reversed : i32 = reverseBits(signedWord);\n" +
		"  var high : i32 = firstLeadingBit(signedWord);\n" +
		"  var low : u32 = firstTrailingBit(vec2u(word, 8u)).y;\n" +
		"  var field : i32 = extractBits(signedWord, u32(4i), u32(8i));\n" +
		"  var fields : vec3u = extractBits(vec3u(word, 7u, 9u), u32(1i), u32(3i));\n" +
		"  var placed : u32 = insertBits(word, u32(5i), u32(4i), u32(8i));\n" +
		"  var bytes : u32 = (pack4x8unorm(unit) + pack4x8snorm(unit));\n" +
		"  var shorts : u32 = (pack2x16unorm(pair) + pack2x16snorm(pair));\n" +
		"  var a : vec4f = (unpack4x8unorm(bytes) + unpack4x8snorm(bytes));\n" +
		"  var b : vec2f = (unpack2x16unorm(shorts) + unpack2x16snorm(shorts));\n" +
		"  var half : vec2f = unpack2x16float(pack2x16float(pair));\n");
	const gl = printedFor(m, 1, ShaderTarget.Glsl430, "bits");
	assert gl.includes("    uint counted = uint(bitCount(word));\n" +
		"    int reversed = bitfieldReverse(signedWord);\n" +
		"    int high = findMSB(signedWord);\n" +
		"    uint low = uvec2(findLSB(uvec2(word, 8u))).y;\n" +
		"    int field = bitfieldExtract(signedWord, int(min(uint(4), 32u)), " +
		"int(min(uint(8), 32u - min(uint(4), 32u))));\n" +
		"    uvec3 fields = bitfieldExtract(uvec3(word, 7u, 9u), int(min(uint(1), 32u)), " +
		"int(min(uint(3), 32u - min(uint(1), 32u))));\n" +
		"    uint placed = bitfieldInsert(word, uint(5), int(min(uint(4), 32u)), " +
		"int(min(uint(8), 32u - min(uint(4), 32u))));\n" +
		"    uint bytes = packUnorm4x8(unit) + packSnorm4x8(unit);\n" +
		"    uint shorts = packUnorm2x16(pair) + packSnorm2x16(pair);\n" +
		"    vec4 a = unpackUnorm4x8(bytes) + unpackSnorm4x8(bytes);\n" +
		"    vec2 b = unpackUnorm2x16(shorts) + unpackSnorm2x16(shorts);\n" +
		"    vec2 half_1 = unpackHalf2x16(packHalf2x16(pair));\n");
}

test "HLSL spells them as FXC takes them, and writes the rest as helper functions" {
	const hlsl = printedFor(programOf(), 1, ShaderTarget.Hlsl5, "bits");
	assert hlsl.includes("    uint counted = countbits(word);\n" +
		"    int reversed = asint(reversebits(asuint(signedWord)));\n" +
		"    int high = asint(firstbithigh(signedWord));\n" +
		"    uint low = firstbitlow(uint2(word, 8u)).y;\n" +
		"    int field = extractBits(signedWord, uint(4), uint(8));\n" +
		"    uint3 fields = extractBits(uint3(word, 7u, 9u), uint(1), uint(3));\n" +
		"    uint placed = insertBits(word, uint(5), uint(4), uint(8));\n" +
		"    uint bytes = packUnorm4x8(unit) + packSnorm4x8(unit);\n" +
		"    uint shorts = packUnorm2x16(pair) + packSnorm2x16(pair);\n" +
		"    float4 a = unpackUnorm4x8(bytes) + unpackSnorm4x8(bytes);\n" +
		"    float2 b = unpackUnorm2x16(shorts) + unpackSnorm2x16(shorts);\n" +
		"    float2 half_1 = unpackHalf2x16(packHalf2x16(pair));\n");
	assert hlsl.includes("int extractBits(int e, uint offset, uint count)\n{\n" +
		"    uint w = 32u;\n    uint o = min(offset, w);\n    uint c = min(count, w - o);\n" +
		"    if (c == 0u) { return (int)0; }\n" +
		"    return (e << (w - c - o)) >> (w - c);\n}\n");
	assert hlsl.includes("uint3 extractBits(uint3 e, uint offset, uint count)\n");
	assert hlsl.includes("uint insertBits(uint e, uint newBits, uint offset, uint count)\n{\n" +
		"    uint w = 32u;\n    uint o = min(offset, w);\n    uint c = min(count, w - o);\n" +
		"    if (c == 0u) { return e; }\n" +
		"    uint mask = (0xFFFFFFFFu >> (32u - c)) << o;\n" +
		"    return (e & ~mask) | ((newBits << o) & mask);\n}\n");
	assert hlsl.includes("uint packSnorm4x8(float4 e)\n{\n" +
		"    return uint((int(round(clamp(e.x, -1.0, 1.0) * 127.0)) & 0xFF) | " +
		"((int(round(clamp(e.y, -1.0, 1.0) * 127.0)) & 0xFF) << 8) | " +
		"((int(round(clamp(e.z, -1.0, 1.0) * 127.0)) & 0xFF) << 16) | " +
		"((int(round(clamp(e.w, -1.0, 1.0) * 127.0)) & 0xFF) << 24));\n}\n");
	assert hlsl.includes("float4 unpackSnorm4x8(uint e)\n{\n" +
		"    return max(float4(int4(e << 24, e << 16, e << 8, e) >> 24) / 127.0, -1.0);\n}\n");
	assert hlsl.includes("float2 unpackHalf2x16(uint e)\n{\n" +
		"    return float2(f16tof32(e), f16tof32(e >> 16));\n}\n");
	assert hlsl.includes("uint packHalf2x16(float2 e)\n{\n" +
		"    return f32tof16(e.x) | (f32tof16(e.y) << 16);\n}\n");
}

test "MSL spells them from popcount to extract_bits" {
	const msl = printedFor(programOf(), 1, ShaderTarget.Msl, "bits");
	assert msl.includes("  uint counted = popcount(in.word);\n" +
		"  int reversed = reverse_bits(in.signedWord);\n" +
		"  int high = select(31 - clz(select(in.signedWord, ~in.signedWord, in.signedWord < 0)), " +
		"int(-1), in.signedWord == 0 || in.signedWord == -1);\n" +
		"  uint low = (((ctz(uint2(in.word, 8u)) + 1) % 33) - 1).y;\n" +
		"  int field = extract_bits(in.signedWord, min(uint(4), 32u), " +
		"min(uint(8), 32u - min(uint(4), 32u)));\n" +
		"  uint3 fields = extract_bits(uint3(in.word, 7u, 9u), min(uint(1), 32u), " +
		"min(uint(3), 32u - min(uint(1), 32u)));\n" +
		"  uint placed = insert_bits(in.word, uint(5), min(uint(4), 32u), " +
		"min(uint(8), 32u - min(uint(4), 32u)));\n" +
		"  uint bytes = (pack_float_to_unorm4x8(in.unit) + pack_float_to_snorm4x8(in.unit));\n" +
		"  uint shorts = (pack_float_to_unorm2x16(in.pair) + pack_float_to_snorm2x16(in.pair));\n" +
		"  float4 a = (unpack_unorm4x8_to_float(bytes) + unpack_snorm4x8_to_float(bytes));\n" +
		"  float2 b = (unpack_unorm2x16_to_float(shorts) + unpack_snorm2x16_to_float(shorts));\n" +
		"  float2 half_1 = float2(as_type<half2>(as_type<uint>(half2(in.pair))));\n");
}

test "GLSL ES 3.00 has the 16-bit packs and refuses the rest, naming the builtin" {
	const refused = printedFor(programOf(), 1, ShaderTarget.Glsl300es, "bits");
	assert refused.includes("CountOneBits is not in GLSL ES 3.00 (ES 3.10 has it)");
	const m = halvesOf();
	assert irErrors(m).length == 0;
	const es = printedFor(m, 1, ShaderTarget.Glsl300es, "halves");
	assert es.includes("packUnorm2x16(pair)") && es.includes("packHalf2x16(pair)");
	assert es.includes("unpackUnorm2x16(shorts)") && es.includes("unpackHalf2x16(shorts)");
	for (const target of [ShaderTarget.Wgsl, ShaderTarget.Hlsl5, ShaderTarget.Glsl430,
		ShaderTarget.Msl]) {
		assert printedFor(m, 1, target, "halves").length > 0;
	}
}

test "a bit builtin keeps WGSL's operands and result" {
	let m = programOf();
	const body = m.functions[m.entries[1].functionIndex].body;
	const counted = body.filter((s) => s.kind == StmtKind.Let &&
		s.expr.intrinsic == Intrinsic.CountOneBits)[0].expr;
	counted.operands[0].type = scalarType(ScalarKind.F32);
	assert irErrors(m).includes(
		"function 'bitsFs': CountOneBits takes an i32 or u32 scalar or vector, " +
		"as WGSL's");
	let short = programOf();
	const shortBody = short.functions[short.entries[1].functionIndex].body;
	const extracted = shortBody.filter((s) => s.kind == StmtKind.Let &&
		s.expr.intrinsic == Intrinsic.ExtractBits)[0].expr;
	extracted.operands.pop();
	assert irErrors(short).includes("function 'bitsFs': ExtractBits takes 3 operands, as WGSL's");
}
