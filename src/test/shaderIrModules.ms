// Hand-built IR modules the shader printer checks share: void2d's blur, a compute entry, and one
// pair of entries that reaches every intrinsic and statement kind, and depth comparison.

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
	SampleType,
	SamplerType,
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
	intrinsicOf,
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

export const F32 = scalarType(ScalarKind.F32);
export const I32 = scalarType(ScalarKind.I32);
export const U32 = scalarType(ScalarKind.U32);
export const BOOL = scalarType(ScalarKind.Bool);
export const VEC2 = vectorType(ScalarKind.F32, 2);
export const VEC3 = vectorType(ScalarKind.F32, 3);
export const VEC4 = vectorType(ScalarKind.F32, 4);
export const IVEC2 = vectorType(ScalarKind.I32, 2);
export const UVEC3 = vectorType(ScalarKind.U32, 3);
export const BVEC3 = vectorType(ScalarKind.Bool, 3);
export const MAT4 = matrixType(4, 4);
export const TEXTURE = textureType(TextureShape.D2, ScalarKind.F32);
export const LAYERS = textureType(TextureShape.D2Array, ScalarKind.F32);

export function field(name: string, type: ShaderType): ShaderField {
	let f = new ShaderField();
	f.name = name;
	f.type = type;
	return f;
}

export function block(name: string, members: ShaderField[]): ShaderStruct {
	let s = new ShaderStruct();
	s.name = name;
	s.members = members;
	return s;
}

export function resource(kind: ResourceKind, name: string, binding: int32,
	type: ShaderType): ShaderResource {
	let r = new ShaderResource();
	r.kind = kind;
	r.name = name;
	r.group = kind == ResourceKind.UniformBlock ? 0 : kind == ResourceKind.Sampler ? 2 : 1;
	r.binding = binding;
	r.type = type;
	return r;
}

export function io(name: string, stage: ShaderStage, direction: IoDirection, type: ShaderType,
	builtin: Builtin): ShaderIo {
	let v = new ShaderIo();
	v.name = name;
	v.stage = stage;
	v.direction = direction;
	v.type = type;
	v.builtin = builtin;
	return v;
}

export function entry(name: string, stage: ShaderStage, functionIndex: int32): ShaderEntry {
	let e = new ShaderEntry();
	e.name = name;
	e.stage = stage;
	e.functionIndex = functionIndex;
	return e;
}

export function shaderFunction(name: string, body: ShaderStmt[]): ShaderFunction {
	let f = new ShaderFunction();
	f.name = name;
	f.body = body;
	return f;
}

export function ret(): ShaderStmt { return stmtOf(StmtKind.Return, new ShaderExpr(), []); }

export function ioOf(m: ShaderModule, index: int32): ShaderExpr {
	return exprOf(ExprKind.Io, m.ios[index].type, index, []);
}

export function resourceOf(m: ShaderModule, index: int32): ShaderExpr {
	return exprOf(ExprKind.Resource, m.resources[index].type, index, []);
}

export function swizzle(base: ShaderExpr, type: ShaderType, components: int32[]): ShaderExpr {
	let e = exprOf(ExprKind.Swizzle, type, -1, [base]);
	e.components = components;
	return e;
}

export function memberOf(m: ShaderModule, resourceIndex: int32, member: int32): ShaderExpr {
	const s = m.structs[m.resources[resourceIndex].type.structIndex];
	let e = exprOf(ExprKind.BlockMember, s.members[member].type, resourceIndex, []);
	e.member = member;
	return e;
}

export function local(f: ShaderFunction, name: string, type: ShaderType): ShaderExpr {
	f.locals.push(field(name, type));
	return exprOf(ExprKind.Local, type, (f.locals.length - 1) as int32, []);
}

export function bind(f: ShaderFunction, name: string, value: ShaderExpr): ShaderExpr {
	const l = local(f, name, value.type);
	let s = stmtOf(StmtKind.Let, value, []);
	s.local = l.index;
	f.body.push(s);
	return l;
}

export function compound(op: AssignOp, target: ShaderExpr, value: ShaderExpr): ShaderStmt {
	let s = assignOf(target, value);
	s.assign = op;
	return s;
}

export function caseOf(labels: ShaderExpr[], isDefault: boolean, body: ShaderStmt[]): ShaderCase {
	let k = new ShaderCase();
	k.labels = labels;
	k.isDefault = isDefault;
	k.body = body;
	return k;
}

export function constantOf(name: string, value: ShaderExpr): ShaderConstant {
	let c = new ShaderConstant();
	c.name = name;
	c.type = value.type;
	c.value = value;
	return c;
}

export function unaryOf(op: UnaryOp, value: ShaderExpr): ShaderExpr {
	let e = exprOf(ExprKind.Unary, value.type, -1, [value]);
	e.unary = op;
	return e;
}

// blurVs and blurFs of src/void2d/shader2dGen.glsl, the blur weights left out.
export function blurModule(): ShaderModule {
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

// Reads a read-only storage buffer, writes a read-write one and a storage texture, loads a texture,
// and reads every compute builtin.
export function computeModule(): ShaderModule {
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

// One vertex and one fragment entry that between them use every intrinsic but TextureStore, every
// statement kind but FeatureIf, and every interpolation.
export function everyModule(): ShaderModule {
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

export function tiny(stage: ShaderStage, value: ShaderExpr): ShaderModule {
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

export function model(): ShaderExpr {
	let e = exprOf(ExprKind.BlockMember, MAT4, 0, []);
	e.member = 0;
	return e;
}

export function column(matrix: ShaderExpr): ShaderExpr {
	return exprOf(ExprKind.Index, VEC4, -1, [matrix, literal(I32, 0.0)]);
}

export function depthTexture(name: string, binding: int32, shape: TextureShape): ShaderResource {
	let r = resource(ResourceKind.Texture, name, binding, textureType(shape, ScalarKind.F32));
	r.sampleType = SampleType.Depth;
	return r;
}

export function comparisonSampler(name: string, binding: int32): ShaderResource {
	let r = resource(ResourceKind.Sampler, name, binding, samplerType());
	r.samplerType = SamplerType.Comparison;
	return r;
}

export function depthCompare(op: Intrinsic, texture: int32, sampler: int32, shape: TextureShape,
	at: ShaderExpr): ShaderExpr {
	return intrinsicOf(op, F32, [
		exprOf(ExprKind.Resource, textureType(shape, ScalarKind.F32), texture, []),
		exprOf(ExprKind.Resource, samplerType(), sampler, []),
		at,
		literal(F32, 0.5),
	]);
}

// Depth comparison on every depth shape, at the derivative's level in the fragment entry and at
// level 0 in the vertex entry, beside texel fetches and size queries that pass no sampler.
export function depthModule(): ShaderModule {
	let m = new ShaderModule();
	m.resources = [
		depthTexture("shadowMap", 0, TextureShape.Depth2d),
		depthTexture("shadowLayers", 1, TextureShape.Depth2dArray),
		depthTexture("shadowCube", 2, TextureShape.DepthCube),
		resource(ResourceKind.Texture, "lut", 3, TEXTURE),
		comparisonSampler("shadowSmp", 0),
		depthTexture("heightMap", 4, TextureShape.Depth2d),
		comparisonSampler("heightSmp", 1),
	];
	let color = io("color", ShaderStage.Fragment, IoDirection.Out, VEC4, Builtin.None);
	color.location = 0;
	m.ios = [
		io("clip", ShaderStage.Vertex, IoDirection.Out, VEC4, Builtin.Position),
		io("uv", ShaderStage.Vertex, IoDirection.Out, VEC2, Builtin.None),
		io("uv", ShaderStage.Fragment, IoDirection.In, VEC2, Builtin.None),
		color,
	];
	const uv = ioOf(m, 2);
	const layered = exprOf(ExprKind.Construct, VEC3, -1, [uv, literal(F32, 1.0)]);
	const D2 = TextureShape.Depth2d;
	const ARRAY = TextureShape.Depth2dArray;
	const CUBE = TextureShape.DepthCube;
	const COMPARE = Intrinsic.TextureSampleCompare;
	const LEVEL = Intrinsic.TextureSampleCompareLevel;
	const levels = binaryOf(BinaryOp.Add, F32, binaryOf(BinaryOp.Add, F32,
		depthCompare(LEVEL, 0, 4, D2, uv), depthCompare(LEVEL, 1, 4, ARRAY, layered)),
		depthCompare(LEVEL, 2, 4, CUBE, layered));
	const fetched = intrinsicOf(Intrinsic.TextureLoad, F32, [
		exprOf(ExprKind.Resource, textureType(D2, ScalarKind.F32), 0, []),
		exprOf(ExprKind.Construct, IVEC2, -1, [literal(I32, 1.0)]),
		literal(I32, 0.0),
	]);
	const lutRead = intrinsicOf(Intrinsic.TextureLoad, VEC4, [resourceOf(m, 3),
		exprOf(ExprKind.Construct, IVEC2, -1, [literal(I32, 1.0)]), literal(I32, 0.0)]);
	const lutSize = intrinsicOf(Intrinsic.TextureDimensions, IVEC2,
		[resourceOf(m, 3), literal(I32, 0.0)]);
	const shaded = exprOf(ExprKind.Construct, VEC4, -1, [
		depthCompare(COMPARE, 0, 4, D2, uv),
		depthCompare(COMPARE, 1, 4, ARRAY, layered),
		depthCompare(COMPARE, 2, 4, CUBE, layered),
		binaryOf(BinaryOp.Mul, F32, levels, fetched),
	]);
	const heightSize = intrinsicOf(Intrinsic.TextureDimensions, IVEC2, [resourceOf(m, 5)]);
	const height = binaryOf(BinaryOp.Add, F32,
		depthCompare(LEVEL, 5, 6, D2, exprOf(ExprKind.Construct, VEC2, -1, [literal(F32, 0.5)])),
		exprOf(ExprKind.Convert, F32, -1, [swizzle(heightSize, I32, [0])]));
	let tooSmall = stmtOf(StmtKind.If, binaryOf(BinaryOp.Less, BOOL, swizzle(lutSize, I32, [0]),
		literal(I32, 1.0)), [stmtOf(StmtKind.Discard, new ShaderExpr(), [])]);
	m.functions = [
		shaderFunction("depthVs", [
			assignOf(ioOf(m, 1), exprOf(ExprKind.Construct, VEC2, -1, [literal(F32, 0.5)])),
			assignOf(ioOf(m, 0), exprOf(ExprKind.Construct, VEC4, -1,
				[literal(F32, 0.0), literal(F32, 0.0), height, literal(F32, 1.0)])),
			ret(),
		]),
		shaderFunction("depthFs", [
			tooSmall,
			assignOf(ioOf(m, 3), binaryOf(BinaryOp.Mul, VEC4, shaded, lutRead)),
			ret(),
		]),
	];
	m.entries = [entry("depthVs", ShaderStage.Vertex, 0), entry("depthFs", ShaderStage.Fragment, 1)];
	return m;
}
