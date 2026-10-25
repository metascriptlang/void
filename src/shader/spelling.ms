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
		_ => "",
	};
}

export function floatText(v: float64): string {
	return v == 0.0 && 1.0 / v < 0.0 ? "-0.0" : String(v);
}

export function pointed(text: string): string {
	return text.includes(".") || text.includes("e") ? text : text + ".0";
}

export function isIntMin(s: ScalarKind, v: float64): boolean {
	return s == ScalarKind.I32 && v == -2147483648.0;
}
