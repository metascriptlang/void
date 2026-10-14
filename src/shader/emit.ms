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
	Mat3x3f,
	Mat4x4f,
	Sampler,
	Texture2d,
	Vec2f,
	Vec2i,
	Vec3f,
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
		getTypeImpl(Vec3f),
		getTypeImpl(Vec4f),
		getTypeImpl(Vec2i),
		getTypeImpl(Mat3x3f),
		getTypeImpl(Mat4x4f),
	];
	const vectorNames = ["vec2", "vec3", "vec4", "ivec2", "mat3", "mat4"];

	function glslType(t: Node | null, at: Node): string {
		if (t == null) { fail(at, "the expression has no type"); }
		const kind = typeKind(t);
		if (kind == TypeKind.Float32) { return "float"; }
		if (kind == TypeKind.Int32) { return "int"; }
		if (kind == TypeKind.Uint32) { return "uint"; }
		if (kind == TypeKind.Boolean) { return "bool"; }
		if (kind == TypeKind.SizedArray) {
			return glslType(t.typExprElement, at) + "[" + String(t.typExprSize) + "]";
		}
		for (let i = 0; i < vectorTypes.length; i++) {
			if (sameType(t, vectorTypes[i])) { return vectorNames[i]; }
		}
		fail(at, "a shader value is float32, int32, uint32, boolean, or a ./std vector or matrix");
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

	function kindOf(n: Node): TypeKind { return typeKind(getType(n)); }

	function scalar(n: Node): boolean {
		const kind = kindOf(n);
		return kind == TypeKind.Float32 || kind == TypeKind.Int32 || kind == TypeKind.Uint32 ||
			kind == TypeKind.Boolean;
	}

	function integer(n: Node): boolean {
		return kindOf(n) == TypeKind.Int32 || kindOf(n) == TypeKind.Uint32;
	}

	function condition(n: Node): string {
		if (kindOf(n) != TypeKind.Boolean) { fail(n, "a shader condition is a boolean"); }
		return value(n);
	}

	function value(n: Node): string {
		if (n.kind == NodeKind.BinaryExpr) {
			const op = n.operator == "===" ? "==" : n.operator == "!==" ? "!=" : n.operator;
			if (["&&", "||"].includes(op)) {
				if (kindOf(n.left) != TypeKind.Boolean || kindOf(n.right) != TypeKind.Boolean) {
					fail(n, "'" + op + "' takes booleans in a shader");
				}
			} else if (["<", "<=", ">", ">=", "==", "!="].includes(op)) {
				if (!scalar(n.left)) { fail(n, "'" + op + "' compares scalars in a shader"); }
			} else if (op == "%" || op == "/" && integer(n.left)) {
				fail(n, "'" + op + "' has no GLSL form: GLSL does not truncate as MetaScript does");
			} else if (op != "+" && op != "-" && op != "*" && op != "/") {
				fail(n, "operator '" + op + "' has no GLSL form yet");
			}
			return expr(n.left) + " " + op + " " + expr(n.right);
		}
		if (n.kind == NodeKind.UnaryExpr) {
			const op = n.unaryOp;
			if (op == "!" && kindOf(n.operand) == TypeKind.Boolean ||
				op == "-" && kindOf(n.operand) != TypeKind.Uint32) {
				return op + expr(n.operand);
			}
			fail(n, "unary '" + op + "' has no GLSL form yet");
		}
		if (n.kind == NodeKind.ConditionalExpr) {
			if (kindOf(n.ternaryCondition) != TypeKind.Boolean) {
				fail(n, "a shader condition is a boolean");
			}
			return expr(n.ternaryCondition) + " ? " + expr(n.ternaryConsequent) + " : " +
				expr(n.ternaryAlternate);
		}
		return expr(n);
	}

	function expr(n: Node): string {
		if (n.kind == NodeKind.NumberLiteral) { return number(n); }
		if (n.kind == NodeKind.BooleanLiteral) { return n.boolValue ? "true" : "false"; }
		if (n.kind == NodeKind.Identifier) { return n.name; }
		if (n.kind == NodeKind.BinaryExpr || n.kind == NodeKind.UnaryExpr ||
			n.kind == NodeKind.ConditionalExpr) {
			return "(" + value(n) + ")";
		}
		if (n.kind == NodeKind.ArrayAccess) { return expr(n.array) + "[" + value(n.index) + "]"; }
		if (n.kind == NodeKind.ArrayLiteral) {
			let elements: string[] = [];
			for (const e of n.elements) { elements.push(expr(e)); }
			return glslType(getType(n), n) + "(" + elements.join(", ") + ")";
		}
		if (n.kind == NodeKind.TypeAssertion) {
			const from = kindOf(n.asExpr);
			const to = kindOf(n);
			if ((from == TypeKind.Float32 || from == TypeKind.Int32) &&
				(to == TypeKind.Float32 || to == TypeKind.Int32)) {
				return glslType(getType(n), n) + "(" + value(n.asExpr) + ")";
			}
			fail(n, "'as' converts between float32 and int32 only in a shader");
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
			const listed = "(" + args.join(", ") + ")";
			const sampled = args.length >= 2 ? "sampler2D(" + args[0] + ", " + args[1] + ")" : "";
			return match (impl.fnName) {
				"max" | "min" | "clamp" | "mix" | "pow" | "dot" | "length" | "normalize" =>
					impl.fnName + listed,
				"vec2f" => "vec2" + listed,
				"vec3f" => "vec3" + listed,
				"vec4f" => "vec4" + listed,
				"vec2i" => "ivec2" + listed,
				"mat3x3f" | "upperLeft3x3" => "mat3" + listed,
				"mat4x4f" => "mat4" + listed,
				"select" => "(" + args[2] + " ? " + args[1] + " : " + args[0] + ")",
				"textureDimensions" => "textureSize(" + sampled + ", " + args[2] + ")",
				"textureLoad" => "texelFetch(" + sampled + ", " + args[2] + ", " + args[3] + ")",
				_ => fail(n, "./std's '" + impl.fnName + "' has no GLSL spelling"),
			};
		}
		fail(n, "this expression has no GLSL form yet (node kind " + String(n.kind) + ")");
	}

	function output(name: string, value: Node, indent: string): string {
		const o = outputNames.indexOf(name);
		const target = outputTargets[o];
		const feature = outputFeatures[o];
		if (feature != "") { features.push(feature); }
		use(target);
		const text = indent + target + " = " + expr(value) + ";\n";
		if (feature == "") { return text; }
		features.pop();
		return "#ifdef " + feature + "\n" + text + "#endif\n";
	}

	let locals: string[] = [];

	function assignment(n: Node): string {
		const target = n.kind == NodeKind.UpdateExpr ? n.updateArg : n.left;
		if (target.kind != NodeKind.Identifier || !locals.includes(target.name)) {
			fail(n, "a shader assigns only to its own locals");
		}
		if (n.kind == NodeKind.UpdateExpr) { return target.name + n.updateOp; }
		if (n.operator == "/=" && integer(target)) {
			fail(n, "'/=' has no GLSL form: GLSL does not truncate as MetaScript does");
		}
		if (!["=", "+=", "-=", "*=", "/="].includes(n.operator)) {
			fail(n, "operator '" + n.operator + "' has no GLSL form yet");
		}
		return target.name + " " + n.operator + " " + value(n.right);
	}

	function simple(n: Node): string {
		if (n.kind == NodeKind.ExprStmt) {
			const e = n.expr;
			if (e.kind != NodeKind.UpdateExpr && e.kind != NodeKind.BinaryExpr) {
				fail(n, "a shader statement is an assignment, not a value (node kind " +
					String(e.kind) + ")");
			}
			return assignment(e);
		}
		if (n.kind != NodeKind.VariableDecl) {
			fail(n, "this statement has no GLSL form yet (node kind " + String(n.kind) + ")");
		}
		if (n.initializer == null) { fail(n, "a shader local is declared with its value"); }
		if (globals.indexOf(n.declName) >= 0) {
			fail(n, "local '" + n.declName + "' hides a stage interface name");
		}
		const text = glslType(getType(n.initializer), n) + " " + n.declName + " = " +
			value(n.initializer);
		locals.push(n.declName);
		return text;
	}

	function body(n: Node, indent: string): string {
		const outer = locals.length;
		let out = "";
		const statements = n.kind == NodeKind.BlockStmt ? n.statements : [n];
		for (const s of statements) { out += stmt(s, indent); }
		while (locals.length > outer) { locals.pop(); }
		return out;
	}

	function branches(n: Node, indent: string): string {
		const inner = indent + "    ";
		const out = "if (" + condition(n.condition) + ") {\n" + body(n.consequent, inner) +
			indent + "}";
		const other = n.alternate;
		if (other == null || other.kind == NodeKind.BlockStmt && other.statements.length == 0) {
			return out;
		}
		if (other.kind == NodeKind.IfStmt) { return out + " else " + branches(other, indent); }
		return out + " else {\n" + body(other, inner) + indent + "}";
	}

	function stmt(n: Node, indent: string): string {
		const inner = indent + "    ";
		if (n.kind == NodeKind.BlockStmt) {
			return indent + "{\n" + body(n, inner) + indent + "}\n";
		}
		if (n.kind == NodeKind.IfStmt && featureOf(n.condition) != "") {
			const feature = featureOf(n.condition);
			features.push(feature);
			let text = "#ifdef " + feature + "\n" + body(n.consequent, indent);
			features.pop();
			if (n.alternate != null) {
				features.push("!" + feature);
				const otherwise = body(n.alternate, indent);
				features.pop();
				if (otherwise != "") { text += "#else\n" + otherwise; }
			}
			return text + "#endif\n";
		}
		if (n.kind == NodeKind.IfStmt) { return indent + branches(n, indent) + "\n"; }
		if (n.kind == NodeKind.WhileStmt) {
			if (n.whileLabel != "") { fail(n, "GLSL has no labelled loops"); }
			return indent + "while (" + condition(n.whileCondition) + ") {\n" +
				body(n.whileBody, inner) + indent + "}\n";
		}
		if (n.kind == NodeKind.ForStmt) {
			if (n.forLabel != "") { fail(n, "GLSL has no labelled loops"); }
			const outer = locals.length;
			const head = "for (" + simple(n.forInit) + "; " + condition(n.forCondition) + "; " +
				assignment(n.forUpdate) + ") {\n";
			const out = indent + head + body(n.forBody, inner) + indent + "}\n";
			while (locals.length > outer) { locals.pop(); }
			return out;
		}
		if (n.kind == NodeKind.BreakStmt || n.kind == NodeKind.ContinueStmt) {
			const label = n.kind == NodeKind.BreakStmt ? n.breakLabel : n.continueLabel;
			if (label != "") { fail(n, "GLSL has no labelled loops"); }
			return indent + (n.kind == NodeKind.BreakStmt ? "break" : "continue") + ";\n";
		}
		if (n.kind == NodeKind.ReturnStmt) {
			const result = n.argument;
			if (result == null) { fail(n, "an entry returns its stage output"); }
			if (outputs == null) {
				use("fragColor");
				return indent + "fragColor = " + value(result) + ";\n" + indent + "return;\n";
			}
			if (result.kind != NodeKind.ObjectLiteral) {
				fail(n, "a struct stage output is returned as an object literal");
			}
			let text = "";
			for (let k = 0; k < result.keys.length; k++) {
				text += output(result.keys[k], result.properties[k], indent);
			}
			return text + indent + "return;\n";
		}
		return indent + simple(n) + ";\n";
	}

	const main = body(fn.fnBody, "    ");
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
	const source = header + "void main() {\n" + main + "}\n";
	return { kind: NodeKind.StringLiteral, line: entry.line, column: entry.column, value: source };
}
