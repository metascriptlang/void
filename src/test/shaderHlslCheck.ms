// Hand-built IR modules printed as HLSL SM5: the blur keeps the committed interface, every
// intrinsic and statement kind has a spelling, and each refusal names its case. The printed files
// land in out/hlslProbe/ for scripts/validateHlsl.sh.

import { mkdir, writeFile } from "std/fs";
import {
	Access,
	AssignOp,
	BinaryOp,
	Builtin,
	ExprKind,
	Interpolation,
	Intrinsic,
	IoDirection,
	ResourceKind,
	Sampling,
	ScalarKind,
	ShaderCase,
	ShaderConstant,
	ShaderEntry,
	ShaderExpr,
	ShaderField,
	ShaderFunction,
	ShaderIo,
	ShaderModule,
	ShaderResource,
	ShaderStage,
	ShaderStmt,
	ShaderStruct,
	ShaderType,
	StmtKind,
	TexelFormat,
	TextureShape,
	UnaryOp,
	arrayType,
	assignOf,
	binaryOf,
	exprOf,
	featureOn,
	intrinsicOf,
	irErrors,
	literal,
	matrixType,
	samplerType,
	scalarType,
	stmtOf,
	storageTextureType,
	structType,
	textureType,
	vectorType,
} from "../shader/ir";
import { ShaderTarget, bindingSlots } from "../shader/layout";
import { printHlsl } from "../shader/printHlsl";
import { blurShaderModule } from "../void2d/shader2dModules";

const F32 = scalarType(ScalarKind.F32);
const I32 = scalarType(ScalarKind.I32);
const U32 = scalarType(ScalarKind.U32);
const BOOL = scalarType(ScalarKind.Bool);
const VEC2 = vectorType(ScalarKind.F32, 2);
const VEC3 = vectorType(ScalarKind.F32, 3);
const VEC4 = vectorType(ScalarKind.F32, 4);
const IVEC2 = vectorType(ScalarKind.I32, 2);
const UVEC3 = vectorType(ScalarKind.U32, 3);
const BVEC3 = vectorType(ScalarKind.Bool, 3);
const MAT2 = matrixType(2, 2);
const MAT3 = matrixType(3, 3);
const MAT4 = matrixType(4, 4);
const TEXTURE = textureType(TextureShape.D2, ScalarKind.F32);

function field(name: string, type: ShaderType): ShaderField {
	let f = new ShaderField();
	f.name = name;
	f.type = type;
	return f;
}

function block(name: string, members: ShaderField[]): ShaderStruct {
	let s = new ShaderStruct();
	s.name = name;
	s.members = members;
	return s;
}

function resource(kind: ResourceKind, name: string, binding: int32,
	type: ShaderType): ShaderResource {
	let r = new ShaderResource();
	r.kind = kind;
	r.name = name;
	r.group = kind == ResourceKind.UniformBlock ? 0 : kind == ResourceKind.Sampler ? 2 : 1;
	r.binding = binding;
	r.type = type;
	return r;
}

function io(name: string, stage: ShaderStage, direction: IoDirection, type: ShaderType,
	builtin: Builtin): ShaderIo {
	let v = new ShaderIo();
	v.name = name;
	v.stage = stage;
	v.direction = direction;
	v.type = type;
	v.builtin = builtin;
	return v;
}

function entry(name: string, stage: ShaderStage, functionIndex: int32): ShaderEntry {
	let e = new ShaderEntry();
	e.name = name;
	e.stage = stage;
	e.functionIndex = functionIndex;
	return e;
}

function shaderFunction(name: string, locals: ShaderField[], body: ShaderStmt[]): ShaderFunction {
	let f = new ShaderFunction();
	f.name = name;
	f.locals = locals;
	f.body = body;
	return f;
}

function ret(): ShaderStmt { return stmtOf(StmtKind.Return, new ShaderExpr(), []); }

function ioRead(index: int32, type: ShaderType): ShaderExpr {
	return exprOf(ExprKind.Io, type, index, []);
}

function member(resourceIndex: int32, index: int32, type: ShaderType): ShaderExpr {
	let e = exprOf(ExprKind.BlockMember, type, resourceIndex, []);
	e.member = index;
	return e;
}

function swizzle(base: ShaderExpr, type: ShaderType, components: int32[]): ShaderExpr {
	let e = exprOf(ExprKind.Swizzle, type, -1, [base]);
	e.components = components;
	return e;
}

function construct(type: ShaderType, operands: ShaderExpr[]): ShaderExpr {
	return exprOf(ExprKind.Construct, type, -1, operands);
}

function letOf(local: int32, init: ShaderExpr): ShaderStmt {
	let s = stmtOf(StmtKind.Let, init, []);
	s.local = local;
	return s;
}

function update(target: ShaderExpr, op: AssignOp, value: ShaderExpr): ShaderStmt {
	let s = assignOf(target, value);
	s.assign = op;
	return s;
}

function printed(m: ShaderModule, entryIndex: int32, program: int32[]): string {
	const slots = bindingSlots(m, program, ShaderTarget.Hlsl5);
	if (!slots.ok) { return slots.error; }
	const text = printHlsl(m, entryIndex, slots.value);
	if (!text.ok) { return text.error; }
	return text.value;
}

// blurVs and blurFs of src/void2d/shader2dGen.glsl, the blur weights left out, as
// shaderReflectCheck.ms builds them.
function blurModule(): ShaderModule {
	let m = new ShaderModule();
	m.structs = [block("BlurParams", [field("dir", VEC4)])];
	m.resources = [
		resource(ResourceKind.Texture, "srcTex", 0, TEXTURE),
		resource(ResourceKind.Sampler, "srcSmp", 0, samplerType()),
		resource(ResourceKind.UniformBlock, "blur_params", 0, structType(0)),
	];
	let fragColor = io("fragColor", ShaderStage.Fragment, IoDirection.Out, VEC4, Builtin.None);
	fragColor.location = 0;
	m.ios = [
		io("pos", ShaderStage.Vertex, IoDirection.In, VEC2, Builtin.None),
		io("uv0", ShaderStage.Vertex, IoDirection.In, VEC2, Builtin.None),
		io("clip", ShaderStage.Vertex, IoDirection.Out, VEC4, Builtin.Position),
		io("uv", ShaderStage.Vertex, IoDirection.Out, VEC2, Builtin.None),
		io("uv", ShaderStage.Fragment, IoDirection.In, VEC2, Builtin.None),
		fragColor,
	];
	const placed = construct(VEC4, [ioRead(0, VEC2), literal(F32, 0.0), literal(F32, 1.0)]);
	const sampled = intrinsicOf(Intrinsic.TextureSample, VEC4, [
		exprOf(ExprKind.Resource, TEXTURE, 0, []),
		exprOf(ExprKind.Resource, samplerType(), 1, []),
		ioRead(4, VEC2),
	]);
	m.functions = [
		shaderFunction("blurVs", [], [
			assignOf(ioRead(3, VEC2), ioRead(1, VEC2)),
			assignOf(ioRead(2, VEC4), placed),
			ret(),
		]),
		shaderFunction("blurFs", [], [
			assignOf(ioRead(5, VEC4), binaryOf(BinaryOp.Mul, VEC4, sampled, member(2, 0, VEC4))),
			ret(),
		]),
	];
	m.entries = [entry("blurVs", ShaderStage.Vertex, 0), entry("blurFs", ShaderStage.Fragment, 1)];
	return m;
}

// Each line that binds a register, a packoffset or a semantic, with the declared name left out,
// since the committed names (`gl_Position`, `_13_dir`) are SPIR-V ids.
function interfaceLines(text: string): string[] {
	let out: string[] = [];
	for (const line of text.split("\n")) {
		const bound = line.includes(" : register(") || line.includes(" : packoffset(") ||
			line.includes(" : TEXCOORD") || line.includes(" : SV_");
		if (!bound) { continue; }
		const words = line.trim().split(" ");
		out.push(words.slice(0, words.length - 3).join(" ") + " " +
			words.slice(words.length - 2).join(" "));
	}
	return out;
}

test "blur prints the interface of the committed HLSL" {
	const m = blurModule();
	assert irErrors(m).length == 0;
	const vs = printed(m, 0, [0, 1]);
	const fs = printed(m, 1, [0, 1]);
	assert interfaceLines(fs).join("\n") == [
		"cbuffer : register(b0)",
		"float4 : packoffset(c0);",
		"Texture2D<float4> : register(t0);",
		"SamplerState : register(s0);",
		"float2 : TEXCOORD0;",
		"float4 : SV_Target0;",
	].join("\n");
	assert interfaceLines(vs).join("\n") == [
		"float2 : TEXCOORD0;",
		"float2 : TEXCOORD1;",
		"float2 : TEXCOORD0;",
		"float4 : SV_Position;",
	].join("\n");
	assert fs.includes("cbuffer blur_params : register(b0)\n{\n    float4 _2_dir : packoffset(c0);\n};\n");
	assert fs.includes("fragColor = srcTex.Sample(srcSmp, uv) * _2_dir;\n");
	assert vs.includes("clip_1 = float4(pos, 0.0, 1.0);\n");
	assert !fs.includes("struct BlurParams");
	assert vs.includes("StageOutput main(StageInput stage_input)\n");
	when (windows) {
		const committed = blurShaderModule();
		assert interfaceLines(fs).join("\n") == interfaceLines(committed.fragmentCode).join("\n");
		assert interfaceLines(vs).join("\n") == interfaceLines(committed.vertexCode).join("\n");
	}
}

// Matrices from a uniform block, a std140 block with members off a vec4 boundary, vertex and
// instance index, and flat, linear and centroid varyings.
function vertexModule(): ShaderModule {
	let m = new ShaderModule();
	m.structs = [block("Camera", [
		field("viewProj", MAT4),
		field("offset", VEC4),
		field("tint", VEC3),
		field("scale", F32),
		field("shift", VEC2),
		field("normalMatrix", MAT3),
		field("lights", arrayType(VEC4, 2)),
	])];
	m.resources = [resource(ResourceKind.UniformBlock, "camera", 1, structType(0))];
	let flat = io("id", ShaderStage.Vertex, IoDirection.Out, U32, Builtin.None);
	flat.interpolation = Interpolation.Flat;
	let linear = io("uvL", ShaderStage.Vertex, IoDirection.Out, VEC2, Builtin.None);
	linear.interpolation = Interpolation.Linear;
	linear.sampling = Sampling.Centroid;
	m.ios = [
		io("position", ShaderStage.Vertex, IoDirection.In, VEC3, Builtin.None),
		io("color", ShaderStage.Vertex, IoDirection.In, VEC4, Builtin.None),
		io("vertexIndex", ShaderStage.Vertex, IoDirection.In, U32, Builtin.VertexIndex),
		io("instanceIndex", ShaderStage.Vertex, IoDirection.In, U32, Builtin.InstanceIndex),
		io("clip", ShaderStage.Vertex, IoDirection.Out, VEC4, Builtin.Position),
		io("shade", ShaderStage.Vertex, IoDirection.Out, VEC4, Builtin.None),
		flat,
		linear,
	];
	const placed = construct(VEC4, [ioRead(0, VEC3), literal(F32, 1.0)]);
	const turned = binaryOf(BinaryOp.Mul, VEC3, member(0, 5, MAT3), member(0, 2, VEC3));
	let light = exprOf(ExprKind.Index, VEC4, -1, [member(0, 6, arrayType(VEC4, 2)),
		literal(I32, 1.0)]);
	m.functions = [shaderFunction("probeVs", [], [
		assignOf(ioRead(4, VEC4), binaryOf(BinaryOp.Mul, VEC4, member(0, 0, MAT4), placed)),
		assignOf(ioRead(5, VEC4), binaryOf(BinaryOp.Add, VEC4,
			binaryOf(BinaryOp.Mul, VEC4, ioRead(1, VEC4), member(0, 3, F32)),
			binaryOf(BinaryOp.Add, VEC4, construct(VEC4, [turned, literal(F32, 0.0)]), light))),
		assignOf(ioRead(6, U32), binaryOf(BinaryOp.Add, U32, ioRead(2, U32), ioRead(3, U32))),
		assignOf(ioRead(7, VEC2), binaryOf(BinaryOp.Add, VEC2, member(0, 4, VEC2),
			swizzle(member(0, 1, VEC4), VEC2, [0, 1]))),
		ret(),
	])];
	m.entries = [entry("probeVs", ShaderStage.Vertex, 0)];
	return m;
}

test "the vertex probe reads matrices through mul and blocks through packoffset" {
	const m = vertexModule();
	assert irErrors(m).length == 0;
	const text = printed(m, 0, [0]);
	assert text.includes("cbuffer camera : register(b1)\n{\n" +
		"    row_major float4x4 _0_viewProj : packoffset(c0);\n" +
		"    float4 _0_offset : packoffset(c4);\n" +
		"    float3 _0_tint : packoffset(c5);\n" +
		"    float _0_scale : packoffset(c5.w);\n" +
		"    float2 _0_shift : packoffset(c6);\n" +
		"    row_major float3x3 _0_normalMatrix : packoffset(c7);\n" +
		"    float4 _0_lights[2] : packoffset(c10);\n};\n");
	assert text.includes("clip_1 = mul(float4(position, 1.0), _0_viewProj);\n");
	assert text.includes("mul(_0_tint, _0_normalMatrix)");
	assert text.includes("    uint vertexIndex : SV_VertexID;\n    uint instanceIndex : SV_InstanceID;\n");
	assert text.includes("struct StageOutput\n{\n    float4 shade : TEXCOORD0;\n" +
		"    nointerpolation uint id : TEXCOORD1;\n    noperspective centroid float2 uvL : TEXCOORD2;\n" +
		"    float4 clip_1 : SV_Position;\n};\n");
}

const SAMPLE = structType(1);
const LOCAL_TYPES = [F32, VEC2, VEC3, VEC4, MAT2, MAT3, MAT4, I32, U32, BOOL, BVEC3,
	arrayType(F32, 3), IVEC2, SAMPLE, I32, I32, IVEC2];
const LOCAL_NAMES = ["f", "v2", "v3", "v4", "m2", "m3", "m4", "i", "u", "b", "b3", "arr", "i2",
	"s", "k", "j", "size"];

function local(index: int32): ShaderExpr {
	return exprOf(ExprKind.Local, LOCAL_TYPES[index], index, []);
}

function f32(value: float64): ShaderExpr { return literal(F32, value); }

function i32(value: float64): ShaderExpr { return literal(I32, value); }

function setLocal(index: int32, op: Intrinsic, args: ShaderExpr[]): ShaderStmt {
	return assignOf(local(index), intrinsicOf(op, LOCAL_TYPES[index], args));
}

function binary(op: BinaryOp, type: ShaderType, a: ShaderExpr, b: ShaderExpr): ShaderExpr {
	return binaryOf(op, type, a, b);
}

function compare(op: BinaryOp, a: ShaderExpr, b: ShaderExpr): ShaderExpr {
	return binaryOf(op, BOOL, a, b);
}

function ifOf(condition: ShaderExpr, body: ShaderStmt[], otherwise: ShaderStmt[]): ShaderStmt {
	let s = stmtOf(StmtKind.If, condition, body);
	s.otherwise = otherwise;
	return s;
}

function caseOf(labels: ShaderExpr[], isDefault: boolean, body: ShaderStmt[]): ShaderCase {
	let k = new ShaderCase();
	k.labels = labels;
	k.isDefault = isDefault;
	k.body = body;
	return k;
}

function single(kind: StmtKind): ShaderStmt { return stmtOf(kind, new ShaderExpr(), []); }

function fragmentModule(): ShaderModule {
	let m = new ShaderModule();
	m.structs = [
		block("Material", [field("tint", VEC4), field("model", MAT4)]),
		block("Sample", [field("weight", F32), field("offset", VEC2)]),
	];
	m.resources = [
		resource(ResourceKind.UniformBlock, "material", 0, structType(0)),
		resource(ResourceKind.Texture, "albedo", 0, TEXTURE),
		resource(ResourceKind.Sampler, "albedoSmp", 0, samplerType()),
	];
	let weights = new ShaderConstant();
	weights.name = "weights";
	weights.type = arrayType(F32, 3);
	weights.value = construct(weights.type, [f32(0.25), f32(0.5), f32(0.25)]);
	m.constants = [weights];
	let id = io("id", ShaderStage.Fragment, IoDirection.In, U32, Builtin.None);
	id.interpolation = Interpolation.Flat;
	let color = io("color", ShaderStage.Fragment, IoDirection.Out, VEC4, Builtin.None);
	color.location = 0;
	let extra = io("extra", ShaderStage.Fragment, IoDirection.Out, VEC4, Builtin.None);
	extra.location = 1;
	m.ios = [
		io("shade", ShaderStage.Fragment, IoDirection.In, VEC4, Builtin.None),
		id,
		io("frag", ShaderStage.Fragment, IoDirection.In, VEC4, Builtin.Position),
		io("facing", ShaderStage.Fragment, IoDirection.In, BOOL, Builtin.FrontFacing),
		color,
		extra,
		io("depth", ShaderStage.Fragment, IoDirection.Out, F32, Builtin.FragDepth),
	];
	const texture = exprOf(ExprKind.Resource, TEXTURE, 1, []);
	const sampler = exprOf(ExprKind.Resource, samplerType(), 2, []);
	const [f, v2, v3, v4, m2, m3, m4, i, u, b, b3, arr, i2, s, k, j] =
		[local(0), local(1), local(2), local(3), local(4), local(5), local(6), local(7), local(8),
			local(9), local(10), local(11), local(12), local(13), local(14), local(15)];
	let weight = exprOf(ExprKind.Field, F32, 0, [s]);
	let offset = exprOf(ExprKind.Field, VEC2, 1, [s]);
	let shadeCall = exprOf(ExprKind.Call, VEC3, 1, [v3, f]);

	let body: ShaderStmt[] = [
		letOf(0, f32(0.5)),
		letOf(1, swizzle(ioRead(0, VEC4), VEC2, [0, 1])),
		letOf(2, construct(VEC3, [v2, f32(1.0)])),
		letOf(3, intrinsicOf(Intrinsic.TextureSample, VEC4, [texture, sampler, v2])),
		letOf(4, construct(MAT2, [v2, v2])),
		letOf(5, construct(MAT3, [v3, v3, v3])),
		letOf(6, construct(MAT4, [v4, v4, v4, v4])),
		letOf(7, exprOf(ExprKind.Convert, I32, -1, [f])),
		letOf(8, ioRead(1, U32)),
		letOf(9, ioRead(3, BOOL)),
		letOf(10, intrinsicOf(Intrinsic.LessThanEqual, BVEC3, [v3, v3])),
		letOf(11, construct(arrayType(F32, 3), [f, f, f32(2.0)])),
		letOf(12, exprOf(ExprKind.Convert, IVEC2, -1, [v2])),
		letOf(13, construct(SAMPLE, [f, v2])),
		letOf(16, intrinsicOf(Intrinsic.TextureDimensions, IVEC2, [texture, sampler, i32(0.0)])),
	];
	for (const op of [Intrinsic.Abs, Intrinsic.Sqrt, Intrinsic.InverseSqrt, Intrinsic.Exp,
		Intrinsic.Exp2, Intrinsic.Log, Intrinsic.Log2, Intrinsic.Sin, Intrinsic.Cos, Intrinsic.Tan,
		Intrinsic.Asin, Intrinsic.Acos, Intrinsic.Atan, Intrinsic.Sinh, Intrinsic.Cosh,
		Intrinsic.Tanh, Intrinsic.Degrees, Intrinsic.Radians, Intrinsic.Dpdy]) {
		body.push(setLocal(0, op, [f]));
	}
	for (const op of [Intrinsic.Pow, Intrinsic.Atan2, Intrinsic.Step]) {
		body.push(setLocal(0, op, [f, f]));
	}
	for (const op of [Intrinsic.Clamp, Intrinsic.Smoothstep, Intrinsic.Fma]) {
		body.push(setLocal(0, op, [f, f, f]));
	}
	for (const op of [Intrinsic.Sign, Intrinsic.Floor, Intrinsic.Ceil, Intrinsic.Trunc,
		Intrinsic.Round, Intrinsic.Fract, Intrinsic.Normalize]) {
		body.push(setLocal(2, op, [v3]));
	}
	for (const op of [Intrinsic.Min, Intrinsic.Max, Intrinsic.Cross, Intrinsic.Reflect]) {
		body.push(setLocal(2, op, [v3, v3]));
	}
	body.push(setLocal(2, Intrinsic.Mix, [v3, v3, f]));
	body.push(setLocal(2, Intrinsic.Refract, [v3, v3, f]));
	body.push(setLocal(2, Intrinsic.FaceForward, [v3, v3, v3]));
	body.push(setLocal(2, Intrinsic.Select, [v3, v3, b3]));
	body.push(setLocal(0, Intrinsic.Select, [f, f32(1.0), b]));
	body.push(setLocal(3, Intrinsic.Saturate, [v4]));
	body.push(setLocal(0, Intrinsic.Dot, [v3, v3]));
	body.push(setLocal(0, Intrinsic.Length, [v3]));
	body.push(setLocal(0, Intrinsic.Distance, [v3, v3]));
	body.push(setLocal(0, Intrinsic.Determinant, [m3]));
	body.push(setLocal(6, Intrinsic.Transpose, [m4]));
	body.push(setLocal(6, Intrinsic.Inverse, [m4]));
	body.push(setLocal(5, Intrinsic.Inverse, [m3]));
	body.push(setLocal(4, Intrinsic.Inverse, [m2]));
	body.push(setLocal(5, Intrinsic.UpperLeft3x3, [m4]));
	body.push(setLocal(1, Intrinsic.Dpdx, [v2]));
	body.push(setLocal(1, Intrinsic.Fwidth, [v2]));
	body.push(setLocal(7, Intrinsic.Sign, [i]));
	body.push(setLocal(3, Intrinsic.TextureLoad, [texture, sampler, i2, i32(0.0)]));

	const twice = assignOf(f, binary(BinaryOp.Mul, F32, f, f32(2.0)));
	let firstLoop = stmtOf(StmtKind.For, compare(BinaryOp.Less, k, i32(3.0)), [
		update(f, AssignOp.Add, exprOf(ExprKind.Index, F32, -1,
			[exprOf(ExprKind.Constant, arrayType(F32, 3), 0, []), k])),
		ifOf(compare(BinaryOp.Equal, k, i32(1.0)), [single(StmtKind.Continue)], []),
	]);
	firstLoop.init = [letOf(14, i32(0.0))];
	firstLoop.update = [update(k, AssignOp.Increment, new ShaderExpr())];
	let secondLoop = stmtOf(StmtKind.For, compare(BinaryOp.Less, k, j), [
		update(f, AssignOp.Add, exprOf(ExprKind.Index, F32, -1, [arr, k])),
	]);
	secondLoop.init = [letOf(14, i32(0.0)), letOf(15, i32(3.0))];
	secondLoop.update = [update(k, AssignOp.Increment, new ShaderExpr()),
		update(j, AssignOp.Decrement, new ShaderExpr())];
	let choose = stmtOf(StmtKind.Switch, i, []);
	choose.cases = [
		caseOf([i32(0.0), i32(1.0)], false, [update(f, AssignOp.Add, f32(1.0))]),
		caseOf([], true, [update(f, AssignOp.Sub, f32(1.0))]),
	];
	let zw = swizzle(v4, VEC2, [2, 3]);
	const statements: ShaderStmt[] = [
		stmtOf(StmtKind.Block, new ShaderExpr(), [twice]),
		update(v4, AssignOp.Add, v4),
		update(v4, AssignOp.Sub, v4),
		update(v4, AssignOp.Mul, m4),
		update(f, AssignOp.Mul, f32(2.0)),
		update(f, AssignOp.Div, f32(2.0)),
		update(f, AssignOp.Mod, f32(2.0)),
		update(u, AssignOp.Mod, literal(U32, 4.0)),
		update(i, AssignOp.Increment, new ShaderExpr()),
		update(i, AssignOp.Decrement, new ShaderExpr()),
		assignOf(zw, v2),
		stmtOf(StmtKind.Call, shadeCall, []),
		assignOf(v3, shadeCall),
		ifOf(compare(BinaryOp.Less, f, f32(0.0)), [single(StmtKind.Discard)],
			[assignOf(f, exprOf(ExprKind.Unary, F32, -1, [f]))]),
		stmtOf(StmtKind.While, b, [
			assignOf(b, exprOf(ExprKind.Unary, BOOL, -1, [b])),
			ifOf(compare(BinaryOp.Greater, f, f32(2.0)), [single(StmtKind.Break)], []),
		]),
		firstLoop,
		secondLoop,
		choose,
		assignOf(u, binary(BinaryOp.BitAnd, U32, u, literal(U32, 3.0))),
		assignOf(i, binary(BinaryOp.Div, I32, i, i32(2.0))),
		assignOf(b, binary(BinaryOp.LogicalAnd, BOOL, b, compare(BinaryOp.GreaterEqual, f, f32(0.0)))),
		assignOf(b, binary(BinaryOp.LogicalOr, BOOL, b, compare(BinaryOp.LessEqual, f, f32(1.0)))),
		assignOf(b, compare(BinaryOp.Equal, v3, v3)),
		assignOf(b, compare(BinaryOp.NotEqual, v3, v3)),
		assignOf(b, compare(BinaryOp.NotEqual, f, f32(1.0))),
		assignOf(f, exprOf(ExprKind.Conditional, F32, -1, [b, f, f32(1.0)])),
		assignOf(f, binary(BinaryOp.Add, F32, weight, exprOf(ExprKind.Index, F32, -1, [v3, i]))),
		assignOf(v2, binary(BinaryOp.Sub, VEC2, offset, swizzle(ioRead(2, VEC4), VEC2, [0, 1]))),
		assignOf(v4, exprOf(ExprKind.Index, VEC4, -1, [m4, i32(1.0)])),
		assignOf(v4, binary(BinaryOp.Mul, VEC4, member(0, 1, MAT4),
			binary(BinaryOp.Mul, VEC4, v4, member(0, 0, VEC4)))),
		assignOf(f, binary(BinaryOp.Add, F32, f, exprOf(ExprKind.Convert, F32, -1, [
			binary(BinaryOp.Add, U32, u, literal(U32, 2891336453.0))]))),
		assignOf(ioRead(4, VEC4), v4),
		assignOf(ioRead(5, VEC4), construct(VEC4, [v3, f])),
		assignOf(ioRead(6, F32), f),
		ret(),
	];
	for (const st of statements) { body.push(st); }

	let shadeFn = shaderFunction("shade", [], [stmtOf(StmtKind.Return,
		binary(BinaryOp.Mul, VEC3, exprOf(ExprKind.Param, VEC3, 0, []),
			exprOf(ExprKind.Param, F32, 1, [])), [])]);
	shadeFn.params = [field("x", VEC3), field("k", F32)];
	shadeFn.result = VEC3;
	let locals: ShaderField[] = [];
	for (let n = 0; n < LOCAL_TYPES.length; n++) { locals.push(field(LOCAL_NAMES[n], LOCAL_TYPES[n])); }
	m.functions = [shaderFunction("probeFs", locals, body), shadeFn];
	m.entries = [entry("probeFs", ShaderStage.Fragment, 0)];
	return m;
}

test "the fragment probe spells every intrinsic and statement" {
	const m = fragmentModule();
	assert irErrors(m).length == 0;
	const text = printed(m, 0, [0]);
	for (const piece of [
		"static const float weights[3] = { 0.25, 0.5, 0.25 };\n",
		"float3 shade_1(float3 x, float k)\n{\n    return x * k;\n}\n",
		"float arr[3] = { f, f, 2.0 };\n",
		"Sample s = makeSample(f, v2);\n",
		"int2 size = int2(textureSize(albedo, uint(0)));\n",
		"bool3 b3 = v3 <= v3;\n",
		"f = rsqrt(f);\n", "f = mad(f, f, f);\n", "v3 = float3(sign(v3));\n", "v3 = frac(v3);\n",
		"v3 = lerp(v3, v3, f);\n", "v3 = faceforward(v3, v3, v3);\n", "v3 = (b3 ? v3 : v3);\n",
		"f = (b ? 1.0 : f);\n", "m4 = inverse(m4);\n", "m3 = ((float3x3)m4);\n",
		"v2 = ddx(v2);\n", "f = ddy(f);\n", "i = sign(i);\n", "v4 = albedo.Load(int3(i2, 0));\n",
		"v4 = mul(m4, v4);\n", "f = fmod(f, 2.0);\n", "u = u % 4u;\n", "v4.zw = v2;\n",
		"shade_1(v3, f);\n", "if (f < 0.0)\n    {\n        discard;\n    }\n    else\n",
		"for (int k = 0; k < 3; k++)\n", "f += weights[k];\n",
		"    {\n        int k = 0;\n        int j = 3;\n        for (; k < j; k++, j--)\n",
		"        case 0:\n        case 1:\n        {\n            f += 1.0;\n            break;\n",
		"        default:\n", "b = all(v3 == v3);\n", "b = any(v3 != v3);\n", "i = i / 2;\n",
		"f = s.weight + v3[i];\n", "v2 = s.offset - frag.xy;\n", "v4 = m4[1];\n",
		"v4 = mul(v4 * _0_tint, _0_model);\n", "f = b ? f : 1.0;\n", "f = f + float(u + 2891336453u);\n",
		"    frag.w = 1.0 / frag.w;\n", "    nointerpolation uint id : TEXCOORD1;\n",
		"    float4 frag : SV_Position;\n    bool facing : SV_IsFrontFace;\n",
		"    float4 extra : SV_Target1;\n    float depth : SV_Depth;\n",
	]) {
		if (!text.includes(piece)) { console.log("missing: " + piece); }
		assert text.includes(piece);
	}
}

const PROBE_DIR = "out/hlslProbe";

function probe(name: string, text: string): boolean {
	const _made = mkdir(PROBE_DIR);
	return writeFile(PROBE_DIR + "/" + name + ".hlsl", text).ok;
}

test "printed modules are written for fxc" {
	const blur = blurModule();
	assert probe("blur.vs", printed(blur, 0, [0, 1]));
	assert probe("blur.ps", printed(blur, 1, [0, 1]));
	assert probe("vertex.vs", printed(vertexModule(), 0, [0]));
	assert probe("fragment.ps", printed(fragmentModule(), 0, [0]));
}
