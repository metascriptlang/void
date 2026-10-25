import {
	Access,
	AssignOp,
	BinaryOp,
	Builtin,
	ExprKind,
	Interpolation,
	Intrinsic,
	IoDirection,
	ResourceKind,
	Sampling,
	SamplerType,
	ScalarKind,
	ShaderExpr,
	ShaderFunction,
	ShaderIo,
	ShaderModule,
	ShaderStage,
	ShaderStmt,
	ShaderType,
	ShaderTypeKind,
	StmtKind,
	TexelFormat,
	TextureShape,
	UnaryOp,
	sameShaderType,
	isAtomic,
	isEffect,
} from "./ir";
import { BindingSlot } from "./layout";
import { builtinType, ioLocation } from "./irWalk";
import { claimName } from "./names";
import { printableEntry } from "./specialize";
import {
	binaryOperator,
	floatText,
	isIntMin,
	isMath,
	mathName,
} from "./spelling";

function wgslReservedWords(): string[] {
	let words = [
		"alias", "break", "case", "const", "const_assert", "continue", "continuing", "default",
		"diagnostic", "discard", "else", "enable", "false", "fn", "for", "if", "let", "loop",
		"override", "requires", "return", "struct", "switch", "true", "var", "while",
		"NULL", "Self", "abstract", "active", "alignas", "alignof", "as", "asm", "asm_fragment",
		"async", "attribute", "auto", "await", "become", "cast", "catch", "class", "co_await",
		"co_return", "co_yield", "coherent", "column_major", "common", "compile",
		"compile_fragment", "concept", "const_cast", "consteval", "constexpr", "constinit",
		"crate", "debugger", "decltype", "delete", "demote", "demote_to_helper", "do",
		"dynamic_cast", "enum", "explicit", "export", "extends", "extern", "external",
		"fallthrough", "filter", "final", "finally", "friend", "from", "fxgroup", "get", "goto",
		"groupshared", "highp", "impl", "implements", "import", "inline", "instanceof",
		"interface", "layout", "lowp", "macro", "macro_rules", "match", "mediump", "meta", "mod",
		"module", "move", "mut", "mutable", "namespace", "new", "nil", "noexcept", "noinline",
		"nointerpolation", "non_coherent", "noncoherent", "noperspective", "null", "nullptr",
		"of", "operator", "package", "packoffset", "partition", "pass", "patch", "pixelfragment",
		"precise", "precision", "premerge", "priv", "protected", "pub", "public", "readonly",
		"ref", "regardless", "register", "reinterpret_cast", "require", "resource", "restrict",
		"self", "set", "shared", "sizeof", "smooth", "snorm", "static", "static_assert",
		"static_cast", "std", "subroutine", "super", "target", "template", "this",
		"thread_local", "throw", "trait", "try", "type", "typedef", "typeid", "typename",
		"typeof", "union", "unless", "unorm", "unsafe", "unsized", "use", "using", "varying",
		"virtual", "volatile", "wgsl", "where", "with", "writeonly", "yield",
		"bool", "f16", "f32", "i32", "u32", "array", "atomic", "ptr", "sampler",
		"sampler_comparison", "texture_1d", "texture_2d", "texture_2d_array", "texture_3d",
		"texture_cube", "texture_cube_array", "texture_multisampled_2d", "texture_depth_2d",
		"texture_depth_2d_array", "texture_depth_cube", "texture_depth_cube_array",
		"texture_depth_multisampled_2d", "texture_storage_1d", "texture_storage_2d",
		"texture_storage_2d_array", "texture_storage_3d", "texture_external",
		"function", "private", "workgroup", "uniform", "storage", "handle", "read", "write",
		"read_write", "rgba8unorm", "rgba8snorm", "rgba8uint", "rgba8sint", "rgba16uint",
		"rgba16sint", "rgba16float", "r32uint", "r32sint", "r32float", "rg32uint", "rg32sint",
		"rg32float", "rgba32uint", "rgba32sint", "rgba32float", "bgra8unorm",
		"all", "any", "select", "bitcast", "textureSample", "textureSampleLevel", "textureLoad",
		"textureStore", "textureDimensions", "textureSampleCompare", "textureSampleCompareLevel",
		"main",
	];
	for (let n = 2; n <= 4; n++) {
		words.push("vec" + String(n));
		for (const suffix of ["f", "h", "i", "u"]) { words.push("vec" + String(n) + suffix); }
		for (let r = 2; r <= 4; r++) {
			const mat = "mat" + String(n) + "x" + String(r);
			words.push(mat);
			words.push(mat + "f");
			words.push(mat + "h");
		}
	}
	for (let i = 0; i <= (Intrinsic.TextureDimensions as int32); i++) {
		const op = i as Intrinsic;
		if (!isMath(op) && op != Intrinsic.Select) { continue; }
		const name = builtinName(op);
		if (name != "") { words.push(name); }
	}
	return words;
}

function builtinName(op: Intrinsic): string {
	return match (op) {
		Intrinsic.InverseSqrt => "inverseSqrt",
		Intrinsic.FaceForward => "faceForward",
		Intrinsic.Dpdx => "dpdx",
		Intrinsic.Dpdy => "dpdy",
		Intrinsic.Select => "select",
		_ => mathName(op),
	};
}

const UPPER_LEFT = "upperLeft3x3";

function inverseName(n: int32): string { return "inverse" + String(n) + "x" + String(n); }

function inverseText(n: int32): string {
	const mat = "mat" + String(n) + "x" + String(n) + "f";
	const body = match (n) {
		2 => [
			"let k = 1.0f / determinant(m);",
			"return mat2x2f(m[1].y * k, -m[0].y * k, -m[1].x * k, m[0].x * k);",
		],
		3 => [
			"let k = 1.0f / determinant(m);",
			"return transpose(mat3x3f(cross(m[1], m[2]) * k, cross(m[2], m[0]) * k, " +
				"cross(m[0], m[1]) * k));",
		],
		_ => [
			"let a = m[0].xyz;",
			"let b = m[1].xyz;",
			"let c = m[2].xyz;",
			"let d = m[3].xyz;",
			"let s = cross(a, b);",
			"let t = cross(c, d);",
			"let u = a * m[1].w - b * m[0].w;",
			"let v = c * m[3].w - d * m[2].w;",
			"let k = 1.0f / (dot(s, v) + dot(t, u));",
			"return transpose(mat4x4f(",
			"  vec4f(cross(b, v * k) + t * k * m[1].w, -dot(b, t * k)),",
			"  vec4f(cross(v * k, a) - t * k * m[0].w, dot(a, t * k)),",
			"  vec4f(cross(d, u * k) + s * k * m[3].w, -dot(d, s * k)),",
			"  vec4f(cross(u * k, c) - s * k * m[2].w, dot(c, s * k))));",
		],
	};
	return "fn " + inverseName(n) + "(m : " + mat + ") -> " + mat + " {\n" +
		body.map((line) => "  " + line + "\n").join("") + "}";
}

class Printer {
	module: ShaderModule = new ShaderModule();
	stage: ShaderStage = ShaderStage.Vertex;
	taken: string[] = [];
	structs: string[] = [];
	members: string[][] = [];
	constants: string[] = [];
	resources: string[] = [];
	ios: string[] = [];
	functions: string[] = [];
	workgroups: string[] = [];
	fn: ShaderFunction = new ShaderFunction();
	scope: string[] = [];
	params: string[] = [];
	locals: string[] = [];
	derivatives: boolean = false;
	error: string = "";
	upperLeft: boolean = false;
	inverses: int32[] = [];
	lines: string[] = [];
	depth: int32 = 0;
	unhoistable: string = "";
	reserved: string[] = [];
}

function refusal(p: Printer, what: string): string {
	if (p.error == "") { p.error = "printWgsl: " + what; }
	return "";
}

function isIdentifier(name: string): boolean {
	if (name == "" || name == "_" || name.startsWith("__")) { return false; }
	for (let i = 0; i < name.length; i++) {
		const c = name.charCodeAt(i);
		const letter = (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95;
		if (!letter && !(i > 0 && c >= 48 && c <= 57)) { return false; }
	}
	return true;
}

function nameIn(p: Printer, scope: string[], name: string): string {
	if (!isIdentifier(name)) { return refusal(p, "'" + name + "' is no WGSL identifier"); }
	return claimName(scope, (n) => p.reserved.includes(n), name);
}

function scalarText(s: ScalarKind): string {
	return match (s) {
		ScalarKind.F32 => "f32",
		ScalarKind.I32 => "i32",
		ScalarKind.U32 => "u32",
		ScalarKind.Bool => "bool",
	};
}

function texelText(p: Printer, s: ScalarKind): string {
	if (s == ScalarKind.Bool) { return refusal(p, "a texture of bool texels"); }
	return scalarText(s);
}

function textureText(p: Printer, t: ShaderType): string {
	const texel = "<" + texelText(p, t.scalar) + ">";
	return match (t.shape) {
		TextureShape.D2 => "texture_2d" + texel,
		TextureShape.D2Array => "texture_2d_array" + texel,
		TextureShape.D3 => "texture_3d" + texel,
		TextureShape.Cube => "texture_cube" + texel,
		TextureShape.CubeArray => "texture_cube_array" + texel,
		TextureShape.Depth2d => "texture_depth_2d",
		TextureShape.Depth2dArray => "texture_depth_2d_array",
		TextureShape.DepthCube => "texture_depth_cube",
		TextureShape.Multisampled2d => "texture_multisampled_2d" + texel,
	};
}

function formatText(f: TexelFormat): string {
	return match (f) {
		TexelFormat.Rgba8unorm => "rgba8unorm",
		TexelFormat.Rgba8snorm => "rgba8snorm",
		TexelFormat.Rgba8uint => "rgba8uint",
		TexelFormat.Rgba16float => "rgba16float",
		TexelFormat.Rgba32float => "rgba32float",
		TexelFormat.R32float => "r32float",
		TexelFormat.R32uint => "r32uint",
		TexelFormat.Rg32float => "rg32float",
	};
}

function accessText(a: Access): string {
	return match (a) {
		Access.Read => "read",
		Access.Write => "write",
		Access.ReadWrite => "read_write",
	};
}

function typeText(p: Printer, t: ShaderType): string {
	const rows = String(t.rows);
	return match (t.kind) {
		ShaderTypeKind.Scalar => scalarText(t.scalar),
		ShaderTypeKind.Vector => t.scalar == ScalarKind.Bool ? "vec" + rows + "<bool>" :
			"vec" + rows + scalarText(t.scalar).substring(0, 1),
		ShaderTypeKind.Matrix => "mat" + String(t.columns) + "x" + rows + "f",
		ShaderTypeKind.Array => "array<" + typeText(p, t.element[0]) + ", " +
			String(t.length) + ">",
		ShaderTypeKind.RuntimeArray => "array<" + typeText(p, t.element[0]) + ">",
		ShaderTypeKind.Struct => p.structs[t.structIndex],
		ShaderTypeKind.Texture => textureText(p, t),
		ShaderTypeKind.Sampler => "sampler",
		ShaderTypeKind.StorageTexture => "texture_storage_" + storageShapeText(p, t.shape) + "<" +
			formatText(t.format) + ", " + accessText(t.access) + ">",
		ShaderTypeKind.Atomic => "atomic<" + scalarText(t.scalar) + ">",
		ShaderTypeKind.ExchangeResult => refusal(p, "an atomic exchange result outside the " +
			"local it initializes"),
		ShaderTypeKind.Void => refusal(p, "a value of type void"),
	};
}

function atomicText(p: Printer, e: ShaderExpr): string {
	const o = e.operands;
	const place = "&" + exprText(p, o[0]);
	const rest = o.slice(1).map((a) => ", " + exprText(p, a)).join("");
	const name = match (e.intrinsic) {
		Intrinsic.AtomicLoad => "atomicLoad",
		Intrinsic.AtomicStore => "atomicStore",
		Intrinsic.AtomicAdd => "atomicAdd",
		Intrinsic.AtomicSub => "atomicSub",
		Intrinsic.AtomicMax => "atomicMax",
		Intrinsic.AtomicMin => "atomicMin",
		Intrinsic.AtomicAnd => "atomicAnd",
		Intrinsic.AtomicOr => "atomicOr",
		Intrinsic.AtomicXor => "atomicXor",
		Intrinsic.AtomicExchange => "atomicExchange",
		Intrinsic.AtomicCompareExchangeWeak => "atomicCompareExchangeWeak",
		_ => refusal(p, e.intrinsic.toString() + " has no WGSL atomic spelling"),
	};
	return name + "(" + place + rest + ")";
}

function scalarLiteral(s: ScalarKind, value: float64): string {
	if (s == ScalarKind.Bool) { return value != 0.0 ? "true" : "false"; }
	if (s == ScalarKind.F32) {
		const text = floatText(value) + "f";
		return value < 0.0 || text.startsWith("-") ? "(" + text + ")" : text;
	}
	if (isIntMin(s, value)) { return "(-2147483647i - 1i)"; }
	const text = String(value as int64) + (s == ScalarKind.I32 ? "i" : "u");
	return value < 0.0 ? "(" + text + ")" : text;
}

function literalText(p: Printer, t: ShaderType, value: float64): string {
	return match (t.kind) {
		ShaderTypeKind.Scalar => scalarLiteral(t.scalar, value),
		ShaderTypeKind.Vector => typeText(p, t) + "(" + scalarLiteral(t.scalar, value) + ")",
		_ => refusal(p, "a literal of a " + t.kind.toString()),
	};
}

function argsText(p: Printer, args: ShaderExpr[]): string {
	return args.map((a) => exprText(p, a)).join(", ");
}

function binaryText(p: Printer, e: ShaderExpr): string {
	const left = e.operands[0];
	const shortCircuit = e.binary == BinaryOp.LogicalAnd || e.binary == BinaryOp.LogicalOr;
	if (shortCircuit && hoists(e.operands[1])) {
		return refusal(p, "a conditional whose branch calls a function, right of '" +
			binaryOperator(e.binary) + "'");
	}
	const text = "(" + exprText(p, left) + " " + binaryOperator(e.binary) + " " +
		exprText(p, e.operands[1]) + ")";
	const whole = (e.binary == BinaryOp.Equal || e.binary == BinaryOp.NotEqual) &&
		e.type.kind == ShaderTypeKind.Scalar;
	if (!whole || left.type.kind == ShaderTypeKind.Scalar) { return text; }
	if (left.type.kind != ShaderTypeKind.Vector) {
		return refusal(p, "'" + binaryOperator(e.binary) + "' on a " + left.type.kind.toString());
	}
	return (e.binary == BinaryOp.Equal ? "all" : "any") + text;
}

function runsEffect(e: ShaderExpr): boolean {
	return e.kind == ExprKind.Call || e.kind == ExprKind.Intrinsic && isEffect(e.intrinsic);
}

function hasEffect(e: ShaderExpr): boolean {
	return runsEffect(e) || e.operands.some((o) => hasEffect(o));
}

// select evaluates both arms, so a conditional with a call in an arm becomes a var assigned in
// an if/else ahead of its statement, as Tint's PromoteSideEffectsToDecl does.
function isHoisted(e: ShaderExpr): boolean {
	return e.kind == ExprKind.Conditional && (hasEffect(e.operands[1]) || hasEffect(e.operands[2]));
}

function hoists(e: ShaderExpr): boolean {
	return isHoisted(e) || e.operands.some((o) => hoists(o));
}

function bareEffect(e: ShaderExpr): boolean {
	if (isHoisted(e)) { return false; }
	return runsEffect(e) || e.operands.some((o) => bareEffect(o));
}

function keepsOrder(e: ShaderExpr): boolean {
	if (!isHoisted(e) && hoists(e) && bareEffect(e)) { return false; }
	return !e.operands.some((o) => !keepsOrder(o));
}

function hoistReason(s: ShaderStmt): string {
	const parts = [s.target, s.expr];
	const hoisting = parts.some((e) => hoists(e));
	const ordered = !parts.some((e) => !keepsOrder(e)) &&
		!(hoisting && parts.some((e) => bareEffect(e)));
	return ordered ? "" : "beside a call it would run ahead of";
}

function conditionalText(p: Printer, e: ShaderExpr): string {
	if (e.type.kind != ShaderTypeKind.Scalar && e.type.kind != ShaderTypeKind.Vector) {
		return refusal(p, "a conditional of a " + e.type.kind.toString());
	}
	if (!isHoisted(e)) {
		return "select(" + exprText(p, e.operands[2]) + ", " + exprText(p, e.operands[1]) + ", " +
			exprText(p, e.operands[0]) + ")";
	}
	if (p.unhoistable != "") {
		return refusal(p, "a conditional whose branch calls a function, " + p.unhoistable);
	}
	const condition = exprText(p, e.operands[0]);
	const name = nameIn(p, p.scope, "selected");
	const depth = p.depth;
	emit(p, depth, "var " + name + " : " + typeText(p, e.type) + ";");
	emit(p, depth, "if (" + condition + ") {");
	p.depth = depth + 1;
	emit(p, depth + 1, name + " = " + exprText(p, e.operands[1]) + ";");
	emit(p, depth, "} else {");
	emit(p, depth + 1, name + " = " + exprText(p, e.operands[2]) + ";");
	emit(p, depth, "}");
	p.depth = depth;
	return name;
}

function withoutSamplers(args: ShaderExpr[]): ShaderExpr[] {
	return args.filter((a) => a.type.kind != ShaderTypeKind.Sampler);
}

function isDepth(t: ShaderType): boolean {
	return t.shape == TextureShape.Depth2d || t.shape == TextureShape.Depth2dArray ||
		t.shape == TextureShape.DepthCube;
}

function biasText(p: Printer, o: ShaderExpr[]): string {
	p.derivatives = true;
	return "textureSampleBias(" + argsText(p, o) + ")";
}

function compareText(p: Printer, e: ShaderExpr, level: boolean): string {
	const o = e.operands;
	const name = e.intrinsic.toString();
	const layered = o.length > 0 && o[0].type.shape == TextureShape.Depth2dArray;
	if (o.length != (layered ? 5 : 4) || o[0].type.kind != ShaderTypeKind.Texture ||
		o[1].type.kind != ShaderTypeKind.Sampler) {
		return refusal(p, name + " takes a texture, a sampler, coordinates, for an array texture " +
			"a layer, and a depth reference");
	}
	if (!level) { p.derivatives = true; }
	const sampler = o[1].kind == ExprKind.Resource ? p.module.resources[o[1].index] : null;
	if (sampler === null || sampler.samplerType != SamplerType.Comparison) {
		return refusal(p, name + " through a sampler that is no comparison sampler binding");
	}
	if (!isDepth(o[0].type)) {
		return refusal(p, name + " of a " + o[0].type.shape.toString() + " texture, which holds " +
			"no depth");
	}
	return (level ? "textureSampleCompareLevel(" : "textureSampleCompare(") + argsText(p, o) + ")";
}

function intrinsicText(p: Printer, e: ShaderExpr): string {
	const o = e.operands;
	const op = e.intrinsic;
	const name = isMath(op) || op == Intrinsic.Select ? builtinName(op) : "";
	if (op == Intrinsic.Dpdx || op == Intrinsic.Dpdy || op == Intrinsic.Fwidth) {
		p.derivatives = true;
	}
	if (name != "") { return name + "(" + argsText(p, o) + ")"; }
	if (op == Intrinsic.UpperLeft3x3) { p.upperLeft = true; }
	if (op == Intrinsic.TextureSample && p.stage == ShaderStage.Fragment) {
		p.derivatives = true;
		return "textureSample(" + argsText(p, o) + ")";
	}
	if (op == Intrinsic.TextureLoad && o[0].type.kind == ShaderTypeKind.Texture &&
		withoutSamplers(o).length < 3) {
		return refusal(p, "textureLoad of a sampled texture takes a level");
	}
	return match (op) {
		Intrinsic.Inverse => inverseCall(p, e),
		Intrinsic.UpperLeft3x3 => UPPER_LEFT + "(" + exprText(p, o[0]) + ")",
		Intrinsic.LessThanEqual => "(" + exprText(p, o[0]) + " <= " + exprText(p, o[1]) + ")",
		Intrinsic.TextureSample => "textureSampleLevel(" + argsText(p, o) + ", " +
			(isDepth(o[0].type) ? "0i" : "0.0f") + ")",
		Intrinsic.TextureLoad => "textureLoad(" + argsText(p, withoutSamplers(o)) + ")",
		Intrinsic.TextureStore => "textureStore(" + argsText(p, o) + ")",
		Intrinsic.TextureDimensions => dimensionsText(p, e),
		Intrinsic.TextureSampleCompare => compareText(p, e, false),
		Intrinsic.TextureSampleCompareLevel => compareText(p, e, true),
		Intrinsic.TextureSampleLevel => "textureSampleLevel(" + argsText(p, o) + ")",
		Intrinsic.TextureSampleBias => biasText(p, o),
		Intrinsic.TextureSampleGrad => "textureSampleGrad(" + argsText(p, o) + ")",
		Intrinsic.WorkgroupBarrier => "workgroupBarrier()",
		Intrinsic.StorageBarrier => "storageBarrier()",
		_ => isAtomic(op) ? atomicText(p, e) : refusal(p, op.toString() + " has no WGSL spelling"),
	};
}

function inverseCall(p: Printer, e: ShaderExpr): string {
	const t = e.type;
	if (t.kind != ShaderTypeKind.Matrix || t.columns != t.rows) {
		return refusal(p, "inverse of a " + t.kind.toString() + " that is no square matrix");
	}
	if (!p.inverses.includes(t.rows)) { p.inverses.push(t.rows); }
	return inverseName(t.rows) + "(" + exprText(p, e.operands[0]) + ")";
}

function storageShapeText(p: Printer, shape: TextureShape): string {
	return match (shape) {
		TextureShape.D2 => "2d",
		TextureShape.D2Array => "2d_array",
		TextureShape.D3 => "3d",
		_ => refusal(p, "a storage texture of shape " + shape.toString()),
	};
}

function dimensionsText(p: Printer, e: ShaderExpr): string {
	const call = "textureDimensions(" + argsText(p, withoutSamplers(e.operands)) + ")";
	return e.type.scalar == ScalarKind.U32 ? call : typeText(p, e.type) + "(" + call + ")";
}

function memberName(p: Printer, t: ShaderType, member: int32): string {
	return match (t.kind) {
		ShaderTypeKind.ExchangeResult => member == 0 ? "old_value" : "exchanged",
		ShaderTypeKind.Struct => p.members[t.structIndex][member],
		_ => refusal(p, "a field of a " + t.kind.toString()),
	};
}

function swizzleText(components: int32[]): string {
	return components.map((c) => "xyzw".substring(c, c + 1)).join("");
}

function ioName(p: Printer, index: int32): string {
	const io = p.module.ios[index];
	if (io.stage != p.stage) {
		return refusal(p, "io '" + io.name + "' belongs to the " + io.stage.toString() + " stage");
	}
	return p.ios[index];
}

function exprText(p: Printer, e: ShaderExpr): string {
	const m = p.module;
	const o = e.operands;
	return match (e.kind) {
		ExprKind.Literal => literalText(p, e.type, e.value),
		ExprKind.Local => p.locals[e.index],
		ExprKind.Param => p.params[e.index],
		ExprKind.Constant => p.constants[e.index],
		ExprKind.Io => ioName(p, e.index),
		ExprKind.Resource => p.resources[e.index],
		ExprKind.Workgroup => p.workgroups[e.index],
		ExprKind.BlockMember => p.resources[e.index] + "." +
			memberName(p, m.resources[e.index].type, e.member),
		ExprKind.Unary => match (e.unary) {
			UnaryOp.Negate => "(-" + exprText(p, o[0]) + ")",
			UnaryOp.Not => (o[0].type.scalar == ScalarKind.Bool ? "(!" : "(~") +
				exprText(p, o[0]) + ")",
		},
		ExprKind.Binary => binaryText(p, e),
		ExprKind.Conditional => conditionalText(p, e),
		ExprKind.Call => p.functions[e.index] + "(" + argsText(p, o) + ")",
		ExprKind.Intrinsic => intrinsicText(p, e),
		ExprKind.Construct | ExprKind.Convert => typeText(p, e.type) + "(" + argsText(p, o) + ")",
		ExprKind.Field => exprText(p, o[0]) + "." + memberName(p, o[0].type, e.index),
		ExprKind.Swizzle => exprText(p, o[0]) + "." + swizzleText(e.components),
		ExprKind.Index => exprText(p, o[0]) + "[" + exprText(p, o[1]) + "]",
	};
}

function assignOperator(op: AssignOp): string {
	return match (op) {
		AssignOp.Set => " = ",
		AssignOp.Add => " += ",
		AssignOp.Sub => " -= ",
		AssignOp.Mul => " *= ",
		AssignOp.Div => " /= ",
		AssignOp.Mod => " %= ",
		AssignOp.Increment => "++",
		AssignOp.Decrement => "--",
	};
}

function isVoid(e: ShaderExpr): boolean {
	return e.type.kind == ShaderTypeKind.Void;
}

function emit(p: Printer, depth: int32, text: string): void {
	p.lines.push("  ".repeat(depth) + text);
}

function splitSwizzle(s: ShaderStmt): boolean {
	return s.kind == StmtKind.Assign && s.target.kind == ExprKind.Swizzle &&
		s.target.components.length > 1;
}

function simpleText(p: Printer, s: ShaderStmt): string {
	return match (s.kind) {
		StmtKind.Let => p.fn.locals[s.local].type.kind == ShaderTypeKind.ExchangeResult &&
			!isVoid(s.expr) ? "var " + p.locals[s.local] + " = " + exprText(p, s.expr) :
			"var " + p.locals[s.local] + " : " + typeText(p, p.fn.locals[s.local].type) +
			(isVoid(s.expr) ? "" : " = " + exprText(p, s.expr)),
		StmtKind.Assign => s.assign == AssignOp.Increment || s.assign == AssignOp.Decrement ?
			exprText(p, s.target) + assignOperator(s.assign) :
			exprText(p, s.target) + assignOperator(s.assign) + exprText(p, s.expr),
		StmtKind.Call => s.expr.kind == ExprKind.Call || isVoid(s.expr) ?
			exprText(p, s.expr) : "_ = " + exprText(p, s.expr),
		_ => refusal(p, s.kind.toString() + " is no simple statement"),
	};
}

function fitsHeader(stmts: ShaderStmt[], update: boolean): boolean {
	if (stmts.length > 1) { return false; }
	if (stmts.length == 0) { return true; }
	const s = stmts[0];
	return !splitSwizzle(s) && (s.kind == StmtKind.Assign || s.kind == StmtKind.Call ||
		!update && s.kind == StmtKind.Let);
}

function stmtsText(p: Printer, stmts: ShaderStmt[], depth: int32): void {
	for (const s of stmts) { stmtText(p, s, depth); }
}

function stmtText(p: Printer, s: ShaderStmt, depth: int32): void {
	p.depth = depth;
	p.unhoistable = hoistReason(s);
	match (s.kind) {
		StmtKind.Block => {
			emit(p, depth, "{");
			stmtsText(p, s.body, depth + 1);
			emit(p, depth, "}");
		},
		StmtKind.Assign => {
			if (!splitSwizzle(s)) {
				emit(p, depth, simpleText(p, s) + ";");
				return;
			}
			if (s.assign == AssignOp.Increment || s.assign == AssignOp.Decrement) {
				refusal(p, "an increment of a swizzle");
			}
			const value = nameIn(p, p.scope, "swizzled");
			const base = exprText(p, s.target.operands[0]);
			emit(p, depth, "{");
			p.depth = depth + 1;
			emit(p, depth + 1, "let " + value + " = " + exprText(p, s.expr) + ";");
			for (let k = 0; k < s.target.components.length; k++) {
				const c = s.target.components[k];
				emit(p, depth + 1, base + "." + swizzleText([c]) + assignOperator(s.assign) +
					value + "." + swizzleText([k as int32]) + ";");
			}
			emit(p, depth, "}");
		},
		StmtKind.Let | StmtKind.Call => emit(p, depth, simpleText(p, s) + ";"),
		StmtKind.If => {
			emit(p, depth, "if (" + exprText(p, s.expr) + ") {");
			stmtsText(p, s.body, depth + 1);
			if (s.otherwise.length > 0) {
				emit(p, depth, "} else {");
				stmtsText(p, s.otherwise, depth + 1);
			}
			emit(p, depth, "}");
		},
		StmtKind.FeatureIf => refusal(p, "a feature branch is still undecided: specialize the " +
			"module first"),
		StmtKind.While => {
			p.unhoistable = "in a loop condition";
			emit(p, depth, "while (" + exprText(p, s.expr) + ") {");
			stmtsText(p, s.body, depth + 1);
			emit(p, depth, "}");
		},
		StmtKind.For => forText(p, s, depth),
		StmtKind.Switch => {
			emit(p, depth, "switch (" + exprText(p, s.expr) + ") {");
			for (const arm of s.cases) {
				let labels = arm.labels.map((l) => exprText(p, l));
				if (arm.isDefault) { labels.push("default"); }
				emit(
					p,
					depth + 1,
					(arm.labels.length == 0 ? "default" : "case " + labels.join(", ")) + ": {",
				);
				stmtsText(p, arm.body, depth + 2);
				emit(p, depth + 1, "}");
			}
			if (!s.cases.some((arm) => arm.isDefault)) { emit(p, depth + 1, "default: {}"); }
			emit(p, depth, "}");
		},
		StmtKind.Break => emit(p, depth, "break;"),
		StmtKind.Continue => emit(p, depth, "continue;"),
		StmtKind.Return => emit(p, depth, isVoid(s.expr) ? "return;" :
			"return " + exprText(p, s.expr) + ";"),
		StmtKind.Discard => emit(p, depth, "discard;"),
	}
}

function forText(p: Printer, s: ShaderStmt, depth: int32): void {
	const header = fitsHeader(s.init, false) && fitsHeader(s.update, true);
	if (header && s.init.length > 0) { p.unhoistable = hoistReason(s.init[0]); }
	const init = header && s.init.length > 0 ? simpleText(p, s.init[0]) : "";
	p.unhoistable = "in a loop condition or update";
	const condition = isVoid(s.expr) ? "" : exprText(p, s.expr);
	if (header) {
		const update = s.update.length == 0 ? "" : simpleText(p, s.update[0]);
		emit(p, depth, "for (" + init + "; " + condition + "; " + update + ") {");
		stmtsText(p, s.body, depth + 1);
		emit(p, depth, "}");
		return;
	}
	emit(p, depth, "{");
	stmtsText(p, s.init, depth + 1);
	emit(p, depth + 1, "loop {");
	if (condition != "") { emit(p, depth + 2, "if (!" + condition + ") { break; }"); }
	stmtsText(p, s.body, depth + 2);
	if (s.update.length > 0) {
		emit(p, depth + 2, "continuing {");
		stmtsText(p, s.update, depth + 3);
		emit(p, depth + 2, "}");
	}
	emit(p, depth + 1, "}");
	emit(p, depth, "}");
}

function writtenParams(stmts: ShaderStmt[], written: int32[]): void {
	for (const s of stmts) {
		if (s.kind == StmtKind.Assign) {
			let root = s.target;
			while (root.kind == ExprKind.Field || root.kind == ExprKind.Swizzle ||
				root.kind == ExprKind.Index) {
				root = root.operands[0];
			}
			if (root.kind == ExprKind.Param && !written.includes(root.index)) {
				written.push(root.index);
			}
		}
		for (const list of [s.init, s.update, s.body, s.otherwise]) {
			writtenParams(list, written);
		}
		for (const arm of s.cases) { writtenParams(arm.body, written); }
	}
}

function functionText(p: Printer, index: int32): string {
	const f = p.module.functions[index];
	p.fn = f;
	p.scope = p.taken.map((n) => n);
	p.params = f.params.map((x) => nameIn(p, p.scope, x.name));
	p.locals = f.locals.map((x) => nameIn(p, p.scope, x.name));
	let written: int32[] = [];
	writtenParams(f.body, written);
	let header: string[] = [];
	p.lines = [];
	for (let i = 0; i < f.params.length; i++) {
		const type = typeText(p, f.params[i].type);
		if (!written.includes(i)) {
			header.push(p.params[i] + " : " + type);
			continue;
		}
		const incoming = nameIn(p, p.scope, f.params[i].name + "_in");
		header.push(incoming + " : " + type);
		emit(p, 1, "var " + p.params[i] + " : " + type + " = " + incoming + ";");
	}
	stmtsText(p, f.body, 1);
	const result = f.result.kind == ShaderTypeKind.Void ? "" : " -> " + typeText(p, f.result);
	return "fn " + p.functions[index] + "(" + header.join(", ") + ")" + result + " {\n" +
		p.lines.map((l) => l + "\n").join("") + "}";
}

function builtinText(b: Builtin): string {
	return match (b) {
		Builtin.None => "",
		Builtin.VertexIndex => "vertex_index",
		Builtin.InstanceIndex => "instance_index",
		Builtin.Position => "position",
		Builtin.FrontFacing => "front_facing",
		Builtin.FragDepth => "frag_depth",
		Builtin.LocalInvocationId => "local_invocation_id",
		Builtin.LocalInvocationIndex => "local_invocation_index",
		Builtin.GlobalInvocationId => "global_invocation_id",
		Builtin.WorkgroupId => "workgroup_id",
		Builtin.NumWorkgroups => "num_workgroups",
		Builtin.SampleIndex => "sample_index",
		Builtin.SampleMask => "sample_mask",
	};
}

function interpolationText(io: ShaderIo): string {
	if (io.interpolation == Interpolation.Flat) { return " @interpolate(flat)"; }
	const linear = io.interpolation == Interpolation.Linear;
	if (!linear && io.sampling == Sampling.Center) { return ""; }
	const sampling = match (io.sampling) {
		Sampling.Center => "",
		Sampling.Centroid => ", centroid",
		Sampling.Sample => ", sample",
	};
	return " @interpolate(" + (linear ? "linear" : "perspective") + sampling + ")";
}

function interfaceText(p: Printer, io: ShaderIo, ordinal: int32): string {
	if (io.builtin != Builtin.None) {
		const wanted = builtinType(io.builtin);
		if (!sameShaderType(io.type, wanted)) {
			return refusal(p, "io '" + io.name + "' is " + typeText(p, io.type) + "; @builtin(" +
				builtinText(io.builtin) + ") is " + typeText(p, wanted));
		}
		return "@builtin(" + builtinText(io.builtin) + ")";
	}
	const location = "@location(" + String(ioLocation(io, ordinal)) + ")";
	const varying = io.stage == ShaderStage.Vertex && io.direction == IoDirection.Out ||
		io.stage == ShaderStage.Fragment && io.direction == IoDirection.In;
	return varying ? location + interpolationText(io) : location;
}

function resourceText(p: Printer, slot: BindingSlot): string {
	const r = p.module.resources[slot.resource];
	const head = "@binding(" + String(slot.binding) + ") @group(" + String(slot.group) + ") var";
	const name = p.resources[slot.resource];
	return match (r.kind) {
		ResourceKind.UniformBlock => head + "<uniform> " + name + " : " + typeText(p, r.type) + ";",
		ResourceKind.StorageBuffer => head + "<storage, " +
			(r.access == Access.Read ? "read" : "read_write") + "> " + name + " : " +
			typeText(p, r.type) + ";",
		ResourceKind.Sampler => head + " " + name + " : " +
			(r.samplerType == SamplerType.Comparison ? "sampler_comparison" : "sampler") + ";",
		ResourceKind.Texture | ResourceKind.StorageTexture => head + " " + name + " : " +
			typeText(p, r.type) + ";",
	};
}

function noteStructs(m: ShaderModule, t: ShaderType, structs: int32[]): void {
	if (t.kind == ShaderTypeKind.Struct && !structs.includes(t.structIndex)) {
		structs.push(t.structIndex);
		for (const f of m.structs[t.structIndex].members) { noteStructs(m, f.type, structs); }
	}
	for (const e of t.element) { noteStructs(m, e, structs); }
}

function stageText(m: ShaderModule, entry: int32): string {
	const e = m.entries[entry];
	const size = e.workgroupSize.map((n) => String(n)).join(", ");
	return match (e.stage) {
		ShaderStage.Vertex => "@vertex",
		ShaderStage.Fragment => "@fragment",
		ShaderStage.Compute => "@compute @workgroup_size(" + size + ")",
	};
}

export function printWgsl(m: ShaderModule, entry: int32, bindings: BindingSlot[]):
	Result<string, string> {
	const printable = printableEntry(m, entry);
	if (!printable.ok) { return Result.err("printWgsl: " + printable.error); }
	const reads = printable.value;
	const e = m.entries[entry];

	let p = new Printer();
	p.reserved = wgslReservedWords();
	p.module = m;
	p.stage = e.stage;
	p.taken = ["main_out", UPPER_LEFT, inverseName(2), inverseName(3), inverseName(4)];
	for (const s of m.structs) {
		p.structs.push(nameIn(p, p.taken, s.name));
		let scope: string[] = [];
		p.members.push(s.members.map((x) => nameIn(p, scope, x.name)));
	}
	p.constants = m.constants.map((c) => nameIn(p, p.taken, c.name));
	p.resources = m.resources.map((r) => nameIn(p, p.taken, r.name));
	p.ios = m.ios.map((io) => io.stage == e.stage ? nameIn(p, p.taken, io.name) : "");
	p.functions = m.functions.map((x) => nameIn(p, p.taken, x.name));
	p.workgroups = m.workgroups.map((w) => nameIn(p, p.taken, w.name));

	let functions: string[] = [];
	for (let i = 0; i < m.functions.length; i++) {
		if (reads.functions.includes(i)) { functions.push(functionText(p, i)); }
	}
	let structs = reads.structs.map((n) => n);
	let privates: string[] = [];
	let params: string[] = [];
	let copies: string[] = [];
	let outputs: string[] = [];
	let results: string[] = [];
	let ordinals = [0, 0];
	for (let i = 0; i < m.ios.length; i++) {
		const io = m.ios[i];
		if (io.stage != e.stage) { continue; }
		noteStructs(m, io.type, structs);
		const type = typeText(p, io.type);
		privates.push("var<private> " + p.ios[i] + " : " + type + ";");
		const input = io.direction == IoDirection.In;
		const side = input ? 0 : 1;
		const attribute = interfaceText(p, io, ordinals[side]);
		if (io.builtin == Builtin.None) { ordinals[side] += 1; }
		if (input) {
			const param = nameIn(p, p.taken, p.ios[i] + "_param");
			params.push(attribute + " " + param + " : " + type);
			copies.push("  " + p.ios[i] + " = " + param + ";\n");
		} else {
			outputs.push("  " + attribute + " " + p.ios[i] + " : " + type + ",\n");
			results.push(p.ios[i]);
		}
	}

	let decls: string[] = [];
	if (p.derivatives) { decls.push("diagnostic(off, derivative_uniformity);"); }
	for (let i = 0; i < m.structs.length; i++) {
		if (!structs.includes(i)) { continue; }
		let text = "struct " + p.structs[i] + " {\n";
		for (let k = 0; k < m.structs[i].members.length; k++) {
			text += "  " + p.members[i][k] + " : " + typeText(p, m.structs[i].members[k].type) +
				",\n";
		}
		decls.push(text + "}");
	}
	for (let i = 0; i < m.constants.length; i++) {
		if (!reads.constants.includes(i)) { continue; }
		const c = m.constants[i];
		decls.push("const " + p.constants[i] + " : " + typeText(p, c.type) + " = " +
			exprText(p, c.value) + ";");
	}
	for (const index of reads.resources) {
		if (!bindings.some((s) => s.resource == index)) {
			return Result.err("printWgsl: resource '" + m.resources[index].name +
				"' has no binding slot");
		}
	}
	let declared: int32[] = [];
	for (const s of bindings) {
		if (reads.resources.includes(s.resource) && !declared.includes(s.resource)) {
			declared.push(s.resource);
			decls.push(resourceText(p, s));
		}
	}
	for (const w of reads.workgroups) {
		decls.push("var<workgroup> " + p.workgroups[w] + " : " + typeText(p, m.workgroups[w].type) +
			";");
	}
	for (const v of privates) { decls.push(v); }
	if (p.upperLeft) {
		decls.push("fn " + UPPER_LEFT + "(m : mat4x4f) -> mat3x3f {\n" +
			"  return mat3x3f(m[0].xyz, m[1].xyz, m[2].xyz);\n}");
	}
	for (let n = 2; n <= 4; n++) {
		if (p.inverses.includes(n as int32)) { decls.push(inverseText(n as int32)); }
	}
	for (const text of functions) { decls.push(text); }
	if (outputs.length > 0) { decls.push("struct main_out {\n" + outputs.join("") + "}"); }
	const returned = outputs.length > 0 ? " -> main_out" : "";
	decls.push(stageText(m, entry) + "\nfn main(" + params.join(", ") + ")" + returned + " {\n" +
		copies.join("") + "  " + p.functions[e.functionIndex] + "();\n" +
		(outputs.length > 0 ? "  return main_out(" + results.join(", ") + ");\n" : "") + "}");
	if (p.error != "") { return Result.err(p.error); }
	return Result.ok(decls.join("\n\n") + "\n");
}
