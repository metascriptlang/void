import {
	Access,
	BinaryOp,
	Interpolation,
	Intrinsic,
	Sampling,
	ScalarKind,
	ShaderType,
	ShaderTypeKind,
	TexelFormat,
} from "./ir";

export function binaryOperator(op: BinaryOp): string {
	return match (op) {
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
}

export function scalarName(s: ScalarKind): string {
	return match (s) {
		ScalarKind.F32 => "float",
		ScalarKind.I32 => "int",
		ScalarKind.U32 => "uint",
		ScalarKind.Bool => "bool",
	};
}

export function vectorPrefix(s: ScalarKind): string {
	return match (s) {
		ScalarKind.F32 => "",
		ScalarKind.I32 => "i",
		ScalarKind.U32 => "u",
		ScalarKind.Bool => "b",
	};
}

export function isComponentCompare(op: Intrinsic): boolean {
	return op == Intrinsic.LessThan || op == Intrinsic.LessThanEqual || op == Intrinsic.GreaterThan ||
		op == Intrinsic.GreaterThanEqual || op == Intrinsic.Equal || op == Intrinsic.NotEqual;
}

// The operator that spells a componentwise test where the target compares vectors by operator.
export function componentCompare(op: Intrinsic): BinaryOp {
	if (op == Intrinsic.LessThan) { return BinaryOp.Less; }
	if (op == Intrinsic.LessThanEqual) { return BinaryOp.LessEqual; }
	if (op == Intrinsic.GreaterThan) { return BinaryOp.Greater; }
	if (op == Intrinsic.GreaterThanEqual) { return BinaryOp.GreaterEqual; }
	if (op == Intrinsic.Equal) { return BinaryOp.Equal; }
	if (op == Intrinsic.NotEqual) { return BinaryOp.NotEqual; }
	unspelled("componentwise test", op);
}

function unspelled(what: string, op: Intrinsic): never {
	throw new Error("internal: no " + what + " spelling for " + op.toString());
}

export function isMath(op: Intrinsic): boolean {
	return match (op) {
		Intrinsic.Inverse | Intrinsic.UpperLeft3x3 | Intrinsic.Select | Intrinsic.LessThan |
			Intrinsic.LessThanEqual | Intrinsic.GreaterThan | Intrinsic.GreaterThanEqual |
			Intrinsic.Equal | Intrinsic.NotEqual |
			Intrinsic.TextureSample | Intrinsic.TextureLoad | Intrinsic.TextureStore |
			Intrinsic.TextureDimensions | Intrinsic.TextureNumSamples | Intrinsic.ArrayLength |
			Intrinsic.WorkgroupUniformLoad | Intrinsic.TextureBarrier |
			Intrinsic.TextureSampleCompare | Intrinsic.TextureSampleCompareLevel |
			Intrinsic.TextureSampleLevel |
			Intrinsic.TextureSampleBias | Intrinsic.TextureSampleGrad | Intrinsic.WorkgroupBarrier |
			Intrinsic.StorageBarrier | Intrinsic.AtomicLoad | Intrinsic.AtomicStore |
			Intrinsic.AtomicAdd | Intrinsic.AtomicSub | Intrinsic.AtomicMax | Intrinsic.AtomicMin |
			Intrinsic.AtomicAnd | Intrinsic.AtomicOr | Intrinsic.AtomicXor |
			Intrinsic.AtomicExchange | Intrinsic.AtomicCompareExchangeWeak => false,
		Intrinsic.Abs | Intrinsic.Sign | Intrinsic.Floor | Intrinsic.Ceil | Intrinsic.Trunc |
			Intrinsic.Round | Intrinsic.Fract | Intrinsic.Sqrt | Intrinsic.InverseSqrt |
			Intrinsic.Exp | Intrinsic.Exp2 | Intrinsic.Log | Intrinsic.Log2 | Intrinsic.Pow |
			Intrinsic.Sin | Intrinsic.Cos | Intrinsic.Tan | Intrinsic.Asin | Intrinsic.Acos |
			Intrinsic.Atan | Intrinsic.Atan2 | Intrinsic.Sinh | Intrinsic.Cosh | Intrinsic.Tanh |
			Intrinsic.Asinh | Intrinsic.Acosh | Intrinsic.Atanh | Intrinsic.Ldexp | Intrinsic.Modf |
			Intrinsic.Frexp | Intrinsic.Degrees | Intrinsic.Radians | Intrinsic.Min | Intrinsic.Max |
			Intrinsic.Clamp | Intrinsic.Saturate | Intrinsic.Mix | Intrinsic.Step |
			Intrinsic.Smoothstep | Intrinsic.Fma | Intrinsic.Dot | Intrinsic.Cross |
			Intrinsic.Length | Intrinsic.Distance | Intrinsic.Normalize | Intrinsic.Reflect |
			Intrinsic.Refract | Intrinsic.FaceForward | Intrinsic.Transpose |
			Intrinsic.Determinant | Intrinsic.Any | Intrinsic.All | Intrinsic.Dpdx | Intrinsic.Dpdy |
			Intrinsic.Fwidth | Intrinsic.DpdxCoarse | Intrinsic.DpdxFine | Intrinsic.DpdyCoarse |
			Intrinsic.DpdyFine | Intrinsic.FwidthCoarse | Intrinsic.FwidthFine | Intrinsic.Bitcast |
			Intrinsic.CountOneBits | Intrinsic.ReverseBits | Intrinsic.FirstLeadingBit |
			Intrinsic.FirstTrailingBit | Intrinsic.CountLeadingZeros | Intrinsic.CountTrailingZeros |
			Intrinsic.ExtractBits | Intrinsic.InsertBits |
			Intrinsic.Pack4x8Unorm | Intrinsic.Pack4x8Snorm | Intrinsic.Pack2x16Unorm |
			Intrinsic.Pack2x16Snorm | Intrinsic.Pack2x16Float | Intrinsic.Unpack4x8Unorm |
			Intrinsic.Unpack4x8Snorm | Intrinsic.Unpack2x16Unorm | Intrinsic.Unpack2x16Snorm |
			Intrinsic.Unpack2x16Float => true,
	};
}

export function mathName(op: Intrinsic): string {
	return match (op) {
		Intrinsic.Abs => "abs",
		Intrinsic.Sign => "sign",
		Intrinsic.Floor => "floor",
		Intrinsic.Ceil => "ceil",
		Intrinsic.Trunc => "trunc",
		Intrinsic.Round => "round",
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
		Intrinsic.Atan => "atan",
		Intrinsic.Atan2 => "atan2",
		Intrinsic.Sinh => "sinh",
		Intrinsic.Cosh => "cosh",
		Intrinsic.Tanh => "tanh",
		Intrinsic.Asinh => "asinh",
		Intrinsic.Acosh => "acosh",
		Intrinsic.Atanh => "atanh",
		Intrinsic.Ldexp => "ldexp",
		Intrinsic.Modf => "modf",
		Intrinsic.Frexp => "frexp",
		Intrinsic.Degrees => "degrees",
		Intrinsic.Radians => "radians",
		Intrinsic.Min => "min",
		Intrinsic.Max => "max",
		Intrinsic.Clamp => "clamp",
		Intrinsic.Saturate => "saturate",
		Intrinsic.Mix => "mix",
		Intrinsic.Step => "step",
		Intrinsic.Smoothstep => "smoothstep",
		Intrinsic.Fma => "fma",
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
		Intrinsic.Any => "any",
		Intrinsic.All => "all",
		Intrinsic.Dpdx => "dFdx",
		Intrinsic.Dpdy => "dFdy",
		Intrinsic.Fwidth => "fwidth",
		Intrinsic.DpdxCoarse => "dFdxCoarse",
		Intrinsic.DpdxFine => "dFdxFine",
		Intrinsic.DpdyCoarse => "dFdyCoarse",
		Intrinsic.DpdyFine => "dFdyFine",
		Intrinsic.FwidthCoarse => "fwidthCoarse",
		Intrinsic.FwidthFine => "fwidthFine",
		Intrinsic.Bitcast => "bitcast",
		Intrinsic.CountOneBits => "bitCount",
		Intrinsic.ReverseBits => "bitfieldReverse",
		Intrinsic.FirstLeadingBit => "findMSB",
		Intrinsic.FirstTrailingBit => "findLSB",
		Intrinsic.CountLeadingZeros => "countLeadingZeros",
		Intrinsic.CountTrailingZeros => "countTrailingZeros",
		Intrinsic.ExtractBits => "bitfieldExtract",
		Intrinsic.InsertBits => "bitfieldInsert",
		Intrinsic.Pack4x8Unorm => "packUnorm4x8",
		Intrinsic.Pack4x8Snorm => "packSnorm4x8",
		Intrinsic.Pack2x16Unorm => "packUnorm2x16",
		Intrinsic.Pack2x16Snorm => "packSnorm2x16",
		Intrinsic.Pack2x16Float => "packHalf2x16",
		Intrinsic.Unpack4x8Unorm => "unpackUnorm4x8",
		Intrinsic.Unpack4x8Snorm => "unpackSnorm4x8",
		Intrinsic.Unpack2x16Unorm => "unpackUnorm2x16",
		Intrinsic.Unpack2x16Snorm => "unpackSnorm2x16",
		Intrinsic.Unpack2x16Float => "unpackHalf2x16",
		_ => { unspelled("math", op); },
	};
}

export function glslAtomicName(op: Intrinsic): string {
	return match (op) {
		Intrinsic.AtomicLoad | Intrinsic.AtomicAdd | Intrinsic.AtomicSub => "atomicAdd",
		Intrinsic.AtomicMax => "atomicMax",
		Intrinsic.AtomicMin => "atomicMin",
		Intrinsic.AtomicAnd => "atomicAnd",
		Intrinsic.AtomicOr => "atomicOr",
		Intrinsic.AtomicXor => "atomicXor",
		Intrinsic.AtomicCompareExchangeWeak => "atomicCompSwap",
		Intrinsic.AtomicStore | Intrinsic.AtomicExchange => "atomicExchange",
		_ => { unspelled("GLSL atomic", op); },
	};
}

export function exchangeSlot(scalar: ScalarKind): int32 { return scalar == ScalarKind.I32 ? 0 : 1; }

export function floatText(v: float64): string {
	return v == 0.0 && 1.0 / v < 0.0 ? "-0.0" : String(v);
}

export function pointed(text: string): string {
	return text.includes(".") || text.includes("e") ? text : text + ".0";
}

export function isIntMin(s: ScalarKind, v: float64): boolean {
	return s == ScalarKind.I32 && v == -2147483648.0;
}

export function isNarrowBits(op: Intrinsic): boolean {
	return op == Intrinsic.CountOneBits || op == Intrinsic.FirstLeadingBit ||
		op == Intrinsic.FirstTrailingBit;
}

function unsignedOf(signedType: string): string {
	return signedType == "int" ? "uint" : "u" + signedType.substring(1);
}

// The GLSL spelling of the bit and pack builtins, as naga's back-end writes them. bitCount, findMSB
// and findLSB return int, so an unsigned operand's result is converted back; bitfieldExtract and
// bitfieldInsert are undefined past the 32 bits WGSL clamps to, so the offset and count clamp first.
// The offset of an extract and of an insert is printed twice.
export function glslBits(
	op: Intrinsic,
	args: string[],
	resultType: string,
	unsigned: boolean,
): string {
	const call = mathName(op) + "(" + args.join(", ") + ")";
	if (isNarrowBits(op)) { return unsigned ? resultType + "(" + call + ")" : call; }
	if (op == Intrinsic.CountLeadingZeros) {
		return unsigned ? resultType + "(31 - findMSB(" + args[0] + "))" :
			"31 - findMSB(" + unsignedOf(resultType) + "(" + args[0] + "))";
	}
	if (op == Intrinsic.CountTrailingZeros) {
		const word = unsigned ? resultType : unsignedOf(resultType);
		const lowest = word + "(findLSB(" + args[0] + "))";
		return unsigned ? "min(" + lowest + ", 32u)" :
			resultType + "(min(" + lowest + ", 32u))";
	}
	if (op == Intrinsic.ExtractBits) {
		return "bitfieldExtract(" + args[0] + ", int(min(" + args[1] + ", 32u)), int(min(" +
			args[2] + ", 32u - min(" + args[1] + ", 32u))))";
	}
	if (op == Intrinsic.InsertBits) {
		return "bitfieldInsert(" + args[0] + ", " + args[1] + ", int(min(" + args[2] +
			", 32u)), int(min(" + args[3] + ", 32u - min(" + args[2] + ", 32u))))";
	}
	return call;
}

// The operand of a bit builtin that a printer repeats.
export function repeatedBitsOperand(op: Intrinsic): int32 {
	return op == Intrinsic.ExtractBits ? 1 : op == Intrinsic.InsertBits ? 2 : -1;
}

// GLSL's bitcast: the float functions reinterpret, and an i32 and a u32 share their bits through
// the constructor, as WGSL's conversion between them does.
export function glslBitcast(
	from: ScalarKind,
	to: ScalarKind,
	resultType: string,
	arg: string,
): string {
	if (from == ScalarKind.F32) {
		return (to == ScalarKind.I32 ? "floatBitsToInt(" : "floatBitsToUint(") + arg + ")";
	}
	if (to == ScalarKind.F32) {
		return (from == ScalarKind.I32 ? "intBitsToFloat(" : "uintBitsToFloat(") + arg + ")";
	}
	return resultType + "(" + arg + ")";
}

// The structs of modf and frexp are predeclared in WGSL; the other targets declare one per width
// the module uses, with a helper that makes it, as naga's back-ends do.
export function splitStructName(t: ShaderType): string {
	const head = t.kind == ShaderTypeKind.ModfResult ? "ModfResult" : "FrexpResult";
	return head + (t.rows == 1 ? "F32" : "Vec" + String(t.rows) + "f");
}

export function splitHelperName(t: ShaderType): string {
	const head = t.kind == ShaderTypeKind.ModfResult ? "modf" : "frexp";
	return head + (t.rows == 1 ? "F32" : "Vec" + String(t.rows) + "f");
}

export function splitMember(t: ShaderType, member: int32): string {
	if (member == 0) { return "fract"; }
	return t.kind == ShaderTypeKind.ModfResult ? "whole" : "exp";
}

// GLSL's float or vec and the type of the second field: the same for modf, an int or ivec for frexp.
export function glslSplitTypes(t: ShaderType): string[] {
	const arg = t.rows == 1 ? "float" : "vec" + String(t.rows);
	if (t.kind == ShaderTypeKind.ModfResult) { return [arg, arg]; }
	return [arg, t.rows == 1 ? "int" : "ivec" + String(t.rows)];
}

// The layout qualifier of a storage texture's format; bgra8unorm has none, so a printer refuses it first.
export function glslImageFormat(f: TexelFormat): string {
	return match (f) {
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
		TexelFormat.Bgra8unorm => { throw new Error("internal: bgra8unorm has no GLSL image format"); },
	};
}

export function glslInterpolation(i: Interpolation): string {
	return match (i) {
		Interpolation.Perspective => "",
		Interpolation.Linear => "noperspective ",
		Interpolation.Flat => "flat ",
	};
}

export function glslSampling(s: Sampling): string {
	return match (s) {
		Sampling.Center => "",
		Sampling.Centroid => "centroid ",
		Sampling.Sample => "sample ",
	};
}

// The GLSL function of an intrinsic whose name WGSL spells differently, shared by 430, ES 300 and 450.
export function glslMathName(op: Intrinsic): string {
	return match (op) {
		Intrinsic.Round => "roundEven",
		Intrinsic.Atan2 => "atan",
		Intrinsic.LessThan => "lessThan",
		Intrinsic.LessThanEqual => "lessThanEqual",
		Intrinsic.GreaterThan => "greaterThan",
		Intrinsic.GreaterThanEqual => "greaterThanEqual",
		Intrinsic.Equal => "equal",
		Intrinsic.NotEqual => "notEqual",
		_ => mathName(op),
	};
}

export function glslAccessWord(a: Access): string {
	return match (a) {
		Access.Read => "readonly ",
		Access.Write => "writeonly ",
		Access.ReadWrite => "",
	};
}
