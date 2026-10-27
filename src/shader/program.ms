import {
	DeclKind,
	Node,
	NodeKind,
	TypeKind,
	bindSym,
	define,
	getType,
	getTypeImpl,
	readFile,
	sameType,
	stringValue,
	typeKind,
	warning,
} from "std/meta";
import { glslComputeIr, glslIr, glslLinkedIr } from "./emit";
import {
	bytesBase64,
	computeModule,
	programModule,
	programSource,
	targetArms,
	wordsBase64,
} from "./descriptor";
import { dxbcStage, findFxc } from "./dxbcCache";
import { shaderBytecodeFromBase64 } from "./dxbc";
import { metalFlags, metallibStage } from "./metallibCache";
import { ShaderTarget } from "./layout";
import { reflectProgram } from "./reflect";
import { Vec2f, Vec2i, Vec2u, Vec3f, Vec3i, Vec3u, Vec4f, Vec4i, Vec4u } from "./std";
import { GPUShaderModuleDescriptor } from "../webgpu/types.ms";
import { DoorLayout, doorRegisterLayouts, doorRegisterPrograms } from "../gpu/doorGpu.ms";
import { registerComputePrograms } from "../gpu/doorCompute.ms";

export function shaderModuleOf(descriptor: GPUShaderModuleDescriptor): GPUShaderModuleDescriptor {
	return descriptor;
}

export function shaderProgramRegister(
	descriptor: GPUShaderModuleDescriptor,
	layout: DoorLayout,
): int32 {
	const layoutId = doorRegisterLayouts([layout]);
	return doorRegisterPrograms(
		(index: int32): GPUShaderModuleDescriptor => descriptor,
		[layoutId],
	);
}

export function shaderComputeRegister(descriptor: GPUShaderModuleDescriptor): int32 {
	return registerComputePrograms((index: int32): GPUShaderModuleDescriptor => descriptor, 1);
}

class StageBlob {
	path: string = "";
	missing: string = "";
	error: string = "";
}

function dxbcProfile(stage: string): string {
	if (stage == "vertex") { return "vs_5_0"; }
	if (stage == "fragment") { return "ps_5_0"; }
	if (stage == "compute") { return "cs_5_0"; }
	console.error("no DXBC profile for the " + stage + " stage");
	unreachable;
}

// The tracked blobs sit in shaders/ and the ones a build compiles in out/shaders/, both under the
// directory msc runs in; an empty path with an empty `missing` is a language with no bytecode.
export function stageBlob(
	language: string,
	stage: string,
	code: string,
	entry: string,
	fxc: string,
): StageBlob {
	const blob = new StageBlob();
	if (language == "hlsl5") {
		const found = dxbcStage("shaders/dxbc", "out/shaders/dxbc",
			fxc, dxbcProfile(stage), entry, code);
		blob.path = found.path;
		blob.error = found.error;
		if (found.path == "" && found.error == "") { blob.missing = "fxc"; }
	} else if (metalFlags(language).length > 0) {
		const found = metallibStage("shaders/metallib", "out/shaders/metallib", language, entry, code);
		blob.path = found.path;
		blob.error = found.error;
		blob.missing = found.missing;
	}
	return blob;
}

export macro oneProgram(product: Node, entry: Node): Node {
	const named = stringValue(product);
	function refuseFeatures(fields: Node | null): void {
		if (fields == null || fields.kind != NodeKind.TypeObject) { return; }
		for (let f = 0; f < fields.typExprFieldNames.length; f++) {
			for (const d of fields.typExprFieldDecorators[f]) {
				if (d.macroName == "feature") {
					error(named + " builds one program, so '" + fields.typExprFieldNames[f] +
						"' cannot be @feature; a program family is a row of " +
						"src/void3d/programKeys.txt", d);
				}
			}
		}
	}
	const signature = getType(entry);
	if (signature == null || signature.kind != NodeKind.TypeFunction) {
		error(named + ": this is not a shader entry", entry);
	}
	for (const t of signature.typExprParams) { refuseFeatures(getTypeImpl(t)); }
	refuseFeatures(getTypeImpl(signature.typExprReturn));
	return product;
}

export macro vertexFormats(vertex: Node, fragment: Node): Node {
	function formatOf(t: Node, at: Node): string {
		const kind = typeKind(t);
		if (kind == TypeKind.Float32) { return "float32 4"; }
		const impl = getTypeImpl(t);
		if (sameType(impl, getTypeImpl(Vec2f))) { return "float32x2 8"; }
		if (sameType(impl, getTypeImpl(Vec3f))) { return "float32x3 12"; }
		if (sameType(impl, getTypeImpl(Vec4f))) { return "float32x4 16"; }
		const integer = kind == TypeKind.Int32 || kind == TypeKind.Uint32 ||
			sameType(impl, getTypeImpl(Vec2i)) || sameType(impl, getTypeImpl(Vec3i)) ||
			sameType(impl, getTypeImpl(Vec4i)) || sameType(impl, getTypeImpl(Vec2u)) ||
			sameType(impl, getTypeImpl(Vec3u)) || sameType(impl, getTypeImpl(Vec4u));
		if (integer) {
			error("shaderProgram: an int32 or uint32 vertex attribute has no GPUVertexFormat " +
				"(src/webgpu/types.ms); take float32 or a ./std float vector", at);
		}
		error("shaderProgram: a vertex attribute is float32 or a ./std float vector of it", at);
	}

	const signature = getType(vertex);
	let text = "";
	for (const t of signature.typExprParams) {
		const fields = getTypeImpl(t);
		if (fields == null || fields.kind != NodeKind.TypeObject) { continue; }
		let bindings = false;
		for (const decorators of fields.typExprFieldDecorators) {
			for (const d of decorators) {
				if (d.macroName == "binding") { bindings = true; }
			}
		}
		if (bindings) { continue; }
		for (let f = 0; f < fields.typExprFieldNames.length; f++) {
			let builtin = false;
			for (const d of fields.typExprFieldDecorators[f]) {
				if (d.macroName == "builtin") { builtin = true; }
			}
			if (builtin) { continue; }
			text = text + fields.typExprFieldNames[f] + " " +
				formatOf(fields.typExprFieldTypes[f], vertex) + "\n";
		}
	}
	return { kind: NodeKind.StringLiteral, line: vertex.line, column: vertex.column, value: text };
}

export macro shaderProgram(name: Node, vertex: Node, fragment: Node): Node {
	function literal(text: string): Node {
		return { kind: NodeKind.StringLiteral, line: name.line, column: name.column, value: text };
	}
	function called(callee: Node | null, args: Node[]): Node {
		if (callee == null) {
			error("shaderProgram: a macro it expands to is not in scope", name);
		}
		return {
			kind: NodeKind.CallExpr,
			line: name.line,
			column: name.column,
			callee,
			arguments: args,
		};
	}
	if (name.kind != NodeKind.Identifier) {
		error("shaderProgram: the first argument names the program it declares", name);
	}
	const base = name.name;
	return {
		kind: NodeKind.SpliceMany,
		line: name.line,
		column: name.column,
		spliceNodes: [
			{
				kind: NodeKind.VariableDecl,
				line: name.line,
				column: name.column,
				declName: base,
				declType: "int32",
				initializer: called(bindSym("shaderBuild"), [
					literal(base),
					called(bindSym("glslIr"), [vertex]),
					called(bindSym("glslLinkedIr"), [fragment, vertex]),
					called(bindSym("vertexFormats"), [vertex, fragment]),
					called(bindSym("oneProgram"), [
						called(bindSym("oneProgram"), [literal("shaderProgram"), vertex]),
						fragment,
					]),
				]),
				declKind: DeclKind.Const,
				nameLocation: { line: name.line, column: name.column },
			},
		],
	};
}

export macro shaderBuild(
	name: Node,
	vertex: Node,
	fragment: Node,
	formats: Node,
	product: Node,
): Node {
	const kind = stringValue(product);
	const base = stringValue(name);
	const compute = kind == "shaderCompute" || kind == "shaderComputeModule";
	function armIndex(): int32 {
		const arms = targetArms();
		for (let i = 0; i < arms.length; i++) {
			for (const all of arms[i].anyOfAll) {
				let set = true;
				for (const d of all) { if (define(d) == "") { set = false; } }
				if (set) { return i; }
			}
		}
		error(kind + ": no shader target for this build's target", name);
	}
	function refused(message: string): never {
		error(kind + " '" + base + "': " + message, name);
	}
	function text(value: string): Node {
		return { kind: NodeKind.StringLiteral, line: name.line, column: name.column, value: value };
	}
	function integer(value: int32): Node {
		const literal: Node = {
			kind: NodeKind.NumberLiteral,
			line: name.line,
			column: name.column,
			value: value < 0 ? -value : value,
			isFloat: false,
			intVal: (value < 0 ? -value : value) as int64,
			outOfRangeText: "",
			isBitPattern: false,
		};
		if (value >= 0) { return literal; }
		return {
			kind: NodeKind.UnaryExpr,
			line: name.line,
			column: name.column,
			unaryOp: "-",
			operand: literal,
		};
	}
	function object(keys: string[], values: Node[]): Node {
		return {
			kind: NodeKind.ObjectLiteral,
			line: name.line,
			column: name.column,
			properties: values,
			keys: keys,
			keyLocations: [],
		};
	}
	function array(elements: Node[]): Node {
		return {
			kind: NodeKind.ArrayLiteral,
			line: name.line,
			column: name.column,
			elements: elements,
		};
	}
	function called(callee: string, args: Node[]): Node {
		const symbol = callee == "shaderModuleOf" ?
			bindSym("shaderModuleOf") :
			callee == "shaderBytecodeFromBase64" ?
			bindSym("shaderBytecodeFromBase64") :
			callee == "shaderComputeRegister" ?
			bindSym("shaderComputeRegister") :
			bindSym("shaderProgramRegister");
		if (symbol == null) { error(kind + ": " + callee + " is not in scope", name); }
		return {
			kind: NodeKind.CallExpr,
			line: name.line,
			column: name.column,
			callee: symbol,
			arguments: args,
		};
	}
	function optional(keys: string[], values: Node[], key: string, value: string): void {
		if (value == "") { return; }
		keys.push(key);
		values.push(text(value));
	}

	const module = compute ? computeModule(stringValue(vertex), []) :
		programModule(stringValue(vertex), stringValue(fragment), []);
	if (!module.ok) { refused(module.error); }
	const arm = targetArms()[armIndex()];
	const target = arm.target;
	const source = programSource(module.value, target);
	if (!source.ok) { refused(source.error); }
	const s = source.value;
	if (s.refusal != "") { refused(s.refusal); }
	const fxc = arm.language == "hlsl5" ? findFxc(define("fxc")) : "";
	function blobBase64(stage: string, code: string): string {
		const found = stageBlob(arm.language, stage, code, s.entryPoint, fxc);
		if (found.error != "") { refused(found.error); }
		if (found.path != "") { return bytesBase64(readFile(found.path)); }
		if (found.missing == "") { return ""; }
		const lacking = "no " + found.missing + " on this host";
		if (define("requireShaderBytecode") != "") {
			refused(stage + " has no " + arm.language + " bytecode: " + lacking);
		}
		warning(kind + " '" + base + "' " + stage + " keeps its " + arm.language + " text: " + lacking,
			name);
		return "";
	}
	function stageBase64(stage: string, code: string, words: uint32[]): string {
		return target == ShaderTarget.Spirv ? wordsBase64(words) : blobBase64(stage, code);
	}
	const vertexBase64 = compute ? "" : stageBase64("vertex", s.vertexCode, s.vertexWords);
	const fragmentBase64 = compute ? "" : stageBase64("fragment", s.fragmentCode, s.fragmentWords);
	const computeBase64 = compute ? stageBase64("compute", s.computeCode, s.computeWords) : "";
	const keepText = arm.language == "metal_ios";
	const bindings: Node[] = [];
	for (const b of s.reflection.bindings) {
		const bindingKind: string = b.kind;
		const keys = ["group", "binding", "kind", "visibility", "size"];
		const values = [
			integer(b.group),
			integer(b.binding),
			text(bindingKind),
			integer(b.visibility),
			integer(b.size),
		];
		const sampleType: string = b.sampleType;
		const samplerType: string = b.samplerType;
		optional(keys, values, "sampleType", sampleType);
		optional(keys, values, "samplerType", samplerType);
		keys.push("nativeSlot");
		values.push(integer(b.nativeSlot));
		const nativeName = b.nativeName;
		if (nativeName !== null) {
			keys.push("nativeName");
			values.push(text(nativeName));
		}
		keys.push("textureBinding");
		values.push(integer(b.textureBinding));
		const bufferType: string = b.bufferType;
		const viewDimension: string = b.viewDimension;
		const storageAccess: string = b.storageAccess;
		const storageFormat: string = b.storageFormat;
		optional(keys, values, "bufferType", bufferType);
		optional(keys, values, "viewDimension", viewDimension);
		if (b.multisampled) {
			keys.push("multisampled");
			values.push({
				kind: NodeKind.BooleanLiteral,
				line: name.line,
				column: name.column,
				boolValue: true,
			});
		}
		optional(keys, values, "storageAccess", storageAccess);
		optional(keys, values, "storageFormat", storageFormat);
		bindings.push(object(keys, values));
	}
	const attributes: Node[] = [];
	for (const a of s.reflection.attributes) {
		const keys = ["location"];
		const values = [integer(a.location)];
		const nativeName = a.nativeName;
		if (nativeName !== null) {
			keys.push("nativeName");
			values.push(text(nativeName));
		}
		keys.push("semanticIndex");
		values.push(integer(a.semanticIndex));
		attributes.push(object(keys, values));
	}
	const stageKeys = compute ?
		["computeCode", "computeEntryPoint"] :
		["vertexCode", "vertexEntryPoint", "fragmentCode", "fragmentEntryPoint"];
	const stageValues = compute ?
		[text(computeBase64 != "" && !keepText ? "" : s.computeCode), text(s.entryPoint)] :
		[
			text(vertexBase64 != "" && !keepText ? "" : s.vertexCode),
			text(s.entryPoint),
			text(fragmentBase64 != "" && !keepText ? "" : s.fragmentCode),
			text(s.entryPoint),
		];
	const descriptorKeys = ["label"].concat(stageKeys).concat(["bindings", "attributes"]);
	const descriptorValues = [text(base)].concat(stageValues)
		.concat([array(bindings), array(attributes)]);
	if (computeBase64 != "") {
		descriptorKeys.push("computeBytecode");
		descriptorValues.push(called("shaderBytecodeFromBase64", [text(computeBase64)]));
	}
	if (compute) {
		descriptorKeys.push("workgroupSize");
		descriptorValues.push(array(s.reflection.workgroupSize.map((n) => integer(n))));
	}
	if (vertexBase64 != "") {
		descriptorKeys.push("vertexBytecode");
		descriptorValues.push(called("shaderBytecodeFromBase64", [text(vertexBase64)]));
	}
	if (fragmentBase64 != "") {
		descriptorKeys.push("fragmentBytecode");
		descriptorValues.push(called("shaderBytecodeFromBase64", [text(fragmentBase64)]));
	}
	if (s.reflection.readsVertexIndex) {
		descriptorKeys.push("readsVertexIndex");
		descriptorValues.push({
			kind: NodeKind.BooleanLiteral,
			line: name.line,
			column: name.column,
			boolValue: true,
		});
	}
	if (s.reflection.readsInstanceIndex) {
		descriptorKeys.push("readsInstanceIndex");
		descriptorValues.push({
			kind: NodeKind.BooleanLiteral,
			line: name.line,
			column: name.column,
			boolValue: true,
		});
	}
	const descriptor = object(descriptorKeys, descriptorValues);
	if (kind == "shaderModule" || kind == "shaderComputeModule") {
		return called("shaderModuleOf", [descriptor]);
	}
	if (kind == "shaderCompute") { return called("shaderComputeRegister", [descriptor]); }
	const named = reflectProgram(module.value, 0, 1, ShaderTarget.Glsl430);
	if (!named.ok) { refused(named.error); }
	const vertexAttributes: Node[] = [];
	let offset = 0;
	for (const line of stringValue(formats).split("\n")) {
		if (line == "") { continue; }
		const parts = line.split(" ");
		for (const a of named.value.attributes) {
			if (a.nativeName !== parts[0]) { continue; }
			vertexAttributes.push(object(["format", "offset", "shaderLocation"],
				[text(parts[1]), integer(offset), integer(a.location)]));
		}
		offset += Number(parts[2]) as int32;
	}
	const buffer = object(["arrayStride", "stepMode", "attributes"],
		[integer(offset), text("vertex"), array(vertexAttributes)]);
	return called("shaderProgramRegister", [descriptor, object(["buffers"], [array([buffer])])]);
}

export macro shaderModule(name: Node, vertex: Node, fragment: Node): Node {
	function literal(text: string): Node {
		return { kind: NodeKind.StringLiteral, line: name.line, column: name.column, value: text };
	}
	function called(callee: Node | null, args: Node[]): Node {
		if (callee == null) {
			error("shaderModule: a macro it expands to is not in scope", name);
		}
		return {
			kind: NodeKind.CallExpr,
			line: name.line,
			column: name.column,
			callee,
			arguments: args,
		};
	}
	if (name.kind != NodeKind.Identifier) {
		error("shaderModule: the first argument names the program it declares", name);
	}
	const base = name.name;
	return {
		kind: NodeKind.SpliceMany,
		line: name.line,
		column: name.column,
		spliceNodes: [
			{
				kind: NodeKind.VariableDecl,
				line: name.line,
				column: name.column,
				declName: base + "Module",
				declType: "",
				initializer: called(bindSym("shaderBuild"), [
					literal(base),
					called(bindSym("glslIr"), [vertex]),
					called(bindSym("glslLinkedIr"), [fragment, vertex]),
					literal(""),
					literal("shaderModule"),
				]),
				declKind: DeclKind.Const,
				nameLocation: { line: name.line, column: name.column },
			},
		],
	};
}

// The workgroup size is written beside the kernel, as glslCompute takes it.
export macro shaderCompute(name: Node, kernel: Node, workgroupSize: Node): Node {
	function literal(text: string): Node {
		return { kind: NodeKind.StringLiteral, line: name.line, column: name.column, value: text };
	}
	function called(callee: Node | null, args: Node[]): Node {
		if (callee == null) {
			error("shaderCompute: a macro it expands to is not in scope", name);
		}
		return {
			kind: NodeKind.CallExpr,
			line: name.line,
			column: name.column,
			callee,
			arguments: args,
		};
	}
	if (name.kind != NodeKind.Identifier) {
		error("shaderCompute: the first argument names the program it declares", name);
	}
	const base = name.name;
	return {
		kind: NodeKind.SpliceMany,
		line: name.line,
		column: name.column,
		spliceNodes: [
			{
				kind: NodeKind.VariableDecl,
				line: name.line,
				column: name.column,
				declName: base,
				declType: "int32",
				initializer: called(bindSym("shaderBuild"), [
					literal(base),
					called(bindSym("glslComputeIr"), [kernel, workgroupSize]),
					literal(""),
					literal(""),
					called(bindSym("oneProgram"), [literal("shaderCompute"), kernel]),
				]),
				declKind: DeclKind.Const,
				nameLocation: { line: name.line, column: name.column },
			},
		],
	};
}
