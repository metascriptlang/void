import {
	AssignOp,
	BinaryOp,
	Builtin,
	ExprKind,
	Intrinsic,
	IoDirection,
	ResourceKind,
	ShaderExpr,
	ShaderModule,
	ShaderStage,
	ShaderType,
	StmtKind,
	TextureShape,
	UnaryOp,
	arrayType,
	assignOf,
	binaryOf,
	exprOf,
	intrinsicOf,
	irErrors,
	literal,
	matrixType,
	samplerType,
	stmtOf,
} from "../shader/ir";
import { BindingSlot, ShaderTarget, bindingSlots } from "../shader/layout";
import { printSpirv } from "../shader/printSpirv";
import {
	BOOL,
	F32,
	I32,
	IVEC2,
	MAT4,
	TEXTURE,
	VEC2,
	VEC4,
	blurModule,
	column,
	comparisonSampler,
	computeBuiltinsModule,
	constantOf,
	depthCompare,
	depthModule,
	depthTexture,
	everyModule,
	io,
	model,
	prepend,
	resource,
	ret,
	shaderFunction,
	swizzle,
	tiny,
	unaryOf,
} from "./shaderProbeModules";

class Instruction {
	opcode: int32 = 0;
	operands: uint32[] = [];
}

function slotsOf(m: ShaderModule, entries: int32[]): BindingSlot[] {
	const slots = bindingSlots(m, entries, ShaderTarget.Wgsl);
	if (!slots.ok) { return [] }
	return slots.value;
}

function wordsOf(m: ShaderModule, index: int32, slots: BindingSlot[]): uint32[] {
	const printed = printSpirv(m, index, slots);
	if (printed.ok) { return printed.value; }
	return [];
}

function refusalOf(m: ShaderModule, index: int32, slots: BindingSlot[]): string {
	const printed = printSpirv(m, index, slots);
	if (printed.ok) { return "printed"; }
	return printed.error;
}

function refused(m: ShaderModule): string { return refusalOf(m, 0, slotsOf(m, [0])); }

function instructions(words: uint32[]): Instruction[] {
	let out: Instruction[] = [];
	let at = 5;
	while (at < words.length) {
		const head = words[at];
		const count = (head >> 16) as int32;
		let i = new Instruction();
		i.opcode = (head & 65535) as int32;
		i.operands = words.slice(at + 1, at + count);
		out.push(i);
		at += count < 1 ? words.length : count;
	}
	return out;
}

function encoded(text: string): uint32[] {
	let out: uint32[] = [];
	let word: uint32 = 0;
	let shift: uint32 = 1;
	for (let i = 0; i < text.length; i++) {
		word += (text.charCodeAt(i) as uint32) * shift;
		if (shift == 16777216) {
			out.push(word);
			word = 0;
			shift = 1;
		} else {
			shift *= 256;
		}
	}
	out.push(word);
	return out;
}

function sameWords(a: uint32[], b: uint32[]): boolean {
	if (a.length != b.length) { return false; }
	for (let i = 0; i < a.length; i++) {
		if (a[i] != b[i]) { return false; }
	}
	return true;
}

function named(list: Instruction[], text: string): uint32 {
	const wanted = encoded(text);
	for (const i of list) {
		if (i.opcode == 5 && sameWords(i.operands.slice(1), wanted)) { return i.operands[0]; }
	}
	return 0;
}

function joined(words: uint32[]): string {
	return words.map((w) => String(w)).join(":");
}

function decorationsOf(list: Instruction[], id: uint32): string {
	let out: string[] = [];
	for (const i of list) {
		if (i.opcode == 71 && i.operands[0] == id) { out.push(joined(i.operands.slice(1))); }
	}
	return out.join(",");
}

function memberDecorationsOf(list: Instruction[], id: uint32): string {
	let out: string[] = [];
	for (const i of list) {
		if (i.opcode == 72 && i.operands[0] == id) { out.push(joined(i.operands.slice(1))); }
	}
	return out.join(",");
}

function operandsOf(list: Instruction[], opcode: int32): string {
	let out: string[] = [];
	for (const i of list) {
		if (i.opcode == opcode) { out.push(joined(i.operands)); }
	}
	return out.join(",");
}

function count(list: Instruction[], opcode: int32): int32 {
	let n: int32 = 0;
	for (const i of list) {
		if (i.opcode == opcode) { n++; }
	}
	return n;
}

class EntryPoint {
	model: int32 = -1;
	interfaces: int32 = 0;
}

function entryPointOf(list: Instruction[]): EntryPoint {
	let out = new EntryPoint();
	const name = encoded("main");
	for (const i of list) {
		if (i.opcode != 15) { continue; }
		out.model = i.operands[0] as int32;
		if (sameWords(i.operands.slice(2, 2 + name.length), name)) {
			out.interfaces = (i.operands.length - 2 - name.length) as int32;
		}
	}
	return out;
}

function headerHolds(words: uint32[]): boolean {
	return words.length > 5 && words[0] == 0x07230203 && words[1] == 0x00010300 &&
		words[2] == 0 && words[3] > words[4] && words[4] == 0;
}

test "a fragment entry prints its header, entry point and uniform block layout" {
	const m = tiny(ShaderStage.Fragment, column(model()));
	const words = wordsOf(m, 0, slotsOf(m, [0]));
	assert headerHolds(words);
	const list = instructions(words);
	const point = entryPointOf(list);
	assert point.model == 4 && point.interfaces == 1;
	assert operandsOf(list, 16).endsWith(":7");
	assert operandsOf(list, 17) == "1";
	assert operandsOf(list, 14) == "0:1";
	const params = named(list, "Params");
	assert decorationsOf(list, params) == "2";
	assert memberDecorationsOf(list, params) == "0:35:0,0:5,0:7:16";
	assert decorationsOf(list, named(list, "params")) == "34:0,33:0";
	assert decorationsOf(list, named(list, "result")) == "30:0";
	assert count(list, 65) == 1 && count(list, 62) == 1;
}

test "blur prints the bindings and interface of the committed program" {
	const m = blurModule();
	const slots = slotsOf(m, [0, 1]);
	const vsList = instructions(wordsOf(m, 0, slots));
	const fsList = instructions(wordsOf(m, 1, slots));
	assert entryPointOf(vsList).model == 0 && entryPointOf(vsList).interfaces == 4;
	assert entryPointOf(fsList).model == 4 && entryPointOf(fsList).interfaces == 2;
	assert decorationsOf(vsList, named(vsList, "pos")) == "30:0";
	assert decorationsOf(vsList, named(vsList, "uv0")) == "30:1";
	assert decorationsOf(vsList, named(vsList, "clip")) == "11:0";
	assert decorationsOf(vsList, named(vsList, "uv")) == "30:0";
	assert decorationsOf(fsList, named(fsList, "uv")) == "30:0";
	assert decorationsOf(fsList, named(fsList, "fragColor")) == "30:0";
	assert decorationsOf(fsList, named(fsList, "srcTex")) == "34:1,33:0";
	assert decorationsOf(fsList, named(fsList, "srcSmp")) == "34:1,33:32";
	assert decorationsOf(fsList, named(fsList, "blur_params")) == "34:0,33:0";
	assert count(fsList, 86) == 1 && count(fsList, 87) == 1 && count(vsList, 86) == 0;
	assert named(vsList, "srcTex") == 0;
}

test "compute prints storage resources, builtins and its workgroup size" {
	const m = computeBuiltinsModule();
	assert irErrors(m).length == 0;
	const words = wordsOf(m, 0, slotsOf(m, [0]));
	assert headerHolds(words);
	const list = instructions(words);
	assert entryPointOf(list).model == 5 && entryPointOf(list).interfaces == 5;
	assert operandsOf(list, 16).endsWith(":17:32:1:1");
	assert decorationsOf(list, named(list, "id")) == "11:28";
	assert decorationsOf(list, named(list, "local")) == "11:27";
	assert decorationsOf(list, named(list, "index")) == "11:29";
	assert decorationsOf(list, named(list, "group")) == "11:26";
	assert decorationsOf(list, named(list, "groups")) == "11:24";
	assert decorationsOf(list, named(list, "commands")) == "34:1,33:0,24";
	assert decorationsOf(list, named(list, "results")) == "34:1,33:1";
	assert decorationsOf(list, named(list, "image")) == "34:1,33:2,25";
	assert decorationsOf(list, named(list, "lut")) == "34:1,33:3";
	assert named(list, "lutSmp") == 0;
	assert memberDecorationsOf(list, named(list, "Command")) == "0:35:0";
	assert memberDecorationsOf(list, named(list, "Total")) == "0:35:0";
	let strides: string[] = [];
	for (const i of list) {
		if (i.opcode == 71 && i.operands[1] == 6) { strides.push(String(i.operands[2])); }
	}
	assert strides.length == 2 && strides.includes("4") && strides.includes("16");
	assert count(list, 95) == 2 && count(list, 99) == 1;
}

test "depth comparison picks implicit or explicit level by stage" {
	const m = depthModule();
	assert irErrors(m).length == 0;
	const slots = slotsOf(m, [0, 1]);
	const vsList = instructions(wordsOf(m, 0, slots));
	const fsList = instructions(wordsOf(m, 1, slots));
	assert count(fsList, 89) == 3 && count(fsList, 90) == 3 && count(fsList, 95) == 2;
	assert count(vsList, 89) == 0 && count(vsList, 90) == 1;
	assert count(fsList, 103) == 1 && count(vsList, 103) == 1;
	assert operandsOf(fsList, 17).split(",").includes("50");
	assert operandsOf(vsList, 17).split(",").includes("50");
	assert count(fsList, 252) == 1;
	assert decorationsOf(fsList, named(fsList, "shadowSmp")) == "34:1,33:32";
}

test "every intrinsic and statement prints" {
	const m = everyModule();
	assert irErrors(m).length == 0;
	const slots = slotsOf(m, [0, 1]);
	assert refusalOf(m, 0, slots) == "printed";
	assert refusalOf(m, 1, slots) == "printed";
	const fsList = instructions(wordsOf(m, 1, slots));
	assert decorationsOf(fsList, named(fsList, "uv")) == "30:0,17";
	assert decorationsOf(fsList, named(fsList, "tint")) == "30:1,13,16";
	assert decorationsOf(fsList, named(fsList, "id")) == "30:2,14";
	assert operandsOf(fsList, 17).split(",").includes("35");
	assert count(fsList, 246) > 0 && count(fsList, 251) > 0 && count(fsList, 252) > 0;
}

function helperCall(): ShaderExpr { return exprOf(ExprKind.Call, VEC4, 1, []); }

function withHelper(m: ShaderModule): ShaderModule {
	let helper = shaderFunction("helper", [], [stmtOf(StmtKind.Return, literal(VEC4, 1.0), [])]);
	helper.result = VEC4;
	m.functions.push(helper);
	return m;
}

function calledConditional(type: ShaderType, called: ShaderExpr, other: ShaderExpr): ShaderExpr {
	return exprOf(ExprKind.Conditional, type, -1, [literal(BOOL, 1.0), called, other]);
}

test "a conditional that calls a function in an arm becomes a branch and a phi" {
	const called = calledConditional(VEC4, helperCall(), literal(VEC4, 0.0));
	const m = withHelper(tiny(ShaderStage.Fragment, binaryOf(BinaryOp.Mul, VEC4, called,
		literal(VEC4, 2.0))));
	const list = instructions(wordsOf(m, 0, slotsOf(m, [0])));
	assert count(list, 245) == 1 && count(list, 57) == 1 && count(list, 247) == 1;
	assert refused(withHelper(tiny(ShaderStage.Fragment, binaryOf(BinaryOp.Add, VEC4,
		helperCall(), calledConditional(VEC4, helperCall(), literal(VEC4, 0.0)))))) == "printed";
	const positive = binaryOf(BinaryOp.Greater, BOOL, swizzle(helperCall(), F32, [0]),
		literal(F32, 0.0));
	const guarded = binaryOf(BinaryOp.LogicalAnd, BOOL, literal(BOOL, 1.0), positive);
	const chosen = withHelper(tiny(ShaderStage.Fragment, exprOf(ExprKind.Conditional, VEC4, -1,
		[guarded, literal(VEC4, 1.0), literal(VEC4, 0.0)])));
	assert count(instructions(wordsOf(chosen, 0, slotsOf(chosen, [0]))), 245) == 1;
}

function compared(stage: ShaderStage, op: Intrinsic, shape: TextureShape,
	comparison: boolean): ShaderModule {
	let m = tiny(stage, exprOf(ExprKind.Construct, VEC4, -1,
		[depthCompare(op, 1, 2, shape, literal(VEC2, 0.5))]));
	m.resources.push(depthTexture("shadowMap", 0, shape));
	m.resources.push(comparison ? comparisonSampler("shadowSmp", 0) :
		resource(ResourceKind.Sampler, "shadowSmp", 0, samplerType()));
	return m;
}

test "a module constant array with negated literals is a composite constant read at a dynamic index" {
	let m = tiny(ShaderStage.Fragment, new ShaderExpr());
	const corner = (x: float64, y: float64): ShaderExpr => exprOf(ExprKind.Construct, VEC2, -1, [
		unaryOf(UnaryOp.Negate, literal(F32, x)), literal(F32, y)]);
	const corners = exprOf(ExprKind.Construct, arrayType(VEC2, 2), -1,
		[corner(0.5, 1.0), corner(2.0, 0.0)]);
	m.constants = [constantOf("CORNERS", corners)];
	const at = binaryOf(BinaryOp.Add, I32, literal(I32, 1.0), literal(I32, 0.0));
	const read = exprOf(ExprKind.Index, VEC2, -1,
		[exprOf(ExprKind.Constant, corners.type, 0, []), at]);
	m.functions[0].body = [assignOf(exprOf(ExprKind.Io, VEC4, 0, []),
		exprOf(ExprKind.Construct, VEC4, -1, [read, read])), ret()];
	assert irErrors(m).length == 0;
	assert refused(m) == "printed";
	const list = instructions(wordsOf(m, 0, slotsOf(m, [0])));
	assert count(list, 44) == 3;
	assert count(list, 65) == 2 && count(list, 62) == 3;
}

test "what SPIR-V cannot print yet is refused by name" {
	const fragment = ShaderStage.Fragment;
	assert refused(tiny(fragment, column(model()))) == "printed";
	assert refused(tiny(fragment, column(intrinsicOf(Intrinsic.Inverse, matrixType(4, 3),
		[model()])))) == "printSpirv: inverse of a Matrix that is no square matrix";
	assert refused(tiny(ShaderStage.Vertex, intrinsicOf(Intrinsic.Dpdx, VEC4,
		[literal(VEC4, 1.0)]))) == "printSpirv: entry 'tinyEntry': Dpdx outside a fragment entry";
	assert refused(tiny(fragment, column(literal(MAT4, 1.0)))) ==
		"printSpirv: a literal of a Matrix";
	assert refused(tiny(fragment, literal(VEC4, 1.0 / 0.0))) ==
		"printSpirv: function 'tinyEntry': a literal that is not finite";
	assert refusalOf(tiny(fragment, column(model())), 0, []) ==
		"printSpirv: resource 'params' has no binding slot";
	assert refusalOf(tiny(fragment, column(model())), 1, []) == "printSpirv: entry 1 is out of range";
	assert refused(tiny(fragment, exprOf(ExprKind.Construct, VEC4, -1, [exprOf(ExprKind.Convert,
		F32, -1, [intrinsicOf(Intrinsic.Dot, I32, [literal(IVEC2, 1.0), literal(IVEC2, 2.0)])])]))) ==
		"printSpirv: Dot of integer vectors is not printed yet";

	let unlevelled = tiny(fragment, intrinsicOf(Intrinsic.TextureLoad, VEC4, [
		exprOf(ExprKind.Resource, TEXTURE, 1, []),
		exprOf(ExprKind.Resource, samplerType(), 2, []),
		literal(IVEC2, 0.0),
	]));
	unlevelled.resources.push(resource(ResourceKind.Texture, "lut", 0, TEXTURE));
	unlevelled.resources.push(resource(ResourceKind.Sampler, "lutSmp", 0, samplerType()));
	assert refused(unlevelled) == "printSpirv: TextureLoad of a sampled texture takes a level";

	let signed = tiny(ShaderStage.Vertex, literal(VEC4, 0.0));
	signed.ios.push(io("vertexIndex", ShaderStage.Vertex, IoDirection.In, I32,
		Builtin.VertexIndex));
	assert refused(signed) == "printSpirv: io 'vertexIndex' is i32; BuiltIn VertexIndex is u32";

	let constant = tiny(fragment, literal(VEC4, 0.0));
	prepend(constant.functions[0], assignOf(column(model()), literal(VEC4, 1.0)));
	assert refused(constant) == "printSpirv: a write to uniform block 'params'";

	let input = tiny(fragment, literal(VEC4, 0.0));
	input.ios.push(io("coord", fragment, IoDirection.In, VEC4, Builtin.Position));
	prepend(input.functions[0], assignOf(exprOf(ExprKind.Io, VEC4, 1, []), literal(VEC4, 1.0)));
	assert refused(input) == "printSpirv: a write to input io 'coord'";

	let bumped = tiny(fragment, literal(VEC4, 0.0));
	let bump = assignOf(swizzle(exprOf(ExprKind.Io, VEC4, 0, []), VEC2, [0, 1]),
		literal(VEC2, 1.0));
	bump.assign = AssignOp.Increment;
	prepend(bumped.functions[0], bump);
	assert refused(bumped) == "printSpirv: an increment of a swizzle";
}

test "depth comparison is refused by name where it cannot print" {
	const COMPARE = Intrinsic.TextureSampleCompare;
	const LEVEL = Intrinsic.TextureSampleCompareLevel;
	const D2 = TextureShape.Depth2d;
	assert refused(compared(ShaderStage.Vertex, LEVEL, D2, true)) == "printed";
	assert refused(compared(ShaderStage.Fragment, COMPARE, D2, true)) == "printed";
	assert refused(compared(ShaderStage.Vertex, COMPARE, D2, true)) ==
		"printSpirv: entry 'tinyEntry': TextureSampleCompare outside a fragment entry";
	assert refused(compared(ShaderStage.Fragment, LEVEL, D2, false)) ==
		"printSpirv: TextureSampleCompareLevel through a sampler that is no comparison sampler binding";
	assert refused(compared(ShaderStage.Fragment, COMPARE, TextureShape.D2, true)) ==
		"printSpirv: TextureSampleCompare of a D2 texture, which holds no depth";
}
