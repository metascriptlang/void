// glsl(fn) reads the typed body of a shader entry function and returns it as Vulkan-style GLSL 450
// for sokol-shdc: the parameters become the stage's interface, the body becomes main().
// The node walk lives inside the macro body: only there are Node fields readable (LANG-METAPROGRAMMING.md
// "Navigation only in the macro body").

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
	resolveType,
	sameType,
	typeKind,
} from "std/meta";
import {
	FragCoord,
	IVec2,
	Sampler,
	Texture2D,
	Vec2,
	Vec3,
	Vec4,
	sampler2D,
} from "./glsl";

export macro glsl(entry: Node): Node {
	const builtinSymbol = bindSym("sampler2D");
	if (builtinSymbol == null || builtinSymbol.resolvedSym == null) {
		error("glsl: bindSym(\"sampler2D\") carries no symbol (compiler card 2026-10-11-bindsym-literal-node-has-no-symbol)", entry);
	}
	const builtinModule = builtinSymbol.resolvedSym.modulePath;
	const fragCoordType = getTypeImpl(FragCoord);
	const textureType = getTypeImpl(Texture2D);
	const samplerType = getTypeImpl(Sampler);
	const vectorTypes = [getTypeImpl(Vec2), getTypeImpl(Vec3), getTypeImpl(Vec4), getTypeImpl(IVec2)];
	const vectorNames = ["vec2", "vec3", "vec4", "ivec2"];

	function fail(n: Node, msg: string): never {
		error("glsl: " + msg, n);
	}

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
		fail(at, "a shader value must be float32, int32, uint32, boolean or a vector of ./glsl");
	}

	const fn = getImpl(entry);
	if (fn == null || fn.kind != NodeKind.FunctionDecl) { fail(entry, "the entry must be a function"); }

	let header = "";
	let fragCoordName = "";
	let textures = 0;
	let samplers = 0;
	let inputs = 0;
	let outputs = 0;
	for (let i = 0; i < fn.params.length; i++) {
		const name = fn.params[i];
		const declared = fn.fnParamTypes[i];
		const isOut = declared.startsWith("out ");
		const t = resolveType(isOut ? declared.replace("out ", "") : declared);
		if (t == null) { fail(entry, "parameter '" + name + "' has no resolvable type"); }
		if (sameType(t, fragCoordType)) {
			fragCoordName = name;
		} else if (sameType(t, textureType)) {
			header += "layout(binding=" + String(textures) + ") uniform texture2D " + name + ";\n";
			textures += 1;
		} else if (sameType(t, samplerType)) {
			header += "layout(binding=" + String(samplers) + ") uniform sampler " + name + ";\n";
			samplers += 1;
		} else if (isOut) {
			header += "layout(location=" + String(outputs) + ") out " + glslType(t, entry) + " " + name + ";\n";
			outputs += 1;
		} else {
			header += "layout(location=" + String(inputs) + ") in " + glslType(t, entry) + " " + name + ";\n";
			inputs += 1;
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

	function isBuiltin(callee: Node): boolean {
		return callee.resolvedSym != null && callee.resolvedSym.modulePath == builtinModule;
	}

	function expr(n: Node): string {
		if (n.kind == NodeKind.NumberLiteral) { return number(n); }
		if (n.kind == NodeKind.BooleanLiteral) { return n.boolValue ? "true" : "false"; }
		if (n.kind == NodeKind.Identifier) {
			if (n.name == fragCoordName && fragCoordName != "") { return "gl_FragCoord"; }
			return n.name;
		}
		if (n.kind == NodeKind.BinaryExpr) {
			const op = n.operator == "===" ? "==" : n.operator == "!==" ? "!=" : n.operator;
			if (op.endsWith("=") && op != "==" && op != "!=" && op != "<=" && op != ">=") {
				return expr(n.left) + " " + op + " " + expr(n.right);
			}
			return "(" + expr(n.left) + " " + op + " " + expr(n.right) + ")";
		}
		if (n.kind == NodeKind.UnaryExpr) { return n.unaryOp + expr(n.operand); }
		if (n.kind == NodeKind.ConditionalExpr) {
			return "(" + expr(n.ternaryCondition) + " ? " + expr(n.ternaryConsequent) + " : " +
				expr(n.ternaryAlternate) + ")";
		}
		if (n.kind == NodeKind.MemberExpr) { return expr(n.object) + "." + n.property; }
		if (n.kind == NodeKind.CallExpr) {
			const callee = n.callee;
			const impl = getImpl(callee);
			if (!isBuiltin(callee) || impl == null || impl.kind != NodeKind.FunctionDecl) {
				fail(n, "only functions of ./glsl can be called from a shader yet");
			}
			let args: string[] = [];
			if (callee.kind == NodeKind.MemberExpr) {
				if (impl.fnName.startsWith("get_")) {
					return expr(callee.object) + "." + impl.fnName.replace("get_", "");
				}
				args.push(expr(callee.object));
			}
			for (const a of n.arguments) { args.push(expr(a)); }
			return impl.fnName + "(" + args.join(", ") + ")";
		}
		fail(n, "this expression has no GLSL form yet (node kind " + String(n.kind) + ")");
	}

	function stmt(n: Node, indent: string): string {
		if (n.kind == NodeKind.BlockStmt) {
			let out = "";
			for (const s of n.statements) { out += stmt(s, indent); }
			return out;
		}
		if (n.kind == NodeKind.VariableDecl) {
			return indent + glslType(getType(n.initializer), n) + " " + n.declName + " = " +
				expr(n.initializer) + ";\n";
		}
		if (n.kind == NodeKind.ExprStmt) { return indent + expr(n.expr) + ";\n"; }
		if (n.kind == NodeKind.IfStmt) {
			let out = indent + "if (" + expr(n.condition) + ") {\n" + stmt(n.consequent, indent + "    ") +
				indent + "}";
			if (n.alternate != null) {
				out += " else {\n" + stmt(n.alternate, indent + "    ") + indent + "}";
			}
			return out + "\n";
		}
		fail(n, "this statement has no GLSL form yet (node kind " + String(n.kind) + ")");
	}

	const source = header + "void main() {\n" + stmt(fn.fnBody, "    ") + "}\n";
	return { kind: NodeKind.StringLiteral, line: entry.line, column: entry.column, value: source };
}
