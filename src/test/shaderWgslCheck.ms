// Hand-built IR modules print as WGSL, one module per entry. Each printed module is written to
// out/wgslProbe/, which scripts/validateWgsl.sh hands to naga.

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
import { BindingSlot, ShaderTarget, bindingSlots } from "../shader/layout";
import { printWgsl } from "../shader/printWgsl";
import { specialize } from "../shader/specialize";

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
const MAT4 = matrixType(4, 4);
const TEXTURE = textureType(TextureShape.D2, ScalarKind.F32);
const LAYERS = textureType(TextureShape.D2Array, ScalarKind.F32);

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

function ioOf(m: ShaderModule, index: int32): ShaderExpr {
	return exprOf(ExprKind.Io, m.ios[index].type, index, []);
}

function resourceOf(m: ShaderModule, index: int32): ShaderExpr {
	return exprOf(ExprKind.Resource, m.resources[index].type, index, []);
}

function swizzle(base: ShaderExpr, type: ShaderType, components: int32[]): ShaderExpr {
	let e = exprOf(ExprKind.Swizzle, type, -1, [base]);
	e.components = components;
	return e;
}

function memberOf(m: ShaderModule, resourceIndex: int32, member: int32): ShaderExpr {
	const s = m.structs[m.resources[resourceIndex].type.structIndex];
	let e = exprOf(ExprKind.BlockMember, s.members[member].type, resourceIndex, []);
	e.member = member;
	return e;
}

function local(f: ShaderFunction, name: string, type: ShaderType): ShaderExpr {
	f.locals.push(field(name, type));
	return exprOf(ExprKind.Local, type, (f.locals.length - 1) as int32, []);
}

function bind(f: ShaderFunction, name: string, value: ShaderExpr): ShaderExpr {
	const l = local(f, name, value.type);
	let s = stmtOf(StmtKind.Let, value, []);
	s.local = l.index;
	f.body.push(s);
	return l;
}

function compound(op: AssignOp, target: ShaderExpr, value: ShaderExpr): ShaderStmt {
	let s = assignOf(target, value);
	s.assign = op;
	return s;
}

function caseOf(labels: ShaderExpr[], isDefault: boolean, body: ShaderStmt[]): ShaderCase {
	let k = new ShaderCase();
	k.labels = labels;
	k.isDefault = isDefault;
	k.body = body;
	return k;
}

function constantOf(name: string, value: ShaderExpr): ShaderConstant {
	let c = new ShaderConstant();
	c.name = name;
	c.type = value.type;
	c.value = value;
	return c;
}

function unaryOf(op: UnaryOp, value: ShaderExpr): ShaderExpr {
	let e = exprOf(ExprKind.Unary, value.type, -1, [value]);
	e.unary = op;
	return e;
}

function slotsOf(m: ShaderModule, entries: int32[]): BindingSlot[] {
	const slots = bindingSlots(m, entries, ShaderTarget.Wgsl);
	if (!slots.ok) { return [] }
	return slots.value;
}

function writeProbe(name: string, text: string): boolean {
	const _out = mkdir("out");
	const _probe = mkdir("out/wgslProbe");
	return writeFile("out/wgslProbe/" + name + ".wgsl", text).ok;
}

function wgslOf(m: ShaderModule, index: int32, slots: BindingSlot[]): string {
	const printed = printWgsl(m, index, slots);
	if (printed.ok) { return printed.value; }
	return printed.error;
}

function refusalOf(m: ShaderModule, index: int32, slots: BindingSlot[]): string {
	const printed = printWgsl(m, index, slots);
	if (printed.ok) { return "printed"; }
	return printed.error;
}

// blurVs and blurFs of src/void2d/shader2dGen.glsl, the blur weights left out.
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
	const placed = exprOf(ExprKind.Construct, VEC4, -1,
		[ioOf(m, 0), literal(F32, 0.0), literal(F32, 1.0)]);
	const sampled = intrinsicOf(Intrinsic.TextureSample, VEC4,
		[resourceOf(m, 0), resourceOf(m, 1), ioOf(m, 4)]);
	m.functions = [
		shaderFunction("blurVs", [assignOf(ioOf(m, 3), ioOf(m, 1)), assignOf(ioOf(m, 2), placed),
			ret()]),
		shaderFunction("blurFs", [
			assignOf(ioOf(m, 5), binaryOf(BinaryOp.Mul, VEC4, sampled, memberOf(m, 2, 0))),
			ret(),
		]),
	];
	m.entries = [entry("blurVs", ShaderStage.Vertex, 0), entry("blurFs", ShaderStage.Fragment, 1)];
	return m;
}

// The interface lines of the WGSL committed in src/void2d/shader2dModules.ms (webgpu
// blurShaderModule).
const COMMITTED_BLUR_VS = "struct main_out {\n  @location(0)\n  uv_1 : vec2f,\n" +
	"  @builtin(position)\n  gl_Position : vec4f,\n}\n\n@vertex\n" +
	"fn main(@location(1) uv0_param : vec2f, @location(0) pos_param : vec2f) -> main_out {\n";
const COMMITTED_BLUR_FS = "@binding(0) @group(0) var<uniform> x_13 : blur_params;\n\n" +
	"@binding(0) @group(1) var srcTex : texture_2d<f32>;\n\n" +
	"@binding(32) @group(1) var srcSmp : sampler;\n\n" +
	"struct main_out {\n  @location(0)\n  fragColor_1 : vec4f,\n}\n\n@fragment\n" +
	"fn main(@location(0) uv_param : vec2f) -> main_out {\n";

function withoutName(item: string): string {
	const parts = item.trim().split(" : ");
	let words = parts[0].split(" ");
	words.pop();
	return words.join(" ") + " : " + parts[1];
}

function sorted(items: string[]): string[] {
	let out = items.map((s) => s);
	out.sort((a, b) => a < b ? -1 : a > b ? 1 : 0);
	return out;
}

function interfaceOf(text: string): string {
	let facts: string[] = [];
	const lines = text.split("\n");
	for (let i = 0; i < lines.length; i++) {
		const line = lines[i];
		if (line.startsWith("@binding(")) {
			const item = withoutName(line.substring(0, line.length - 1));
			facts.push(line.includes("<uniform>") ? item.split(" : ")[0] : item);
		}
		if (line == "@vertex" || line == "@fragment") { facts.push(line); }
		if (line.startsWith("fn main(")) {
			const inside = line.substring(8, line.lastIndexOf(")"));
			facts.push("in " + sorted(inside.split(", ").map((x) => withoutName(x))).join(", "));
		}
		if (line == "struct main_out {") {
			let members = "";
			for (let k = i + 1; k < lines.length && lines[k] != "}"; k++) {
				members += " " + lines[k].trim();
			}
			const items = members.split(",").filter((x) => x.trim() != "");
			facts.push("out " + sorted(items.map((x) => withoutName(x))).join(", "));
		}
	}
	return facts.join("\n");
}

test "blur prints the bindings and entry interface of the committed WGSL" {
	const m = blurModule();
	const slots = slotsOf(m, [0, 1]);
	const vs = wgslOf(m, 0, slots);
	const fs = wgslOf(m, 1, slots);
	assert writeProbe("blurVs", vs);
	assert writeProbe("blurFs", fs);
	assert interfaceOf(vs) == interfaceOf(COMMITTED_BLUR_VS);
	assert interfaceOf(fs) == interfaceOf(COMMITTED_BLUR_FS);
	assert interfaceOf(fs) == [
		"@binding(0) @group(0) var<uniform>",
		"@binding(0) @group(1) var : texture_2d<f32>",
		"@binding(32) @group(1) var : sampler",
		"out @location(0) : vec4f",
		"@fragment",
		"in @location(0) : vec2f",
	].join("\n");
	assert vs.includes("fn main(@location(0) pos_param : vec2f, @location(1) uv0_param : vec2f)" +
		" -> main_out {\n  pos = pos_param;\n  uv0 = uv0_param;\n  blurVs();\n" +
		"  return main_out(clip, uv);\n}\n");
	assert !vs.includes("diagnostic") && fs.startsWith("diagnostic(off, derivative_uniformity);\n");
	assert fs.includes("  fragColor = (textureSample(srcTex, srcSmp, uv) * blur_params.dir);\n");
}

// Reads a read-only storage buffer, writes a read-write one and a storage texture, loads a texture,
// and reads every compute builtin.
function computeModule(): ShaderModule {
	let m = new ShaderModule();
	m.structs = [block("Command", [field("value", F32)]), block("Total", [field("sum", VEC4)])];
	let results = resource(ResourceKind.StorageBuffer, "results", 1, arrayType(structType(1), -1));
	results.access = Access.ReadWrite;
	m.resources = [
		resource(ResourceKind.StorageBuffer, "commands", 0, arrayType(structType(0), -1)),
		results,
		resource(ResourceKind.StorageTexture, "image", 2,
			storageTextureType(TexelFormat.Rgba8unorm, Access.Write)),
		resource(ResourceKind.Texture, "lut", 3, TEXTURE),
		resource(ResourceKind.Sampler, "lutSmp", 0, samplerType()),
	];
	m.ios = [
		io("id", ShaderStage.Compute, IoDirection.In, UVEC3, Builtin.GlobalInvocationId),
		io("local", ShaderStage.Compute, IoDirection.In, UVEC3, Builtin.LocalInvocationId),
		io("index", ShaderStage.Compute, IoDirection.In, U32, Builtin.LocalInvocationIndex),
		io("group", ShaderStage.Compute, IoDirection.In, UVEC3, Builtin.WorkgroupId),
		io("groups", ShaderStage.Compute, IoDirection.In, UVEC3, Builtin.NumWorkgroups),
	];
	const x = swizzle(ioOf(m, 0), U32, [0]);
	const value = exprOf(ExprKind.Field, F32, 0, [exprOf(ExprKind.Index, structType(0), -1,
		[resourceOf(m, 0), x])]);
	const slot = binaryOf(BinaryOp.Add, U32, swizzle(ioOf(m, 3), U32, [0]),
		binaryOf(BinaryOp.Add, U32, ioOf(m, 2), swizzle(ioOf(m, 4), U32, [1])));
	const sum = exprOf(ExprKind.Field, VEC4, 0, [exprOf(ExprKind.Index, structType(1), -1,
		[resourceOf(m, 1), slot])]);
	const at = exprOf(ExprKind.Convert, IVEC2, -1, [swizzle(ioOf(m, 1), vectorType(ScalarKind.U32,
		2), [0, 1])]);
	const looked = intrinsicOf(Intrinsic.TextureLoad, VEC4,
		[resourceOf(m, 3), resourceOf(m, 4), at, literal(I32, 0.0)]);
	const store = intrinsicOf(Intrinsic.TextureStore, new ShaderType(),
		[resourceOf(m, 2), at, binaryOf(BinaryOp.Mul, VEC4, looked, value)]);
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

test "compute prints storage resources, builtins and its workgroup size" {
	const m = computeModule();
	assert irErrors(m).length == 0;
	const cs = wgslOf(m, 0, slotsOf(m, [0]));
	assert writeProbe("total", cs);
	assert cs.includes("@binding(0) @group(1) var<storage, read> commands : array<Command>;\n");
	assert cs.includes("@binding(1) @group(1) var<storage, read_write> results : array<Total>;\n");
	assert cs.includes("@binding(2) @group(1) var image : texture_storage_2d<rgba8unorm, write>;\n");
	assert cs.includes("@binding(3) @group(1) var lut : texture_2d<f32>;\n");
	assert cs.includes("@binding(32) @group(1) var lutSmp : sampler;\n");
	assert cs.includes("@compute @workgroup_size(32, 1, 1)\nfn main(@builtin(global_invocation_id)" +
		" id_param : vec3u, @builtin(local_invocation_id) local_param : vec3u, " +
		"@builtin(local_invocation_index) index_param : u32, @builtin(workgroup_id) group_param :" +
		" vec3u, @builtin(num_workgroups) groups_param : vec3u) {\n");
	assert cs.includes("  textureStore(image, vec2i(local.xy), (textureLoad(lut, vec2i(local.xy)," +
		" 0i) * commands[id.x].value));\n");
	assert cs.includes("results[(group.x + (index + groups.y))].sum = ");
}

// One vertex and one fragment entry that between them use every intrinsic but TextureStore, every
// statement kind but FeatureIf, and every interpolation.
function everyModule(): ShaderModule {
	let m = new ShaderModule();
	m.structs = [
		block("Params", [field("tint", VEC4), field("model", MAT4),
			field("rows", arrayType(VEC4, 2))]),
		block("Light", [field("colour", VEC3), field("power", F32)]),
	];
	m.resources = [
		resource(ResourceKind.UniformBlock, "params", 0, structType(0)),
		resource(ResourceKind.Texture, "albedo", 0, TEXTURE),
		resource(ResourceKind.Sampler, "albedoSampler", 0, samplerType()),
		resource(ResourceKind.Texture, "texel", 1, TEXTURE),
		resource(ResourceKind.Texture, "layers", 2, LAYERS),
		resource(ResourceKind.Texture, "heightMap", 3, TEXTURE),
		resource(ResourceKind.Sampler, "heightSampler", 1, samplerType()),
	];
	let tintIn = io("tint", ShaderStage.Fragment, IoDirection.In, VEC4, Builtin.None);
	let tintOut = io("tint", ShaderStage.Vertex, IoDirection.Out, VEC4, Builtin.None);
	for (const t of [tintIn, tintOut]) {
		t.interpolation = Interpolation.Linear;
		t.sampling = Sampling.Centroid;
	}
	let uvIn = io("uv", ShaderStage.Fragment, IoDirection.In, VEC2, Builtin.None);
	let uvOut = io("uv", ShaderStage.Vertex, IoDirection.Out, VEC2, Builtin.None);
	for (const t of [uvIn, uvOut]) { t.sampling = Sampling.Sample; }
	let idIn = io("id", ShaderStage.Fragment, IoDirection.In, U32, Builtin.None);
	let idOut = io("id", ShaderStage.Vertex, IoDirection.Out, U32, Builtin.None);
	for (const t of [idIn, idOut]) { t.interpolation = Interpolation.Flat; }
	let colour = io("colour", ShaderStage.Fragment, IoDirection.Out, VEC4, Builtin.None);
	colour.location = 0;
	let extra = io("extra", ShaderStage.Fragment, IoDirection.Out, VEC4, Builtin.None);
	extra.location = 1;
	m.ios = [
		uvIn, tintIn, idIn,
		io("coord", ShaderStage.Fragment, IoDirection.In, VEC4, Builtin.Position),
		io("facing", ShaderStage.Fragment, IoDirection.In, BOOL, Builtin.FrontFacing),
		colour, extra,
		io("depth", ShaderStage.Fragment, IoDirection.Out, F32, Builtin.FragDepth),
		io("position", ShaderStage.Vertex, IoDirection.In, VEC2, Builtin.None),
		io("vertexIndex", ShaderStage.Vertex, IoDirection.In, U32, Builtin.VertexIndex),
		io("instance", ShaderStage.Vertex, IoDirection.In, U32, Builtin.InstanceIndex),
		io("clip", ShaderStage.Vertex, IoDirection.Out, VEC4, Builtin.Position),
		uvOut, tintOut, idOut,
	];
	m.constants = [];
	const SCALE = 0;
	const LOOP = 1;
	m.constants.push(constantOf("SCALE", literal(F32, 2.0)));
	m.constants.push(constantOf("loop", literal(I32, 3.0)));
	const scaleRead = exprOf(ExprKind.Constant, F32, SCALE, []);

	let shade = shaderFunction("shade", []);
	shade.params = [field("light", structType(1)), field("gain", F32)];
	shade.result = VEC3;
	const gain = exprOf(ExprKind.Param, F32, 1, []);
	shade.body = [
		compound(AssignOp.Mul, gain, scaleRead),
		stmtOf(StmtKind.Return, binaryOf(BinaryOp.Mul, VEC3,
			exprOf(ExprKind.Field, VEC3, 0, [exprOf(ExprKind.Param, structType(1), 0, [])]), gain),
			[]),
	];

	let fs = shaderFunction("everyFs", []);
	const uv = ioOf(m, 0);
	const f = bind(fs, "f", binaryOf(BinaryOp.Mul, F32, swizzle(uv, F32, [0]), scaleRead));
	const v3 = bind(fs, "v3", exprOf(ExprKind.Construct, VEC3, -1, [uv, literal(F32, 1.0)]));
	const v4 = bind(fs, "v4", memberOf(m, 0, 0));
	const m4 = bind(fs, "m4", memberOf(m, 0, 1));
	const i = bind(fs, "i", exprOf(ExprKind.Convert, I32, -1, [f]));
	const u = bind(fs, "u", exprOf(ExprKind.Convert, U32, -1, [i]));
	const b = bind(fs, "b", unaryOf(UnaryOp.Not, binaryOf(BinaryOp.Less, BOOL, f,
		literal(F32, -0.5))));
	const vb = bind(fs, "select", intrinsicOf(Intrinsic.LessThanEqual, BVEC3,
		[v3, literal(VEC3, 0.5)]));
	const light = bind(fs, "light", exprOf(ExprKind.Construct, structType(1), -1, [v3, f]));
	for (const op of [Intrinsic.Abs, Intrinsic.Sign, Intrinsic.Floor, Intrinsic.Ceil,
		Intrinsic.Trunc, Intrinsic.Round, Intrinsic.Fract, Intrinsic.Sqrt, Intrinsic.InverseSqrt,
		Intrinsic.Exp, Intrinsic.Exp2, Intrinsic.Log, Intrinsic.Log2, Intrinsic.Sin, Intrinsic.Cos,
		Intrinsic.Tan, Intrinsic.Asin, Intrinsic.Acos, Intrinsic.Atan, Intrinsic.Sinh,
		Intrinsic.Cosh, Intrinsic.Tanh, Intrinsic.Degrees, Intrinsic.Radians, Intrinsic.Saturate,
		Intrinsic.Normalize, Intrinsic.Dpdy]) {
		bind(fs, "of" + op.toString(), intrinsicOf(op, VEC3, [v3]));
	}
	for (const op of [Intrinsic.Pow, Intrinsic.Atan2, Intrinsic.Min, Intrinsic.Max, Intrinsic.Step,
		Intrinsic.Cross, Intrinsic.Reflect]) {
		bind(fs, "of" + op.toString(), intrinsicOf(op, VEC3, [v3, v3]));
	}
	for (const op of [Intrinsic.Clamp, Intrinsic.Smoothstep, Intrinsic.Fma,
		Intrinsic.FaceForward]) {
		bind(fs, "of" + op.toString(), intrinsicOf(op, VEC3, [v3, v3, v3]));
	}
	bind(fs, "ofMix", intrinsicOf(Intrinsic.Mix, VEC3, [v3, v3, f]));
	bind(fs, "ofRefract", intrinsicOf(Intrinsic.Refract, VEC3, [v3, v3, f]));
	bind(fs, "ofDot", intrinsicOf(Intrinsic.Dot, F32, [v3, v3]));
	bind(fs, "ofLength", intrinsicOf(Intrinsic.Length, F32, [v3]));
	bind(fs, "ofDistance", intrinsicOf(Intrinsic.Distance, F32, [v3, v3]));
	bind(fs, "ofDeterminant", intrinsicOf(Intrinsic.Determinant, F32, [m4]));
	bind(fs, "ofDpdx", intrinsicOf(Intrinsic.Dpdx, F32, [f]));
	bind(fs, "ofFwidth", intrinsicOf(Intrinsic.Fwidth, VEC4, [v4]));
	bind(fs, "ofTranspose", intrinsicOf(Intrinsic.Transpose, MAT4, [m4]));
	const m3 = bind(fs, "ofUpperLeft3x3", intrinsicOf(Intrinsic.UpperLeft3x3, matrixType(3, 3),
		[m4]));
	const m2 = exprOf(ExprKind.Construct, matrixType(2, 2), -1, [uv, uv]);
	bind(fs, "ofInverse", intrinsicOf(Intrinsic.Inverse, MAT4, [m4]));
	bind(fs, "ofInverse3", intrinsicOf(Intrinsic.Inverse, matrixType(3, 3), [m3]));
	bind(fs, "ofInverse2", intrinsicOf(Intrinsic.Inverse, matrixType(2, 2), [m2]));
	bind(fs, "ofSelect", intrinsicOf(Intrinsic.Select, VEC3, [v3, literal(VEC3, 1.0), vb]));
	bind(fs, "ofAbsInt", intrinsicOf(Intrinsic.Abs, I32, [i]));
	bind(fs, "ofMinUint", intrinsicOf(Intrinsic.Min, U32, [u, literal(U32, 7.0)]));
	const texel = exprOf(ExprKind.Convert, IVEC2, -1, [uv]);
	bind(fs, "ofTextureSample", intrinsicOf(Intrinsic.TextureSample, VEC4,
		[resourceOf(m, 1), resourceOf(m, 2), uv]));
	bind(fs, "ofTextureSampleLayer", intrinsicOf(Intrinsic.TextureSample, VEC4,
		[resourceOf(m, 4), resourceOf(m, 2), uv, i]));
	bind(fs, "ofTextureLoad", intrinsicOf(Intrinsic.TextureLoad, VEC4,
		[resourceOf(m, 3), resourceOf(m, 2), texel, literal(I32, 0.0)]));
	bind(fs, "ofTextureLoadLayer", intrinsicOf(Intrinsic.TextureLoad, VEC4,
		[resourceOf(m, 4), resourceOf(m, 2), texel, i, literal(I32, 0.0)]));
	bind(fs, "ofTextureDimensions", intrinsicOf(Intrinsic.TextureDimensions, IVEC2,
		[resourceOf(m, 3), resourceOf(m, 2), literal(I32, 0.0)]));
	bind(fs, "least", literal(I32, -2147483648.0));
	bind(fs, "same", binaryOf(BinaryOp.Equal, BOOL, v3, v3));
	bind(fs, "differ", binaryOf(BinaryOp.NotEqual, BOOL, v4, v4));
	bind(fs, "chosen", exprOf(ExprKind.Conditional, F32, -1, [b, literal(F32, 1.0),
		literal(F32, 0.0)]));
	bind(fs, "row", exprOf(ExprKind.Index, VEC4, -1, [memberOf(m, 0, 2), literal(I32, 1.0)]));
	bind(fs, "column", exprOf(ExprKind.Index, VEC4, -1, [m4, literal(I32, 2.0)]));
	bind(fs, "both", binaryOf(BinaryOp.LogicalOr, BOOL,
		binaryOf(BinaryOp.LogicalAnd, BOOL, b, ioOf(m, 4)),
		binaryOf(BinaryOp.GreaterEqual, BOOL, i, literal(I32, -3.0))));
	bind(fs, "ints", binaryOf(BinaryOp.Div, I32, binaryOf(BinaryOp.Sub, I32,
		binaryOf(BinaryOp.Add, I32, i, literal(I32, 1.0)), exprOf(ExprKind.Constant, I32, LOOP,
		[])), literal(I32, 2.0)));
	bind(fs, "negated", unaryOf(UnaryOp.Negate, literal(F32, -0.5)));

	const k = local(fs, "k", I32);
	const j = local(fs, "j", I32);
	let start = stmtOf(StmtKind.Let, literal(I32, 0.0), []);
	start.local = k.index;
	let jStart = stmtOf(StmtKind.Let, literal(I32, 0.0), []);
	jStart.local = j.index;
	const rowAt = exprOf(ExprKind.Index, VEC4, -1, [memberOf(m, 0, 2),
		binaryOf(BinaryOp.Mod, I32, k, literal(I32, 2.0))]);
	let simple = stmtOf(StmtKind.For, binaryOf(BinaryOp.Less, BOOL, k, literal(I32, 4.0)), [
		stmtOf(StmtKind.If, binaryOf(BinaryOp.Equal, BOOL, k, literal(I32, 2.0)),
			[stmtOf(StmtKind.Continue, new ShaderExpr(), [])]),
		compound(AssignOp.Add, f, swizzle(rowAt, F32, [0])),
	]);
	simple.init = [start];
	simple.update = [compound(AssignOp.Increment, k, new ShaderExpr())];
	let switched = stmtOf(StmtKind.Switch, j, []);
	switched.cases = [
		caseOf([literal(I32, 0.0), literal(I32, 1.0)], false,
			[compound(AssignOp.Add, f, literal(F32, 1.0))]),
		caseOf([literal(I32, 3.0)], true, [stmtOf(StmtKind.Break, new ShaderExpr(), [])]),
	];
	let complex = stmtOf(StmtKind.For, binaryOf(BinaryOp.Less, BOOL, j, literal(I32, 2.0)),
		[switched]);
	complex.init = [jStart, assignOf(f, f)];
	complex.update = [compound(AssignOp.Increment, j, new ShaderExpr()),
		compound(AssignOp.Add, f, literal(F32, 0.0))];
	let bare = stmtOf(StmtKind.Switch, u, []);
	bare.cases = [caseOf([literal(U32, 5.0)], false, [compound(AssignOp.Sub, f, literal(F32,
		1.0))])];
	let shaded = stmtOf(StmtKind.Call, exprOf(ExprKind.Call, VEC3, 0, [light, f]), []);
	let inner = stmtOf(StmtKind.Block, new ShaderExpr(), []);
	const scratch = local(fs, "scratch", F32);
	let declared = stmtOf(StmtKind.Let, new ShaderExpr(), []);
	declared.local = scratch.index;
	inner.body = [declared, assignOf(scratch, f)];
	let written = stmtOf(StmtKind.If, binaryOf(BinaryOp.LogicalAnd, BOOL, b, ioOf(m, 4)),
		[assignOf(ioOf(m, 5), v4)]);
	written.otherwise = [stmtOf(StmtKind.Discard, new ShaderExpr(), [])];
	const halving = stmtOf(StmtKind.While, binaryOf(BinaryOp.Greater, BOOL, f, literal(F32, 1.0)),
		[
			assignOf(f, binaryOf(BinaryOp.Mul, F32, f, literal(F32, 0.5))),
			stmtOf(StmtKind.If, binaryOf(BinaryOp.LessEqual, BOOL, f, literal(F32, 0.25)),
				[stmtOf(StmtKind.Break, new ShaderExpr(), [])]),
		]);
	for (const s of [
		compound(AssignOp.Add, f, literal(F32, 1.0)),
		compound(AssignOp.Sub, f, literal(F32, 0.5)),
		compound(AssignOp.Mul, f, literal(F32, 2.0)),
		compound(AssignOp.Div, f, literal(F32, 3.0)),
		compound(AssignOp.Mod, f, literal(F32, 7.0)),
		compound(AssignOp.Mod, i, literal(I32, 3.0)),
		compound(AssignOp.Increment, i, new ShaderExpr()),
		compound(AssignOp.Decrement, i, new ShaderExpr()),
		assignOf(u, binaryOf(BinaryOp.BitAnd, U32, unaryOf(UnaryOp.Not, u), literal(U32, 255.0))),
		assignOf(swizzle(v4, VEC3, [0, 1, 2]), v3),
		compound(AssignOp.Add, swizzle(v4, VEC2, [1, 0]), literal(VEC2, 1.0)),
		assignOf(swizzle(v4, F32, [3]), f),
		written,
		simple,
		complex,
		bare,
		shaded,
		stmtOf(StmtKind.Call, intrinsicOf(Intrinsic.Dpdx, F32, [f]), []),
		inner,
		halving,
		assignOf(ioOf(m, 6), exprOf(ExprKind.Construct, VEC4, -1,
			[exprOf(ExprKind.Call, VEC3, 0, [light, f]), literal(F32, 1.0)])),
		assignOf(ioOf(m, 7), binaryOf(BinaryOp.Mul, F32, swizzle(ioOf(m, 3), F32, [2]),
			exprOf(ExprKind.Convert, F32, -1, [ioOf(m, 2)]))),
		ret(),
	]) {
		fs.body.push(s);
	}

	let vs = shaderFunction("everyVs", []);
	const position = ioOf(m, 8);
	const height = intrinsicOf(Intrinsic.TextureSample, VEC4,
		[resourceOf(m, 5), resourceOf(m, 6), position]);
	vs.body = [
		assignOf(ioOf(m, 11), exprOf(ExprKind.Construct, VEC4, -1,
			[position, swizzle(height, F32, [0]), literal(F32, 1.0)])),
		assignOf(ioOf(m, 12), position),
		assignOf(ioOf(m, 13), exprOf(ExprKind.Construct, VEC4, -1,
			[exprOf(ExprKind.Convert, F32, -1, [ioOf(m, 9)])])),
		assignOf(ioOf(m, 14), binaryOf(BinaryOp.Add, U32, ioOf(m, 9), ioOf(m, 10))),
		ret(),
	];
	m.functions = [shade, fs, vs];
	m.entries = [entry("everyVs", ShaderStage.Vertex, 2), entry("everyFs", ShaderStage.Fragment, 1)];
	return m;
}

test "every intrinsic and statement prints" {
	const m = everyModule();
	assert irErrors(m).length == 0;
	const slots = slotsOf(m, [0, 1]);
	const vs = wgslOf(m, 0, slots);
	const fs = wgslOf(m, 1, slots);
	assert writeProbe("everyVs", vs);
	assert writeProbe("everyFs", fs);
	assert !vs.includes("diagnostic") && fs.startsWith("diagnostic(off, derivative_uniformity);\n");
	assert vs.includes("@binding(33) @group(1) var heightSampler : sampler;\n");
	assert vs.includes("textureSampleLevel(heightMap, heightSampler, position, 0.0f)");
	assert vs.includes("  @builtin(position) clip : vec4f,\n" +
		"  @location(0) @interpolate(perspective, sample) uv : vec2f,\n" +
		"  @location(1) @interpolate(linear, centroid) tint : vec4f,\n" +
		"  @location(2) @interpolate(flat) id : u32,\n}\n");
	assert vs.includes("fn main(@location(0) position_param : vec2f, @builtin(vertex_index) " +
		"vertexIndex_param : u32, @builtin(instance_index) instance_param : u32) -> main_out {\n");
	assert fs.includes("fn main(@location(0) @interpolate(perspective, sample) uv_param : vec2f, " +
		"@location(1) @interpolate(linear, centroid) tint_param : vec4f, @location(2) " +
		"@interpolate(flat) id_param : u32, @builtin(position) coord_param : vec4f, " +
		"@builtin(front_facing) facing_param : bool) -> main_out {\n");
	assert fs.includes("  @builtin(frag_depth) depth : f32,\n");
	for (const fragment of [
		"const loop_1 : i32 = 3i;\n",
		"fn shade(light : Light, gain_in : f32) -> vec3f {\n  var gain : f32 = gain_in;\n",
		"fn upperLeft3x3(m : mat4x4f) -> mat3x3f {\n",
		"  var select_1 : vec3<bool> = (v3 <= vec3f(0.5f));\n",
		"  var ofUpperLeft3x3 : mat3x3f = upperLeft3x3(m4);\n",
		"fn inverse2x2(m : mat2x2f) -> mat2x2f {\n  let k = 1.0f / determinant(m);\n",
		"fn inverse3x3(m : mat3x3f) -> mat3x3f {\n",
		"fn inverse4x4(m : mat4x4f) -> mat4x4f {\n  let a = m[0].xyz;\n",
		"  var ofInverse : mat4x4f = inverse4x4(m4);\n",
		"  var ofInverse3 : mat3x3f = inverse3x3(ofUpperLeft3x3);\n",
		"  var ofInverse2 : mat2x2f = inverse2x2(mat2x2f(uv, uv));\n",
		"  var ofSelect : vec3f = select(v3, vec3f(1f), select_1);\n",
		"  var ofTextureSampleLayer : vec4f = textureSample(layers, albedoSampler, uv, i);\n",
		"  var ofTextureLoadLayer : vec4f = textureLoad(layers, vec2i(uv), i, 0i);\n",
		"  var ofTextureDimensions : vec2i = vec2i(textureDimensions(texel, 0i));\n",
		"  var least : i32 = (-2147483647i - 1i);\n",
		"  var same : bool = all(v3 == v3);\n",
		"  var differ : bool = any(v4 != v4);\n",
		"  var chosen : f32 = select(0f, 1f, b);\n",
		"  var ints : i32 = (((i + 1i) - loop_1) / 2i);\n",
		"  var negated : f32 = (-(-0.5f));\n",
		"  i %= 3i;\n  i++;\n  i--;\n  u = ((~u) & 255u);\n",
		"  {\n    let swizzled = v3;\n    v4.x = swizzled.x;\n    v4.y = swizzled.y;\n" +
			"    v4.z = swizzled.z;\n  }\n",
		"    v4.y += swizzled_1.x;\n    v4.x += swizzled_1.y;\n",
		"  } else {\n    discard;\n  }\n",
		"  for (var k : i32 = 0i; (k < 4i); k++) {\n    if ((k == 2i)) {\n      continue;\n",
		"    loop {\n      if (!(j < 2i)) { break; }\n      switch (j) {\n" +
			"        case 0i, 1i: {\n",
		"        case 3i, default: {\n          break;\n        }\n",
		"      continuing {\n        j++;\n        f += 0f;\n      }\n",
		"    case 5u: {\n      f -= 1f;\n    }\n    default: {}\n",
		"  shade(light, f);\n  _ = dpdx(f);\n  {\n    var scratch : f32;\n",
		"  while ((f > 1f)) {\n",
		"  depth = (coord.z * f32(id));\n",
	]) {
		assert fs.includes(fragment);
	}
}

function tiny(stage: ShaderStage, value: ShaderExpr): ShaderModule {
	let m = new ShaderModule();
	m.structs = [block("Params", [field("model", MAT4)])];
	m.resources = [resource(ResourceKind.UniformBlock, "params", 0, structType(0))];
	const vertex = stage == ShaderStage.Vertex;
	let out = io("result", stage, IoDirection.Out, VEC4, vertex ? Builtin.Position : Builtin.None);
	out.location = vertex ? -1 : 0;
	m.ios = [out];
	m.functions = [shaderFunction("tinyEntry", [assignOf(ioOf(m, 0), value), ret()])];
	m.entries = [entry("tinyEntry", stage, 0)];
	return m;
}

function refused(m: ShaderModule): string { return refusalOf(m, 0, slotsOf(m, [0])); }

function model(): ShaderExpr {
	let e = exprOf(ExprKind.BlockMember, MAT4, 0, []);
	e.member = 0;
	return e;
}

function column(matrix: ShaderExpr): ShaderExpr {
	return exprOf(ExprKind.Index, VEC4, -1, [matrix, literal(I32, 0.0)]);
}

test "what WGSL cannot say is refused by name" {
	const fragment = ShaderStage.Fragment;
	assert refused(tiny(fragment, column(model()))) == "printed";
	assert refused(tiny(fragment, column(intrinsicOf(Intrinsic.Inverse, matrixType(4, 3),
		[model()])))) == "printWgsl: inverse of a Matrix that is no square matrix";
	assert refused(tiny(ShaderStage.Vertex, intrinsicOf(Intrinsic.Dpdx, VEC4,
		[literal(VEC4, 1.0)]))) == "printWgsl: dpdx outside a fragment entry";
	assert refused(tiny(fragment, column(literal(MAT4, 1.0)))) ==
		"printWgsl: a literal of a Matrix";
	assert refused(tiny(fragment, literal(VEC4, 1.0 / 0.0))) ==
		"printWgsl: a literal that is not finite";
	assert refusalOf(tiny(fragment, column(model())), 0, []) ==
		"printWgsl: resource 'params' has no binding slot";
	assert refusalOf(tiny(fragment, column(model())), 1, []) == "printWgsl: entry 1 is out of range";

	let called = tiny(fragment, exprOf(ExprKind.Conditional, VEC4, -1,
		[literal(BOOL, 1.0), exprOf(ExprKind.Call, VEC4, 1, []), literal(VEC4, 0.0)]));
	let helper = shaderFunction("helper", [stmtOf(StmtKind.Return, literal(VEC4, 1.0), [])]);
	helper.result = VEC4;
	called.functions.push(helper);
	assert refused(called) == "printWgsl: a conditional whose branch calls a function";

	let unlevelled = tiny(fragment, intrinsicOf(Intrinsic.TextureLoad, VEC4, [
		exprOf(ExprKind.Resource, TEXTURE, 1, []),
		exprOf(ExprKind.Resource, samplerType(), 2, []),
		literal(IVEC2, 0.0),
	]));
	unlevelled.resources.push(resource(ResourceKind.Texture, "lut", 0, TEXTURE));
	unlevelled.resources.push(resource(ResourceKind.Sampler, "lutSmp", 0, samplerType()));
	assert refused(unlevelled) == "printWgsl: textureLoad of a sampled texture takes a level";

	let signed = tiny(ShaderStage.Vertex, literal(VEC4, 0.0));
	signed.ios.push(io("vertexIndex", ShaderStage.Vertex, IoDirection.In, I32,
		Builtin.VertexIndex));
	assert refused(signed) == "printWgsl: io 'vertexIndex' is i32; @builtin(vertex_index) is u32";

	let unspellable = tiny(fragment, literal(VEC4, 0.0));
	unspellable.functions[0].name = "__entry";
	assert refused(unspellable) == "printWgsl: '__entry' is no WGSL identifier";
}

test "a feature branch prints only after specialize decides it" {
	let m = tiny(ShaderStage.Fragment, literal(VEC4, 0.0));
	m.features = ["CUTOUT"];
	let branch = stmtOf(StmtKind.FeatureIf, new ShaderExpr(), [stmtOf(StmtKind.Discard,
		new ShaderExpr(), [])]);
	branch.condition = featureOn("CUTOUT");
	m.functions[0].body.splice(1, 0, branch);
	assert refused(m) ==
		"printWgsl: a feature branch is still undecided: specialize the module first";
	const on = specialize(m, ["CUTOUT"]);
	const off = specialize(m, []);
	assert on.ok && off.ok;
	if (on.ok && off.ok) {
		const cut = wgslOf(on.value, 0, slotsOf(on.value, [0]));
		const kept = wgslOf(off.value, 0, slotsOf(off.value, [0]));
		assert cut.includes("  discard;\n") && !kept.includes("discard");
		assert writeProbe("cutout", cut) && writeProbe("kept", kept);
	}
}
