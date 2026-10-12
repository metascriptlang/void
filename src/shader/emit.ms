// glsl(fn) reads a fragment entry function and returns it as Vulkan-style GLSL 450 for sokol-shdc:
// the signature becomes the stage's interface, the body becomes main().
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

	const fn = getImpl(entry);
	const signature = getType(entry);
	if (fn == null || fn.kind != NodeKind.FunctionDecl || signature == null ||
		signature.kind != NodeKind.TypeFunction) {
		fail(entry, "the entry must be a function");
	}

	let header = "";
	let inputName = "";
	let positionField = "";
	let textures = 0;
	let samplers = 0;
	for (let i = 0; i < signature.typExprParams.length; i++) {
		const name = signature.typExprParamNames[i];
		const t = signature.typExprParams[i];
		if (sameType(t, textureType)) {
			header += "layout(binding=" + String(textures) + ") uniform texture2D " + name + ";\n";
			textures += 1;
		} else if (sameType(t, samplerType)) {
			header += "layout(binding=" + String(samplers) + ") uniform sampler " + name + ";\n";
			samplers += 1;
		} else {
			const fields = getTypeImpl(t);
			if (fields == null || fields.kind != NodeKind.TypeObject || inputName != "") {
				fail(entry, "parameter '" + name +
					"' is not a texture, a sampler or the one input struct");
			}
			inputName = name;
			for (let f = 0; f < fields.typExprFieldNames.length; f++) {
				const decorators = fields.typExprFieldDecorators[f];
				const isPosition = decorators.length == 1 && decorators[0].macroName == "builtin" &&
					decorators[0].macroArgs.length == 1 &&
					decorators[0].macroArgs[0].kind == NodeKind.Identifier &&
					decorators[0].macroArgs[0].name == "position";
				if (!isPosition || positionField != "") {
					fail(entry, "input field '" + fields.typExprFieldNames[f] +
						"': only one @builtin(position) field has a GLSL form yet");
				}
				positionField = fields.typExprFieldNames[f];
			}
		}
	}
	const colour = glslType(signature.typExprReturn, entry);
	header += "layout(location=0) out " + colour + " fragColor;\n";

	function number(n: Node): string {
		const kind = typeKind(getType(n));
		if (kind == TypeKind.Float32 || kind == TypeKind.Float64) {
			const text = String(floatValue(n));
			return text.indexOf(".") >= 0 || text.indexOf("e") >= 0 ? text : text + ".0";
		}
		return String(intValue(n));
	}

	function expr(n: Node): string {
		if (n.kind == NodeKind.NumberLiteral) { return number(n); }
		if (n.kind == NodeKind.Identifier) { return n.name; }
		if (n.kind == NodeKind.BinaryExpr) {
			return "(" + expr(n.left) + " " + n.operator + " " + expr(n.right) + ")";
		}
		if (n.kind == NodeKind.MemberExpr) {
			const object = n.object;
			if (object.kind == NodeKind.Identifier && object.name == inputName) {
				if (n.property == positionField) { return "gl_FragCoord"; }
				fail(n, "input field '" + n.property + "' has no GLSL form yet");
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

	function stmt(n: Node): string {
		if (n.kind == NodeKind.BlockStmt) {
			let out = "";
			for (const s of n.statements) { out += stmt(s); }
			return out;
		}
		if (n.kind == NodeKind.VariableDecl) {
			return "    " + glslType(getType(n.initializer), n) + " " + n.declName + " = " +
				expr(n.initializer) + ";\n";
		}
		if (n.kind == NodeKind.ReturnStmt) {
			const value = n.argument;
			if (value == null) { fail(n, "a fragment entry returns its colour"); }
			return "    fragColor = " + expr(value) + ";\n    return;\n";
		}
		fail(n, "this statement has no GLSL form yet (node kind " + String(n.kind) + ")");
	}

	const source = header + "void main() {\n" + stmt(fn.fnBody) + "}\n";
	return { kind: NodeKind.StringLiteral, line: entry.line, column: entry.column, value: source };
}
