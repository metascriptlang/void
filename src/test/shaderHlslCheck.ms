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

const PROBE_DIR = "out/hlslProbe";

function probe(name: string, text: string): boolean {
	const _made = mkdir(PROBE_DIR);
	return writeFile(PROBE_DIR + "/" + name + ".hlsl", text).ok;
}

test "printed modules are written for fxc" {
	const blur = blurModule();
	assert probe("blur.vs", printed(blur, 0, [0, 1]));
	assert probe("blur.ps", printed(blur, 1, [0, 1]));
}
