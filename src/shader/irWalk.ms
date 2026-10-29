import {
	Builtin,
	ConditionKind,
	ExprKind,
	ResourceKind,
	ScalarKind,
	ShaderExpr,
	ShaderIo,
	ShaderModule,
	ShaderStage,
	ShaderStmt,
	ShaderType,
	ShaderTypeKind,
	StmtKind,
	isEffect,
	rootOf,
	sameShaderType,
	scalarType,
	vectorType,
} from "./ir";

export function withoutSamplers(args: ShaderExpr[]): ShaderExpr[] {
	return args.filter((a) => a.type.kind != ShaderTypeKind.Sampler);
}

export function hasCallOrEffect(e: ShaderExpr): boolean {
	return e.kind == ExprKind.Call || e.kind == ExprKind.Intrinsic && isEffect(e.intrinsic) ||
		e.operands.some((o) => hasCallOrEffect(o));
}

export function innermost(t: ShaderType): ShaderType {
	return t.kind == ShaderTypeKind.Array ? innermost(t.element[0]) : t;
}

export function ioLocation(io: ShaderIo, ordinal: int32): int32 {
	return io.location >= 0 ? io.location : ordinal;
}

export function builtinType(b: Builtin): ShaderType {
	return match (b) {
		Builtin.Position => vectorType(ScalarKind.F32, 4),
		Builtin.FrontFacing => scalarType(ScalarKind.Bool),
		Builtin.FragDepth => scalarType(ScalarKind.F32),
		Builtin.LocalInvocationId | Builtin.GlobalInvocationId | Builtin.WorkgroupId |
			Builtin.NumWorkgroups => vectorType(ScalarKind.U32, 3),
		Builtin.VertexIndex | Builtin.InstanceIndex | Builtin.LocalInvocationIndex |
			Builtin.SampleIndex | Builtin.SampleMask | Builtin.PrimitiveIndex =>
			scalarType(ScalarKind.U32),
		Builtin.None => { throw new Error("internal: builtinType of Builtin.None"); },
	};
}

function stmtsHaveEffect(m: ShaderModule, effects: int32[], stmts: ShaderStmt[]): boolean {
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

// Calls visit on the expressions every statement of stmts holds, nested statements and case
// labels included, in source order.
export function stmtExprs(stmts: ShaderStmt[], visit: (e: ShaderExpr) => void): void {
	for (const s of stmts) {
		visit(s.expr);
		visit(s.target);
		for (const list of [s.init, s.update, s.body, s.otherwise]) { stmtExprs(list, visit); }
		for (const arm of s.cases) {
			for (const label of arm.labels) { visit(label); }
			stmtExprs(arm.body, visit);
		}
	}
}

function exprCalls(e: ShaderExpr, out: int32[]): void {
	if (e.kind == ExprKind.Call && !out.includes(e.index)) { out.push(e.index); }
	for (const o of e.operands) { exprCalls(o, out); }
}

function calls(stmts: ShaderStmt[], out: int32[]): void {
	stmtExprs(stmts, (e) => exprCalls(e, out));
}

export function functionOrder(m: ShaderModule, index: int32, path: int32[], out: int32[]): void {
	if (out.includes(index) || path.includes(index)) { return; }
	path.push(index);
	let callees: int32[] = [];
	calls(m.functions[index].body, callees);
	for (const c of callees) { functionOrder(m, c, path, out); }
	path.pop();
	out.push(index);
}

export function structOrder(m: ShaderModule, t: ShaderType, out: int32[]): void {
	for (const e of t.element) { structOrder(m, e, out); }
	if (t.kind != ShaderTypeKind.Struct || out.includes(t.structIndex)) { return; }
	for (const f of m.structs[t.structIndex].members) { structOrder(m, f.type, out); }
	out.push(t.structIndex);
}

function exprStructs(
	m: ShaderModule,
	e: ShaderExpr,
	skipBlockMembers: boolean,
	out: int32[],
): void {
	if (!skipBlockMembers || e.kind != ExprKind.BlockMember) { structOrder(m, e.type, out); }
	for (const o of e.operands) { exprStructs(m, o, skipBlockMembers, out); }
}

function stmtStructs(
	m: ShaderModule,
	stmts: ShaderStmt[],
	skipBlockMembers: boolean,
	out: int32[],
): void {
	stmtExprs(stmts, (e) => exprStructs(m, e, skipBlockMembers, out));
}

function constantOrder(m: ShaderModule, e: ShaderExpr, out: int32[]): void {
	for (const o of e.operands) { constantOrder(m, o, out); }
	if (e.kind == ExprKind.Constant && !out.includes(e.index)) {
		constantOrder(m, m.constants[e.index].value, out);
		out.push(e.index);
	}
}

export function constantsInOrder(m: ShaderModule, roots: int32[]): int32[] {
	let out: int32[] = [];
	for (const c of roots) {
		if (out.includes(c)) { continue; }
		constantOrder(m, m.constants[c].value, out);
		out.push(c);
	}
	return out;
}

export function ofKinds(m: ShaderModule, resources: int32[], kinds: ResourceKind[]): int32[] {
	let out: int32[] = [];
	for (const kind of kinds) {
		for (const r of resources) {
			if (m.resources[r].kind == kind) { out.push(r); }
		}
	}
	return out;
}

export function entryStructs(
	m: ShaderModule,
	functions: int32[],
	resources: int32[],
	constants: int32[],
	stage: ShaderStage,
	skipBlockMembers: boolean,
): int32[] {
	let out: int32[] = [];
	for (const f of functions) {
		const callee = m.functions[f];
		for (const v of callee.params) { structOrder(m, v.type, out); }
		for (const v of callee.locals) { structOrder(m, v.type, out); }
		structOrder(m, callee.result, out);
		stmtStructs(m, callee.body, skipBlockMembers, out);
	}
	for (const r of resources) {
		if (m.resources[r].kind == ResourceKind.StorageBuffer) {
			structOrder(m, m.resources[r].type, out);
		}
	}
	for (const c of constants) { exprStructs(m, m.constants[c].value, skipBlockMembers, out); }
	for (const io of m.ios) {
		if (io.stage == stage) { structOrder(m, io.type, out); }
	}
	return out;
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

function exprSplits(e: ShaderExpr, out: ShaderType[]): void {
	const split = e.type.kind == ShaderTypeKind.ModfResult ||
		e.type.kind == ShaderTypeKind.FrexpResult;
	if (split && !out.some((t) => sameShaderType(t, e.type))) { out.push(e.type); }
	for (const o of e.operands) { exprSplits(o, out); }
}

function stmtSplits(stmts: ShaderStmt[], out: ShaderType[]): void {
	stmtExprs(stmts, (e) => exprSplits(e, out));
}

// The modf and frexp result types the functions use, in first-use order: a printer declares each
// one's struct and the helper that makes it once, before any function.
export function splitResults(m: ShaderModule, functions: int32[]): ShaderType[] {
	let out: ShaderType[] = [];
	for (const f of functions) { stmtSplits(m.functions[f].body, out); }
	return out;
}
