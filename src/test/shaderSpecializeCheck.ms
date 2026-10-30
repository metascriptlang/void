// One program key of a hand-built module keeps exactly the declarations its reached code reads.

import {
	BinaryOp,
	Builtin,
	ExprKind,
	Intrinsic,
	IoDirection,
	ResourceKind,
	ScalarKind,
	ShaderConstant,
	ShaderDeclaration,
	DeclarationKind,
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
	assignOf,
	binaryOf,
	exprOf,
	featureOn,
	intrinsicOf,
	irErrors,
	literal,
	samplerType,
	scalarType,
	stmtOf,
	structType,
	textureType,
	vectorType,
} from "../shader/ir";
import { readsFrom, specialize } from "../shader/specialize";

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

function io(name: string, direction: IoDirection, type: ShaderType): ShaderIo {
	let v = new ShaderIo();
	v.name = name;
	v.stage = ShaderStage.Fragment;
	v.direction = direction;
	v.type = type;
	v.builtin = Builtin.None;
	return v;
}

function member(resource: int32, index: int32, type: ShaderType): ShaderExpr {
	let e = exprOf(ExprKind.BlockMember, type, resource, []);
	e.member = index;
	return e;
}

function featureIf(feature: string, body: ShaderStmt[]): ShaderStmt {
	let s = stmtOf(StmtKind.FeatureIf, new ShaderExpr(), body);
	s.condition = featureOn(feature);
	return s;
}

function declared(kind: DeclarationKind, index: int32): ShaderDeclaration {
	let d = new ShaderDeclaration();
	d.kind = kind;
	d.index = index;
	return d;
}

function rgbaOf(value: ShaderExpr): ShaderExpr {
	let e = exprOf(ExprKind.Swizzle, value.type, -1, [value]);
	e.components = [0, 1, 2, 3];
	e.rgba = true;
	return e;
}

function ret(value: ShaderExpr): ShaderStmt { return stmtOf(StmtKind.Return, value, []); }

// A fragment entry that always reads `base`; under A a masked texture and the A-only input
// `tangent`, and under A and B the constant SCALE; under B the `fog` block through `fogged`.
function twoFeatureModule(): ShaderModule {
	const f32 = scalarType(ScalarKind.F32);
	const vec2 = vectorType(ScalarKind.F32, 2);
	const vec4 = vectorType(ScalarKind.F32, 4);
	const texture = textureType(TextureShape.D2, ScalarKind.F32);
	let m = new ShaderModule();
	m.features = ["A", "B"];
	m.structs = [
		block("Base", [field("tint", vec4)]),
		block("Unused", [field("x", vec4)]),
		block("Fog", [field("color", vec4)]),
	];
	let scale = new ShaderConstant();
	scale.name = "SCALE";
	scale.type = f32;
	scale.value = literal(f32, 2.0);
	m.constants = [scale];
	m.resources = [
		resource(ResourceKind.UniformBlock, "base", 0, structType(0)),
		resource(ResourceKind.UniformBlock, "unusedBlock", 2, structType(1)),
		resource(ResourceKind.UniformBlock, "fog", 1, structType(2)),
		resource(ResourceKind.Texture, "maskTex", 0, texture),
		resource(ResourceKind.Sampler, "maskSmp", 0, samplerType()),
	];
	let tangent = io("tangent", IoDirection.In, vec4);
	tangent.condition = featureOn("A");
	let colour = io("colour", IoDirection.Out, vec4);
	colour.location = 0;
	m.ios = [io("uv", IoDirection.In, vec2), tangent, colour];

	let fogged = new ShaderFunction();
	fogged.name = "fogged";
	fogged.params = [field("c", vec4)];
	fogged.result = vec4;
	fogged.body = [ret(binaryOf(BinaryOp.Mul, vec4, exprOf(ExprKind.Param, vec4, 0, []),
		member(2, 0, vec4)))];
	let unused = new ShaderFunction();
	unused.name = "unusedFn";
	unused.result = vec4;
	unused.body = [ret(member(1, 0, vec4))];

	const c = exprOf(ExprKind.Local, vec4, 0, []);
	let start = stmtOf(StmtKind.Let, member(0, 0, vec4), []);
	start.local = 0;
	const sampled = intrinsicOf(Intrinsic.TextureSample, vec4, [
		exprOf(ExprKind.Resource, texture, 3, []),
		exprOf(ExprKind.Resource, samplerType(), 4, []),
		exprOf(ExprKind.Io, vec2, 0, []),
	]);
	let main = new ShaderFunction();
	main.name = "mainFs";
	main.locals = [field("c", vec4)];
	main.body = [
		start,
		featureIf("A", [
			assignOf(c, binaryOf(BinaryOp.Mul, vec4, c, sampled)),
			assignOf(c, binaryOf(BinaryOp.Add, vec4, c, exprOf(ExprKind.Io, vec4, 1, []))),
			featureIf("B", [
				assignOf(c, binaryOf(BinaryOp.Mul, vec4, c, exprOf(ExprKind.Constant, f32, 0, []))),
			]),
		]),
		featureIf("B", [assignOf(c, exprOf(ExprKind.Call, vec4, 0, [c]))]),
		assignOf(exprOf(ExprKind.Io, vec4, 2, []), rgbaOf(c)),
		ret(new ShaderExpr()),
	];
	m.functions = [fogged, unused, main];
	m.declarations = [
		declared(DeclarationKind.Struct, 0),
		declared(DeclarationKind.Struct, 1),
		declared(DeclarationKind.Struct, 2),
		declared(DeclarationKind.Constant, 0),
		declared(DeclarationKind.Function, 0),
		declared(DeclarationKind.Function, 1),
		declared(DeclarationKind.Function, 2),
	];
	let entry = new ShaderEntry();
	entry.name = "mainFs";
	entry.stage = ShaderStage.Fragment;
	entry.functionIndex = 2;
	m.entries = [entry];
	return m;
}

function hasFeatureIf(stmts: ShaderStmt[]): boolean {
	return stmts.some((s) => s.kind == StmtKind.FeatureIf ||
		hasFeatureIf(s.body) || hasFeatureIf(s.otherwise) || hasFeatureIf(s.init) ||
		hasFeatureIf(s.update));
}

function shape(m: ShaderModule): string {
	return "resources " + m.resources.map((r) => r.name).join(",") +
		"; functions " + m.functions.map((f) => f.name).join(",") +
		"; constants " + m.constants.map((c) => c.name).join(",") +
		"; structs " + m.structs.map((s) => s.name).join(",") +
		"; ios " + m.ios.map((v) => v.name).join(",");
}

function specialized(on: string[]): ShaderModule {
	const r = specialize(twoFeatureModule(), on);
	if (!r.ok) { return new ShaderModule(); }
	return r.value;
}

function decided(m: ShaderModule): boolean {
	return m.entries.length == 1 && irErrors(m).length == 0 && m.features.length == 0 &&
		!m.functions.some((f) => hasFeatureIf(f.body)) &&
		m.functions[m.entries[0].functionIndex].name == "mainFs";
}

test "the unspecialized module holds every invariant" {
	assert irErrors(twoFeatureModule()).length == 0;
}

test "no feature keeps only what every program reads" {
	const m = specialized([]);
	assert decided(m);
	assert shape(m) ==
		"resources base; functions mainFs; constants ; structs Base; ios uv,colour";
}

test "an input no read reaches stays declared" {
	let m = twoFeatureModule();
	m.ios.push(io("spare", IoDirection.In, vectorType(ScalarKind.F32, 4)));
	const r = specialize(m, []);
	assert r.ok;
	if (r.ok) { assert r.value.ios.map((v) => v.name).join(",") == "uv,colour,spare"; }
}

test "feature A brings its texture pair and its input" {
	const m = specialized(["A"]);
	assert decided(m);
	assert shape(m) ==
		"resources base,maskTex,maskSmp; functions mainFs; constants ; structs Base; " +
		"ios uv,tangent,colour";
}

test "feature B brings its helper and the block the helper reads" {
	const m = specialized(["B"]);
	assert decided(m);
	assert shape(m) ==
		"resources base,fog; functions fogged,mainFs; constants ; structs Base,Fog; ios uv,colour";
}

test "A and B together read the constant under both" {
	const m = specialized(["A", "B"]);
	assert decided(m);
	assert shape(m) == "resources base,fog,maskTex,maskSmp; functions fogged,mainFs; " +
		"constants SCALE; structs Base,Fog; ios uv,tangent,colour";
	const reads = readsFrom(m, m.entries[0].functionIndex);
	assert reads.ok;
	if (reads.ok) {
		assert reads.value.pairs.length == 1;
		assert m.resources[reads.value.pairs[0].texture].name == "maskTex";
		assert m.resources[reads.value.pairs[0].sampler].name == "maskSmp";
	}
}

// twoFeatureModule with an early write and return under B, alone or inside A, before A's reads.
function earlyReturnModule(insideA: boolean): ShaderModule {
	let m = twoFeatureModule();
	const vec4 = vectorType(ScalarKind.F32, 4);
	const early = [
		assignOf(exprOf(ExprKind.Io, vec4, 2, []), rgbaOf(exprOf(ExprKind.Local, vec4, 0, []))),
		ret(new ShaderExpr()),
	];
	const main = m.functions[2].body;
	let body = [main[0], insideA ? featureIf("A", [featureIf("B", early)]) : featureIf("B", early)];
	for (let i = 1; i < main.length; i++) { body.push(main[i]); }
	m.functions[2].body = body;
	return m;
}

function earlyReturn(insideA: boolean, on: string[]): ShaderModule {
	const r = specialize(earlyReturnModule(insideA), on);
	if (!r.ok) { return new ShaderModule(); }
	return r.value;
}

test "a feature branch that returns drops what follows it" {
	for (const insideA of [false, true]) {
		const m = earlyReturn(insideA, ["A", "B"]);
		assert decided(m);
		assert shape(m) ==
			"resources base; functions mainFs; constants ; structs Base; ios uv,tangent,colour";
		assert m.functions[m.entries[0].functionIndex].body.length == 3;
	}
}

test "a returning branch left out keeps what follows it" {
	assert shape(earlyReturn(true, ["A"])) == shape(specialized(["A"]));
	assert shape(earlyReturn(true, ["B"])) == shape(specialized(["B"]));
	assert shape(earlyReturn(false, ["A"])) == shape(specialized(["A"]));
}

test "the kept declarations keep their order under the new indices" {
	const m = specialized(["B"]);
	assert decided(m);
	assert m.declarations.map((d) => d.kind.toString() + " " + String(d.index)).join(", ") ==
		"Struct 0, Struct 1, Function 0, Function 1";
}

test "a colour swizzle stays a colour swizzle" {
	const m = specialized([]);
	const written = m.functions[m.entries[0].functionIndex].body[1].expr;
	assert written.kind == ExprKind.Swizzle && written.rgba;
}

test "a read of an input outside its feature is refused by name" {
	let m = twoFeatureModule();
	const vec4 = vectorType(ScalarKind.F32, 4);
	let body = [assignOf(exprOf(ExprKind.Local, vec4, 0, []), exprOf(ExprKind.Io, vec4, 1, []))];
	for (const s of m.functions[2].body) { body.push(s); }
	m.functions[2].body = body;
	const r = specialize(m, ["B"]);
	assert !r.ok;
	if (!r.ok) {
		assert r.error == "io 'tangent' is read in a program whose features leave it out";
	}
}

test "reads of an unspecialized module are refused" {
	const m = twoFeatureModule();
	const r = readsFrom(m, 2);
	assert !r.ok;
	if (!r.ok) {
		assert r.error == "a feature branch is still undecided: specialize the module first";
	}
}
