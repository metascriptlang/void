import { BinaryOp, Intrinsic, ScalarKind } from "./ir";

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

export function isComponentCompare(op: Intrinsic): boolean {
	return op == Intrinsic.LessThan || op == Intrinsic.LessThanEqual || op == Intrinsic.GreaterThan ||
		op == Intrinsic.GreaterThanEqual || op == Intrinsic.Equal || op == Intrinsic.NotEqual;
}

// The operator that spells a componentwise test where the target compares vectors by operator.
export function componentCompare(op: Intrinsic): BinaryOp {
	return match (op) {
		Intrinsic.LessThan => BinaryOp.Less,
		Intrinsic.LessThanEqual => BinaryOp.LessEqual,
		Intrinsic.GreaterThan => BinaryOp.Greater,
		Intrinsic.GreaterThanEqual => BinaryOp.GreaterEqual,
		Intrinsic.Equal => BinaryOp.Equal,
		Intrinsic.NotEqual => BinaryOp.NotEqual,
		_ => { unspelled("componentwise test", op); },
	};
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
			Intrinsic.TextureDimensions | Intrinsic.TextureSampleCompare |
			Intrinsic.TextureSampleCompareLevel | Intrinsic.TextureSampleLevel |
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
			Intrinsic.Degrees | Intrinsic.Radians | Intrinsic.Min | Intrinsic.Max |
			Intrinsic.Clamp | Intrinsic.Saturate | Intrinsic.Mix | Intrinsic.Step |
			Intrinsic.Smoothstep | Intrinsic.Fma | Intrinsic.Dot | Intrinsic.Cross |
			Intrinsic.Length | Intrinsic.Distance | Intrinsic.Normalize | Intrinsic.Reflect |
			Intrinsic.Refract | Intrinsic.FaceForward | Intrinsic.Transpose |
			Intrinsic.Determinant | Intrinsic.Any | Intrinsic.All | Intrinsic.Dpdx | Intrinsic.Dpdy |
			Intrinsic.Fwidth |
			Intrinsic.CountOneBits | Intrinsic.ReverseBits | Intrinsic.FirstLeadingBit |
			Intrinsic.FirstTrailingBit | Intrinsic.ExtractBits | Intrinsic.InsertBits |
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
		Intrinsic.CountOneBits => "bitCount",
		Intrinsic.ReverseBits => "bitfieldReverse",
		Intrinsic.FirstLeadingBit => "findMSB",
		Intrinsic.FirstTrailingBit => "findLSB",
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
