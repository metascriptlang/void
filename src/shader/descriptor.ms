import {
	ConditionKind,
	DeclarationKind,
	ExprKind,
	IoDirection,
	ShaderExpr,
	ShaderModule,
	ShaderStage,
	ShaderStmt,
	ShaderType,
	ShaderTypeKind,
	StmtKind,
	assignOf,
	conditionOf,
	exprOf,
	irErrors,
	sameShaderType,
	stmtOf,
} from "./ir";
import { irFromText } from "./irText";
import { ShaderTarget, bindingSlots } from "./layout";
import { GlslTarget, printGlsl } from "./printGlsl";
import { printHlsl } from "./printHlsl";
import { printMsl } from "./printMsl";
import { printSpirv } from "./printSpirv";
import { printWgsl } from "./printWgsl";
import { Reflection, reflectCompute, reflectProgram } from "./reflect";
import { specialize } from "./specialize";

struct Offsets {
	structs: int32;
	constants: int32;
	resources: int32[];
	ios: int32[];
	functions: int32;
	workgroups: int32;
}

function shiftType(o: Offsets, t: ShaderType): void {
	if (t.kind == ShaderTypeKind.Struct) { t.structIndex += o.structs; }
	for (const e of t.element) { shiftType(o, e); }
}

function shiftExpr(o: Offsets, e: ShaderExpr): void {
	shiftType(o, e.type);
	match (e.kind) {
		ExprKind.Constant => { e.index += o.constants; },
		ExprKind.Io => { e.index = o.ios[e.index]; },
		ExprKind.Resource | ExprKind.BlockMember => { e.index = o.resources[e.index]; },
		ExprKind.Call => { e.index += o.functions; },
		ExprKind.Workgroup => { e.index += o.workgroups; },
		_ => {},
	}
	for (const operand of e.operands) { shiftExpr(o, operand); }
}

function shiftStmts(o: Offsets, stmts: ShaderStmt[]): void {
	for (const s of stmts) {
		shiftExpr(o, s.target);
		shiftExpr(o, s.expr);
		for (const list of [s.init, s.update, s.body, s.otherwise]) { shiftStmts(o, list); }
		for (const k of s.cases) {
			for (const label of k.labels) { shiftExpr(o, label); }
			shiftStmts(o, k.body);
		}
	}
}

function sameResourceType(m: ShaderModule, a: ShaderType, b: ShaderType): boolean {
	if (a.kind != ShaderTypeKind.Struct || b.kind != ShaderTypeKind.Struct) {
		return sameShaderType(a, b);
	}
	const x = m.structs[a.structIndex];
	const y = m.structs[b.structIndex];
	if (x.name != y.name || x.members.length != y.members.length) { return false; }
	for (let i = 0; i < x.members.length; i++) {
		if (x.members[i].name != y.members[i].name ||
			!sameResourceType(m, x.members[i].type, y.members[i].type)) {
			return false;
		}
	}
	return true;
}

function append(into: ShaderModule, from: ShaderModule): void {
	const stage = from.entries[0].stage;
	let next = into.ios.length as int32;
	let ios: int32[] = [];
	for (const io of from.ios) {
		ios.push(io.stage == stage ? next : -1);
		if (io.stage == stage) { next++; }
	}
	let o: Offsets = {
		structs: into.structs.length as int32,
		constants: into.constants.length as int32,
		resources: [],
		ios,
		functions: into.functions.length as int32,
		workgroups: into.workgroups.length as int32,
	};
	for (const s of from.structs) {
		for (const f of s.members) { shiftType(o, f.type); }
		into.structs.push(s);
	}
	for (const c of from.constants) {
		shiftType(o, c.type);
		shiftExpr(o, c.value);
		into.constants.push(c);
	}
	for (const r of from.resources) {
		shiftType(o, r.type);
		const same = into.resources.findIndex((held) => held.name == r.name &&
			held.kind == r.kind && held.group == r.group && held.binding == r.binding &&
			sameResourceType(into, held.type, r.type));
		if (same < 0) {
			o.resources.push(into.resources.length as int32);
			into.resources.push(r);
			continue;
		}
		o.resources.push(same as int32);
		const held = into.resources[same];
		if (held.condition.kind != ConditionKind.Always) {
			held.condition = r.condition.kind == ConditionKind.Always ? r.condition :
				conditionOf(ConditionKind.Any, [held.condition, r.condition]);
		}
	}
	for (const io of from.ios) {
		if (io.stage != stage) { continue; }
		shiftType(o, io.type);
		into.ios.push(io);
	}
	for (const f of from.functions) {
		for (const p of f.params) { shiftType(o, p.type); }
		for (const l of f.locals) { shiftType(o, l.type); }
		shiftType(o, f.result);
		shiftStmts(o, f.body);
		into.functions.push(f);
	}
	for (const w of from.workgroups) {
		shiftType(o, w.type);
		into.workgroups.push(w);
	}
	for (const e of from.entries) {
		e.functionIndex += o.functions;
		into.entries.push(e);
	}
	for (const d of from.declarations) {
		d.index += match (d.kind) {
			DeclarationKind.Struct => o.structs,
			DeclarationKind.Constant => o.constants,
			DeclarationKind.Function => o.functions,
			DeclarationKind.Workgroup => o.workgroups,
		};
		into.declarations.push(d);
	}
}

function stageModule(text: string, on: string[], what: string): Result<ShaderModule, string> {
	const lowered = irFromText(text);
	if (!lowered.ok) { return Result.err(what + ": " + lowered.error); }
	const specialized = specialize(lowered.value, on);
	if (!specialized.ok) { return Result.err(what + ": " + specialized.error); }
	return Result.ok(specialized.value);
}

function returnsWritten(stmts: ShaderStmt[], output: ShaderExpr): ShaderStmt[] {
	let out: ShaderStmt[] = [];
	for (const s of stmts) {
		s.init = returnsWritten(s.init, output);
		s.update = returnsWritten(s.update, output);
		s.body = returnsWritten(s.body, output);
		s.otherwise = returnsWritten(s.otherwise, output);
		for (const k of s.cases) { k.body = returnsWritten(k.body, output); }
		if (s.kind == StmtKind.Return && s.expr.type.kind != ShaderTypeKind.Void) {
			out.push(assignOf(exprOf(ExprKind.Io, output.type, output.index, []), s.expr));
			out.push(stmtOf(StmtKind.Return, new ShaderExpr(), []));
		} else {
			out.push(s);
		}
	}
	return out;
}

// The IR lets an entry `return` its single colour; printGlsl450 writes it to the stage's output,
// the other printers print what is there, so the write is spelled out here.
function colourWritten(m: ShaderModule): void {
	for (const e of m.entries) {
		const index = m.ios.findIndex((io) => io.stage == e.stage &&
			io.direction == IoDirection.Out);
		if (index < 0) { continue; }
		const output = exprOf(ExprKind.Io, m.ios[index].type, index as int32, []);
		let f = m.functions[e.functionIndex];
		f.body = returnsWritten(f.body, output);
	}
}

function checked(m: ShaderModule, what: string): Result<ShaderModule, string> {
	colourWritten(m);
	const broken = irErrors(m);
	if (broken.length > 0) { return Result.err(what + ": " + broken[0]); }
	return Result.ok(m);
}

export function programModule(vertexText: string, fragmentText: string, on: string[]):
	Result<ShaderModule, string> {
	let m = try stageModule(vertexText, on, "the vertex stage");
	const fragment = try stageModule(fragmentText, on, "the fragment stage");
	append(m, fragment);
	if (m.entries.length != 2 || m.entries[0].stage != ShaderStage.Vertex ||
		m.entries[1].stage != ShaderStage.Fragment) {
		return Result.err("a program is one vertex and one fragment entry");
	}
	return checked(m, "the program");
}

export function computeModule(text: string, on: string[]): Result<ShaderModule, string> {
	const m = try stageModule(text, on, "the compute stage");
	if (m.entries.length != 1 || m.entries[0].stage != ShaderStage.Compute) {
		return Result.err("a compute program is one compute entry");
	}
	return checked(m, "the compute program");
}

export function targetName(target: ShaderTarget): string {
	return match (target) {
		ShaderTarget.Wgsl => "wgsl",
		ShaderTarget.Glsl300es => "glsl300es",
		ShaderTarget.Glsl430 => "glsl430",
		ShaderTarget.Hlsl5 => "hlsl5",
		ShaderTarget.Msl => "msl",
		ShaderTarget.Spirv => "spirv",
	};
}

struct TargetArm {
	language: string;
	target: ShaderTarget;
	anyOfAll: string[][];
}

export function targetArms(): TargetArm[] {
	return [
		{ language: "spirv", target: ShaderTarget.Spirv, anyOfAll: [["voidVulkan"]] },
		{ language: "wgsl", target: ShaderTarget.Wgsl, anyOfAll: [["webgpu"]] },
		{
			language: "glsl300es",
			target: ShaderTarget.Glsl300es,
			anyOfAll: [["webgl2"], ["android"], ["linux", "voidGles3"]],
		},
		{ language: "metal_ios", target: ShaderTarget.Msl, anyOfAll: [["ios"]] },
		{ language: "metal_macos", target: ShaderTarget.Msl, anyOfAll: [["macos"]] },
		{ language: "glsl430", target: ShaderTarget.Glsl430, anyOfAll: [["voidGlCore"], ["linux"]] },
		{ language: "hlsl5", target: ShaderTarget.Hlsl5, anyOfAll: [["windows"]] },
	];
}

export function armCondition(a: TargetArm): string {
	return a.anyOfAll.map((all) => all.length == 1 ? all[0] : "(" + all.join(" && ") + ")")
		.join(" || ");
}

function entryPointOf(target: ShaderTarget): string {
	return target == ShaderTarget.Msl ? "main0" : "main";
}

function programEntries(m: ShaderModule): int32[] {
	let out: int32[] = [];
	for (let i = 0; i < m.entries.length; i++) { out.push(i); }
	return out;
}

export function stageSource(m: ShaderModule, entry: int32, target: ShaderTarget):
	Result<string, string> {
	const slots = try bindingSlots(m, programEntries(m), target);
	return match (target) {
		ShaderTarget.Hlsl5 => printHlsl(m, entry, slots),
		ShaderTarget.Wgsl => printWgsl(m, entry, slots),
		ShaderTarget.Glsl430 => printGlsl(m, entry, slots, GlslTarget.Glsl430),
		ShaderTarget.Glsl300es => printGlsl(m, entry, slots, GlslTarget.Glsl300es),
		ShaderTarget.Msl => printMsl(m, entry, slots),
		ShaderTarget.Spirv => Result.err("a SPIR-V stage is words, not text; use stageWords"),
	};
}

export function stageWords(m: ShaderModule, entry: int32): Result<uint32[], string> {
	const slots = try bindingSlots(m, programEntries(m), ShaderTarget.Spirv);
	return printSpirv(m, entry, slots);
}

const BASE64_DIGITS = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";

export function wordsBase64(words: uint32[]): string {
	let bytes: int32[] = [];
	for (const w of words) {
		bytes.push((w & 255) as int32);
		bytes.push(((w >> 8) & 255) as int32);
		bytes.push(((w >> 16) & 255) as int32);
		bytes.push(((w >> 24) & 255) as int32);
	}
	let out: string[] = [];
	for (let i = 0; i < bytes.length; i += 3) {
		const left = bytes.length - i;
		const b1 = left > 1 ? bytes[i + 1] : 0;
		const b2 = left > 2 ? bytes[i + 2] : 0;
		const chunk = bytes[i] * 65536 + b1 * 256 + b2;
		out.push(BASE64_DIGITS.charAt((chunk / 262144) % 64));
		out.push(BASE64_DIGITS.charAt((chunk / 4096) % 64));
		out.push(left > 1 ? BASE64_DIGITS.charAt((chunk / 64) % 64) : "=");
		out.push(left > 2 ? BASE64_DIGITS.charAt(chunk % 64) : "=");
	}
	return out.join("");
}

export class ProgramSource {
	reflection: Reflection = {
		bindings: [],
		attributes: [],
		workgroupSize: [0, 0, 0],
		readsVertexIndex: false,
		readsInstanceIndex: false,
	};
	vertexCode: string = "";
	fragmentCode: string = "";
	computeCode: string = "";
	vertexWords: uint32[] = [];
	fragmentWords: uint32[] = [];
	computeWords: uint32[] = [];
	entryPoint: string = "main";
	refusal: string = "";
}

function spirvSource(m: ShaderModule, out: ProgramSource): Result<ProgramSource, string> {
	if (m.entries.length == 1) {
		out.reflection = try reflectCompute(m, 0, ShaderTarget.Spirv);
		const words = stageWords(m, 0);
		if (words.ok) { out.computeWords = words.value; } else { out.refusal = words.error; }
		return Result.ok(out);
	}
	out.reflection = try reflectProgram(m, 0, 1, ShaderTarget.Spirv);
	const vertex = stageWords(m, 0);
	const fragment = stageWords(m, 1);
	if (!vertex.ok) {
		out.refusal = vertex.error;
	} else if (!fragment.ok) {
		out.refusal = fragment.error;
	} else {
		out.vertexWords = vertex.value;
		out.fragmentWords = fragment.value;
	}
	return Result.ok(out);
}

export function programSource(m: ShaderModule, target: ShaderTarget):
	Result<ProgramSource, string> {
	let out = new ProgramSource();
	out.entryPoint = entryPointOf(target);
	if (target == ShaderTarget.Spirv) { return spirvSource(m, out); }
	if (m.entries.length == 1) {
		out.reflection = try reflectCompute(m, 0, target);
		const code = stageSource(m, 0, target);
		if (code.ok) { out.computeCode = code.value; } else { out.refusal = code.error; }
		return Result.ok(out);
	}
	out.reflection = try reflectProgram(m, 0, 1, target);
	const vertex = stageSource(m, 0, target);
	const fragment = stageSource(m, 1, target);
	if (!vertex.ok) {
		out.refusal = vertex.error;
	} else if (!fragment.ok) {
		out.refusal = fragment.error;
	} else {
		out.vertexCode = vertex.value;
		out.fragmentCode = fragment.value;
	}
	return Result.ok(out);
}

export function quotedSource(text: string): string {
	let out = "\"";
	for (let i = 0; i < text.length; i++) {
		out += match (text[i]) {
			"\\" => "\\\\",
			"\"" => "\\\"",
			"\n" => "\\n",
			"\t" => "\\t",
			"\r" => "",
			_ => text[i],
		};
	}
	return out + "\"";
}

function optional(name: string, value: string): string {
	return value != "" ? ", " + name + ": \"" + value + "\"" : "";
}

function bindingSource(r: Reflection): string[] {
	return r.bindings.map((b) => {
		const kind: string = b.kind;
		const sampleType: string = b.sampleType;
		const samplerType: string = b.samplerType;
		const bufferType: string = b.bufferType;
		const viewDimension: string = b.viewDimension;
		const storageAccess: string = b.storageAccess;
		const storageFormat: string = b.storageFormat;
		const name = b.nativeName;
		return "{ group: " + String(b.group) + ", binding: " + String(b.binding) + ", kind: \"" +
			kind + "\", visibility: " + String(b.visibility) + ", size: " + String(b.size) +
			optional("sampleType", sampleType) + optional("samplerType", samplerType) +
			", nativeSlot: " + String(b.nativeSlot) +
			(name !== null ? ", nativeName: " + quotedSource(name) : "") +
			", textureBinding: " + String(b.textureBinding) +
			optional("bufferType", bufferType) + optional("viewDimension", viewDimension) +
			(b.multisampled ? ", multisampled: true" : "") +
			optional("storageAccess", storageAccess) + optional("storageFormat", storageFormat) +
			" }";
	});
}

function attributeSource(r: Reflection): string[] {
	return r.attributes.map((a) => {
		const name = a.nativeName;
		return "{ location: " + String(a.location) +
			(name !== null ? ", nativeName: " + quotedSource(name) : "") + ", semanticIndex: " +
			String(a.semanticIndex) + " }";
	});
}

export function isComputeSource(s: ProgramSource): boolean {
	return s.computeCode != "" || s.computeWords.length > 0 || s.reflection.workgroupSize[0] > 0;
}

export function descriptorSource(
	name: string,
	s: ProgramSource,
	code: string[],
	bytecode: string[],
): string {
	const refused = s.refusal != "" ? "\t// " + s.refusal + "\n" : "";
	const stages = isComputeSource(s) ?
		"\t\t\tcomputeCode: " + code[0] + ",\n" +
		"\t\t\tcomputeEntryPoint: " + quotedSource(s.entryPoint) + ",\n" +
		"\t\t\tcomputeBytecode: " + bytecode[0] + ",\n" +
		"\t\t\tworkgroupSize: [" + s.reflection.workgroupSize.map((n) => String(n)).join(", ") +
		"],\n" :
		"\t\t\tvertexCode: " + code[0] + ",\n" +
		"\t\t\tvertexEntryPoint: " + quotedSource(s.entryPoint) + ",\n" +
		"\t\t\tvertexBytecode: " + bytecode[0] + ",\n" +
		"\t\t\tfragmentCode: " + code[1] + ",\n" +
		"\t\t\tfragmentEntryPoint: " + quotedSource(s.entryPoint) + ",\n" +
		"\t\t\tfragmentBytecode: " + bytecode[1] + ",\n" +
		(s.reflection.readsVertexIndex ? "\t\t\treadsVertexIndex: true,\n" : "") +
		(s.reflection.readsInstanceIndex ? "\t\t\treadsInstanceIndex: true,\n" : "");
	return refused + "\texport function " + name + "ShaderModule(): GPUShaderModuleDescriptor {\n" +
		"\t\treturn {\n" +
		"\t\t\tlabel: " + quotedSource(name) + ",\n" +
		stages +
		"\t\t\tbindings: [\n\t\t\t\t" + bindingSource(s.reflection).join(",\n\t\t\t\t") +
		",\n\t\t\t],\n" +
		"\t\t\tattributes: [\n\t\t\t\t" + attributeSource(s.reflection).join(",\n\t\t\t\t") +
		",\n\t\t\t],\n" +
		"\t\t};\n\t}\n";
}
