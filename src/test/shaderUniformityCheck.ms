// A barrier and a workgroup uniform load are reached by every invocation of the workgroup, as the
// WGSL uniformity rule needs: the IR refuses one under control flow that differs between
// invocations, so no backend prints it. Modules are built by hand, because the macro stops at the
// refusal (tests/refusals/barrierNonUniform.ms).

import { stageSource } from "../shader/descriptor";
import { ShaderTarget } from "../shader/layout";
import {
	Access,
	AssignOp,
	BinaryOp,
	Builtin,
	ExprKind,
	Intrinsic,
	IoDirection,
	ResourceKind,
	ScalarKind,
	ShaderCase,
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
	arrayType,
	assignOf,
	binaryOf,
	exprOf,
	intrinsicOf,
	irErrors,
	literal,
	scalarType,
	stmtOf,
	structType,
	vectorType,
} from "../shader/ir";

const U32 = scalarType(ScalarKind.U32);
const BOOL = scalarType(ScalarKind.Bool);
const VEC3U = vectorType(ScalarKind.U32, 3);

const LID = "builtin localInvocationId";
const IF_LID = "an if whose condition depends on " + LID;

function field(name: string, type: ShaderType): ShaderField {
	let f = new ShaderField();
	f.name = name;
	f.type = type;
	return f;
}

function resource(kind: ResourceKind, name: string, binding: int32, type: ShaderType,
	access: Access): ShaderResource {
	let r = new ShaderResource();
	r.kind = kind;
	r.name = name;
	r.binding = binding;
	r.type = type;
	r.access = access;
	return r;
}

function io(name: string, builtin: Builtin): ShaderIo {
	let v = new ShaderIo();
	v.name = name;
	v.stage = ShaderStage.Compute;
	v.direction = IoDirection.In;
	v.type = VEC3U;
	v.builtin = builtin;
	return v;
}

function shaderFunction(name: string, params: ShaderField[], locals: ShaderField[],
	result: ShaderType, body: ShaderStmt[]): ShaderFunction {
	let f = new ShaderFunction();
	f.name = name;
	f.params = params;
	f.locals = locals;
	f.result = result;
	f.body = body;
	return f;
}

function ret(): ShaderStmt { return stmtOf(StmtKind.Return, new ShaderExpr(), []); }

function x(of: ShaderExpr): ShaderExpr {
	let e = exprOf(ExprKind.Swizzle, U32, -1, [of]);
	e.components = [0];
	return e;
}

function localId(): ShaderExpr { return x(exprOf(ExprKind.Io, VEC3U, 0, [])); }

function workgroupId(): ShaderExpr { return x(exprOf(ExprKind.Io, VEC3U, 1, [])); }

function limit(): ShaderExpr {
	let e = exprOf(ExprKind.BlockMember, U32, 0, []);
	e.member = 0;
	return e;
}

function stored(): ShaderExpr {
	const items = arrayType(structType(1), -1);
	const element = exprOf(ExprKind.Index, structType(1), -1,
		[exprOf(ExprKind.Resource, items, 1, []), literal(U32, 0.0)]);
	let e = exprOf(ExprKind.Field, U32, -1, [element]);
	e.index = 0;
	return e;
}

function tile(): ShaderExpr { return exprOf(ExprKind.Workgroup, U32, 0, []); }

function local(i: int32): ShaderExpr { return exprOf(ExprKind.Local, U32, i, []); }

function param(i: int32): ShaderExpr { return exprOf(ExprKind.Param, U32, i, []); }

function zero(): ShaderExpr { return literal(U32, 0.0); }

function equal(a: ShaderExpr, b: ShaderExpr): ShaderExpr {
	return binaryOf(BinaryOp.Equal, BOOL, a, b);
}

function barrier(op: Intrinsic): ShaderStmt {
	return stmtOf(StmtKind.Call, intrinsicOf(op, new ShaderType(), []), []);
}

function when(cond: ShaderExpr, body: ShaderStmt[]): ShaderStmt {
	return stmtOf(StmtKind.If, cond, body);
}

function bind(at: int32, value: ShaderExpr): ShaderStmt {
	let s = stmtOf(StmtKind.Let, value, []);
	s.local = at;
	return s;
}

function callOf(index: int32, args: ShaderExpr[]): ShaderExpr {
	return exprOf(ExprKind.Call, new ShaderType(), index, args);
}

// for (let i = 0; i < bound; i++) { body }, with i as local 0.
function counted(bound: ShaderExpr, body: ShaderStmt[]): ShaderStmt {
	let step = assignOf(local(0), new ShaderExpr());
	step.assign = AssignOp.Increment;
	let loop = stmtOf(StmtKind.For, binaryOf(BinaryOp.Less, BOOL, local(0), bound), body);
	loop.init = [bind(0, zero())];
	loop.update = [step];
	return loop;
}

function arm(label: ShaderExpr, body: ShaderStmt[]): ShaderCase {
	let k = new ShaderCase();
	k.labels = [label];
	k.body = body;
	return k;
}

// A compute entry 'kernel' over a uniform block with `limit`, a read_write storage buffer
// `data`, the workgroup variable `tile` and the local and workgroup ids. Helpers follow it.
function kernelOf(locals: ShaderField[], body: ShaderStmt[],
	helpers: ShaderFunction[]): ShaderModule {
	let m = new ShaderModule();
	let params = new ShaderStruct();
	params.name = "Params";
	params.members = [field("limit", U32)];
	let item = new ShaderStruct();
	item.name = "Item";
	item.members = [field("n", U32)];
	m.structs.push(params);
	m.structs.push(item);
	m.resources.push(resource(ResourceKind.UniformBlock, "params", 0, structType(0),
		Access.Read));
	m.resources.push(resource(ResourceKind.StorageBuffer, "data", 1,
		arrayType(structType(1), -1), Access.ReadWrite));
	m.ios.push(io("local", Builtin.LocalInvocationId));
	m.ios.push(io("group", Builtin.WorkgroupId));
	m.workgroups.push(field("tile", U32));
	m.functions.push(shaderFunction("kernel", [], locals, new ShaderType(),
		body.concat([ret()])));
	for (const h of helpers) { m.functions.push(h); }
	let e = new ShaderEntry();
	e.name = "kernel";
	e.stage = ShaderStage.Compute;
	e.functionIndex = 0;
	e.workgroupSize = [64, 1, 1];
	m.entries.push(e);
	return m;
}

function plain(body: ShaderStmt[]): ShaderModule { return kernelOf([], body, []); }

function reached(op: string, flow: string): string {
	return op + " runs in non-uniform control flow, " + flow + "; WGSL's uniformity rule " +
		"needs every invocation of the workgroup to reach it";
}

function refusal(fn: string, op: string, flow: string): string {
	return "function '" + fn + "': " + reached(op, flow);
}

function refusedAs(m: ShaderModule, named: string): boolean {
	const errors = irErrors(m);
	return errors.length == 1 && errors[0] == named;
}

const BARRIER = Intrinsic.WorkgroupBarrier;

test "a barrier in flow every invocation shares is legal" {
	assert irErrors(plain([barrier(BARRIER)])).length == 0;
	assert irErrors(plain([when(equal(limit(), zero()), [barrier(BARRIER)])])).length == 0;
	assert irErrors(plain([when(equal(workgroupId(), zero()), [barrier(BARRIER)])])).length == 0;
	const never = when(equal(literal(U32, 1.0), zero()), [barrier(BARRIER)]);
	assert irErrors(plain([never])).length == 0;
	assert irErrors(plain([when(equal(limit(), zero()), [ret()]), barrier(BARRIER)])).length == 0;
}

test "flow rejoins after a branch that holds no barrier" {
	const split = when(equal(localId(), zero()), [assignOf(stored(), literal(U32, 1.0))]);
	const both = [split, barrier(BARRIER), barrier(Intrinsic.StorageBarrier)];
	assert irErrors(plain(both)).length == 0;
}

test "a loop bounded by a uniform value keeps its barrier legal" {
	assert irErrors(kernelOf([field("i", U32)], [counted(limit(), [barrier(BARRIER)])], []))
		.length == 0;
	const early = counted(limit(), [when(equal(limit(), zero()), [stmtOf(StmtKind.Break,
		new ShaderExpr(), [])]), barrier(BARRIER)]);
	assert irErrors(kernelOf([field("i", U32)], [early], [])).length == 0;
}

test "a barrier under a condition on the local id is refused" {
	const m = plain([when(equal(localId(), zero()), [barrier(BARRIER)])]);
	assert refusedAs(m, refusal("kernel", "workgroupBarrier", IF_LID));
}

test "every target refuses it" {
	const m = plain([when(equal(localId(), zero()), [barrier(BARRIER)])]);
	const named = refusal("kernel", "workgroupBarrier", IF_LID);
	for (const t of [ShaderTarget.Wgsl, ShaderTarget.Hlsl5, ShaderTarget.Glsl430,
		ShaderTarget.Msl]) {
		const printed = stageSource(m, 0, t);
		assert !printed.ok && printed.error.endsWith(": " + named);
	}
}

test "a storage or texture barrier is refused as a workgroup one is" {
	const named = ["storageBarrier", "textureBarrier"];
	const ops = [Intrinsic.StorageBarrier, Intrinsic.TextureBarrier];
	for (let i = 0; i < ops.length; i++) {
		const m = plain([when(equal(localId(), zero()), [barrier(ops[i])])]);
		assert refusedAs(m, refusal("kernel", named[i], IF_LID));
	}
}

test "a switch on a non-uniform value refuses a barrier in its arm" {
	let choice = stmtOf(StmtKind.Switch, localId(), []);
	choice.cases = [arm(literal(U32, 1.0), [barrier(Intrinsic.StorageBarrier)])];
	assert refusedAs(plain([choice]), refusal("kernel", "storageBarrier",
		"a switch whose condition depends on " + LID));
}

test "a loop bounded by read_write storage refuses the barrier in it" {
	const m = kernelOf([field("i", U32)], [counted(stored(), [barrier(BARRIER)])], []);
	assert refusedAs(m, refusal("kernel", "workgroupBarrier",
		"a loop whose condition depends on writable storage buffer 'data'"));
}

test "a non-uniform early return leaves the barrier after it refused" {
	const m = plain([when(equal(localId(), zero()), [ret()]), barrier(BARRIER)]);
	assert refusedAs(m, refusal("kernel", "workgroupBarrier", "an earlier return in " + IF_LID));
}

test "a non-uniform break or continue leaves the rest of the loop refused" {
	const leave = (kind: StmtKind) => when(equal(localId(), zero()),
		[stmtOf(kind, new ShaderExpr(), [])]);
	for (const kind of [StmtKind.Break, StmtKind.Continue]) {
		const after = kernelOf([field("i", U32)],
			[counted(limit(), [leave(kind), barrier(BARRIER)])], []);
		assert refusedAs(after, refusal("kernel", "workgroupBarrier",
			"an earlier break or continue in " + IF_LID));
		const before = kernelOf([field("i", U32)],
			[counted(limit(), [barrier(BARRIER), leave(kind)])], []);
		assert refusedAs(before, refusal("kernel", "workgroupBarrier",
			"an earlier break or continue in " + IF_LID));
	}
}

test "a value derived from a non-uniform one through a local is non-uniform" {
	const through = kernelOf([field("v", U32)],
		[bind(0, localId()), when(equal(local(0), zero()), [barrier(BARRIER)])], []);
	assert refusedAs(through, refusal("kernel", "workgroupBarrier", IF_LID));
	const assigned = kernelOf([field("v", U32)], [bind(0, limit()),
		assignOf(local(0), localId()), when(equal(local(0), zero()), [barrier(BARRIER)])], []);
	assert refusedAs(assigned, refusal("kernel", "workgroupBarrier", IF_LID));
	const rewritten = kernelOf([field("v", U32)], [bind(0, localId()),
		assignOf(local(0), limit()), when(equal(local(0), zero()), [barrier(BARRIER)])], []);
	assert irErrors(rewritten).length == 0;
}

test "a helper called with a non-uniform argument refuses its barrier" {
	const sync = shaderFunction("sync", [field("p", U32)], [], new ShaderType(),
		[when(equal(param(0), zero()), [barrier(BARRIER)]), ret()]);
	const skewed = kernelOf([], [stmtOf(StmtKind.Call, callOf(1, [localId()]), [])], [sync]);
	assert refusedAs(skewed, "function 'sync' (called from entry 'kernel'): " +
		reached("workgroupBarrier", IF_LID));
	const shared = kernelOf([], [stmtOf(StmtKind.Call, callOf(1, [limit()]), [])], [sync]);
	assert irErrors(shared).length == 0;
}

test "a helper's result carries the uniformity of what it returns" {
	const pick = shaderFunction("pick", [field("p", U32)], [], U32,
		[stmtOf(StmtKind.Return, param(0), [])]);
	const body = (arg: ShaderExpr) => [bind(0, exprOf(ExprKind.Call, U32, 1, [arg])),
		when(equal(local(0), zero()), [barrier(BARRIER)])];
	assert refusedAs(kernelOf([field("v", U32)], body(localId()), [pick]),
		refusal("kernel", "workgroupBarrier", IF_LID));
	assert irErrors(kernelOf([field("v", U32)], body(limit()), [pick])).length == 0;
}

test "read_write storage and workgroup memory are non-uniform, a uniform load is not" {
	assert refusedAs(plain([when(equal(stored(), zero()), [barrier(BARRIER)])]),
		refusal("kernel", "workgroupBarrier",
			"an if whose condition depends on writable storage buffer 'data'"));
	assert refusedAs(plain([when(equal(tile(), zero()), [barrier(BARRIER)])]),
		refusal("kernel", "workgroupBarrier",
			"an if whose condition depends on workgroup variable 'tile'"));
	const loaded = kernelOf([field("n", U32)], [bind(0,
		intrinsicOf(Intrinsic.WorkgroupUniformLoad, U32, [tile()])),
		when(equal(local(0), zero()), [barrier(BARRIER)])], []);
	assert irErrors(loaded).length == 0;
}

test "a workgroup uniform load is reached by every invocation too" {
	const load = bind(0, intrinsicOf(Intrinsic.WorkgroupUniformLoad, U32, [tile()]));
	const m = kernelOf([field("n", U32)], [when(equal(localId(), zero()), [load])], []);
	assert refusedAs(m, refusal("kernel", "workgroupUniformLoad", IF_LID));
}
