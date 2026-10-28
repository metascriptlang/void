// WGSL's boolean vectors authored in MetaScript: the CPU oracle of the componentwise tests,
// any, all, not and select, an entry that uses each, its text per target, the probe files that
// fxc and spirv-val read, and the places a bool cannot go.

import { mkdir, writeFile } from "std/fs";
import { programModule, stageSource } from "../shader/descriptor";
import { glslIr, glslLinked, glslLinkedIr } from "../shader/emit";
import {
	Builtin,
	IoDirection,
	ResourceKind,
	ShaderModule,
	ShaderStage,
	arrayType,
	irErrors,
	structType,
} from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import {
	Vec2f,
	Vec2i,
	Vec3f,
	Vec4f,
	Vec4u,
	all,
	any,
	builtin,
	eq,
	ge,
	gt,
	le,
	lt,
	ne,
	not,
	select,
	vec2b,
	vec2f,
	vec2i,
	vec2u,
	vec3b,
	vec3f,
	vec3i,
	vec3u,
	vec4b,
	vec4f,
	vec4i,
	vec4u,
} from "../shader/std";
import { opcodeOf, spirvProbe } from "./shaderProbeModules";
import { BOOL, BVEC3, block, column, field, io, model, resource, tiny } from "./shaderProbeModules";

export struct Corner {
	position: Vec2f;
}

export struct Placed {
	@builtin(position) clip: Vec4f;
	low: Vec3f;
	high: Vec3f;
	signedLow: Vec2i;
	signedHigh: Vec2i;
	wordLow: Vec4u;
	wordHigh: Vec4u;
}

export struct Tested {
	@builtin(position) position: Vec4f;
	low: Vec3f;
	high: Vec3f;
	signedLow: Vec2i;
	signedHigh: Vec2i;
	wordLow: Vec4u;
	wordHigh: Vec4u;
}

export function boolVs(input: Corner): Placed {
	return {
		clip: vec4f(input.position.x, input.position.y, 0.0, 1.0),
		low: vec3f(0.0, 1.0, 2.0),
		high: vec3f(1.0, 1.0, 1.0),
		signedLow: vec2i(-1, 5),
		signedHigh: vec2i(2, 5),
		wordLow: vec4u(1, 2, 3, 4),
		wordHigh: vec4u(1, 3, 3, 0),
	};
}

function weigh(set: boolean, weight: float32): float32 { return set ? weight : 0.0; }

export function boolFs(input: Tested): Vec4f {
	const below = lt(input.low, input.high);
	const noMore = le(input.signedLow, input.signedHigh);
	const above = gt(input.wordLow, input.wordHigh);
	const noLess = ge(input.low, input.high);
	const same = eq(input.wordLow, input.wordHigh);
	const differ = ne(input.signedLow, input.signedHigh);
	const picked = select(input.low, input.high, below);
	const pickedSigned = select(input.signedLow, input.signedHigh, not(noMore));
	const pickedWords = select(input.wordLow, input.wordHigh, same);
	const pickedFlags = select(below, noLess, vec3b(true, false, true));
	const whole = select(input.signedLow.x, input.signedHigh.x, all(differ));
	const flags = weigh(any(above), 1.0) + weigh(all(pickedFlags), 2.0) +
		weigh(any(not(same)), 4.0);
	return vec4f(
		picked.x + picked.z + (pickedSigned.y as float32),
		(pickedWords.w as float32) + (whole as float32),
		flags,
		1.0,
	);
}

test "the componentwise tests answer WGSL's, one bool per lane" {
	const a = vec3f(0.0, 1.0, 2.0);
	const b = vec3f(1.0, 1.0, 1.0);
	assert lt(a, b).x && !lt(a, b).y && !lt(a, b).z;
	assert le(a, b).x && le(a, b).y && !le(a, b).z;
	assert !gt(a, b).x && !gt(a, b).y && gt(a, b).z;
	assert !ge(a, b).x && ge(a, b).y && ge(a, b).z;
	assert !eq(a, b).x && eq(a, b).y && !eq(a, b).z;
	assert ne(a, b).x && !ne(a, b).y && ne(a, b).z;
	const s = vec2i(-1, 5);
	const t = vec2i(2, 5);
	assert lt(s, t).x && !lt(s, t).y && eq(s, t).y && !eq(s, t).x;
	assert le(s, t).x && le(s, t).y && !gt(s, t).x && ge(s, t).y && ne(s, t).x;
	const u = vec4u(1, 2, 3, 4);
	const v = vec4u(1, 3, 3, 0);
	assert eq(u, v).x && !eq(u, v).y && eq(u, v).z && !eq(u, v).w;
	assert !lt(u, v).x && lt(u, v).y && !lt(u, v).z && !lt(u, v).w;
	assert gt(u, v).w && ge(u, v).x && le(u, v).z && !le(u, v).w && ne(u, v).y;
	assert lt(vec2f(1.0, 2.0), vec2f(2.0, 1.0)).x && gt(vec2u(3, 1), vec2u(2, 1)).x;
	assert eq(vec4i(1, 2, 3, 4), vec4i(1, 0, 3, 0)).z && ne(vec4f(0.0), vec4f(1.0)).w;
	assert le(vec3u(1, 2, 3), vec3u(1, 2, 3)).z && ge(vec3i(1, 2, 3), vec3i(2, 2, 2)).y;
}

test "any and all fold a bool vector, not flips each lane" {
	assert any(vec2b(false, true)) && !any(vec2b(false, false));
	assert any(vec3b(false, false, true)) && !any(vec3b(false, false, false));
	assert any(vec4b(false, false, false, true)) && !any(vec4b(false, false, false, false));
	assert all(vec2b(true, true)) && !all(vec2b(true, false));
	assert all(vec3b(true, true, true)) && !all(vec3b(true, false, true));
	assert all(vec4b(true, true, true, true)) && !all(vec4b(true, true, true, false));
	const flipped = not(vec3b(true, false, true));
	assert !flipped.x && flipped.y && !flipped.z;
	const flippedWide = not(vec4b(true, false, true, false));
	assert !flippedWide.x && flippedWide.y && !flippedWide.z && flippedWide.w;
	assert not(vec2b(false, true)).x && !not(vec2b(false, true)).y;
	assert !not(true) && not(false);
}

test "select takes the second value where the condition holds, for every type and shape" {
	assert select(1.5, 2.5, true) == 2.5 && select(1.5, 2.5, false) == 1.5;
	const i1: int32 = -3;
	const i2: int32 = 9;
	const u1: uint32 = 3;
	const u2: uint32 = 9;
	assert select(i1, i2, true) == 9 && select(i1, i2, false) == -3;
	assert select(u1, u2, true) == 9 && select(u1, u2, false) == 3;
	assert select(false, true, true) && !select(false, true, false);
	const f = select(vec2f(1.0, 2.0), vec2f(3.0, 4.0), vec2b(true, false));
	assert f.x == 3.0 && f.y == 2.0;
	const g = select(vec4f(1.0, 2.0, 3.0, 4.0), vec4f(5.0, 6.0, 7.0, 8.0),
		vec4b(false, true, false, true));
	assert g.x == 1.0 && g.y == 6.0 && g.z == 3.0 && g.w == 8.0;
	assert select(vec3f(1.0), vec3f(2.0), true).z == 2.0 &&
		select(vec3f(1.0), vec3f(2.0), false).z == 1.0;
	const i = select(vec3i(1, 2, 3), vec3i(4, 5, 6), vec3b(true, false, true));
	assert i.x == 4 && i.y == 2 && i.z == 6;
	assert select(vec2i(1, 2), vec2i(3, 4), true).y == 4;
	const w = select(vec4u(1, 2, 3, 4), vec4u(5, 6, 7, 8), vec4b(true, true, false, false));
	assert w.x == 5 && w.y == 6 && w.z == 3 && w.w == 4;
	assert select(vec3u(1, 2, 3), vec3u(4, 5, 6), false).x == 1;
	const b = select(vec3b(true, true, false), vec3b(false, false, true), vec3b(true, false, true));
	assert !b.x && b.y && b.z;
	assert select(vec2b(true, false), vec2b(false, true), true).y;
	assert select(vec4b(true, false, true, false), vec4b(false, true, false, true), false).x;
}

test "the entry runs on the CPU" {
	const out = boolFs({
		position: vec4f(0.0),
		low: vec3f(0.0, 1.0, 2.0),
		high: vec3f(1.0, 1.0, 1.0),
		signedLow: vec2i(-1, 5),
		signedHigh: vec2i(2, 5),
		wordLow: vec4u(1, 2, 3, 4),
		wordHigh: vec4u(1, 3, 3, 0),
	});
	assert out.x == 8.0 && out.y == 3.0 && out.z == 5.0 && out.w == 1.0;
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
	const m = programModule(glslIr(boolVs), glslLinkedIr(boolFs, boolVs), []);
	if (!m.ok) { return new ShaderModule(); }
	return m.value;
}

test "GLSL 450 spells the tests as lessThan and its kin and a select by a bool vector as mix" {
	assert glslLinked(boolFs, boolVs) ==
		"in vec3 low;\n" +
		"in vec3 high;\n" +
		"flat in ivec2 signedLow;\n" +
		"flat in ivec2 signedHigh;\n" +
		"flat in uvec4 wordLow;\n" +
		"flat in uvec4 wordHigh;\n" +
		"layout(location=0) out vec4 fragColor;\n" +
		"float weigh(bool set, float weight) {\n" +
		"    return set ? weight : 0.0;\n" +
		"}\n" +
		"void main() {\n" +
		"    bvec3 below = lessThan(low, high);\n" +
		"    bvec2 noMore = lessThanEqual(signedLow, signedHigh);\n" +
		"    bvec4 above = greaterThan(wordLow, wordHigh);\n" +
		"    bvec3 noLess = greaterThanEqual(low, high);\n" +
		"    bvec4 same = equal(wordLow, wordHigh);\n" +
		"    bvec2 differ = notEqual(signedLow, signedHigh);\n" +
		"    vec3 picked = mix(low, high, below);\n" +
		"    ivec2 pickedSigned = mix(signedLow, signedHigh, (not(noMore)));\n" +
		"    uvec4 pickedWords = mix(wordLow, wordHigh, same);\n" +
		"    bvec3 pickedFlags = mix(below, noLess, bvec3(true, false, true));\n" +
		"    int whole = (all(differ) ? signedHigh.x : signedLow.x);\n" +
		"    float flags = (weigh(any(above), 1.0) + weigh(all(pickedFlags), 2.0)) + " +
		"weigh(any((not(same))), 4.0);\n" +
		"    fragColor = vec4(((picked.x + picked.z) + float(pickedSigned.y)), " +
		"(float(pickedWords.w) + float(whole)), flags, 1.0);\n" +
		"    return;\n" +
		"}\n";
}

test "WGSL spells the tests as operators and the rest by its own names" {
	const m = programOf();
	assert irErrors(m).length == 0;
	const wgsl = printedFor(m, 1, ShaderTarget.Wgsl, "boolVector");
	assert wgsl.includes("  var below : vec3<bool> = (low < high);\n" +
		"  var noMore : vec2<bool> = (signedLow <= signedHigh);\n" +
		"  var above : vec4<bool> = (wordLow > wordHigh);\n" +
		"  var noLess : vec3<bool> = (low >= high);\n" +
		"  var same : vec4<bool> = (wordLow == wordHigh);\n" +
		"  var differ : vec2<bool> = (signedLow != signedHigh);\n" +
		"  var picked : vec3f = select(low, high, below);\n" +
		"  var pickedSigned : vec2i = select(signedLow, signedHigh, (!noMore));\n" +
		"  var pickedWords : vec4u = select(wordLow, wordHigh, same);\n" +
		"  var pickedFlags : vec3<bool> = select(below, noLess, vec3<bool>(true, false, true));\n" +
		"  var whole : i32 = select(signedLow.x, signedHigh.x, all(differ));\n");
	assert wgsl.includes("weigh(any(above), 1f)") && wgsl.includes("any((!same))");
}

test "GLSL 430 and ES 300 select an integer or bool vector lane by lane" {
	const m = programOf();
	for (const target of [ShaderTarget.Glsl430, ShaderTarget.Glsl300es]) {
		const text = printedFor(m, 1, target, "boolVector");
		assert text.includes("bvec3 below = lessThan(low, high);\n" +
			"    bvec2 noMore = lessThanEqual(signedLow, signedHigh);\n" +
			"    bvec4 above = greaterThan(wordLow, wordHigh);\n" +
			"    bvec3 noLess = greaterThanEqual(low, high);\n" +
			"    bvec4 same = equal(wordLow, wordHigh);\n" +
			"    bvec2 differ = notEqual(signedLow, signedHigh);\n");
		assert text.includes("vec3 picked = mix(low, high, below);\n");
		assert text.includes(
			"ivec2 pickedSigned = ivec2((not(noMore)).x ? signedHigh.x : signedLow.x, " +
			"(not(noMore)).y ? signedHigh.y : signedLow.y);\n");
		assert text.includes("uvec4 pickedWords = uvec4(same.x ? wordHigh.x : wordLow.x, " +
			"same.y ? wordHigh.y : wordLow.y, same.z ? wordHigh.z : wordLow.z, " +
			"same.w ? wordHigh.w : wordLow.w);\n");
		assert text.includes(
			"bvec3 pickedFlags = bvec3(bvec3(true, false, true).x ? noLess.x : below.x, " +
			"bvec3(true, false, true).y ? noLess.y : below.y, " +
			"bvec3(true, false, true).z ? noLess.z : below.z);\n");
		assert text.includes("int whole = (all(differ) ? signedHigh.x : signedLow.x);\n");
		assert text.includes("weigh(any(above), 1.0)") && text.includes("any(not(same))");
	}
}

test "HLSL spells them as operators and a ternary on a bool vector" {
	const hlsl = printedFor(programOf(), 1, ShaderTarget.Hlsl5, "boolVector");
	assert hlsl.includes("    bool3 below = (low < high);\n" +
		"    bool2 noMore = (signedLow <= signedHigh);\n" +
		"    bool4 above = (wordLow > wordHigh);\n" +
		"    bool3 noLess = (low >= high);\n" +
		"    bool4 same = (wordLow == wordHigh);\n" +
		"    bool2 differ = (signedLow != signedHigh);\n" +
		"    float3 picked = (below ? high : low);\n" +
		"    int2 pickedSigned = ((!noMore) ? signedHigh : signedLow);\n" +
		"    uint4 pickedWords = (same ? wordHigh : wordLow);\n" +
		"    bool3 pickedFlags = (bool3(true, false, true) ? noLess : below);\n" +
		"    int whole = (all(differ) ? signedHigh.x : signedLow.x);\n");
	assert hlsl.includes("weigh(any(above), 1.0)") && hlsl.includes("any(!same)");
}

test "MSL spells a select by a bool vector as metal's select" {
	const msl = printedFor(programOf(), 1, ShaderTarget.Msl, "boolVector");
	assert msl.includes("  bool3 below = (in.low < in.high);\n" +
		"  bool2 noMore = (in.signedLow <= in.signedHigh);\n" +
		"  bool4 above = (in.wordLow > in.wordHigh);\n" +
		"  bool3 noLess = (in.low >= in.high);\n" +
		"  bool4 same = (in.wordLow == in.wordHigh);\n" +
		"  bool2 differ = (in.signedLow != in.signedHigh);\n" +
		"  float3 picked = select(in.low, in.high, below);\n" +
		"  int2 pickedSigned = select(in.signedLow, in.signedHigh, (!noMore));\n" +
		"  uint4 pickedWords = select(in.wordLow, in.wordHigh, same);\n" +
		"  bool3 pickedFlags = select(below, noLess, bool3(true, false, true));\n" +
		"  int whole = select(in.signedLow.x, in.signedHigh.x, all(differ));\n");
	assert msl.includes("weigh(any(above), 1.0)") && msl.includes("any((!same))");
}

function opcodes(words: uint32[][], opcode: int32): int32 {
	return words.filter((i) => opcodeOf(i) == opcode).length as int32;
}

test "SPIR-V tests each lane with the opcode of its type and selects by a bool vector" {
	const m = programOf();
	const _vertex = spirvProbe(m, 0, "boolVector");
	const fs = spirvProbe(m, 1, "boolVector");
	assert opcodes(fs, 184) == 1;
	assert opcodes(fs, 179) == 1;
	assert opcodes(fs, 172) == 1;
	assert opcodes(fs, 190) == 1;
	assert opcodes(fs, 170) == 1;
	assert opcodes(fs, 171) == 1;
	assert opcodes(fs, 154) == 2;
	assert opcodes(fs, 155) == 2;
	assert opcodes(fs, 168) == 2;
	assert opcodes(fs, 169) == 6;
}

test "a bool is no attribute, varying, output, uniform or storage member" {
	let m = tiny(ShaderStage.Fragment, column(model()));
	assert irErrors(m).length == 0;
	m.ios.push(io("flags", ShaderStage.Fragment, IoDirection.In, BVEC3, Builtin.None));
	m.ios.push(io("lit", ShaderStage.Fragment, IoDirection.In, BOOL, Builtin.None));
	m.ios.push(io("front", ShaderStage.Fragment, IoDirection.In, BOOL, Builtin.FrontFacing));
	m.structs[0].members.push(field("mask", BVEC3));
	m.structs.push(block("Cell", [field("live", BOOL)]));
	m.resources.push(resource(ResourceKind.StorageBuffer, "cells", 1,
		arrayType(structType(1), -1)));
	const errors = irErrors(m);
	assert errors.length == 4;
	assert errors[0] == "resource 'params': a bool is no uniform or storage member, as WGSL's";
	assert errors[1] == "resource 'cells': a bool is no uniform or storage member, as WGSL's";
	assert errors[2] == "io 'flags': a bool is no attribute, varying or output, as WGSL's";
	assert errors[3] == "io 'lit': a bool is no attribute, varying or output, as WGSL's";
}
