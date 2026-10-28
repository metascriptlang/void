// WGSL's remaining math and bit builtins authored in MetaScript: the CPU oracle of countLeadingZeros,
// countTrailingZeros, the bitcasts, ldexp, asinh, acosh and atanh, three entries that use them and
// the coarse and fine derivatives, their text per target, the probe files that fxc and
// spirv-val read, and the places they are refused.

import { mkdir, writeFile } from "std/fs";
import { programModule, stageSource } from "../shader/descriptor";
import { glslIr, glslLinked, glslLinkedIr } from "../shader/emit";
import { Intrinsic, ShaderModule, ShaderStage, intrinsicOf, irErrors, literal } from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import {
	Vec2f,
	Vec2i,
	Vec3f,
	Vec4f,
	Vec4u,
	acosh,
	asinh,
	atanh,
	bitcastF32toI32,
	bitcastF32toU32,
	bitcastI32toF32,
	bitcastI32toU32,
	bitcastU32toF32,
	bitcastU32toI32,
	builtin,
	countLeadingZeros,
	countTrailingZeros,
	dpdxCoarse,
	dpdxFine,
	dpdyCoarse,
	dpdyFine,
	fwidthCoarse,
	fwidthFine,
	ldexp,
	vec2f,
	vec2i,
	vec2u,
	vec3f,
	vec3i,
	vec3u,
	vec4f,
	vec4i,
	vec4u,
} from "../shader/std";
import { opcodeOf, spirvProbe } from "./shaderProbeModules";
import { VEC4, tiny } from "./shaderProbeModules";

export struct Corner {
	position: Vec2f;
}

export struct Bits {
	@builtin(position) position: Vec4f;
	low: Vec3f;
	signedWords: Vec2i;
	words: Vec4u;
}

export struct Smooth {
	@builtin(position) position: Vec4f;
	low: Vec3f;
}

export function bitsVs(input: Corner): Bits {
	return {
		position: vec4f(input.position.x, input.position.y, 0.0, 1.0),
		low: vec3f(0.5, 1.5, 2.0),
		signedWords: vec2i(-8, 12),
		words: vec4u(0, 1, 256, 0x80000000),
	};
}

export function smoothVs(input: Corner): Smooth {
	return {
		position: vec4f(input.position.x, input.position.y, 0.0, 1.0),
		low: vec3f(0.5, 1.5, 2.0),
	};
}

export function bitsFs(input: Bits): Vec4f {
	const leading = countLeadingZeros(input.words);
	const trailing = countTrailingZeros(input.words);
	const leadingSigned = countLeadingZeros(input.signedWords);
	const trailingSigned = countTrailingZeros(input.signedWords);
	const lone = countLeadingZeros(input.words.z);
	const loneSigned = countTrailingZeros(input.signedWords.y);
	const pattern = bitcastF32toU32(input.low.x);
	const patternSigned = bitcastF32toI32(input.low);
	const back = bitcastU32toF32(pattern);
	const backSigned = bitcastI32toF32(patternSigned);
	const swapped = bitcastU32toI32(input.words);
	const swappedBack = bitcastI32toU32(input.signedWords);
	return vec4f(
		(leading.x + leading.y + leading.z + leading.w + lone) as float32,
		(trailing.x + trailing.y + trailing.z + trailing.w) as float32,
		(leadingSigned.x + leadingSigned.y + trailingSigned.x + trailingSigned.y + loneSigned) as float32,
		back + backSigned.y + ((swappedBack.x & 255) as float32) + (swapped.z as float32),
	);
}

export function mathFs(input: Smooth): Vec4f {
	const wide = asinh(input.low);
	const steep = acosh(vec3f(input.low.y, input.low.z, input.low.y));
	const open = atanh(vec2f(input.low.x * 0.5, input.low.x * 0.25));
	const scaled = ldexp(input.low, vec3i(1, 2, 3));
	const whole = ldexp(input.low.x, 3);
	const single = asinh(input.low.x) + acosh(input.low.y) + atanh(input.low.x * 0.5);
	return vec4f(wide.x + steep.y + open.x, scaled.y + whole, single, scaled.z);
}

export function slopeFs(input: Smooth): Vec4f {
	const across = dpdxCoarse(input.low);
	const down = dpdyFine(input.low);
	const wide = fwidthCoarse(input.low.x);
	const fine = fwidthFine(input.low);
	const alongFine = dpdxFine(input.low.x);
	const downCoarse = dpdyCoarse(input.low.x);
	const pair = dpdxFine(vec2f(input.low.x, input.low.y));
	return vec4f(across.x + alongFine, down.y + downCoarse, wide + pair.y, fine.z);
}

function near(a: float32, b: float32): boolean { return Math.abs(a - b) < 0.00001; }

test "countLeadingZeros and countTrailingZeros count the full 32 bits of a zero" {
	assert countLeadingZeros(0 as uint32) == 32 && countTrailingZeros(0 as uint32) == 32;
	assert countLeadingZeros(1 as uint32) == 31 && countTrailingZeros(1 as uint32) == 0;
	assert countLeadingZeros(256 as uint32) == 23 && countTrailingZeros(256 as uint32) == 8;
	assert countLeadingZeros(0x80000000 as uint32) == 0 && countTrailingZeros(0x80000000 as uint32) == 31;
	assert countLeadingZeros(0xFFFFFFFF as uint32) == 0 && countTrailingZeros(0xFFFFFFFF as uint32) == 0;
	const none: int32 = 0;
	const minusOne: int32 = -1;
	const minusEight: int32 = -8;
	const twelve: int32 = 12;
	const least: int32 = -2147483648;
	assert countLeadingZeros(none) == 32 && countTrailingZeros(none) == 32;
	assert countLeadingZeros(minusOne) == 0 && countTrailingZeros(minusOne) == 0;
	assert countLeadingZeros(minusEight) == 0 && countTrailingZeros(minusEight) == 3;
	assert countLeadingZeros(twelve) == 28 && countTrailingZeros(twelve) == 2;
	assert countLeadingZeros(least) == 0 && countTrailingZeros(least) == 31;
	const u = vec4u(0, 1, 256, 0x80000000);
	assert countLeadingZeros(u).x == 32 && countLeadingZeros(u).y == 31;
	assert countLeadingZeros(u).z == 23 && countLeadingZeros(u).w == 0;
	assert countTrailingZeros(u).x == 32 && countTrailingZeros(u).y == 0;
	assert countTrailingZeros(u).z == 8 && countTrailingZeros(u).w == 31;
	assert countLeadingZeros(vec2u(2, 0)).x == 30 && countTrailingZeros(vec3u(4, 0, 1)).y == 32;
	const s = vec2i(-8, 12);
	assert countLeadingZeros(s).x == 0 && countLeadingZeros(s).y == 28;
	assert countTrailingZeros(s).x == 3 && countTrailingZeros(s).y == 2;
	assert countLeadingZeros(vec3i(0, -1, 1)).z == 31 && countTrailingZeros(vec4i(0, 0, 0, 2)).w == 1;
}

test "a bitcast reinterprets the bits, to every scalar and for every shape" {
	assert bitcastF32toU32(1.0) == 0x3F800000 && bitcastF32toU32(-2.0) == 0xC0000000;
	assert bitcastF32toU32(0.0) == 0 && bitcastF32toU32(-0.0) == 0x80000000;
	assert bitcastF32toU32(0.5) == 0x3F000000 && bitcastF32toU32(3.4028234663852886e38) == 0x7F7FFFFF;
	assert bitcastF32toU32(1.17549435e-38) == 0x00800000;
	assert bitcastF32toU32(1.4012984643248171e-45) == 1 && bitcastF32toU32(1.1754942106924411e-38) == 0x007FFFFF;
	assert bitcastF32toI32(-2.0) == -1073741824 && bitcastF32toI32(1.0) == 1065353216;
	assert bitcastU32toF32(0x3F800000) == 1.0 && bitcastU32toF32(0xC0000000) == -2.0;
	assert bitcastU32toF32(0) == 0.0 && 1.0 / bitcastU32toF32(0x80000000) < 0.0;
	assert bitcastU32toF32(1) == 1.4012984643248171e-45 && bitcastU32toF32(0x00800000) == 1.17549435e-38;
	assert bitcastI32toF32(-1073741824) == -2.0 && bitcastI32toF32(1065353216) == 1.0;
	const all: int32 = -1;
	assert bitcastI32toU32(all) == 0xFFFFFFFF && bitcastU32toI32(0xFFFFFFFF) == -1;
	assert bitcastU32toI32(0x80000000) == -2147483648 && bitcastI32toU32(-2147483648) == 0x80000000;
	const f = vec3f(0.5, -1.0, 2.0);
	assert bitcastF32toU32(f).x == 0x3F000000 && bitcastF32toU32(f).y == 0xBF800000;
	assert bitcastF32toI32(f).z == 1073741824 && bitcastI32toF32(bitcastF32toI32(f)).y == -1.0;
	assert bitcastU32toF32(vec2u(0x3F800000, 0x40000000)).y == 2.0;
	assert bitcastU32toF32(vec4u(0x3F800000, 0, 0, 0xC0000000)).w == -2.0;
	assert bitcastI32toU32(vec2i(-8, 12)).x == 0xFFFFFFF8 && bitcastU32toI32(vec4u(0, 1, 256, 0x80000000)).w == -2147483648;
	assert bitcastF32toU32(vec2f(1.0, 2.0)).y == 0x40000000 && bitcastI32toF32(vec4i(0, 0, 0, 1065353216)).w == 1.0;
	assert bitcastU32toI32(vec3u(7, 8, 9)).z == 9 && bitcastI32toU32(vec3i(7, 8, 9)).x == 7;
	assert bitcastF32toI32(vec4f(1.0, 0.0, 0.0, 0.0)).x == 1065353216 && bitcastF32toI32(vec2f(1.0, -2.0)).y == -1073741824;
}

test "ldexp scales by a power of two, asinh acosh and atanh invert the hyperbolics" {
	assert ldexp(0.5, 3) == 4.0 && ldexp(3.0, -2) == 0.75 && ldexp(1.5, 0) == 1.5;
	const scaled = ldexp(vec3f(0.5, 1.5, 2.0), vec3i(1, 2, 3));
	assert scaled.x == 1.0 && scaled.y == 6.0 && scaled.z == 16.0;
	assert ldexp(vec2f(1.0, 3.0), vec2i(4, -1)).y == 1.5 && ldexp(vec4f(1.0), vec4i(1, 2, 3, 4)).w == 16.0;
	assert near(asinh(0.5), 0.48121183) && near(asinh(-0.5), -0.48121183) && asinh(0.0) == 0.0;
	assert near(acosh(2.0), 1.3169579) && near(acosh(1.5), 0.9624237) && acosh(1.0) == 0.0;
	assert near(atanh(0.25), 0.2554128) && near(atanh(-0.25), -0.2554128) && atanh(0.0) == 0.0;
	const w = asinh(vec3f(0.5, 1.5, 2.0));
	assert near(w.x, 0.48121183) && near(w.y, 1.1947632) && near(w.z, 1.4436355);
	assert near(acosh(vec2f(2.0, 1.5)).y, 0.9624237) && near(atanh(vec4f(0.25, 0.0, 0.0, -0.25)).w, -0.2554128);
}

test "the entries run on the CPU" {
	const bits = bitsFs({
		position: vec4f(0.0),
		low: vec3f(0.5, 1.5, 2.0),
		signedWords: vec2i(-8, 12),
		words: vec4u(0, 1, 256, 0x80000000),
	});
	assert bits.x == 109.0 && bits.y == 71.0 && bits.z == 35.0 && bits.w == 506.0;
	const math = mathFs({ position: vec4f(0.0), low: vec3f(0.5, 1.5, 2.0) });
	assert near(math.x, 2.0535825) && math.y == 10.0 && near(math.z, 1.6990483) && math.w == 16.0;
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

function bitsProgram(): ShaderModule {
	const m = programModule(glslIr(bitsVs), glslLinkedIr(bitsFs, bitsVs), []);
	if (!m.ok) { throw new Error("bitsProgram: " + m.error); }
	return m.value;
}

function mathProgram(): ShaderModule {
	const m = programModule(glslIr(smoothVs), glslLinkedIr(mathFs, smoothVs), []);
	if (!m.ok) { throw new Error("mathProgram: " + m.error); }
	return m.value;
}

function slopeProgram(): ShaderModule {
	const m = programModule(glslIr(smoothVs), glslLinkedIr(slopeFs, smoothVs), []);
	if (!m.ok) { throw new Error("slopeProgram: " + m.error); }
	return m.value;
}

test "GLSL 450 spells the counts, the casts, ldexp and the hyperbolics as GLSL's own names" {
	assert glslLinked(bitsFs, bitsVs).includes(
		"    uvec4 leading = uvec4(31 - findMSB(words));
" +
		"    uvec4 trailing = min(uvec4(findLSB(words)), 32u);
" +
		"    ivec2 leadingSigned = 31 - findMSB(uvec2(signedWords));
" +
		"    ivec2 trailingSigned = ivec2(min(uvec2(findLSB(signedWords)), 32u));
" +
		"    uint lone = uint(31 - findMSB(words.z));
" +
		"    int loneSigned = int(min(uint(findLSB(signedWords.y)), 32u));
" +
		"    uint pattern = floatBitsToUint(low.x);
" +
		"    ivec3 patternSigned = floatBitsToInt(low);
" +
		"    float back = uintBitsToFloat(pattern);
" +
		"    vec3 backSigned = intBitsToFloat(patternSigned);
" +
		"    ivec4 swapped = ivec4(words);
" +
		"    uvec2 swappedBack = uvec2(signedWords);
");
	const math = glslLinked(mathFs, smoothVs);
	assert math.includes("    vec3 wide = asinh(low);
");
	assert math.includes("    vec3 steep = acosh(vec3(low.y, low.z, low.y));
");
	assert math.includes("    vec3 scaled = ldexp(low, ivec3(1, 2, 3));
");
	assert math.includes("    float whole = ldexp(low.x, 3);
");
	const slope = glslLinked(slopeFs, smoothVs);
	assert slope.includes("    vec3 across = dFdxCoarse(low);
") && slope.includes("    vec3 down = dFdyFine(low);
");
	assert slope.includes("    float wide = fwidthCoarse(low.x);
") && slope.includes("    vec3 fine = fwidthFine(low);
");
}

test "WGSL spells them by its own names and a bitcast as bitcast<T>" {
	const bits = printedFor(bitsProgram(), 1, ShaderTarget.Wgsl, "mathBits");
	assert bits.includes("  var leading : vec4u = countLeadingZeros(words);
" +
		"  var trailing : vec4u = countTrailingZeros(words);
" +
		"  var leadingSigned : vec2i = countLeadingZeros(signedWords);
" +
		"  var trailingSigned : vec2i = countTrailingZeros(signedWords);
" +
		"  var lone : u32 = countLeadingZeros(words.z);
" +
		"  var loneSigned : i32 = countTrailingZeros(signedWords.y);
" +
		"  var pattern : u32 = bitcast<u32>(low.x);
" +
		"  var patternSigned : vec3i = bitcast<vec3i>(low);
" +
		"  var back : f32 = bitcast<f32>(pattern);
" +
		"  var backSigned : vec3f = bitcast<vec3f>(patternSigned);
" +
		"  var swapped : vec4i = bitcast<vec4i>(words);
" +
		"  var swappedBack : vec2u = bitcast<vec2u>(signedWords);
");
	const math = printedFor(mathProgram(), 1, ShaderTarget.Wgsl, "mathHyper");
	assert math.includes("asinh(low)") && math.includes("acosh(vec3f(low.y, low.z, low.y))");
	assert math.includes("atanh(vec2f((low.x * 0.5f), (low.x * 0.25f)))");
	assert math.includes("ldexp(low, vec3i(1i, 2i, 3i))") && math.includes("ldexp(low.x, 3i)");
	const slope = printedFor(slopeProgram(), 1, ShaderTarget.Wgsl, "mathSlope");
	assert slope.includes("dpdxCoarse(low)") && slope.includes("dpdyFine(low)");
	assert slope.includes("fwidthCoarse(low.x)") && slope.includes("fwidthFine(low)");
	assert slope.includes("dpdxFine(low.x)") && slope.includes("dpdyCoarse(low.x)");
	assert slope.includes("diagnostic(off, derivative_uniformity);");
}

test "GLSL 430 and ES 300 print the casts and the hyperbolics alike, the bit counts and ldexp on 430 only" {
	const slope430 = printedFor(slopeProgram(), 1, ShaderTarget.Glsl430, "mathSlope");
	const slopeEs = printedFor(slopeProgram(), 1, ShaderTarget.Glsl300es, "mathSlope");
	for (const text of [slope430, slopeEs]) {
		assert text.includes("vec3 across = dFdx(low);") && text.includes("vec3 down = dFdy(low);");
		assert text.includes("float wide = fwidth(low.x);") && text.includes("vec3 fine = fwidth(low);");
		assert text.includes("float alongFine = dFdx(low.x);") && text.includes("float downCoarse = dFdy(low.x);");
		assert !text.includes("Coarse(") && !text.includes("Fine(");
	}
	const math430 = printedFor(mathProgram(), 1, ShaderTarget.Glsl430, "mathHyper");
	assert math430.includes("vec3 wide = asinh(low);") && math430.includes("ldexp(low, ivec3(1, 2, 3))");
	const mathEs = printedFor(mathProgram(), 1, ShaderTarget.Glsl300es, "mathHyper");
	assert mathEs == "printGlsl: Ldexp is not in GLSL ES 3.00 (ES 3.10 has it)";
	const bits430 = printedFor(bitsProgram(), 1, ShaderTarget.Glsl430, "mathBits");
	assert bits430.includes("uvec4 leading = uvec4(31 - findMSB(words));");
	assert bits430.includes("uint pattern = floatBitsToUint(low.x);");
	const bitsEs = printedFor(bitsProgram(), 1, ShaderTarget.Glsl300es, "mathBits");
	assert bitsEs == "printGlsl: CountLeadingZeros is not in GLSL ES 3.00 (ES 3.10 has it)";
}

test "HLSL counts through firstbithigh and firstbitlow, casts with as*, and writes helpers for the rest" {
	const bits = printedFor(bitsProgram(), 1, ShaderTarget.Hlsl5, "mathBits");
	assert bits.includes("    uint4 leading = (31u - firstbithigh(words));
" +
		"    uint4 trailing = min(32u, firstbitlow(words));
" +
		"    int2 leadingSigned = asint(31u - firstbithigh(asuint(signedWords)));
" +
		"    int2 trailingSigned = asint(min(32u, firstbitlow(asuint(signedWords))));
" +
		"    uint lone = (31u - firstbithigh(words.z));
" +
		"    int loneSigned = asint(min(32u, firstbitlow(asuint(signedWords.y))));
" +
		"    uint pattern = asuint(low.x);
" +
		"    int3 patternSigned = asint(low);
" +
		"    float back = asfloat(pattern);
" +
		"    float3 backSigned = asfloat(patternSigned);
" +
		"    int4 swapped = asint(words);
" +
		"    uint2 swappedBack = asuint(signedWords);
");
	const math = printedFor(mathProgram(), 1, ShaderTarget.Hlsl5, "mathHyper");
	assert math.includes("float3 asinh(float3 e)
{
    return sign(e) * log(abs(e) + sqrt(e * e + 1.0));
}
");
	assert math.includes("float acosh(float e)") && math.includes("return log(e + sqrt(e * e - 1.0));");
	assert math.includes("return 0.5 * log((1.0 + e) / (1.0 - e));");
	assert math.includes("ldexp(low, int3(1, 2, 3))") && math.includes("ldexp(low.x, 3)");
	const slope = printedFor(slopeProgram(), 1, ShaderTarget.Hlsl5, "mathSlope");
	assert slope.includes("ddx_coarse(low)") && slope.includes("ddy_fine(low)");
	assert slope.includes("ddx_fine(low.x)") && slope.includes("ddy_coarse(low.x)");
	assert slope.includes("return abs(ddx_coarse(e)) + abs(ddy_coarse(e));");
	assert slope.includes("return abs(ddx_fine(e)) + abs(ddy_fine(e));");
}

test "MSL counts with clz and ctz, casts with as_type, and has the rest by name" {
	const bits = printedFor(bitsProgram(), 1, ShaderTarget.Msl, "mathBits");
	assert bits.includes("  uint4 leading = clz(in.words);
" +
		"  uint4 trailing = ctz(in.words);
" +
		"  int2 leadingSigned = clz(in.signedWords);
" +
		"  int2 trailingSigned = ctz(in.signedWords);
" +
		"  uint lone = clz(in.words.z);
" +
		"  int loneSigned = ctz(in.signedWords.y);
" +
		"  uint pattern = as_type<uint>(in.low.x);
" +
		"  int3 patternSigned = as_type<int3>(in.low);
" +
		"  float back = as_type<float>(pattern);
" +
		"  float3 backSigned = as_type<float3>(patternSigned);
" +
		"  int4 swapped = as_type<int4>(in.words);
" +
		"  uint2 swappedBack = as_type<uint2>(in.signedWords);
");
	const math = printedFor(mathProgram(), 1, ShaderTarget.Msl, "mathHyper");
	assert math.includes("asinh(in.low)") && math.includes("acosh(float3(in.low.y, in.low.z, in.low.y))");
	assert math.includes("ldexp(in.low, int3(1, 2, 3))");
	const slope = printedFor(slopeProgram(), 1, ShaderTarget.Msl, "mathSlope");
	assert slope.includes("dfdx(in.low)") && slope.includes("dfdy(in.low)") && slope.includes("fwidth(in.low)");
	assert !slope.includes("Coarse(") && !slope.includes("Fine(");
}

function opcodes(words: uint32[][], opcode: int32): int32 {
	return words.filter((i) => opcodeOf(i) == opcode).length as int32;
}

function extensions(words: uint32[][], number: uint32): int32 {
	return words.filter((i) => opcodeOf(i) == 12 && i[4] == number).length as int32;
}

test "SPIR-V counts with GLSL.std.450's FindUMsb and FindILsb, casts with OpBitcast, and takes the control capability" {
	const bitsModule = bitsProgram();
	const _bitsVertex = spirvProbe(bitsModule, 0, "mathBits");
	const bits = spirvProbe(bitsModule, 1, "mathBits");
	assert opcodes(bits, 124) == 6;
	assert opcodes(bits, 130) == 3;
	assert extensions(bits, 75) == 3;
	assert extensions(bits, 73) == 3;
	assert extensions(bits, 38) == 3;
	assert opcodes(bits, 17) == 1;
	const mathModule = mathProgram();
	const _mathVertex = spirvProbe(mathModule, 0, "mathHyper");
	const math = spirvProbe(mathModule, 1, "mathHyper");
	assert extensions(math, 22) == 2 && extensions(math, 23) == 2 && extensions(math, 24) == 2;
	assert extensions(math, 53) == 2;
	const slopeModule = slopeProgram();
	const _slopeVertex = spirvProbe(slopeModule, 0, "mathSlope");
	const slope = spirvProbe(slopeModule, 1, "mathSlope");
	assert opcodes(slope, 213) == 1 && opcodes(slope, 211) == 1 && opcodes(slope, 215) == 1;
	assert opcodes(slope, 212) == 1 && opcodes(slope, 210) == 2 && opcodes(slope, 214) == 1;
	assert opcodes(slope, 17) == 2;
}

test "a bitcast changes the scalar and keeps the shape, ldexp takes an i32 shape, coarse and fine are a fragment's" {
	const same = tiny(ShaderStage.Fragment, intrinsicOf(Intrinsic.Bitcast, VEC4, [literal(VEC4, 1.0)]));
	assert irErrors(same).includes("function 'tinyEntry': Bitcast takes one i32, u32 or f32 scalar or " +
		"vector and answers the same shape of another scalar");
	const scaled = tiny(ShaderStage.Fragment, intrinsicOf(Intrinsic.Ldexp, VEC4,
		[literal(VEC4, 1.0), literal(VEC4, 1.0)]));
	assert irErrors(scaled).includes("function 'tinyEntry': Ldexp takes an f32 scalar or vector and an " +
		"i32 of its shape, as WGSL's");
	for (const op of [Intrinsic.DpdxCoarse, Intrinsic.DpdxFine, Intrinsic.DpdyCoarse, Intrinsic.DpdyFine,
		Intrinsic.FwidthCoarse, Intrinsic.FwidthFine]) {
		const vertex = tiny(ShaderStage.Vertex, intrinsicOf(op, VEC4, [literal(VEC4, 1.0)]));
		assert irErrors(vertex).includes("entry 'tinyEntry': " + op.toString() + " outside a fragment entry");
	}
}
