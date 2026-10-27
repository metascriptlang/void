import {
	ExprKind,
	ResourceKind,
	ScalarKind,
	ShaderCase,
	ShaderExpr,
	ShaderField,
	ShaderFunction,
	ShaderModule,
	ShaderStage,
	ShaderStmt,
	ShaderTypeKind,
	StmtKind,
	UnaryOp,
	assignOf,
	exprOf,
	isEffect,
	literal,
	scalarType,
	stmtOf,
} from "./ir";
import { functionOrder, rootOf } from "./irWalk";

// WGSL's discard demotes the invocation to a helper: it runs on, so the derivatives its quad
// takes stay defined, and only its writes are dropped. A target whose discard ends the
// invocation gets that meaning as Tint's DemoteToHelper gives it
// (src/tint/lang/core/ir/transform/demote_to_helper.cc): a discard raises a flag, a write to
// storage waits for the flag to be clear, and the entry discards when it returns.
class Demotion {
	module: ShaderModule = new ShaderModule();
	flag: ShaderExpr = new ShaderExpr();
	entry: int32 = -1;
	errors: string[] = [];
}

function discards(stmts: ShaderStmt[]): boolean {
	return stmts.some((s) => s.kind == StmtKind.Discard ||
		[s.init, s.update, s.body, s.otherwise].some((list) => discards(list)) ||
		s.cases.some((arm) => discards(arm.body)));
}

function hasIntrinsicEffect(e: ShaderExpr): boolean {
	return e.kind == ExprKind.Intrinsic && isEffect(e.intrinsic) ||
		e.operands.some((o) => hasIntrinsicEffect(o));
}

function writesStorage(d: Demotion, s: ShaderStmt): boolean {
	const root = rootOf(s.target);
	return s.kind == StmtKind.Assign && root.kind == ExprKind.Resource &&
		d.module.resources[root.index].kind == ResourceKind.StorageBuffer;
}

function unlessDemoted(d: Demotion, s: ShaderStmt): ShaderStmt {
	let clear = exprOf(ExprKind.Unary, d.flag.type, -1, [d.flag]);
	clear.unary = UnaryOp.Not;
	return stmtOf(StmtKind.If, clear, [s]);
}

function discardIfDemoted(d: Demotion): ShaderStmt {
	return stmtOf(StmtKind.If, d.flag, [stmtOf(StmtKind.Discard, new ShaderExpr(), [])]);
}

function lowered(d: Demotion, stmts: ShaderStmt[], owner: string, entry: boolean): ShaderStmt[] {
	let out: ShaderStmt[] = [];
	for (const s of stmts) {
		if (s.kind == StmtKind.Discard) {
			out.push(assignOf(d.flag, literal(d.flag.type, 1.0)));
			continue;
		}
		if (s.kind == StmtKind.Return && entry) { out.push(discardIfDemoted(d)); }
		let copy = stmtOf(s.kind, s.expr, lowered(d, s.body, owner, entry));
		copy.local = s.local;
		copy.assign = s.assign;
		copy.target = s.target;
		copy.condition = s.condition;
		copy.init = lowered(d, s.init, owner, entry);
		copy.update = lowered(d, s.update, owner, entry);
		copy.otherwise = lowered(d, s.otherwise, owner, entry);
		copy.cases = s.cases.map((arm) => {
			let c = new ShaderCase();
			c.labels = arm.labels;
			c.isDefault = arm.isDefault;
			c.body = lowered(d, arm.body, owner, entry);
			return c;
		});
		const effect = s.kind == StmtKind.Call && s.expr.kind == ExprKind.Intrinsic &&
			isEffect(s.expr.intrinsic);
		if (effect || writesStorage(d, s)) {
			out.push(unlessDemoted(d, copy));
			continue;
		}
		if (hasIntrinsicEffect(s.expr) || hasIntrinsicEffect(s.target)) {
			d.errors.push(owner + ": an atomic or texture store whose result is read, in a " +
				"fragment program that discards, has no demote lowering yet");
		}
		out.push(copy);
	}
	return out;
}

function demotedFunction(d: Demotion, index: int32): ShaderFunction {
	const f = d.module.functions[index];
	const owner = "function '" + f.name + "'";
	const entry = index == d.entry;
	let out = new ShaderFunction();
	out.name = f.name;
	out.params = f.params;
	out.locals = f.locals;
	out.result = f.result;
	out.condition = f.condition;
	out.body = lowered(d, f.body, owner, entry);
	const last = f.body.length > 0 ? f.body[f.body.length - 1].kind : StmtKind.Block;
	if (entry && last != StmtKind.Return) { out.body.push(discardIfDemoted(d)); }
	if (!entry && f.result.kind != ShaderTypeKind.Void && last != StmtKind.Return) {
		d.errors.push(owner + " can end without a return once its discard no longer ends the " +
			"invocation; return on every path");
	}
	return out;
}

export function demotedDiscards(m: ShaderModule, entryIndex: int32): Result<ShaderModule, string> {
	if (entryIndex < 0 || entryIndex >= m.entries.length) { return Result.ok(m); }
	const entry = m.entries[entryIndex];
	if (entry.stage != ShaderStage.Fragment) { return Result.ok(m); }
	let reached: int32[] = [];
	functionOrder(m, entry.functionIndex, [], reached);
	if (!reached.some((f) => discards(m.functions[f].body))) { return Result.ok(m); }

	let out = new ShaderModule();
	out.features = m.features;
	out.structs = m.structs;
	out.constants = m.constants;
	out.resources = m.resources;
	out.ios = m.ios;
	out.entries = m.entries;
	out.declarations = m.declarations;
	out.workgroups = m.workgroups;
	let flag = new ShaderField();
	flag.name = "demoted";
	flag.type = scalarType(ScalarKind.Bool);
	out.privates = m.privates.concat([flag]);

	let d = new Demotion();
	d.module = m;
	d.entry = entry.functionIndex;
	d.flag = exprOf(ExprKind.Private, flag.type, (out.privates.length - 1) as int32, []);
	out.functions = m.functions.map((f, i) => reached.includes(i as int32) ?
		demotedFunction(d, i as int32) : f);
	if (d.errors.length > 0) { return Result.err("demote: " + d.errors.join("; ")); }
	return Result.ok(out);
}
