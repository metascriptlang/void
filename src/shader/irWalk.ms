import {
	ConditionKind,
	ExprKind,
	ShaderExpr,
	ShaderModule,
	ShaderStage,
	ShaderStmt,
	ShaderType,
	ShaderTypeKind,
	StmtKind,
	isEffect,
} from "./ir";

export function innermost(t: ShaderType): ShaderType {
	return t.kind == ShaderTypeKind.Array ? innermost(t.element[0]) : t;
}

export function rootOf(e: ShaderExpr): ShaderExpr {
	const through = e.kind == ExprKind.Field || e.kind == ExprKind.Swizzle ||
		e.kind == ExprKind.Index;
	return through && e.operands.length > 0 ? rootOf(e.operands[0]) : e;
}

export function stmtsHaveEffect(m: ShaderModule, effects: int32[], stmts: ShaderStmt[]): boolean {
	for (const s of stmts) {
		const root = rootOf(s.target).kind;
		const writes = s.kind == StmtKind.Assign &&
			(root == ExprKind.Io || root == ExprKind.Resource);
		if (writes || hasEffect(m, effects, s.expr) || hasEffect(m, effects, s.target)) {
			return true;
		}
		for (const list of [s.init, s.update, s.body, s.otherwise]) {
			if (stmtsHaveEffect(m, effects, list)) { return true; }
		}
		for (const arm of s.cases) {
			if (stmtsHaveEffect(m, effects, arm.body)) { return true; }
		}
	}
	return false;
}

export function hasEffect(m: ShaderModule, effects: int32[], e: ShaderExpr): boolean {
	if (e.kind == ExprKind.Intrinsic && isEffect(e.intrinsic)) { return true; }
	if (e.kind == ExprKind.Call) {
		if (effects[e.index] == 0) {
			effects[e.index] = 1;
			effects[e.index] = stmtsHaveEffect(m, effects, m.functions[e.index].body) ? 2 : 1;
		}
		if (effects[e.index] == 2) { return true; }
	}
	return e.operands.some((o) => hasEffect(m, effects, o));
}

export function exprCalls(e: ShaderExpr, out: int32[]): void {
	if (e.kind == ExprKind.Call && !out.includes(e.index)) { out.push(e.index); }
	for (const o of e.operands) { exprCalls(o, out); }
}

export function calls(stmts: ShaderStmt[], out: int32[]): void {
	for (const s of stmts) {
		exprCalls(s.expr, out);
		exprCalls(s.target, out);
		for (const list of [s.init, s.update, s.body, s.otherwise]) { calls(list, out); }
		for (const arm of s.cases) {
			for (const label of arm.labels) { exprCalls(label, out); }
			calls(arm.body, out);
		}
	}
}

export function structOrder(m: ShaderModule, t: ShaderType, out: int32[]): void {
	for (const e of t.element) { structOrder(m, e, out); }
	if (t.kind != ShaderTypeKind.Struct || out.includes(t.structIndex)) { return; }
	for (const f of m.structs[t.structIndex].members) { structOrder(m, f.type, out); }
	out.push(t.structIndex);
}

export function exprStructs(
	m: ShaderModule,
	e: ShaderExpr,
	skipBlockMembers: boolean,
	out: int32[],
): void {
	if (!skipBlockMembers || e.kind != ExprKind.BlockMember) { structOrder(m, e.type, out); }
	for (const o of e.operands) { exprStructs(m, o, skipBlockMembers, out); }
}

export function stmtStructs(
	m: ShaderModule,
	stmts: ShaderStmt[],
	skipBlockMembers: boolean,
	out: int32[],
): void {
	for (const s of stmts) {
		exprStructs(m, s.expr, skipBlockMembers, out);
		exprStructs(m, s.target, skipBlockMembers, out);
		for (const list of [s.init, s.update, s.body, s.otherwise]) {
			stmtStructs(m, list, skipBlockMembers, out);
		}
		for (const arm of s.cases) {
			for (const label of arm.labels) { exprStructs(m, label, skipBlockMembers, out); }
			stmtStructs(m, arm.body, skipBlockMembers, out);
		}
	}
}

export function constantOrder(m: ShaderModule, e: ShaderExpr, out: int32[]): void {
	for (const o of e.operands) { constantOrder(m, o, out); }
	if (e.kind == ExprKind.Constant && !out.includes(e.index)) {
		constantOrder(m, m.constants[e.index].value, out);
		out.push(e.index);
	}
}

export function unspecialized(
	m: ShaderModule,
	stage: ShaderStage,
	resources: int32[],
	functions: int32[],
): string {
	const held = (kind: ConditionKind) => kind == ConditionKind.Always;
	for (const io of m.ios) {
		if (io.stage == stage && !held(io.condition.kind)) { return "io '" + io.name + "'"; }
	}
	for (const r of resources) {
		if (!held(m.resources[r].condition.kind)) {
			return "resource '" + m.resources[r].name + "'";
		}
	}
	for (const f of functions) {
		if (!held(m.functions[f].condition.kind)) {
			return "function '" + m.functions[f].name + "'";
		}
	}
	return "";
}
