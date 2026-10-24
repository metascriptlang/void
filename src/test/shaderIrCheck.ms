// The shader IR holds a vertex+fragment pair and a compute entry built by hand, and its checker
// names each broken invariant.

import { Node, NodeKind } from "std/meta";
import {
	Access,
	AssignOp,
	BinaryOp,
	Builtin,
	ConditionKind,
	ExprKind,
	Interpolation,
	Intrinsic,
	IoDirection,
	ResourceKind,
	SamplerType,
	ScalarKind,
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
	arrayType,
	assignOf,
	binaryOf,
	conditionOf,
	exprOf,
	featureOn,
	holds,
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

function field(name: string, type: ShaderType): ShaderField {
	let f = new ShaderField();
	f.name = name;
	f.type = type;
	return f;
}

function resource(kind: ResourceKind, name: string, binding: int32, type: ShaderType): ShaderResource {
	let r = new ShaderResource();
	r.kind = kind;
	r.name = name;
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

// litVs/litFs in miniature: position and uv in, uv varying, a textured colour times a uniform tint,
// and a cutout discard only in CUTOUT's programs.
function texturedModule(): ShaderModule {
	const f32 = scalarType(ScalarKind.F32);
	const vec2 = vectorType(ScalarKind.F32, 2);
	const vec3 = vectorType(ScalarKind.F32, 3);
	const vec4 = vectorType(ScalarKind.F32, 4);
	let m = new ShaderModule();
	m.features = ["CUTOUT"];
	let material = new ShaderStruct();
	material.name = "Material";
	material.members = [field("tint", vec4), field("model", matrixType(4, 4))];
	m.structs.push(material);
	m.resources.push(resource(ResourceKind.UniformBlock, "material", 0, structType(0)));
	m.resources.push(resource(ResourceKind.Texture, "albedo", 1,
		textureType(TextureShape.D2, ScalarKind.F32)));
	m.resources.push(resource(ResourceKind.Sampler, "albedoSampler", 2, samplerType()));
	m.ios.push(io("position", ShaderStage.Vertex, IoDirection.In, vec3, Builtin.None));
	m.ios.push(io("uv", ShaderStage.Vertex, IoDirection.In, vec2, Builtin.None));
	m.ios.push(io("clip", ShaderStage.Vertex, IoDirection.Out, vec4, Builtin.Position));
	m.ios.push(io("uv", ShaderStage.Vertex, IoDirection.Out, vec2, Builtin.None));
	m.ios.push(io("uv", ShaderStage.Fragment, IoDirection.In, vec2, Builtin.None));
	m.ios.push(io("colour", ShaderStage.Fragment, IoDirection.Out, vec4, Builtin.None));
	m.ios[5].location = 0;

	const model = exprOf(ExprKind.BlockMember, matrixType(4, 4), 0, []);
	model.member = 1;
	const placed = exprOf(ExprKind.Construct, vec4, -1,
		[exprOf(ExprKind.Io, vec3, 0, []), literal(f32, 1.0)]);
	m.functions.push(shaderFunction("texturedVs", [], [
		assignOf(exprOf(ExprKind.Io, vec4, 2, []), binaryOf(BinaryOp.Mul, vec4, model, placed)),
		assignOf(exprOf(ExprKind.Io, vec2, 3, []), exprOf(ExprKind.Io, vec2, 1, [])),
		ret(),
	]));

	const sampled = intrinsicOf(Intrinsic.TextureSample, vec4, [
		exprOf(ExprKind.Resource, textureType(TextureShape.D2, ScalarKind.F32), 1, []),
		exprOf(ExprKind.Resource, samplerType(), 2, []),
		exprOf(ExprKind.Io, vec2, 4, []),
	]);
	const tint = exprOf(ExprKind.BlockMember, vec4, 0, []);
	tint.member = 0;
	let colour = stmtOf(StmtKind.Let, binaryOf(BinaryOp.Mul, vec4, sampled, tint), []);
	colour.local = 0;
	let alpha = exprOf(ExprKind.Swizzle, f32, -1, [exprOf(ExprKind.Local, vec4, 0, [])]);
	alpha.components = [3];
	const thin = binaryOf(BinaryOp.Less, scalarType(ScalarKind.Bool), alpha, literal(f32, 0.5));
	let cutout = stmtOf(StmtKind.FeatureIf, new ShaderExpr(), [
		stmtOf(StmtKind.If, thin, [stmtOf(StmtKind.Discard, new ShaderExpr(), [])]),
	]);
	cutout.condition = featureOn("CUTOUT");
	m.functions.push(shaderFunction("texturedFs", [field("colour", vec4)], [
		colour,
		cutout,
		assignOf(exprOf(ExprKind.Io, vec4, 5, []), exprOf(ExprKind.Local, vec4, 0, [])),
		ret(),
	]));
	m.entries.push(entry("texturedVs", ShaderStage.Vertex, 0));
	m.entries.push(entry("texturedFs", ShaderStage.Fragment, 1));
	return m;
}

// shady's compute1: each invocation walks its row, writing a storage buffer's value to a texel.
function computeModule(): ShaderModule {
	const f32 = scalarType(ScalarKind.F32);
	const i32 = scalarType(ScalarKind.I32);
	const ivec2 = vectorType(ScalarKind.I32, 2);
	const vec4 = vectorType(ScalarKind.F32, 4);
	const image = storageTextureType(TexelFormat.Rgba8unorm, Access.Write);
	let m = new ShaderModule();
	let command = new ShaderStruct();
	command.name = "Command";
	command.members = [field("value", f32)];
	m.structs.push(command);
	m.resources.push(resource(ResourceKind.StorageBuffer, "commands", 0,
		arrayType(structType(0), -1)));
	m.resources.push(resource(ResourceKind.StorageTexture, "image", 1, image));
	m.ios.push(io("id", ShaderStage.Compute, IoDirection.In, vectorType(ScalarKind.U32, 3),
		Builtin.GlobalInvocationId));

	const x = exprOf(ExprKind.Local, i32, 1, []);
	let start = stmtOf(StmtKind.Let, literal(i32, 0.0), []);
	start.local = 1;
	let step = assignOf(x, new ShaderExpr());
	step.assign = AssignOp.Increment;
	let width = exprOf(ExprKind.Swizzle, i32, -1, [exprOf(ExprKind.Local, ivec2, 0, [])]);
	width.components = [0];
	const element = exprOf(ExprKind.Index, structType(0), -1,
		[exprOf(ExprKind.Resource, arrayType(structType(0), -1), 0, []), x]);
	let value = exprOf(ExprKind.Field, f32, -1, [element]);
	value.index = 0;
	const store = intrinsicOf(Intrinsic.TextureStore, new ShaderType(), [
		exprOf(ExprKind.Resource, image, 1, []),
		exprOf(ExprKind.Construct, ivec2, -1, [x, x]),
		exprOf(ExprKind.Construct, vec4, -1, [literal(f32, 0.5), literal(f32, 0.0), value,
			literal(f32, 1.0)]),
	]);
	let loop = stmtOf(StmtKind.For, binaryOf(BinaryOp.Less, scalarType(ScalarKind.Bool), x, width),
		[stmtOf(StmtKind.Call, store, [])]);
	loop.init = [start];
	loop.update = [step];
	let size = stmtOf(StmtKind.Let, intrinsicOf(Intrinsic.TextureDimensions, ivec2,
		[exprOf(ExprKind.Resource, image, 1, [])]), []);
	size.local = 0;
	m.functions.push(shaderFunction("commandsToImage", [field("size", ivec2), field("x", i32)],
		[size, loop, ret()]));
	let e = entry("commandsToImage", ShaderStage.Compute, 0);
	e.workgroupSize = [32, 1, 1];
	m.entries.push(e);
	return m;
}

macro computeErrorsAtCompileTime(at: Node): Node {
	return { kind: NodeKind.StringLiteral, line: at.line, column: at.column,
		value: "[" + irErrors(computeModule()).join("; ") + "]" };
}

test "a hand-built vertex, fragment and compute module hold every invariant" {
	assert irErrors(texturedModule()).length == 0;
	assert irErrors(computeModule()).length == 0;
}

test "a macro builds and checks the IR at compile time" {
	assert computeErrorsAtCompileTime(0) == "[]";
}

test "a feature condition holds per program key" {
	const cutout = featureOn("CUTOUT");
	assert holds(cutout, ["CUTOUT"]) && !holds(cutout, []);
	const either = conditionOf(ConditionKind.Any, [cutout, featureOn("SKIN")]);
	const neither = conditionOf(ConditionKind.Not, [either]);
	assert holds(either, ["SKIN"]) && !holds(neither, ["SKIN"]) && holds(neither, []);
	const both = conditionOf(ConditionKind.All, [cutout, featureOn("SKIN")]);
	assert !holds(both, ["SKIN"]) && holds(both, ["SKIN", "CUTOUT"]);
}

test "resources of one kind may share a binding, two kinds may not" {
	let m = texturedModule();
	m.resources.push(resource(ResourceKind.UniformBlock, "movingMaterial", 0, structType(0)));
	m.resources.push(resource(ResourceKind.Texture, "normalMap", 1,
		textureType(TextureShape.D2, ScalarKind.F32)));
	assert irErrors(m).length == 0;
	m.resources.push(resource(ResourceKind.StorageBuffer, "particles", 1, structType(0)));
	assert irErrors(m).includes("resource 'particles': binding 1 is also 'albedo'");
}

test "a uniform block holds no struct and a sampler is typed a sampler" {
	let m = texturedModule();
	m.structs[0].members.push(field("inner", structType(0)));
	m.resources[2].type = textureType(TextureShape.D2, ScalarKind.F32);
	m.resources[2].samplerType = SamplerType.NonFiltering;
	const errors = irErrors(m);
	assert errors.length == 2;
	assert errors[0] == "resource 'material': its type does not fit a UniformBlock";
	assert errors[1] == "resource 'albedoSampler': its type does not fit a Sampler";
}

test "an integer varying is flat" {
	let m = texturedModule();
	m.ios.push(io("id", ShaderStage.Vertex, IoDirection.Out, scalarType(ScalarKind.U32),
		Builtin.None));
	let read = io("id", ShaderStage.Fragment, IoDirection.In, scalarType(ScalarKind.U32),
		Builtin.None);
	read.interpolation = Interpolation.Flat;
	m.ios.push(read);
	assert irErrors(m)[0] == "io 'id': an integer varying is flat";
}

test "an attribute, varying or output is no array" {
	let m = texturedModule();
	m.ios.push(io("weights", ShaderStage.Vertex, IoDirection.In,
		arrayType(vectorType(ScalarKind.F32, 4), 2), Builtin.None));
	assert irErrors(m)[0] == "io 'weights': an attribute, varying or output is no array, as WGSL's";
}

test "varyings link by name, type, order and condition" {
	let m = texturedModule();
	m.ios[4].condition = featureOn("CUTOUT");
	assert irErrors(m)[0] == "varying 0 differs between the vertex output and the fragment input";
	m.ios[4].condition = featureOn("SKIN");
	assert irErrors(m)[0] == "io 'uv': feature 'SKIN' is not in the module's features";
}

test "builtins belong to their stage" {
	let m = texturedModule();
	m.ios.push(io("index", ShaderStage.Fragment, IoDirection.In, scalarType(ScalarKind.U32),
		Builtin.VertexIndex));
	assert irErrors(m)[0] == "io 'index': VertexIndex is no Fragment input";
	let c = computeModule();
	c.entries[0].workgroupSize = [32, 0, 1];
	c.ios.push(io("out", ShaderStage.Compute, IoDirection.Out, scalarType(ScalarKind.F32),
		Builtin.None));
	const errors = irErrors(c);
	assert errors.length == 2 && errors[0] == "entry 'commandsToImage': a compute entry has no outputs";
}

test "every reference names a declaration that exists" {
	let m = computeModule();
	m.functions[0].body[1].body[0].expr.operands[0].index = 7;
	m.entries[0].functionIndex = 3;
	const errors = irErrors(m);
	assert errors[0] == "function 'commandsToImage': resource 7 is out of range";
	assert errors[1] == "entry 'commandsToImage': function 3 is out of range";
}
