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

function unspelled(what: string, op: Intrinsic): never {
	throw new Error("internal: no " + what + " spelling for " + op.toString());
}

export function isMath(op: Intrinsic): boolean {
	return match (op) {
		Intrinsic.Inverse | Intrinsic.UpperLeft3x3 | Intrinsic.Select | Intrinsic.LessThanEqual |
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
			Intrinsic.Determinant | Intrinsic.Dpdx | Intrinsic.Dpdy | Intrinsic.Fwidth => true,
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
		Intrinsic.Dpdx => "dFdx",
		Intrinsic.Dpdy => "dFdy",
		Intrinsic.Fwidth => "fwidth",
		_ => { unspelled("math", op); },
	};
}

// GLSL 4.30 has no atomic load or store: a load is an add of 0 and a store an exchange.
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
