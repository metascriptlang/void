import { Offsets, shiftExpr, shiftStmts, shiftType } from "./descriptor";
import {
	DeclarationKind,
	ExprKind,
	ShaderExpr,
	ShaderFunction,
	ShaderModule,
	ShaderStmt,
	ShaderTypeKind,
	StmtKind,
	exprOf,
	sameShaderType,
	stmtOf,
} from "./ir";
import { irFromText, irText } from "./irText";
import { suffixed } from "./names";

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
		const index = try merge(m, e, segment.name);
		chains[at] = exprOf(ExprKind.Call, chains[at].type, index, [chains[at]]);
	}
	for (let k = 0; k < sites.length; k++) {
		m.functions[sites[k]].body = [stmtOf(StmtKind.Return, chains[k], [])];
	}
	return Result.ok(m);
}
