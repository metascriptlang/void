import {
	Access,
	AssignOp,
	BinaryOp,
	Builtin,
	ConditionKind,
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
	irErrors,
} from "./ir";
import { BindingSlot, storageElementLayout, uniformBlockLayout } from "./layout";
import { readsFrom } from "./specialize";

export enum GlslTarget {
	Glsl430,
	Glsl300es,
}

const KEYWORDS = [
	"attribute", "const", "uniform", "varying", "buffer", "shared", "coherent", "volatile",
	"restrict", "readonly", "writeonly", "atomic_uint", "layout", "centroid", "flat", "smooth",
	"noperspective", "patch", "sample", "break", "continue", "do", "for", "while", "switch",
	"case", "default", "if", "else", "subroutine", "in", "out", "inout", "float", "double", "int",
	"uint", "void", "bool", "true", "false", "invariant", "precise", "discard", "return", "lowp",
	"mediump", "highp", "precision", "struct", "common", "partition", "active", "asm", "class",
	"union", "enum", "typedef", "template", "this", "resource", "goto", "inline", "noinline",
	"public", "static", "extern", "external", "interface", "long", "short", "half", "fixed",
	"unsigned", "superp", "input", "output", "filter", "sizeof", "cast", "namespace", "using",
];

const FUNCTIONS = [
	"radians", "degrees", "sin", "cos", "tan", "asin", "acos", "atan", "sinh", "cosh", "tanh",
	"asinh", "acosh", "atanh", "pow", "exp", "log", "exp2", "log2", "sqrt", "inversesqrt", "abs",
	"sign", "floor", "trunc", "round", "roundEven", "ceil", "fract", "mod", "modf", "min", "max",
	"clamp", "mix", "step", "smoothstep", "isnan", "isinf", "floatBitsToInt", "floatBitsToUint",
	"intBitsToFloat", "uintBitsToFloat", "fma", "frexp", "ldexp", "packUnorm2x16",
	"packSnorm2x16", "packUnorm4x8", "packSnorm4x8", "unpackUnorm2x16", "unpackSnorm2x16",
	"unpackUnorm4x8", "unpackSnorm4x8", "packHalf2x16", "unpackHalf2x16", "packDouble2x32",
	"unpackDouble2x32", "length", "distance", "dot", "cross", "normalize", "ftransform",
	"faceforward", "reflect", "refract", "matrixCompMult", "outerProduct", "transpose",
	"determinant", "inverse", "lessThan", "lessThanEqual", "greaterThan", "greaterThanEqual",
	"equal", "notEqual", "any", "all", "not", "uaddCarry", "usubBorrow", "umulExtended",
	"imulExtended", "bitfieldExtract", "bitfieldInsert", "bitfieldReverse", "bitCount", "findLSB",
	"findMSB", "textureSize", "textureQueryLod", "textureQueryLevels", "textureSamples",
	"texture", "textureProj", "textureLod", "textureOffset", "texelFetch", "texelFetchOffset",
	"textureProjOffset", "textureLodOffset", "textureProjLod", "textureProjLodOffset",
	"textureGrad", "textureGradOffset", "textureProjGrad", "textureProjGradOffset",
	"textureGather", "textureGatherOffset", "textureGatherOffsets", "texture1D", "texture2D",
	"texture3D", "textureCube", "texture2DLod", "texture2DProj", "shadow1D", "shadow2D",
	"atomicCounterIncrement", "atomicCounterDecrement", "atomicCounter", "atomicAdd", "atomicMin",
	"atomicMax", "atomicAnd", "atomicOr", "atomicXor", "atomicExchange", "atomicCompSwap",
	"imageSize", "imageSamples", "imageLoad", "imageStore", "imageAtomicAdd", "imageAtomicMin",
	"imageAtomicMax", "imageAtomicAnd", "imageAtomicOr", "imageAtomicXor", "imageAtomicExchange",
	"imageAtomicCompSwap", "dFdx", "dFdy", "fwidth", "dFdxFine", "dFdyFine", "fwidthFine",
	"dFdxCoarse", "dFdyCoarse", "fwidthCoarse", "interpolateAtCentroid", "interpolateAtSample",
	"interpolateAtOffset", "noise1", "noise2", "noise3", "noise4", "EmitStreamVertex",
	"EndStreamPrimitive", "EmitVertex", "EndPrimitive", "barrier", "memoryBarrier",
	"memoryBarrierAtomicCounter", "memoryBarrierBuffer", "memoryBarrierShared",
	"memoryBarrierImage", "groupMemoryBarrier",
];

const SAMPLED_SHAPES = ["1D", "2D", "3D", "Cube", "2DRect", "1DArray", "2DArray", "CubeArray",
	"Buffer", "2DMS", "2DMSArray"];

const SHADOW_TYPES = ["sampler1DShadow", "sampler2DShadow", "samplerCubeShadow",
	"sampler1DArrayShadow", "sampler2DArrayShadow", "samplerCubeArrayShadow", "sampler2DRectShadow",
	"sampler3DRect", "samplerExternalOES"];

const SWIZZLE = ["x", "y", "z", "w"];

function isTypeName(name: string): boolean {
	for (const base of ["vec", "ivec", "uvec", "bvec", "dvec", "hvec", "fvec", "mat", "dmat"]) {
		if (!name.startsWith(base)) { continue; }
		const rest = name.substring(base.length);
		const digit = (at: int32) => rest.length > at && "234".includes(rest.substring(at, at + 1));
		if (rest.length == 1 && digit(0)) { return true; }
		if (rest.length == 3 && digit(0) && rest.substring(1, 2) == "x" && digit(2)) { return true; }
	}
	for (const prefix of ["sampler", "isampler", "usampler", "image", "iimage", "uimage"]) {
		if (name.startsWith(prefix) && SAMPLED_SHAPES.includes(name.substring(prefix.length))) {
			return true;
		}
	}
	return SHADOW_TYPES.includes(name);
}

function isReserved(name: string): boolean {
	return KEYWORDS.includes(name) || FUNCTIONS.includes(name) || isTypeName(name);
}

enum Nesting {
	Loop,
	Switch,
}

class Pair {
	texture: int32 = -1;
	sampler: int32 = -1;
	name: string = "";
	unit: int32 = 0;
}

class Printer {
	module: ShaderModule = new ShaderModule();
	stage: ShaderStage = ShaderStage.Vertex;
	es: boolean = false;
	error: string = "";
	globals: string[] = [];
	structNames: string[] = [];
	fieldNames: string[][] = [];
	constantNames: string[] = [];
	resourceNames: string[] = [];
	blockNames: string[] = [];
	blockOffsets: int32[][] = [];
	ioNames: string[] = [];
	functionNames: string[] = [];
	effects: int32[] = [];
	pairs: Pair[] = [];
	scope: string[] = [];
	current: ShaderFunction = new ShaderFunction();
	nesting: Nesting[] = [];
}

function fail(p: Printer, message: string): string {
	if (p.error == "") { p.error = "printGlsl: " + message; }
	return "";
}

function claim(p: Printer, taken: string[], name: string): string {
	if (name.startsWith("gl_") || name.includes("__")) {
		return fail(p, "'" + name + "' is a name GLSL reserves to itself");
	}
	let candidate = name;
	let n = 1;
	while (isReserved(candidate) || taken.includes(candidate)) {
		candidate = name + "_" + String(n);
		n++;
	}
	taken.push(candidate);
	return candidate;
}

function claimFixed(p: Printer, name: string, what: string): string {
	const named = claim(p, p.globals, name);
	if (named != name) {
		return fail(p, what + " '" + name + "' is a word GLSL holds or another name takes, " +
			"and GL binds it by that name");
	}
	return named;
}

function scalarName(s: ScalarKind): string {
	return match (s) {
		ScalarKind.F32 => "float",
		ScalarKind.I32 => "int",
		ScalarKind.U32 => "uint",
		ScalarKind.Bool => "bool",
	};
}

function vectorPrefix(s: ScalarKind): string {
	return match (s) {
		ScalarKind.F32 => "",
		ScalarKind.I32 => "i",
		ScalarKind.U32 => "u",
		ScalarKind.Bool => "b",
	};
}

function innermost(t: ShaderType): ShaderType {
	return t.kind == ShaderTypeKind.Array ? innermost(t.element[0]) : t;
}

function arraySuffix(p: Printer, t: ShaderType): string {
	if (t.kind != ShaderTypeKind.Array) { return ""; }
	if (p.es && t.element[0].kind == ShaderTypeKind.Array) {
		return fail(p, "an array of arrays, which GLSL ES 3.00 has not");
	}
	return "[" + String(t.length) + "]" + arraySuffix(p, t.element[0]);
}

function imageFormat(format: TexelFormat): string {
	return match (format) {
		TexelFormat.Rgba8unorm => "rgba8",
		TexelFormat.Rgba8snorm => "rgba8_snorm",
		TexelFormat.Rgba8uint => "rgba8ui",
		TexelFormat.Rgba16float => "rgba16f",
		TexelFormat.Rgba32float => "rgba32f",
		TexelFormat.R32float => "r32f",
		TexelFormat.R32uint => "r32ui",
		TexelFormat.Rg32float => "rg32f",
	};
}

function texelType(format: TexelFormat): string {
	return format == TexelFormat.Rgba8uint || format == TexelFormat.R32uint ? "uvec4" : "vec4";
}

function typeName(p: Printer, t: ShaderType): string {
	return match (t.kind) {
		ShaderTypeKind.Void => "void",
		ShaderTypeKind.Scalar => scalarName(t.scalar),
		ShaderTypeKind.Vector => vectorPrefix(t.scalar) + "vec" + String(t.rows),
		ShaderTypeKind.Matrix => t.columns == t.rows ? "mat" + String(t.rows) :
			"mat" + String(t.columns) + "x" + String(t.rows),
		ShaderTypeKind.Array => typeName(p, innermost(t)),
		ShaderTypeKind.RuntimeArray => fail(p, "a runtime array is only a storage buffer"),
		ShaderTypeKind.Struct => p.structNames[t.structIndex],
		ShaderTypeKind.Texture | ShaderTypeKind.Sampler =>
			fail(p, "a " + t.kind.toString() + " outside a texture operation: GL samples through " +
				"combined samplers"),
		ShaderTypeKind.StorageTexture => t.shape == TextureShape.D2 ?
			(texelType(t.format) == "uvec4" ? "uimage2D" : "image2D") :
			fail(p, "a storage texture of shape " + t.shape.toString()),
	};
}

// GLSL ES 3.00 §4.5.3: a fragment shader has no default float precision and no sampler type but
// sampler2D and samplerCube has one in either stage, so those carry `highp` as the committed
// output does.
function precision(p: Printer, t: ShaderType): string {
	if (!p.es) { return ""; }
	const own = innermost(t);
	if (own.kind == ShaderTypeKind.StorageTexture) { return "highp "; }
	const numeric = (own.kind == ShaderTypeKind.Scalar || own.kind == ShaderTypeKind.Vector ||
		own.kind == ShaderTypeKind.Matrix) && own.scalar != ScalarKind.Bool;
	return p.stage == ShaderStage.Fragment && numeric ? "highp " : "";
}

function declaration(p: Printer, t: ShaderType, name: string): string {
	return precision(p, t) + typeName(p, t) + " " + name + arraySuffix(p, t);
}

function repeated(text: string, count: int32): string {
	let parts: string[] = [];
	for (let i = 0; i < count; i++) { parts.push(text); }
	return parts.join(", ");
}

function indent(depth: int32): string { return "    ".repeat(depth); }

function isNone(e: ShaderExpr): boolean {
	return e.kind == ExprKind.Literal && e.type.kind == ShaderTypeKind.Void;
}

function scalarLiteral(p: Printer, s: ScalarKind, v: float64): string {
	if (v - v != 0.0) { return fail(p, "a literal that is not finite"); }
	return match (s) {
		ScalarKind.F32 => {
			const text = String(v);
			return text.includes(".") || text.includes("e") ? text : text + ".0";
		},
		ScalarKind.I32 => String(v as int64),
		ScalarKind.U32 => String(v as int64) + "u",
		ScalarKind.Bool => v != 0.0 ? "true" : "false",
	};
}

function literalText(p: Printer, e: ShaderExpr): string {
	const t = e.type;
	const one = scalarLiteral(p, t.scalar, e.value);
	return match (t.kind) {
		ShaderTypeKind.Scalar => one,
		ShaderTypeKind.Vector => typeName(p, t) + "(" + one + ")",
		ShaderTypeKind.Matrix => typeName(p, t) + "(" +
			repeated("vec" + String(t.rows) + "(" + one + ")", t.columns) + ")",
		_ => fail(p, "a literal of " + t.kind.toString()),
	};
}

function rootOf(e: ShaderExpr): ShaderExpr {
	const through = e.kind == ExprKind.Field || e.kind == ExprKind.Swizzle ||
		e.kind == ExprKind.Index;
	return through && e.operands.length > 0 ? rootOf(e.operands[0]) : e;
}

function stmtsHaveEffect(p: Printer, stmts: ShaderStmt[]): boolean {
	for (const s of stmts) {
		const root = rootOf(s.target).kind;
		const writes = s.kind == StmtKind.Assign &&
			(root == ExprKind.Io || root == ExprKind.Resource);
		if (writes || hasEffect(p, s.expr) || hasEffect(p, s.target)) { return true; }
		for (const list of [s.init, s.update, s.body, s.otherwise]) {
			if (stmtsHaveEffect(p, list)) { return true; }
		}
		for (const k of s.cases) {
			if (stmtsHaveEffect(p, k.body)) { return true; }
		}
	}
	return false;
}

function hasEffect(p: Printer, e: ShaderExpr): boolean {
	if (e.kind == ExprKind.Intrinsic && e.intrinsic == Intrinsic.TextureStore) { return true; }
	if (e.kind == ExprKind.Call) {
		if (p.effects[e.index] == 0) {
			p.effects[e.index] = 1;
			p.effects[e.index] = stmtsHaveEffect(p, p.module.functions[e.index].body) ? 2 : 1;
		}
		if (p.effects[e.index] == 2) { return true; }
	}
	return e.operands.some((o) => hasEffect(p, o));
}

function pure(p: Printer, what: string, operands: ShaderExpr[]): void {
	if (operands.some((o) => hasEffect(p, o))) {
		fail(p, "'" + what + "' prints an operand more or fewer times than the IR evaluates " +
			"it in GLSL, and one of them has an effect");
	}
}

function operand(p: Printer, e: ShaderExpr): string {
	const text = expr(p, e);
	const compound = e.kind == ExprKind.Binary || e.kind == ExprKind.Unary ||
		e.kind == ExprKind.Conditional || text.startsWith("-");
	return compound ? "(" + text + ")" : text;
}

function postfixBase(p: Printer, e: ShaderExpr): string {
	return e.kind == ExprKind.Literal ? "(" + expr(p, e) + ")" : operand(p, e);
}

function isScalarKind(t: ShaderType, s: ScalarKind): boolean {
	return (t.kind == ShaderTypeKind.Scalar || t.kind == ShaderTypeKind.Vector) && t.scalar == s;
}

function remainder(p: Printer, a: ShaderExpr, b: ShaderExpr): string {
	if (isScalarKind(a.type, ScalarKind.F32)) {
		pure(p, "%", [a, b]);
		return operand(p, a) + " - " + operand(p, b) + " * trunc(" + operand(p, a) + " / " +
			operand(p, b) + ")";
	}
	if (isScalarKind(a.type, ScalarKind.U32)) { return operand(p, a) + " % " + operand(p, b); }
	return fail(p, "'%' of " + a.type.scalar.toString() + ": GLSL leaves a negative operand " +
		"undefined");
}

function binaryText(p: Printer, e: ShaderExpr): string {
	const a = e.operands[0];
	const b = e.operands[1];
	const op = match (e.binary) {
		BinaryOp.Add => "+",
		BinaryOp.Sub => "-",
		BinaryOp.Mul => "*",
		BinaryOp.Div => "/",
		BinaryOp.Mod => "%",
		BinaryOp.BitAnd => "&",
		BinaryOp.LogicalAnd => "&&",
		BinaryOp.LogicalOr => "||",
		BinaryOp.Equal => "==",
		BinaryOp.NotEqual => "!=",
		BinaryOp.Less => "<",
		BinaryOp.LessEqual => "<=",
		BinaryOp.Greater => ">",
		BinaryOp.GreaterEqual => ">=",
	};
	if (e.binary == BinaryOp.Mod) { return remainder(p, a, b); }
	const folds = e.type.kind == ShaderTypeKind.Scalar && a.type.kind == ShaderTypeKind.Vector;
	if (folds && e.binary != BinaryOp.Equal && e.binary != BinaryOp.NotEqual) {
		return fail(p, "'" + op + "' of two vectors into one bool");
	}
	return operand(p, a) + " " + op + " " + operand(p, b);
}

function converted(p: Printer, text: string, from: string, to: ShaderType): string {
	const target = typeName(p, to);
	return from == target ? text : target + "(" + text + ")";
}

function intText(p: Printer, e: ShaderExpr): string {
	if (e.kind == ExprKind.Literal && e.type.kind == ShaderTypeKind.Scalar) {
		return String(e.value as int64);
	}
	const t = e.type;
	if (t.scalar == ScalarKind.I32) { return expr(p, e); }
	const target = t.kind == ShaderTypeKind.Vector ? "ivec" + String(t.rows) : "int";
	return target + "(" + expr(p, e) + ")";
}

function narrowed(text: string, to: ShaderType): string {
	const rows = to.kind == ShaderTypeKind.Vector ? to.rows : 1;
	return rows == 4 ? text : text + "." + SWIZZLE.slice(0, rows).join("");
}

function pairOf(p: Printer, texture: ShaderExpr, sampler: ShaderExpr | null): Pair {
	let none = new Pair();
	if (texture.kind != ExprKind.Resource) {
		fail(p, "a texture passed as a value: GL samples through combined samplers of bindings");
		return none;
	}
	const named = p.module.resources[texture.index].name;
	for (const pair of p.pairs) {
		if (pair.texture != texture.index) { continue; }
		const chosen = sampler === null ? !isComparison(p, pair) :
			sampler.kind == ExprKind.Resource && pair.sampler == sampler.index;
		if (chosen) { return pair; }
	}
	fail(p, "texture '" + named + "' has no combined sampler in this stage's binding slots");
	return none;
}

function isComparison(p: Printer, pair: Pair): boolean {
	return pair.sampler >= 0 &&
		p.module.resources[pair.sampler].samplerType == SamplerType.Comparison;
}

function samplerOperand(e: ShaderExpr): ShaderExpr | null {
	for (const o of e.operands) {
		if (o.type.kind == ShaderTypeKind.Sampler) { return o; }
	}
	return null;
}

function withoutSampler(e: ShaderExpr): ShaderExpr[] {
	return e.operands.filter((o) => o.type.kind != ShaderTypeKind.Sampler);
}

function sizeOf(p: Printer, e: ShaderExpr): string {
	const args = withoutSampler(e);
	const t = args[0].type;
	if (t.kind == ShaderTypeKind.StorageTexture) {
		return converted(p, "imageSize(" + expr(p, args[0]) + ")", "ivec2", e.type);
	}
	if (t.kind != ShaderTypeKind.Texture) {
		return fail(p, "TextureDimensions of a " + t.kind.toString());
	}
	const pair = pairOf(p, args[0], samplerOperand(e));
	if (t.shape == TextureShape.Multisampled2d) {
		return converted(p, "textureSize(" + pair.name + ")", "ivec2", e.type);
	}
	const level = args.length > 1 ? intText(p, args[1]) : "0";
	const call = "textureSize(" + pair.name + ", " + level + ")";
	if (t.shape == TextureShape.D3) { return converted(p, call, "ivec3", e.type); }
	const layered = t.shape == TextureShape.D2Array || t.shape == TextureShape.Depth2dArray ||
		t.shape == TextureShape.CubeArray;
	return converted(p, layered ? call + ".xy" : call, "ivec2", e.type);
}

function loadOf(p: Printer, e: ShaderExpr): string {
	const args = withoutSampler(e);
	const t = args[0].type;
	if (args.length < 2) { return fail(p, "TextureLoad without coordinates"); }
	if (t.kind == ShaderTypeKind.StorageTexture) {
		return narrowed("imageLoad(" + expr(p, args[0]) + ", " + intText(p, args[1]) + ")", e.type);
	}
	if (t.kind != ShaderTypeKind.Texture) { return fail(p, "TextureLoad of a " + t.kind.toString()); }
	const pair = pairOf(p, args[0], samplerOperand(e));
	if (isComparison(p, pair)) {
		return fail(p, "TextureLoad through comparison sampler pair '" + pair.name + "'");
	}
	const level = args.length > 2 ? intText(p, args[2]) : "0";
	const fetch = "texelFetch(" + pair.name + ", " + intText(p, args[1]) + ", " + level + ")";
	return match (t.shape) {
		TextureShape.D2 | TextureShape.Depth2d | TextureShape.D3 | TextureShape.Multisampled2d =>
			narrowed(fetch, e.type),
		_ => fail(p, "TextureLoad of a " + t.shape.toString() + " texture: the IR names no layer"),
	};
}

function sampleOf(p: Printer, e: ShaderExpr): string {
	if (e.operands.length != 3) {
		return fail(p, "TextureSample takes a texture, a sampler and coordinates");
	}
	const [texture, sampler, at] = [e.operands[0], e.operands[1], e.operands[2]];
	if (texture.type.kind != ShaderTypeKind.Texture || sampler.type.kind != ShaderTypeKind.Sampler) {
		return fail(p, "TextureSample takes a texture and a sampler first");
	}
	if (texture.type.shape == TextureShape.Multisampled2d) {
		return fail(p, "TextureSample of a multisampled texture");
	}
	const pair = pairOf(p, texture, sampler);
	if (isComparison(p, pair)) {
		return fail(p, "TextureSample through a comparison sampler, which needs a depth reference");
	}
	return narrowed("texture(" + pair.name + ", " + expr(p, at) + ")", e.type);
}

function compareOf(p: Printer, e: ShaderExpr, level: boolean): string {
	const name = e.intrinsic.toString();
	if (e.operands.length != 4) {
		return fail(p, name + " takes a texture, a sampler, coordinates and a depth reference");
	}
	const [texture, sampler, at, reference] = [e.operands[0], e.operands[1], e.operands[2],
		e.operands[3]];
	if (texture.type.kind != ShaderTypeKind.Texture || sampler.type.kind != ShaderTypeKind.Sampler) {
		return fail(p, name + " takes a texture and a sampler first");
	}
	if (!level && p.stage != ShaderStage.Fragment) {
		return fail(p, name + " outside a fragment stage");
	}
	const pair = pairOf(p, texture, sampler);
	if (!isComparison(p, pair)) {
		return fail(p, name + " through sampler pair '" + pair.name + "', whose sampler is no " +
			"comparison sampler");
	}
	const coords = expr(p, at) + ", " + expr(p, reference);
	return match (texture.type.shape) {
		TextureShape.Depth2d => level ?
			"textureLod(" + pair.name + ", vec3(" + coords + "), 0.0)" :
			"texture(" + pair.name + ", vec3(" + coords + "))",
		TextureShape.Depth2dArray => level ?
			"textureGrad(" + pair.name + ", vec4(" + coords + "), vec2(0.0), vec2(0.0))" :
			"texture(" + pair.name + ", vec4(" + coords + "))",
		TextureShape.DepthCube => level ?
			"textureGrad(" + pair.name + ", vec4(" + coords + "), vec3(0.0), vec3(0.0))" :
			"texture(" + pair.name + ", vec4(" + coords + "))",
		_ => fail(p, name + " of a " + texture.type.shape.toString() + " texture, which holds " +
			"no depth"),
	};
}

function storeOf(p: Printer, e: ShaderExpr): string {
	if (e.operands.length != 3 || e.operands[0].type.kind != ShaderTypeKind.StorageTexture) {
		return fail(p, "TextureStore takes a storage texture, coordinates and a value");
	}
	const texel = texelType(e.operands[0].type.format);
	const value = e.operands[2];
	const rows = value.type.kind == ShaderTypeKind.Vector ? value.type.rows : 1;
	const zero = texel == "uvec4" ? "0u" : "0.0";
	const written = rows == 4 ? converted(p, expr(p, value), typeName(p, value.type),
		texel == "uvec4" ? vectorTypeOf(ScalarKind.U32) : vectorTypeOf(ScalarKind.F32)) :
		texel + "(" + expr(p, value) + ", " + repeated(zero, 4 - rows) + ")";
	return "imageStore(" + expr(p, e.operands[0]) + ", " + intText(p, e.operands[1]) + ", " +
		written + ")";
}

function vectorTypeOf(s: ScalarKind): ShaderType {
	let t = new ShaderType();
	t.kind = ShaderTypeKind.Vector;
	t.scalar = s;
	t.rows = 4;
	return t;
}

function intrinsicName(op: Intrinsic): string {
	return match (op) {
		Intrinsic.Abs => "abs",
		Intrinsic.Floor => "floor",
		Intrinsic.Ceil => "ceil",
		Intrinsic.Trunc => "trunc",
		Intrinsic.Round => "roundEven",
		Intrinsic.Fract => "fract",
		Intrinsic.Sqrt => "sqrt",
		Intrinsic.InverseSqrt => "inversesqrt",
		Intrinsic.Exp => "exp",
		Intrinsic.Exp2 => "exp2",
		Intrinsic.Log => "log",
		Intrinsic.Log2 => "log2",
		Intrinsic.Pow => "pow",
		Intrinsic.Sin => "sin",
		Intrinsic.Cos => "cos",
		Intrinsic.Tan => "tan",
		Intrinsic.Asin => "asin",
		Intrinsic.Acos => "acos",
		Intrinsic.Atan | Intrinsic.Atan2 => "atan",
		Intrinsic.Sinh => "sinh",
		Intrinsic.Cosh => "cosh",
		Intrinsic.Tanh => "tanh",
		Intrinsic.Degrees => "degrees",
		Intrinsic.Radians => "radians",
		Intrinsic.Min => "min",
		Intrinsic.Max => "max",
		Intrinsic.Clamp => "clamp",
		Intrinsic.Mix => "mix",
		Intrinsic.Step => "step",
		Intrinsic.Smoothstep => "smoothstep",
		Intrinsic.Dot => "dot",
		Intrinsic.Cross => "cross",
		Intrinsic.Length => "length",
		Intrinsic.Distance => "distance",
		Intrinsic.Normalize => "normalize",
		Intrinsic.Reflect => "reflect",
		Intrinsic.Refract => "refract",
		Intrinsic.FaceForward => "faceforward",
		Intrinsic.Transpose => "transpose",
		Intrinsic.Determinant => "determinant",
		Intrinsic.LessThanEqual => "lessThanEqual",
		Intrinsic.Dpdx => "dFdx",
		Intrinsic.Dpdy => "dFdy",
		Intrinsic.Fwidth => "fwidth",
		_ => "",
	};
}

function selectText(p: Printer, e: ShaderExpr): string {
	const [falseValue, trueValue, condition] = [e.operands[0], e.operands[1], e.operands[2]];
	if (condition.type.kind == ShaderTypeKind.Vector) {
		if (!isScalarKind(e.type, ScalarKind.F32)) {
			return fail(p, "Select of " + e.type.scalar.toString() + " by a bool vector: GLSL " +
				"mixes float vectors only");
		}
		return "mix(" + expr(p, falseValue) + ", " + expr(p, trueValue) + ", " +
			expr(p, condition) + ")";
	}
	pure(p, "select", [falseValue, trueValue]);
	return "(" + operand(p, condition) + " ? " + operand(p, trueValue) + " : " +
		operand(p, falseValue) + ")";
}

function intrinsicText(p: Printer, e: ShaderExpr): string {
	const args = () => e.operands.map((o) => expr(p, o)).join(", ");
	const derivative = e.intrinsic == Intrinsic.Dpdx || e.intrinsic == Intrinsic.Dpdy ||
		e.intrinsic == Intrinsic.Fwidth;
	if (derivative && p.stage != ShaderStage.Fragment) {
		return fail(p, e.intrinsic.toString() + " outside a fragment stage");
	}
	return match (e.intrinsic) {
		Intrinsic.Sign => converted(p, "sign(" + args() + ")", typeName(p, e.operands[0].type),
			e.type),
		Intrinsic.Saturate => "clamp(" + args() + ", 0.0, 1.0)",
		Intrinsic.Fma => p.es ? "(" + operand(p, e.operands[0]) + " * " +
			operand(p, e.operands[1]) + " + " + operand(p, e.operands[2]) + ")" :
			"fma(" + args() + ")",
		Intrinsic.Inverse => {
			const t = e.operands[0].type;
			if (t.kind != ShaderTypeKind.Matrix || t.columns != t.rows) {
				return fail(p, "Inverse of a " + t.kind.toString() + " that is no square matrix");
			}
			return "inverse(" + args() + ")";
		},
		Intrinsic.UpperLeft3x3 => "mat3(" + args() + ")",
		Intrinsic.Select => selectText(p, e),
		Intrinsic.TextureSample => sampleOf(p, e),
		Intrinsic.TextureLoad => loadOf(p, e),
		Intrinsic.TextureStore => storeOf(p, e),
		Intrinsic.TextureDimensions => sizeOf(p, e),
		Intrinsic.TextureSampleCompare => compareOf(p, e, false),
		Intrinsic.TextureSampleCompareLevel => compareOf(p, e, true),
		_ => intrinsicName(e.intrinsic) + "(" + args() + ")",
	};
}

function constructText(p: Printer, e: ShaderExpr): string {
	const t = e.type;
	const args = e.operands.map((o) => expr(p, o)).join(", ");
	if (t.kind == ShaderTypeKind.Struct) { return p.structNames[t.structIndex] + "(" + args + ")"; }
	if (t.kind == ShaderTypeKind.Array) {
		return typeName(p, t) + arraySuffix(p, t) + "(" + args + ")";
	}
	if (t.kind != ShaderTypeKind.Vector && t.kind != ShaderTypeKind.Matrix) {
		return fail(p, "Construct of a " + t.kind.toString());
	}
	if (t.kind == ShaderTypeKind.Matrix && e.operands.length == 1 &&
		e.operands[0].type.kind == ShaderTypeKind.Scalar) {
		return fail(p, "a matrix built from one scalar");
	}
	return typeName(p, t) + "(" + args + ")";
}

function blockRow(p: Printer, r: int32, row: string): string {
	return p.blockNames[r] + "[" + row + "]";
}

function matrixRows(p: Printer, r: int32, t: ShaderType, row: (column: int32) => string): string {
	let columns: string[] = [];
	for (let c = 0; c < t.columns; c++) {
		const whole = blockRow(p, r, row(c));
		columns.push(t.rows == 4 ? whole : whole + "." + SWIZZLE.slice(0, t.rows).join(""));
	}
	return typeName(p, t) + "(" + columns.join(", ") + ")";
}

function stride(t: ShaderType): int32 { return t.kind == ShaderTypeKind.Matrix ? t.columns : 1; }

function memberText(p: Printer, e: ShaderExpr): string {
	const r = e.index;
	const t = e.type;
	const offset = p.blockOffsets[r][e.member];
	const row = offset / 16;
	if (t.kind == ShaderTypeKind.Array) {
		let elements: string[] = [];
		for (let i = 0; i < t.length; i++) {
			elements.push(elementText(p, r, t.element[0], row + i * stride(t.element[0]), ""));
		}
		return typeName(p, t) + arraySuffix(p, t) + "(" + elements.join(", ") + ")";
	}
	if (t.kind == ShaderTypeKind.Matrix) { return elementText(p, r, t, row, ""); }
	const lane = (offset % 16) / 4;
	const width = t.kind == ShaderTypeKind.Vector ? t.rows : 1;
	const whole = blockRow(p, r, String(row));
	return lane == 0 && width == 4 ? whole :
		whole + "." + SWIZZLE.slice(lane, lane + width).join("");
}

function elementText(p: Printer, r: int32, t: ShaderType, row: int32, index: string): string {
	const at = (column: int32) => {
		const fixed = row + column;
		if (index == "") { return String(fixed); }
		const scaled = stride(t) == 1 ? index : index + " * " + String(stride(t));
		return fixed == 0 ? scaled : String(fixed) + " + " + scaled;
	};
	return t.kind == ShaderTypeKind.Matrix ? matrixRows(p, r, t, at) : blockRow(p, r, at(0));
}

function indexText(p: Printer, e: ShaderExpr): string {
	const base = e.operands[0];
	const at = e.operands[1];
	if (base.kind != ExprKind.BlockMember || base.type.kind != ShaderTypeKind.Array) {
		return postfixBase(p, base) + "[" + expr(p, at) + "]";
	}
	const element = base.type.element[0];
	const row = p.blockOffsets[base.index][base.member] / 16;
	if (at.kind == ExprKind.Literal) {
		return elementText(p, base.index, element, row + (at.value as int32) * stride(element), "");
	}
	if (element.kind == ShaderTypeKind.Matrix) { pure(p, "[]", [at]); }
	const index = at.type.scalar == ScalarKind.I32 ? operand(p, at) : intText(p, at);
	return elementText(p, base.index, element, row, index);
}

function builtinRead(p: Printer, io: ShaderIo): [string, string] {
	const desktop = (name: string, ty: string): [string, string] =>
		p.es ? [fail(p, io.builtin.toString() + ": GLSL ES 3.00 has no " + name), ""] : [name, ty];
	return match (io.builtin) {
		Builtin.VertexIndex => ["gl_VertexID", "int"],
		Builtin.InstanceIndex => ["gl_InstanceID", "int"],
		Builtin.Position => p.stage == ShaderStage.Vertex ? ["gl_Position", "vec4"] :
			["gl_FragCoord", "vec4"],
		Builtin.FrontFacing => ["gl_FrontFacing", "bool"],
		Builtin.FragDepth => ["gl_FragDepth", "float"],
		Builtin.LocalInvocationId => ["gl_LocalInvocationID", "uvec3"],
		Builtin.LocalInvocationIndex => ["gl_LocalInvocationIndex", "uint"],
		Builtin.GlobalInvocationId => ["gl_GlobalInvocationID", "uvec3"],
		Builtin.WorkgroupId => ["gl_WorkGroupID", "uvec3"],
		Builtin.NumWorkgroups => ["gl_NumWorkGroups", "uvec3"],
		Builtin.SampleIndex => desktop("gl_SampleID", "int"),
		Builtin.SampleMask => desktop(io.direction == IoDirection.In ? "gl_SampleMaskIn[0]" :
			"gl_SampleMask[0]", "int"),
		Builtin.None => [fail(p, "io '" + io.name + "' is no builtin"), ""],
	};
}

function ioText(p: Printer, index: int32): string {
	const io = p.module.ios[index];
	if (io.stage != p.stage) {
		return fail(p, "io '" + io.name + "' belongs to the " + io.stage.toString() + " stage");
	}
	if (io.builtin == Builtin.None) { return p.ioNames[index]; }
	const [name, ty] = builtinRead(p, io);
	return converted(p, name, ty, io.type);
}

function resourceText(p: Printer, index: int32): string {
	const r = p.module.resources[index];
	return match (r.kind) {
		ResourceKind.UniformBlock => fail(p, "uniform block '" + r.name + "' read whole"),
		ResourceKind.StorageBuffer => p.resourceNames[index] + ".data",
		ResourceKind.StorageTexture => p.resourceNames[index],
		_ => fail(p, r.kind.toString() + " '" + r.name + "' outside a texture operation: GL " +
			"samples through combined samplers"),
	};
}

function expr(p: Printer, e: ShaderExpr): string {
	return match (e.kind) {
		ExprKind.Literal => literalText(p, e),
		ExprKind.Local => e.index >= 0 && e.index < p.current.locals.length ?
			p.scope[p.current.params.length + e.index] : fail(p, "a local out of range"),
		ExprKind.Param => p.scope[e.index],
		ExprKind.Constant => p.constantNames[e.index],
		ExprKind.Io => ioText(p, e.index),
		ExprKind.Resource => resourceText(p, e.index),
		ExprKind.BlockMember => memberText(p, e),
		ExprKind.Unary => (e.unary == UnaryOp.Negate ? "-" : "!") + operand(p, e.operands[0]),
		ExprKind.Binary => binaryText(p, e),
		ExprKind.Conditional => operand(p, e.operands[0]) + " ? " + operand(p, e.operands[1]) +
			" : " + operand(p, e.operands[2]),
		ExprKind.Call => p.functionNames[e.index] + "(" +
			e.operands.map((o) => expr(p, o)).join(", ") + ")",
		ExprKind.Intrinsic => intrinsicText(p, e),
		ExprKind.Construct => constructText(p, e),
		ExprKind.Convert => {
			const t = e.type;
			if (t.kind != ShaderTypeKind.Scalar && t.kind != ShaderTypeKind.Vector) {
				return fail(p, "Convert to a " + t.kind.toString());
			}
			return typeName(p, t) + "(" + expr(p, e.operands[0]) + ")";
		},
		ExprKind.Field => {
			const base = e.operands[0];
			if (base.type.kind != ShaderTypeKind.Struct) {
				return fail(p, "Field of a " + base.type.kind.toString());
			}
			return postfixBase(p, base) + "." + p.fieldNames[base.type.structIndex][e.index];
		},
		ExprKind.Swizzle => postfixBase(p, e.operands[0]) + "." +
			e.components.map((c) => SWIZZLE[c]).join(""),
		ExprKind.Index => indexText(p, e),
	};
}

function targetText(p: Printer, s: ShaderStmt): string {
	const root = rootOf(s.target);
	if (root.kind == ExprKind.BlockMember) {
		return fail(p, "uniform block '" + p.module.resources[root.index].name + "' written");
	}
	if (root.kind != ExprKind.Io) { return expr(p, s.target); }
	const io = p.module.ios[root.index];
	if (io.direction == IoDirection.In) {
		return fail(p, "io '" + io.name + "' is a stage input, which GLSL only reads");
	}
	if (io.builtin != Builtin.SampleMask) { return expr(p, s.target); }
	if (s.target.kind != ExprKind.Io || s.assign != AssignOp.Set) {
		return fail(p, "SampleMask written other than whole by '='");
	}
	return builtinRead(p, io)[0];
}

function assignment(p: Printer, s: ShaderStmt): string {
	const target = targetText(p, s);
	const value = s.expr;
	const root = rootOf(s.target);
	if (root.kind == ExprKind.Io && p.module.ios[root.index].builtin == Builtin.SampleMask) {
		return target + " = int(" + expr(p, value) + ")";
	}
	return match (s.assign) {
		AssignOp.Set => target + " = " + expr(p, value),
		AssignOp.Add => target + " += " + expr(p, value),
		AssignOp.Sub => target + " -= " + expr(p, value),
		AssignOp.Mul => target + " *= " + expr(p, value),
		AssignOp.Div => target + " /= " + expr(p, value),
		AssignOp.Mod => target + " = " + remainder(p, s.target, value),
		AssignOp.Increment => target + "++",
		AssignOp.Decrement => target + "--",
	};
}

function letText(p: Printer, s: ShaderStmt): string {
	if (s.local < 0 || s.local >= p.current.locals.length) { return fail(p, "a Let out of range"); }
	const name = p.scope[p.current.params.length + s.local];
	const head = declaration(p, p.current.locals[s.local].type, name);
	return isNone(s.expr) ? head : head + " = " + expr(p, s.expr);
}

function simple(p: Printer, s: ShaderStmt): string {
	return match (s.kind) {
		StmtKind.Let => letText(p, s),
		StmtKind.Assign => assignment(p, s),
		StmtKind.Call => expr(p, s.expr),
		_ => fail(p, s.kind.toString() + " where a simple statement goes"),
	};
}

function block(p: Printer, stmts: ShaderStmt[], depth: int32): string {
	return indent(depth) + "{\n" + stmts.map((s) => stmt(p, s, depth + 1)).join("") +
		indent(depth) + "}\n";
}

function nested(p: Printer, kind: Nesting, stmts: ShaderStmt[], depth: int32): string {
	p.nesting.push(kind);
	const text = block(p, stmts, depth);
	p.nesting.pop();
	return text;
}

function forText(p: Printer, s: ShaderStmt, depth: int32): string {
	const update = s.update.map((u) => simple(p, u)).join(", ");
	const condition = isNone(s.expr) ? "" : expr(p, s.expr);
	if (s.init.length <= 1) {
		const init = s.init.length == 1 ? simple(p, s.init[0]) : "";
		return indent(depth) + "for (" + init + "; " + condition + "; " + update + ")\n" +
			nested(p, Nesting.Loop, s.body, depth);
	}
	const head = s.init.map((i) => indent(depth + 1) + simple(p, i) + ";\n").join("");
	return indent(depth) + "{\n" + head + indent(depth + 1) + "for (; " + condition + "; " +
		update + ")\n" + nested(p, Nesting.Loop, s.body, depth + 1) + indent(depth) + "}\n";
}

function switchText(p: Printer, s: ShaderStmt, depth: int32): string {
	let text = indent(depth) + "switch (" + expr(p, s.expr) + ")\n" + indent(depth) + "{\n";
	for (const k of s.cases) {
		for (const label of k.labels) {
			text += indent(depth + 1) + "case " + expr(p, label) + ":\n";
		}
		if (k.isDefault) { text += indent(depth + 1) + "default:\n"; }
		p.nesting.push(Nesting.Switch);
		text += indent(depth + 1) + "{\n" + k.body.map((b) => stmt(p, b, depth + 2)).join("") +
			indent(depth + 2) + "break;\n" + indent(depth + 1) + "}\n";
		p.nesting.pop();
	}
	return text + indent(depth) + "}\n";
}

function stmt(p: Printer, s: ShaderStmt, depth: int32): string {
	const at = indent(depth);
	return match (s.kind) {
		StmtKind.Block => block(p, s.body, depth),
		StmtKind.Let | StmtKind.Assign | StmtKind.Call => at + simple(p, s) + ";\n",
		StmtKind.If => {
			let text = at + "if (" + expr(p, s.expr) + ")\n" + block(p, s.body, depth);
			if (s.otherwise.length > 0) { text += at + "else\n" + block(p, s.otherwise, depth); }
			return text;
		},
		StmtKind.FeatureIf =>
			fail(p, "a feature branch is still undecided: specialize the module first"),
		StmtKind.While => at + "while (" + expr(p, s.expr) + ")\n" +
			nested(p, Nesting.Loop, s.body, depth),
		StmtKind.For => forText(p, s, depth),
		StmtKind.Switch => switchText(p, s, depth),
		StmtKind.Break => p.nesting.length > 0 && p.nesting[p.nesting.length - 1] == Nesting.Switch ?
			fail(p, "a break inside a switch case, which GLSL reads as leaving the switch") :
			at + "break;\n",
		StmtKind.Continue => at + "continue;\n",
		StmtKind.Return => isNone(s.expr) ? at + "return;\n" :
			at + "return " + expr(p, s.expr) + ";\n",
		StmtKind.Discard => p.stage == ShaderStage.Fragment ? at + "discard;\n" :
			fail(p, "Discard outside a fragment stage"),
	};
}

function functionText(p: Printer, index: int32): string {
	const f = p.module.functions[index];
	p.current = f;
	p.scope = p.globals.map((n) => n);
	const start = p.scope.length;
	for (const param of f.params) { claim(p, p.scope, param.name); }
	for (const local of f.locals) { claim(p, p.scope, local.name); }
	p.scope = p.scope.slice(start);
	if (f.result.kind == ShaderTypeKind.Array) {
		return fail(p, "function '" + f.name + "' returns an array");
	}
	const params = f.params.map((param, i) => declaration(p, param.type, p.scope[i]));
	return precision(p, f.result) + typeName(p, f.result) + " " + p.functionNames[index] + "(" +
		params.join(", ") + ")\n" + block(p, f.body, 0);
}

function exprCalls(e: ShaderExpr, out: int32[]): void {
	if (e.kind == ExprKind.Call && !out.includes(e.index)) { out.push(e.index); }
	for (const o of e.operands) { exprCalls(o, out); }
}

function calls(stmts: ShaderStmt[], out: int32[]): void {
	for (const s of stmts) {
		exprCalls(s.expr, out);
		exprCalls(s.target, out);
		for (const list of [s.init, s.update, s.body, s.otherwise]) { calls(list, out); }
		for (const k of s.cases) {
			for (const label of k.labels) { exprCalls(label, out); }
			calls(k.body, out);
		}
	}
}

function functionOrder(p: Printer, index: int32, path: int32[], out: int32[]): void {
	if (out.includes(index)) { return; }
	if (path.includes(index)) {
		fail(p, "function '" + p.module.functions[index].name + "' is recursive");
		return;
	}
	path.push(index);
	let callees: int32[] = [];
	calls(p.module.functions[index].body, callees);
	for (const c of callees) { functionOrder(p, c, path, out); }
	path.pop();
	out.push(index);
}

function structOrder(p: Printer, t: ShaderType, out: int32[]): void {
	for (const e of t.element) { structOrder(p, e, out); }
	if (t.kind != ShaderTypeKind.Struct || out.includes(t.structIndex)) { return; }
	for (const f of p.module.structs[t.structIndex].members) { structOrder(p, f.type, out); }
	out.push(t.structIndex);
}

function exprStructs(p: Printer, e: ShaderExpr, out: int32[]): void {
	if (e.kind != ExprKind.BlockMember) { structOrder(p, e.type, out); }
	for (const o of e.operands) { exprStructs(p, o, out); }
}

function stmtStructs(p: Printer, stmts: ShaderStmt[], out: int32[]): void {
	for (const s of stmts) {
		exprStructs(p, s.expr, out);
		exprStructs(p, s.target, out);
		for (const list of [s.init, s.update, s.body, s.otherwise]) { stmtStructs(p, list, out); }
		for (const k of s.cases) {
			for (const label of k.labels) { exprStructs(p, label, out); }
			stmtStructs(p, k.body, out);
		}
	}
}

function constantOrder(p: Printer, e: ShaderExpr, out: int32[]): void {
	for (const o of e.operands) { constantOrder(p, o, out); }
	if (e.kind == ExprKind.Constant && !out.includes(e.index)) {
		constantOrder(p, p.module.constants[e.index].value, out);
		out.push(e.index);
	}
}

function structText(p: Printer, structIndex: int32): string {
	const s = p.module.structs[structIndex];
	return "struct " + p.structNames[structIndex] + "\n{\n" + s.members.map((f, i) =>
		"    " + declaration(p, f.type, p.fieldNames[structIndex][i]) + ";\n").join("") +
		"};\n\n";
}

function slotOf(p: Printer, index: int32, slots: BindingSlot[]): int32 {
	const found = slots.filter((s) => s.resource == index && s.texture < 0);
	if (found.length == 0 || found[0].nativeSlot < 0) {
		fail(p, "resource '" + p.module.resources[index].name + "' has no GL slot");
		return -1;
	}
	return found[0].nativeSlot;
}

function accessWord(a: Access): string {
	return match (a) {
		Access.Read => "readonly ",
		Access.Write => "writeonly ",
		Access.ReadWrite => "",
	};
}

function combinedType(p: Printer, pair: Pair): string {
	const t = p.module.resources[pair.texture].type;
	const prefix = vectorPrefix(t.scalar == ScalarKind.Bool ? ScalarKind.F32 : t.scalar);
	const shadow = isComparison(p, pair);
	const plain = (shape: string) =>
		shadow ? fail(p, "comparison sampler pair '" + pair.name + "' on a " + t.shape.toString() +
			" texture") : prefix + "sampler" + shape;
	const desktop = (shape: string) => p.es ?
		fail(p, "texture '" + p.module.resources[pair.texture].name + "' is " + t.shape.toString() +
			", which GLSL ES 3.00 has not") : plain(shape);
	return match (t.shape) {
		TextureShape.D2 => plain("2D"),
		TextureShape.D2Array => plain("2DArray"),
		TextureShape.D3 => plain("3D"),
		TextureShape.Cube => plain("Cube"),
		TextureShape.CubeArray => desktop("CubeArray"),
		TextureShape.Depth2d => shadow ? "sampler2DShadow" : "sampler2D",
		TextureShape.Depth2dArray => shadow ? "sampler2DArrayShadow" : "sampler2DArray",
		TextureShape.DepthCube => shadow ? "samplerCubeShadow" : "samplerCube",
		TextureShape.Multisampled2d => desktop("2DMS"),
	};
}

function resourceDeclaration(p: Printer, index: int32, slots: BindingSlot[]): string {
	const r = p.module.resources[index];
	const name = p.resourceNames[index];
	if (p.es && (r.kind == ResourceKind.StorageBuffer || r.kind == ResourceKind.StorageTexture)) {
		return fail(p, r.kind.toString() + " '" + r.name + "': GLSL ES 3.00 has no storage " +
			"resources");
	}
	return match (r.kind) {
		ResourceKind.UniformBlock => {
			const layout = uniformBlockLayout(p.module, index);
			if (!layout.ok) { return fail(p, layout.error); }
			const highp = p.es && p.stage == ShaderStage.Fragment ? "highp " : "";
			return "uniform " + highp + "vec4 " + p.blockNames[index] + "[" +
				String(layout.value.size / 16) + "];\n";
		},
		ResourceKind.Texture | ResourceKind.Sampler => "",
		ResourceKind.StorageBuffer => {
			const layout = storageElementLayout(p.module, index);
			if (!layout.ok) { return fail(p, layout.error); }
			return "layout(std430, binding = " + String(slotOf(p, index, slots)) + ") " +
				accessWord(r.access) + "buffer " + p.blockNames[index] + "\n{\n    " +
				p.structNames[r.type.element[0].structIndex] + " data[];\n} " + name + ";\n";
		},
		ResourceKind.StorageTexture => "layout(binding = " + String(slotOf(p, index, slots)) +
			", " + imageFormat(r.type.format) + ") uniform " + accessWord(r.type.access) +
			typeName(p, r.type) + " " + name + ";\n",
	};
}

function pairDeclaration(p: Printer, pair: Pair): string {
	const unit = p.es ? "" : "layout(binding = " + String(pair.unit) + ") ";
	return unit + "uniform " + (p.es ? "highp " : "") + combinedType(p, pair) + " " + pair.name +
		";\n";
}

function interpolation(p: Printer, io: ShaderIo): string {
	const mode = match (io.interpolation) {
		Interpolation.Perspective => "",
		Interpolation.Linear => p.es ?
			fail(p, "io '" + io.name + "' is linear, which GLSL ES 3.00 has not") : "noperspective ",
		Interpolation.Flat => "flat ",
	};
	const sampling = match (io.sampling) {
		Sampling.Center => "",
		Sampling.Centroid => "centroid ",
		Sampling.Sample => p.es ?
			fail(p, "io '" + io.name + "' is per sample, which GLSL ES 3.00 has not") : "sample ",
	};
	return mode + sampling;
}

function ioDeclarations(p: Printer): string {
	const m = p.module;
	let text = "";
	let ordinals = [0, 0];
	for (let i = 0; i < m.ios.length; i++) {
		const io = m.ios[i];
		if (io.stage != p.stage || io.builtin != Builtin.None) { continue; }
		if (p.stage == ShaderStage.Compute) {
			return fail(p, "compute io '" + io.name + "' is no builtin");
		}
		const way = io.direction == IoDirection.In ? 0 : 1;
		const location = io.location >= 0 ? io.location : ordinals[way];
		ordinals[way] += 1;
		const varying = p.stage == ShaderStage.Vertex ? way == 1 : way == 0;
		const placed = !varying || !p.es ? "layout(location = " + String(location) + ") " : "";
		const storage = way == 0 ? "in " : "out ";
		text += placed + (varying ? interpolation(p, io) : "") + storage +
			declaration(p, io.type, p.ioNames[i]) + ";\n";
	}
	return text;
}

function unspecialized(m: ShaderModule, stage: ShaderStage, resources: int32[],
	functions: int32[]): string {
	const held = (kind: ConditionKind) => kind == ConditionKind.Always;
	for (const io of m.ios) {
		if (io.stage == stage && !held(io.condition.kind)) { return "io '" + io.name + "'"; }
	}
	for (const r of resources) {
		if (!held(m.resources[r].condition.kind)) { return "resource '" + m.resources[r].name + "'"; }
	}
	for (const f of functions) {
		if (!held(m.functions[f].condition.kind)) { return "function '" + m.functions[f].name + "'"; }
	}
	return "";
}

// A uniform block is one `vec4 <block>[size / 16]` and each texture-sampler pair one combined
// sampler, both bound by name (src/webgpu/gl/backend.ms resolveUniforms, resolveTextureUnits).
export function printGlsl(m: ShaderModule, entryIndex: int32, slots: BindingSlot[],
	target: GlslTarget): Result<string, string> {
	const invalid = irErrors(m);
	if (invalid.length > 0) { return Result.err("printGlsl: " + invalid[0]); }
	if (entryIndex < 0 || entryIndex >= m.entries.length) {
		return Result.err("printGlsl: entry " + String(entryIndex) + " is out of range");
	}
	const entry = m.entries[entryIndex];
	const es = target == GlslTarget.Glsl300es;
	if (es && entry.stage == ShaderStage.Compute) {
		return Result.err("printGlsl: entry '" + entry.name + "' is compute, which GLSL ES 3.00 " +
			"has not");
	}
	const readsResult = readsFrom(m, entry.functionIndex);
	if (!readsResult.ok) { return Result.err("printGlsl: " + readsResult.error); }
	const reads = readsResult.value;
	const conditioned = unspecialized(m, entry.stage, reads.resources, reads.functions);
	if (conditioned != "") {
		return Result.err("printGlsl: " + conditioned + " is under a feature condition: " +
			"specialize the module first");
	}
	const entryFunction = m.functions[entry.functionIndex];
	if (entryFunction.params.length > 0 || entryFunction.result.kind != ShaderTypeKind.Void) {
		return Result.err("printGlsl: entry '" + entry.name + "' takes parameters or returns a " +
			"value; an entry reads and writes its stage's io");
	}

	let p = new Printer();
	p.module = m;
	p.stage = entry.stage;
	p.es = es;
	p.structNames = m.structs.map((_s) => "");
	p.fieldNames = m.structs.map((_s) => []);
	p.constantNames = m.constants.map((_c) => "");
	p.resourceNames = m.resources.map((_r) => "");
	p.blockNames = m.resources.map((_r) => "");
	p.blockOffsets = m.resources.map((_r) => []);
	p.ioNames = m.ios.map((_io) => "");
	p.functionNames = m.functions.map((_f) => "");
	p.effects = m.functions.map((_f) => 0);

	let functions: int32[] = [];
	functionOrder(p, entry.functionIndex, [], functions);
	let structs: int32[] = [];
	for (const f of functions) {
		const fn = m.functions[f];
		for (const v of fn.params) { structOrder(p, v.type, structs); }
		for (const v of fn.locals) { structOrder(p, v.type, structs); }
		structOrder(p, fn.result, structs);
		stmtStructs(p, fn.body, structs);
	}
	for (const r of reads.resources) {
		if (m.resources[r].kind == ResourceKind.StorageBuffer) {
			structOrder(p, m.resources[r].type, structs);
		}
	}
	for (const c of reads.constants) { exprStructs(p, m.constants[c].value, structs); }
	for (const io of m.ios) {
		if (io.stage == entry.stage) { structOrder(p, io.type, structs); }
	}
	let constants: int32[] = [];
	for (const c of reads.constants) {
		let read = new ShaderExpr();
		read.kind = ExprKind.Constant;
		read.index = c;
		constantOrder(p, read, constants);
	}
	const kinds = [ResourceKind.UniformBlock, ResourceKind.StorageBuffer,
		ResourceKind.StorageTexture];
	let resources: int32[] = [];
	for (const kind of kinds) {
		for (const r of reads.resources) {
			if (m.resources[r].kind == kind) { resources.push(r); }
		}
	}

	claimFixed(p, "main", "entry");
	let unit = 0;
	for (const s of slots) {
		if (s.texture < 0) { continue; }
		if (s.stage == entry.stage) {
			let pair = new Pair();
			pair.texture = s.texture;
			pair.sampler = s.resource;
			pair.name = claimFixed(p, s.nativeName, "combined sampler");
			pair.unit = unit;
			p.pairs.push(pair);
		}
		unit++;
	}
	for (const r of resources) {
		if (m.resources[r].kind != ResourceKind.UniformBlock) { continue; }
		p.blockNames[r] = claimFixed(p, m.resources[r].name, "uniform block");
		const layout = uniformBlockLayout(m, r);
		if (!layout.ok) { return Result.err("printGlsl: " + layout.error); }
		p.blockOffsets[r] = layout.value.offsets;
	}
	for (let i = 0; i < m.ios.length; i++) {
		const io = m.ios[i];
		if (io.stage == entry.stage && io.builtin == Builtin.None) {
			p.ioNames[i] = claimFixed(p, io.name, "io");
		}
	}
	for (const s of structs) {
		p.structNames[s] = claim(p, p.globals, m.structs[s].name);
		let fields: string[] = [];
		for (const f of m.structs[s].members) { claim(p, fields, f.name); }
		p.fieldNames[s] = fields;
	}
	for (const r of resources) {
		if (m.resources[r].kind == ResourceKind.UniformBlock) { continue; }
		p.resourceNames[r] = claim(p, p.globals, m.resources[r].name);
		if (m.resources[r].kind == ResourceKind.StorageBuffer) {
			p.blockNames[r] = claim(p, p.globals, m.resources[r].name + "_buffer");
		}
	}
	for (const c of constants) { p.constantNames[c] = claim(p, p.globals, m.constants[c].name); }
	for (const f of functions) {
		p.functionNames[f] = f == entry.functionIndex ? "main" :
			claim(p, p.globals, m.functions[f].name);
	}

	let head = es ? "#version 300 es\n" : "#version 430\n";
	if (es && entry.stage == ShaderStage.Fragment) {
		head += "precision mediump float;\nprecision highp int;\n";
	}
	head += "\n";
	if (entry.stage == ShaderStage.Compute) {
		const axes = ["x", "y", "z"];
		head += "layout(" + entry.workgroupSize.map((n, i) => "local_size_" + axes[i] + " = " +
			String(n)).join(", ") + ") in;\n\n";
	}
	for (const s of structs) { head += structText(p, s); }
	for (const c of constants) {
		const constant = m.constants[c];
		head += "const " + declaration(p, constant.type, p.constantNames[c]) + " = " +
			expr(p, constant.value) + ";\n";
	}
	if (constants.length > 0) { head += "\n"; }
	let declared = "";
	for (const r of resources) { declared += resourceDeclaration(p, r, slots); }
	for (const pair of p.pairs) { declared += pairDeclaration(p, pair); }
	const ios = ioDeclarations(p);
	if (declared != "") { head += declared + "\n"; }
	if (ios != "") { head += ios + "\n"; }
	const bodies = functions.map((f) => functionText(p, f)).join("\n");
	if (p.error != "") { return Result.err(p.error); }
	return Result.ok(head + bodies);
}
