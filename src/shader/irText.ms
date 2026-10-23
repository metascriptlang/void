// A lowered module leaves the glsl macro as text (glslIr) and is read back where it is printed
// for a target. Each record is a JSON array of its fields in declaration order, an enum is its
// ordinal: inside a macro, jsonStringify of the IR stops msc
// (~/metascript/.inbox/compiler/2026-10-23-json-stringify-recursive-class-in-macro-exits-127.md)
// and an enum's toString() is its ordinal.

import { JsonKind, JsonValue, parseJson } from "std/serialize/json";
import {
	Access,
	AssignOp,
	BinaryOp,
	Builtin,
	ConditionKind,
	DeclarationKind,
	ExprKind,
	FeatureCondition,
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
	ShaderDeclaration,
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
	ShaderTypeKind,
	StmtKind,
	TexelFormat,
	TextureShape,
	UnaryOp,
} from "./ir";

function quoted(s: string): string { return "\"" + s + "\""; }

function record(parts: string[]): string { return "[" + parts.join(",") + "]"; }

function numbers(list: int32[]): string { return record(list.map((n) => String(n))); }

function typeText(t: ShaderType): string {
	return record([
		String(t.kind as int32),
		String(t.scalar as int32),
		String(t.rows),
		String(t.columns),
		String(t.length),
		record(t.element.map((e) => typeText(e))),
		String(t.structIndex),
		String(t.shape as int32),
		String(t.format as int32),
		String(t.access as int32),
	]);
}

function conditionText(c: FeatureCondition): string {
	return record([
		String(c.kind as int32),
		quoted(c.feature),
		record(c.operands.map((o) => conditionText(o))),
	]);
}

function exprText(e: ShaderExpr): string {
	return record([
		String(e.kind as int32),
		typeText(e.type),
		String(e.value),
		String(e.index),
		String(e.member),
		String(e.unary as int32),
		String(e.binary as int32),
		String(e.intrinsic as int32),
		numbers(e.components),
		e.rgba ? "true" : "false",
		record(e.operands.map((o) => exprText(o))),
	]);
}

function stmtsText(list: ShaderStmt[]): string { return record(list.map((s) => stmtText(s))); }

function caseText(k: ShaderCase): string {
	return record([
		record(k.labels.map((l) => exprText(l))),
		k.isDefault ? "true" : "false",
		stmtsText(k.body),
	]);
}

function stmtText(s: ShaderStmt): string {
	return record([
		String(s.kind as int32),
		String(s.local),
		String(s.assign as int32),
		exprText(s.target),
		exprText(s.expr),
		conditionText(s.condition),
		stmtsText(s.init),
		stmtsText(s.update),
		stmtsText(s.body),
		stmtsText(s.otherwise),
		record(s.cases.map((k) => caseText(k))),
	]);
}

function fieldsText(list: ShaderField[]): string {
	return record(list.map((f) => record([quoted(f.name), typeText(f.type)])));
}

function resourceText(r: ShaderResource): string {
	return record([
		String(r.kind as int32),
		quoted(r.name),
		String(r.group),
		String(r.binding),
		typeText(r.type),
		String(r.access as int32),
		String(r.sampleType as int32),
		String(r.samplerType as int32),
		conditionText(r.condition),
	]);
}

function ioText(io: ShaderIo): string {
	return record([
		quoted(io.name),
		String(io.stage as int32),
		String(io.direction as int32),
		typeText(io.type),
		String(io.location),
		String(io.builtin as int32),
		String(io.interpolation as int32),
		String(io.sampling as int32),
		conditionText(io.condition),
	]);
}

function functionText(f: ShaderFunction): string {
	return record([
		quoted(f.name),
		fieldsText(f.params),
		fieldsText(f.locals),
		typeText(f.result),
		stmtsText(f.body),
		conditionText(f.condition),
	]);
}

export function irText(m: ShaderModule): string {
	return record([
		record(m.features.map((f) => quoted(f))),
		record(m.structs.map((s) => record([quoted(s.name), fieldsText(s.members)]))),
		record(m.constants.map((c) => record([quoted(c.name), typeText(c.type),
			exprText(c.value)]))),
		record(m.resources.map((r) => resourceText(r))),
		record(m.ios.map((io) => ioText(io))),
		record(m.functions.map((f) => functionText(f))),
		record(m.entries.map((e) => record([quoted(e.name), String(e.stage as int32),
			String(e.functionIndex), numbers(e.workgroupSize)]))),
		record(m.declarations.map((d) => record([String(d.kind as int32), String(d.index)]))),
		fieldsText(m.workgroups),
	]);
}

class Reader {
	errors: string[] = [];
}

function fieldsOf(r: Reader, v: JsonValue, count: int32, what: string): JsonValue[] {
	if (v == null || v.kind != JsonKind.Array || v.items.length != count) {
		r.errors.push("irText: a " + what + " is not a record of " + String(count) + " fields");
		return [];
	}
	return v.items;
}

function itemsOf(r: Reader, v: JsonValue, what: string): JsonValue[] {
	if (v == null || v.kind != JsonKind.Array) {
		r.errors.push("irText: " + what + " is not a list");
		return [];
	}
	return v.items;
}

function intOf(v: JsonValue): int32 {
	return match (v.kind) {
		JsonKind.Int => v.intVal as int32,
		JsonKind.Number => v.numVal as int32,
		_ => 0,
	};
}

function floatOf(v: JsonValue): float64 {
	return match (v.kind) {
		JsonKind.Int => v.intVal as float64,
		JsonKind.Number => v.numVal,
		_ => 0.0,
	};
}

function textOf(v: JsonValue): string { return v.kind == JsonKind.String ? v.strVal : ""; }

function flagOf(v: JsonValue): boolean { return v.kind == JsonKind.Bool && v.boolVal; }

function intsOf(r: Reader, v: JsonValue): int32[] {
	return itemsOf(r, v, "an int list").map((n) => intOf(n));
}

function readType(r: Reader, v: JsonValue): ShaderType {
	let t = new ShaderType();
	const f = fieldsOf(r, v, 10, "type");
	if (f.length == 0) { return t; }
	t.kind = intOf(f[0]) as ShaderTypeKind;
	t.scalar = intOf(f[1]) as ScalarKind;
	t.rows = intOf(f[2]);
	t.columns = intOf(f[3]);
	t.length = intOf(f[4]);
	t.element = itemsOf(r, f[5], "element").map((e) => readType(r, e));
	t.structIndex = intOf(f[6]);
	t.shape = intOf(f[7]) as TextureShape;
	t.format = intOf(f[8]) as TexelFormat;
	t.access = intOf(f[9]) as Access;
	return t;
}

function readCondition(r: Reader, v: JsonValue): FeatureCondition {
	let c = new FeatureCondition();
	const f = fieldsOf(r, v, 3, "condition");
	if (f.length == 0) { return c; }
	c.kind = intOf(f[0]) as ConditionKind;
	c.feature = textOf(f[1]);
	c.operands = itemsOf(r, f[2], "operands").map((o) => readCondition(r, o));
	return c;
}

function readExpr(r: Reader, v: JsonValue): ShaderExpr {
	let e = new ShaderExpr();
	const f = fieldsOf(r, v, 11, "expression");
	if (f.length == 0) { return e; }
	e.kind = intOf(f[0]) as ExprKind;
	e.type = readType(r, f[1]);
	e.value = floatOf(f[2]);
	e.index = intOf(f[3]);
	e.member = intOf(f[4]);
	e.unary = intOf(f[5]) as UnaryOp;
	e.binary = intOf(f[6]) as BinaryOp;
	e.intrinsic = intOf(f[7]) as Intrinsic;
	e.components = intsOf(r, f[8]);
	e.rgba = flagOf(f[9]);
	e.operands = itemsOf(r, f[10], "operands").map((o) => readExpr(r, o));
	return e;
}

function readStmts(r: Reader, v: JsonValue): ShaderStmt[] {
	return itemsOf(r, v, "statements").map((s) => readStmt(r, s));
}

function readCase(r: Reader, v: JsonValue): ShaderCase {
	let k = new ShaderCase();
	const f = fieldsOf(r, v, 3, "case");
	if (f.length == 0) { return k; }
	k.labels = itemsOf(r, f[0], "labels").map((l) => readExpr(r, l));
	k.isDefault = flagOf(f[1]);
	k.body = readStmts(r, f[2]);
	return k;
}

function readStmt(r: Reader, v: JsonValue): ShaderStmt {
	let s = new ShaderStmt();
	const f = fieldsOf(r, v, 11, "statement");
	if (f.length == 0) { return s; }
	s.kind = intOf(f[0]) as StmtKind;
	s.local = intOf(f[1]);
	s.assign = intOf(f[2]) as AssignOp;
	s.target = readExpr(r, f[3]);
	s.expr = readExpr(r, f[4]);
	s.condition = readCondition(r, f[5]);
	s.init = readStmts(r, f[6]);
	s.update = readStmts(r, f[7]);
	s.body = readStmts(r, f[8]);
	s.otherwise = readStmts(r, f[9]);
	s.cases = itemsOf(r, f[10], "cases").map((k) => readCase(r, k));
	return s;
}

function readFields(r: Reader, v: JsonValue): ShaderField[] {
	return itemsOf(r, v, "fields").map((x) => {
		let field = new ShaderField();
		const f = fieldsOf(r, x, 2, "field");
		if (f.length == 0) { return field; }
		field.name = textOf(f[0]);
		field.type = readType(r, f[1]);
		return field;
	});
}

function readStruct(r: Reader, v: JsonValue): ShaderStruct {
	let s = new ShaderStruct();
	const f = fieldsOf(r, v, 2, "struct");
	if (f.length == 0) { return s; }
	s.name = textOf(f[0]);
	s.members = readFields(r, f[1]);
	return s;
}

function readConstant(r: Reader, v: JsonValue): ShaderConstant {
	let c = new ShaderConstant();
	const f = fieldsOf(r, v, 3, "constant");
	if (f.length == 0) { return c; }
	c.name = textOf(f[0]);
	c.type = readType(r, f[1]);
	c.value = readExpr(r, f[2]);
	return c;
}

function readResource(r: Reader, v: JsonValue): ShaderResource {
	let res = new ShaderResource();
	const f = fieldsOf(r, v, 9, "resource");
	if (f.length == 0) { return res; }
	res.kind = intOf(f[0]) as ResourceKind;
	res.name = textOf(f[1]);
	res.group = intOf(f[2]);
	res.binding = intOf(f[3]);
	res.type = readType(r, f[4]);
	res.access = intOf(f[5]) as Access;
	res.sampleType = intOf(f[6]) as SampleType;
	res.samplerType = intOf(f[7]) as SamplerType;
	res.condition = readCondition(r, f[8]);
	return res;
}

function readIo(r: Reader, v: JsonValue): ShaderIo {
	let io = new ShaderIo();
	const f = fieldsOf(r, v, 9, "io");
	if (f.length == 0) { return io; }
	io.name = textOf(f[0]);
	io.stage = intOf(f[1]) as ShaderStage;
	io.direction = intOf(f[2]) as IoDirection;
	io.type = readType(r, f[3]);
	io.location = intOf(f[4]);
	io.builtin = intOf(f[5]) as Builtin;
	io.interpolation = intOf(f[6]) as Interpolation;
	io.sampling = intOf(f[7]) as Sampling;
	io.condition = readCondition(r, f[8]);
	return io;
}

function readFunction(r: Reader, v: JsonValue): ShaderFunction {
	let fn = new ShaderFunction();
	const f = fieldsOf(r, v, 6, "function");
	if (f.length == 0) { return fn; }
	fn.name = textOf(f[0]);
	fn.params = readFields(r, f[1]);
	fn.locals = readFields(r, f[2]);
	fn.result = readType(r, f[3]);
	fn.body = readStmts(r, f[4]);
	fn.condition = readCondition(r, f[5]);
	return fn;
}

function readEntry(r: Reader, v: JsonValue): ShaderEntry {
	let e = new ShaderEntry();
	const f = fieldsOf(r, v, 4, "entry");
	if (f.length == 0) { return e; }
	e.name = textOf(f[0]);
	e.stage = intOf(f[1]) as ShaderStage;
	e.functionIndex = intOf(f[2]);
	e.workgroupSize = intsOf(r, f[3]);
	return e;
}

function readDeclaration(r: Reader, v: JsonValue): ShaderDeclaration {
	let d = new ShaderDeclaration();
	const f = fieldsOf(r, v, 2, "declaration");
	if (f.length == 0) { return d; }
	d.kind = intOf(f[0]) as DeclarationKind;
	d.index = intOf(f[1]);
	return d;
}

export function irFromText(text: string): Result<ShaderModule, string> {
	const parsed = parseJson(text);
	if (!parsed.ok) { return Result.err("irText: " + parsed.error); }
	let r = new Reader();
	let m = new ShaderModule();
	const f = fieldsOf(r, parsed.value, 9, "module");
	if (f.length == 0) { return Result.err(r.errors[0]); }
	m.features = itemsOf(r, f[0], "features").map((x) => textOf(x));
	m.structs = itemsOf(r, f[1], "structs").map((x) => readStruct(r, x));
	m.constants = itemsOf(r, f[2], "constants").map((x) => readConstant(r, x));
	m.resources = itemsOf(r, f[3], "resources").map((x) => readResource(r, x));
	m.ios = itemsOf(r, f[4], "ios").map((x) => readIo(r, x));
	m.functions = itemsOf(r, f[5], "functions").map((x) => readFunction(r, x));
	m.entries = itemsOf(r, f[6], "entries").map((x) => readEntry(r, x));
	m.declarations = itemsOf(r, f[7], "declarations").map((x) => readDeclaration(r, x));
	m.workgroups = readFields(r, f[8]);
	if (r.errors.length > 0) { return Result.err(r.errors[0]); }
	return Result.ok(m);
}
