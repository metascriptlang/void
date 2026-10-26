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
	isShift,
	isArrayTexture,
	hasOffset,
	offsetOf,
	sampleBase,
	isAtomic,
	sameShaderType,
	texelScalar,
} from "./ir";
import { BindingSlot, storageElementLayout, uniformBlockLayout } from "./layout";
import {
	constantOrder,
	exprStructs,
	functionOrder,
	hasEffect,
	innermost,
	ioLocation,
	rootOf,
	splitResults,
	stmtStructs,
	structOrder,
} from "./irWalk";
import {
	binaryOperator,
	exchangeSlot,
	floatText,
	glslAtomicName,
	glslBitcast,
	glslBits,
	glslSplitTypes,
	isIntMin,
	mathName,
	pointed,
	repeatedBitsOperand,
	splitHelperName,
	splitMember,
	splitStructName,
} from "./spelling";
import { claimName } from "./names";
import { printableEntry } from "./specialize";

export enum GlslTarget {
	Glsl430,
	Glsl300es,
}

function glslKeywords(): string[] {
	return [
		"attribute", "const", "uniform", "varying", "buffer", "shared", "coherent", "volatile",
		"restrict", "readonly", "writeonly", "atomic_uint", "layout", "centroid", "flat", "smooth",
		"noperspective", "patch", "sample", "break", "continue", "do", "for", "while", "switch",
		"case", "default", "if", "else", "subroutine", "in", "out", "inout", "float", "double",
		"int", "uint", "void", "bool", "true", "false", "invariant", "precise", "discard", "return",
		"lowp", "mediump", "highp", "precision", "struct", "common", "partition", "active", "asm",
		"class", "union", "enum", "typedef", "template", "this", "resource", "goto", "inline",
		"noinline", "public", "static", "extern", "external", "interface", "long", "short", "half",
		"fixed", "unsigned", "superp", "input", "output", "filter", "sizeof", "cast", "namespace",
		"using",
	];
}

function glslFunctions(): string[] {
	return [
		"radians", "degrees", "sin", "cos", "tan", "asin", "acos", "atan", "sinh", "cosh", "tanh",
		"asinh", "acosh", "atanh", "pow", "exp", "log", "exp2", "log2", "sqrt", "inversesqrt",
		"abs", "sign", "floor", "trunc", "round", "roundEven", "ceil", "fract", "mod", "modf",
		"min", "max", "clamp", "mix", "step", "smoothstep", "isnan", "isinf", "floatBitsToInt",
		"floatBitsToUint", "intBitsToFloat", "uintBitsToFloat", "fma", "frexp", "ldexp",
		"packUnorm2x16", "packSnorm2x16", "packUnorm4x8", "packSnorm4x8", "unpackUnorm2x16",
		"unpackSnorm2x16", "unpackUnorm4x8", "unpackSnorm4x8", "packHalf2x16", "unpackHalf2x16",
		"packDouble2x32", "unpackDouble2x32", "length", "distance", "dot", "cross", "normalize",
		"ftransform", "faceforward", "reflect", "refract", "matrixCompMult", "outerProduct",
		"transpose", "determinant", "inverse", "lessThan", "lessThanEqual", "greaterThan",
		"greaterThanEqual", "equal", "notEqual", "any", "all", "not", "uaddCarry", "usubBorrow",
		"umulExtended", "imulExtended", "bitfieldExtract", "bitfieldInsert", "bitfieldReverse",
		"bitCount", "findLSB", "findMSB", "textureSize", "textureQueryLod", "textureQueryLevels",
		"textureSamples", "texture", "textureProj", "textureLod", "textureOffset", "texelFetch",
		"texelFetchOffset", "textureProjOffset", "textureLodOffset", "textureProjLod",
		"textureProjLodOffset", "textureGrad", "textureGradOffset", "textureProjGrad",
		"textureProjGradOffset", "textureGather", "textureGatherOffset", "textureGatherOffsets",
		"texture1D", "texture2D", "texture3D", "textureCube", "texture2DLod", "texture2DProj",
		"shadow1D", "shadow2D", "atomicCounterIncrement", "atomicCounterDecrement", "atomicCounter",
		"atomicAdd", "atomicMin", "atomicMax", "atomicAnd", "atomicOr", "atomicXor",
		"atomicExchange", "atomicCompSwap", "imageSize", "imageSamples", "imageLoad", "imageStore",
		"imageAtomicAdd", "imageAtomicMin", "imageAtomicMax", "imageAtomicAnd", "imageAtomicOr",
		"imageAtomicXor", "imageAtomicExchange", "imageAtomicCompSwap", "dFdx", "dFdy", "fwidth",
		"dFdxFine", "dFdyFine", "fwidthFine", "dFdxCoarse", "dFdyCoarse", "fwidthCoarse",
		"interpolateAtCentroid", "interpolateAtSample", "interpolateAtOffset", "noise1", "noise2",
		"noise3", "noise4", "EmitStreamVertex", "EndStreamPrimitive", "EmitVertex", "EndPrimitive",
		"barrier", "memoryBarrier", "memoryBarrierAtomicCounter", "memoryBarrierBuffer",
		"memoryBarrierShared", "memoryBarrierImage", "groupMemoryBarrier",
	];
}

const SWIZZLE = "xyzw";

function isTypeName(name: string): boolean {
	const bases = ["vec", "ivec", "uvec", "bvec", "dvec", "hvec", "fvec", "mat", "dmat"];
	for (const base of bases) {
		if (!name.startsWith(base)) { continue; }
		const rest = name.substring(base.length);
		const digit = (at: int32) =>
			rest.length > at && "234".includes(rest.substring(at, at + 1));
		if (rest.length == 1 && digit(0)) { return true; }
		if (rest.length == 3 && digit(0) && rest.substring(1, 2) == "x" && digit(2)) {
			return true;
		}
	}
	const shapes = [
		"1D", "2D", "3D", "Cube", "2DRect", "1DArray", "2DArray", "CubeArray", "Buffer", "2DMS",
		"2DMSArray",
	];
	for (const prefix of ["sampler", "isampler", "usampler", "image", "iimage", "uimage"]) {
		if (name.startsWith(prefix) && shapes.includes(name.substring(prefix.length))) {
			return true;
		}
	}
	return ["sampler1DShadow", "sampler2DShadow", "samplerCubeShadow", "sampler1DArrayShadow",
		"sampler2DArrayShadow", "samplerCubeArrayShadow", "sampler2DRectShadow", "sampler3DRect",
		"samplerExternalOES"].includes(name);
}

function isReserved(p: Printer, name: string): boolean {
	return p.reserved.includes(name) || isTypeName(name);
}

enum Nesting {
	Loop,
	Switch,
}

struct Pair {
	texture: int32;
	sampler: int32;
	name: string;
	unit: int32;
}

class Printer {
	module: ShaderModule = new ShaderModule();
	stage: ShaderStage = ShaderStage.Vertex;
	es: boolean = false;
	samplesQueried: boolean = false;
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
	workgroupNames: string[] = [];
	exchangeNames: string[] = ["", ""];
	splits: ShaderType[] = [];
	splitStructs: string[] = [];
	splitHelpers: string[] = [];
	effects: int32[] = [];
	pairs: Pair[] = [];
	scope: string[] = [];
	current: ShaderFunction = new ShaderFunction();
	nesting: Nesting[] = [];
	reserved: string[] = [];
}

function fail(p: Printer, message: string): string {
	if (p.error == "") { p.error = "printGlsl: " + message; }
	return "";
}

function claim(p: Printer, taken: string[], name: string): string {
	if (name.startsWith("gl_") || name.includes("__")) {
		return fail(p, "'" + name + "' is a name GLSL reserves to itself");
	}
	return claimName(taken, (n) => isReserved(p, n), name);
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

function arraySuffix(p: Printer, t: ShaderType): string {
	if (t.kind != ShaderTypeKind.Array) { return ""; }
	if (p.es && t.element[0].kind == ShaderTypeKind.Array) {
		return fail(p, "an array of arrays, which GLSL ES 3.00 has not");
	}
	return "[" + String(t.length) + "]" + arraySuffix(p, t.element[0]);
}

function imageFormat(p: Printer, format: TexelFormat): string {
	return match (format) {
		TexelFormat.Rgba8unorm => "rgba8",
		TexelFormat.Rgba8snorm => "rgba8_snorm",
		TexelFormat.Rgba8uint => "rgba8ui",
		TexelFormat.Rgba8sint => "rgba8i",
		TexelFormat.Rgba16uint => "rgba16ui",
		TexelFormat.Rgba16sint => "rgba16i",
		TexelFormat.Rgba16float => "rgba16f",
		TexelFormat.Rgba32uint => "rgba32ui",
		TexelFormat.Rgba32sint => "rgba32i",
		TexelFormat.Rgba32float => "rgba32f",
		TexelFormat.R32float => "r32f",
		TexelFormat.R32uint => "r32ui",
		TexelFormat.R32sint => "r32i",
		TexelFormat.Rg32float => "rg32f",
		TexelFormat.Rg32uint => "rg32ui",
		TexelFormat.Rg32sint => "rg32i",
		TexelFormat.Bgra8unorm => fail(p, "bgra8unorm has no GLSL image format"),
	};
}

function splitNames(p: Printer, t: ShaderType, names: string[]): string {
	const at = p.splits.findIndex((s) => sameShaderType(s, t));
	if (at >= 0) { return names[at]; }
	if (p.es && t.kind == ShaderTypeKind.FrexpResult) {
		return fail(p, "Frexp is not in GLSL ES 3.00 (ES 3.10 has it)");
	}
	return fail(p, "no struct is declared for a " + t.kind.toString());
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
		ShaderTypeKind.StorageTexture => vectorPrefix(texelScalar(t.format)) +
			imageShapeName(p, t.shape),
		ShaderTypeKind.Atomic => scalarName(t.scalar),
		ShaderTypeKind.ExchangeResult => p.exchangeNames[exchangeSlot(t.scalar)],
		ShaderTypeKind.ModfResult | ShaderTypeKind.FrexpResult => splitNames(p, t, p.splitStructs),
	};
}

// SPIRV-Cross's GLSL atomics (measured through sokol-shdc): GLSL 4.30 has no atomic load or
// store, so a load is an add of 0 and a store an exchange.
function atomicText(p: Printer, e: ShaderExpr): string {
	if (p.es) { return fail(p, e.intrinsic.toString() + " has no GLSL ES 3.00 form"); }
	const o = e.operands;
	const value = match (e.intrinsic) {
		Intrinsic.AtomicLoad => o[0].type.scalar == ScalarKind.U32 ? "0u" : "0",
		Intrinsic.AtomicSub => "-" + operand(p, o[1]),
		Intrinsic.AtomicStore | Intrinsic.AtomicAdd | Intrinsic.AtomicMax | Intrinsic.AtomicMin |
			Intrinsic.AtomicAnd | Intrinsic.AtomicOr | Intrinsic.AtomicXor |
			Intrinsic.AtomicExchange =>
			o.slice(1).map((a) => expr(p, a)).join(", "),
		_ => fail(p, e.intrinsic.toString() + " is no GLSL atomic expression"),
	};
	return glslAtomicName(e.intrinsic) + "(" + expr(p, o[0]) + ", " + value + ")";
}

function exchangeLet(p: Printer, s: ShaderStmt, at: string): string {
	const name = p.scope[p.current.params.length + s.local];
	const o = s.expr.operands;
	const compare = claim(p, p.globals.concat(p.scope), "compare");
	p.scope.push(compare);
	return at + scalarName(o[0].type.scalar) + " " + compare + " = " + expr(p, o[1]) + ";\n" +
		at + typeName(p, s.expr.type) + " " + name + ";\n" +
		at + name + ".old_value = atomicCompSwap(" + expr(p, o[0]) + ", " + compare + ", " +
		expr(p, o[2]) + ");\n" +
		at + name + ".exchanged = " + name + ".old_value == " + compare + ";\n";
}

function isExchange(e: ShaderExpr): boolean {
	return e.kind == ExprKind.Intrinsic && e.intrinsic == Intrinsic.AtomicCompareExchangeWeak;
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

function scalarLiteral(s: ScalarKind, v: float64): string {
	return match (s) {
		ScalarKind.F32 => pointed(floatText(v)),
		ScalarKind.I32 => isIntMin(s, v) ? "(-2147483647 - 1)" : String(v as int64),
		ScalarKind.U32 => String(v as int64) + "u",
		ScalarKind.Bool => v != 0.0 ? "true" : "false",
	};
}

function literalText(p: Printer, e: ShaderExpr): string {
	const t = e.type;
	const one = scalarLiteral(t.scalar, e.value);
	return match (t.kind) {
		ShaderTypeKind.Scalar => one,
		ShaderTypeKind.Vector => typeName(p, t) + "(" + one + ")",
		ShaderTypeKind.Matrix => typeName(p, t) + "(" +
			repeated("vec" + String(t.rows) + "(" + one + ")", t.columns) + ")",
		_ => fail(p, "a literal of " + t.kind.toString()),
	};
}

function pure(p: Printer, what: string, operands: ShaderExpr[]): void {
	if (operands.some((o) => hasEffect(p.module, p.effects, o))) {
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

function notOfVector(e: ShaderExpr): boolean {
	const t = e.operands[0].type;
	return e.unary == UnaryOp.Not && t.kind == ShaderTypeKind.Vector && t.scalar == ScalarKind.Bool;
}

function unaryText(e: ShaderExpr): string {
	return match (e.unary) {
		UnaryOp.Negate => "-",
		UnaryOp.Not => e.operands[0].type.scalar == ScalarKind.Bool ? "!" : "~",
	};
}

function binaryText(p: Printer, e: ShaderExpr): string {
	const a = e.operands[0];
	const b = e.operands[1];
	const op = binaryOperator(e.binary);
	if (e.binary == BinaryOp.Mod) { return remainder(p, a, b); }
	if (isShift(e.binary) && b.kind != ExprKind.Literal) {
		return operand(p, a) + " " + op + " (" + operand(p, b) + " & 31u)";
	}
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
	return rows == 4 ? text : text + "." + SWIZZLE.substring(0, rows);
}

function pairOf(p: Printer, texture: ShaderExpr, sampler: ShaderExpr | null): Pair {
	const none: Pair = { texture: -1, sampler: -1, name: "", unit: 0 };
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
		const size = "imageSize(" + expr(p, args[0]) + ")";
		return match (t.shape) {
			TextureShape.D3 => converted(p, size, "ivec3", e.type),
			TextureShape.D2Array => converted(p, size + ".xy", "ivec2", e.type),
			TextureShape.D2 => converted(p, size, "ivec2", e.type),
			_ => fail(p, "a storage texture of shape " + t.shape.toString()),
		};
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

function samplesOf(p: Printer, e: ShaderExpr): string {
	const t = e.operands[0].type;
	if (t.kind != ShaderTypeKind.Texture || t.shape != TextureShape.Multisampled2d ||
		e.type.scalar != ScalarKind.I32) {
		return fail(p, "TextureNumSamples takes a multisampled texture and gives an i32");
	}
	const pair = pairOf(p, e.operands[0], null);
	p.samplesQueried = true;
	return "textureSamples(" + pair.name + ")";
}

function loadOf(p: Printer, e: ShaderExpr): string {
	const args = withoutSampler(e);
	const t = args[0].type;
	if (args.length < 2) { return fail(p, "TextureLoad without coordinates"); }
	if (t.kind == ShaderTypeKind.StorageTexture) {
		return narrowed("imageLoad(" + expr(p, args[0]) + ", " + imageAt(p, args) + ")", e.type);
	}
	if (t.kind != ShaderTypeKind.Texture) {
		return fail(p, "TextureLoad of a " + t.kind.toString());
	}
	const pair = pairOf(p, args[0], samplerOperand(e));
	if (isComparison(p, pair)) {
		return fail(p, "TextureLoad through comparison sampler pair '" + pair.name + "'");
	}
	const layered = t.shape == TextureShape.D2Array;
	const levelAt = layered ? 3 : 2;
	const level = args.length > levelAt ? intText(p, args[levelAt]) : "0";
	const at = layered ? "ivec3(" + intText(p, args[1]) + ", " + intText(p, args[2]) + ")" :
		intText(p, args[1]);
	const fetch = "texelFetch(" + pair.name + ", " + at + ", " + level + ")";
	return match (t.shape) {
		TextureShape.D2 | TextureShape.D2Array | TextureShape.Depth2d | TextureShape.D3 |
			TextureShape.Multisampled2d => narrowed(fetch, e.type),
		_ => fail(p, "TextureLoad of a " + t.shape.toString() + " texture"),
	};
}

function isLayered(t: ShaderType): boolean {
	return t.shape == TextureShape.D2Array || t.shape == TextureShape.Depth2dArray;
}

function sampleOf(p: Printer, e: ShaderExpr): string {
	const layered = e.operands.length > 0 && isLayered(e.operands[0].type);
	const base = layered ? 4 : 3;
	if (e.operands.length != base && e.operands.length != base + 1) {
		return fail(p, "TextureSample takes a texture, a sampler, coordinates and, for an array " +
			"texture, a layer, and an optional constant offset");
	}
	const [texture, sampler, at] = [e.operands[0], e.operands[1], e.operands[2]];
	if (texture.type.kind != ShaderTypeKind.Texture ||
		sampler.type.kind != ShaderTypeKind.Sampler) {
		return fail(p, "TextureSample takes a texture and a sampler first");
	}
	if (texture.type.shape == TextureShape.Multisampled2d) {
		return fail(p, "TextureSample of a multisampled texture");
	}
	const pair = pairOf(p, texture, sampler);
	if (isComparison(p, pair)) {
		return fail(p, "TextureSample through a comparison sampler, which needs a depth reference");
	}
	const coords = layered ? "vec3(" + expr(p, at) + ", float(" + expr(p, e.operands[3]) + "))" :
		expr(p, at);
	return narrowed(e.operands.length == base ? "texture(" + pair.name + ", " + coords + ")" :
		"textureOffset(" + pair.name + ", " + coords + ", " + expr(p, e.operands[base]) + ")", e.type);
}

function explicitSampleOf(p: Printer, e: ShaderExpr): string {
	const o = e.operands;
	const t = o[0].type;
	const pair = pairOf(p, o[0], o[1]);
	if (isComparison(p, pair)) {
		return fail(p, e.intrinsic.toString() + " through a comparison sampler, which needs a " +
			"depth reference");
	}
	const layer = isArrayTexture(t) ? 1 : 0;
	const at = layer == 0 ? expr(p, o[2]) : (t.shape == TextureShape.CubeArray ? "vec4(" :
		"vec3(") + expr(p, o[2]) + ", float(" + expr(p, o[3]) + "))";
	const tail = o.slice(3 + layer, sampleBase(e)).map((a) => a.type.kind == ShaderTypeKind.Scalar &&
		a.type.scalar != ScalarKind.F32 ? "float(" + expr(p, a) + ")" : expr(p, a)).join(", ");
	const offset = hasOffset(e) ? expr(p, offsetOf(e)) : "";
	const suffix = offset == "" ? "" : "Offset";
	const name = match (e.intrinsic) {
		Intrinsic.TextureSampleLevel => "textureLod" + suffix + "(",
		Intrinsic.TextureSampleBias => "texture" + suffix + "(",
		Intrinsic.TextureSampleGrad => "textureGrad" + suffix + "(",
		_ => fail(p, e.intrinsic.toString() + " is no explicit sample"),
	};
	const args = e.intrinsic == Intrinsic.TextureSampleBias && offset != "" ?
		offset + ", " + tail : tail + (offset == "" ? "" : ", " + offset);
	return narrowed(name + pair.name + ", " + at + ", " + args + ")", e.type);
}

function compareOf(p: Printer, e: ShaderExpr, level: boolean): string {
	const name = e.intrinsic.toString();
	const layered = e.operands.length > 0 && isLayered(e.operands[0].type);
	const base = layered ? 5 : 4;
	if (e.operands.length != base && e.operands.length != base + 1) {
		return fail(p, name + " takes a texture, a sampler, coordinates, for an array texture a " +
			"layer, a depth reference, and an optional constant offset");
	}
	const [texture, sampler, at] = [e.operands[0], e.operands[1], e.operands[2]];
	const reference = e.operands[base - 1];
	const offset = e.operands.length == base ? "" : ", " + expr(p, e.operands[base]);
	const suffix = offset == "" ? "" : "Offset";
	if (texture.type.kind != ShaderTypeKind.Texture ||
		sampler.type.kind != ShaderTypeKind.Sampler) {
		return fail(p, name + " takes a texture and a sampler first");
	}
	const pair = pairOf(p, texture, sampler);
	if (!isComparison(p, pair)) {
		return fail(p, name + " through sampler pair '" + pair.name + "', whose sampler is no " +
			"comparison sampler");
	}
	const coords = expr(p, at) + (layered ? ", float(" + expr(p, e.operands[3]) + ")" : "") +
		", " + expr(p, reference);
	if (p.es && offset != "" && !level && texture.type.shape == TextureShape.Depth2dArray) {
		return fail(p, name + " of a texture_depth_2d_array with an offset has no GLSL ES 3.00 " +
			"form: textureOffset on sampler2DArrayShadow is GLSL 4.30's, never ES's");
	}
	return match (texture.type.shape) {
		TextureShape.Depth2d => level ?
			"textureLod" + suffix + "(" + pair.name + ", vec3(" + coords + "), 0.0" + offset + ")" :
			"texture" + suffix + "(" + pair.name + ", vec3(" + coords + ")" + offset + ")",
		TextureShape.Depth2dArray => level ?
			"textureGrad" + suffix + "(" + pair.name + ", vec4(" + coords + "), vec2(0.0), vec2(0.0)" +
				offset + ")" :
			"texture" + suffix + "(" + pair.name + ", vec4(" + coords + ")" + offset + ")",
		TextureShape.DepthCube => level ?
			"textureGrad(" + pair.name + ", vec4(" + coords + "), vec3(0.0), vec3(0.0))" :
			"texture(" + pair.name + ", vec4(" + coords + "))",
		_ => fail(p, name + " of a " + texture.type.shape.toString() + " texture, which holds " +
			"no depth"),
	};
}

function imageShapeName(p: Printer, shape: TextureShape): string {
	return match (shape) {
		TextureShape.D2 => "image2D",
		TextureShape.D2Array => "image2DArray",
		TextureShape.D3 => "image3D",
		_ => fail(p, "a storage texture of shape " + shape.toString()),
	};
}

function imageAt(p: Printer, args: ShaderExpr[]): string {
	return args[0].type.shape == TextureShape.D2Array ?
		"ivec3(" + intText(p, args[1]) + ", " + intText(p, args[2]) + ")" : intText(p, args[1]);
}

function storeOf(p: Printer, e: ShaderExpr): string {
	const o = e.operands;
	const wanted = o.length > 0 && o[0].type.shape == TextureShape.D2Array ? 4 : 3;
	if (o.length != wanted || o[0].type.kind != ShaderTypeKind.StorageTexture) {
		return fail(p, "TextureStore takes a storage texture, coordinates, a layer of an " +
			"array, and a value");
	}
	const channel = texelScalar(o[0].type.format);
	const texel = vectorPrefix(channel) + "vec4";
	const value = o[wanted - 1];
	const rows = value.type.kind == ShaderTypeKind.Vector ? value.type.rows : 1;
	const zero = match (channel) {
		ScalarKind.U32 => "0u",
		ScalarKind.I32 => "0",
		ScalarKind.F32 => "0.0",
		ScalarKind.Bool => fail(p, "a storage texture of bool texels"),
	};
	const written = rows == 4 ? converted(p, expr(p, value), typeName(p, value.type),
		vectorTypeOf(channel)) : texel + "(" + expr(p, value) + ", " + repeated(zero, 4 - rows) + ")";
	return "imageStore(" + expr(p, o[0]) + ", " + imageAt(p, o) + ", " + written + ")";
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
		Intrinsic.Round => "roundEven",
		Intrinsic.Atan2 => "atan",
		Intrinsic.LessThan => "lessThan",
		Intrinsic.LessThanEqual => "lessThanEqual",
		Intrinsic.GreaterThan => "greaterThan",
		Intrinsic.GreaterThanEqual => "greaterThanEqual",
		Intrinsic.Equal => "equal",
		Intrinsic.NotEqual => "notEqual",
		Intrinsic.DpdxCoarse | Intrinsic.DpdxFine => "dFdx",
		Intrinsic.DpdyCoarse | Intrinsic.DpdyFine => "dFdy",
		Intrinsic.FwidthCoarse | Intrinsic.FwidthFine => "fwidth",
		_ => mathName(op),
	};
}

function selectText(p: Printer, e: ShaderExpr): string {
	const [falseValue, trueValue, condition] = [e.operands[0], e.operands[1], e.operands[2]];
	if (condition.type.kind == ShaderTypeKind.Vector) {
		if (isScalarKind(e.type, ScalarKind.F32)) {
			return "mix(" + expr(p, falseValue) + ", " + expr(p, trueValue) + ", " +
				expr(p, condition) + ")";
		}
		pure(p, "select", [falseValue, trueValue, condition]);
		let lanes: string[] = [];
		for (let i = 0; i < e.type.rows; i++) {
			const lane = "." + SWIZZLE.substring(i, i + 1);
			lanes.push(postfixBase(p, condition) + lane + " ? " + postfixBase(p, trueValue) + lane +
				" : " + postfixBase(p, falseValue) + lane);
		}
		return typeName(p, e.type) + "(" + lanes.join(", ") + ")";
	}
	pure(p, "select", [falseValue, trueValue]);
	return "(" + operand(p, condition) + " ? " + operand(p, trueValue) + " : " +
		operand(p, falseValue) + ")";
}

function bitsText(p: Printer, e: ShaderExpr): string {
	if (p.es) {
		return fail(p, e.intrinsic.toString() + " is not in GLSL ES 3.00 (ES 3.10 has it)");
	}
	const at = repeatedBitsOperand(e.intrinsic);
	if (at >= 0) { pure(p, e.intrinsic.toString(), [e.operands[at]]); }
	return glslBits(e.intrinsic, e.operands.map((o) => expr(p, o)), typeName(p, e.type),
		e.type.scalar == ScalarKind.U32);
}

function intrinsicText(p: Printer, e: ShaderExpr): string {
	const args = () => e.operands.map((o) => expr(p, o)).join(", ");
	return match (e.intrinsic) {
		Intrinsic.Sign => converted(p, "sign(" + args() + ")", typeName(p, e.operands[0].type),
			e.type),
		Intrinsic.CountOneBits | Intrinsic.ReverseBits | Intrinsic.FirstLeadingBit |
			Intrinsic.FirstTrailingBit | Intrinsic.CountLeadingZeros | Intrinsic.CountTrailingZeros |
			Intrinsic.ExtractBits | Intrinsic.InsertBits | Intrinsic.Pack4x8Unorm |
			Intrinsic.Pack4x8Snorm | Intrinsic.Unpack4x8Unorm | Intrinsic.Unpack4x8Snorm =>
			bitsText(p, e),
		Intrinsic.Bitcast => glslBitcast(e.operands[0].type.scalar, e.type.scalar,
			typeName(p, e.type), expr(p, e.operands[0])),
		Intrinsic.Ldexp => p.es ? fail(p, "Ldexp is not in GLSL ES 3.00 (ES 3.10 has it)") :
			"ldexp(" + args() + ")",
		Intrinsic.Modf | Intrinsic.Frexp => splitNames(p, e.type, p.splitHelpers) + "(" + args() + ")",
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
		Intrinsic.TextureNumSamples => samplesOf(p, e),
		Intrinsic.TextureSampleCompare => compareOf(p, e, false),
		Intrinsic.TextureSampleCompareLevel => compareOf(p, e, true),
		Intrinsic.TextureSampleLevel | Intrinsic.TextureSampleBias | Intrinsic.TextureSampleGrad =>
			explicitSampleOf(p, e),
		Intrinsic.WorkgroupBarrier => "memoryBarrierShared(); barrier()",
		Intrinsic.StorageBarrier => "memoryBarrierBuffer(); barrier()",
		Intrinsic.AtomicCompareExchangeWeak => p.es ? atomicText(p, e) : fail(p,
			"AtomicCompareExchangeWeak outside a " +
			"local's initializer: atomicCompSwap returns only the old value"),
		_ => isAtomic(e.intrinsic) ? atomicText(p, e) :
			intrinsicName(e.intrinsic) + "(" + args() + ")",
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
		columns.push(t.rows == 4 ? whole : whole + "." + SWIZZLE.substring(0, t.rows));
	}
	return typeName(p, t) + "(" + columns.join(", ") + ")";
}

function stride(t: ShaderType): int32 { return t.kind == ShaderTypeKind.Matrix ? t.columns : 1; }

function twoRowColumns(p: Printer, r: int32, t: ShaderType, offset: int32): string {
	let columns: string[] = [];
	for (let c = 0; c < t.columns; c++) {
		const at = offset + 8 * c;
		const lane = (at % 16) / 4;
		columns.push(blockRow(p, r, String(at / 16)) + "." + SWIZZLE.substring(lane, lane + 2));
	}
	return typeName(p, t) + "(" + columns.join(", ") + ")";
}

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
	if (t.kind == ShaderTypeKind.Matrix) {
		return t.rows == 2 ? twoRowColumns(p, r, t, offset) : elementText(p, r, t, row, "");
	}
	const lane = (offset % 16) / 4;
	const width = t.kind == ShaderTypeKind.Vector ? t.rows : 1;
	const whole = blockRow(p, r, String(row));
	return lane == 0 && width == 4 ? whole :
		whole + "." + SWIZZLE.substring(lane, lane + width);
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
	const desktop = (name: string, typeText: string): [string, string] =>
		p.es ? [fail(p, io.builtin.toString() + ": GLSL ES 3.00 has no " + name), ""] :
			[name, typeText];
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
	const [name, typeText] = builtinRead(p, io);
	return converted(p, name, typeText, io.type);
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
		ExprKind.Local => p.scope[p.current.params.length + e.index],
		ExprKind.Param => p.scope[e.index],
		ExprKind.Constant => p.constantNames[e.index],
		ExprKind.Workgroup => p.workgroupNames[e.index],
		ExprKind.Io => ioText(p, e.index),
		ExprKind.Resource => resourceText(p, e.index),
		ExprKind.BlockMember => memberText(p, e),
		ExprKind.Unary => notOfVector(e) ? "not(" + expr(p, e.operands[0]) + ")" :
			unaryText(e) + operand(p, e.operands[0]),
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
			if (base.type.kind == ShaderTypeKind.ExchangeResult) {
				return postfixBase(p, base) + (e.index == 0 ? ".old_value" : ".exchanged");
			}
			if (base.type.kind == ShaderTypeKind.ModfResult || base.type.kind == ShaderTypeKind.FrexpResult) {
				return postfixBase(p, base) + "." + splitMember(base.type, e.index);
			}
			if (base.type.kind != ShaderTypeKind.Struct) {
				return fail(p, "Field of a " + base.type.kind.toString());
			}
			return postfixBase(p, base) + "." + p.fieldNames[base.type.structIndex][e.index];
		},
		ExprKind.Swizzle => postfixBase(p, e.operands[0]) + "." +
			e.components.map((c) => SWIZZLE.substring(c, c + 1)).join(""),
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
	for (const arm of s.cases) {
		for (const label of arm.labels) {
			text += indent(depth + 1) + "case " + expr(p, label) + ":\n";
		}
		if (arm.isDefault) { text += indent(depth + 1) + "default:\n"; }
		p.nesting.push(Nesting.Switch);
		text += indent(depth + 1) + "{\n" + arm.body.map((b) => stmt(p, b, depth + 2)).join("") +
			indent(depth + 2) + "break;\n" + indent(depth + 1) + "}\n";
		p.nesting.pop();
	}
	return text + indent(depth) + "}\n";
}

function stmt(p: Printer, s: ShaderStmt, depth: int32): string {
	const at = indent(depth);
	if (s.kind == StmtKind.Let && isExchange(s.expr) && !p.es) { return exchangeLet(p, s, at); }
	if (s.kind == StmtKind.Call && isExchange(s.expr)) {
		return at + atomicText(p, s.expr) + ";\n";
	}
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
		StmtKind.Break => p.nesting.length > 0 &&
			p.nesting[p.nesting.length - 1] == Nesting.Switch ?
			fail(p, "a break inside a switch case, which GLSL reads as leaving the switch") :
			at + "break;\n",
		StmtKind.Continue => at + "continue;\n",
		StmtKind.Return => isNone(s.expr) ? at + "return;\n" :
			at + "return " + expr(p, s.expr) + ";\n",
		StmtKind.Discard => at + "discard;\n",
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
			", which GLSL ES 3.00 has not (" + prefix + "sampler" + shape + ")") : plain(shape);
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
			", " + imageFormat(p, r.type.format) + ") uniform " + accessWord(r.type.access) +
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
			fail(p, "io '" + io.name + "' is linear, which GLSL ES 3.00 has not") :
			"noperspective ",
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
		const location = ioLocation(io, ordinals[way]);
		ordinals[way] += 1;
		const varying = p.stage == ShaderStage.Vertex ? way == 1 : way == 0;
		const placed = !varying || !p.es ? "layout(location = " + String(location) + ") " : "";
		const storage = way == 0 ? "in " : "out ";
		text += placed + (varying ? interpolation(p, io) : "") + storage +
			declaration(p, io.type, p.ioNames[i]) + ";\n";
	}
	return text;
}

// A uniform block is one `vec4 <block>[size / 16]` and each texture-sampler pair one combined
// sampler, both bound by name (src/webgpu/gl/backend.ms resolveUniforms, resolveTextureUnits).
export function printGlsl(
	m: ShaderModule,
	entryIndex: int32,
	slots: BindingSlot[],
	target: GlslTarget,
): Result<string, string> {
	const printable = printableEntry(m, entryIndex);
	if (!printable.ok) { return Result.err("printGlsl: " + printable.error); }
	const reads = printable.value;
	const entry = m.entries[entryIndex];
	const es = target == GlslTarget.Glsl300es;
	if (es && entry.stage == ShaderStage.Compute) {
		return Result.err("printGlsl: entry '" + entry.name + "' is compute, which GLSL ES 3.00 " +
			"has not");
	}

	let p = new Printer();
	p.reserved = glslKeywords().concat(glslFunctions());
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
	p.workgroupNames = m.workgroups.map((_w) => "");
	p.effects = m.functions.map((_f) => 0);

	let functions: int32[] = [];
	functionOrder(m, entry.functionIndex, [], functions);
	let structs: int32[] = [];
	for (const f of functions) {
		const callee = m.functions[f];
		for (const v of callee.params) { structOrder(m, v.type, structs); }
		for (const v of callee.locals) { structOrder(m, v.type, structs); }
		structOrder(m, callee.result, structs);
		stmtStructs(m, callee.body, true, structs);
	}
	for (const r of reads.resources) {
		if (m.resources[r].kind == ResourceKind.StorageBuffer) {
			structOrder(m, m.resources[r].type, structs);
		}
	}
	for (const c of reads.constants) { exprStructs(m, m.constants[c].value, true, structs); }
	for (const io of m.ios) {
		if (io.stage == entry.stage) { structOrder(m, io.type, structs); }
	}
	let constants: int32[] = [];
	for (const c of reads.constants) {
		let read = new ShaderExpr();
		read.kind = ExprKind.Constant;
		read.index = c;
		constantOrder(m, read, constants);
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
	let units: string[] = [];
	for (const s of slots) {
		if (s.texture < 0) { continue; }
		if (!units.includes(s.nativeName)) { units.push(s.nativeName); }
		if (s.stage == entry.stage) {
			const pair: Pair = {
				texture: s.texture,
				sampler: s.resource,
				name: claimFixed(p, s.nativeName, "combined sampler"),
				unit: units.indexOf(s.nativeName) as int32,
			};
			p.pairs.push(pair);
		}
	}
	for (const r of resources) {
		if (m.resources[r].kind != ResourceKind.UniformBlock) { continue; }
		p.blockNames[r] = claimFixed(p, m.resources[r].name, "uniform block");
		const layout = uniformBlockLayout(m, r);
		if (!layout.ok) { return Result.err("printGlsl: " + layout.error); }
		p.blockOffsets[r] = layout.value.offsets;
	}
	let varyingNames = m.ios.filter((io) => io.stage == ShaderStage.Vertex &&
		io.direction == IoDirection.In && io.builtin == Builtin.None).map((io) => io.name);
	for (let i = 0; i < m.ios.length; i++) {
		const io = m.ios[i];
		if (io.stage != entry.stage || io.builtin != Builtin.None) { continue; }
		const varying = io.stage == ShaderStage.Vertex ? io.direction == IoDirection.Out :
			io.stage == ShaderStage.Fragment && io.direction == IoDirection.In;
		p.ioNames[i] = varying ? claimFixed(p, claim(p, varyingNames, io.name), "varying") :
			claimFixed(p, io.name, "io");
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
	for (const w of reads.workgroups) {
		p.workgroupNames[w] = claim(p, p.globals, m.workgroups[w].name);
	}
	for (const f of functions) {
		p.functionNames[f] = f == entry.functionIndex ? "main" :
			claim(p, p.globals, m.functions[f].name);
	}
	let exchanges = "";
	for (const f of functions) {
		for (const v of m.functions[f].locals) {
			const slot = v.type.kind == ShaderTypeKind.ExchangeResult ?
				exchangeSlot(v.type.scalar) : -1;
			if (slot < 0 || p.exchangeNames[slot] != "") { continue; }
			p.exchangeNames[slot] = claim(p, p.globals, slot == 0 ? "AtomicExchangeI32" :
				"AtomicExchangeU32");
			exchanges += "struct " + p.exchangeNames[slot] + "\n{\n    " +
				scalarName(v.type.scalar) + " old_value;\n    bool exchanged;\n};\n\n";
		}
	}
	for (const t of splitResults(m, functions)) {
		if (es && t.kind == ShaderTypeKind.FrexpResult) { continue; }
		p.splits.push(t);
		const structName = claim(p, p.globals, splitStructName(t));
		const helperName = claim(p, p.globals, splitHelperName(t));
		p.splitStructs.push(structName);
		p.splitHelpers.push(helperName);
		const types = glslSplitTypes(t);
		const call = t.kind == ShaderTypeKind.ModfResult ? "modf" : "frexp";
		exchanges += "struct " + structName + "\n{\n    " + types[0] + " " + splitMember(t, 0) + ";\n    " +
			types[1] + " " + splitMember(t, 1) + ";\n};\n\n" +
			structName + " " + helperName + "(" + types[0] + " arg)\n{\n    " + types[1] + " other;\n    " +
			types[0] + " part = " + call + "(arg, other);\n    return " + structName + "(part, other);\n}\n\n";
	}

	const version = es ? "#version 300 es\n" : "#version 430\n";
	let head = "";
	if (es && entry.stage == ShaderStage.Fragment) {
		head += "precision highp float;\nprecision highp int;\n";
	}
	head += "\n";
	if (entry.stage == ShaderStage.Compute) {
		const axes = ["x", "y", "z"];
		head += "layout(" + entry.workgroupSize.map((n, i) => "local_size_" + axes[i] + " = " +
			String(n)).join(", ") + ") in;\n\n";
	}
	for (const s of structs) { head += structText(p, s); }
	head += exchanges;
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
	for (const w of reads.workgroups) {
		head += "shared " + declaration(p, m.workgroups[w].type, p.workgroupNames[w]) + ";\n";
	}
	if (reads.workgroups.length > 0) { head += "\n"; }
	const bodies = functions.map((f) => functionText(p, f)).join("\n");
	if (p.error != "") { return Result.err(p.error); }
	const extensions = p.samplesQueried ? "#extension GL_ARB_shader_texture_image_samples : require\n" : "";
	return Result.ok(version + extensions + head + bodies);
}
