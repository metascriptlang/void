import {
	Access,
	AssignOp,
	BinaryOp,
	Builtin,
	ConditionKind,
	DeclarationKind,
	ExprKind,
	FeatureCondition,
	Interpolation,
	Intrinsic,
	IoDirection,
	ResourceKind,
	SampleType,
	SamplerType,
	ScalarKind,
	ShaderEntry,
	ShaderExpr,
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
	isAtomic,
	isShift,
} from "./ir";
import {
	Names,
	fieldNames,
	nameConstant,
	nameFunction,
	nameLocal,
	nameParam,
	nameStruct,
	suffixed,
} from "./names";
import { binaryOperator, mathName } from "./spelling";

// GLSL 4.50 keywords and reserved words (section 3.6), builtin functions (section 8) and the
// texture and sampler types of Vulkan GLSL.
export function glslReservedWords(): string[] {
	let words = [
		"attribute", "const", "uniform", "varying", "buffer", "shared", "coherent", "volatile",
		"restrict", "readonly", "writeonly", "atomic_uint", "layout", "centroid", "flat", "smooth",
		"noperspective", "patch", "sample", "invariant", "precise", "break", "continue", "do",
		"for", "while", "switch", "case", "default", "if", "else", "subroutine", "in", "out",
		"inout", "float", "double", "int", "uint", "void", "bool", "true", "false", "discard",
		"return", "lowp", "mediump", "highp", "precision", "struct", "sampler", "common",
		"partition", "active", "asm", "class", "union", "enum", "typedef", "template", "this",
		"resource", "goto", "inline", "noinline", "public", "static", "extern", "external",
		"interface", "long", "short", "half", "fixed", "unsigned", "superp", "input", "output",
		"hvec2", "hvec3", "hvec4", "fvec2", "fvec3", "fvec4", "sampler3DRect", "filter", "sizeof",
		"cast", "namespace", "using",
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
		"atomicCounterIncrement", "atomicCounterDecrement", "atomicCounter", "atomicAdd",
		"atomicMin", "atomicMax", "atomicAnd", "atomicOr", "atomicXor", "atomicExchange",
		"atomicCompSwap", "imageSize", "imageSamples", "imageLoad", "imageStore",
		"imageAtomicAdd", "imageAtomicMin", "imageAtomicMax", "imageAtomicAnd", "imageAtomicOr",
		"imageAtomicXor", "imageAtomicExchange", "imageAtomicCompSwap", "EmitStreamVertex",
		"EndStreamPrimitive", "EmitVertex", "EndPrimitive", "dFdx", "dFdy", "dFdxFine",
		"dFdyFine", "dFdxCoarse", "dFdyCoarse", "fwidth", "fwidthFine", "fwidthCoarse",
		"interpolateAtCentroid", "interpolateAtSample", "interpolateAtOffset", "noise1",
		"noise2", "noise3", "noise4", "barrier", "memoryBarrier", "memoryBarrierAtomicCounter",
		"memoryBarrierBuffer", "memoryBarrierShared", "memoryBarrierImage",
		"groupMemoryBarrier", "subpassLoad",
	];
	for (const prefix of ["", "b", "i", "u", "d"]) {
		for (let n = 2; n <= 4; n++) { words.push(prefix + "vec" + String(n)); }
	}
	for (const prefix of ["", "d"]) {
		for (let n = 2; n <= 4; n++) {
			words.push(prefix + "mat" + String(n));
			for (let m = 2; m <= 4; m++) {
				words.push(prefix + "mat" + String(n) + "x" + String(m));
			}
		}
	}
	const shapes = [
		"1D", "2D", "3D", "Cube", "2DRect", "1DArray", "2DArray", "CubeArray", "Buffer", "2DMS",
		"2DMSArray",
	];
	for (const prefix of ["", "i", "u"]) {
		for (const opaque of ["sampler", "texture", "image"]) {
			for (const shape of shapes) { words.push(prefix + opaque + shape); }
		}
		words.push(prefix + "subpassInput");
		words.push(prefix + "subpassInputMS");
	}
	for (const shape of ["", "1D", "2D", "Cube", "2DRect", "1DArray", "2DArray", "CubeArray"]) {
		words.push("sampler" + shape + "Shadow");
	}
	return words;
}

class Glsl {
	module: ShaderModule = new ShaderModule();
	entry: ShaderEntry = new ShaderEntry();
	ioNames: string[] = [];
	structNames: string[] = [];
	structFields: string[][] = [];
	constantNames: string[] = [];
	functionNames: string[] = [];
	paramNames: string[][] = [];
	localNames: string[][] = [];
	workgroupNames: string[] = [];
	exchangeNames: string[] = ["", ""];
	exchangeMakers: string[] = ["", ""];
	fn: int32 = -1;
	samplerless: boolean = false;
}

function isNever(c: FeatureCondition): boolean {
	return c.kind == ConditionKind.Any && c.operands.length == 0;
}

function conditionText(c: FeatureCondition): string {
	return match (c.kind) {
		ConditionKind.Always => "",
		ConditionKind.Feature => "defined(" + c.feature + ")",
		ConditionKind.Not => "!" + groupedCondition(c.operands[0]),
		ConditionKind.All => c.operands.map((o) => groupedCondition(o)).join(" && "),
		ConditionKind.Any => c.operands.map((o) => groupedCondition(o)).join(" || "),
	};
}

function groupedCondition(c: FeatureCondition): string {
	const joined = c.kind == ConditionKind.All || c.kind == ConditionKind.Any;
	return joined ? "(" + conditionText(c) + ")" : conditionText(c);
}

function opening(c: FeatureCondition): string {
	if (c.kind == ConditionKind.Feature) { return "#ifdef " + c.feature; }
	if (c.kind == ConditionKind.Not && c.operands[0].kind == ConditionKind.Feature) {
		return "#ifndef " + c.operands[0].feature;
	}
	return "#if " + conditionText(c);
}

function gated(c: FeatureCondition, text: string): string {
	if (isNever(c)) { return ""; }
	if (c.kind == ConditionKind.Always) { return text; }
	return opening(c) + "\n" + text + "#endif\n";
}

function scalarName(s: ScalarKind): string {
	return match (s) {
		ScalarKind.F32 => "float",
		ScalarKind.I32 => "int",
		ScalarKind.U32 => "uint",
		ScalarKind.Bool => "bool",
	};
}

function broken(message: string): never {
	throw new Error("printGlsl450: " + message);
}

function vectorPrefix(s: ScalarKind): string {
	return match (s) {
		ScalarKind.F32 => "",
		ScalarKind.I32 => "i",
		ScalarKind.U32 => "u",
		ScalarKind.Bool => "b",
	};
}

function typeName(p: Glsl, t: ShaderType): string {
	return match (t.kind) {
		ShaderTypeKind.Scalar => scalarName(t.scalar),
		ShaderTypeKind.Vector => vectorPrefix(t.scalar) + "vec" + String(t.rows),
		ShaderTypeKind.Matrix => "mat" + String(t.columns),
		ShaderTypeKind.Array => typeName(p, t.element[0]) + "[" + String(t.length) + "]",
		ShaderTypeKind.Struct => p.structNames[t.structIndex],
		ShaderTypeKind.Atomic => scalarName(t.scalar),
		ShaderTypeKind.ExchangeResult => p.exchangeNames[exchangeSlot(t.scalar)],
		_ => { broken("a " + t.kind.toString() + " is no GLSL value type"); },
	};
}

function exchangeSlot(scalar: ScalarKind): int32 { return scalar == ScalarKind.I32 ? 0 : 1; }

function atomicName(op: Intrinsic): string {
	return match (op) {
		Intrinsic.AtomicLoad | Intrinsic.AtomicAdd | Intrinsic.AtomicSub => "atomicAdd",
		Intrinsic.AtomicMax => "atomicMax",
		Intrinsic.AtomicMin => "atomicMin",
		Intrinsic.AtomicAnd => "atomicAnd",
		Intrinsic.AtomicOr => "atomicOr",
		Intrinsic.AtomicXor => "atomicXor",
		Intrinsic.AtomicCompareExchangeWeak => "atomicCompSwap",
		_ => "atomicExchange",
	};
}

function atomicText(e: ShaderExpr, args: string[]): string {
	const unsigned = e.operands[0].type.scalar == ScalarKind.U32;
	const rest = match (e.intrinsic) {
		Intrinsic.AtomicLoad => unsigned ? "0u" : "0",
		Intrinsic.AtomicSub => "-(" + args[1] + ")",
		_ => args.slice(1).join(", "),
	};
	return atomicName(e.intrinsic) + "(" + args[0] + ", " + rest + ")";
}

function exchangeLet(p: Glsl, s: ShaderStmt, indent: string): string {
	const name = p.localNames[p.fn][s.local];
	const slot = exchangeSlot(s.expr.operands[0].type.scalar);
	const args = s.expr.operands.map((a) => expr(p, a));
	return indent + p.exchangeNames[slot] + " " + name + " = " + p.exchangeNames[slot] + "(" +
		value(p, s.expr.operands[1]) + ", false);\n" + indent + name + " = " +
		p.exchangeMakers[slot] + "(" + name + ".old_value, atomicCompSwap(" + args[0] + ", " +
		name + ".old_value, " + args[2] + "));\n";
}

function declared(p: Glsl, t: ShaderType, name: string): string {
	if (t.kind == ShaderTypeKind.Array) {
		return typeName(p, t.element[0]) + " " + name + "[" + String(t.length) + "]";
	}
	return typeName(p, t) + " " + name;
}

function isVarying(io: ShaderIo): boolean {
	return io.builtin == Builtin.None && (io.stage == ShaderStage.Vertex ?
		io.direction == IoDirection.Out : io.direction == IoDirection.In);
}

function builtinName(io: ShaderIo): string {
	if (io.direction == IoDirection.Out) { return "gl_Position"; }
	return match (io.builtin) {
		Builtin.VertexIndex => "uint(gl_VertexIndex)",
		Builtin.InstanceIndex => "uint(gl_InstanceIndex)",
		Builtin.Position => "gl_FragCoord",
		Builtin.FrontFacing => "gl_FrontFacing",
		Builtin.GlobalInvocationId => "gl_GlobalInvocationID",
		Builtin.LocalInvocationId => "gl_LocalInvocationID",
		Builtin.LocalInvocationIndex => "gl_LocalInvocationIndex",
		Builtin.WorkgroupId => "gl_WorkGroupID",
		Builtin.NumWorkgroups => "gl_NumWorkGroups",
		_ => { broken("@builtin " + io.builtin.toString() + " has no GLSL input"); },
	};
}

function ioName(p: Glsl, index: int32): string {
	const io = p.module.ios[index];
	return io.builtin == Builtin.None ? p.ioNames[index] : builtinName(io);
}

function integerText(value: float64): string {
	return String(value as int64);
}

function literalText(e: ShaderExpr): string {
	if (e.type.scalar == ScalarKind.Bool) { return e.value != 0.0 ? "true" : "false"; }
	if (e.type.scalar != ScalarKind.F32) { return integerText(e.value); }
	const text = String(e.value);
	return text.indexOf(".") >= 0 || text.indexOf("e") >= 0 ? text : text + ".0";
}

function isIntegerScalar(t: ShaderType): boolean {
	return t.kind == ShaderTypeKind.Scalar &&
		(t.scalar == ScalarKind.I32 || t.scalar == ScalarKind.U32);
}

function value(p: Glsl, e: ShaderExpr): string {
	if (e.kind == ExprKind.Binary) {
		const left = e.operands[0];
		const right = e.operands[1];
		if (e.binary == BinaryOp.Mod && !isIntegerScalar(left.type)) {
			const leftText = expr(p, left);
			const rightText = expr(p, right);
			return leftText + " - " + rightText + " * trunc(" + leftText + " / " + rightText +
				")";
		}
		const amount = isShift(e.binary) && right.kind != ExprKind.Literal ?
			"(" + expr(p, right) + " & 31u)" : expr(p, right);
		return expr(p, left) + " " + binaryOperator(e.binary) + " " + amount;
	}
	if (e.kind == ExprKind.Unary) {
		const operand = e.operands[0];
		const op = e.unary == UnaryOp.Negate ? "-" :
			operand.type.scalar == ScalarKind.Bool ? "!" : "~";
		return op +
			(operand.kind == ExprKind.Unary ? "(" + value(p, operand) + ")" : expr(p, operand));
	}
	if (e.kind == ExprKind.Conditional) {
		return expr(p, e.operands[0]) + " ? " + expr(p, e.operands[1]) + " : " +
			expr(p, e.operands[2]);
	}
	return expr(p, e);
}

function listed(p: Glsl, args: ShaderExpr[]): string {
	return "(" + args.map((a) => expr(p, a)).join(", ") + ")";
}

const COMPONENTS = "xyzw";
const COLOUR_COMPONENTS = "rgba";

function swizzle(e: ShaderExpr): string {
	const letters = e.rgba ? COLOUR_COMPONENTS : COMPONENTS;
	let text = "";
	for (const c of e.components) { text += letters.slice(c, c + 1); }
	return text;
}

function expr(p: Glsl, e: ShaderExpr): string {
	const m = p.module;
	return match (e.kind) {
		ExprKind.Literal => literalText(e),
		ExprKind.Unary => e.unary == UnaryOp.Negate && e.operands[0].kind == ExprKind.Literal ?
			"-" + literalText(e.operands[0]) : "(" + value(p, e) + ")",
		ExprKind.Binary | ExprKind.Conditional => "(" + value(p, e) + ")",
		ExprKind.Local => p.localNames[p.fn][e.index],
		ExprKind.Param => p.paramNames[p.fn][e.index],
		ExprKind.Constant => p.constantNames[e.index],
		ExprKind.Io => ioName(p, e.index),
		ExprKind.Resource => m.resources[e.index].name,
		ExprKind.Workgroup => p.workgroupNames[e.index],
		ExprKind.BlockMember =>
			m.structs[m.resources[e.index].type.structIndex].members[e.member].name,
		ExprKind.Call => p.functionNames[e.index] + listed(p, e.operands),
		ExprKind.Intrinsic => intrinsic(p, e),
		ExprKind.Construct => typeName(p, e.type) + listed(p, e.operands),
		ExprKind.Convert => e.type.kind == ShaderTypeKind.Scalar &&
			e.type.scalar == ScalarKind.U32 && e.operands[0].kind == ExprKind.Literal ?
			integerText(e.operands[0].value) + "u" :
			typeName(p, e.type) + "(" + value(p, e.operands[0]) + ")",
		ExprKind.Field => e.operands[0].type.kind == ShaderTypeKind.ExchangeResult ?
			expr(p, e.operands[0]) + (e.index == 0 ? ".old_value" : ".exchanged") :
			expr(p, e.operands[0]) + "." + p.structFields[e.operands[0].type.structIndex][e.index],
		ExprKind.Swizzle => expr(p, e.operands[0]) + "." + swizzle(e),
		ExprKind.Index => expr(p, e.operands[0]) + "[" + value(p, e.operands[1]) + "]",
	};
}

function intrinsicName(op: Intrinsic): string {
	return match (op) {
		Intrinsic.Round => "roundEven",
		Intrinsic.Atan2 => "atan",
		Intrinsic.Saturate => "clamp",
		Intrinsic.Inverse => "inverse",
		Intrinsic.UpperLeft3x3 => "mat3",
		Intrinsic.Select => "mix",
		Intrinsic.LessThanEqual => "lessThanEqual",
		Intrinsic.TextureSample => "texture",
		Intrinsic.TextureLoad => "texelFetch",
		Intrinsic.TextureStore => "imageStore",
		Intrinsic.TextureDimensions => "textureSize",
		Intrinsic.TextureSampleCompare => "texture",
		Intrinsic.TextureSampleCompareLevel | Intrinsic.TextureSampleLevel => "textureLod",
		Intrinsic.TextureSampleBias => "texture",
		Intrinsic.TextureSampleGrad => "textureGrad",
		Intrinsic.WorkgroupBarrier | Intrinsic.StorageBarrier => "barrier",
		Intrinsic.AtomicLoad | Intrinsic.AtomicStore | Intrinsic.AtomicAdd | Intrinsic.AtomicSub |
			Intrinsic.AtomicMax | Intrinsic.AtomicMin | Intrinsic.AtomicAnd | Intrinsic.AtomicOr |
			Intrinsic.AtomicXor | Intrinsic.AtomicExchange |
			Intrinsic.AtomicCompareExchangeWeak => atomicName(op),
		_ => mathOrStop(op),
	};
}

function mathOrStop(op: Intrinsic): string {
	const name = mathName(op);
	if (name == "") { throw new Error("internal: printGlsl450 has no spelling for " + op.toString()); }
	return name;
}

function intrinsic(p: Glsl, e: ShaderExpr): string {
	const args = e.operands.map((a) => expr(p, a));
	const all = "(" + args.join(", ") + ")";
	const texture = e.operands.length > 0 ? e.operands[0].type : new ShaderType();
	const layered = texture.kind == ShaderTypeKind.Texture && texture.shape == TextureShape.D2Array;
	const cube = texture.kind == ShaderTypeKind.Texture && texture.shape == TextureShape.Cube;
	const shape = texture.kind == ShaderTypeKind.Texture && texture.scalar == ScalarKind.U32 ?
		"usampler2D(" : layered ? "sampler2DArray(" : cube ? "samplerCube(" : "sampler2D(";
	const sampled = args.length >= 2 ? shape + args[0] + ", " + args[1] + ")" : "";
	return match (e.intrinsic) {
		Intrinsic.Saturate => "clamp(" + args[0] + ", 0.0, 1.0)",
		Intrinsic.Select => e.operands[2].type.kind == ShaderTypeKind.Vector ? "mix" + all :
			"(" + args[2] + " ? " + args[1] + " : " + args[0] + ")",
		Intrinsic.TextureDimensions | Intrinsic.TextureLoad => fetched(p, e, args),
		Intrinsic.TextureStore => "imageStore(" + args[0] + ", " + imageAt(e, args) + ", " +
			args[args.length - 1] + ")",
		Intrinsic.TextureSample => layered ?
			"texture(" + sampled + ", vec3(" + args[2] + ", float(" + args[3] + ")))" :
			"texture(" + sampled + ", " + args[2] + ")",
		Intrinsic.TextureSampleCompare | Intrinsic.TextureSampleCompareLevel => compared(e, args),
		Intrinsic.TextureSampleLevel | Intrinsic.TextureSampleBias | Intrinsic.TextureSampleGrad =>
			intrinsicName(e.intrinsic) + "(" + sampled + ", " + (layered ? "vec3(" + args[2] +
				", float(" + args[3] + "))" : args[2]) + ", " +
				args.slice(layered ? 4 : 3).join(", ") + ")",
		// glslang gives a compute barrier() workgroup-memory semantics, while the OpMemoryBarrier
		// of memoryBarrierShared() is refused by sokol-shdc's WGSL reader (measured, shdc win32).
		Intrinsic.WorkgroupBarrier => "barrier()",
		Intrinsic.StorageBarrier => "memoryBarrierBuffer(); barrier()",
		Intrinsic.AtomicCompareExchangeWeak => {
			broken("AtomicCompareExchangeWeak outside a local's initializer or a statement of " +
				"its own: atomicCompSwap returns only the old value");
		},
		_ => isAtomic(e.intrinsic) ? atomicText(e, args) : intrinsicName(e.intrinsic) + all,
	};
}

function fetched(p: Glsl, e: ShaderExpr, all: string[]): string {
	const args = all.filter((_, i) => e.operands[i].type.kind != ShaderTypeKind.Sampler);
	const texture = e.operands[0].type;
	if (texture.kind == ShaderTypeKind.StorageTexture) {
		if (e.intrinsic == Intrinsic.TextureLoad) {
			return "imageLoad(" + args[0] + ", " + imageAt(e, args) + ")";
		}
		const size = "imageSize(" + args[0] + ")";
		return texture.shape == TextureShape.D2Array ? size + ".xy" : size;
	}
	p.samplerless = true;
	if (e.intrinsic == Intrinsic.TextureDimensions) {
		return "textureSize(" + args[0] + ", " + args[1] + ")";
	}
	return texture.shape == TextureShape.D2Array ?
		"texelFetch(" + args[0] + ", ivec3(" + args[1] + ", " + args[2] + "), " + args[3] + ")" :
		"texelFetch(" + args[0] + ", " + args[1] + ", " + args[2] + ")";
}

function imageAt(e: ShaderExpr, args: string[]): string {
	return e.operands[0].type.shape == TextureShape.D2Array ?
		"ivec3(" + args[1] + ", " + args[2] + ")" : args[1];
}

function imageName(t: ShaderType): string {
	const unsigned = t.format == TexelFormat.R32uint || t.format == TexelFormat.Rgba8uint;
	return (unsigned ? "u" : "") + match (t.shape) {
		TextureShape.D2Array => "image2DArray",
		TextureShape.D3 => "image3D",
		_ => "image2D",
	};
}

function compared(e: ShaderExpr, args: string[]): string {
	const level = e.intrinsic == Intrinsic.TextureSampleCompareLevel;
	const layered = e.operands[0].type.shape == TextureShape.Depth2dArray;
	const coords = args[2] + (layered ? ", float(" + args[3] + ")" : "") + ", " +
		args[args.length - 1];
	const pair = "(" + args[0] + ", " + args[1] + ")";
	return match (e.operands[0].type.shape) {
		TextureShape.Depth2dArray => level ? "textureGrad(sampler2DArrayShadow" + pair +
			", vec4(" + coords + "), vec2(0.0), vec2(0.0))" :
			"texture(sampler2DArrayShadow" + pair + ", vec4(" + coords + "))",
		TextureShape.DepthCube => level ? "textureGrad(samplerCubeShadow" + pair + ", vec4(" +
			coords + "), vec3(0.0), vec3(0.0))" :
			"texture(samplerCubeShadow" + pair + ", vec4(" + coords + "))",
		_ => level ? "textureLod(sampler2DShadow" + pair + ", vec3(" + coords + "), 0.0)" :
			"texture(sampler2DShadow" + pair + ", vec3(" + coords + "))",
	};
}

function simple(p: Glsl, s: ShaderStmt): string {
	if (s.kind == StmtKind.Let) {
		const local = p.module.functions[p.fn].locals[s.local];
		return typeName(p, local.type) + " " + p.localNames[p.fn][s.local] + " = " +
			value(p, s.expr);
	}
	if (s.kind == StmtKind.Call) { return expr(p, s.expr); }
	const target = expr(p, s.target);
	return match (s.assign) {
		AssignOp.Increment => target + "++",
		AssignOp.Decrement => target + "--",
		_ => target + " " + match (s.assign) {
			AssignOp.Add => "+=",
			AssignOp.Sub => "-=",
			AssignOp.Mul => "*=",
			AssignOp.Div => "/=",
			AssignOp.Mod => "%=",
			_ => "=",
		} + " " + (s.target.kind == ExprKind.Io ? expr(p, s.expr) : value(p, s.expr)),
	};
}

function statements(p: Glsl, list: ShaderStmt[], indent: string): string {
	let out = "";
	for (const s of list) { out += stmt(p, s, indent); }
	return out;
}

function branches(p: Glsl, s: ShaderStmt, indent: string): string {
	const inner = indent + "    ";
	const out = "if (" + value(p, s.expr) + ") {\n" + statements(p, s.body, inner) + indent + "}";
	const other = s.otherwise;
	if (other.length == 0) { return out; }
	if (other.length == 1 && other[0].kind == StmtKind.If) {
		return out + " else " + branches(p, other[0], indent);
	}
	const list = other.length == 1 && other[0].kind == StmtKind.Block ? other[0].body : other;
	return out + " else {\n" + statements(p, list, inner) + indent + "}";
}

function caseText(p: Glsl, labels: string[], body: ShaderStmt[], indent: string): string {
	const inner = indent + "    ";
	let text = indent + labels.join(" ") + " {\n" + statements(p, body, inner);
	const last = body.length > 0 ? body[body.length - 1].kind : StmtKind.Block;
	if (last != StmtKind.Return && last != StmtKind.Continue) { text += inner + "break;\n"; }
	return text + indent + "}\n";
}

function switchText(p: Glsl, s: ShaderStmt, indent: string): string {
	let text = indent + "switch (" + value(p, s.expr) + ") {\n";
	for (const arm of s.cases) {
		let labels: string[] = arm.isDefault ? ["default:"] : [];
		for (const label of arm.labels) { labels.push("case " + value(p, label) + ":"); }
		text += caseText(p, labels, arm.body, indent + "    ");
	}
	return text + indent + "}\n";
}

function outputName(p: Glsl): string {
	for (let i = 0; i < p.module.ios.length; i++) {
		const io = p.module.ios[i];
		if (io.stage == p.entry.stage && io.direction == IoDirection.Out) { return ioName(p, i); }
	}
	broken("the entry returns a value and has no output");
}

function stmt(p: Glsl, s: ShaderStmt, indent: string): string {
	const inner = indent + "    ";
	const exchange = s.expr.kind == ExprKind.Intrinsic &&
		s.expr.intrinsic == Intrinsic.AtomicCompareExchangeWeak;
	if (exchange && s.kind == StmtKind.Let) { return exchangeLet(p, s, indent); }
	if (exchange && s.kind == StmtKind.Call) {
		return indent + atomicText(s.expr, s.expr.operands.map((a) => expr(p, a))) + ";\n";
	}
	return match (s.kind) {
		StmtKind.Block => indent + "{\n" + statements(p, s.body, inner) + indent + "}\n",
		StmtKind.FeatureIf => opening(s.condition) + "\n" + statements(p, s.body, indent) +
			(s.otherwise.length > 0 ? "#else\n" + statements(p, s.otherwise, indent) : "") +
			"#endif\n",
		StmtKind.If => indent + branches(p, s, indent) + "\n",
		StmtKind.While => indent + "while (" + value(p, s.expr) + ") {\n" +
			statements(p, s.body, inner) + indent + "}\n",
		StmtKind.For => indent + "for (" + simple(p, s.init[0]) + "; " + value(p, s.expr) + "; " +
			simple(p, s.update[0]) + ") {\n" + statements(p, s.body, inner) + indent + "}\n",
		StmtKind.Switch => switchText(p, s, indent),
		StmtKind.Break => indent + "break;\n",
		StmtKind.Continue => indent + "continue;\n",
		StmtKind.Discard => indent + "discard;\n",
		StmtKind.Return => p.fn != p.entry.functionIndex ?
			indent + "return " + value(p, s.expr) + ";\n" :
			s.expr.type.kind == ShaderTypeKind.Void ? indent + "return;\n" :
			indent + outputName(p) + " = " + value(p, s.expr) + ";\n" + indent + "return;\n",
		StmtKind.Let | StmtKind.Assign | StmtKind.Call => indent + simple(p, s) + ";\n",
	};
}

function sampleTypeName(t: SampleType): string {
	return match (t) {
		SampleType.Float => "float",
		SampleType.UnfilterableFloat => "unfilterable_float",
		SampleType.Depth => "depth",
		SampleType.Sint => "sint",
		SampleType.Uint => "uint",
	};
}

function samplerTypeName(t: SamplerType): string {
	return match (t) {
		SamplerType.Filtering => "filtering",
		SamplerType.NonFiltering => "nonfiltering",
		SamplerType.Comparison => "comparison",
	};
}

function formatName(f: TexelFormat): string {
	return match (f) {
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

function accessMode(a: Access): string {
	return match (a) {
		Access.Read => "readonly ",
		Access.Write => "writeonly ",
		Access.ReadWrite => "",
	};
}

function resourceText(p: Glsl, r: ShaderResource): string {
	const at = "layout(binding=" + String(r.binding) + ")";
	const slot = at + " uniform ";
	return match (r.kind) {
		ResourceKind.UniformBlock => slot + r.name + " {\n" +
			p.module.structs[r.type.structIndex].members.map((f) =>
				"    " + declared(p, f.type, f.name) + ";\n").join("") + "};\n",
		ResourceKind.Texture => match (r.type.shape) {
			TextureShape.D2Array => slot + "texture2DArray " + r.name + ";\n",
			TextureShape.Cube => slot + "textureCube " + r.name + ";\n",
			TextureShape.Depth2dArray | TextureShape.DepthCube =>
				"@image_sample_type " + r.name + " depth\n" + slot + (r.type.shape ==
					TextureShape.DepthCube ? "textureCube " : "texture2DArray ") + r.name + ";\n",
			_ => r.type.scalar == ScalarKind.U32 ?
				"@image_sample_type " + r.name + " uint\n" + slot + "utexture2D " + r.name + ";\n" :
				(r.sampleType == SampleType.Float ? "" : "@image_sample_type " + r.name + " " +
					sampleTypeName(r.sampleType) + "\n") + slot + "texture2D " + r.name + ";\n",
		},
		ResourceKind.Sampler => (r.samplerType == SamplerType.Filtering ? "" : "@sampler_type " +
			r.name + " " + samplerTypeName(r.samplerType) + "\n") + slot + "sampler " + r.name +
			";\n",
		ResourceKind.StorageBuffer => at + " " + (r.access == Access.ReadWrite ? "" : "readonly ") +
			"buffer " + r.name + "Buffer {\n    " + typeName(p, r.type.element[0]) + " " + r.name +
			"[];\n};\n",
		ResourceKind.StorageTexture => "layout(binding=" + String(r.binding) + ", " +
			formatName(r.type.format) + ") uniform " + accessMode(r.type.access) +
			imageName(r.type) + " " + r.name + ";\n",
	};
}

function ioText(p: Glsl, index: int32): string {
	const io = p.module.ios[index];
	const spelled = declared(p, io.type, p.ioNames[index]);
	if (io.direction == IoDirection.Out && io.stage == ShaderStage.Fragment) {
		return "layout(location=" + String(io.location) + ") out " + spelled + ";\n";
	}
	return (io.interpolation == Interpolation.Flat ? "flat " : "") +
		(io.direction == IoDirection.In ? "in " : "out ") + spelled + ";\n";
}

function nameDeclarations(p: Glsl): void {
	const m = p.module;
	let names = new Names();
	names.reserved = glslReservedWords();
	names.values = ["main", "fragColor"];
	for (const r of m.resources) {
		names.globals.push(r.name);
		if (r.kind == ResourceKind.UniformBlock) {
			for (const f of m.structs[r.type.structIndex].members) { names.globals.push(f.name); }
		}
	}
	for (let i = 0; i < m.ios.length; i++) {
		const io = m.ios[i];
		if (io.stage == p.entry.stage && io.builtin == Builtin.None) {
			names.globals.push(p.ioNames[i]);
		}
	}
	for (const s of m.structs) {
		p.structNames.push("");
		p.structFields.push([]);
	}
	for (const c of m.constants) { p.constantNames.push(""); }
	for (const w of m.workgroups) { p.workgroupNames.push(""); }
	for (const f of m.functions) {
		p.functionNames.push("");
		p.paramNames.push([]);
		p.localNames.push([]);
	}
	for (const f of m.functions) {
		for (const l of f.locals) {
			const slot = l.type.kind == ShaderTypeKind.ExchangeResult ?
				exchangeSlot(l.type.scalar) : -1;
			if (slot < 0 || p.exchangeNames[slot] != "") { continue; }
			const suffix = slot == 0 ? "I32" : "U32";
			const scalar = scalarName(l.type.scalar);
			p.exchangeNames[slot] = nameStruct(names, "AtomicExchange" + suffix);
			p.exchangeMakers[slot] = nameFunction(names, "atomicExchangeResult" + suffix,
				"(" + scalar + ", " + scalar + ")");
		}
	}
	for (const d of m.declarations) {
		const i = d.index;
		if (d.kind == DeclarationKind.Struct) {
			const s = m.structs[i];
			p.structNames[i] = nameStruct(names, s.name);
			p.structFields[i] = fieldNames(names.reserved, s.members.map((f) => f.name));
			continue;
		}
		if (d.kind == DeclarationKind.Constant) {
			p.constantNames[i] = nameConstant(names, m.constants[i].name);
			continue;
		}
		if (d.kind == DeclarationKind.Workgroup) {
			p.workgroupNames[i] = nameConstant(names, m.workgroups[i].name);
			continue;
		}
		const f = m.functions[i];
		if (i == p.entry.functionIndex) {
			names.params = [];
			names.locals = [];
		} else {
			const types = "(" + f.params.map((a) => typeName(p, a.type)).join(", ") + ")";
			p.functionNames[i] = nameFunction(names, f.name, types);
			p.paramNames[i] = f.params.map((a) => nameParam(names, a.name));
		}
		p.localNames[i] = f.locals.map((l) => nameLocal(names, l.name));
	}
}

// One stage of a module, its first entry, as Vulkan-style GLSL 450 for sokol-shdc.
export function printGlsl450(m: ShaderModule): string {
	let p = new Glsl();
	p.module = m;
	p.entry = m.entries[0];
	let attributes: string[] = [];
	for (const io of m.ios) {
		if (io.stage == ShaderStage.Vertex && io.direction == IoDirection.In &&
			io.builtin == Builtin.None) {
			attributes.push(io.name);
		}
	}
	for (const io of m.ios) {
		p.ioNames.push(isVarying(io) ? suffixed(io.name, attributes) : io.name);
	}
	nameDeclarations(p);

	let out = "";
	if (p.entry.stage == ShaderStage.Compute) {
		const size = p.entry.workgroupSize;
		out += "layout(local_size_x=" + String(size[0]) + ", local_size_y=" + String(size[1]) +
			", local_size_z=" + String(size[2]) + ") in;\n";
	}
	for (const d of m.declarations) {
		if (d.kind != DeclarationKind.Struct) { continue; }
		const s = m.structs[d.index];
		out += "struct " + p.structNames[d.index] + " {\n";
		for (let f = 0; f < s.members.length; f++) {
			out += "    " + typeName(p, s.members[f].type) + " " + p.structFields[d.index][f] +
				";\n";
		}
		out += "};\n";
	}
	for (let slot = 0; slot < 2; slot++) {
		if (p.exchangeNames[slot] == "") { continue; }
		const t = p.exchangeNames[slot];
		const scalar = slot == 0 ? "int" : "uint";
		out += "struct " + t + " {\n    " + scalar + " old_value;\n    bool exchanged;\n};\n" + t +
			" " + p.exchangeMakers[slot] + "(" + scalar + " compare, " + scalar + " old) {\n" +
			"    return " + t + "(old, old == compare);\n}\n";
	}
	for (const r of m.resources) { out += gated(r.condition, resourceText(p, r)); }
	for (const direction of [IoDirection.In, IoDirection.Out]) {
		for (let i = 0; i < m.ios.length; i++) {
			const io = m.ios[i];
			if (io.stage == p.entry.stage && io.direction == direction &&
				io.builtin == Builtin.None) {
				out += gated(io.condition, ioText(p, i));
			}
		}
	}
	for (const d of m.declarations) {
		if (d.kind == DeclarationKind.Constant) {
			const c = m.constants[d.index];
			out += "const " + typeName(p, c.type) + " " + p.constantNames[d.index] + " = " +
				expr(p, c.value) + ";\n";
		}
		if (d.kind == DeclarationKind.Workgroup) {
			out += "shared " + typeName(p, m.workgroups[d.index].type) + " " +
				p.workgroupNames[d.index] + ";\n";
		}
		if (d.kind == DeclarationKind.Function && d.index != p.entry.functionIndex) {
			const f = m.functions[d.index];
			p.fn = d.index;
			let params: string[] = [];
			for (let a = 0; a < f.params.length; a++) {
				params.push(typeName(p, f.params[a].type) + " " + p.paramNames[d.index][a]);
			}
			out += gated(f.condition, typeName(p, f.result) + " " + p.functionNames[d.index] + "(" +
				params.join(", ") + ") {\n" + statements(p, f.body, "    ") + "}\n");
		}
	}
	p.fn = p.entry.functionIndex;
	out += "void main() {\n" + statements(p, m.functions[p.fn].body, "    ") + "}\n";
	return (p.samplerless ? "#extension GL_EXT_samplerless_texture_functions : require\n" : "") +
		out;
}
