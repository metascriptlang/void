// A program's GPUShaderModuleDescriptor from the IR: each stage's lowered module (irText) is
// specialized for the program key, the stages are joined into one module, and per target the
// reflection comes from reflect.ms and the source from that target's printer.

import {
	DeclarationKind,
	ExprKind,
	ShaderExpr,
	ShaderModule,
	ShaderStage,
	ShaderStmt,
	ShaderType,
	ShaderTypeKind,
	irErrors,
} from "./ir";
import { irFromText } from "./irText";
import { ShaderTarget, bindingSlots } from "./layout";
import { printHlsl } from "./printHlsl";
import { printWgsl } from "./printWgsl";
import { Reflection, reflectCompute, reflectProgram } from "./reflect";
import { specialize } from "./specialize";

class Offsets {
	structs: int32 = 0;
	constants: int32 = 0;
	resources: int32 = 0;
	ios: int32[] = [];
	functions: int32 = 0;
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
		ExprKind.Resource | ExprKind.BlockMember => { e.index += o.resources; },
		ExprKind.Call => { e.index += o.functions; },
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

// Appends `from` to `into`, moving every index of `from` past what `into` already holds; `from`
// is consumed. Only the ios of `from`'s own stage come along: a linked fragment also holds its
// vertex entry's inputs, which glslLinked reads to name the varyings apart from them.
function append(into: ShaderModule, from: ShaderModule): void {
	const stage = from.entries[0].stage;
	let o = new Offsets();
	o.structs = into.structs.length as int32;
	o.constants = into.constants.length as int32;
	o.resources = into.resources.length as int32;
	let next = into.ios.length as int32;
	for (const io of from.ios) {
		o.ios.push(io.stage == stage ? next : -1);
		if (io.stage == stage) { next++; }
	}
	o.functions = into.functions.length as int32;
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
		into.resources.push(r);
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
	for (const e of from.entries) {
		e.functionIndex += o.functions;
		into.entries.push(e);
	}
	for (const d of from.declarations) {
		d.index += match (d.kind) {
			DeclarationKind.Struct => o.structs,
			DeclarationKind.Constant => o.constants,
			DeclarationKind.Function => o.functions,
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

function checked(m: ShaderModule, what: string): Result<ShaderModule, string> {
	const broken = irErrors(m);
	if (broken.length > 0) { return Result.err(what + ": " + broken[0]); }
	return Result.ok(m);
}

// One module holding the program's vertex entry (0) and fragment entry (1) for the features `on`.
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
	};
}

export function entryPointOf(target: ShaderTarget): string {
	return target == ShaderTarget.Msl ? "main0" : "main";
}

function wgslOf(m: ShaderModule, entry: int32, target: ShaderTarget): Result<string, string> {
	const slots = try bindingSlots(m, [entry], target);
	try {
		return Result.ok(printWgsl(m, entry, slots));
	} catch (e) {
		return Result.err(e.message);
	}
}

// The source of one entry for one target; a target whose printer is not in the tree is refused
// by name.
export function stageSource(m: ShaderModule, entry: int32, target: ShaderTarget):
	Result<string, string> {
	return match (target) {
		ShaderTarget.Hlsl5 => {
			const slots = try bindingSlots(m, [entry], target);
			return printHlsl(m, entry, slots);
		},
		ShaderTarget.Wgsl => wgslOf(m, entry, target),
		ShaderTarget.Glsl430 | ShaderTarget.Glsl300es | ShaderTarget.Msl =>
			Result.err("no " + targetName(target) + " printer is merged yet"),
	};
}

export class ProgramSource {
	reflection: Reflection = new Reflection();
	vertexCode: string = "";
	fragmentCode: string = "";
	computeCode: string = "";
	entryPoint: string = "main";
	refusal: string = "";
}

// The reflection always; the sources when the target's printer exists, else `refusal` says why.
export function programSource(m: ShaderModule, target: ShaderTarget): Result<ProgramSource, string> {
	let out = new ProgramSource();
	out.entryPoint = entryPointOf(target);
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
		const c = text[i];
		if (c == "\\") {
			out += "\\\\";
		} else if (c == "\"") {
			out += "\\\"";
		} else if (c == "\n") {
			out += "\\n";
		} else if (c == "\t") {
			out += "\\t";
		} else if (c != "\r") {
			out += c;
		}
	}
	return out + "\"";
}

function optional(name: string, value: string): string {
	return value != "" ? ", " + name + ": \"" + value + "\"" : "";
}

// The binding and attribute lines as tools/shaderTables.ms writes them from shdc's reflection,
// so the two generators' modules diff line by line; members shdc never reflects follow.
export function bindingSource(r: Reflection): string[] {
	return r.bindings.map((b) => {
		const kind: string = b.kind;
		const stage: string = b.stage;
		const sampleType: string = b.sampleType;
		const samplerType: string = b.samplerType;
		const bufferType: string = b.bufferType;
		const viewDimension: string = b.viewDimension;
		const storageAccess: string = b.storageAccess;
		const storageFormat: string = b.storageFormat;
		const name = b.nativeName;
		return "{ group: " + String(b.group) + ", binding: " + String(b.binding) + ", kind: \"" +
			kind + "\", stage: \"" + stage + "\", size: " + String(b.size) +
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

export function attributeSource(r: Reflection): string[] {
	return r.attributes.map((a) => {
		const name = a.nativeName;
		return "{ location: " + String(a.location) +
			(name !== null ? ", nativeName: " + quotedSource(name) : "") + ", semanticIndex: " +
			String(a.semanticIndex) + " }";
	});
}

// One `export function <name>ShaderModule()` as tools/shaderTables.ms writes it.
export function descriptorSource(name: string, s: ProgramSource): string {
	const refused = s.refusal != "" ? "\t// " + s.refusal + "\n" : "";
	const stages = s.computeCode != "" || s.reflection.workgroupSize[0] > 0 ?
		"\t\t\tcomputeCode: " + quotedSource(s.computeCode) + ",\n" +
		"\t\t\tcomputeEntryPoint: " + quotedSource(s.entryPoint) + ",\n" +
		"\t\t\tworkgroupSize: [" + s.reflection.workgroupSize.map((n) => String(n)).join(", ") +
		"],\n" :
		"\t\t\tvertexCode: " + quotedSource(s.vertexCode) + ",\n" +
		"\t\t\tvertexEntryPoint: " + quotedSource(s.entryPoint) + ",\n" +
		"\t\t\tfragmentCode: " + quotedSource(s.fragmentCode) + ",\n" +
		"\t\t\tfragmentEntryPoint: " + quotedSource(s.entryPoint) + ",\n";
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
