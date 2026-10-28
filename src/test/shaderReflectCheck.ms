// The reflection of a hand-built void2d blur program equals the descriptor sokol-shdc's output
// gave it, per target, and a compute program reflects its storage resources.

import {
	Access,
	BinaryOp,
	Builtin,
	ExprKind,
	Intrinsic,
	IoDirection,
	ResourceKind,
	SampleType,
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
	exprOf,
	intrinsicOf,
	irErrors,
	literal,
	samplerType,
	scalarType,
	stmtOf,
	storageTextureType,
	structType,
	textureType,
	vectorType,
} from "../shader/ir";
import { ShaderTarget } from "../shader/layout";
import { Reflection, reflectCompute, reflectProgram } from "../shader/reflect";
import { GPUShaderAttribute, GPUShaderBinding, GPUShaderStage } from "../webgpu/types.ms";
import { blurShaderModule } from "../void2d/shader2dModules";

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

// blurVs and blurFs of src/void2d/shader2d.ms, the blur weights left out.
function blurModule(): ShaderModule {
	const f32 = scalarType(ScalarKind.F32);
	const vec2 = vectorType(ScalarKind.F32, 2);
	const vec4 = vectorType(ScalarKind.F32, 4);
	const texture = textureType(TextureShape.D2, ScalarKind.F32);
	let m = new ShaderModule();
	m.structs = [block("BlurParams", [field("dir", vec4)])];
	m.resources = [
		resource(ResourceKind.Texture, "srcTex", 0, texture),
		resource(ResourceKind.Sampler, "srcSmp", 0, samplerType()),
		resource(ResourceKind.UniformBlock, "blur_params", 0, structType(0)),
	];
	let fragColor = io("fragColor", ShaderStage.Fragment, IoDirection.Out, vec4, Builtin.None);
	fragColor.location = 0;
	m.ios = [
		io("pos", ShaderStage.Vertex, IoDirection.In, vec2, Builtin.None),
		io("uv0", ShaderStage.Vertex, IoDirection.In, vec2, Builtin.None),
		io("clip", ShaderStage.Vertex, IoDirection.Out, vec4, Builtin.Position),
		io("uv", ShaderStage.Vertex, IoDirection.Out, vec2, Builtin.None),
		io("uv", ShaderStage.Fragment, IoDirection.In, vec2, Builtin.None),
		fragColor,
	];
	const placed = exprOf(ExprKind.Construct, vec4, -1,
		[exprOf(ExprKind.Io, vec2, 0, []), literal(f32, 0.0), literal(f32, 1.0)]);
	let dir = exprOf(ExprKind.BlockMember, vec4, 2, []);
	dir.member = 0;
	const sampled = intrinsicOf(Intrinsic.TextureSample, vec4, [
		exprOf(ExprKind.Resource, texture, 0, []),
		exprOf(ExprKind.Resource, samplerType(), 1, []),
		exprOf(ExprKind.Io, vec2, 4, []),
	]);
	m.functions = [
		shaderFunction("blurVs", [
			assignOf(exprOf(ExprKind.Io, vec2, 3, []), exprOf(ExprKind.Io, vec2, 1, [])),
			assignOf(exprOf(ExprKind.Io, vec4, 2, []), placed),
			ret(),
		]),
		shaderFunction("blurFs", [
			assignOf(exprOf(ExprKind.Io, vec4, 5, []), binaryOf(BinaryOp.Mul, vec4, sampled, dir)),
			ret(),
		]),
	];
	m.entries = [entry("blurVs", ShaderStage.Vertex, 0), entry("blurFs", ShaderStage.Fragment, 1)];
	return m;
}

function visibilityName(mask: int32): string {
	let names: string[] = [];
	if ((mask & (GPUShaderStage.VERTEX as int32)) != 0) { names.push("vertex"); }
	if ((mask & (GPUShaderStage.FRAGMENT as int32)) != 0) { names.push("fragment"); }
	if ((mask & (GPUShaderStage.COMPUTE as int32)) != 0) { names.push("compute"); }
	return names.join("+");
}

function describeBinding(b: GPUShaderBinding): string {
	const kind: string = b.kind;
	const sampleType: string = b.sampleType;
	const samplerType: string = b.samplerType;
	const bufferType: string = b.bufferType;
	const viewDimension: string = b.viewDimension;
	const storageAccess: string = b.storageAccess;
	const storageFormat: string = b.storageFormat;
	const name = b.nativeName;
	return kind + " " + visibilityName(b.visibility) + " " + String(b.group) + "/" + String(b.binding) + " size " +
		String(b.size) + " slot " + String(b.nativeSlot) + " name " +
		(name === null ? "-" : name) + " tb " + String(b.textureBinding) +
		" [" + sampleType + "|" + samplerType + "|" + bufferType + "|" + viewDimension + "|" +
		(b.multisampled ? "ms" : "") + "|" + storageAccess + "|" + storageFormat + "]";
}

function describeAttribute(a: GPUShaderAttribute): string {
	const name = a.nativeName;
	return String(a.location) + " " + (name === null ? "-" : name) + " " + String(a.semanticIndex);
}

function describe(r: Reflection): string {
	return r.bindings.map((b) => describeBinding(b)).join("\n") + "\n" +
		r.attributes.map((a) => describeAttribute(a)).join("\n") + "\n" +
		r.workgroupSize.map((n) => String(n)).join(",");
}

function reflected(m: ShaderModule, target: ShaderTarget): string {
	const r = m.entries.length == 1 ? reflectCompute(m, 0, target) :
		reflectProgram(m, 0, 1, target);
	if (!r.ok) { return r.error; }
	return describe(r.value);
}

// Copied from src/void2d/shader2dModules.ms blurShaderModule, one branch per target.
function committed(bindings: GPUShaderBinding[], attributes: GPUShaderAttribute[]): string {
	return describe({
		bindings,
		attributes,
		workgroupSize: [0, 0, 0],
		readsVertexIndex: false,
		readsInstanceIndex: false,
	});
}

function committedWgsl(): string {
	return committed([
		{
			group: 0, binding: 0, kind: "uniform", visibility: GPUShaderStage.FRAGMENT as int32, size: 16, nativeSlot: -1,
			textureBinding: -1,
		},
		{
			group: 1, binding: 0, kind: "texture", visibility: GPUShaderStage.FRAGMENT as int32, size: 0, sampleType: "float",
			nativeSlot: -1, textureBinding: -1,
		},
		{
			group: 1, binding: 32, kind: "sampler", visibility: GPUShaderStage.FRAGMENT as int32, size: 0,
			samplerType: "filtering", nativeSlot: -1, textureBinding: -1,
		},
	], [
		{ location: 0, semanticIndex: 0 },
		{ location: 1, semanticIndex: 0 },
	]);
}

function committedGl(): string {
	return committed([
		{
			group: 0, binding: 0, kind: "uniform", visibility: GPUShaderStage.FRAGMENT as int32, size: 16, nativeSlot: -1,
			nativeName: "blur_params", textureBinding: -1,
		},
		{
			group: 1, binding: 0, kind: "texture", visibility: GPUShaderStage.FRAGMENT as int32, size: 0, sampleType: "float",
			nativeSlot: -1, textureBinding: -1,
		},
		{
			group: 1, binding: 32, kind: "sampler", visibility: GPUShaderStage.FRAGMENT as int32, size: 0,
			samplerType: "filtering", nativeSlot: -1, nativeName: "srcTex_srcSmp",
			textureBinding: 0,
		},
	], [
		{ location: 0, nativeName: "pos", semanticIndex: 0 },
		{ location: 1, nativeName: "uv0", semanticIndex: 0 },
	]);
}

function committedMsl(): string {
	return committed([
		{
			group: 0, binding: 0, kind: "uniform", visibility: GPUShaderStage.FRAGMENT as int32, size: 16, nativeSlot: 0,
			textureBinding: -1,
		},
		{
			group: 1, binding: 0, kind: "texture", visibility: GPUShaderStage.FRAGMENT as int32, size: 0, sampleType: "float",
			nativeSlot: 0, textureBinding: -1,
		},
		{
			group: 1, binding: 32, kind: "sampler", visibility: GPUShaderStage.FRAGMENT as int32, size: 0,
			samplerType: "filtering", nativeSlot: 0, textureBinding: -1,
		},
	], [
		{ location: 0, semanticIndex: 0 },
		{ location: 1, semanticIndex: 0 },
	]);
}

function committedHlsl(): string {
	return committed([
		{
			group: 0, binding: 0, kind: "uniform", visibility: GPUShaderStage.FRAGMENT as int32, size: 16, nativeSlot: 0,
			textureBinding: -1,
		},
		{
			group: 1, binding: 0, kind: "texture", visibility: GPUShaderStage.FRAGMENT as int32, size: 0, sampleType: "float",
			nativeSlot: 0, textureBinding: -1,
		},
		{
			group: 1, binding: 32, kind: "sampler", visibility: GPUShaderStage.FRAGMENT as int32, size: 0,
			samplerType: "filtering", nativeSlot: 0, textureBinding: -1,
		},
	], [
		{ location: 0, semanticIndex: 0 },
		{ location: 1, semanticIndex: 1 },
	]);
}

when (webgpu) {
	const HOST_TARGET = ShaderTarget.Wgsl;
} else when (webgl2 || android) {
	const HOST_TARGET = ShaderTarget.Glsl300es;
} else when (ios || macos) {
	const HOST_TARGET = ShaderTarget.Msl;
} else when (voidGlCore || linux) {
	const HOST_TARGET = ShaderTarget.Glsl430;
} else when (windows) {
	const HOST_TARGET = ShaderTarget.Hlsl5;
}

function hostDescriptor(): string {
	const d = blurShaderModule();
	let bindings: GPUShaderBinding[] = [];
	for (const b of d.bindings) {
		const kind: string = b.kind;
		if (kind != "") { bindings.push(b); }
	}
	let attributes: GPUShaderAttribute[] = [];
	for (let i = 0; i < 2; i++) { attributes.push(d.attributes[i]); }
	return describe({
		bindings,
		attributes,
		workgroupSize: [0, 0, 0],
		readsVertexIndex: false,
		readsInstanceIndex: false,
	});
}

test "the blur module holds every invariant" {
	assert irErrors(blurModule()).length == 0;
}

test "blur reflects as the committed WGSL, GL, MSL and HLSL descriptors" {
	assert reflected(blurModule(), ShaderTarget.Wgsl) == committedWgsl();
	assert reflected(blurModule(), ShaderTarget.Glsl430) == committedGl();
	assert reflected(blurModule(), ShaderTarget.Glsl300es) == committedGl();
	assert reflected(blurModule(), ShaderTarget.Msl) == committedMsl();
	assert reflected(blurModule(), ShaderTarget.Hlsl5) == committedHlsl();
}

test "blur reflects as the descriptor this build compiles" {
	assert reflected(blurModule(), HOST_TARGET) == hostDescriptor();
}

// Reads a read-only storage buffer, writes a read-write one and a storage texture, and loads a
// texture with its sampler, so every view kind meets HLSL's t and u and MSL's buffer counters.
function computeModule(): ShaderModule {
	const f32 = scalarType(ScalarKind.F32);
	const vec2 = vectorType(ScalarKind.F32, 2);
	const vec4 = vectorType(ScalarKind.F32, 4);
	const texture = textureType(TextureShape.D2, ScalarKind.F32);
	const image = storageTextureType(TexelFormat.Rgba8unorm, Access.Write);
	let m = new ShaderModule();
	m.structs = [block("Command", [field("value", f32)]), block("Total", [field("sum", vec4)])];
	let results = resource(ResourceKind.StorageBuffer, "results", 1, arrayType(structType(1), -1));
	results.access = Access.ReadWrite;
	m.resources = [
		resource(ResourceKind.StorageBuffer, "commands", 0, arrayType(structType(0), -1)),
		results,
		resource(ResourceKind.StorageTexture, "image", 2, image),
		resource(ResourceKind.Texture, "lut", 3, texture),
		resource(ResourceKind.Sampler, "lutSmp", 0, samplerType()),
	];
	m.ios = [io("id", ShaderStage.Compute, IoDirection.In, vectorType(ScalarKind.U32, 3),
		Builtin.GlobalInvocationId)];
	const zero = literal(scalarType(ScalarKind.I32), 0.0);
	let value = exprOf(ExprKind.Field, f32, 0, [exprOf(ExprKind.Index, structType(0), -1,
		[exprOf(ExprKind.Resource, arrayType(structType(0), -1), 0, []), zero])]);
	let sum = exprOf(ExprKind.Field, vec4, 0, [exprOf(ExprKind.Index, structType(1), -1,
		[exprOf(ExprKind.Resource, arrayType(structType(1), -1), 1, []), zero])]);
	const looked = intrinsicOf(Intrinsic.TextureLoad, vec4, [
		exprOf(ExprKind.Resource, texture, 3, []),
		literal(vec2, 0.0),
	]);
	const store = intrinsicOf(Intrinsic.TextureStore, new ShaderType(), [
		exprOf(ExprKind.Resource, image, 2, []),
		literal(vectorType(ScalarKind.I32, 2), 0.0),
		binaryOf(BinaryOp.Mul, vec4, looked, value),
	]);
	m.functions = [shaderFunction("total", [
		assignOf(sum, looked),
		stmtOf(StmtKind.Call, store, []),
		ret(),
	])];
	let e = entry("total", ShaderStage.Compute, 0);
	e.workgroupSize = [32, 1, 1];
	m.entries = [e];
	return m;
}

const COMPUTE_ATTRIBUTES = "\n\n32,1,1";

test "the compute module holds every invariant" {
	assert irErrors(computeModule()).length == 0;
}

test "HLSL puts read-only storage in t and writable storage in u" {
	assert reflected(computeModule(), ShaderTarget.Hlsl5) == [
		"storage-buffer compute 1/0 size 4 slot 0 name - tb -1 [||read-only-storage||||]",
		"storage-buffer compute 1/1 size 16 slot 0 name - tb -1 [||storage||||]",
		"storage-texture compute 1/2 size 0 slot 1 name - tb -1 [|||||write-only|rgba8unorm]",
		"texture compute 1/3 size 0 slot 1 name - tb -1 [float||||||]",
	].join("\n") + COMPUTE_ATTRIBUTES;
}

test "MSL puts storage buffers after the uniform buffers and storage textures with textures" {
	assert reflected(computeModule(), ShaderTarget.Msl) == [
		"storage-buffer compute 1/0 size 4 slot 8 name - tb -1 [||read-only-storage||||]",
		"storage-buffer compute 1/1 size 16 slot 9 name - tb -1 [||storage||||]",
		"storage-texture compute 1/2 size 0 slot 0 name - tb -1 [|||||write-only|rgba8unorm]",
		"texture compute 1/3 size 0 slot 1 name - tb -1 [float||||||]",
	].join("\n") + COMPUTE_ATTRIBUTES;
}

test "GL binds a storage buffer at its slot and a storage texture at its own count" {
	assert reflected(computeModule(), ShaderTarget.Glsl430) == [
		"storage-buffer compute 1/0 size 4 slot 0 name - tb -1 [||read-only-storage||||]",
		"storage-buffer compute 1/1 size 16 slot 1 name - tb -1 [||storage||||]",
		"storage-texture compute 1/2 size 0 slot 0 name - tb -1 [|||||write-only|rgba8unorm]",
		"texture compute 1/3 size 0 slot -1 name - tb -1 [float||||||]",
		"sampler compute 1/-1 size 0 slot -1 name lut_SPIRV_Cross_DummySampler tb 3 [|non-filtering|||||]",
	].join("\n") + COMPUTE_ATTRIBUTES;
}

test "WGSL and GLSL ES reflect storage by WebGPU numbers or refuse it" {
	assert reflected(computeModule(), ShaderTarget.Wgsl) == [
		"storage-buffer compute 1/0 size 4 slot -1 name - tb -1 [||read-only-storage||||]",
		"storage-buffer compute 1/1 size 16 slot -1 name - tb -1 [||storage||||]",
		"storage-texture compute 1/2 size 0 slot -1 name - tb -1 [|||||write-only|rgba8unorm]",
		"texture compute 1/3 size 0 slot -1 name - tb -1 [float||||||]",
	].join("\n") + COMPUTE_ATTRIBUTES;
	assert reflected(computeModule(), ShaderTarget.Glsl300es) ==
		"resource 'results': GLSL ES 3.0 has no storage resources";
}

test "texture kinds beyond 2d carry their WebGPU spelling" {
	let m = blurModule();
	m.resources[0].type = textureType(TextureShape.CubeArray, ScalarKind.F32);
	m.resources[0].sampleType = SampleType.Depth;
	m.resources[1].samplerType = SamplerType.Comparison;
	const text = reflected(m, ShaderTarget.Wgsl).split("\n");
	assert text[1] == "texture fragment 1/0 size 0 slot -1 name - tb -1 [depth|||cube-array|||]";
	assert text[2] == "sampler fragment 1/32 size 0 slot -1 name - tb -1 [|comparison|||||]";
	m.resources[0].type = textureType(TextureShape.Multisampled2d, ScalarKind.F32);
	assert reflected(m, ShaderTarget.Wgsl).split("\n")[1] ==
		"texture fragment 1/0 size 0 slot -1 name - tb -1 [depth||||ms||]";
}

test "a storage format WebGPU cannot name is refused" {
	let m = computeModule();
	m.resources[2].type = storageTextureType(TexelFormat.Rgba8snorm, Access.Write);
	assert reflected(m, ShaderTarget.Wgsl) ==
		"storage texture 'image': Rgba8snorm is no GPUTextureFormat";
}

test "a samplerless texel fetch reflects the GL dummy sampler and nothing elsewhere" {
	let m = blurModule();
	const vec2 = vectorType(ScalarKind.F32, 2);
	const ivec2 = vectorType(ScalarKind.I32, 2);
	const vec4 = vectorType(ScalarKind.F32, 4);
	const fetched = intrinsicOf(Intrinsic.TextureLoad, vec4, [
		exprOf(ExprKind.Resource, m.resources[0].type, 0, []),
		exprOf(ExprKind.Convert, ivec2, -1, [exprOf(ExprKind.Io, vec2, 4, [])]),
		literal(scalarType(ScalarKind.I32), 0.0),
	]);
	m.functions[1].body = [assignOf(exprOf(ExprKind.Io, vec4, 5, []), fetched), ret()];
	assert irErrors(m).length == 0;
	const gl = reflected(m, ShaderTarget.Glsl430).split("\n");
	assert gl[0] == "texture fragment 1/0 size 0 slot -1 name - tb -1 [float||||||]";
	assert gl[1] == "sampler fragment 1/-1 size 0 slot -1 name srcTex_SPIRV_Cross_DummySampler " +
		"tb 0 [|non-filtering|||||]";
	const hlsl = reflected(m, ShaderTarget.Hlsl5).split("\n");
	assert hlsl[0] == "texture fragment 1/0 size 0 slot 0 name - tb -1 [float||||||]";
	assert hlsl[1] == "0 - 0";
}

test "a vertex entry that takes instanceIndex says so in its reflection" {
	let m = blurModule();
	const before = reflectProgram(m, 0, 1, ShaderTarget.Wgsl);
	assert before.ok && !before.value.readsInstanceIndex;
	m.ios.push(io("instanceIndex", ShaderStage.Vertex, IoDirection.In,
		scalarType(ScalarKind.U32), Builtin.InstanceIndex));
	for (const target of [ShaderTarget.Wgsl, ShaderTarget.Hlsl5, ShaderTarget.Glsl300es]) {
		const after = reflectProgram(m, 0, 1, target);
		assert after.ok && after.value.readsInstanceIndex;
		assert after.value.attributes.length == before.value.attributes.length;
		assert !after.value.readsVertexIndex;
	}
}

test "a vertex entry that takes vertexIndex says so in its reflection" {
	let m = blurModule();
	const before = reflectProgram(m, 0, 1, ShaderTarget.Wgsl);
	assert before.ok && !before.value.readsVertexIndex;
	m.ios.push(io("vertexIndex", ShaderStage.Vertex, IoDirection.In,
		scalarType(ScalarKind.U32), Builtin.VertexIndex));
	for (const target of [ShaderTarget.Wgsl, ShaderTarget.Hlsl5, ShaderTarget.Glsl300es]) {
		const after = reflectProgram(m, 0, 1, target);
		assert after.ok && after.value.readsVertexIndex && !after.value.readsInstanceIndex;
		assert after.value.attributes.length == before.value.attributes.length;
	}
}
