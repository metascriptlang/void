// WGSL's non-square matrices authored in MetaScript: Mat2x3f, Mat2x4f, Mat3x2f, Mat3x4f, Mat4x2f and
// Mat4x3f with their constructors, products, transposes and column reads. The CPU oracle runs every
// overload against a fixed value, one entry uses the shapes through a uniform block, and the text
// per target, the probe files that naga, fxc and spirv-val read, and the refusals are pinned.

import { mkdir, writeFile } from "std/fs";
import { programModule, programSource, stageSource, stageWords } from "../shader/descriptor";
import { glslIr, glslLinked, glslLinkedIr } from "../shader/emit";
import { ShaderModule } from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import { reflectProgram } from "../shader/reflect";
import { opcodeOf, spirvProbe } from "./shaderProbeModules";
import {
	Mat2x2f,
	Mat2x3f,
	Mat2x4f,
	Mat3x2f,
	Mat3x3f,
	Mat3x4f,
	Mat4x2f,
	Mat4x3f,
	Mat4x4f,
	Vec2f,
	Vec3f,
	Vec4f,
	binding,
	builtin,
	mat2x2f,
	mat2x3f,
	mat2x4f,
	mat3x2f,
	mat3x3f,
	mat3x4f,
	mat4x2f,
	mat4x3f,
	mat4x4f,
	transpose,
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

export struct Shapes {
	wide: Mat2x3f;
	tall: Mat4x3f;
	basis: Mat3x4f;
	extra: Mat2x4f;
}

export struct ShapeBindings {
	@binding(0) shapes: Shapes;
}

export struct NarrowShapes {
	flat: Mat3x2f;
}

export struct NarrowBindings {
	@binding(0) narrow: NarrowShapes;
}

export function shapeVs(input: Corner): Parts {
	return {
		position: vec4f(input.position.x, input.position.y, 0.0, 1.0),
		amount: vec3f(0.5, 1.5, 2.5),
	};
}

export function shapeFs(input: Parts, b: ShapeBindings): Vec4f {
	const across = b.shapes.wide * vec2f(input.amount.x, input.amount.y);
	const back = input.amount * b.shapes.wide;
	const tall = b.shapes.tall * vec4f(input.amount, 1.0);
	const lifted = b.shapes.basis * b.shapes.wide;
	const flipped = transpose(b.shapes.wide);
	const small = flipped * input.amount;
	const own = mat3x2f(vec2f(1.0, 2.0), vec2f(3.0, 4.0), vec2f(5.0, 6.0));
	const column = b.shapes.extra.columns[1];
	return vec4f(
		across.x + back.y + tall.z,
		lifted.columns[1].w + small.x,
		own.columns[2].y + column.z,
		flipped.columns[2].x,
	);
}

export function narrowFs(input: Parts, b: NarrowBindings): Vec4f {
	return vec4f(b.narrow.flat * input.amount, 0.0, 1.0);
}

function shapeBindings(): ShapeBindings {
	return {
		shapes: {
			wide: mat2x3f(vec3f(1.0, 2.0, 3.0), vec3f(4.0, 5.0, 6.0)),
			tall: mat4x3f(vec3f(1.0, 0.0, 0.0), vec3f(0.0, 1.0, 0.0), vec3f(0.0, 0.0, 1.0), vec3f(1.0, 1.0, 1.0)),
			basis: mat3x4f(vec4f(1.0, 0.0, 0.0, 0.0), vec4f(0.0, 1.0, 0.0, 0.0), vec4f(0.0, 0.0, 1.0, 1.0)),
			extra: mat2x4f(vec4f(1.0, 2.0, 3.0, 4.0), vec4f(5.0, 6.0, 7.0, 8.0)),
		},
	};
}

function close2(a: Vec2f, b: Vec2f): boolean { return Math.abs(a.x - b.x) < 0.0001 && Math.abs(a.y - b.y) < 0.0001; }

function close3(a: Vec3f, b: Vec3f): boolean {
	return close2(vec2f(a.x, a.y), vec2f(b.x, b.y)) && Math.abs(a.z - b.z) < 0.0001;
}

function close4(a: Vec4f, b: Vec4f): boolean {
	return close3(vec3f(a.x, a.y, a.z), vec3f(b.x, b.y, b.z)) && Math.abs(a.w - b.w) < 0.0001;
}

// Column j holds j * rows + 1, j * rows + 2 and so on, so no two shapes share a value pattern.
function entry(rows: int32, column: int32, lane: int32): float32 { return (column * rows + lane + 1) as float32; }

function column2(c: int32): Vec2f { return vec2f(entry(2, c, 0), entry(2, c, 1)); }
function column3(c: int32): Vec3f { return vec3f(entry(3, c, 0), entry(3, c, 1), entry(3, c, 2)); }
function column4(c: int32): Vec4f { return vec4f(entry(4, c, 0), entry(4, c, 1), entry(4, c, 2), entry(4, c, 3)); }

function m2x2(): Mat2x2f { return mat2x2f(column2(0), column2(1)); }
function m2x3(): Mat2x3f { return mat2x3f(column3(0), column3(1)); }
function m2x4(): Mat2x4f { return mat2x4f(column4(0), column4(1)); }
function m3x2(): Mat3x2f { return mat3x2f(column2(0), column2(1), column2(2)); }
function m3x3(): Mat3x3f { return mat3x3f(column3(0), column3(1), column3(2)); }
function m3x4(): Mat3x4f { return mat3x4f(column4(0), column4(1), column4(2)); }
function m4x2(): Mat4x2f { return mat4x2f(column2(0), column2(1), column2(2), column2(3)); }
function m4x3(): Mat4x3f { return mat4x3f(column3(0), column3(1), column3(2), column3(3)); }
function m4x4(): Mat4x4f { return mat4x4f(column4(0), column4(1), column4(2), column4(3)); }

function probe(lane: int32): float32 { return lane == 0 ? 1.5 : lane == 1 ? -2.0 : lane == 2 ? 0.5 : 3.0; }
function p2(): Vec2f { return vec2f(probe(0), probe(1)); }
function p3(): Vec3f { return vec3f(probe(0), probe(1), probe(2)); }
function p4(): Vec4f { return vec4f(probe(0), probe(1), probe(2), probe(3)); }

function lanes(v: Vec2f): float32[] { return [v.x, v.y]; }
function lanes(v: Vec3f): float32[] { return [v.x, v.y, v.z]; }
function lanes(v: Vec4f): float32[] { return [v.x, v.y, v.z, v.w]; }

function same(a: float32[], b: float32[]): boolean {
	if (a.length != b.length) { return false; }
	for (let i = 0; i < a.length; i++) {
		if (Math.abs(a[i] - b[i]) > 0.0001) { return false; }
	}
	return true;
}

// What a matrix of this shape does to the probe, written lane by lane from its entries.
function matVec(columns: int32, rows: int32): float32[] {
	let out: float32[] = [];
	for (let i = 0; i < rows; i++) {
		let sum: float32 = 0.0;
		for (let j = 0; j < columns; j++) { sum += entry(rows, j, i) * probe(j); }
		out.push(sum);
	}
	return out;
}

function vecMat(columns: int32, rows: int32): float32[] {
	let out: float32[] = [];
	for (let j = 0; j < columns; j++) {
		let sum: float32 = 0.0;
		for (let i = 0; i < rows; i++) { sum += probe(i) * entry(rows, j, i); }
		out.push(sum);
	}
	return out;
}

function transposedColumn(columns: int32, rows: int32, at: int32): float32[] {
	let out: float32[] = [];
	for (let j = 0; j < columns; j++) { out.push(entry(rows, j, at)); }
	return out;
}

test "a non-square matrix keeps its columns, its rows are the column's lanes" {
	const wide = mat2x3f(vec3f(1.0, 2.0, 3.0), vec3f(4.0, 5.0, 6.0));
	assert wide.columns.length == 2 && wide.columns[1].z == 6.0 && wide.columns[0].y == 2.0;
	const tall = mat3x2f(vec2f(1.0, 2.0), vec2f(3.0, 4.0), vec2f(5.0, 6.0));
	assert tall.columns.length == 3 && tall.columns[2].y == 6.0 && tall.columns[1].x == 3.0;
	assert m4x3().columns.length == 4 && m4x3().columns[3].z == 12.0;
	assert m2x4().columns.length == 2 && m2x4().columns[1].w == 8.0;
}

test "a matrix times a vector sums its columns, a vector times a matrix dots them" {
	const wide = mat2x3f(vec3f(1.0, 2.0, 3.0), vec3f(4.0, 5.0, 6.0));
	assert close3(wide * vec2f(10.0, 100.0), vec3f(410.0, 520.0, 630.0));
	assert close2(vec3f(1.0, 2.0, 3.0) * wide, vec2f(14.0, 32.0));
	const tall = mat3x2f(vec2f(1.0, 2.0), vec2f(3.0, 4.0), vec2f(5.0, 6.0));
	assert close2(tall * vec3f(1.0, 10.0, 100.0), vec2f(531.0, 642.0));
	assert close3(vec2f(1.0, 10.0) * tall, vec3f(21.0, 43.0, 65.0));
	const b = shapeBindings();
	assert close3(b.shapes.wide * vec2f(0.5, 1.5), vec3f(6.5, 8.5, 10.5));
	assert close2(vec3f(0.5, 1.5, 2.5) * b.shapes.wide, vec2f(11.0, 24.5));
	assert close3(b.shapes.tall * vec4f(0.5, 1.5, 2.5, 1.0), vec3f(1.5, 2.5, 3.5));
}

test "a matrix times a matrix answers the columns of the left one applied to the right one" {
	const b = shapeBindings();
	const lifted = b.shapes.basis * b.shapes.wide;
	assert lifted.columns.length == 2;
	assert close4(lifted.columns[0], vec4f(1.0, 2.0, 3.0, 3.0));
	assert close4(lifted.columns[1], vec4f(4.0, 5.0, 6.0, 6.0));
}

test "transpose swaps columns and rows" {
	const flipped = transpose(mat2x3f(vec3f(1.0, 2.0, 3.0), vec3f(4.0, 5.0, 6.0)));
	assert flipped.columns.length == 3;
	assert close2(flipped.columns[0], vec2f(1.0, 4.0));
	assert close2(flipped.columns[1], vec2f(2.0, 5.0));
	assert close2(flipped.columns[2], vec2f(3.0, 6.0));
	const back = transpose(flipped);
	assert back.columns.length == 2 && close3(back.columns[1], vec3f(4.0, 5.0, 6.0));
}

test "the entry runs on the CPU" {
	const parts: Parts = { position: vec4f(0.0), amount: vec3f(0.5, 1.5, 2.5) };
	const color = shapeFs(parts, shapeBindings());
	assert close4(color, vec4f(34.5, 17.0, 13.0, 3.0));
	const narrow: NarrowBindings = { narrow: { flat: mat3x2f(vec2f(1.0, 2.0), vec2f(3.0, 4.0), vec2f(5.0, 6.0)) } };
	assert close4(narrowFs(parts, narrow), vec4f(0.5 + 4.5 + 12.5, 1.0 + 6.0 + 15.0, 0.0, 1.0));
}

test "every non-square product agrees with the products of its columns" {
	assert same(lanes(m2x2() * p2()), matVec(2, 2));
	assert same(lanes(m2x3() * p2()), matVec(2, 3));
	assert same(lanes(m2x4() * p2()), matVec(2, 4));
	assert same(lanes(m3x2() * p3()), matVec(3, 2));
	assert same(lanes(m3x3() * p3()), matVec(3, 3));
	assert same(lanes(m3x4() * p3()), matVec(3, 4));
	assert same(lanes(m4x2() * p4()), matVec(4, 2));
	assert same(lanes(m4x3() * p4()), matVec(4, 3));
	assert same(lanes(m4x4() * p4()), matVec(4, 4));
	assert same(lanes(p2() * m2x2()), vecMat(2, 2));
	assert same(lanes(p3() * m2x3()), vecMat(2, 3));
	assert same(lanes(p4() * m2x4()), vecMat(2, 4));
	assert same(lanes(p2() * m3x2()), vecMat(3, 2));
	assert same(lanes(p3() * m3x3()), vecMat(3, 3));
	assert same(lanes(p4() * m3x4()), vecMat(3, 4));
	assert same(lanes(p2() * m4x2()), vecMat(4, 2));
	assert same(lanes(p3() * m4x3()), vecMat(4, 3));
	assert same(lanes(p4() * m4x4()), vecMat(4, 4));
	assert same(lanes(m2x2() * m2x2() * p2()), lanes(m2x2() * (m2x2() * p2())));
	assert same(lanes(m2x2() * m3x2() * p3()), lanes(m2x2() * (m3x2() * p3())));
	assert same(lanes(m2x2() * m4x2() * p4()), lanes(m2x2() * (m4x2() * p4())));
	assert same(lanes(m2x3() * m2x2() * p2()), lanes(m2x3() * (m2x2() * p2())));
	assert same(lanes(m2x3() * m3x2() * p3()), lanes(m2x3() * (m3x2() * p3())));
	assert same(lanes(m2x3() * m4x2() * p4()), lanes(m2x3() * (m4x2() * p4())));
	assert same(lanes(m2x4() * m2x2() * p2()), lanes(m2x4() * (m2x2() * p2())));
	assert same(lanes(m2x4() * m3x2() * p3()), lanes(m2x4() * (m3x2() * p3())));
	assert same(lanes(m2x4() * m4x2() * p4()), lanes(m2x4() * (m4x2() * p4())));
	assert same(lanes(m3x2() * m2x3() * p2()), lanes(m3x2() * (m2x3() * p2())));
	assert same(lanes(m3x2() * m3x3() * p3()), lanes(m3x2() * (m3x3() * p3())));
	assert same(lanes(m3x2() * m4x3() * p4()), lanes(m3x2() * (m4x3() * p4())));
	assert same(lanes(m3x3() * m2x3() * p2()), lanes(m3x3() * (m2x3() * p2())));
	assert same(lanes(m3x3() * m3x3() * p3()), lanes(m3x3() * (m3x3() * p3())));
	assert same(lanes(m3x3() * m4x3() * p4()), lanes(m3x3() * (m4x3() * p4())));
	assert same(lanes(m3x4() * m2x3() * p2()), lanes(m3x4() * (m2x3() * p2())));
	assert same(lanes(m3x4() * m3x3() * p3()), lanes(m3x4() * (m3x3() * p3())));
	assert same(lanes(m3x4() * m4x3() * p4()), lanes(m3x4() * (m4x3() * p4())));
	assert same(lanes(m4x2() * m2x4() * p2()), lanes(m4x2() * (m2x4() * p2())));
	assert same(lanes(m4x2() * m3x4() * p3()), lanes(m4x2() * (m3x4() * p3())));
	assert same(lanes(m4x2() * m4x4() * p4()), lanes(m4x2() * (m4x4() * p4())));
	assert same(lanes(m4x3() * m2x4() * p2()), lanes(m4x3() * (m2x4() * p2())));
	assert same(lanes(m4x3() * m3x4() * p3()), lanes(m4x3() * (m3x4() * p3())));
	assert same(lanes(m4x3() * m4x4() * p4()), lanes(m4x3() * (m4x4() * p4())));
	assert same(lanes(m4x4() * m2x4() * p2()), lanes(m4x4() * (m2x4() * p2())));
	assert same(lanes(m4x4() * m3x4() * p3()), lanes(m4x4() * (m3x4() * p3())));
	assert same(lanes(m4x4() * m4x4() * p4()), lanes(m4x4() * (m4x4() * p4())));
	assert same(lanes(transpose(m2x3()).columns[0]), transposedColumn(2, 3, 0));
	assert same(lanes(transpose(m2x3()).columns[1]), transposedColumn(2, 3, 1));
	assert same(lanes(transpose(m2x3()).columns[2]), transposedColumn(2, 3, 2));
	assert same(lanes(transpose(m2x4()).columns[0]), transposedColumn(2, 4, 0));
	assert same(lanes(transpose(m2x4()).columns[1]), transposedColumn(2, 4, 1));
	assert same(lanes(transpose(m2x4()).columns[2]), transposedColumn(2, 4, 2));
	assert same(lanes(transpose(m2x4()).columns[3]), transposedColumn(2, 4, 3));
	assert same(lanes(transpose(m3x2()).columns[0]), transposedColumn(3, 2, 0));
	assert same(lanes(transpose(m3x2()).columns[1]), transposedColumn(3, 2, 1));
	assert same(lanes(transpose(m3x4()).columns[0]), transposedColumn(3, 4, 0));
	assert same(lanes(transpose(m3x4()).columns[1]), transposedColumn(3, 4, 1));
	assert same(lanes(transpose(m3x4()).columns[2]), transposedColumn(3, 4, 2));
	assert same(lanes(transpose(m3x4()).columns[3]), transposedColumn(3, 4, 3));
	assert same(lanes(transpose(m4x2()).columns[0]), transposedColumn(4, 2, 0));
	assert same(lanes(transpose(m4x2()).columns[1]), transposedColumn(4, 2, 1));
	assert same(lanes(transpose(m4x3()).columns[0]), transposedColumn(4, 3, 0));
	assert same(lanes(transpose(m4x3()).columns[1]), transposedColumn(4, 3, 1));
	assert same(lanes(transpose(m4x3()).columns[2]), transposedColumn(4, 3, 2));
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

function shapeProgram(): ShaderModule {
	const m = programModule(glslIr(shapeVs), glslLinkedIr(shapeFs, shapeVs), []);
	if (!m.ok) { throw new Error("shapeProgram: " + m.error); }
	return m.value;
}

function narrowProgram(): Result<ShaderModule, string> {
	return programModule(glslIr(shapeVs), glslLinkedIr(narrowFs, shapeVs), []);
}

function opcodes(words: uint32[][], opcode: int32): int32 {
	return words.filter((i) => opcodeOf(i) == opcode).length as int32;
}

test "the block of non-square matrices reads as its own columns on every GLSL" {
	const glsl450 = glslLinked(shapeFs, shapeVs);
	assert glsl450.includes("uniform shapes {\n    mat2x3 wide;\n    mat4x3 tall;\n    mat3x4 basis;\n    mat2x4 extra;\n};\n");
	assert glsl450.includes("    vec3 across = wide * vec2(amount.x, amount.y);\n    vec2 back = amount * wide;\n");
	assert glsl450.includes("    mat2x4 lifted = basis * wide;\n    mat3x2 flipped = transpose(wide);\n");
	assert glsl450.includes("    mat3x2 own = mat3x2(vec2(1.0, 2.0), vec2(3.0, 4.0), vec2(5.0, 6.0));\n");
	const columns = "mat2x3(shapes[0].xyz, shapes[1].xyz)";
	for (const target of [ShaderTarget.Glsl430, ShaderTarget.Glsl300es]) {
		const text = printedFor(shapeProgram(), 1, target, "shapeMat");
		assert text.includes("uniform ") && text.includes("vec4 shapes[11];\n");
		assert text.includes("across = " + columns + " * vec2(amount.x, amount.y);\n");
		assert text.includes("back = amount * " + columns + ";\n");
		assert text.includes("tall = mat4x3(shapes[2].xyz, shapes[3].xyz, shapes[4].xyz, shapes[5].xyz) * vec4(amount, 1.0);\n");
		assert text.includes("lifted = mat3x4(shapes[6], shapes[7], shapes[8]) * " + columns + ";\n");
		assert text.includes("flipped = transpose(" + columns + ");\n");
		assert text.includes("column = mat2x4(shapes[9], shapes[10])[1];\n");
	}
}

test "HLSL lays a non-square matrix out as rows of the IR's columns and multiplies in the other order" {
	const text = printedFor(shapeProgram(), 1, ShaderTarget.Hlsl5, "shapeMat");
	assert text.includes("    row_major float2x3 _0_wide : packoffset(c0);\n    row_major float4x3 _0_tall : packoffset(c2);\n" +
		"    row_major float3x4 _0_basis : packoffset(c6);\n    row_major float2x4 _0_extra : packoffset(c9);\n");
	assert text.includes("float3 across = mul(float2(amount.x, amount.y), _0_wide);\n");
	assert text.includes("float2 back = mul(_0_wide, amount);\n");
	assert text.includes("float3 tall = mul(float4(amount, 1.0), _0_tall);\n");
	assert text.includes("row_major float2x4 lifted = mul(_0_wide, _0_basis);\n");
	assert text.includes("row_major float3x2 flipped = transpose(_0_wide);\n");
	assert text.includes("float2 small = mul(amount, flipped);\n");
	assert text.includes("float4 column = _0_extra[1];\n");
}

test "MSL and WGSL name the shape and multiply with the operator" {
	const msl = printedFor(shapeProgram(), 1, ShaderTarget.Msl, "shapeMat");
	assert msl.includes("struct Shapes {\n  float2x3 wide;\n  float4x3 tall;\n  float3x4 basis;\n  float2x4 extra;\n};\n");
	assert msl.includes("float3 across = (shapes.wide * float2(in.amount.x, in.amount.y));\n");
	assert msl.includes("float2 back = (in.amount * shapes.wide);\n");
	assert msl.includes("float2x4 lifted = (shapes.basis * shapes.wide);\n");
	assert msl.includes("float3x2 flipped = transpose(shapes.wide);\n");
	assert msl.includes("float3x2 own = float3x2(float2(1.0, 2.0), float2(3.0, 4.0), float2(5.0, 6.0));\n");
	const wgsl = printedFor(shapeProgram(), 1, ShaderTarget.Wgsl, "shapeMat");
	assert wgsl.includes("struct Shapes {\n  wide : mat2x3f,\n  tall : mat4x3f,\n  basis : mat3x4f,\n  extra : mat2x4f,\n}\n");
	assert wgsl.includes("var across : vec3f = (shapes.wide * vec2f(amount.x, amount.y));\n");
	assert wgsl.includes("var back : vec2f = (amount * shapes.wide);\n");
	assert wgsl.includes("var lifted : mat2x4f = (shapes.basis * shapes.wide);\n");
	assert wgsl.includes("var flipped : mat3x2f = transpose(shapes.wide);\n");
	assert wgsl.includes("var own : mat3x2f = mat3x2f(vec2f(1f, 2f), vec2f(3f, 4f), vec2f(5f, 6f));\n");
}

function decorations(words: uint32[][], decoration: uint32): uint32[][] {
	return words.filter((i) => opcodeOf(i) == 72 && i[3] == decoration);
}

test "SPIR-V multiplies each shape with its own opcode and strides every column at 16" {
	const m = shapeProgram();
	const _vertex = spirvProbe(m, 0, "shapeMat");
	const words = spirvProbe(m, 1, "shapeMat");
	assert opcodes(words, 145) == 3 && opcodes(words, 144) == 1 && opcodes(words, 146) == 1 && opcodes(words, 84) == 1;
	const strides = decorations(words, 7);
	assert strides.length == 4 && strides.filter((i) => i[4] == 16).length == 4;
	assert decorations(words, 5).length == 4;
}

test "a matrix of two rows is refused in a uniform block, by every printer that lays it out and by reflection" {
	const m = narrowProgram();
	assert m.ok;
	const reason = "member 'flat' is mat3x2, whose vec2 columns sit 8 bytes apart in WGSL's uniform layout " +
		"and 16 in std140; a uniform matrix has 3 or 4 rows";
	for (const target of [ShaderTarget.Glsl430, ShaderTarget.Glsl300es, ShaderTarget.Hlsl5, ShaderTarget.Msl]) {
		const text = stageSource(m.value, 1, target);
		assert !text.ok;
		assert text.error.includes(reason), text.ok ? "printed" : text.error;
	}
	const words = stageWords(m.value, 1);
	assert !words.ok && words.error.includes(reason);
	const reflected = reflectProgram(m.value, 0, 1, ShaderTarget.Wgsl);
	assert !reflected.ok && reflected.error.includes(reason);
	const wgsl = programSource(m.value, ShaderTarget.Wgsl);
	assert !wgsl.ok && wgsl.error.includes(reason);
}
