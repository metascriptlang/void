import {
	ExprKind,
	FeatureCondition,
	ShaderCase,
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
	ShaderTypeKind,
	StmtKind,
	holds,
	irErrors,
} from "./ir";
import { unspecialized } from "./irWalk";

export class TexturePair {
	texture: int32 = -1;
	sampler: int32 = -1;
}

export class Reads {
	functions: int32[] = [];
	resources: int32[] = [];
	constants: int32[] = [];
	ios: int32[] = [];
	structs: int32[] = [];
	pairs: TexturePair[] = [];
	workgroups: int32[] = [];
	privates: int32[] = [];
}

class Walk {
	module: ShaderModule = new ShaderModule();
	on: string[] = [];
	folding: boolean = false;
	reads: Reads = new Reads();
	errors: string[] = [];
}

function note(list: int32[], index: int32): boolean {
	if (list.includes(index)) { return false; }
	list.push(index);
	return true;
}

function fail(w: Walk, message: string): void {
	if (!w.errors.includes(message)) { w.errors.push(message); }
}

function walkType(w: Walk, t: ShaderType): void {
	if (t.kind == ShaderTypeKind.Struct && note(w.reads.structs, t.structIndex)) {
		for (const f of w.module.structs[t.structIndex].members) { walkType(w, f.type); }
	}
	for (const e of t.element) { walkType(w, e); }
}

function reachable(w: Walk, c: FeatureCondition, what: string): void {
	if (w.folding && !holds(c, w.on)) {
		fail(w, what + " is read in a program whose features leave it out");
	}
}

function notePair(w: Walk, e: ShaderExpr): void {
	if (e.operands.length < 2 || e.operands[0].type.kind != ShaderTypeKind.Texture ||
		e.operands[1].type.kind != ShaderTypeKind.Sampler) {
		return;
	}
	const texture = e.operands[0];
	const sampler = e.operands[1];
	if (texture.kind != ExprKind.Resource || sampler.kind != ExprKind.Resource) {
		fail(w, e.intrinsic.toString() + " takes its texture and sampler as bindings, " +
			"not as values");
		return;
	}
	if (!w.reads.pairs.some((p) => p.texture == texture.index && p.sampler == sampler.index)) {
		let p = new TexturePair();
		p.texture = texture.index;
		p.sampler = sampler.index;
		w.reads.pairs.push(p);
	}
}

function walkExpr(w: Walk, e: ShaderExpr): void {
	const m = w.module;
	walkType(w, e.type);
	match (e.kind) {
		ExprKind.Constant => {
			if (note(w.reads.constants, e.index)) {
				walkType(w, m.constants[e.index].type);
				walkExpr(w, m.constants[e.index].value);
			}
		},
		ExprKind.Io => {
			if (note(w.reads.ios, e.index)) {
				reachable(w, m.ios[e.index].condition, "io '" + m.ios[e.index].name + "'");
			}
		},
		ExprKind.Resource | ExprKind.BlockMember => {
			if (note(w.reads.resources, e.index)) {
				const r = m.resources[e.index];
				reachable(w, r.condition, "resource '" + r.name + "'");
				walkType(w, r.type);
			}
		},
		ExprKind.Call => walkFunction(w, e.index),
		ExprKind.Intrinsic => notePair(w, e),
		ExprKind.Workgroup => {
			if (note(w.reads.workgroups, e.index)) { walkType(w, m.workgroups[e.index].type); }
		},
		ExprKind.Private => {
			if (note(w.reads.privates, e.index)) { walkType(w, m.privates[e.index].type); }
		},
		_ => {},
	}
	for (const o of e.operands) { walkExpr(w, o); }
}

function walkStmts(w: Walk, stmts: ShaderStmt[]): void {
	for (const s of stmts) {
		walkStmt(w, s);
		if (returns(s, w.on)) { return; }
	}
}

function returns(s: ShaderStmt, on: string[]): boolean {
	if (s.kind == StmtKind.Return) { return true; }
	if (s.kind != StmtKind.FeatureIf) { return false; }
	return (holds(s.condition, on) ? s.body : s.otherwise).some((t) => returns(t, on));
}

function walkStmt(w: Walk, s: ShaderStmt): void {
	if (s.kind == StmtKind.FeatureIf) {
		if (!w.folding) {
			fail(w, "a feature branch is still undecided: specialize the module first");
			return;
		}
		walkStmts(w, holds(s.condition, w.on) ? s.body : s.otherwise);
		return;
	}
	walkExpr(w, s.expr);
	walkExpr(w, s.target);
	for (const list of [s.init, s.update, s.body, s.otherwise]) { walkStmts(w, list); }
	for (const k of s.cases) {
		for (const label of k.labels) { walkExpr(w, label); }
		walkStmts(w, k.body);
	}
}

function walkFunction(w: Walk, index: int32): void {
	if (!note(w.reads.functions, index)) { return; }
	const f = w.module.functions[index];
	reachable(w, f.condition, "function '" + f.name + "'");
	for (const p of f.params) { walkType(w, p.type); }
	for (const l of f.locals) { walkType(w, l.type); }
	walkType(w, f.result);
	walkStmts(w, f.body);
}

function strayWorkgroup(m: ShaderModule, e: ShaderEntry, reads: Reads): string {
	if (e.stage == ShaderStage.Compute || reads.workgroups.length == 0) { return ""; }
	return "workgroup variable '" + m.workgroups[reads.workgroups[0]].name +
		"' is read outside a compute entry";
}

export function readsFrom(m: ShaderModule, functionIndex: int32): Result<Reads, string> {
	let w = new Walk();
	w.module = m;
	walkFunction(w, functionIndex);
	if (w.errors.length > 0) { return Result.err(w.errors.join("\n")); }
	return Result.ok(w.reads);
}

export function printableEntry(m: ShaderModule, entryIndex: int32): Result<Reads, string> {
	if (entryIndex < 0 || entryIndex >= m.entries.length) {
		return Result.err("entry " + String(entryIndex) + " is out of range");
	}
	const invalid = irErrors(m);
	if (invalid.length > 0) { return Result.err(invalid[0]); }
	const entry = m.entries[entryIndex];
	const entryFunction = m.functions[entry.functionIndex];
	if (entryFunction.params.length > 0 || entryFunction.result.kind != ShaderTypeKind.Void) {
		return Result.err("entry '" + entry.name + "' takes parameters or returns a value; an " +
			"entry reads and writes its stage's io");
	}
	const reads = try readsFrom(m, entry.functionIndex);
	const stray = strayWorkgroup(m, entry, reads);
	if (stray != "") { return Result.err(stray); }
	const conditioned = unspecialized(m, entry.stage, reads.resources, reads.functions);
	if (conditioned != "") {
		return Result.err(conditioned + " is under a feature condition: specialize the module " +
			"first");
	}
	return Result.ok(reads);
}

class Remap {
	on: string[] = [];
	structs: int32[] = [];
	constants: int32[] = [];
	resources: int32[] = [];
	ios: int32[] = [];
	functions: int32[] = [];
	workgroups: int32[] = [];
}

function keptIndices(count: int32, kept: int32[]): int32[] {
	let map: int32[] = [];
	let next = 0;
	for (let i = 0; i < count; i++) {
		if (kept.includes(i)) {
			map.push(next);
			next++;
		} else {
			map.push(-1);
		}
	}
	return map;
}

function copyType(r: Remap, t: ShaderType): ShaderType {
	let c = new ShaderType();
	c.kind = t.kind;
	c.scalar = t.scalar;
	c.rows = t.rows;
	c.columns = t.columns;
	c.length = t.length;
	c.element = t.element.map((e) => copyType(r, e));
	c.structIndex = t.kind == ShaderTypeKind.Struct ? r.structs[t.structIndex] : t.structIndex;
	c.shape = t.shape;
	c.format = t.format;
	c.access = t.access;
	return c;
}

function copyField(r: Remap, f: ShaderField): ShaderField {
	let c = new ShaderField();
	c.name = f.name;
	c.type = copyType(r, f.type);
	return c;
}

function copyExpr(r: Remap, e: ShaderExpr): ShaderExpr {
	let c = new ShaderExpr();
	c.kind = e.kind;
	c.type = copyType(r, e.type);
	c.value = e.value;
	c.index = match (e.kind) {
		ExprKind.Constant => r.constants[e.index],
		ExprKind.Io => r.ios[e.index],
		ExprKind.Resource | ExprKind.BlockMember => r.resources[e.index],
		ExprKind.Call => r.functions[e.index],
		ExprKind.Workgroup => r.workgroups[e.index],
		_ => e.index,
	};
	c.member = e.member;
	c.unary = e.unary;
	c.binary = e.binary;
	c.intrinsic = e.intrinsic;
	c.components = e.components.map((n) => n);
	c.rgba = e.rgba;
	c.operands = e.operands.map((o) => copyExpr(r, o));
	return c;
}

function copyStmts(r: Remap, stmts: ShaderStmt[]): ShaderStmt[] {
	let out: ShaderStmt[] = [];
	for (const s of stmts) {
		if (s.kind != StmtKind.FeatureIf) {
			out.push(copyStmt(r, s));
			if (s.kind == StmtKind.Return) { break; }
			continue;
		}
		for (const inner of copyStmts(r, holds(s.condition, r.on) ? s.body : s.otherwise)) {
			out.push(inner);
		}
		if (returns(s, r.on)) { break; }
	}
	return out;
}

function copyStmt(r: Remap, s: ShaderStmt): ShaderStmt {
	let c = new ShaderStmt();
	c.kind = s.kind;
	c.local = s.local;
	c.assign = s.assign;
	c.target = copyExpr(r, s.target);
	c.expr = copyExpr(r, s.expr);
	c.init = copyStmts(r, s.init);
	c.update = copyStmts(r, s.update);
	c.body = copyStmts(r, s.body);
	c.otherwise = copyStmts(r, s.otherwise);
	c.cases = s.cases.map((k) => {
		let copied = new ShaderCase();
		copied.labels = k.labels.map((label) => copyExpr(r, label));
		copied.isDefault = k.isDefault;
		copied.body = copyStmts(r, k.body);
		return copied;
	});
	return c;
}

// Keep every held io, read or not: shdc's DCE preserves the stage interface (sokol-tools
// src/shdc/spirv.cc CreateAggressiveDCEPass(true)), so its reflection lists them all.
export function specialize(m: ShaderModule, on: string[]): Result<ShaderModule, string> {
	let w = new Walk();
	w.module = m;
	w.on = on;
	w.folding = true;
	for (const e of m.entries) { walkFunction(w, e.functionIndex); }
	let ios: int32[] = [];
	for (let i = 0; i < m.ios.length; i++) {
		if (holds(m.ios[i].condition, on)) {
			ios.push(i);
			walkType(w, m.ios[i].type);
		}
	}
	if (w.errors.length > 0) { return Result.err(w.errors.join("\n")); }

	let r = new Remap();
	r.on = on;
	r.structs = keptIndices(m.structs.length as int32, w.reads.structs);
	r.constants = keptIndices(m.constants.length as int32, w.reads.constants);
	r.resources = keptIndices(m.resources.length as int32, w.reads.resources);
	r.ios = keptIndices(m.ios.length as int32, ios);
	r.functions = keptIndices(m.functions.length as int32, w.reads.functions);
	r.workgroups = keptIndices(m.workgroups.length as int32, w.reads.workgroups);

	let out = new ShaderModule();
	for (let i = 0; i < m.structs.length; i++) {
		if (r.structs[i] < 0) { continue; }
		let s = new ShaderStruct();
		s.name = m.structs[i].name;
		s.members = m.structs[i].members.map((f) => copyField(r, f));
		out.structs.push(s);
	}
	for (let i = 0; i < m.constants.length; i++) {
		if (r.constants[i] < 0) { continue; }
		let c = new ShaderConstant();
		c.name = m.constants[i].name;
		c.type = copyType(r, m.constants[i].type);
		c.value = copyExpr(r, m.constants[i].value);
		out.constants.push(c);
	}
	for (let i = 0; i < m.resources.length; i++) {
		if (r.resources[i] < 0) { continue; }
		const from = m.resources[i];
		let c = new ShaderResource();
		c.kind = from.kind;
		c.name = from.name;
		c.group = from.group;
		c.binding = from.binding;
		c.type = copyType(r, from.type);
		c.access = from.access;
		c.sampleType = from.sampleType;
		c.samplerType = from.samplerType;
		out.resources.push(c);
	}
	for (let i = 0; i < m.ios.length; i++) {
		if (r.ios[i] < 0) { continue; }
		const from = m.ios[i];
		let c = new ShaderIo();
		c.name = from.name;
		c.stage = from.stage;
		c.direction = from.direction;
		c.type = copyType(r, from.type);
		c.location = from.location;
		c.builtin = from.builtin;
		c.interpolation = from.interpolation;
		c.sampling = from.sampling;
		out.ios.push(c);
	}
	for (let i = 0; i < m.functions.length; i++) {
		if (r.functions[i] < 0) { continue; }
		const from = m.functions[i];
		let c = new ShaderFunction();
		c.name = from.name;
		c.params = from.params.map((f) => copyField(r, f));
		c.locals = from.locals.map((f) => copyField(r, f));
		c.result = copyType(r, from.result);
		c.body = copyStmts(r, from.body);
		out.functions.push(c);
	}
	for (let i = 0; i < m.workgroups.length; i++) {
		if (r.workgroups[i] >= 0) { out.workgroups.push(copyField(r, m.workgroups[i])); }
	}
	for (const e of m.entries) {
		let c = new ShaderEntry();
		c.name = e.name;
		c.stage = e.stage;
		c.functionIndex = r.functions[e.functionIndex];
		c.workgroupSize = e.workgroupSize.map((n) => n);
		out.entries.push(c);
	}
	for (const d of m.declarations) {
		const index = match (d.kind) {
			DeclarationKind.Struct => r.structs[d.index],
			DeclarationKind.Constant => r.constants[d.index],
			DeclarationKind.Function => r.functions[d.index],
			DeclarationKind.Workgroup => r.workgroups[d.index],
		};
		if (index < 0) { continue; }
		let c = new ShaderDeclaration();
		c.kind = d.kind;
		c.index = index;
		out.declarations.push(c);
	}
	return Result.ok(out);
}
