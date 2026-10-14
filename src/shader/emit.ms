// glsl(fn) reads a vertex or fragment entry function and returns it as Vulkan-style GLSL 450 for
// sokol-shdc: the signature becomes the stage's interface, the body becomes main().
// The node walk sits in functions nested in the macro body: only there are Node fields readable.

import {
	Node,
	NodeKind,
	TypeKind,
	bindSym,
	floatValue,
	getImpl,
	getType,
	getTypeImpl,
	intValue,
	sameType,
	typeKind,
} from "std/meta";
import {
	Sampler,
	Texture2d,
	Vec2f,
	Vec2i,
	Vec4f,
	textureLoad,
} from "./std";

export macro glsl(entry: Node): Node {
	function fail(n: Node, msg: string): never {
		error("glsl: " + msg, n);
	}

	const stdSymbol = bindSym("textureLoad");
	if (stdSymbol == null || stdSymbol.resolvedSym == null) {
		fail(entry, "./std did not resolve");
	}
	const stdModule = stdSymbol.resolvedSym.modulePath;
	const textureType = getTypeImpl(Texture2d);
	const samplerType = getTypeImpl(Sampler);
	const vectorTypes = [
		getTypeImpl(Vec2f),
		getTypeImpl(Vec4f),
		getTypeImpl(Vec2i),
	];
	const vectorNames = ["vec2", "vec4", "ivec2"];

	function glslType(t: Node | null, at: Node): string {
		if (t == null) { fail(at, "the expression has no type"); }
		const kind = typeKind(t);
		if (kind == TypeKind.Float32) { return "float"; }
		if (kind == TypeKind.Int32) { return "int"; }
		if (kind == TypeKind.Uint32) { return "uint"; }
		if (kind == TypeKind.Boolean) { return "bool"; }
		for (let i = 0; i < vectorTypes.length; i++) {
			if (sameType(t, vectorTypes[i])) { return vectorNames[i]; }
		}
		fail(at, "a shader value is float32, int32, uint32, boolean or a vector of ./std");
	}

	function decorator(decorators: Node[], name: string): Node | null {
		for (const d of decorators) {
			if (d.macroName == name) { return d; }
		}
		return null;
	}

	function argument(d: Node, at: Node): Node {
		if (d.macroArgs.length != 1) { fail(at, "@" + d.macroName + " takes one argument"); }
		return d.macroArgs[0];
	}

	function argumentName(d: Node, at: Node): string {
		const a = argument(d, at);
		if (a.kind != NodeKind.Identifier) { fail(at, "@" + d.macroName + " takes a name"); }
		return a.name;
	}

	function argumentNumber(d: Node, at: Node): string {
		const a = argument(d, at);
		if (a.kind != NodeKind.NumberLiteral) { fail(at, "@" + d.macroName + " takes a number"); }
		return String(intValue(a));
	}

	function fieldsOf(t: Node | null): Node | null {
		if (t == null) { return null; }
		const fields = getTypeImpl(t);
		return fields != null && fields.kind == NodeKind.TypeObject ? fields : null;
	}

	function hasDecorator(fields: Node, name: string): boolean {
		for (const decorators of fields.typExprFieldDecorators) {
			if (decorator(decorators, name) != null) { return true; }
		}
		return false;
	}

	const fn = getImpl(entry);
	const signature = getType(entry);
	if (fn == null || fn.kind != NodeKind.FunctionDecl || signature == null ||
		signature.kind != NodeKind.TypeFunction) {
		fail(entry, "the entry must be a function");
	}

	const outputType = signature.typExprReturn;
	let vectorOutput = false;
	for (const v of vectorTypes) {
		if (outputType != null && sameType(outputType, v)) { vectorOutput = true; }
	}
	const outputs = vectorOutput ? null : fieldsOf(outputType);
	const vertex = outputs != null && hasDecorator(outputs, "builtin");

	let inputType: Node | null = null;
	let bindingsType: Node | null = null;
	let keyType: Node | null = null;
	for (let i = 0; i < signature.typExprParams.length; i++) {
		const name = signature.typExprParamNames[i];
		const t = signature.typExprParams[i];
		const fields = fieldsOf(t);
		if (fields == null) {
			fail(entry, "parameter '" + name + "' is not the input, bindings or program key struct");
		}
		if (hasDecorator(fields, "binding")) {
			if (bindingsType != null) { fail(entry, "two bindings structs: '" + name + "'"); }
			bindingsType = t;
		} else if (hasDecorator(fields, "feature")) {
			if (keyType != null) { fail(entry, "two program key structs: '" + name + "'"); }
			keyType = t;
		} else {
			if (inputType != null) { fail(entry, "two stage input structs: '" + name + "'"); }
			inputType = t;
		}
	}

	function isType(n: Node, t: Node | null): boolean {
		if (t == null) { return false; }
		const own = getType(n);
		return own != null && sameType(own, t);
	}

	// Declarations come out in interface order, each inside the #ifdef of every program key
	// feature all its reads sit under, and left out when nothing reads it: a declared but unread
	// uniform or texture is still one the draw must bind.
	let declNames: string[] = [];
	let declTexts: string[] = [];
	let declGates: string[][] = [];
	let declUsed: boolean[] = [];
	let declAlways: boolean[] = [];
	let features: string[] = [];

	let globals: string[] = [];
	function claim(name: string, at: Node): void {
		if (globals.indexOf(name) >= 0) { fail(at, "'" + name + "' names two things in one stage"); }
		globals.push(name);
	}

	function declare(name: string, text: string, always: boolean): void {
		claim(name, entry);
		declNames.push(name);
		declTexts.push(text);
		declGates.push([]);
		declUsed.push(false);
		declAlways.push(always);
	}

	function use(name: string): void {
		const i = declNames.indexOf(name);
		if (i < 0) { return; }
		if (!declUsed[i]) {
			declUsed[i] = true;
			declGates[i] = features.slice(0);
			return;
		}
		let common: string[] = [];
		for (const g of declGates[i]) {
			if (features.indexOf(g) >= 0) { common.push(g); }
		}
		declGates[i] = common;
	}

	function member(t: Node, name: string, at: Node): string {
		if (t.kind == NodeKind.TypeArray && t.typExprSize > 0) {
			return glslType(t.typExprElement, at) + " " + name + "[" + String(t.typExprSize) + "]";
		}
		return glslType(t, at) + " " + name;
	}

	const bindings = fieldsOf(bindingsType);
	if (bindings != null) {
		for (let f = 0; f < bindings.typExprFieldNames.length; f++) {
			const name = bindings.typExprFieldNames[f];
			const t = bindings.typExprFieldTypes[f];
			const decorators = bindings.typExprFieldDecorators[f];
			const binding = decorator(decorators, "binding");
			if (binding == null) { fail(entry, "binding '" + name + "' has no @binding(n)"); }
			const slot = "layout(binding=" + argumentNumber(binding, entry) + ") uniform ";
			const sampleType = decorator(decorators, "sampleType");
			const samplerKind = decorator(decorators, "samplerType");
			if (sameType(t, textureType)) {
				const tag = sampleType == null ? "" : "@image_sample_type " + name + " " +
					argumentName(sampleType, entry) + "\n";
				declare(name, tag + slot + "texture2D " + name + ";\n", false);
			} else if (sameType(t, samplerType)) {
				const tag = samplerKind == null ? "" : "@sampler_type " + name + " " +
					argumentName(samplerKind, entry) + "\n";
				declare(name, tag + slot + "sampler " + name + ";\n", false);
			} else {
				const block = fieldsOf(t);
				if (block == null) {
					fail(entry, "binding '" + name + "' is not a texture, a sampler or a uniform struct");
				}
				let text = slot + name + " {\n";
				for (let m = 0; m < block.typExprFieldNames.length; m++) {
					const memberName = block.typExprFieldNames[m];
					claim(memberName, entry);
					const blockMember = member(block.typExprFieldTypes[m], memberName, entry);
					text += "    " + blockMember + ";\n";
				}
				declare(name, text + "};\n", false);
			}
		}
	}

	const inputs = fieldsOf(inputType);
	let builtinInputs: string[] = [];
	let builtinInputNames: string[] = [];
	if (inputs != null) {
		for (let f = 0; f < inputs.typExprFieldNames.length; f++) {
			const name = inputs.typExprFieldNames[f];
			const builtin = decorator(inputs.typExprFieldDecorators[f], "builtin");
			if (builtin == null) {
				// Every input is declared, read or not: shdc numbers them in declaration order.
				declare(name, "in " + member(inputs.typExprFieldTypes[f], name, entry) + ";\n", true);
				continue;
			}
			const which = argumentName(builtin, entry);
			const glslName = vertex ? "" : which == "position" ? "gl_FragCoord" :
				which == "frontFacing" ? "gl_FrontFacing" : "";
			if (glslName == "") {
				fail(entry, "input field '" + name + "': @builtin(" + which + ") has no GLSL form yet");
			}
			builtinInputs.push(glslName);
			builtinInputNames.push(name);
		}
	}

	let outputNames: string[] = [];
	let outputTargets: string[] = [];
	let outputFeatures: string[] = [];
	if (outputs == null) {
		const colour = glslType(outputType, entry);
		declare("fragColor", "layout(location=0) out " + colour + " fragColor;\n", true);
	} else {
		for (let f = 0; f < outputs.typExprFieldNames.length; f++) {
			const name = outputs.typExprFieldNames[f];
			const decorators = outputs.typExprFieldDecorators[f];
			const feature = decorator(decorators, "feature");
			outputNames.push(name);
			outputFeatures.push(feature == null ? "" : argumentName(feature, entry));
			const builtin = decorator(decorators, "builtin");
			if (builtin != null) {
				if (!vertex || argumentName(builtin, entry) != "position") {
					fail(entry, "output field '" + name + "': only a vertex @builtin(position) yet");
				}
				outputTargets.push("gl_Position");
				continue;
			}
			outputTargets.push(name);
			const t = outputs.typExprFieldTypes[f];
			if (vertex) {
				declare(name, "out " + member(t, name, entry) + ";\n", true);
				continue;
			}
			const location = decorator(decorators, "location");
			if (location == null) {
				fail(entry, "fragment output '" + name + "' has no @location(n)");
			}
			const slot = "layout(location=" + argumentNumber(location, entry) + ") out ";
			declare(name, slot + member(t, name, entry) + ";\n", feature == null);
		}
	}

	function number(n: Node): string {
		const kind = typeKind(getType(n));
		if (kind == TypeKind.Float32 || kind == TypeKind.Float64) {
			const text = String(floatValue(n));
			return text.indexOf(".") >= 0 || text.indexOf("e") >= 0 ? text : text + ".0";
		}
		return String(intValue(n));
	}

	function featureOf(n: Node): string {
		if (n.kind != NodeKind.MemberExpr || !isType(n.object, keyType)) { return ""; }
		const keys = fieldsOf(keyType);
		const f = keys.typExprFieldNames.indexOf(n.property);
		const feature = decorator(keys.typExprFieldDecorators[f], "feature");
		if (feature == null) { fail(n, "key field '" + n.property + "' has no @feature(NAME)"); }
		return argumentName(feature, n);
	}

	function expr(n: Node): string {
		if (n.kind == NodeKind.NumberLiteral) { return number(n); }
		if (n.kind == NodeKind.Identifier) { return n.name; }
		if (n.kind == NodeKind.BinaryExpr) {
			return "(" + expr(n.left) + " " + n.operator + " " + expr(n.right) + ")";
		}
		if (n.kind == NodeKind.MemberExpr) {
			const object = n.object;
			if (isType(object, inputType)) {
				const b = builtinInputNames.indexOf(n.property);
				if (b >= 0) { return builtinInputs[b]; }
				use(n.property);
				return n.property;
			}
			if (isType(object, bindingsType)) {
				use(n.property);
				return n.property;
			}
			if (object.kind == NodeKind.MemberExpr && isType(object.object, bindingsType)) {
				use(object.property);
				return n.property;
			}
			if (isType(object, keyType)) {
				fail(n, "a program key feature is read only as an if condition");
			}
			return expr(object) + "." + n.property;
		}
		if (n.kind == NodeKind.CallExpr) {
			const callee = n.callee;
			const impl = getImpl(callee);
			if (callee.resolvedSym == null || callee.resolvedSym.modulePath != stdModule ||
				impl == null || impl.kind != NodeKind.FunctionDecl) {
				fail(n, "only functions of ./std can be called from a shader yet");
			}
			if (callee.kind == NodeKind.MemberExpr) {
				if (!impl.fnName.startsWith("get_")) {
					fail(n, "method calls have no GLSL form yet");
				}
				return expr(callee.object) + "." + impl.fnName.replace("get_", "");
			}
			let args: string[] = [];
			for (const a of n.arguments) { args.push(expr(a)); }
			const sampled = args.length >= 2 ? "sampler2D(" + args[0] + ", " + args[1] + ")" : "";
			return match (impl.fnName) {
				"vec2i" => "ivec2(" + args.join(", ") + ")",
				"textureDimensions" => "textureSize(" + sampled + ", " + args[2] + ")",
				"textureLoad" => "texelFetch(" + sampled + ", " + args[2] + ", " + args[3] + ")",
				_ => impl.fnName + "(" + args.join(", ") + ")",
			};
		}
		fail(n, "this expression has no GLSL form yet (node kind " + String(n.kind) + ")");
	}

	function output(name: string, value: Node): string {
		const o = outputNames.indexOf(name);
		const target = outputTargets[o];
		const feature = outputFeatures[o];
		if (feature != "") { features.push(feature); }
		use(target);
		const text = "    " + target + " = " + expr(value) + ";\n";
		if (feature == "") { return text; }
		features.pop();
		return "#ifdef " + feature + "\n" + text + "#endif\n";
	}

	function stmt(n: Node): string {
		if (n.kind == NodeKind.BlockStmt) {
			let out = "";
			for (const s of n.statements) { out += stmt(s); }
			return out;
		}
		if (n.kind == NodeKind.VariableDecl) {
			if (globals.indexOf(n.declName) >= 0) {
				fail(n, "local '" + n.declName + "' hides a stage interface name");
			}
			return "    " + glslType(getType(n.initializer), n) + " " + n.declName + " = " +
				expr(n.initializer) + ";\n";
		}
		if (n.kind == NodeKind.IfStmt) {
			const feature = featureOf(n.condition);
			if (feature == "") { fail(n, "an if has no GLSL form yet unless it reads a program key"); }
			features.push(feature);
			let text = "#ifdef " + feature + "\n" + stmt(n.consequent);
			features.pop();
			if (n.alternate != null) {
				features.push("!" + feature);
				const otherwise = stmt(n.alternate);
				features.pop();
				if (otherwise != "") { text += "#else\n" + otherwise; }
			}
			return text + "#endif\n";
		}
		if (n.kind == NodeKind.ReturnStmt) {
			const value = n.argument;
			if (value == null) { fail(n, "an entry returns its stage output"); }
			if (outputs == null) {
				use("fragColor");
				return "    fragColor = " + expr(value) + ";\n    return;\n";
			}
			if (value.kind != NodeKind.ObjectLiteral) {
				fail(n, "a struct stage output is returned as an object literal");
			}
			let text = "";
			for (let k = 0; k < value.keys.length; k++) {
				text += output(value.keys[k], value.properties[k]);
			}
			return text + "    return;\n";
		}
		fail(n, "this statement has no GLSL form yet (node kind " + String(n.kind) + ")");
	}

	const body = stmt(fn.fnBody);
	let header = "";
	for (let i = 0; i < declNames.length; i++) {
		if (!declUsed[i] && !declAlways[i]) { continue; }
		let text = declTexts[i];
		for (let g = declGates[i].length - 1; g >= 0; g--) {
			const gate = declGates[i][g];
			const open = gate.startsWith("!") ? "#ifndef " + gate.replace("!", "") : "#ifdef " + gate;
			text = open + "\n" + text + "#endif\n";
		}
		header += text;
	}
	const source = header + "void main() {\n" + body + "}\n";
	return { kind: NodeKind.StringLiteral, line: entry.line, column: entry.column, value: source };
}
