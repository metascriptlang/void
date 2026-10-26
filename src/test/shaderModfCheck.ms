// WGSL's modf and frexp authored in MetaScript: the CPU oracle, entries that use them for a scalar
// and for every vector width, their text per target, the probe files that naga, fxc and spirv-val
// read, and the places they are refused.

import { mkdir, writeFile } from "std/fs";
import { programModule, stageSource } from "../shader/descriptor";
import { glslIr, glslLinked, glslLinkedIr } from "../shader/emit";
import { Intrinsic, ShaderModule, ShaderStage, intrinsicOf, irErrors, literal, modfResultType } from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import { opcodeOf, spirvProbe } from "./shaderProbeModules";
import { VEC4, tiny } from "./shaderProbeModules";
import {
	FrexpResultVec3f,
	ModfResultVec3f,
	Vec2f,
	Vec3f,
	Vec4f,
	builtin,
	frexp,
	modf,
	vec2f,
	vec3f,
	vec4f,
} from "../shader/std";

export struct Corner {
	position: Vec2f;
}

export struct Parts {
	@builtin(position) position: Vec4f;
	amount: Vec3f;
}

export function partsVs(input: Corner): Parts {
	return {
		position: vec4f(input.position.x, input.position.y, 0.0, 1.0),
		amount: vec3f(-2.75, 0.5, 6.0),
	};
}

function wholeOf(r: ModfResultVec3f): Vec3f { return r.whole; }

function exponentOf(r: FrexpResultVec3f): Vec3f { return vec3f(r.exp.x as float32, r.exp.y as float32, r.fract.z); }

export function modfFs(input: Parts): Vec4f {
	const one = modf(input.amount.x);
	const many = modf(input.amount);
	const pair = modf(vec2f(input.amount.x, input.amount.y));
	const quad = modf(vec4f(input.amount, 1.5));
	return vec4f(
		one.fract + one.whole,
		many.fract.y + many.whole.z + modf(input.amount.z).fract,
		pair.whole.x + pair.fract.y,
		quad.whole.w + quad.fract.w,
	);
}

export function frexpFs(input: Parts): Vec4f {
	const one = frexp(input.amount.x);
	const many = frexp(input.amount);
	const pair = frexp(vec2f(input.amount.x, input.amount.y));
	const quad = frexp(vec4f(input.amount, 0.375));
	return vec4f(
		one.fract + (one.exp as float32),
		many.fract.y + (many.exp.z as float32) + frexp(input.amount.z).fract,
		pair.fract.x + (pair.exp.y as float32),
		quad.fract.w + (quad.exp.w as float32),
	);
}

export function heldFs(input: Parts): Vec4f {
	const whole = wholeOf(modf(input.amount));
	const exponent = exponentOf(frexp(input.amount));
	return vec4f(whole.x + exponent.x, whole.y + exponent.y, whole.z + exponent.z, 1.0);
}

function near(a: float32, b: float32): boolean { return Math.abs(a - b) < 0.00001; }

test "modf splits a value into a fraction and a whole part that keep its sign" {
	const a = modf(-2.75);
	assert a.fract == -0.75 && a.whole == -2.0;
	const b = modf(6.0);
	assert b.fract == 0.0 && b.whole == 6.0;
	const c = modf(0.5);
	assert c.fract == 0.5 && c.whole == 0.0;
	const d = modf(vec3f(-2.75, 0.5, 6.0));
	assert d.fract.x == -0.75 && d.fract.y == 0.5 && d.fract.z == 0.0;
	assert d.whole.x == -2.0 && d.whole.y == 0.0 && d.whole.z == 6.0;
	assert modf(vec2f(1.25, -3.5)).whole.y == -3.0 && modf(vec2f(1.25, -3.5)).fract.x == 0.25;
	assert modf(vec4f(1.5, 2.5, -0.25, 7.125)).fract.w == 0.125 && modf(vec4f(1.5, 2.5, -0.25, 7.125)).whole.z == 0.0;
	assert modf(16777216.0).fract == 0.0 && modf(0.0000001).whole == 0.0;
}

test "frexp splits a value into a fraction in [0.5, 1) and a power of two" {
	const a = frexp(8.0);
	assert a.fract == 0.5 && a.exp == 4;
	const b = frexp(-2.75);
	assert b.fract == -0.6875 && b.exp == 2;
	const c = frexp(0.375);
	assert c.fract == 0.75 && c.exp == -1;
	const d = frexp(1.0);
	assert d.fract == 0.5 && d.exp == 1;
	const e = frexp(0.0);
	assert e.fract == 0.0 && e.exp == 0;
	const f = frexp(3.4028234663852886e38);
	assert f.fract == 0.99999994 && f.exp == 128;
	const g = frexp(1.4012984643248171e-45);
	assert g.fract == 0.5 && g.exp == -148;
	const h = frexp(vec3f(-2.75, 0.5, 6.0));
	assert h.fract.x == -0.6875 && h.fract.y == 0.5 && h.fract.z == 0.75;
	assert h.exp.x == 2 && h.exp.y == 0 && h.exp.z == 3;
	assert frexp(vec2f(8.0, 0.375)).exp.y == -1 && frexp(vec2f(8.0, 0.375)).fract.x == 0.5;
	assert frexp(vec4f(1.0, 2.0, 4.0, 0.125)).exp.w == -2 && frexp(vec4f(1.0, 2.0, 4.0, 0.125)).exp.z == 3;
}

test "the entries run on the CPU" {
	const parts: Parts = { position: vec4f(0.0), amount: vec3f(-2.75, 0.5, 6.0) };
	const split = modfFs(parts);
	assert near(split.x, -2.75) && near(split.y, 0.5 + 6.0 + 0.0) && near(split.z, -2.0 + 0.5) && near(split.w, 1.0 + 0.5);
	const scaled = frexpFs(parts);
	assert near(scaled.x, -0.6875 + 2.0) && near(scaled.y, 0.5 + 3.0 + 0.75);
	assert near(scaled.z, -0.6875 + 0.0) && near(scaled.w, 0.75 + (-1.0));
	const held = heldFs(parts);
	assert near(held.x, -2.0 + 2.0) && near(held.y, 0.0 + 0.0) && near(held.z, 6.0 + 0.75);
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

function modfProgram(): ShaderModule {
	const m = programModule(glslIr(partsVs), glslLinkedIr(modfFs, partsVs), []);
	if (!m.ok) { throw new Error("modfProgram: " + m.error); }
	return m.value;
}

function frexpProgram(): ShaderModule {
	const m = programModule(glslIr(partsVs), glslLinkedIr(frexpFs, partsVs), []);
	if (!m.ok) { throw new Error("frexpProgram: " + m.error); }
	return m.value;
}

function heldProgram(): ShaderModule {
	const m = programModule(glslIr(partsVs), glslLinkedIr(heldFs, partsVs), []);
	if (!m.ok) { throw new Error("heldProgram: " + m.error); }
	return m.value;
}

function structLines(name: string, first: string, second: string): string {
	return "struct " + name + "\n{\n    " + first + ";\n    " + second + ";\n};\n";
}

test "GLSL 450 declares a struct and a helper per width and reads the fields by name" {
	const modf450 = glslLinked(modfFs, partsVs);
	assert modf450.includes("struct ModfResultVec3f {\n    vec3 fract;\n    vec3 whole;\n};\n" +
		"ModfResultVec3f modfVec3f(vec3 arg) {\n    vec3 other;\n    vec3 part = modf(arg, other);\n" +
		"    return ModfResultVec3f(part, other);\n}\n");
	assert modf450.includes("struct ModfResultF32 {\n    float fract;\n    float whole;\n};\n");
	assert modf450.includes("    ModfResultF32 one = modfF32(amount.x);\n");
	assert modf450.includes("    ModfResultVec2f pair = modfVec2f(vec2(amount.x, amount.y));\n");
	assert modf450.includes("(one.fract + one.whole)") && modf450.includes("modfF32(amount.z).fract");
	const frexp450 = glslLinked(frexpFs, partsVs);
	assert frexp450.includes("struct FrexpResultVec3f {\n    vec3 fract;\n    ivec3 exp;\n};\n" +
		"FrexpResultVec3f frexpVec3f(vec3 arg) {\n    ivec3 other;\n    vec3 part = frexp(arg, other);\n" +
		"    return FrexpResultVec3f(part, other);\n}\n");
	assert frexp450.includes("struct FrexpResultF32 {\n    float fract;\n    int exp;\n};\n");
	assert frexp450.includes("float(one.exp)") && frexp450.includes("float(pair.exp.y)");
	const held450 = glslLinked(heldFs, partsVs);
	assert held450.includes("vec3 wholeOf(ModfResultVec3f r) {\n    return r.whole;\n}");
	assert held450.includes("vec3 exponentOf(FrexpResultVec3f r) {");
}

test "WGSL calls modf and frexp by name and reads fract, whole and exp, but cannot name a result" {
	const modf = printedFor(modfProgram(), 1, ShaderTarget.Wgsl, "splitModf");
	assert modf.includes("  var one = modf(amount.x);\n  var many = modf(amount);\n");
	assert modf.includes("  var pair = modf(vec2f(amount.x, amount.y));\n");
	assert modf.includes("(one.fract + one.whole)") && modf.includes("modf(amount.z).fract");
	assert !modf.includes("struct Modf");
	const frexp = printedFor(frexpProgram(), 1, ShaderTarget.Wgsl, "splitFrexp");
	assert frexp.includes("  var one = frexp(amount.x);\n  var many = frexp(amount);\n");
	assert frexp.includes("f32(one.exp)") && frexp.includes("f32(pair.exp.y)");
	assert printedFor(heldProgram(), 1, ShaderTarget.Wgsl, "splitHeld") ==
		"printWgsl: a ModfResult, which WGSL cannot name, outside the local it initializes";
}

test "GLSL 430 declares the structs once before the functions, and ES 300 has modf but not frexp" {
	const modf = printedFor(modfProgram(), 1, ShaderTarget.Glsl430, "splitModf");
	assert modf.includes(structLines("ModfResultVec3f", "vec3 fract", "vec3 whole") + "\n" +
		"ModfResultVec3f modfVec3f(vec3 arg)\n{\n    vec3 other;\n    vec3 part = modf(arg, other);\n" +
		"    return ModfResultVec3f(part, other);\n}\n");
	assert modf.includes("    ModfResultVec3f many = modfVec3f(amount);\n");
	assert modf.indexOf("struct ModfResultF32") < modf.indexOf("void main()");
	const frexp = printedFor(frexpProgram(), 1, ShaderTarget.Glsl430, "splitFrexp");
	assert frexp.includes(structLines("FrexpResultVec4f", "vec4 fract", "ivec4 exp") + "\n" +
		"FrexpResultVec4f frexpVec4f(vec4 arg)\n{\n    ivec4 other;\n    vec4 part = frexp(arg, other);\n" +
		"    return FrexpResultVec4f(part, other);\n}\n");
	const held = printedFor(heldProgram(), 1, ShaderTarget.Glsl430, "splitHeld");
	assert held.includes("vec3 wholeOf(ModfResultVec3f r)\n{\n    return r.whole;\n}\n");
	const modfEs = printedFor(modfProgram(), 1, ShaderTarget.Glsl300es, "splitModf");
	assert modfEs.includes("ModfResultVec3f modfVec3f(vec3 arg)\n{") && modfEs.includes("modf(arg, other)");
	assert printedFor(frexpProgram(), 1, ShaderTarget.Glsl300es, "splitFrexp") ==
		"printGlsl: Frexp is not in GLSL ES 3.00 (ES 3.10 has it)";
}

test "HLSL writes the struct and a helper, and signs frexp's mantissa by hand" {
	const modf = printedFor(modfProgram(), 1, ShaderTarget.Hlsl5, "splitModf");
	assert modf.includes(structLines("ModfResultVec3f", "float3 fract", "float3 whole") + "\n" +
		"ModfResultVec3f modfVec3f(float3 arg)\n{\n    float3 other;\n    ModfResultVec3f result;\n" +
		"    result.fract = modf(arg, other);\n    result.whole = other;\n    return result;\n}\n");
	assert modf.includes("    ModfResultF32 one = modfF32(amount.x);\n");
	const frexp = printedFor(frexpProgram(), 1, ShaderTarget.Hlsl5, "splitFrexp");
	assert frexp.includes(structLines("FrexpResultVec3f", "float3 fract", "int3 exp") + "\n" +
		"FrexpResultVec3f frexpVec3f(float3 arg)\n{\n    float3 other;\n    FrexpResultVec3f result;\n" +
		"    result.fract = sign(arg) * frexp(arg, other);\n    result.exp = int3(other);\n" +
		"    return result;\n}\n");
	assert frexp.includes("FrexpResultF32 frexpF32(float arg)") && frexp.includes("result.exp = int(other);");
	const held = printedFor(heldProgram(), 1, ShaderTarget.Hlsl5, "splitHeld");
	assert held.includes("float3 wholeOf(ModfResultVec3f r)\n{\n    return r.whole;\n}\n");
}

test "MSL writes the struct and a static helper over metal's modf and frexp" {
	const modf = printedFor(modfProgram(), 1, ShaderTarget.Msl, "splitModf");
	assert modf.includes("struct ModfResultVec3f {\n  float3 fract;\n  float3 whole;\n};\n\n" +
		"static inline ModfResultVec3f modfVec3f(float3 arg) {\n  float3 other;\n" +
		"  float3 part = modf(arg, other);\n  return ModfResultVec3f{part, other};\n}\n");
	assert modf.includes("  ModfResultF32 one = modfF32(in.amount.x);\n");
	const frexp = printedFor(frexpProgram(), 1, ShaderTarget.Msl, "splitFrexp");
	assert frexp.includes("struct FrexpResultVec2f {\n  float2 fract;\n  int2 exp;\n};\n\n" +
		"static inline FrexpResultVec2f frexpVec2f(float2 arg) {\n  int2 other;\n" +
		"  float2 part = frexp(arg, other);\n  return FrexpResultVec2f{part, other};\n}\n");
	assert frexp.indexOf("struct FrexpResultF32") < frexp.indexOf("static inline void frexpFs");
}

function opcodes(words: uint32[][], opcode: int32): int32 {
	return words.filter((i) => opcodeOf(i) == opcode).length as int32;
}

function extensions(words: uint32[][], number: uint32): int32 {
	return words.filter((i) => opcodeOf(i) == 12 && i[4] == number).length as int32;
}

test "SPIR-V calls GLSL.std.450's ModfStruct and FrexpStruct and extracts the fields" {
	const modfModule = modfProgram();
	const _modfVertex = spirvProbe(modfModule, 0, "splitModf");
	const modf = spirvProbe(modfModule, 1, "splitModf");
	assert extensions(modf, 36) == 5 && extensions(modf, 52) == 0;
	const frexpModule = frexpProgram();
	const _frexpVertex = spirvProbe(frexpModule, 0, "splitFrexp");
	const frexp = spirvProbe(frexpModule, 1, "splitFrexp");
	assert extensions(frexp, 52) == 5 && extensions(frexp, 36) == 0;
	const heldModule = heldProgram();
	const _heldVertex = spirvProbe(heldModule, 0, "splitHeld");
	const held = spirvProbe(heldModule, 1, "splitHeld");
	assert extensions(held, 36) == 1 && extensions(held, 52) == 1;
}

test "modf and frexp take an f32 shape and answer the result of its width" {
	const wide = tiny(ShaderStage.Fragment, intrinsicOf(Intrinsic.Modf, VEC4, [literal(VEC4, 1.0)]));
	assert irErrors(wide).includes("function 'tinyEntry': Modf takes an f32 scalar or vector and " +
		"answers the predeclared result of its width, as WGSL's");
	const wrong = tiny(ShaderStage.Fragment, intrinsicOf(Intrinsic.Frexp, modfResultType(4),
		[literal(VEC4, 1.0)]));
	assert irErrors(wrong).includes("function 'tinyEntry': Frexp takes an f32 scalar or vector and " +
		"answers the predeclared result of its width, as WGSL's");
}
