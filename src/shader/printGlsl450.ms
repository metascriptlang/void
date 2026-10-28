import {
	Access,
	AssignOp,
	BinaryOp,
	Builtin,
	ConditionKind,
	DeclarationKind,
	ExprKind,
	FeatureCondition,
	Intrinsic,
	IoDirection,
	ResourceKind,
	SampleType,
	SamplerType,
	ScalarKind,
	ShaderEntry,
	ShaderExpr,
	ShaderField,
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
	hasOffset,
	sampleBase,
	isShift,
	isUniformLoad,
	sameShaderType,
	texelScalar,
	isDepthShape,
	isArrayTexture,
} from "./ir";
import { splitResults } from "./irWalk";
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
import {
	binaryOperator,
	exchangeSlot,
	glslAtomicName,
	glslBitcast,
	glslAccessWord,
	glslBits,
	glslFunctions,
	glslImageFormat,
	glslInterpolation,
	glslKeywords,
	glslMathName,
	glslSampling,
	glslSplitTypes,
	repeatedBitsOperand,
	splitHelperName,
	splitMember,
	splitStructName,
	scalarName,
	vectorPrefix,
} from "./spelling";

function glslReservedWords(): string[] {
	let words = glslKeywords().concat(glslFunctions());
	for (const word of ["sampler", "sampler3DRect", "subpassLoad"]) { words.push(word); }
	for (const prefix of ["h", "f"]) {
		for (let n = 2; n <= 4; n++) { words.push(prefix + "vec" + String(n)); }
	}
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
	splits: ShaderType[] = [];
	splitStructs: string[] = [];
	splitHelpers: string[] = [];
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

function broken(message: string): never {
	throw new Error("printGlsl450: " + message);
}

function splitAt(p: Glsl, t: ShaderType): int32 {
	const at = p.splits.findIndex((s) => sameShaderType(s, t)) as int32;
	if (at < 0) { broken("no struct is declared for a " + t.kind.toString()); }
	return at;
}

function typeName(p: Glsl, t: ShaderType): string {
	return match (t.kind) {
		ShaderTypeKind.Scalar => scalarName(t.scalar),
		ShaderTypeKind.Vector => vectorPrefix(t.scalar) + "vec" + String(t.rows),
		ShaderTypeKind.Matrix => t.columns == t.rows ? "mat" + String(t.columns) :
			"mat" + String(t.columns) + "x" + String(t.rows),
		ShaderTypeKind.Array => typeName(p, t.element[0]) + "[" + String(t.length) + "]",
		ShaderTypeKind.Struct => p.structNames[t.structIndex],
		ShaderTypeKind.Atomic => scalarName(t.scalar),
		ShaderTypeKind.ExchangeResult => p.exchangeNames[exchangeSlot(t.scalar)],
		ShaderTypeKind.ModfResult | ShaderTypeKind.FrexpResult => p.splitStructs[splitAt(p, t)],
		_ => { broken("a " + t.kind.toString() + " is no GLSL value type"); },
	};
}

function isTwoRowMatrix(t: ShaderType): boolean {
	return t.kind == ShaderTypeKind.Matrix && t.rows == 2;
}

function columnName(member: string, column: int32): string {
	return member + "_col" + String(column);
}

function blockMemberText(p: Glsl, e: ShaderExpr): string {
	const name = p.module.structs[p.module.resources[e.index].type.structIndex].members[e.member].name;
	if (!isTwoRowMatrix(e.type)) { return name; }
	let columns: string[] = [];
	for (let c: int32 = 0; c < e.type.columns; c++) { columns.push(columnName(name, c)); }
	return typeName(p, e.type) + "(" + columns.join(", ") + ")";
}

function blockMemberDeclarations(p: Glsl, f: ShaderField): string {
	if (!isTwoRowMatrix(f.type)) { return "    " + declared(p, f.type, f.name) + ";\n"; }
	let text = "";
	for (let c: int32 = 0; c < f.type.columns; c++) {
		text += "    vec2 " + columnName(f.name, c) + ";\n";
	}
	return text;
}

function splitField(e: ShaderExpr): boolean {
	const kind = e.operands[0].type.kind;
	return kind == ShaderTypeKind.ModfResult || kind == ShaderTypeKind.FrexpResult;
}

function atomicText(e: ShaderExpr, args: string[]): string {
	const unsigned = e.operands[0].type.scalar == ScalarKind.U32;
	const rest = match (e.intrinsic) {
		Intrinsic.AtomicLoad => unsigned ? "0u" : "0",
		Intrinsic.AtomicSub => "-(" + args[1] + ")",
		Intrinsic.AtomicStore | Intrinsic.AtomicAdd | Intrinsic.AtomicMax | Intrinsic.AtomicMin |
			Intrinsic.AtomicAnd | Intrinsic.AtomicOr | Intrinsic.AtomicXor |
			Intrinsic.AtomicExchange =>
			args.slice(1).join(", "),
		_ => { broken(e.intrinsic.toString() + " is no GLSL atomic expression"); },
	};
	return glslAtomicName(e.intrinsic) + "(" + args[0] + ", " + rest + ")";
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
	if (io.direction == IoDirection.Out) {
		if (io.builtin == Builtin.FragDepth) { return "gl_FragDepth"; }
		if (io.builtin != Builtin.Position) {
			broken("@builtin " + io.builtin.toString() + " has no GLSL output");
		}
		return "gl_Position";
	}
	return match (io.builtin) {
		Builtin.VertexIndex => "uint(gl_VertexIndex)",
		Builtin.InstanceIndex => "uint(gl_InstanceIndex)",
		Builtin.Position => "gl_FragCoord",
		Builtin.FrontFacing => "gl_FrontFacing",
		Builtin.PrimitiveIndex => "uint(gl_PrimitiveID)",
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
		if (e.unary == UnaryOp.Not && operand.type.kind == ShaderTypeKind.Vector &&
			operand.type.scalar == ScalarKind.Bool) {
			return "not(" + expr(p, operand) + ")";
		}
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
		ExprKind.BlockMember => blockMemberText(p, e),
		ExprKind.Call => p.functionNames[e.index] + listed(p, e.operands),
		ExprKind.Intrinsic => intrinsic(p, e),
		ExprKind.Construct => typeName(p, e.type) + listed(p, e.operands),
		ExprKind.Convert => e.type.kind == ShaderTypeKind.Scalar &&
			e.type.scalar == ScalarKind.U32 && e.operands[0].kind == ExprKind.Literal ?
			integerText(e.operands[0].value) + "u" :
			typeName(p, e.type) + "(" + value(p, e.operands[0]) + ")",
		ExprKind.Field => splitField(e) ? expr(p, e.operands[0]) + "." + splitMember(e.operands[0].type, e.index) :
			e.operands[0].type.kind == ShaderTypeKind.ExchangeResult ?
			expr(p, e.operands[0]) + (e.index == 0 ? ".old_value" : ".exchanged") :
			expr(p, e.operands[0]) + "." + p.structFields[e.operands[0].type.structIndex][e.index],
		ExprKind.Swizzle => expr(p, e.operands[0]) + "." + swizzle(e),
		ExprKind.Index => expr(p, e.operands[0]) + "[" + value(p, e.operands[1]) + "]",
	};
}

function intrinsicName(op: Intrinsic): string {
	return match (op) {
		Intrinsic.Saturate => "clamp",
		Intrinsic.Inverse => "inverse",
		Intrinsic.UpperLeft3x3 => "mat3",
		Intrinsic.Select => "mix",
		Intrinsic.TextureSample => "texture",
		Intrinsic.TextureLoad => "texelFetch",
		Intrinsic.TextureStore => "imageStore",
		Intrinsic.TextureDimensions => "textureSize",
		Intrinsic.TextureNumSamples => "textureSamples",
		Intrinsic.TextureSampleCompare => "texture",
		Intrinsic.TextureSampleCompareLevel | Intrinsic.TextureSampleLevel => "textureLod",
		Intrinsic.TextureSampleBias => "texture",
		Intrinsic.TextureSampleGrad => "textureGrad",
		Intrinsic.WorkgroupBarrier | Intrinsic.StorageBarrier => "barrier",
		Intrinsic.AtomicLoad | Intrinsic.AtomicStore | Intrinsic.AtomicAdd | Intrinsic.AtomicSub |
			Intrinsic.AtomicMax | Intrinsic.AtomicMin | Intrinsic.AtomicAnd | Intrinsic.AtomicOr |
			Intrinsic.AtomicXor | Intrinsic.AtomicExchange |
			Intrinsic.AtomicCompareExchangeWeak => glslAtomicName(op),
		_ => glslMathName(op),
	};
}

function callsFunction(e: ShaderExpr): boolean {
	return e.kind == ExprKind.Call || e.operands.some((o) => callsFunction(o));
}

function bitsText(p: Glsl, e: ShaderExpr, args: string[]): string {
	const at = repeatedBitsOperand(e.intrinsic);
	if (at >= 0 && callsFunction(e.operands[at])) {
		broken(e.intrinsic.toString() + " prints its offset twice, and the offset calls a function");
	}
	return glslBits(e.intrinsic, args, typeName(p, e.type), e.type.scalar == ScalarKind.U32);
}

function intrinsic(p: Glsl, e: ShaderExpr): string {
	const args = e.operands.map((a) => expr(p, a));
	const all = "(" + args.join(", ") + ")";
	const texture = e.operands.length > 0 ? e.operands[0].type : new ShaderType();
	const layered = texture.kind == ShaderTypeKind.Texture && isArrayTexture(texture);
	const cube = texture.kind == ShaderTypeKind.Texture &&
		(texture.shape == TextureShape.Cube || texture.shape == TextureShape.DepthCube);
	const isTexture = texture.kind == ShaderTypeKind.Texture;
	const shape = isTexture && texture.scalar == ScalarKind.U32 ? "usampler2D(" :
		isTexture && texture.scalar == ScalarKind.I32 ? "isampler2D(" :
		isTexture && texture.shape == TextureShape.D3 ? "sampler3D(" :
		isTexture && texture.shape == TextureShape.D1 ? "sampler1D(" :
		layered ? "sampler2DArray(" : cube ? "samplerCube(" : "sampler2D(";
	const sampled = args.length >= 2 ? shape + args[0] + ", " + args[1] + ")" : "";
	return match (e.intrinsic) {
		Intrinsic.CountOneBits | Intrinsic.FirstLeadingBit | Intrinsic.FirstTrailingBit |
			Intrinsic.CountLeadingZeros | Intrinsic.CountTrailingZeros | Intrinsic.ExtractBits |
			Intrinsic.InsertBits => bitsText(p, e, args),
		Intrinsic.Bitcast => glslBitcast(e.operands[0].type.scalar, e.type.scalar,
			typeName(p, e.type), args[0]),
		Intrinsic.Saturate => "clamp(" + args[0] + ", 0.0, 1.0)",
		Intrinsic.Modf | Intrinsic.Frexp => p.splitHelpers[splitAt(p, e.type)] + all,
		Intrinsic.Select => e.operands[2].type.kind == ShaderTypeKind.Vector ? "mix" + all :
			"(" + args[2] + " ? " + args[1] + " : " + args[0] + ")",
		Intrinsic.TextureDimensions | Intrinsic.TextureLoad | Intrinsic.TextureNumSamples =>
			fetched(p, e, args),
		Intrinsic.TextureStore => "imageStore(" + args[0] + ", " + imageAt(e, args) + ", " +
			args[args.length - 1] + ")",
		Intrinsic.TextureSample => "texture" + offsetSuffix(e) + "(" + sampled + ", " +
			(layered ? "vec3(" + args[2] + ", float(" + args[3] + "))" : args[2]) +
			offsetTail(e, args) + ")",
		Intrinsic.TextureSampleCompare | Intrinsic.TextureSampleCompareLevel => compared(e, args),
		Intrinsic.TextureSampleLevel | Intrinsic.TextureSampleBias | Intrinsic.TextureSampleGrad =>
			intrinsicName(e.intrinsic) + offsetSuffix(e) + "(" + sampled + ", " + (layered ?
				"vec3(" + args[2] + ", float(" + args[3] + "))" : args[2]) + ", " +
				explicitTail(e, args, layered ? 4 : 3) + ")" +
				(isDepthShape(texture.shape) ? ".x" : ""),
		// A compute barrier() carries workgroup-memory semantics, while the OpMemoryBarrier
		// of memoryBarrierShared() is refused by a WGSL reader (measured).
		Intrinsic.WorkgroupBarrier => "barrier()",
		Intrinsic.StorageBarrier => "memoryBarrierBuffer(); barrier()",
		Intrinsic.TextureBarrier => "memoryBarrierImage(); barrier()",
		Intrinsic.WorkgroupUniformLoad => args[0],
		Intrinsic.ArrayLength => e.type.scalar == ScalarKind.I32 ? args[0] + ".length()" :
			typeName(p, e.type) + "(" + args[0] + ".length())",
		Intrinsic.AtomicCompareExchangeWeak => {
			broken("AtomicCompareExchangeWeak outside a local's initializer or a statement of " +
				"its own: atomicCompSwap returns only the old value");
		},
		_ => isAtomic(e.intrinsic) ? atomicText(e, args) : intrinsicName(e.intrinsic) + all,
	};
}

function offsetSuffix(e: ShaderExpr): string {
	return hasOffset(e) ? "Offset" : "";
}

function offsetTail(e: ShaderExpr, args: string[]): string {
	return hasOffset(e) ? ", " + args[sampleBase(e)] : "";
}

// A depth texture's level is an integer, and textureLod takes a float. GLSL puts the offset
// before the bias and after the level and the derivatives.
function explicitTail(e: ShaderExpr, args: string[], from: int32): string {
	const rest = args.slice(from, sampleBase(e)).map((a, i) => {
		const t = e.operands[from + i].type;
		return t.kind == ShaderTypeKind.Scalar && t.scalar != ScalarKind.F32 ? "float(" + a + ")" : a;
	}).join(", ");
	if (!hasOffset(e)) { return rest; }
	const offset = args[sampleBase(e)];
	return e.intrinsic == Intrinsic.TextureSampleBias ? offset + ", " + rest : rest + ", " + offset;
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
	if (e.intrinsic == Intrinsic.TextureNumSamples) { return "textureSamples(" + args[0] + ")"; }
	if (e.intrinsic == Intrinsic.TextureDimensions) {
		return "textureSize(" + args.join(", ") + ")";
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
	return vectorPrefix(texelScalar(t.format)) + match (t.shape) {
		TextureShape.D2Array => "image2DArray",
		TextureShape.D3 => "image3D",
		TextureShape.D2 => "image2D",
		TextureShape.D1 => "image1D",
		_ => { broken("a storage texture of shape " + t.shape.toString()); },
	};
}

function compared(e: ShaderExpr, args: string[]): string {
	const level = e.intrinsic == Intrinsic.TextureSampleCompareLevel;
	const layered = e.operands[0].type.shape == TextureShape.Depth2dArray;
	const coords = args[2] + (layered ? ", float(" + args[3] + ")" : "") + ", " +
		args[sampleBase(e) - 1];
	const pair = "(" + args[0] + ", " + args[1] + ")";
	const suffix = offsetSuffix(e);
	const offset = offsetTail(e, args);
	return match (e.operands[0].type.shape) {
		TextureShape.Depth2dArray => level ? "textureGrad" + suffix + "(sampler2DArrayShadow" +
			pair + ", vec4(" + coords + "), vec2(0.0), vec2(0.0)" + offset + ")" :
			"texture" + suffix + "(sampler2DArrayShadow" + pair + ", vec4(" + coords + ")" +
				offset + ")",
		TextureShape.DepthCube => level ? "textureGrad(samplerCubeShadow" + pair + ", vec4(" +
			coords + "), vec3(0.0), vec3(0.0))" :
			"texture(samplerCubeShadow" + pair + ", vec4(" + coords + "))",
		TextureShape.Depth2d => level ? "textureLod" + suffix + "(sampler2DShadow" + pair +
			", vec3(" + coords + "), 0.0" + offset + ")" :
			"texture" + suffix + "(sampler2DShadow" + pair + ", vec3(" + coords + ")" + offset + ")",
		_ => {
			broken("a depth compare of a " + e.operands[0].type.shape.toString() + " texture");
		},
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
			AssignOp.Set => "=",
			_ => { broken(s.assign.toString() + " is no compound assignment"); },
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
	if (s.kind == StmtKind.Let && isUniformLoad(s.expr)) {
		return indent + "barrier();\n" + indent + simple(p, s) + ";\n" + indent + "barrier();\n";
	}
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
	if (f == TexelFormat.Bgra8unorm) { broken("bgra8unorm has no GLSL image format"); }
	return glslImageFormat(f);
}

function sampleTag(r: ShaderResource): string {
	return r.sampleType == SampleType.Float ? "" : "@image_sample_type " + r.name + " " +
		sampleTypeName(r.sampleType) + "\n";
}

function resourceText(p: Glsl, r: ShaderResource): string {
	const at = "layout(binding=" + String(r.binding) + ")";
	const slot = at + " uniform ";
	return match (r.kind) {
		ResourceKind.UniformBlock => slot + r.name + " {\n" +
			p.module.structs[r.type.structIndex].members.map((f) =>
				blockMemberDeclarations(p, f)).join("") + "};\n",
		ResourceKind.Texture => match (r.type.shape) {
			TextureShape.D2Array => sampleTag(r) + slot + vectorPrefix(r.type.scalar) +
				"texture2DArray " + r.name + ";\n",
			TextureShape.Cube => sampleTag(r) + slot + "textureCube " + r.name + ";\n",
			TextureShape.Depth2dArray | TextureShape.DepthCube =>
				"@image_sample_type " + r.name + " depth\n" + slot + (r.type.shape ==
					TextureShape.DepthCube ? "textureCube " : "texture2DArray ") + r.name + ";\n",
			TextureShape.D3 => sampleTag(r) + slot + vectorPrefix(r.type.scalar) + "texture3D " +
				r.name + ";\n",
			TextureShape.D1 => sampleTag(r) + slot + "texture1D " + r.name + ";\n",
			TextureShape.Multisampled2d => sampleTag(r) + slot + "texture2DMS " + r.name + ";\n",
			TextureShape.D2 | TextureShape.Depth2d => sampleTag(r) + slot +
				vectorPrefix(r.type.scalar) + "texture2D " + r.name + ";\n",
			_ => { broken(r.name + " is a " + r.type.shape.toString() + " texture, no GLSL 450"); },
		},
		ResourceKind.Sampler => (r.samplerType == SamplerType.Filtering ? "" : "@sampler_type " +
			r.name + " " + samplerTypeName(r.samplerType) + "\n") + slot + "sampler " + r.name +
			";\n",
		ResourceKind.StorageBuffer => at + " " + (r.access == Access.ReadWrite ? "" : "readonly ") +
			"buffer " + r.name + "Buffer {\n    " + typeName(p, r.type.element[0]) + " " + r.name +
			"[];\n};\n",
		ResourceKind.StorageTexture => "layout(binding=" + String(r.binding) + ", " +
			formatName(r.type.format) + ") uniform " + glslAccessWord(r.type.access) +
			imageName(r.type) + " " + r.name + ";\n",
	};
}

function ioText(p: Glsl, index: int32): string {
	const io = p.module.ios[index];
	const spelled = declared(p, io.type, p.ioNames[index]);
	if (io.direction == IoDirection.Out && io.stage == ShaderStage.Fragment) {
		return "layout(location=" + String(io.location) + ") out " + spelled + ";\n";
	}
	return glslInterpolation(io.interpolation) + glslSampling(io.sampling) + (io.direction == IoDirection.In ? "in " : "out ") + spelled + ";\n";
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
	for (const r of m.resources) {
		if (r.kind != ResourceKind.UniformBlock) { continue; }
		for (const f of m.structs[r.type.structIndex].members) {
			if (!isTwoRowMatrix(f.type)) { continue; }
			for (let c: int32 = 0; c < f.type.columns; c++) {
				const column = columnName(f.name, c);
				if (names.globals.includes(column)) {
					broken("the column " + column + " of uniform member " + f.name +
						" is also the name of a member or resource");
				}
				names.globals.push(column);
			}
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
	for (const t of splitResults(m, m.functions.map((f, i) => i as int32))) {
		const argType = glslSplitTypes(t)[0];
		p.splits.push(t);
		p.splitStructs.push(nameStruct(names, splitStructName(t)));
		p.splitHelpers.push(nameFunction(names, splitHelperName(t), "(" + argType + ")"));
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
	for (let i = 0; i < p.splits.length; i++) {
		const t = p.splits[i];
		const [argType, otherType] = glslSplitTypes(t);
		const call = t.kind == ShaderTypeKind.ModfResult ? "modf" : "frexp";
		out += "struct " + p.splitStructs[i] + " {\n    " + argType + " " + splitMember(t, 0) + ";\n    " +
			otherType + " " + splitMember(t, 1) + ";\n};\n" + p.splitStructs[i] + " " +
			p.splitHelpers[i] + "(" + argType + " arg) {\n    " + otherType + " other;\n    " +
			argType + " part = " + call + "(arg, other);\n    return " + p.splitStructs[i] +
			"(part, other);\n}\n";
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
