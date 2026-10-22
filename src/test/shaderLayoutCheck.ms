// Uniform blocks and storage elements get std140 and std430 offsets, and each target numbers the
// bindings a program reads as sokol-shdc does.

import {
	BinaryOp,
	Builtin,
	ExprKind,
	Intrinsic,
	IoDirection,
	ResourceKind,
	SampleType,
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
	TextureShape,
	arrayType,
	assignOf,
	binaryOf,
	exprOf,
	intrinsicOf,
	irErrors,
	literal,
	matrixType,
	samplerType,
	scalarType,
	stmtOf,
	structType,
	textureType,
	vectorType,
} from "../shader/ir";
import {
	BindingSlot,
	DUMMY_SAMPLER,
	ShaderTarget,
	bindingSlots,
	storageElementLayout,
	uniformBlockLayout,
} from "../shader/layout";
import { depthModule } from "./shaderProbeModules";

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

function shaderFunction(name: string, body: ShaderStmt[]): ShaderFunction {
	let f = new ShaderFunction();
	f.name = name;
	f.body = body;
	return f;
}

function ret(): ShaderStmt { return stmtOf(StmtKind.Return, new ShaderExpr(), []); }

function member(resource: int32, index: int32, type: ShaderType): ShaderExpr {
	let e = exprOf(ExprKind.BlockMember, type, resource, []);
	e.member = index;
	return e;
}

function sample(texture: int32, sampler: int32): ShaderExpr {
	const vec4 = vectorType(ScalarKind.F32, 4);
	return intrinsicOf(Intrinsic.TextureSample, vec4, [
		exprOf(ExprKind.Resource, textureType(TextureShape.D2, ScalarKind.F32), texture, []),
		exprOf(ExprKind.Resource, samplerType(), sampler, []),
		literal(vectorType(ScalarKind.F32, 2), 0.5),
	]);
}

function paramsStruct(): ShaderStruct {
	const f32 = scalarType(ScalarKind.F32);
	const vec4 = vectorType(ScalarKind.F32, 4);
	return block("Params", [
		field("tint", vec4),
		field("lights", arrayType(vec4, 3)),
		field("model", matrixType(4, 4)),
		field("scale", f32),
		field("offset", vectorType(ScalarKind.F32, 2)),
		field("normal", vectorType(ScalarKind.F32, 3)),
	]);
}

// The vertex entry reads vsParams and heightTex with heightSmp; the fragment entry reads params,
// albedo with linearSmp and detail with pointSmp; texture slot 0 is never read.
function slotModule(): ShaderModule {
	const vec4 = vectorType(ScalarKind.F32, 4);
	const texture = textureType(TextureShape.D2, ScalarKind.F32);
	let m = new ShaderModule();
	m.structs = [paramsStruct()];
	let detail = resource(ResourceKind.Texture, "detail", 2, texture);
	detail.sampleType = SampleType.UnfilterableFloat;
	m.resources = [
		resource(ResourceKind.UniformBlock, "params", 0, structType(0)),
		resource(ResourceKind.UniformBlock, "vsParams", 1, structType(0)),
		resource(ResourceKind.Texture, "unreadTex", 0, texture),
		resource(ResourceKind.Texture, "albedo", 1, texture),
		detail,
		resource(ResourceKind.Texture, "heightTex", 3, texture),
		resource(ResourceKind.Sampler, "linearSmp", 0, samplerType()),
		resource(ResourceKind.Sampler, "pointSmp", 1, samplerType()),
		resource(ResourceKind.Sampler, "heightSmp", 2, samplerType()),
	];
	let colour = io("colour", ShaderStage.Fragment, IoDirection.Out, vec4, Builtin.None);
	colour.location = 0;
	m.ios = [
		io("position", ShaderStage.Vertex, IoDirection.In, vectorType(ScalarKind.F32, 3),
			Builtin.None),
		io("clip", ShaderStage.Vertex, IoDirection.Out, vec4, Builtin.Position),
		colour,
	];
	m.functions = [
		shaderFunction("slotVs", [
			assignOf(exprOf(ExprKind.Io, vec4, 1, []),
				binaryOf(BinaryOp.Mul, vec4, sample(5, 8), member(1, 0, vec4))),
			ret(),
		]),
		shaderFunction("slotFs", [
			assignOf(exprOf(ExprKind.Io, vec4, 2, []), binaryOf(BinaryOp.Mul, vec4,
				binaryOf(BinaryOp.Mul, vec4, sample(3, 6), sample(4, 7)), member(0, 0, vec4))),
			ret(),
		]),
	];
	m.entries = [entry("slotVs", ShaderStage.Vertex, 0), entry("slotFs", ShaderStage.Fragment, 1)];
	return m;
}

function describe(m: ShaderModule, slots: BindingSlot[]): string {
	return slots.map((s) => (s.resource >= 0 ? m.resources[s.resource].name : DUMMY_SAMPLER) +
		" " + s.stage.toString() + " " +
		String(s.group) + "/" + String(s.binding) + " " + String(s.nativeSlot) +
		(s.nativeName != "" ? " " + s.nativeName : "") +
		(s.textureBinding >= 0 ? " t" + String(s.textureBinding) : "")).join("; ");
}

function slots(m: ShaderModule, target: ShaderTarget): string {
	const r = bindingSlots(m, [0, 1], target);
	if (!r.ok) { return r.error; }
	return describe(m, r.value);
}

test "the slot module holds every invariant" {
	assert irErrors(slotModule()).length == 0;
}

test "a uniform block takes std140 offsets and a size rounded to 16" {
	let m = slotModule();
	const r = uniformBlockLayout(m, 0);
	assert r.ok;
	if (r.ok) {
		assert r.value.offsets.map((n) => String(n)).join(",") == "0,16,64,128,136,144";
		assert r.value.size == 160;
	}
}

test "a uniform block member GL cannot flatten is refused by name" {
	let m = slotModule();
	m.structs[0].members.push(field("count", scalarType(ScalarKind.I32)));
	const integer = uniformBlockLayout(m, 0);
	assert !integer.ok;
	if (!integer.ok) {
		assert integer.error == "uniform block 'params': member 'count' is I32, and GL carries " +
			"a uniform block as float vec4s only";
	}
	m.structs[0] = block("Params", [field("weights", arrayType(scalarType(ScalarKind.F32), 4))]);
	const floats = uniformBlockLayout(m, 0);
	assert !floats.ok;
	if (!floats.ok) {
		assert floats.error == "uniform block 'params': member 'weights' is an array of F32; " +
			"an array member holds F32x4 or mat4x4";
	}
}

test "a storage buffer element takes std430 offsets" {
	const f32 = scalarType(ScalarKind.F32);
	let m = new ShaderModule();
	m.structs = [block("Particle", [
		field("pos", vectorType(ScalarKind.F32, 3)),
		field("life", f32),
		field("weights", arrayType(f32, 3)),
		field("vel", vectorType(ScalarKind.F32, 2)),
	])];
	m.resources = [
		resource(ResourceKind.StorageBuffer, "particles", 0, arrayType(structType(0), -1)),
	];
	const r = storageElementLayout(m, 0);
	assert r.ok;
	if (r.ok) {
		assert r.value.offsets.map((n) => String(n)).join(",") == "0,12,16,32";
		assert r.value.size == 48;
	}
	m.structs[0].members.push(field("on", scalarType(ScalarKind.Bool)));
	const refused = storageElementLayout(m, 0);
	assert !refused.ok;
	if (!refused.ok) {
		assert refused.error ==
			"storage buffer 'particles' element.on is a bool, which has no host layout";
	}
}

test "HLSL compacts texture registers per stage in slot order" {
	assert slots(slotModule(), ShaderTarget.Hlsl5) ==
		"params Fragment 0/0 0; vsParams Vertex 0/1 1; albedo Fragment 1/1 0; " +
		"detail Fragment 1/2 1; heightTex Vertex 1/3 0; linearSmp Fragment 1/32 0; " +
		"pointSmp Fragment 1/33 1; heightSmp Vertex 1/34 2";
}

test "MSL numbers as HLSL for blocks, textures and samplers" {
	assert slots(slotModule(), ShaderTarget.Msl) == slots(slotModule(), ShaderTarget.Hlsl5);
}

test "WGSL carries the slots as groups and bindings only" {
	assert slots(slotModule(), ShaderTarget.Wgsl) ==
		"params Fragment 0/0 -1; vsParams Vertex 0/1 -1; albedo Fragment 1/1 -1; " +
		"detail Fragment 1/2 -1; heightTex Vertex 1/3 -1; linearSmp Fragment 1/32 -1; " +
		"pointSmp Fragment 1/33 -1; heightSmp Vertex 1/34 -1";
}

test "GL names blocks and combines each sampled texture with its sampler" {
	const gl = "params Fragment 0/0 -1 params; vsParams Vertex 0/1 -1 vsParams; " +
		"albedo Fragment 1/1 -1; detail Fragment 1/2 -1; heightTex Vertex 1/3 -1; " +
		"linearSmp Fragment 1/32 -1 albedo_linearSmp t1; " +
		"pointSmp Fragment 1/33 -1 detail_pointSmp t2; " +
		"heightSmp Vertex 1/34 -1 heightTex_heightSmp t3";
	assert slots(slotModule(), ShaderTarget.Glsl430) == gl;
	assert slots(slotModule(), ShaderTarget.Glsl300es) == gl;
}

test "GL pairs a texture fetched with no sampler with a dummy sampler" {
	const gl = "shadowMap Fragment 1/0 -1; shadowLayers Fragment 1/1 -1; " +
		"shadowCube Fragment 1/2 -1; lut Fragment 1/3 -1; heightMap Vertex 1/4 -1; " +
		"SPIRV_Cross_DummySampler Fragment 1/-1 -1 shadowMap_SPIRV_Cross_DummySampler t0; " +
		"shadowSmp Fragment 1/32 -1 shadowMap_shadowSmp t0; " +
		"shadowSmp Fragment 1/32 -1 shadowLayers_shadowSmp t1; " +
		"shadowSmp Fragment 1/32 -1 shadowCube_shadowSmp t2; " +
		"SPIRV_Cross_DummySampler Fragment 1/-1 -1 lut_SPIRV_Cross_DummySampler t3; " +
		"SPIRV_Cross_DummySampler Vertex 1/-1 -1 heightMap_SPIRV_Cross_DummySampler t4; " +
		"heightSmp Vertex 1/33 -1 heightMap_heightSmp t4";
	assert slots(depthModule(), ShaderTarget.Glsl430) == gl;
	assert slots(depthModule(), ShaderTarget.Glsl300es) == gl;
	assert !slots(depthModule(), ShaderTarget.Hlsl5).includes(DUMMY_SAMPLER);
}

test "a binding read by both stages is refused by name" {
	let m = slotModule();
	m.functions[0].body[0].expr.operands[0].operands[1].index = 6;
	assert slots(m, ShaderTarget.Hlsl5) ==
		"resource 'linearSmp' is read by the Vertex and the Fragment entry; " +
		"a binding belongs to one stage";
}

test "two read views at one slot are refused by name" {
	let m = slotModule();
	m.resources[4].binding = 1;
	assert slots(m, ShaderTarget.Wgsl) ==
		"resource 'detail': @binding(1) is also 'albedo', and this program reads both";
	m.resources[4].binding = 32;
	assert slots(m, ShaderTarget.Wgsl) == "resource 'detail': @binding(32) is outside 0..31";
}
