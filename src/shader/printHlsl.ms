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
	isAtomic,
	isEffect,
} from "./ir";
import { BindingSlot, storageElementLayout, uniformBlockLayout } from "./layout";
import { readsFrom, strayWorkgroup } from "./specialize";

const KEYWORDS = [
	"AppendStructuredBuffer", "asm", "asm_fragment", "BlendState", "bool", "break", "Buffer",
	"ByteAddressBuffer", "case", "cbuffer", "centroid", "class", "column_major", "compile",
	"compile_fragment", "CompileShader", "const", "continue", "ComputeShader",
	"ConsumeStructuredBuffer", "default", "DepthStencilState", "DepthStencilView", "discard", "do",
	"double", "DomainShader", "dword", "else", "export", "extern", "false", "float", "for",
	"fxgroup", "GeometryShader", "groupshared", "half", "Hullshader", "HullShader", "if", "in",
	"inline", "inout", "InputPatch", "int", "interface", "line", "lineadj", "linear", "LineStream",
	"matrix", "min16float", "min10float", "min16int", "min12int", "min16uint", "namespace",
	"nointerpolation", "noperspective", "NULL", "out", "OutputPatch", "packoffset", "pass",
	"pixelfragment", "PixelShader", "point", "PointStream", "precise", "RasterizerState",
	"RenderTargetView", "return", "register", "row_major", "RWBuffer", "RWByteAddressBuffer",
	"RWStructuredBuffer", "RWTexture1D", "RWTexture1DArray", "RWTexture2D", "RWTexture2DArray",
	"RWTexture3D", "sample", "sampler", "SamplerState", "SamplerComparisonState", "shared",
	"snorm", "stateblock", "stateblock_state", "static", "string", "struct", "switch",
	"StructuredBuffer", "tbuffer", "technique", "technique10", "technique11", "texture",
	"Texture1D", "Texture1DArray", "Texture2D", "Texture2DArray", "Texture2DMS",
	"Texture2DMSArray", "Texture3D", "TextureCube", "TextureCubeArray", "true", "typedef",
	"triangle", "triangleadj", "TriangleStream", "uint", "uniform", "unorm", "unsigned", "vector",
	"vertexfragment", "VertexShader", "void", "volatile", "while", "sampler1D", "sampler2D",
	"sampler3D", "samplerCUBE", "sampler_state", "auto", "catch", "char", "const_cast",
	"delete", "dynamic_cast", "enum", "explicit", "friend", "goto", "long", "mutable", "new",
	"operator", "private", "protected", "public", "reinterpret_cast", "short", "signed", "sizeof",
	"static_cast", "template", "this", "throw", "try", "typename", "union", "using", "virtual",
];

const INTRINSICS = [
	"abort", "abs", "acos", "all", "AllMemoryBarrier", "AllMemoryBarrierWithGroupSync", "any",
	"asdouble", "asfloat", "asin", "asint", "asuint", "atan", "atan2", "ceil",
	"CheckAccessFullyMapped", "clamp", "clip", "cos", "cosh", "countbits", "cross",
	"D3DCOLORtoUBYTE4", "ddx", "ddx_coarse", "ddx_fine", "ddy", "ddy_coarse", "ddy_fine",
	"degrees", "determinant", "DeviceMemoryBarrier", "DeviceMemoryBarrierWithGroupSync",
	"distance", "dot", "dst", "errorf", "EvaluateAttributeAtCentroid", "EvaluateAttributeAtSample",
	"EvaluateAttributeSnapped", "exp", "exp2", "f16tof32", "f32tof16", "faceforward",
	"firstbithigh", "firstbitlow", "floor", "fma", "fmod", "frac", "frexp", "fwidth",
	"GetRenderTargetSampleCount", "GetRenderTargetSamplePosition", "GroupMemoryBarrier",
	"GroupMemoryBarrierWithGroupSync", "InterlockedAdd", "InterlockedAnd",
	"InterlockedCompareExchange", "InterlockedCompareStore", "InterlockedExchange",
	"InterlockedMax", "InterlockedMin", "InterlockedOr", "InterlockedXor", "isfinite", "isinf",
	"isnan", "ldexp", "length", "lerp", "lit", "log", "log10", "log2", "mad", "max", "min", "modf",
	"msad4", "mul", "noise", "normalize", "pow", "printf", "Process2DQuadTessFactorsAvg",
	"Process2DQuadTessFactorsMax", "Process2DQuadTessFactorsMin", "ProcessIsolineTessFactors",
	"ProcessQuadTessFactorsAvg", "ProcessQuadTessFactorsMax", "ProcessQuadTessFactorsMin",
	"ProcessTriTessFactorsAvg", "ProcessTriTessFactorsMax", "ProcessTriTessFactorsMin",
	"radians", "rcp", "reflect", "refract", "reversebits", "round", "rsqrt", "saturate", "sign",
	"sin", "sincos", "smoothstep", "sqrt", "step", "tan", "tanh", "tex1D", "tex1Dbias",
	"tex1Dgrad", "tex1Dlod", "tex1Dproj", "tex2D", "tex2Dbias", "tex2Dgrad", "tex2Dlod",
	"tex2Dproj", "tex3D", "tex3Dbias", "tex3Dgrad", "tex3Dlod", "tex3Dproj", "texCUBE",
	"texCUBEbias", "texCUBEgrad", "texCUBElod", "texCUBEproj", "transpose", "trunc",
];

const NUMERIC_TYPES = [
	"bool", "int", "uint", "dword", "half", "float", "double", "min16float", "min10float",
	"min16int", "min12int", "min16uint",
];

const SWIZZLE = ["x", "y", "z", "w"];

function isNumericTypeName(name: string): boolean {
	for (const base of NUMERIC_TYPES) {
		if (!name.startsWith(base)) { continue; }
		const rest = name.substring(base.length);
		const digit = (at: int32) => rest.length > at && "1234".includes(rest.substring(at, at + 1));
		if (rest.length == 1 && digit(0)) { return true; }
		if (rest.length == 3 && digit(0) && rest.substring(1, 2) == "x" && digit(2)) { return true; }
	}
	return false;
}

function isReserved(name: string): boolean {
	return KEYWORDS.includes(name) || INTRINSICS.includes(name) || isNumericTypeName(name);
}

function claim(taken: string[], name: string): string {
	let candidate = name;
	let n = 1;
	while (isReserved(candidate) || taken.includes(candidate)) {
		candidate = name + "_" + String(n);
		n++;
	}
	taken.push(candidate);
	return candidate;
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
	ioNames: string[] = [];
	functionNames: string[] = [];
	workgroupNames: string[] = [];
	effects: int32[] = [];
	scope: string[] = [];
	current: ShaderFunction = new ShaderFunction();
	nesting: Nesting[] = [];
	helperKeys: string[] = [];
	helperBases: string[] = [];
	helperNames: string[] = [];
	helpers: string[] = [];
}

function fail(p: Printer, message: string): string {
	if (p.error == "") { p.error = "printHlsl: " + message; }
	return "";
}

function scalarName(s: ScalarKind): string {
	return match (s) {
		ScalarKind.F32 => "float",
		ScalarKind.I32 => "int",
		ScalarKind.U32 => "uint",
		ScalarKind.Bool => "bool",
	};
}

function innermost(t: ShaderType): ShaderType {
	return t.kind == ShaderTypeKind.Array ? innermost(t.element[0]) : t;
}

function arraySuffix(t: ShaderType): string {
	return t.kind == ShaderTypeKind.Array ?
		"[" + String(t.length) + "]" + arraySuffix(t.element[0]) : "";
}

function textureTypeName(p: Printer, t: ShaderType): string {
	const texel = scalarName(t.scalar) + "4";
	return match (t.shape) {
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
		TexelFormat.Rgba8uint => "uint4",
		TexelFormat.Rgba16float | TexelFormat.Rgba32float => "float4",
		TexelFormat.R32float => "float",
		TexelFormat.R32uint => "uint",
		TexelFormat.Rg32float => "float2",
	};
}

function texelWidth(format: TexelFormat): int32 {
	return match (format) {
		TexelFormat.R32float | TexelFormat.R32uint => 1,
		TexelFormat.Rg32float => 2,
		_ => 4,
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
		ShaderTypeKind.Texture => textureTypeName(p, t),
		ShaderTypeKind.Sampler => "SamplerState",
		ShaderTypeKind.StorageTexture => match (t.shape) {
			TextureShape.D2 => "RWTexture2D<" + texelOf(t.format) + ">",
			TextureShape.D2Array => "RWTexture2DArray<" + texelOf(t.format) + ">",
			TextureShape.D3 => "RWTexture3D<" + texelOf(t.format) + ">",
			_ => fail(p, "a storage texture of shape " + t.shape.toString()),
		},
		ShaderTypeKind.Atomic => scalarName(t.scalar),
		ShaderTypeKind.ExchangeResult => exchangeResult(p, t.scalar),
	};
}

function exchangeResult(p: Printer, scalar: ScalarKind): string {
	const suffix = scalar == ScalarKind.I32 ? "I32" : "U32";
	return helper(p, "exchange " + suffix, "AtomicExchange" + suffix, (n) => "struct " + n +
		"\n{\n    " + scalarName(scalar) + " old_value;\n    bool exchanged;\n};\n");
}

function temporary(p: Printer, name: string): string {
	const named = claim(p.globals.concat(p.scope), name);
	p.scope.push(named);
	p.localsEver.push(named);
	return named;
}

function interlockedName(op: Intrinsic): string {
	return match (op) {
		Intrinsic.AtomicLoad | Intrinsic.AtomicAdd | Intrinsic.AtomicSub => "InterlockedAdd",
		Intrinsic.AtomicMax => "InterlockedMax",
		Intrinsic.AtomicMin => "InterlockedMin",
		Intrinsic.AtomicAnd => "InterlockedAnd",
		Intrinsic.AtomicOr => "InterlockedOr",
		Intrinsic.AtomicXor => "InterlockedXor",
		_ => "InterlockedExchange",
	};
}

// SPIRV-Cross's HLSL atomics: Interlocked* hands the old value back through an out parameter,
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
		_ => expr(p, o[1]),
	};
	const exchange = e.intrinsic == Intrinsic.AtomicStore || e.intrinsic == Intrinsic.AtomicExchange;
	let out = result;
	let head = "";
	if (out == "" && exchange) {
		out = temporary(p, "exchanged");
		head = at + scalar + " " + out + ";\n";
	}
	return head + at + interlockedName(e.intrinsic) + "(" + place + ", " + value +
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
		ShaderTypeKind.Vector => typeName(p, t) + "(" + repeated(one, t.rows) + ")",
		ShaderTypeKind.Matrix => "((" + typeName(p, t) + ")" + one + ")",
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
	if (e.kind == ExprKind.Intrinsic && isEffect(e.intrinsic)) { return true; }
	if (e.kind == ExprKind.Call) {
		if (p.effects[e.index] == 0) {
			p.effects[e.index] = 1;
			p.effects[e.index] = stmtsHaveEffect(p, p.module.functions[e.index].body) ? 2 : 1;
		}
		if (p.effects[e.index] == 2) { return true; }
	}
	return e.operands.some((o) => hasEffect(p, o));
}

function bothSides(p: Printer, what: string, sides: ShaderExpr[]): void {
	if (sides.some((s) => hasEffect(p, s))) {
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
	return e.unary == UnaryOp.Negate ? "-" : e.operands[0].type.scalar == ScalarKind.Bool ? "!" : "~";
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
		BinaryOp.BitOr => "|",
		BinaryOp.BitXor => "^",
		BinaryOp.ShiftLeft => "<<",
		BinaryOp.ShiftRight => ">>",
		BinaryOp.LogicalAnd => "&&",
		BinaryOp.LogicalOr => "||",
		BinaryOp.Equal => "==",
		BinaryOp.NotEqual => "!=",
		BinaryOp.Less => "<",
		BinaryOp.LessEqual => "<=",
		BinaryOp.Greater => ">",
		BinaryOp.GreaterEqual => ">=",
	};
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
	let taken = p.globals.map((n) => n);
	for (const n of p.localsEver) { taken.push(n); }
	const named = claim(taken, name);
	p.globals.push(named);
	return named;
}

function inverseOf(p: Printer, e: ShaderExpr): string {
	const t = e.operands[0].type;
	if (!isMatrix(t) || t.columns != t.rows) {
		return fail(p, "Inverse of a " + t.kind.toString() + " that is no square matrix");
	}
	const ty = typeName(p, t);
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
	const name = helper(p, "inverse " + ty, "inverse",
		(n) => ty + " " + n + "(" + ty + " m)\n{\n" + body + "}\n");
	return name + "(" + expr(p, e.operands[0]) + ")";
}

function withoutSampler(e: ShaderExpr): ShaderExpr[] {
	return e.operands.filter((o) => o.type.kind != ShaderTypeKind.Sampler);
}

function converted(p: Printer, text: string, from: string, to: ShaderType): string {
	const target = typeName(p, to);
	return from == target ? text : target + "(" + text + ")";
}

function sizeOf(p: Printer, e: ShaderExpr): string {
	const args = withoutSampler(e);
	const t = args[0].type;
	const texture = expr(p, args[0]);
	if (t.kind == ShaderTypeKind.StorageTexture) {
		const ty = typeName(p, t);
		const deep = t.shape == TextureShape.D3;
		const sizes = deep ? ["width", "height", "depth"] :
			t.shape == TextureShape.D2Array ? ["width", "height", "layers"] : ["width", "height"];
		const result = deep ? "uint3" : "uint2";
		const kept = deep ? "width, height, depth" : "width, height";
		const name = helper(p, "imageSize " + ty, "imageSize", (n) =>
			result + " " + n + "(" + ty + " image)\n{\n" +
			sizes.map((s) => "    uint " + s + ";\n").join("") +
			"    image.GetDimensions(" + sizes.join(", ") + ");\n" +
			"    return " + result + "(" + kept + ");\n}\n");
		return converted(p, name + "(" + texture + ")", result, e.type);
	}
	if (t.kind != ShaderTypeKind.Texture) {
		return fail(p, "TextureDimensions of a " + t.kind.toString());
	}
	const level = args.length > 1 ? "uint(" + expr(p, args[1]) + ")" : "0u";
	const ty = typeName(p, t);
	const deep = t.shape == TextureShape.D3;
	const layered = t.shape == TextureShape.D2Array || t.shape == TextureShape.Depth2dArray ||
		t.shape == TextureShape.CubeArray;
	const result = deep ? "uint3" : "uint2";
	const outs = deep ? ["width", "height", "depth", "levels"] :
		layered ? ["width", "height", "layers", "levels"] : ["width", "height", "levels"];
	if (t.shape == TextureShape.Multisampled2d) {
		const name = helper(p, "textureSize " + ty, "textureSize", (n) =>
			"uint2 " + n + "(" + ty + " t)\n{\n    uint width;\n    uint height;\n" +
			"    uint samples;\n    t.GetDimensions(width, height, samples);\n" +
			"    return uint2(width, height);\n}\n");
		return converted(p, name + "(" + texture + ")", "uint2", e.type);
	}
	const kept = result == "uint3" ? "width, height, depth" : "width, height";
	const name = helper(p, "textureSize " + ty, "textureSize", (n) =>
		result + " " + n + "(" + ty + " t, uint level)\n{\n" +
		outs.map((o) => "    uint " + o + ";\n").join("") +
		"    t.GetDimensions(level, " + outs.join(", ") + ");\n" +
		"    return " + result + "(" + kept + ");\n}\n");
	return converted(p, name + "(" + texture + ", " + level + ")", result, e.type);
}

function loadOf(p: Printer, e: ShaderExpr): string {
	const args = withoutSampler(e);
	const t = args[0].type;
	const texture = operand(p, args[0]);
	if (args.length < 2) { return fail(p, "TextureLoad without coordinates"); }
	const at = expr(p, args[1]);
	const level = args.length > 2 ? expr(p, args[2]) : "0";
	if (t.kind == ShaderTypeKind.StorageTexture) {
		if (texelWidth(t.format) != 1) {
			return fail(p, "TextureLoad of a " + t.format.toString() + " storage texture: SM5 " +
				"loads typed UAVs of one 32-bit channel only");
		}
		const texel = texture + "[" + storageAt(p, args) + "]";
		if (e.type.kind != ShaderTypeKind.Vector) { return texel; }
		const unsigned = t.format == TexelFormat.R32uint;
		return (unsigned ? "uint4(" : "float4(") + texel +
			(unsigned ? ", 0u, 0u, 1u)" : ", 0.0, 0.0, 1.0)");
	}
	if (t.kind != ShaderTypeKind.Texture) { return fail(p, "TextureLoad of a " + t.kind.toString()); }
	return match (t.shape) {
		TextureShape.D2 | TextureShape.Depth2d =>
			texture + ".Load(int3(" + at + ", " + level + "))",
		TextureShape.D3 => texture + ".Load(int4(" + at + ", " + level + "))",
		TextureShape.Multisampled2d => texture + ".Load(int2(" + at + "), " + level + ")",
		_ => fail(p, "TextureLoad of a " + t.shape.toString() + " texture: the IR names no layer"),
	};
}

function isLayered(t: ShaderType): boolean {
	return t.shape == TextureShape.D2Array || t.shape == TextureShape.Depth2dArray;
}

function layeredAt(p: Printer, e: ShaderExpr, layered: boolean): string {
	return layered ? "float3(" + expr(p, e.operands[2]) + ", float(" + expr(p, e.operands[3]) +
		"))" : expr(p, e.operands[2]);
}

function sampleOf(p: Printer, e: ShaderExpr): string {
	const layered = e.operands.length > 0 && isLayered(e.operands[0].type);
	if (e.operands.length != (layered ? 4 : 3)) {
		return fail(p, "TextureSample takes a texture, a sampler, coordinates and, for an array " +
			"texture, a layer");
	}
	const [texture, sampler] = [e.operands[0], e.operands[1]];
	if (texture.type.kind != ShaderTypeKind.Texture || sampler.type.kind != ShaderTypeKind.Sampler) {
		return fail(p, "TextureSample takes a texture and a sampler first");
	}
	if (texture.type.shape == TextureShape.Multisampled2d) {
		return fail(p, "TextureSample of a multisampled texture");
	}
	if (sampler.kind == ExprKind.Resource &&
		p.module.resources[sampler.index].samplerType == SamplerType.Comparison) {
		return fail(p, "TextureSample through a comparison sampler, which needs a depth reference");
	}
	return operand(p, texture) + ".Sample(" + expr(p, sampler) + ", " + layeredAt(p, e, layered) +
		")";
}

function compareOf(p: Printer, e: ShaderExpr, level: boolean): string {
	const name = e.intrinsic.toString();
	const layered = e.operands.length > 0 && isLayered(e.operands[0].type);
	if (e.operands.length != (layered ? 5 : 4)) {
		return fail(p, name + " takes a texture, a sampler, coordinates, for an array texture a " +
			"layer, and a depth reference");
	}
	const [texture, sampler] = [e.operands[0], e.operands[1]];
	const reference = e.operands[e.operands.length - 1];
	if (texture.type.kind != ShaderTypeKind.Texture || sampler.type.kind != ShaderTypeKind.Sampler) {
		return fail(p, name + " takes a texture and a sampler first");
	}
	if (!level && p.stage != ShaderStage.Fragment) {
		return fail(p, name + " outside a fragment stage");
	}
	if (sampler.kind != ExprKind.Resource ||
		p.module.resources[sampler.index].samplerType != SamplerType.Comparison) {
		return fail(p, name + " through a sampler that is no comparison sampler binding");
	}
	const depth = match (texture.type.shape) {
		TextureShape.Depth2d | TextureShape.Depth2dArray | TextureShape.DepthCube => true,
		_ => false,
	};
	if (!depth) {
		return fail(p, name + " of a " + texture.type.shape.toString() + " texture, which holds " +
			"no depth");
	}
	return operand(p, texture) + (level ? ".SampleCmpLevelZero(" : ".SampleCmp(") +
		expr(p, sampler) + ", " + layeredAt(p, e, layered) + ", " + expr(p, reference) + ")";
}

function storageAt(p: Printer, args: ShaderExpr[]): string {
	return match (args[0].type.shape) {
		TextureShape.D2 => "uint2(" + expr(p, args[1]) + ")",
		TextureShape.D2Array => "uint3(" + expr(p, args[1]) + ", " + expr(p, args[2]) + ")",
		_ => "uint3(" + expr(p, args[1]) + ")",
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
		operand(p, value) + "." + SWIZZLE.slice(0, width).join("") : expr(p, value);
	return operand(p, o[0]) + "[" + storageAt(p, o) + "] = " + written;
}

function intrinsicName(op: Intrinsic): string {
	return match (op) {
		Intrinsic.Abs => "abs",
		Intrinsic.Floor => "floor",
		Intrinsic.Ceil => "ceil",
		Intrinsic.Trunc => "trunc",
		Intrinsic.Round => "round",
		Intrinsic.Fract => "frac",
		Intrinsic.Sqrt => "sqrt",
		Intrinsic.InverseSqrt => "rsqrt",
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
		Intrinsic.Atan => "atan",
		Intrinsic.Atan2 => "atan2",
		Intrinsic.Sinh => "sinh",
		Intrinsic.Cosh => "cosh",
		Intrinsic.Tanh => "tanh",
		Intrinsic.Degrees => "degrees",
		Intrinsic.Radians => "radians",
		Intrinsic.Min => "min",
		Intrinsic.Max => "max",
		Intrinsic.Clamp => "clamp",
		Intrinsic.Saturate => "saturate",
		Intrinsic.Mix => "lerp",
		Intrinsic.Step => "step",
		Intrinsic.Smoothstep => "smoothstep",
		Intrinsic.Fma => "mad",
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
		Intrinsic.Dpdx => "ddx",
		Intrinsic.Dpdy => "ddy",
		Intrinsic.Fwidth => "fwidth",
		_ => "",
	};
}

function computeOnly(p: Printer, e: ShaderExpr, text: string): string {
	if (p.stage != ShaderStage.Compute) {
		return fail(p, e.intrinsic.toString() + " outside a compute entry");
	}
	return text;
}

function intrinsicText(p: Printer, e: ShaderExpr): string {
	const args = () => e.operands.map((o) => expr(p, o)).join(", ");
	return match (e.intrinsic) {
		Intrinsic.Sign => converted(p, "sign(" + args() + ")", "int", e.type),
		Intrinsic.Inverse => inverseOf(p, e),
		Intrinsic.UpperLeft3x3 => "((float3x3)" + operand(p, e.operands[0]) + ")",
		Intrinsic.Select => {
			bothSides(p, "select", [e.operands[0], e.operands[1]]);
			return "(" + operand(p, e.operands[2]) + " ? " + operand(p, e.operands[1]) + " : " +
				operand(p, e.operands[0]) + ")";
		},
		Intrinsic.LessThanEqual => operand(p, e.operands[0]) + " <= " + operand(p, e.operands[1]),
		Intrinsic.TextureSample => sampleOf(p, e),
		Intrinsic.TextureLoad => loadOf(p, e),
		Intrinsic.TextureStore => storeOf(p, e),
		Intrinsic.TextureDimensions => sizeOf(p, e),
		Intrinsic.TextureSampleCompare => compareOf(p, e, false),
		Intrinsic.TextureSampleCompareLevel => compareOf(p, e, true),
		Intrinsic.WorkgroupBarrier => computeOnly(p, e, "GroupMemoryBarrierWithGroupSync()"),
		Intrinsic.StorageBarrier => computeOnly(p, e, "DeviceMemoryBarrierWithGroupSync()"),
		_ => isAtomic(e.intrinsic) ? fail(p, e.intrinsic.toString() + " inside an expression or " +
			"a for header: Interlocked* hands its result back through an out parameter, so an " +
			"atomic is a statement or a local's initializer") :
			intrinsicName(e.intrinsic) + "(" + args() + ")",
	};
}

function structMaker(p: Printer, structIndex: int32): string {
	const s = p.module.structs[structIndex];
	const ty = p.structNames[structIndex];
	return helper(p, "make " + ty, "make" + ty, (n) => {
		const params = s.members.map((f, i) => declaration(p, f.type, "v" + String(i)));
		const sets = s.members.map((f, i) => "    r." + p.fieldNames[structIndex][i] + " = v" +
			String(i) + ";\n");
		return ty + " " + n + "(" + params.join(", ") + ")\n{\n    " + ty + " r = (" + ty +
			")0;\n" + sets.join("") + "    return r;\n}\n";
	});
}

function constructText(p: Printer, e: ShaderExpr): string {
	const t = e.type;
	const args = e.operands.map((o) => expr(p, o)).join(", ");
	if (t.kind == ShaderTypeKind.Struct) { return structMaker(p, t.structIndex) + "(" + args + ")"; }
	if (t.kind == ShaderTypeKind.Array) {
		return fail(p, "an array value outside a local's or constant's initializer");
	}
	if (t.kind != ShaderTypeKind.Vector && t.kind != ShaderTypeKind.Matrix) {
		return fail(p, "Construct of a " + t.kind.toString());
	}
	if (e.operands.length == 1 && e.operands[0].type.kind == ShaderTypeKind.Scalar) {
		if (isMatrix(t)) { return fail(p, "a matrix built from one scalar"); }
		return "((" + typeName(p, t) + ")" + operand(p, e.operands[0]) + ")";
	}
	if (e.operands.length == 1 && isMatrix(e.operands[0].type)) {
		return "((" + typeName(p, t) + ")" + operand(p, e.operands[0]) + ")";
	}
	return typeName(p, t) + "(" + args + ")";
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
		ExprKind.Local => e.index >= 0 && e.index < p.current.locals.length ?
			p.scope[p.current.params.length + e.index] : fail(p, "a local out of range"),
		ExprKind.Param => p.scope[e.index],
		ExprKind.Constant => p.constantNames[e.index],
		ExprKind.Workgroup => p.workgroupNames[e.index],
		ExprKind.Io => p.ioNames[e.index] != "" ? p.ioNames[e.index] :
			fail(p, "io '" + m.ios[e.index].name + "' belongs to the " +
				m.ios[e.index].stage.toString() + " stage"),
		ExprKind.Resource => m.resources[e.index].kind == ResourceKind.UniformBlock ?
			fail(p, "uniform block '" + m.resources[e.index].name + "' read whole") :
			p.resourceNames[e.index],
		ExprKind.BlockMember => p.memberNames[e.index][e.member],
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
			if (base.type.kind != ShaderTypeKind.Struct) {
				return fail(p, "Field of a " + base.type.kind.toString());
			}
			return postfixBase(p, base) + "." + p.fieldNames[base.type.structIndex][e.index];
		},
		ExprKind.Swizzle => postfixBase(p, e.operands[0]) + "." +
			e.components.map((c) => SWIZZLE[c]).join(""),
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
	if (s.local < 0 || s.local >= p.current.locals.length) { return fail(p, "a Let out of range"); }
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

function isAtomicCall(e: ShaderExpr): boolean {
	return e.kind == ExprKind.Intrinsic && isAtomic(e.intrinsic);
}

function stmt(p: Printer, s: ShaderStmt, depth: int32): string {
	const at = indent(depth);
	if (s.kind == StmtKind.Call && isAtomicCall(s.expr)) {
		return atomicStatement(p, s.expr, "", at);
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
		StmtKind.Break => p.nesting.length > 0 && p.nesting[p.nesting.length - 1] == Nesting.Switch ?
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
	for (const param of f.params) { claim(p.scope, param.name); }
	for (const local of f.locals) { claim(p.scope, local.name); }
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
	structOrder(p, e.type, out);
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

function packedSize(t: ShaderType): int32 {
	return match (t.kind) {
		ShaderTypeKind.Scalar | ShaderTypeKind.Atomic => 4,
		ShaderTypeKind.Vector => 4 * t.rows,
		ShaderTypeKind.Matrix => 4 * t.rows * t.columns,
		ShaderTypeKind.Array => t.length * packedSize(t.element[0]),
		_ => -1,
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
			text += "    uint " + claim(names, "_pad") + ";\n";
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
		pad(layout.value.offsets[i]);
		text += "    " + declaration(p, t, p.fieldNames[structIndex][i]) + ";\n";
		end += packedSize(t);
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
		_ => writable ? "u" : "t",
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
		const component = offset % 16 == 0 ? "" : "." + SWIZZLE[(offset % 16) / 4];
		text += "    " + declaration(p, members[i].type, p.memberNames[index][i]) +
			" : packoffset(c" + String(offset / 16) + component + ");\n";
	}
	return text + "};\n\n";
}

function resourceText(p: Printer, index: int32, slots: BindingSlot[]): string {
	const r = p.module.resources[index];
	const name = p.resourceNames[index];
	const at = registerOf(p, index, slots);
	return match (r.kind) {
		ResourceKind.UniformBlock => blockText(p, index, slots),
		ResourceKind.Texture => textureTypeName(p, r.type) + " " + name + " : " + at + ";\n",
		ResourceKind.Sampler => (r.samplerType == SamplerType.Comparison ?
			"SamplerComparisonState " : "SamplerState ") + name + " : " + at + ";\n",
		ResourceKind.StorageBuffer => (r.access == Access.Read ? "StructuredBuffer<" :
			"RWStructuredBuffer<") + p.structNames[r.type.element[0].structIndex] + "> " + name +
			" : " + at + ";\n",
		ResourceKind.StorageTexture => typeName(p, r.type) + " " + name + " : " + at + ";\n",
	};
}

class Port {
	io: int32 = -1;
	type: string = "";
	semantic: string = "";
	order: int32 = 0;
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
		Builtin.None => wrong("is no builtin"),
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
		let port = new Port();
		port.io = i as int32;
		if (io.builtin == Builtin.None) {
			const location = io.location >= 0 ? io.location : ordinal;
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
			port.order = 1000 + i;
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

// Matrices print transposed: an HLSL row holds an IR column, so `row_major` storage reads the
// host's column-major data and M * v is mul(v, M).
export function printHlsl(m: ShaderModule, entryIndex: int32, slots: BindingSlot[]):
	Result<string, string> {
	const invalid = irErrors(m);
	if (invalid.length > 0) { return Result.err("printHlsl: " + invalid[0]); }
	if (entryIndex < 0 || entryIndex >= m.entries.length) {
		return Result.err("printHlsl: entry " + String(entryIndex) + " is out of range");
	}
	const entry = m.entries[entryIndex];
	const readsResult = readsFrom(m, entry.functionIndex);
	if (!readsResult.ok) { return Result.err("printHlsl: " + readsResult.error); }
	const reads = readsResult.value;
	const stray = strayWorkgroup(m, entry, reads);
	if (stray != "") { return Result.err("printHlsl: " + stray); }
	const conditioned = unspecialized(m, entry.stage, reads.resources, reads.functions);
	if (conditioned != "") {
		return Result.err("printHlsl: " + conditioned + " is under a feature condition: " +
			"specialize the module first");
	}

	let p = new Printer();
	p.module = m;
	p.stage = entry.stage;
	for (const fixed of ["main", "stage_input", "stage_output", "StageInput", "StageOutput"]) {
		claim(p.globals, fixed);
	}
	p.structNames = m.structs.map((_s) => "");
	p.fieldNames = m.structs.map((_s) => []);
	p.constantNames = m.constants.map((_c) => "");
	p.resourceNames = m.resources.map((_r) => "");
	p.memberNames = m.resources.map((_r) => []);
	p.ioNames = m.ios.map((_io) => "");
	p.functionNames = m.functions.map((_f) => "");
	p.workgroupNames = m.workgroups.map((_w) => "");
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
	const kinds = [ResourceKind.UniformBlock, ResourceKind.Texture, ResourceKind.Sampler,
		ResourceKind.StorageBuffer, ResourceKind.StorageTexture];
	let resources: int32[] = [];
	for (const kind of kinds) {
		for (const r of reads.resources) {
			if (m.resources[r].kind == kind) { resources.push(r); }
		}
	}

	for (const r of resources) {
		if (m.resources[r].kind != ResourceKind.UniformBlock) { continue; }
		const members = m.structs[m.resources[r].type.structIndex].members;
		p.memberNames[r] = members.map((f) => claim(p.globals, "_" + String(r) + "_" + f.name));
	}
	for (const s of structs) {
		p.structNames[s] = claim(p.globals, m.structs[s].name);
		let fields: string[] = [];
		for (const f of m.structs[s].members) { claim(fields, f.name); }
		p.fieldNames[s] = fields;
	}
	for (const r of resources) { p.resourceNames[r] = claim(p.globals, m.resources[r].name); }
	for (const c of constants) { p.constantNames[c] = claim(p.globals, m.constants[c].name); }
	for (let i = 0; i < m.ios.length; i++) {
		if (m.ios[i].stage == entry.stage) { p.ioNames[i] = claim(p.globals, m.ios[i].name); }
	}
	for (const f of functions) { p.functionNames[f] = claim(p.globals, m.functions[f].name); }
	for (const w of reads.workgroups) {
		p.workgroupNames[w] = claim(p.globals, m.workgroups[w].name);
	}

	const entryFunction = m.functions[entry.functionIndex];
	if (entryFunction.params.length > 0 || entryFunction.result.kind != ShaderTypeKind.Void) {
		return Result.err("printHlsl: entry '" + entry.name + "' takes parameters or returns a " +
			"value; an entry reads and writes its stage's io");
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
	head += "\n";
	const bodies = functions.map((f) => functionText(p, f)).join("\n");
	const tail = mainText(p, entryIndex);
	if (p.error != "") { return Result.err(p.error); }
	const helpers = p.helpers.length > 0 ? p.helpers.join("\n") + "\n" : "";
	return Result.ok(head + helpers + bodies + "\n" + tail);
}
