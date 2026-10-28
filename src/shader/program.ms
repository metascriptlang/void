import {
	DeclKind,
	Node,
	NodeKind,
	TypeKind,
	bindSym,
	createNodeAt,
	define,
	getType,
	getTypeImpl,
	sameType,
	stringValue,
	typeKind,
} from "std/meta";
import { glslIr, glslLinkedIr } from "./emit";
import { programModule, programSource, targetArms, wordsBase64 } from "./descriptor";
import { shaderBytecodeFromBase64 } from "./dxbc";
import { ShaderTarget } from "./layout";
import { reflectProgram } from "./reflect";
import { Vec2f, Vec2i, Vec2u, Vec3f, Vec3i, Vec3u, Vec4f, Vec4i, Vec4u } from "./std";
import { GPUShaderModuleDescriptor } from "../webgpu/types.ms";
import { DoorLayout, doorRegisterLayouts, doorRegisterPrograms } from "../gpu/doorGpu.ms";

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

export macro vertexFormats(vertex: Node, fragment: Node): Node {
	function refuseFeatures(fields: Node | null): void {
		if (fields == null || fields.kind != NodeKind.TypeObject) { return; }
		for (let f = 0; f < fields.typExprFieldNames.length; f++) {
			for (const d of fields.typExprFieldDecorators[f]) {
				if (d.macroName == "feature") {
					error("shaderProgram builds one program, so '" + fields.typExprFieldNames[f] +
						"' cannot be @feature; a program family is a row of " +
						"src/void3d/programKeys.txt", d);
				}
			}
		}
	}
	function refuseFamily(entry: Node): void {
		const signature = getType(entry);
		if (signature == null || signature.kind != NodeKind.TypeFunction) {
			error("shaderProgram: this is not a shader entry", entry);
		}
		for (const t of signature.typExprParams) { refuseFeatures(getTypeImpl(t)); }
		refuseFeatures(getTypeImpl(signature.typExprReturn));
	}
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

	refuseFamily(vertex);
	refuseFamily(fragment);
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

function splicedBuild(
	at: Node,
	base: string,
	product: string,
	build: Node | null,
	ir: Node | null,
	linked: Node | null,
	formats: Node | null,
	vertex: Node,
	fragment: Node,
): Node | null {
	if (build == null) { return null; }
	if (ir == null) { return null; }
	if (linked == null) { return null; }
	let formatsArg: Node = createNodeAt(NodeKind.StringLiteral, { value: "" }, at.location);
	if (product == "shaderProgram") {
		if (formats == null) { return null; }
		formatsArg = createNodeAt(NodeKind.CallExpr, { callee: formats, arguments: [vertex, fragment] },
			at.location);
	}
	const args: Node[] = [
		createNodeAt(NodeKind.StringLiteral, { value: base }, at.location),
		createNodeAt(NodeKind.CallExpr, { callee: ir, arguments: [vertex] }, at.location),
		createNodeAt(NodeKind.CallExpr, { callee: linked, arguments: [fragment, vertex] }, at.location),
		formatsArg,
		createNodeAt(NodeKind.StringLiteral, { value: product }, at.location),
	];
	const program = product == "shaderProgram";
	const declaration: Node = createNodeAt(NodeKind.VariableDecl, {
		declName: program ? base : base + "Module",
		declType: program ? "int32" : "",
		initializer: createNodeAt(NodeKind.CallExpr, { callee: build, arguments: args }, at.location),
		declKind: DeclKind.Const,
		nameLocation: at.location,
	}, at.location);
	return createNodeAt(NodeKind.SpliceMany, { spliceNodes: [declaration] }, at.location);
}

export macro shaderProgram(name: Node, vertex: Node, fragment: Node): Node {
	if (name.kind != NodeKind.Identifier) {
		error("shaderProgram: the first argument names the program it declares", name);
	}
	const spliced = splicedBuild(name, name.name, "shaderProgram", bindSym("shaderBuild"),
		bindSym("glslIr"), bindSym("glslLinkedIr"), bindSym("vertexFormats"), vertex, fragment);
	if (spliced == null) { error("shaderProgram: a macro it expands to is not in scope", name); }
	return spliced;
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
	function targetOf(): ShaderTarget {
		for (const arm of targetArms()) {
			for (const all of arm.anyOfAll) {
				let set = true;
				for (const d of all) { if (define(d) == "") { set = false; } }
				if (set) { return arm.target; }
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
	function flag(): Node {
		return { kind: NodeKind.BooleanLiteral, line: name.line, column: name.column, boolValue: true };
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

	const module = programModule(stringValue(vertex), stringValue(fragment), []);
	if (!module.ok) { refused(module.error); }
	const target = targetOf();
	const source = programSource(module.value, target);
	if (!source.ok) { refused(source.error); }
	const s = source.value;
	if (s.refusal != "") { refused(s.refusal); }
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
			values.push(flag());
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
	const descriptorKeys = [
		"label",
		"vertexCode",
		"vertexEntryPoint",
		"fragmentCode",
		"fragmentEntryPoint",
		"bindings",
		"attributes",
	];
	const descriptorValues = [
		text(base),
		text(s.vertexCode),
		text(s.entryPoint),
		text(s.fragmentCode),
		text(s.entryPoint),
		array(bindings),
		array(attributes),
	];
	if (target == ShaderTarget.Spirv) {
		descriptorKeys.push("vertexBytecode");
		descriptorValues.push(called("shaderBytecodeFromBase64",
			[text(wordsBase64(s.vertexWords))]));
		descriptorKeys.push("fragmentBytecode");
		descriptorValues.push(called("shaderBytecodeFromBase64",
			[text(wordsBase64(s.fragmentWords))]));
	}
	if (s.reflection.readsVertexIndex) {
		descriptorKeys.push("readsVertexIndex");
		descriptorValues.push(flag());
	}
	if (s.reflection.readsInstanceIndex) {
		descriptorKeys.push("readsInstanceIndex");
		descriptorValues.push(flag());
	}
	const descriptor = object(descriptorKeys, descriptorValues);
	if (kind == "shaderModule") { return called("shaderModuleOf", [descriptor]); }
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
	if (name.kind != NodeKind.Identifier) {
		error("shaderModule: the first argument names the program it declares", name);
	}
	const spliced = splicedBuild(name, name.name, "shaderModule", bindSym("shaderBuild"),
		bindSym("glslIr"), bindSym("glslLinkedIr"), null, vertex, fragment);
	if (spliced == null) { error("shaderModule: a macro it expands to is not in scope", name); }
	return spliced;
}
