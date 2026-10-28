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
	ShaderResource,
	ShaderStage,
	ShaderStmt,
	ShaderType,
	ShaderTypeKind,
	StmtKind,
	TexelFormat,
	TextureShape,
	UnaryOp,
	texelScalar,
	hasOffset,
	isArrayTexture,
	sampleBase,
	isAtomic,
	isUniformLoad,
	zeroOf,
} from "./ir";
import { BindingSlot, storageElementLayout, uniformBlockLayout } from "./layout";
import {
	constantsInOrder,
	entryStructs,
	functionOrder,
	hasEffect,
	innermost,
	ioLocation,
	ofKinds,
	withoutSamplers,
} from "./irWalk";
import {
	binaryOperator,
	componentCompare,
	floatText,
	isComponentCompare,
	isIntMin,
	mathName,
	pointed,
	splitHelperName,
	splitMember,
	splitStructName,
	scalarName,
} from "./spelling";
import { claimName } from "./names";
import { demotedDiscards } from "./demote";
import { printableEntry } from "./specialize";

function hlslKeywords(): string[] {
	return [
		"AppendStructuredBuffer", "asm", "asm_fragment", "BlendState", "bool", "break", "Buffer",
		"ByteAddressBuffer", "case", "cbuffer", "centroid", "class", "column_major", "compile",
		"compile_fragment", "CompileShader", "const", "continue", "ComputeShader",
		"ConsumeStructuredBuffer", "default", "DepthStencilState", "DepthStencilView", "discard",
		"do", "double", "DomainShader", "dword", "else", "export", "extern", "false", "float",
		"for", "fxgroup", "GeometryShader", "groupshared", "half", "Hullshader", "HullShader", "if",
		"in", "inline", "inout", "InputPatch", "int", "interface", "line", "lineadj", "linear",
		"LineStream", "matrix", "min16float", "min10float", "min16int", "min12int", "min16uint",
		"namespace", "nointerpolation", "noperspective", "NULL", "out", "OutputPatch", "packoffset",
		"pass", "pixelfragment", "PixelShader", "point", "PointStream", "precise",
		"RasterizerState", "RenderTargetView", "return", "register", "row_major", "RWBuffer",
		"RWByteAddressBuffer", "RWStructuredBuffer", "RWTexture1D", "RWTexture1DArray",
		"RWTexture2D", "RWTexture2DArray", "RWTexture3D", "sample", "sampler", "SamplerState",
		"SamplerComparisonState", "shared", "snorm", "stateblock", "stateblock_state", "static",
		"string", "struct", "switch", "StructuredBuffer", "tbuffer", "technique", "technique10",
		"technique11", "texture", "Texture1D", "Texture1DArray", "Texture2D", "Texture2DArray",
		"Texture2DMS", "Texture2DMSArray", "Texture3D", "TextureCube", "TextureCubeArray", "true",
		"typedef", "triangle", "triangleadj", "TriangleStream", "uint", "uniform", "unorm",
		"unsigned", "vector", "vertexfragment", "VertexShader", "void", "volatile", "while",
		"sampler1D", "sampler2D", "sampler3D", "samplerCUBE", "sampler_state", "auto", "catch",
		"char", "const_cast", "delete", "dynamic_cast", "enum", "explicit", "friend", "goto",
		"long", "mutable", "new", "operator", "private", "protected", "public", "reinterpret_cast",
		"short", "signed", "sizeof", "static_cast", "template", "this", "throw", "try", "typename",
		"union", "using", "virtual",
	];
}

function hlslIntrinsics(): string[] {
	return [
		"abort", "abs", "acos", "all", "AllMemoryBarrier", "AllMemoryBarrierWithGroupSync", "any",
		"asdouble", "asfloat", "asin", "asint", "asuint", "atan", "atan2", "ceil",
		"CheckAccessFullyMapped", "clamp", "clip", "cos", "cosh", "countbits", "cross",
		"D3DCOLORtoUBYTE4", "ddx", "ddx_coarse", "ddx_fine", "ddy", "ddy_coarse", "ddy_fine",
		"degrees", "determinant", "DeviceMemoryBarrier", "DeviceMemoryBarrierWithGroupSync",
		"distance", "dot", "dst", "errorf", "EvaluateAttributeAtCentroid",
		"EvaluateAttributeAtSample", "EvaluateAttributeSnapped", "exp", "exp2", "f16tof32",
		"f32tof16", "faceforward", "firstbithigh", "firstbitlow", "floor", "fma", "fmod", "frac",
		"frexp", "fwidth", "GetRenderTargetSampleCount", "GetRenderTargetSamplePosition",
		"GroupMemoryBarrier", "GroupMemoryBarrierWithGroupSync", "InterlockedAdd", "InterlockedAnd",
		"InterlockedCompareExchange", "InterlockedCompareStore", "InterlockedExchange",
		"InterlockedMax", "InterlockedMin", "InterlockedOr", "InterlockedXor", "isfinite", "isinf",
		"isnan", "ldexp", "length", "lerp", "lit", "log", "log10", "log2", "mad", "max", "min",
		"modf", "msad4", "mul", "noise", "normalize", "pow", "printf",
		"Process2DQuadTessFactorsAvg", "Process2DQuadTessFactorsMax", "Process2DQuadTessFactorsMin",
		"ProcessIsolineTessFactors", "ProcessQuadTessFactorsAvg", "ProcessQuadTessFactorsMax",
		"ProcessQuadTessFactorsMin", "ProcessTriTessFactorsAvg", "ProcessTriTessFactorsMax",
		"ProcessTriTessFactorsMin", "radians", "rcp", "reflect", "refract", "reversebits", "round",
		"rsqrt", "saturate", "sign", "sin", "sincos", "smoothstep", "sqrt", "step", "tan", "tanh",
		"tex1D", "tex1Dbias", "tex1Dgrad", "tex1Dlod", "tex1Dproj", "tex2D", "tex2Dbias",
		"tex2Dgrad", "tex2Dlod", "tex2Dproj", "tex3D", "tex3Dbias", "tex3Dgrad", "tex3Dlod",
		"tex3Dproj", "texCUBE", "texCUBEbias", "texCUBEgrad", "texCUBElod", "texCUBEproj",
		"transpose", "trunc",
	];
}

const SWIZZLE = "xyzw";

function isNumericTypeName(name: string): boolean {
	const bases = [
		"bool", "int", "uint", "dword", "half", "float", "double", "min16float", "min10float",
		"min16int", "min12int", "min16uint",
	];
	for (const base of bases) {
		if (!name.startsWith(base)) { continue; }
		const rest = name.substring(base.length);
		const digit = (at: int32) =>
			rest.length > at && "1234".includes(rest.substring(at, at + 1));
		if (rest.length == 1 && digit(0)) { return true; }
		if (rest.length == 3 && digit(0) && rest.substring(1, 2) == "x" && digit(2)) {
			return true;
		}
	}
	return false;
}

function isReserved(p: Printer, name: string): boolean {
	return p.reserved.includes(name) || isNumericTypeName(name);
}

function claim(p: Printer, taken: string[], name: string): string {
	return claimName(taken, (n) => isReserved(p, n), name);
}

enum Nesting {
	Loop,
	Switch,
}

class Printer {
	module: ShaderModule = new ShaderModule();
	stage: ShaderStage = ShaderStage.Vertex;
	error: string = "";
	globals: string[] = [];
	localsEver: string[] = [];
	structNames: string[] = [];
	fieldNames: string[][] = [];
	constantNames: string[] = [];
	resourceNames: string[] = [];
	memberNames: string[][] = [];
	memberColumns: string[][][] = [];
	ioNames: string[] = [];
	functionNames: string[] = [];
	workgroupNames: string[] = [];
	privateNames: string[] = [];
	effects: int32[] = [];
	scope: string[] = [];
	current: ShaderFunction = new ShaderFunction();
	nesting: Nesting[] = [];
	helperKeys: string[] = [];
	helperBases: string[] = [];
	helperNames: string[] = [];
	helpers: string[] = [];
	reserved: string[] = [];
}

function fail(p: Printer, message: string): string {
	if (p.error == "") { p.error = "printHlsl: " + message; }
	return "";
}

function arraySuffix(t: ShaderType): string {
	return t.kind == ShaderTypeKind.Array ?
		"[" + String(t.length) + "]" + arraySuffix(t.element[0]) : "";
}

function textureTypeName(t: ShaderType): string {
	const texel = scalarName(t.scalar) + "4";
	return match (t.shape) {
		TextureShape.D1 => "Texture1D<" + texel + ">",
		TextureShape.D2 => "Texture2D<" + texel + ">",
		TextureShape.D2Array => "Texture2DArray<" + texel + ">",
		TextureShape.D3 => "Texture3D<" + texel + ">",
		TextureShape.Cube => "TextureCube<" + texel + ">",
		TextureShape.CubeArray => "TextureCubeArray<" + texel + ">",
		TextureShape.Depth2d => "Texture2D<float>",
		TextureShape.Depth2dArray => "Texture2DArray<float>",
		TextureShape.DepthCube => "TextureCube<float>",
		TextureShape.Multisampled2d => "Texture2DMS<" + texel + ">",
	};
}

function texelOf(format: TexelFormat): string {
	return match (format) {
		TexelFormat.Rgba8unorm => "unorm float4",
		TexelFormat.Rgba8snorm => "snorm float4",
		TexelFormat.Bgra8unorm => "unorm float4",
		TexelFormat.Rgba8uint | TexelFormat.Rgba16uint | TexelFormat.Rgba32uint => "uint4",
		TexelFormat.Rgba8sint | TexelFormat.Rgba16sint | TexelFormat.Rgba32sint => "int4",
		TexelFormat.Rgba16float | TexelFormat.Rgba32float => "float4",
		TexelFormat.R32float => "float",
		TexelFormat.R32uint => "uint",
		TexelFormat.R32sint => "int",
		TexelFormat.Rg32float => "float2",
		TexelFormat.Rg32uint => "uint2",
		TexelFormat.Rg32sint => "int2",
	};
}

function texelWidth(format: TexelFormat): int32 {
	return match (format) {
		TexelFormat.R32float | TexelFormat.R32uint | TexelFormat.R32sint => 1,
		TexelFormat.Rg32float | TexelFormat.Rg32uint | TexelFormat.Rg32sint => 2,
		TexelFormat.Rgba8unorm | TexelFormat.Rgba8snorm | TexelFormat.Rgba8uint |
			TexelFormat.Rgba8sint | TexelFormat.Rgba16uint | TexelFormat.Rgba16sint |
			TexelFormat.Rgba16float | TexelFormat.Rgba32uint | TexelFormat.Rgba32sint |
			TexelFormat.Rgba32float | TexelFormat.Bgra8unorm => 4,
	};
}

function typeName(p: Printer, t: ShaderType): string {
	return match (t.kind) {
		ShaderTypeKind.Void => "void",
		ShaderTypeKind.Scalar => scalarName(t.scalar),
		ShaderTypeKind.Vector => scalarName(t.scalar) + String(t.rows),
		ShaderTypeKind.Matrix => "float" + String(t.columns) + "x" + String(t.rows),
		ShaderTypeKind.Array => typeName(p, innermost(t)),
		ShaderTypeKind.RuntimeArray => fail(p, "a runtime array is only a storage buffer"),
		ShaderTypeKind.Struct => p.structNames[t.structIndex],
		ShaderTypeKind.Texture => textureTypeName(t),
		ShaderTypeKind.Sampler => "SamplerState",
		ShaderTypeKind.StorageTexture => match (t.shape) {
			TextureShape.D1 => "RWTexture1D<" + texelOf(t.format) + ">",
			TextureShape.D2 => "RWTexture2D<" + texelOf(t.format) + ">",
			TextureShape.D2Array => "RWTexture2DArray<" + texelOf(t.format) + ">",
			TextureShape.D3 => "RWTexture3D<" + texelOf(t.format) + ">",
			_ => fail(p, "a storage texture of shape " + t.shape.toString()),
		},
		ShaderTypeKind.Atomic => scalarName(t.scalar),
		ShaderTypeKind.ExchangeResult => exchangeResult(p, t.scalar),
		ShaderTypeKind.ModfResult | ShaderTypeKind.FrexpResult => splitResult(p, t),
	};
}

function exchangeResult(p: Printer, scalar: ScalarKind): string {
	const suffix = scalar == ScalarKind.I32 ? "I32" : "U32";
	return helper(p, "exchange " + suffix, "AtomicExchange" + suffix, (n) => "struct " + n +
		"\n{\n    " + scalarName(scalar) + " old_value;\n    bool exchanged;\n};\n");
}

function splitTypes(t: ShaderType): string[] {
	const fract = t.rows == 1 ? "float" : "float" + String(t.rows);
	if (t.kind == ShaderTypeKind.ModfResult) { return [fract, fract]; }
	return [fract, t.rows == 1 ? "int" : "int" + String(t.rows)];
}

// frexp and modf hand back one half through an
// out parameter, and frexp's mantissa is signed by hand because HLSL's carries no sign.
function splitResult(p: Printer, t: ShaderType): string {
	const types = splitTypes(t);
	return helper(p, "split " + splitStructName(t), splitStructName(t), (n) => "struct " + n +
		"\n{\n    " + types[0] + " " + splitMember(t, 0) + ";\n    " + types[1] + " " +
		splitMember(t, 1) + ";\n};\n");
}

function splitCall(p: Printer, e: ShaderExpr): string {
	const result = splitResult(p, e.type);
	const types = splitTypes(e.type);
	const modf = e.type.kind == ShaderTypeKind.ModfResult;
	const name = helper(p, "splitCall " + splitStructName(e.type), splitHelperName(e.type), (n) =>
		result + " " + n + "(" + types[0] + " arg)\n{\n    " + types[0] + " other;\n    " + result +
		" result;\n    result." + splitMember(e.type, 0) + " = " +
		(modf ? "modf" : "sign(arg) * frexp") + "(arg, other);\n    result." +
		splitMember(e.type, 1) + " = " +
		(modf ? "other" : types[1] + "(other)") + ";\n    return result;\n}\n");
	return name + "(" + expr(p, e.operands[0]) + ")";
}

function temporary(p: Printer, name: string): string {
	const named = claim(p, p.globals.concat(p.scope), name);
	p.scope.push(named);
	p.localsEver.push(named);
	return named;
}

function interlockedName(p: Printer, op: Intrinsic): string {
	return match (op) {
		Intrinsic.AtomicLoad | Intrinsic.AtomicAdd | Intrinsic.AtomicSub => "InterlockedAdd",
		Intrinsic.AtomicMax => "InterlockedMax",
		Intrinsic.AtomicMin => "InterlockedMin",
		Intrinsic.AtomicAnd => "InterlockedAnd",
		Intrinsic.AtomicOr => "InterlockedOr",
		Intrinsic.AtomicXor => "InterlockedXor",
		Intrinsic.AtomicStore | Intrinsic.AtomicExchange => "InterlockedExchange",
		_ => fail(p, op.toString() + " has no Interlocked spelling"),
	};
}

// Interlocked* hands the old value back through an out parameter,
// so an atomic is a statement of its own, a load is an add of 0 and a store an exchange.
function atomicStatement(p: Printer, e: ShaderExpr, result: string, at: string): string {
	const o = e.operands;
	const place = expr(p, o[0]);
	const scalar = scalarName(o[0].type.scalar);
	if (e.intrinsic == Intrinsic.AtomicCompareExchangeWeak) {
		if (result == "") {
			return at + "InterlockedCompareStore(" + place + ", " + expr(p, o[1]) + ", " +
				expr(p, o[2]) + ");\n";
		}
		const compare = temporary(p, "compare");
		return at + scalar + " " + compare + " = " + expr(p, o[1]) + ";\n" +
			at + typeName(p, e.type) + " " + result + ";\n" +
			at + "InterlockedCompareExchange(" + place + ", " + compare + ", " + expr(p, o[2]) +
			", " + result + ".old_value);\n" +
			at + result + ".exchanged = " + result + ".old_value == " + compare + ";\n";
	}
	const value = match (e.intrinsic) {
		Intrinsic.AtomicLoad => "0",
		Intrinsic.AtomicSub => "-" + operand(p, o[1]),
		Intrinsic.AtomicStore | Intrinsic.AtomicAdd | Intrinsic.AtomicMax | Intrinsic.AtomicMin |
			Intrinsic.AtomicAnd | Intrinsic.AtomicOr | Intrinsic.AtomicXor |
			Intrinsic.AtomicExchange =>
			expr(p, o[1]),
		_ => fail(p, e.intrinsic.toString() + " has no Interlocked spelling"),
	};
	const exchange = e.intrinsic == Intrinsic.AtomicStore ||
		e.intrinsic == Intrinsic.AtomicExchange;
	let out = result;
	let head = "";
	if (out == "" && exchange) {
		out = temporary(p, "exchanged");
		head = at + scalar + " " + out + ";\n";
	}
	return head + at + interlockedName(p, e.intrinsic) + "(" + place + ", " + value +
		(out == "" ? "" : ", " + out) + ");\n";
}

function declaration(p: Printer, t: ShaderType, name: string): string {
	const major = innermost(t).kind == ShaderTypeKind.Matrix ? "row_major " : "";
	return major + typeName(p, t) + " " + name + arraySuffix(t);
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
		ShaderTypeKind.Vector => typeName(p, t) + "(" + repeated(one, t.rows) + ")",
		ShaderTypeKind.Matrix => "((" + typeName(p, t) + ")" + one + ")",
		_ => fail(p, "a literal of " + t.kind.toString()),
	};
}

function bothSides(p: Printer, what: string, sides: ShaderExpr[]): void {
	if (sides.some((s) => hasEffect(p.module, p.effects, s))) {
		fail(p, "'" + what + "' evaluates every operand in HLSL, and one of them has an effect");
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

function isMatrix(t: ShaderType): boolean { return t.kind == ShaderTypeKind.Matrix; }

function isTwoRowMatrix(t: ShaderType): boolean { return isMatrix(t) && t.rows == 2; }

function blockMemberText(p: Printer, e: ShaderExpr): string {
	const columns = p.memberColumns[e.index][e.member];
	return columns.length == 0 ? p.memberNames[e.index][e.member] :
		typeName(p, e.type) + "(" + columns.join(", ") + ")";
}

function isScalarKind(t: ShaderType, s: ScalarKind): boolean {
	return (t.kind == ShaderTypeKind.Scalar || t.kind == ShaderTypeKind.Vector) && t.scalar == s;
}

function product(p: Printer, a: ShaderExpr, b: ShaderExpr): string {
	const scalar = a.type.kind == ShaderTypeKind.Scalar || b.type.kind == ShaderTypeKind.Scalar;
	if ((isMatrix(a.type) || isMatrix(b.type)) && !scalar) {
		return "mul(" + expr(p, b) + ", " + expr(p, a) + ")";
	}
	return operand(p, a) + " * " + operand(p, b);
}

function remainder(p: Printer, a: ShaderExpr, b: ShaderExpr): string {
	if (isScalarKind(a.type, ScalarKind.F32)) {
		return "fmod(" + expr(p, a) + ", " + expr(p, b) + ")";
	}
	if (isScalarKind(a.type, ScalarKind.U32)) { return operand(p, a) + " % " + operand(p, b); }
	return fail(p, "'%' of " + a.type.scalar.toString() + ": HLSL leaves a negative operand " +
		"undefined");
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
	if (e.binary == BinaryOp.Mul) { return product(p, a, b); }
	if (e.binary == BinaryOp.Mod) { return remainder(p, a, b); }
	if (e.binary == BinaryOp.LogicalAnd || e.binary == BinaryOp.LogicalOr) {
		bothSides(p, op, [b]);
	}
	const plain = operand(p, a) + " " + op + " " + operand(p, b);
	const folds = e.type.kind == ShaderTypeKind.Scalar && a.type.kind == ShaderTypeKind.Vector;
	if (!folds) { return plain; }
	return match (e.binary) {
		BinaryOp.Equal => "all(" + plain + ")",
		BinaryOp.NotEqual => "any(" + plain + ")",
		_ => fail(p, "'" + op + "' of two vectors into one bool"),
	};
}

function helper(p: Printer, key: string, name: string, write: (n: string) => string): string {
	const at = p.helperKeys.indexOf(key);
	if (at >= 0) { return p.helperNames[at]; }
	const base = p.helperBases.indexOf(name);
	const named = base >= 0 ? p.helperNames[base] : claimHelper(p, name);
	p.helperKeys.push(key);
	p.helperBases.push(name);
	p.helperNames.push(named);
	p.helpers.push(write(named));
	return named;
}

function claimHelper(p: Printer, name: string): string {
	const named = claim(p, p.globals.concat(p.localsEver), name);
	p.globals.push(named);
	return named;
}

function inverseOf(p: Printer, e: ShaderExpr): string {
	const t = e.operands[0].type;
	if (!isMatrix(t) || t.columns != t.rows) {
		return fail(p, "Inverse of a " + t.kind.toString() + " that is no square matrix");
	}
	const typeText = typeName(p, t);
	const body = match (t.rows) {
		2 => "    return float2x2(m[1][1], -m[0][1], -m[1][0], m[0][0]) / determinant(m);\n",
		3 => "    float3 a = m[0];\n    float3 b = m[1];\n    float3 c = m[2];\n" +
			"    return transpose(float3x3(cross(b, c), cross(c, a), cross(a, b))) / " +
			"dot(a, cross(b, c));\n",
		_ => "    float3 a = m[0].xyz;\n    float3 b = m[1].xyz;\n    float3 c = m[2].xyz;\n" +
			"    float3 d = m[3].xyz;\n" +
			"    float x = m[0].w;\n    float y = m[1].w;\n    float z = m[2].w;\n" +
			"    float w = m[3].w;\n" +
			"    float3 s = cross(a, b);\n    float3 t = cross(c, d);\n" +
			"    float3 u = a * y - b * x;\n    float3 v = c * w - d * z;\n" +
			"    float k = 1.0 / (dot(s, v) + dot(t, u));\n" +
			"    s *= k;\n    t *= k;\n    u *= k;\n    v *= k;\n" +
			"    return transpose(float4x4(float4(cross(b, v) + t * y, -dot(b, t)), " +
			"float4(cross(v, a) - t * x, dot(a, t)), float4(cross(d, u) + s * w, -dot(d, s)), " +
			"float4(cross(u, c) - s * z, dot(c, s))));\n",
	};
	const name = helper(p, "inverse " + typeText, "inverse",
		(n) => typeText + " " + n + "(" + typeText + " m)\n{\n" + body + "}\n");
	return name + "(" + expr(p, e.operands[0]) + ")";
}

function converted(p: Printer, text: string, from: string, to: ShaderType): string {
	const target = typeName(p, to);
	return from == target ? text : target + "(" + text + ")";
}

function storageSizeNames(p: Printer, shape: TextureShape): string[] {
	if (shape == TextureShape.D3) { return ["width", "height", "depth"]; }
	if (shape == TextureShape.D2Array) { return ["width", "height", "layers"]; }
	if (shape == TextureShape.D2) { return ["width", "height"]; }
	if (shape == TextureShape.D1) { return ["width"]; }
	fail(p, "a storage texture of shape " + shape.toString());
	return [];
}

function sizeRows(shape: TextureShape): int32 {
	return shape == TextureShape.D3 ? 3 : shape == TextureShape.D1 ? 1 : 2;
}

function sizeType(shape: TextureShape): string {
	return sizeRows(shape) == 1 ? "uint" : "uint" + String(sizeRows(shape));
}

function sizeResult(shape: TextureShape, result: string, kept: string): string {
	return sizeRows(shape) == 1 ? kept : result + "(" + kept + ")";
}

function sizeOf(p: Printer, e: ShaderExpr): string {
	const args = withoutSamplers(e.operands);
	const t = args[0].type;
	const texture = expr(p, args[0]);
	if (t.kind == ShaderTypeKind.StorageTexture) {
		const typeText = typeName(p, t);
		const sizes = storageSizeNames(p, t.shape);
		const result = sizeType(t.shape);
		const kept = sizes.slice(0, sizeRows(t.shape)).join(", ");
		const name = helper(p, "imageSize " + typeText, "imageSize", (n) =>
			result + " " + n + "(" + typeText + " image)\n{\n" +
			sizes.map((s) => "    uint " + s + ";\n").join("") +
			"    image.GetDimensions(" + sizes.join(", ") + ");\n" +
			"    return " + sizeResult(t.shape, result, kept) + ";\n}\n");
		return converted(p, name + "(" + texture + ")", result, e.type);
	}
	if (t.kind != ShaderTypeKind.Texture) {
		return fail(p, "TextureDimensions of a " + t.kind.toString());
	}
	const level = args.length > 1 ? "uint(" + expr(p, args[1]) + ")" : "0u";
	const typeText = typeName(p, t);
	const result = sizeType(t.shape);
	const outs = match (t.shape) {
		TextureShape.D1 => ["width", "levels"],
		TextureShape.D3 => ["width", "height", "depth", "levels"],
		TextureShape.D2Array | TextureShape.Depth2dArray | TextureShape.CubeArray =>
			["width", "height", "layers", "levels"],
		TextureShape.D2 | TextureShape.Cube | TextureShape.Depth2d | TextureShape.DepthCube |
			TextureShape.Multisampled2d => ["width", "height", "levels"],
	};
	if (t.shape == TextureShape.Multisampled2d) {
		const name = helper(p, "textureSize " + typeText, "textureSize", (n) =>
			"uint2 " + n + "(" + typeText + " t)\n{\n    uint width;\n    uint height;\n" +
			"    uint samples;\n    t.GetDimensions(width, height, samples);\n" +
			"    return uint2(width, height);\n}\n");
		return converted(p, name + "(" + texture + ")", "uint2", e.type);
	}
	const kept = outs.slice(0, sizeRows(t.shape)).join(", ");
	const name = helper(p, "textureSize " + typeText, "textureSize", (n) =>
		result + " " + n + "(" + typeText + " t, uint level)\n{\n" +
		outs.map((o) => "    uint " + o + ";\n").join("") +
		"    t.GetDimensions(level, " + outs.join(", ") + ");\n" +
		"    return " + sizeResult(t.shape, result, kept) + ";\n}\n");
	return converted(p, name + "(" + texture + ", " + level + ")", result, e.type);
}

function samplesOf(p: Printer, e: ShaderExpr): string {
	const typeText = typeName(p, e.operands[0].type);
	const name = helper(p, "textureSamples " + typeText, "textureSamples", (n) =>
		"uint " + n + "(" + typeText + " t)\n{\n    uint width;\n    uint height;\n" +
		"    uint samples;\n    t.GetDimensions(width, height, samples);\n" +
		"    return samples;\n}\n");
	return converted(p, name + "(" + expr(p, e.operands[0]) + ")", "uint", e.type);
}

function lengthOf(p: Printer, e: ShaderExpr): string {
	const typeText = bufferTypeName(p, p.module.resources[e.operands[0].index]);
	const name = helper(p, "arrayLength " + typeText, "arrayLength", (n) =>
		"uint " + n + "(" + typeText + " b)\n{\n    uint count;\n    uint stride;\n" +
		"    b.GetDimensions(count, stride);\n    return count;\n}\n");
	return converted(p, name + "(" + expr(p, e.operands[0]) + ")", "uint", e.type);
}

function loadOf(p: Printer, e: ShaderExpr): string {
	const args = withoutSamplers(e.operands);
	const t = args[0].type;
	const texture = operand(p, args[0]);
	if (args.length < 2) { return fail(p, "TextureLoad without coordinates"); }
	const at = expr(p, args[1]);
	const levelAt = t.shape == TextureShape.D2Array ? 3 : 2;
	const level = args.length > levelAt ? expr(p, args[levelAt]) : "0";
	if (t.kind == ShaderTypeKind.StorageTexture) {
		if (texelWidth(t.format) != 1) {
			return fail(p, "TextureLoad of a " + t.format.toString() + " storage texture: SM5 " +
				"loads typed UAVs of one 32-bit channel only");
		}
		const texel = texture + "[" + storageAt(p, args) + "]";
		if (e.type.kind != ShaderTypeKind.Vector) { return texel; }
		const channel = texelScalar(t.format);
		return scalarName(channel) + "4(" + texel + (channel == ScalarKind.U32 ? ", 0u, 0u, 1u)" :
			channel == ScalarKind.I32 ? ", 0, 0, 1)" : ", 0.0, 0.0, 1.0)");
	}
	if (t.kind != ShaderTypeKind.Texture) {
		return fail(p, "TextureLoad of a " + t.kind.toString());
	}
	return match (t.shape) {
		TextureShape.D1 => texture + ".Load(int2(" + at + ", " + level + "))",
		TextureShape.D2 | TextureShape.Depth2d =>
			texture + ".Load(int3(" + at + ", " + level + "))",
		TextureShape.D3 => texture + ".Load(int4(" + at + ", " + level + "))",
		TextureShape.D2Array =>
			texture + ".Load(int4(" + at + ", " + expr(p, args[2]) + ", " + level + "))",
		TextureShape.Multisampled2d => texture + ".Load(int2(" + at + "), " + level + ")",
		_ => fail(p, "TextureLoad of a " + t.shape.toString() + " texture"),
	};
}

function layeredAt(p: Printer, e: ShaderExpr): string {
	const t = e.operands[0].type;
	if (!isArrayTexture(t)) { return expr(p, e.operands[2]); }
	return (t.shape == TextureShape.CubeArray ? "float4(" : "float3(") + expr(p, e.operands[2]) +
		", float(" + expr(p, e.operands[3]) + "))";
}

function sampleOf(p: Printer, e: ShaderExpr): string {
	const layered = e.operands.length > 0 && isArrayTexture(e.operands[0].type);
	const base = layered ? 4 : 3;
	const offset = e.operands.length == base ? "" : ", " + expr(p, e.operands[base]);
	const [texture, sampler] = [e.operands[0], e.operands[1]];
	if (p.stage != ShaderStage.Fragment) {
		return operand(p, texture) + ".SampleLevel(" + expr(p, sampler) + ", " +
			layeredAt(p, e) + ", 0.0" + offset + ")";
	}
	return operand(p, texture) + ".Sample(" + expr(p, sampler) + ", " + layeredAt(p, e) +
		offset + ")";
}

function explicitSampleOf(p: Printer, e: ShaderExpr): string {
	const o = e.operands;
	const t = o[0].type;
	const layer = isArrayTexture(t) ? 1 : 0;
	const at = layeredAt(p, e);
	const tail = o.slice(3 + layer, sampleBase(e) + (hasOffset(e) ? 1 : 0)).map((a) =>
		expr(p, a)).join(", ");
	const method = match (e.intrinsic) {
		Intrinsic.TextureSampleLevel => ".SampleLevel(",
		Intrinsic.TextureSampleBias => ".SampleBias(",
		Intrinsic.TextureSampleGrad => ".SampleGrad(",
		_ => fail(p, e.intrinsic.toString() + " is no explicit sample"),
	};
	return operand(p, o[0]) + method + expr(p, o[1]) + ", " + at + ", " + tail + ")";
}

function compareOf(p: Printer, e: ShaderExpr, level: boolean): string {
	const layered = e.operands.length > 0 && isArrayTexture(e.operands[0].type);
	const base = layered ? 5 : 4;
	const [texture, sampler] = [e.operands[0], e.operands[1]];
	const reference = e.operands[base - 1];
	const offset = e.operands.length == base ? "" : ", " + expr(p, e.operands[base]);
	return operand(p, texture) + (level ? ".SampleCmpLevelZero(" : ".SampleCmp(") +
		expr(p, sampler) + ", " + layeredAt(p, e) + ", " + expr(p, reference) + offset + ")";
}

function storageAt(p: Printer, args: ShaderExpr[]): string {
	return match (args[0].type.shape) {
		TextureShape.D1 => "uint(" + expr(p, args[1]) + ")",
		TextureShape.D2 => "uint2(" + expr(p, args[1]) + ")",
		TextureShape.D2Array => "uint3(" + expr(p, args[1]) + ", " + expr(p, args[2]) + ")",
		TextureShape.D3 => "uint3(" + expr(p, args[1]) + ")",
		_ => fail(p, "a storage texture of shape " + args[0].type.shape.toString()),
	};
}

function storeOf(p: Printer, e: ShaderExpr): string {
	const o = e.operands;
	const wanted = o.length > 0 && o[0].type.shape == TextureShape.D2Array ? 4 : 3;
	if (o.length != wanted || o[0].type.kind != ShaderTypeKind.StorageTexture) {
		return fail(p, "TextureStore takes a storage texture, coordinates, a layer of an " +
			"array, and a value");
	}
	const width = texelWidth(o[0].type.format);
	const value = o[wanted - 1];
	const rows = value.type.kind == ShaderTypeKind.Vector ? value.type.rows : 1;
	const written = width < rows ?
		operand(p, value) + "." + SWIZZLE.substring(0, width) : expr(p, value);
	return operand(p, o[0]) + "[" + storageAt(p, o) + "] = " + written;
}

function intrinsicName(op: Intrinsic): string {
	return match (op) {
		Intrinsic.Fract => "frac",
		Intrinsic.InverseSqrt => "rsqrt",
		Intrinsic.Mix => "lerp",
		Intrinsic.Fma => "mad",
		Intrinsic.Dpdx => "ddx",
		Intrinsic.Dpdy => "ddy",
		Intrinsic.DpdxCoarse => "ddx_coarse",
		Intrinsic.DpdxFine => "ddx_fine",
		Intrinsic.DpdyCoarse => "ddy_coarse",
		Intrinsic.DpdyFine => "ddy_fine",
		_ => mathName(op),
	};
}

function packLanes(lanes: int32, width: int32, scale: string, signed: boolean): string {
	const names = ["x", "y", "z", "w"];
	let parts: string[] = [];
	for (let i = 0; i < lanes; i++) {
		const lane = signed ? "(int(round(clamp(e." + names[i] + ", -1.0, 1.0) * " + scale +
			")) & " + (width == 8 ? "0xFF" : "0xFFFF") + ")" :
			"uint(round(clamp(e." + names[i] + ", 0.0, 1.0) * " + scale + "))";
		parts.push(i == 0 ? lane : "(" + lane + " << " + String(i * width) + ")");
	}
	return signed ? "uint(" + parts.join(" | ") + ")" : parts.join(" | ");
}

function unpackLanes(width: int32, scale: string, signed: boolean): string {
	if (signed) {
		const shifts = width == 8 ? ["e << 24", "e << 16", "e << 8", "e"] : ["e << 16", "e"];
		const lanes = String(shifts.length);
		return "max(float" + lanes + "(int" + lanes + "(" + shifts.join(", ") + ") >> " +
			String(32 - width) + ") / " + scale + ", -1.0)";
	}
	const fields = width == 8 ? ["e & 0xFF", "(e >> 8) & 0xFF", "(e >> 16) & 0xFF", "e >> 24"] :
		["e & 0xFFFF", "e >> 16"];
	return "float" + String(fields.length) + "(" + fields.join(", ") + ") / " + scale;
}

function packText(op: Intrinsic): string {
	return match (op) {
		Intrinsic.Pack4x8Unorm => packLanes(4, 8, "255.0", false),
		Intrinsic.Pack4x8Snorm => packLanes(4, 8, "127.0", true),
		Intrinsic.Pack2x16Unorm => packLanes(2, 16, "65535.0", false),
		Intrinsic.Pack2x16Snorm => packLanes(2, 16, "32767.0", true),
		Intrinsic.Pack2x16Float => "f32tof16(e.x) | (f32tof16(e.y) << 16)",
		Intrinsic.Unpack4x8Unorm => unpackLanes(8, "255.0", false),
		Intrinsic.Unpack4x8Snorm => unpackLanes(8, "127.0", true),
		Intrinsic.Unpack2x16Unorm => unpackLanes(16, "65535.0", false),
		Intrinsic.Unpack2x16Snorm => unpackLanes(16, "32767.0", true),
		_ => "float2(f16tof32(e), f16tof32(e >> 16))",
	};
}

// HLSL has no intrinsic for these: each is a helper function, so an operand
// is evaluated once. FXC has no int overload of countbits, reversebits, firstbithigh and
// firstbitlow.
function bitsOf(p: Printer, e: ShaderExpr): string {
	const o = e.operands;
	const op = e.intrinsic;
	const isSigned = e.type.scalar == ScalarKind.I32;
	const t = typeName(p, e.type);
	if (op == Intrinsic.CountOneBits || op == Intrinsic.ReverseBits) {
		const call = (op == Intrinsic.CountOneBits ? "countbits(" : "reversebits(") +
			(isSigned ? "asuint(" + expr(p, o[0]) + "))" : expr(p, o[0]) + ")");
		return isSigned ? "asint(" + call + ")" : call;
	}
	if (op == Intrinsic.FirstLeadingBit || op == Intrinsic.FirstTrailingBit) {
		const call = (op == Intrinsic.FirstLeadingBit ? "firstbithigh(" : "firstbitlow(") +
			expr(p, o[0]) + ")";
		return isSigned ? "asint(" + call + ")" : call;
	}
	if (op == Intrinsic.CountLeadingZeros) {
		const call = "(31u - firstbithigh(" + (isSigned ? "asuint(" + expr(p, o[0]) + ")" :
			expr(p, o[0])) + "))";
		return isSigned ? "asint" + call : call;
	}
	if (op == Intrinsic.CountTrailingZeros) {
		const call = "min(32u, firstbitlow(" + (isSigned ? "asuint(" + expr(p, o[0]) + ")" :
			expr(p, o[0])) + "))";
		return isSigned ? "asint(" + call + ")" : call;
	}
	if (op == Intrinsic.ExtractBits) {
		const name = helper(p, "extractBits " + t, "extractBits", (n) =>
			t + " " + n + "(" + t + " e, uint offset, uint count)\n{\n" +
			"    uint w = 32u;\n    uint o = min(offset, w);\n    uint c = min(count, w - o);\n" +
			"    if (c == 0u) { return (" + t + ")0; }\n" +
			"    return (e << (w - c - o)) >> (w - c);\n}\n");
		return name + "(" + o.map((a) => expr(p, a)).join(", ") + ")";
	}
	if (op == Intrinsic.InsertBits) {
		const name = helper(p, "insertBits " + t, "insertBits", (n) =>
			t + " " + n + "(" + t + " e, " + t + " newBits, uint offset, uint count)\n{\n" +
			"    uint w = 32u;\n    uint o = min(offset, w);\n    uint c = min(count, w - o);\n" +
			"    if (c == 0u) { return e; }\n" +
			"    uint mask = (0xFFFFFFFFu >> (32u - c)) << o;\n" +
			"    return (e & ~mask) | ((newBits << o) & mask);\n}\n");
		return name + "(" + o.map((a) => expr(p, a)).join(", ") + ")";
	}
	const from = typeName(p, o[0].type);
	const name = helper(p, op.toString(), mathName(op), (n) =>
		t + " " + n + "(" + from + " e)\n{\n    return " + packText(op) + ";\n}\n");
	return name + "(" + expr(p, o[0]) + ")";
}

// HLSL has no asinh, acosh, atanh or coarse and fine fwidth: each is a helper, so an operand
// is evaluated once. asinh is odd by construction, where the plain form loses
// every digit of a large negative operand to the cancellation in e + sqrt(e * e + 1).
function polyfillOf(p: Printer, e: ShaderExpr): string {
	const op = e.intrinsic;
	const t = typeName(p, e.type);
	const body = match (op) {
		Intrinsic.Asinh => "sign(e) * log(abs(e) + sqrt(e * e + 1.0))",
		Intrinsic.Acosh => "log(e + sqrt(e * e - 1.0))",
		Intrinsic.Atanh => "0.5 * log((1.0 + e) / (1.0 - e))",
		Intrinsic.FwidthCoarse => "abs(ddx_coarse(e)) + abs(ddy_coarse(e))",
		Intrinsic.FwidthFine => "abs(ddx_fine(e)) + abs(ddy_fine(e))",
		_ => fail(p, op.toString() + " has no HLSL helper"),
	};
	const name = helper(p, op.toString() + " " + t, mathName(op), (n) =>
		t + " " + n + "(" + t + " e)
{
    return " + body + ";
}
");
	return name + "(" + expr(p, e.operands[0]) + ")";
}

function bitcastOf(p: Printer, e: ShaderExpr): string {
	const to = e.type.scalar;
	const name = to == ScalarKind.F32 ? "asfloat" : to == ScalarKind.I32 ? "asint" : "asuint";
	return name + "(" + expr(p, e.operands[0]) + ")";
}

function intrinsicText(p: Printer, e: ShaderExpr): string {
	const args = () => e.operands.map((o) => expr(p, o)).join(", ");
	if (isComponentCompare(e.intrinsic)) {
		return "(" + operand(p, e.operands[0]) + " " +
			binaryOperator(componentCompare(e.intrinsic)) + " " + operand(p, e.operands[1]) + ")";
	}
	return match (e.intrinsic) {
		Intrinsic.CountOneBits | Intrinsic.ReverseBits | Intrinsic.FirstLeadingBit |
			Intrinsic.FirstTrailingBit | Intrinsic.CountLeadingZeros |
			Intrinsic.CountTrailingZeros | Intrinsic.ExtractBits | Intrinsic.InsertBits |
			Intrinsic.Pack4x8Unorm | Intrinsic.Pack4x8Snorm | Intrinsic.Pack2x16Unorm |
			Intrinsic.Pack2x16Snorm | Intrinsic.Pack2x16Float | Intrinsic.Unpack4x8Unorm |
			Intrinsic.Unpack4x8Snorm | Intrinsic.Unpack2x16Unorm | Intrinsic.Unpack2x16Snorm |
			Intrinsic.Unpack2x16Float => bitsOf(p, e),
		Intrinsic.Asinh | Intrinsic.Acosh | Intrinsic.Atanh | Intrinsic.FwidthCoarse |
			Intrinsic.FwidthFine => polyfillOf(p, e),
		Intrinsic.Bitcast => bitcastOf(p, e),
		Intrinsic.Modf | Intrinsic.Frexp => splitCall(p, e),
		Intrinsic.Sign => converted(p, "sign(" + args() + ")", "int", e.type),
		Intrinsic.Inverse => inverseOf(p, e),
		Intrinsic.UpperLeft3x3 => "((float3x3)" + operand(p, e.operands[0]) + ")",
		Intrinsic.Select => {
			bothSides(p, "select", [e.operands[0], e.operands[1]]);
			return "(" + operand(p, e.operands[2]) + " ? " + operand(p, e.operands[1]) + " : " +
				operand(p, e.operands[0]) + ")";
		},
		Intrinsic.TextureSample => sampleOf(p, e),
		Intrinsic.TextureLoad => loadOf(p, e),
		Intrinsic.TextureStore => storeOf(p, e),
		Intrinsic.TextureDimensions => sizeOf(p, e),
		Intrinsic.TextureNumSamples => samplesOf(p, e),
		Intrinsic.TextureSampleCompare => compareOf(p, e, false),
		Intrinsic.TextureSampleCompareLevel => compareOf(p, e, true),
		Intrinsic.TextureSampleLevel | Intrinsic.TextureSampleBias | Intrinsic.TextureSampleGrad =>
			explicitSampleOf(p, e),
		Intrinsic.WorkgroupBarrier => "GroupMemoryBarrierWithGroupSync()",
		Intrinsic.StorageBarrier | Intrinsic.TextureBarrier => "DeviceMemoryBarrierWithGroupSync()",
		Intrinsic.WorkgroupUniformLoad => expr(p, e.operands[0]),
		Intrinsic.ArrayLength => lengthOf(p, e),
		_ => isAtomic(e.intrinsic) ? fail(p, e.intrinsic.toString() + " inside an expression or " +
			"a for header: Interlocked* hands its result back through an out parameter, so an " +
			"atomic is a statement or a local's initializer") :
			intrinsicName(e.intrinsic) + "(" + args() + ")",
	};
}

function structMaker(p: Printer, structIndex: int32): string {
	const s = p.module.structs[structIndex];
	const typeText = p.structNames[structIndex];
	return helper(p, "make " + typeText, "make" + typeText, (n) => {
		const params = s.members.map((f, i) => declaration(p, f.type, "v" + String(i)));
		const sets = s.members.map((f, i) => "    r." + p.fieldNames[structIndex][i] + " = v" +
			String(i) + ";\n");
		return typeText + " " + n + "(" + params.join(", ") + ")\n{\n    " + typeText +
			" r = (" + typeText + ")0;\n" + sets.join("") + "    return r;\n}\n";
	});
}

function constructText(p: Printer, e: ShaderExpr): string {
	const t = e.type;
	const args = e.operands.map((o) => expr(p, o)).join(", ");
	return match (t.kind) {
		ShaderTypeKind.Struct => structMaker(p, t.structIndex) + "(" + args + ")",
		ShaderTypeKind.Array =>
			fail(p, "an array value outside a local's or constant's initializer"),
		ShaderTypeKind.Vector | ShaderTypeKind.Matrix => {
			if (e.operands.length == 1 && e.operands[0].type.kind == ShaderTypeKind.Scalar) {
				if (isMatrix(t)) { return fail(p, "a matrix built from one scalar"); }
				return "((" + typeName(p, t) + ")" + operand(p, e.operands[0]) + ")";
			}
			if (e.operands.length == 1 && isMatrix(e.operands[0].type)) {
				return "((" + typeName(p, t) + ")" + operand(p, e.operands[0]) + ")";
			}
			return typeName(p, t) + "(" + args + ")";
		},
		_ => fail(p, "Construct of a " + t.kind.toString()),
	};
}

function initializer(p: Printer, e: ShaderExpr): string {
	if (e.kind == ExprKind.Construct && e.type.kind == ShaderTypeKind.Array) {
		return "{ " + e.operands.map((o) => initializer(p, o)).join(", ") + " }";
	}
	return expr(p, e);
}

function expr(p: Printer, e: ShaderExpr): string {
	const m = p.module;
	return match (e.kind) {
		ExprKind.Literal => literalText(p, e),
		ExprKind.Local => p.scope[p.current.params.length + e.index],
		ExprKind.Param => p.scope[e.index],
		ExprKind.Constant => p.constantNames[e.index],
		ExprKind.Workgroup => p.workgroupNames[e.index],
		ExprKind.Private => p.privateNames[e.index],
		ExprKind.Io => p.ioNames[e.index] != "" ? p.ioNames[e.index] :
			fail(p, "io '" + m.ios[e.index].name + "' belongs to the " +
				m.ios[e.index].stage.toString() + " stage"),
		ExprKind.Resource => m.resources[e.index].kind == ResourceKind.UniformBlock ?
			fail(p, "uniform block '" + m.resources[e.index].name + "' read whole") :
			p.resourceNames[e.index],
		ExprKind.BlockMember => blockMemberText(p, e),
		ExprKind.Unary => unaryText(e) + operand(p, e.operands[0]),
		ExprKind.Binary => binaryText(p, e),
		ExprKind.Conditional => {
			bothSides(p, "?:", [e.operands[1], e.operands[2]]);
			if (e.type.kind == ShaderTypeKind.Struct || e.type.kind == ShaderTypeKind.Array) {
				return fail(p, "a conditional of a " + e.type.kind.toString());
			}
			return operand(p, e.operands[0]) + " ? " + operand(p, e.operands[1]) + " : " +
				operand(p, e.operands[2]);
		},
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
			if (base.type.kind == ShaderTypeKind.ModfResult ||
				base.type.kind == ShaderTypeKind.FrexpResult) {
				return postfixBase(p, base) + "." + splitMember(base.type, e.index);
			}
			if (base.type.kind != ShaderTypeKind.Struct) {
				return fail(p, "Field of a " + base.type.kind.toString());
			}
			return postfixBase(p, base) + "." + p.fieldNames[base.type.structIndex][e.index];
		},
		ExprKind.Swizzle => postfixBase(p, e.operands[0]) + "." +
			e.components.map((c) => SWIZZLE.substring(c, c + 1)).join(""),
		ExprKind.Index => postfixBase(p, e.operands[0]) + "[" + expr(p, e.operands[1]) + "]",
	};
}

function assignment(p: Printer, s: ShaderStmt): string {
	const target = expr(p, s.target);
	const value = s.expr;
	return match (s.assign) {
		AssignOp.Set => target + " = " + expr(p, value),
		AssignOp.Add => target + " += " + expr(p, value),
		AssignOp.Sub => target + " -= " + expr(p, value),
		AssignOp.Mul => isMatrix(s.target.type) || isMatrix(value.type) ?
			target + " = " + product(p, s.target, value) : target + " *= " + expr(p, value),
		AssignOp.Div => target + " /= " + expr(p, value),
		AssignOp.Mod => target + " = " + remainder(p, s.target, value),
		AssignOp.Increment => target + "++",
		AssignOp.Decrement => target + "--",
	};
}

function letText(p: Printer, s: ShaderStmt): string {
	const name = p.scope[p.current.params.length + s.local];
	const head = declaration(p, p.current.locals[s.local].type, name);
	return isNone(s.expr) ? head : head + " = " + initializer(p, s.expr);
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

function isAtomicCall(e: ShaderExpr): boolean {
	return e.kind == ExprKind.Intrinsic && isAtomic(e.intrinsic);
}

function stmt(p: Printer, s: ShaderStmt, depth: int32): string {
	const at = indent(depth);
	if (s.kind == StmtKind.Call && isAtomicCall(s.expr)) {
		return atomicStatement(p, s.expr, "", at);
	}
	if (s.kind == StmtKind.Let && isUniformLoad(s.expr)) {
		const barrier = at + "GroupMemoryBarrierWithGroupSync();\n";
		return barrier + at + simple(p, s) + ";\n" + barrier;
	}
	if (s.kind == StmtKind.Let && isAtomicCall(s.expr)) {
		const name = p.scope[p.current.params.length + s.local];
		const head = s.expr.intrinsic == Intrinsic.AtomicCompareExchangeWeak ? "" :
			at + declaration(p, p.current.locals[s.local].type, name) + ";\n";
		return head + atomicStatement(p, s.expr, name, at);
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
			fail(p, "a break inside a switch case, which HLSL reads as leaving the switch") :
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
	const named = p.scope.slice(start);
	for (const n of named) { p.localsEver.push(n); }
	p.scope = named;
	if (f.result.kind == ShaderTypeKind.Array) {
		return fail(p, "function '" + f.name + "' returns an array");
	}
	const params = f.params.map((param, i) => declaration(p, param.type, named[i]));
	return typeName(p, f.result) + " " + p.functionNames[index] + "(" + params.join(", ") +
		")\n" + block(p, f.body, 0);
}

function packedSize(t: ShaderType): int32 {
	return match (t.kind) {
		ShaderTypeKind.Scalar | ShaderTypeKind.Atomic => 4,
		ShaderTypeKind.Vector => 4 * t.rows,
		ShaderTypeKind.Matrix => 4 * t.rows * t.columns,
		ShaderTypeKind.Array => t.length * packedSize(t.element[0]),
		ShaderTypeKind.Void | ShaderTypeKind.RuntimeArray | ShaderTypeKind.Struct |
			ShaderTypeKind.Texture | ShaderTypeKind.Sampler | ShaderTypeKind.StorageTexture |
			ShaderTypeKind.ExchangeResult | ShaderTypeKind.ModfResult |
			ShaderTypeKind.FrexpResult => -1,
	};
}

function std430Stride(t: ShaderType): int32 {
	const rows = t.kind == ShaderTypeKind.Matrix || t.kind == ShaderTypeKind.Vector ? t.rows : 1;
	const columns = t.kind == ShaderTypeKind.Matrix ? t.columns : 1;
	const column = rows == 3 ? 16 : 4 * rows;
	return t.kind == ShaderTypeKind.Matrix ? column * columns : column;
}

function storageStructText(p: Printer, structIndex: int32, resource: int32): string {
	const s = p.module.structs[structIndex];
	const layout = storageElementLayout(p.module, resource);
	if (!layout.ok) { return fail(p, layout.error); }
	let names = p.fieldNames[structIndex].map((n) => n);
	let text = "struct " + p.structNames[structIndex] + "\n{\n";
	let end = 0;
	const pad = (to: int32) => {
		while (end < to) {
			text += "    uint " + claim(p, names, "_pad") + ";\n";
			end += 4;
		}
	};
	for (let i = 0; i < s.members.length; i++) {
		const t = s.members[i].type;
		const own = innermost(t);
		const owner = "storage element '" + s.name + "' member '" + s.members[i].name + "'";
		if (own.kind == ShaderTypeKind.Struct) { return fail(p, owner + " nests a struct"); }
		const loose = own.kind == ShaderTypeKind.Matrix && own.rows == 3 ||
			t.kind == ShaderTypeKind.Array && std430Stride(own) != packedSize(own);
		if (loose) {
			return fail(p, owner + " has a std430 stride a structured buffer does not pack");
		}
		const size = packedSize(t);
		if (size < 0) { return fail(p, owner + " is a " + own.kind.toString() + " with no size"); }
		pad(layout.value.offsets[i]);
		text += "    " + declaration(p, t, p.fieldNames[structIndex][i]) + ";\n";
		end += size;
	}
	pad(layout.value.size);
	return text + "};\n\n";
}

function structText(p: Printer, structIndex: int32): string {
	const s = p.module.structs[structIndex];
	for (let i = 0; i < p.module.resources.length; i++) {
		const r = p.module.resources[i];
		if (r.kind == ResourceKind.StorageBuffer && p.resourceNames[i] != "" &&
			r.type.element[0].structIndex == structIndex) {
			return storageStructText(p, structIndex, i as int32);
		}
	}
	return "struct " + p.structNames[structIndex] + "\n{\n" + s.members.map((f, i) =>
		"    " + declaration(p, f.type, p.fieldNames[structIndex][i]) + ";\n").join("") +
		"};\n\n";
}

function registerOf(p: Printer, index: int32, slots: BindingSlot[]): string {
	const r = p.module.resources[index];
	const found = slots.filter((s) => s.resource == index && s.texture < 0);
	if (found.length == 0 || found[0].nativeSlot < 0) {
		return fail(p, "resource '" + r.name + "' has no HLSL slot");
	}
	const writable = r.kind == ResourceKind.StorageTexture ||
		r.kind == ResourceKind.StorageBuffer && r.access != Access.Read;
	const space = match (r.kind) {
		ResourceKind.UniformBlock => "b",
		ResourceKind.Sampler => "s",
		ResourceKind.Texture => "t",
		ResourceKind.StorageBuffer | ResourceKind.StorageTexture => writable ? "u" : "t",
	};
	return "register(" + space + String(found[0].nativeSlot) + ")";
}

function blockText(p: Printer, index: int32, slots: BindingSlot[]): string {
	const r = p.module.resources[index];
	const layout = uniformBlockLayout(p.module, index);
	if (!layout.ok) { return fail(p, layout.error); }
	const members = p.module.structs[r.type.structIndex].members;
	let text = "cbuffer " + p.resourceNames[index] + " : " + registerOf(p, index, slots) + "\n{\n";
	for (let i = 0; i < members.length; i++) {
		const offset = layout.value.offsets[i];
		const lane = (offset % 16) / 4;
		const columns = p.memberColumns[index][i];
		if (columns.length > 0) {
			for (let c = 0; c < columns.length; c++) {
				const at = offset + 8 * c;
				const half = (at % 16) / 4;
				text += "    float2 " + columns[c] + " : packoffset(c" + String(at / 16) +
					(at % 16 == 0 ? "" : "." + SWIZZLE.substring(half, half + 1)) + ");\n";
			}
			continue;
		}
		const component = offset % 16 == 0 ? "" : "." + SWIZZLE.substring(lane, lane + 1);
		text += "    " + declaration(p, members[i].type, p.memberNames[index][i]) +
			" : packoffset(c" + String(offset / 16) + component + ");\n";
	}
	return text + "};\n\n";
}

function bufferTypeName(p: Printer, r: ShaderResource): string {
	return (r.access == Access.Read ? "StructuredBuffer<" : "RWStructuredBuffer<") +
		p.structNames[r.type.element[0].structIndex] + ">";
}

function resourceText(p: Printer, index: int32, slots: BindingSlot[]): string {
	const r = p.module.resources[index];
	const name = p.resourceNames[index];
	const at = registerOf(p, index, slots);
	return match (r.kind) {
		ResourceKind.UniformBlock => blockText(p, index, slots),
		ResourceKind.Texture => textureTypeName(r.type) + " " + name + " : " + at + ";\n",
		ResourceKind.Sampler => (r.samplerType == SamplerType.Comparison ?
			"SamplerComparisonState " : "SamplerState ") + name + " : " + at + ";\n",
		ResourceKind.StorageBuffer => bufferTypeName(p, r) + " " + name + " : " + at + ";\n",
		ResourceKind.StorageTexture => typeName(p, r.type) + " " + name + " : " + at + ";\n",
	};
}

struct Port {
	io: int32;
	type: string;
	semantic: string;
	order: int32;
}

function semanticOf(p: Printer, io: ShaderIo): [string, string] {
	const wrong = (what: string): [string, string] =>
		[fail(p, io.builtin.toString() + " " + what), ""];
	return match (io.builtin) {
		Builtin.VertexIndex => ["uint", "SV_VertexID"],
		Builtin.InstanceIndex => ["uint", "SV_InstanceID"],
		Builtin.Position => ["float4", "SV_Position"],
		Builtin.FrontFacing => ["bool", "SV_IsFrontFace"],
		Builtin.FragDepth => ["float", "SV_Depth"],
		Builtin.LocalInvocationId => ["uint3", "SV_GroupThreadID"],
		Builtin.LocalInvocationIndex => ["uint", "SV_GroupIndex"],
		Builtin.GlobalInvocationId => ["uint3", "SV_DispatchThreadID"],
		Builtin.WorkgroupId => ["uint3", "SV_GroupID"],
		Builtin.NumWorkgroups => wrong("has no HLSL system value"),
		Builtin.SampleIndex => ["uint", "SV_SampleIndex"],
		Builtin.SampleMask => ["uint", "SV_Coverage"],
		Builtin.PrimitiveIndex => ["uint", "SV_PrimitiveID"],
		Builtin.None => wrong("is no builtin"),
	};
}

function builtinRank(builtin: Builtin): int32 {
	return match (builtin) {
		Builtin.PrimitiveIndex => 0,
		Builtin.Position => 1,
		Builtin.InstanceIndex => 2,
		Builtin.VertexIndex => 3,
		Builtin.FragDepth => 4,
		Builtin.FrontFacing => 5,
		Builtin.SampleIndex => 6,
		Builtin.SampleMask => 7,
		Builtin.GlobalInvocationId => 8,
		Builtin.LocalInvocationId => 9,
		Builtin.LocalInvocationIndex => 10,
		Builtin.WorkgroupId => 11,
		Builtin.NumWorkgroups => 12,
		Builtin.None => 13,
	};
}

function qualifiers(io: ShaderIo): string {
	const interpolation = match (io.interpolation) {
		Interpolation.Perspective => "",
		Interpolation.Linear => "noperspective ",
		Interpolation.Flat => "nointerpolation ",
	};
	const sampling = match (io.sampling) {
		Sampling.Center => "",
		Sampling.Centroid => "centroid ",
		Sampling.Sample => "sample ",
	};
	return interpolation + sampling;
}

function ports(p: Printer, direction: IoDirection): Port[] {
	const m = p.module;
	let out: Port[] = [];
	let ordinal = 0;
	for (let i = 0; i < m.ios.length; i++) {
		const io = m.ios[i];
		if (io.stage != p.stage || io.direction != direction) { continue; }
		let port: Port = { io: i as int32, type: "", semantic: "", order: 0 };
		if (io.builtin == Builtin.None) {
			const location = ioLocation(io, ordinal);
			ordinal++;
			if (p.stage == ShaderStage.Compute) {
				fail(p, "compute io '" + io.name + "' is no builtin");
			}
			const target = p.stage == ShaderStage.Fragment && direction == IoDirection.Out;
			port.semantic = (target ? "SV_Target" : "TEXCOORD") + String(location);
			port.order = location;
			const varying = !target && !(p.stage == ShaderStage.Vertex &&
				direction == IoDirection.In);
			port.type = (varying ? qualifiers(io) : "") + typeName(p, io.type);
		} else {
			const [type, semantic] = semanticOf(p, io);
			port.type = type;
			port.semantic = semantic;
			port.order = 1000 + builtinRank(io.builtin);
		}
		out.push(port);
	}
	out.sort((a, b) => a.order - b.order);
	return out;
}

function portStruct(p: Printer, name: string, list: Port[]): string {
	return "struct " + name + "\n{\n" + list.map((port) => "    " + port.type + " " +
		p.ioNames[port.io] + arraySuffix(p.module.ios[port.io].type) + " : " + port.semantic +
		";\n").join("") + "};\n\n";
}

function mainText(p: Printer, entryIndex: int32): string {
	const entry = p.module.entries[entryIndex];
	const inputs = ports(p, IoDirection.In);
	const outputs = ports(p, IoDirection.Out);
	let text = "";
	if (inputs.length > 0) { text += portStruct(p, "StageInput", inputs); }
	if (outputs.length > 0) { text += portStruct(p, "StageOutput", outputs); }
	if (entry.stage == ShaderStage.Compute) {
		text += "[numthreads(" + entry.workgroupSize.map((n) => String(n)).join(", ") + ")]\n";
	}
	text += (outputs.length > 0 ? "StageOutput" : "void") + " main(" +
		(inputs.length > 0 ? "StageInput stage_input" : "") + ")\n{\n";
	for (const port of inputs) {
		const io = p.module.ios[port.io];
		const name = p.ioNames[port.io];
		const declared = typeName(p, io.type);
		const read = port.type.endsWith(declared) ? "stage_input." + name :
			declared + "(stage_input." + name + ")";
		text += "    " + name + " = " + read + ";\n";
		if (io.builtin == Builtin.Position) {
			text += "    " + name + ".w = 1.0 / " + name + ".w;\n";
		}
	}
	text += "    " + p.functionNames[entry.functionIndex] + "();\n";
	if (outputs.length > 0) {
		text += "    StageOutput stage_output;\n";
		for (const port of outputs) {
			const name = p.ioNames[port.io];
			const declared = typeName(p, p.module.ios[port.io].type);
			const value = port.type.endsWith(declared) ? name : port.type + "(" + name + ")";
			text += "    stage_output." + name + " = " + value + ";\n";
		}
		text += "    return stage_output;\n";
	}
	return text + "}\n";
}

// Matrices print transposed: an HLSL row holds an IR column, so `row_major` storage reads the
// host's column-major data and M * v is mul(v, M).
export function printHlsl(
	source: ShaderModule,
	entryIndex: int32,
	slots: BindingSlot[],
): Result<string, string> {
	const demoted = demotedDiscards(source, entryIndex);
	if (!demoted.ok) { return Result.err("printHlsl: " + demoted.error); }
	const m = demoted.value;
	const printable = printableEntry(m, entryIndex);
	if (!printable.ok) { return Result.err("printHlsl: " + printable.error); }
	const reads = printable.value;
	const entry = m.entries[entryIndex];

	let p = new Printer();
	p.reserved = hlslKeywords().concat(hlslIntrinsics());
	p.module = m;
	p.stage = entry.stage;
	for (const fixed of ["main", "stage_input", "stage_output", "StageInput", "StageOutput"]) {
		claim(p, p.globals, fixed);
	}
	p.structNames = m.structs.map((_s) => "");
	p.fieldNames = m.structs.map((_s) => []);
	p.constantNames = m.constants.map((_c) => "");
	p.resourceNames = m.resources.map((_r) => "");
	p.memberNames = m.resources.map((_r) => []);
	p.memberColumns = m.resources.map((_r) => []);
	p.ioNames = m.ios.map((_io) => "");
	p.functionNames = m.functions.map((_f) => "");
	p.workgroupNames = m.workgroups.map((_w) => "");
	p.privateNames = m.privates.map((_v) => "");
	p.effects = m.functions.map((_f) => 0);

	let functions: int32[] = [];
	functionOrder(m, entry.functionIndex, [], functions);
	const structs = entryStructs(m, functions, reads.resources, reads.constants, entry.stage,
		false);
	const constants = constantsInOrder(m, reads.constants);
	const resources = ofKinds(m, reads.resources, [ResourceKind.UniformBlock,
		ResourceKind.Texture, ResourceKind.Sampler, ResourceKind.StorageBuffer,
		ResourceKind.StorageTexture]);

	for (const r of resources) {
		if (m.resources[r].kind != ResourceKind.UniformBlock) { continue; }
		const members = m.structs[m.resources[r].type.structIndex].members;
		p.memberNames[r] = members.map((f) => claim(p, p.globals, "_" + String(r) + "_" + f.name));
		p.memberColumns[r] = members.map((f, i) => {
			let columns: string[] = [];
			if (!isTwoRowMatrix(f.type)) { return columns; }
			for (let c = 0; c < f.type.columns; c++) {
				columns.push(claim(p, p.globals, p.memberNames[r][i] + "_" + String(c)));
			}
			return columns;
		});
	}
	for (const s of structs) {
		p.structNames[s] = claim(p, p.globals, m.structs[s].name);
		let fields: string[] = [];
		for (const f of m.structs[s].members) { claim(p, fields, f.name); }
		p.fieldNames[s] = fields;
	}
	for (const r of resources) { p.resourceNames[r] = claim(p, p.globals, m.resources[r].name); }
	for (const c of constants) { p.constantNames[c] = claim(p, p.globals, m.constants[c].name); }
	for (let i = 0; i < m.ios.length; i++) {
		if (m.ios[i].stage == entry.stage) { p.ioNames[i] = claim(p, p.globals, m.ios[i].name); }
	}
	for (const f of functions) { p.functionNames[f] = claim(p, p.globals, m.functions[f].name); }
	for (const w of reads.workgroups) {
		p.workgroupNames[w] = claim(p, p.globals, m.workgroups[w].name);
	}
	for (const v of reads.privates) {
		p.privateNames[v] = claim(p, p.globals, m.privates[v].name);
	}

	let head = "";
	for (const s of structs) {
		if (p.structNames[s] != "") { head += structText(p, s); }
	}
	for (const c of constants) {
		const constant = m.constants[c];
		head += "static const " + declaration(p, constant.type, p.constantNames[c]) + " = " +
			initializer(p, constant.value) + ";\n";
	}
	if (constants.length > 0) { head += "\n"; }
	let declared = "";
	for (const r of resources) { declared += resourceText(p, r, slots); }
	if (declared != "") { head += declared.endsWith("\n\n") ? declared : declared + "\n"; }
	for (let i = 0; i < m.ios.length; i++) {
		if (p.ioNames[i] != "") {
			head += "static " + declaration(p, m.ios[i].type, p.ioNames[i]) + ";\n";
		}
	}
	for (const w of reads.workgroups) {
		head += "groupshared " + declaration(p, m.workgroups[w].type, p.workgroupNames[w]) + ";\n";
	}
	for (const v of reads.privates) {
		const t = m.privates[v].type;
		head += "static " + declaration(p, t, p.privateNames[v]) + " = " + expr(p, zeroOf(t)) +
			";\n";
	}
	head += "\n";
	const bodies = functions.map((f) => functionText(p, f)).join("\n");
	const tail = mainText(p, entryIndex);
	if (p.error != "") { return Result.err(p.error); }
	const helpers = p.helpers.length > 0 ? p.helpers.join("\n") + "\n" : "";
	return Result.ok(head + helpers + bodies + "\n" + tail);
}
