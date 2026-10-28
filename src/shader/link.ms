import {
	Offsets,
	checked,
	joinedProgram,
	programModule,
	shiftExpr,
	shiftStmts,
	shiftType,
} from "./descriptor";
import {
	AssignOp,
	Builtin,
	DeclarationKind,
	ExprKind,
	IoDirection,
	ShaderExpr,
	ShaderFunction,
	ShaderIo,
	ShaderModule,
	ShaderStage,
	ShaderStmt,
	ShaderType,
	ShaderTypeKind,
	StmtKind,
	exprOf,
	literal,
	rootOf,
	sameShaderType,
	scalarType,
	stmtOf,
} from "./ir";
import { functionOrder, hasEffect, stmtExprs } from "./irWalk";
import { irFromText, irText } from "./irText";
import { slotLimit } from "./layout";
import { suffixed } from "./names";
import { withoutUnread } from "./specialize";

function phaseOf(m: ShaderModule, f: ShaderFunction): string {
	if (f.params.length != 1 || f.result.kind != ShaderTypeKind.Struct ||
		!sameShaderType(f.params[0].type, f.result)) {
		return "";
	}
	return m.structs[f.result.structIndex].name;
}

function isHookSite(m: ShaderModule, f: ShaderFunction): boolean {
	if (!m.structs.some((s) => s.name == f.name)) { return false; }
	const body = f.body.length == 1 ? f.body[0] : new ShaderStmt();
	if (phaseOf(m, f) != f.name || f.locals.length > 0 || body.kind != StmtKind.Return ||
		body.expr.kind != ExprKind.Param || body.expr.index != 0) {
		throw new Error("link: function '" + f.name + "' is named as a struct and is no hook " +
			"site, whose body returns its phase");
	}
	return true;
}

function sameMembers(into: ShaderModule, held: int32, from: ShaderModule, s: int32): boolean {
	const a = into.structs[held].members;
	const b = from.structs[s].members;
	if (a.length != b.length) { return false; }
	for (let i = 0; i < a.length; i++) {
		if (a[i].name != b[i].name || !sameShaderType(a[i].type, b[i].type)) { return false; }
	}
	return true;
}

function merge(into: ShaderModule, from: ShaderModule, effect: string): Result<int32, string> {
	let o: Offsets = {
		structs: [],
		constants: into.constants.length as int32,
		resources: [],
		ios: [],
		functions: into.functions.length as int32,
		workgroups: into.workgroups.length as int32,
	};
	const structsBefore = into.structs.length as int32;
	for (let i = 0; i < from.structs.length; i++) {
		const s = from.structs[i];
		for (const f of s.members) { shiftType(o, f.type); }
		const held = into.structs.findIndex((h) => h.name == s.name);
		if (held < 0) {
			o.structs.push(into.structs.length as int32);
			into.structs.push(s);
			continue;
		}
		if (!sameMembers(into, held as int32, from, i as int32)) {
			return Result.err("link: effect '" + effect + "' declares struct '" + s.name +
				"' with other members than the linked module's '" + s.name + "'");
		}
		o.structs.push(held as int32);
	}
	for (const c of from.constants) {
		shiftType(o, c.type);
		shiftExpr(o, c.value);
		c.name = suffixed(c.name, into.constants.map((k) => k.name));
		into.constants.push(c);
	}
	for (const r of from.resources) {
		shiftType(o, r.type);
		const held = into.resources.findIndex((h) => h.name == r.name);
		if (held < 0) {
			o.resources.push(into.resources.length as int32);
			into.resources.push(r);
			continue;
		}
		const h = into.resources[held];
		if (h.kind != r.kind || !sameShaderType(h.type, r.type)) {
			return Result.err("link: effect '" + effect + "' declares resource '" + r.name +
				"' with another kind or type than the linked module's '" + r.name + "'");
		}
		o.resources.push(held as int32);
	}
	for (const f of from.functions) {
		for (const p of f.params) { shiftType(o, p.type); }
		for (const l of f.locals) { shiftType(o, l.type); }
		shiftType(o, f.result);
		shiftStmts(o, f.body);
		f.name = suffixed(f.name, into.functions.map((g) => g.name));
		into.functions.push(f);
	}
	for (const d of from.declarations) {
		if (d.kind == DeclarationKind.Struct) {
			if (o.structs[d.index] < structsBefore) { continue; }
			d.index = o.structs[d.index];
		} else if (d.kind == DeclarationKind.Constant) {
			d.index += o.constants;
		} else {
			d.index += o.functions;
		}
		into.declarations.push(d);
	}
	return Result.ok((into.functions.length - 1) as int32);
}

function numberBindings(m: ShaderModule, owners: string[], effects: string[]):
	Result<void, string> {
	for (const r of m.resources) {
		if (r.binding >= 0) { continue; }
		const effect = effects[owners.indexOf(r.name)];
		let next = 0;
		for (const o of m.resources) {
			if (o.group == r.group && o.binding >= next) { next = o.binding + 1; }
		}
		if (next >= slotLimit(r.kind)) {
			return Result.err("link: effect '" + effect + "' finds no binding for " +
				r.kind.toString() + " '" + r.name + "': bindings 0.." +
				String(slotLimit(r.kind) - 1) + " are taken");
		}
		r.binding = next;
	}
	return Result.ok(null);
}

export function link(base: ShaderModule, effects: ShaderModule[]): Result<ShaderModule, string> {
	let m = try irFromText(irText(base));
	let sites: int32[] = [];
	let chains: ShaderExpr[] = [];
	for (let i = 0; i < m.functions.length; i++) {
		const f = m.functions[i];
		if (!isHookSite(m, f)) { continue; }
		sites.push(i as int32);
		chains.push(exprOf(ExprKind.Param, f.result, 0, []));
	}
	let owners: string[] = [];
	let owning: string[] = [];
	for (const given of effects) {
		const e = try irFromText(irText(given));
		const segment = e.functions.length > 0 ? e.functions[e.functions.length - 1] :
			new ShaderFunction();
		const phase = phaseOf(e, segment);
		if (e.entries.length > 0 || e.ios.length > 0 || e.workgroups.length > 0 || phase == "") {
			return Result.err("link: effect '" + segment.name + "' is no segment: a module " +
				"without entries whose last function takes and returns its phase struct");
		}
		const at = sites.findIndex((s) => m.functions[s].name == phase);
		if (at < 0) {
			return Result.err("link: effect '" + segment.name + "' works on phase '" + phase +
				"', which the base has no hook site for");
		}
		const effect = segment.name;
		const index = try merge(m, e, effect);
		for (const r of m.resources) {
			if (r.binding < 0 && !owners.includes(r.name)) {
				owners.push(r.name);
				owning.push(effect);
			}
		}
		chains[at] = exprOf(ExprKind.Call, chains[at].type, index, [chains[at]]);
	}
	for (let k = 0; k < sites.length; k++) {
		m.functions[sites[k]].body = [stmtOf(StmtKind.Return, chains[k], [])];
	}
	for (const f of m.functions) { pruneDeadFields(m, f); }
	const kept = try withoutUnread(try withoutUnreadVaryings(m));
	try numberBindings(kept, owners, owning);
	return Result.ok(kept);
}

export function linkedProgram(vertexText: string, fragmentText: string, on: string[],
	segmentTexts: string[]): Result<ShaderModule, string> {
	if (segmentTexts.length == 0) { return programModule(vertexText, fragmentText, on); }
	const m = try joinedProgram(vertexText, fragmentText, on);
	let segments: ShaderModule[] = [];
	for (const text of segmentTexts) { segments.push(try irFromText(text)); }
	return checked(try link(m, segments), "the program");
}

class Liveness {
	module: ShaderModule = new ShaderModule();
	live: boolean[][] = [];
	effects: int32[] = [];
	changed: boolean = false;
}

function isIdentity(m: ShaderModule, index: int32): boolean {
	const f = m.functions[index];
	return f.params.length == 1 && f.body.length == 1 && f.body[0].kind == StmtKind.Return &&
		f.body[0].expr.kind == ExprKind.Param && f.body[0].expr.index == 0;
}

function localOf(m: ShaderModule, e: ShaderExpr): int32 {
	if (e.kind == ExprKind.Local) { return e.index; }
	if (e.kind == ExprKind.Call && isIdentity(m, e.index)) { return localOf(m, e.operands[0]); }
	return -1;
}

function setLive(l: Liveness, local: int32, field: int32): void {
	if (!l.live[local][field]) {
		l.live[local][field] = true;
		l.changed = true;
	}
}

function markRead(l: Liveness, e: ShaderExpr): void {
	if (e.kind == ExprKind.Field) {
		const held = localOf(l.module, e.operands[0]);
		if (held >= 0 && l.live[held].length > 0) {
			setLive(l, held, e.index);
			return;
		}
	}
	const whole = localOf(l.module, e);
	if (whole >= 0) {
		for (let k = 0; k < l.live[whole].length; k++) { setLive(l, whole, k as int32); }
		return;
	}
	for (const o of e.operands) { markRead(l, o); }
}

function isStructValue(e: ShaderExpr): boolean {
	return e.kind == ExprKind.Construct && e.type.kind == ShaderTypeKind.Struct;
}

function flowInto(l: Liveness, local: int32, value: ShaderExpr): void {
	if (l.live[local].length == 0) {
		markRead(l, value);
		return;
	}
	if (isStructValue(value)) {
		for (let i = 0; i < value.operands.length; i++) {
			const o = value.operands[i];
			if (l.live[local][i] || hasEffect(l.module, l.effects, o)) { markRead(l, o); }
		}
		return;
	}
	const from = localOf(l.module, value);
	if (from < 0) {
		markRead(l, value);
		return;
	}
	for (let k = 0; k < l.live[local].length; k++) {
		if (l.live[local][k]) { setLive(l, from, k as int32); }
	}
}

function storedField(target: ShaderExpr): int32 {
	let e = target;
	while (e.operands.length > 0) {
		if (e.kind == ExprKind.Field && e.operands[0].kind == ExprKind.Local) { return e.index; }
		e = e.operands[0];
	}
	return -1;
}

function isDeadStore(l: Liveness, s: ShaderStmt): boolean {
	const root = rootOf(s.target);
	if (s.kind != StmtKind.Assign || root.kind != ExprKind.Local) { return false; }
	const field = storedField(s.target);
	return field >= 0 && l.live[root.index].length > 0 && !l.live[root.index][field] &&
		!hasEffect(l.module, l.effects, s.expr) && !hasEffect(l.module, l.effects, s.target);
}

function isWholeSet(s: ShaderStmt): boolean {
	return s.kind == StmtKind.Assign && s.assign == AssignOp.Set &&
		s.target.kind == ExprKind.Local;
}

function liveStmts(l: Liveness, stmts: ShaderStmt[]): void {
	for (const s of stmts) {
		if (s.kind == StmtKind.Let && s.local >= 0) {
			flowInto(l, s.local, s.expr);
		} else if (isWholeSet(s)) {
			flowInto(l, s.target.index, s.expr);
		} else if (!isDeadStore(l, s)) {
			markRead(l, s.expr);
			markRead(l, s.target);
		}
		for (const list of [s.init, s.update, s.body, s.otherwise]) { liveStmts(l, list); }
		for (const arm of s.cases) {
			for (const label of arm.labels) { markRead(l, label); }
			liveStmts(l, arm.body);
		}
	}
}

function isZeroable(t: ShaderType): boolean {
	return t.kind == ShaderTypeKind.Scalar || t.kind == ShaderTypeKind.Vector;
}

function zeroOf(t: ShaderType): ShaderExpr {
	if (t.kind == ShaderTypeKind.Scalar) { return literal(t, 0.0); }
	return exprOf(ExprKind.Construct, t, -1, [literal(scalarType(t.scalar), 0.0)]);
}

function pruneValue(l: Liveness, local: int32, value: ShaderExpr): void {
	if (l.live[local].length == 0 || !isStructValue(value)) { return; }
	for (let i = 0; i < value.operands.length; i++) {
		const o = value.operands[i];
		if (!l.live[local][i] && isZeroable(o.type) && !hasEffect(l.module, l.effects, o)) {
			value.operands[i] = zeroOf(o.type);
		}
	}
}

function pruneStmts(l: Liveness, stmts: ShaderStmt[]): ShaderStmt[] {
	let out: ShaderStmt[] = [];
	for (const s of stmts) {
		if (s.kind == StmtKind.Let && s.local >= 0) {
			pruneValue(l, s.local, s.expr);
		} else if (isWholeSet(s)) {
			pruneValue(l, s.target.index, s.expr);
		} else if (isDeadStore(l, s)) {
			continue;
		}
		s.init = pruneStmts(l, s.init);
		s.update = pruneStmts(l, s.update);
		s.body = pruneStmts(l, s.body);
		s.otherwise = pruneStmts(l, s.otherwise);
		for (const arm of s.cases) { arm.body = pruneStmts(l, arm.body); }
		out.push(s);
	}
	return out;
}

function pruneDeadFields(m: ShaderModule, f: ShaderFunction): void {
	let l = new Liveness();
	l.module = m;
	l.effects = m.functions.map((_) => 0 as int32);
	l.live = f.locals.map((v) => v.type.kind == ShaderTypeKind.Struct ?
		m.structs[v.type.structIndex].members.map((_) => false) : []);
	l.changed = true;
	while (l.changed) {
		l.changed = false;
		liveStmts(l, f.body);
	}
	f.body = pruneStmts(l, f.body);
}

function ioReads(e: ShaderExpr, out: int32[]): void {
	if (e.kind == ExprKind.Io && !out.includes(e.index)) { out.push(e.index); }
	for (const o of e.operands) { ioReads(o, out); }
}

function varyingsOf(m: ShaderModule, stage: ShaderStage, direction: IoDirection): int32[] {
	let out: int32[] = [];
	for (let i = 0; i < m.ios.length; i++) {
		const io = m.ios[i];
		if (io.stage == stage && io.direction == direction && io.builtin == Builtin.None) {
			out.push(i as int32);
		}
	}
	return out;
}

function withoutStores(m: ShaderModule, stmts: ShaderStmt[], dropped: int32[],
	effects: int32[], stray: string[]): ShaderStmt[] {
	let out: ShaderStmt[] = [];
	for (const s of stmts) {
		const root = rootOf(s.target);
		if (s.kind == StmtKind.Assign && root.kind == ExprKind.Io && dropped.includes(root.index)) {
			if (hasEffect(m, effects, s.expr) || hasEffect(m, effects, s.target)) {
				stray.push(m.ios[root.index].name);
			}
			continue;
		}
		s.init = withoutStores(m, s.init, dropped, effects, stray);
		s.update = withoutStores(m, s.update, dropped, effects, stray);
		s.body = withoutStores(m, s.body, dropped, effects, stray);
		s.otherwise = withoutStores(m, s.otherwise, dropped, effects, stray);
		for (const arm of s.cases) { arm.body = withoutStores(m, arm.body, dropped, effects, stray); }
		out.push(s);
	}
	return out;
}

function renumberIos(e: ShaderExpr, map: int32[], stray: string[], names: string[]): void {
	if (e.kind == ExprKind.Io) {
		if (map[e.index] < 0) { stray.push(names[e.index]); }
		e.index = map[e.index];
	}
	for (const o of e.operands) { renumberIos(o, map, stray, names); }
}

function withoutUnreadVaryings(m: ShaderModule): Result<ShaderModule, string> {
	const vertex = m.entries.filter((e) => e.stage == ShaderStage.Vertex);
	const fragment = m.entries.filter((e) => e.stage == ShaderStage.Fragment);
	if (vertex.length != 1 || fragment.length != 1) { return Result.ok(m); }
	let reachable: int32[] = [];
	functionOrder(m, fragment[0].functionIndex, [], reachable);
	let read: int32[] = [];
	for (const f of reachable) { stmtExprs(m.functions[f].body, (e) => ioReads(e, read)); }
	const outs = varyingsOf(m, ShaderStage.Vertex, IoDirection.Out);
	const ins = varyingsOf(m, ShaderStage.Fragment, IoDirection.In);
	let dropped: int32[] = [];
	for (let k = 0; k < outs.length && k < ins.length; k++) {
		if (!read.includes(ins[k])) {
			dropped.push(outs[k]);
			dropped.push(ins[k]);
		}
	}
	if (dropped.length == 0) { return Result.ok(m); }
	const effects = m.functions.map((_) => 0 as int32);
	let stray: string[] = [];
	for (const f of m.functions) { f.body = withoutStores(m, f.body, dropped, effects, stray); }
	if (stray.length > 0) {
		return Result.err("link: varying '" + stray[0] + "' is read by no fragment, and the " +
			"value its vertex stores has an effect");
	}
	let map: int32[] = [];
	let ios: ShaderIo[] = [];
	for (let i = 0; i < m.ios.length; i++) {
		map.push(dropped.includes(i as int32) ? -1 : ios.length as int32);
		if (map[i] >= 0) { ios.push(m.ios[i]); }
	}
	const names = m.ios.map((io) => io.name);
	for (const f of m.functions) {
		stmtExprs(f.body, (e) => renumberIos(e, map, stray, names));
	}
	if (stray.length > 0) {
		return Result.err("link: varying '" + stray[0] + "' is dropped and still read");
	}
	m.ios = ios;
	return Result.ok(m);
}
