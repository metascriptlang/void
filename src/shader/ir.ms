export enum ScalarKind {
	F32,
	I32,
	U32,
	Bool,
}

export enum ShaderTypeKind {
	Void,
	Scalar,
	Vector,
	Matrix,
	Array,
	RuntimeArray,
	Struct,
	Texture,
	Sampler,
	StorageTexture,
	Atomic,
	ExchangeResult,
	ModfResult,
	FrexpResult,
}

export enum TextureShape {
	D2,
	D2Array,
	D3,
	Cube,
	CubeArray,
	Depth2d,
	Depth2dArray,
	DepthCube,
	Multisampled2d,
	D1,
}

export enum TexelFormat {
	Rgba8unorm,
	Rgba8snorm,
	Rgba8uint,
	Rgba16float,
	Rgba32float,
	R32float,
	R32uint,
	Rg32float,
	Rgba8sint,
	Rgba16uint,
	Rgba16sint,
	R32sint,
	Rg32uint,
	Rg32sint,
	Rgba32uint,
	Rgba32sint,
	Bgra8unorm,
}

// The scalar of a storage texel: WGSL's texel format table gives each format the channel type
// textureLoad returns and textureStore takes, a vec4 of it.
export function texelScalar(format: TexelFormat): ScalarKind {
	if (format == TexelFormat.Rgba8uint || format == TexelFormat.Rgba16uint ||
		format == TexelFormat.R32uint || format == TexelFormat.Rg32uint ||
		format == TexelFormat.Rgba32uint) {
		return ScalarKind.U32;
	}
	if (format == TexelFormat.Rgba8sint || format == TexelFormat.Rgba16sint ||
		format == TexelFormat.R32sint || format == TexelFormat.Rg32sint ||
		format == TexelFormat.Rgba32sint) {
		return ScalarKind.I32;
	}
	if (format == TexelFormat.Rgba8unorm || format == TexelFormat.Rgba8snorm ||
		format == TexelFormat.Rgba16float || format == TexelFormat.Rgba32float ||
		format == TexelFormat.R32float || format == TexelFormat.Rg32float ||
		format == TexelFormat.Bgra8unorm) {
		return ScalarKind.F32;
	}
	throw new Error("texelScalar: a texel format with no channel type");
}

export enum Access {
	Read,
	Write,
	ReadWrite,
}

export class ShaderType {
	kind: ShaderTypeKind = ShaderTypeKind.Void;
	scalar: ScalarKind = ScalarKind.F32;
	rows: int32 = 1;
	columns: int32 = 1;
	length: int32 = 0;
	element: ShaderType[] = [];
	structIndex: int32 = -1;
	shape: TextureShape = TextureShape.D2;
	format: TexelFormat = TexelFormat.Rgba8unorm;
	access: Access = Access.Read;
}

export enum ConditionKind {
	Always,
	Feature,
	Not,
	All,
	Any,
}

export class FeatureCondition {
	kind: ConditionKind = ConditionKind.Always;
	feature: string = "";
	operands: FeatureCondition[] = [];
}

export enum ExprKind {
	Literal,
	Local,
	Param,
	Constant,
	Io,
	Resource,
	BlockMember,
	Unary,
	Binary,
	Conditional,
	Call,
	Intrinsic,
	Construct,
	Convert,
	Field,
	Swizzle,
	Index,
	Workgroup,
}

export enum UnaryOp {
	Negate,
	Not,
}

export enum BinaryOp {
	Add,
	Sub,
	Mul,
	Div,
	Mod,
	BitAnd,
	BitOr,
	BitXor,
	ShiftLeft,
	ShiftRight,
	LogicalAnd,
	LogicalOr,
	Equal,
	NotEqual,
	Less,
	LessEqual,
	Greater,
	GreaterEqual,
}

export function isShift(op: BinaryOp): boolean {
	return op == BinaryOp.ShiftLeft || op == BinaryOp.ShiftRight;
}

export enum Intrinsic {
	Abs,
	Sign,
	Floor,
	Ceil,
	Trunc,
	Round,
	Fract,
	Sqrt,
	InverseSqrt,
	Exp,
	Exp2,
	Log,
	Log2,
	Pow,
	Sin,
	Cos,
	Tan,
	Asin,
	Acos,
	Atan,
	Atan2,
	Sinh,
	Cosh,
	Tanh,
	Asinh,
	Acosh,
	Atanh,
	Ldexp,
	Modf,
	Frexp,
	Degrees,
	Radians,
	Min,
	Max,
	Clamp,
	Saturate,
	Mix,
	Step,
	Smoothstep,
	Fma,
	Dot,
	Cross,
	Length,
	Distance,
	Normalize,
	Reflect,
	Refract,
	FaceForward,
	Transpose,
	Determinant,
	Inverse,
	UpperLeft3x3,
	Select,
	LessThan,
	LessThanEqual,
	GreaterThan,
	GreaterThanEqual,
	Equal,
	NotEqual,
	Any,
	All,
	Dpdx,
	Dpdy,
	Fwidth,
	DpdxCoarse,
	DpdxFine,
	DpdyCoarse,
	DpdyFine,
	FwidthCoarse,
	FwidthFine,
	Bitcast,
	CountOneBits,
	ReverseBits,
	FirstLeadingBit,
	FirstTrailingBit,
	CountLeadingZeros,
	CountTrailingZeros,
	ExtractBits,
	InsertBits,
	Pack4x8Unorm,
	Pack4x8Snorm,
	Pack2x16Unorm,
	Pack2x16Snorm,
	Pack2x16Float,
	Unpack4x8Unorm,
	Unpack4x8Snorm,
	Unpack2x16Unorm,
	Unpack2x16Snorm,
	Unpack2x16Float,
	TextureSample,
	TextureLoad,
	TextureStore,
	TextureDimensions,
	TextureSampleCompare,
	TextureSampleCompareLevel,
	WorkgroupBarrier,
	StorageBarrier,
	AtomicLoad,
	AtomicStore,
	AtomicAdd,
	AtomicSub,
	AtomicMax,
	AtomicMin,
	AtomicAnd,
	AtomicOr,
	AtomicXor,
	AtomicExchange,
	AtomicCompareExchangeWeak,
	TextureSampleLevel,
	TextureSampleBias,
	TextureSampleGrad,
	TextureNumSamples,
	ArrayLength,
	WorkgroupUniformLoad,
	TextureBarrier,
}

function isExplicitSample(op: Intrinsic): boolean {
	return op == Intrinsic.TextureSampleLevel || op == Intrinsic.TextureSampleBias ||
		op == Intrinsic.TextureSampleGrad;
}

export function isSampling(op: Intrinsic): boolean {
	return isExplicitSample(op) || op == Intrinsic.TextureSample ||
		op == Intrinsic.TextureSampleCompare || op == Intrinsic.TextureSampleCompareLevel;
}

export function isComparisonSampler(m: ShaderModule, sampler: ShaderExpr): boolean {
	return sampler.kind == ExprKind.Resource &&
		m.resources[sampler.index].samplerType == SamplerType.Comparison;
}

export function isDepthShape(shape: TextureShape): boolean {
	return shape == TextureShape.Depth2d || shape == TextureShape.Depth2dArray ||
		shape == TextureShape.DepthCube;
}

export function isArrayTexture(t: ShaderType): boolean {
	return t.shape == TextureShape.D2Array || t.shape == TextureShape.CubeArray ||
		t.shape == TextureShape.Depth2dArray;
}

// The operands of a sample before its constant offset: texture, sampler, coordinates, the layer
// of an array, then the level, bias, reference or two derivatives.
export function sampleBase(e: ShaderExpr): int32 {
	let tail = 1;
	if (e.intrinsic == Intrinsic.TextureSample) { tail = 0; }
	if (e.intrinsic == Intrinsic.TextureSampleGrad) { tail = 2; }
	return 3 + (isArrayTexture(e.operands[0].type) ? 1 : 0) + tail;
}

export function hasOffset(e: ShaderExpr): boolean {
	return isSampling(e.intrinsic) && e.operands.length > 0 &&
		e.operands.length == sampleBase(e) + 1;
}

export function offsetOf(e: ShaderExpr): ShaderExpr {
	return e.operands[sampleBase(e)];
}

export function offsetRows(shape: TextureShape): int32 {
	if (shape == TextureShape.D3) { return 3; }
	const plane = shape == TextureShape.D2 || shape == TextureShape.D2Array ||
		shape == TextureShape.Depth2d || shape == TextureShape.Depth2dArray;
	return plane ? 2 : 0;
}

export const OFFSET_MIN = -8;
export const OFFSET_MAX = 7;

// The texel offsets of a constant vector of i32 literals, or none when it is anything else.
export function offsetParts(e: ShaderExpr): float64[] {
	let parts: float64[] = [];
	if (e.kind != ExprKind.Construct || e.type.kind != ShaderTypeKind.Vector ||
		e.type.scalar != ScalarKind.I32 || e.operands.length != e.type.rows) {
		return parts;
	}
	for (const o of e.operands) {
		if (o.kind != ExprKind.Literal || o.type.kind != ShaderTypeKind.Scalar ||
			o.type.scalar != ScalarKind.I32) {
			return [];
		}
		parts.push(o.value);
	}
	return parts;
}

function offsetError(e: ShaderExpr): string {
	const name = e.intrinsic.toString();
	const o = e.operands;
	if (o.length == 0 || o[0].type.kind != ShaderTypeKind.Texture) { return ""; }
	const base = sampleBase(e);
	if (o.length <= base) { return ""; }
	const shape = o[0].type.shape;
	if (o.length > base + 1) { return name + " takes one constant offset, last, as WGSL's"; }
	const rows = offsetRows(shape);
	if (rows == 0) {
		return name + " takes no offset on a " + shape.toString() + " texture, as WGSL's";
	}
	const type = o[base].type;
	if (type.kind != ShaderTypeKind.Vector || type.scalar != ScalarKind.I32 || type.rows != rows) {
		return name + " takes a constant offset of " + String(rows) + " i32 for a " +
			shape.toString() + " texture, as WGSL's";
	}
	const parts = offsetParts(o[base]);
	let inRange = parts.length == rows;
	for (const part of parts) {
		if (part < OFFSET_MIN || part > OFFSET_MAX) { inRange = false; }
	}
	return inRange ? "" : name + " takes a constant offset in [-8, 7], as WGSL's";
}

function multisampleError(e: ShaderExpr): string {
	const name = e.intrinsic.toString();
	const o = e.operands;
	const multisampled = o.length > 0 && o[0].type.kind == ShaderTypeKind.Texture &&
		o[0].type.shape == TextureShape.Multisampled2d;
	if (e.intrinsic == Intrinsic.TextureNumSamples) {
		return o.length == 1 && multisampled ? "" :
			name + " takes one multisampled texture, as WGSL's";
	}
	if (!multisampled) { return ""; }
	if (e.intrinsic == Intrinsic.TextureDimensions && o.length != 1) {
		return name + " of a multisampled texture takes no level, as WGSL's";
	}
	if (e.intrinsic == Intrinsic.TextureLoad &&
		(o.length != 3 || o[2].type.kind != ShaderTypeKind.Scalar ||
		o[2].type.scalar != ScalarKind.I32 && o[2].type.scalar != ScalarKind.U32)) {
		return name + " of a multisampled texture takes coordinates and an i32 or u32 sample " +
			"index, as WGSL's";
	}
	return "";
}

function storageTexelError(e: ShaderExpr): string {
	const o = e.operands;
	if (o.length == 0 || o[0].type.kind != ShaderTypeKind.StorageTexture) { return ""; }
	const texel = e.intrinsic == Intrinsic.TextureStore ? o[o.length - 1].type : e.type;
	const wanted = texelScalar(o[0].type.format);
	if (texel.kind == ShaderTypeKind.Vector && texel.rows == 4 && texel.scalar == wanted) {
		return "";
	}
	return e.intrinsic.toString() + " of a " + o[0].type.format.toString() +
		" storage texture takes a vec4 of " + wanted.toString() + ", as WGSL's";
}

function arrayLengthError(m: ShaderModule, e: ShaderExpr): string {
	const o = e.operands;
	const buffer = o.length == 1 && o[0].kind == ExprKind.Resource && o[0].index >= 0 &&
		o[0].index < m.resources.length &&
		m.resources[o[0].index].kind == ResourceKind.StorageBuffer;
	if (!buffer) {
		return "ArrayLength takes one storage buffer, as WGSL's takes a runtime-sized array";
	}
	const count = e.type.kind == ShaderTypeKind.Scalar &&
		(e.type.scalar == ScalarKind.U32 || e.type.scalar == ScalarKind.I32);
	return count ? "" : "ArrayLength gives a u32 or an i32 count";
}

export function isUniformLoad(e: ShaderExpr): boolean {
	return e.kind == ExprKind.Intrinsic && e.intrinsic == Intrinsic.WorkgroupUniformLoad;
}

function uniformLoadError(e: ShaderExpr): string {
	const o = e.operands;
	if (o.length != 1 || rootOf(o[0]).kind != ExprKind.Workgroup) {
		return "WorkgroupUniformLoad takes a workgroup variable, as WGSL's takes a " +
			"ptr<workgroup, T>";
	}
	const plain = o[0].type.kind == ShaderTypeKind.Scalar ||
		o[0].type.kind == ShaderTypeKind.Vector;
	return plain && e.type.kind == o[0].type.kind && e.type.scalar == o[0].type.scalar ? "" :
		"WorkgroupUniformLoad loads a scalar or a vector";
}

function explicitSampleError(e: ShaderExpr): string {
	const name = e.intrinsic.toString();
	const o = e.operands;
	if (o.length < 3 || o[0].type.kind != ShaderTypeKind.Texture ||
		o[1].type.kind != ShaderTypeKind.Sampler) {
		return name + " takes a texture, a sampler and coordinates first";
	}
	const t = o[0].type;
	if (t.shape == TextureShape.D1 && e.intrinsic != Intrinsic.TextureSampleLevel) {
		return name + " of a D1 texture: WGSL samples it with textureSample and " +
			"textureSampleLevel only";
	}
	const color = t.shape == TextureShape.D2 || t.shape == TextureShape.D2Array ||
		t.shape == TextureShape.D1 || t.shape == TextureShape.D3 || t.shape == TextureShape.Cube ||
		t.shape == TextureShape.CubeArray;
	const depth = t.shape == TextureShape.Depth2d || t.shape == TextureShape.Depth2dArray ||
		t.shape == TextureShape.DepthCube;
	const depthLevel = depth && e.intrinsic == Intrinsic.TextureSampleLevel;
	if (!depthLevel && (!color || t.scalar != ScalarKind.F32)) {
		return name + " of a " + t.shape.toString() + " texture of " + t.scalar.toString() +
			": it samples a float color texture here";
	}
	const tail = e.intrinsic == Intrinsic.TextureSampleGrad ? 2 : 1;
	const base = 3 + (isArrayTexture(t) ? 1 : 0) + tail;
	if (o.length != base && o.length != base + 1) {
		return name + " takes a texture, a sampler, coordinates, a layer of an array, and " +
			(tail == 2 ? "two derivatives" : "a level or bias") + ", as WGSL's";
	}
	const level = o[base - 1].type;
	if (depthLevel && (level.kind != ShaderTypeKind.Scalar ||
		level.scalar != ScalarKind.I32 && level.scalar != ScalarKind.U32)) {
		return name + " of a " + t.shape.toString() +
			" texture takes an i32 or u32 level, as WGSL's";
	}
	return "";
}

function sampleError(m: ShaderModule, e: ShaderExpr): string {
	const name = e.intrinsic.toString();
	const o = e.operands;
	const typed = o.length >= 2 && o[0].type.kind == ShaderTypeKind.Texture &&
		o[1].type.kind == ShaderTypeKind.Sampler;
	if (isExplicitSample(e.intrinsic)) {
		return typed && isComparisonSampler(m, o[1]) ?
			name + " through a comparison sampler, which needs a depth reference" : "";
	}
	const compare = e.intrinsic != Intrinsic.TextureSample;
	const base = typed ? sampleBase(e) : 0;
	if (!typed || o.length != base && o.length != base + 1) {
		return compare ? name +
			" takes a texture, a sampler, coordinates, for an array texture a " +
			"layer, a depth reference, and an optional constant offset" :
			name + " takes a texture, a sampler, coordinates and, for an array texture, a layer, " +
			"and an optional constant offset";
	}
	if (compare) {
		if (!isComparisonSampler(m, o[1])) {
			return name + " through a sampler that is no comparison sampler binding";
		}
		return isDepthShape(o[0].type.shape) ? "" :
			name + " of a " + o[0].type.shape.toString() + " texture, which holds no depth";
	}
	if (o[0].type.shape == TextureShape.Multisampled2d) {
		return name + " of a multisampled texture";
	}
	return isComparisonSampler(m, o[1]) ?
		name + " through a comparison sampler, which needs a depth reference" : "";
}

export function isBitsOp(op: Intrinsic): boolean {
	const at = op as int32;
	return at >= (Intrinsic.CountOneBits as int32) && at <= (Intrinsic.Unpack2x16Float as int32);
}

function isBitsOnIntegers(op: Intrinsic): boolean {
	return (op as int32) <= (Intrinsic.InsertBits as int32);
}

function bitsOperands(e: ShaderExpr): ShaderType[] {
	const x = e.operands.length > 0 ? e.operands[0].type : new ShaderType();
	const u = scalarType(ScalarKind.U32);
	return match (e.intrinsic) {
		Intrinsic.ExtractBits => [x, u, u],
		Intrinsic.InsertBits => [x, x, u, u],
		Intrinsic.Pack4x8Unorm | Intrinsic.Pack4x8Snorm => [vectorType(ScalarKind.F32, 4)],
		Intrinsic.Pack2x16Unorm | Intrinsic.Pack2x16Snorm | Intrinsic.Pack2x16Float =>
			[vectorType(ScalarKind.F32, 2)],
		Intrinsic.Unpack4x8Unorm | Intrinsic.Unpack4x8Snorm | Intrinsic.Unpack2x16Unorm |
			Intrinsic.Unpack2x16Snorm | Intrinsic.Unpack2x16Float => [u],
		_ => [x],
	};
}

function bitsResult(e: ShaderExpr): ShaderType {
	return match (e.intrinsic) {
		Intrinsic.Pack4x8Unorm | Intrinsic.Pack4x8Snorm | Intrinsic.Pack2x16Unorm |
			Intrinsic.Pack2x16Snorm | Intrinsic.Pack2x16Float => scalarType(ScalarKind.U32),
		Intrinsic.Unpack4x8Unorm | Intrinsic.Unpack4x8Snorm => vectorType(ScalarKind.F32, 4),
		Intrinsic.Unpack2x16Unorm | Intrinsic.Unpack2x16Snorm | Intrinsic.Unpack2x16Float =>
			vectorType(ScalarKind.F32, 2),
		_ => bitsOperands(e)[0],
	};
}

function bitsError(e: ShaderExpr): string {
	const name = e.intrinsic.toString();
	const want = bitsOperands(e);
	if (e.operands.length != want.length) {
		return name + " takes " + String(want.length) + " operands, as WGSL's";
	}
	for (let i = 0; i < want.length; i++) {
		if (!sameShaderType(e.operands[i].type, want[i])) {
			return name + ": operand " + String(i) + " is not the type WGSL's takes";
		}
	}
	if (isBitsOnIntegers(e.intrinsic) && !isIntegral(want[0])) {
		return name + " takes an i32 or u32 scalar or vector, as WGSL's";
	}
	if (!sameShaderType(e.type, bitsResult(e))) {
		return name + " returns another type than WGSL's";
	}
	return "";
}

function isNumericShape(t: ShaderType): boolean {
	return (t.kind == ShaderTypeKind.Scalar || t.kind == ShaderTypeKind.Vector) &&
		t.scalar != ScalarKind.Bool;
}

function sameShape(a: ShaderType, b: ShaderType): boolean {
	return a.kind == b.kind && (a.kind == ShaderTypeKind.Scalar || a.rows == b.rows);
}

function isMixedMath(op: Intrinsic): boolean {
	return op == Intrinsic.Bitcast || op == Intrinsic.Ldexp;
}

// Bitcast keeps its operand's shape and changes its scalar; ldexp scales an f32 shape by an i32
// one.
function mixedMathError(e: ShaderExpr): string {
	const name = e.intrinsic.toString();
	const o = e.operands;
	const first = o.length > 0 ? o[0].type : new ShaderType();
	if (e.intrinsic == Intrinsic.Bitcast) {
		if (o.length != 1 || !isNumericShape(first) || !isNumericShape(e.type) ||
			!sameShape(first, e.type) || first.scalar == e.type.scalar) {
			return name +
				" takes one i32, u32 or f32 scalar or vector and answers the same shape " +
				"of another scalar";
		}
		return "";
	}
	if (o.length != 2 || !isNumericShape(first) || first.scalar != ScalarKind.F32 ||
		!isNumericShape(o[1].type) || o[1].type.scalar != ScalarKind.I32 ||
		!sameShape(first, o[1].type) || !sameShaderType(e.type, first)) {
		return name + " takes an f32 scalar or vector and an i32 of its shape, as WGSL's";
	}
	return "";
}

// modf and frexp take an f32 scalar or vector and answer the predeclared result of its width.
function splitError(e: ShaderExpr): string {
	const name = e.intrinsic.toString();
	const o = e.operands;
	const want = e.intrinsic == Intrinsic.Modf ?
		ShaderTypeKind.ModfResult : ShaderTypeKind.FrexpResult;
	if (o.length != 1 || !isNumericShape(o[0].type) || o[0].type.scalar != ScalarKind.F32 ||
		e.type.kind != want || e.type.rows != o[0].type.rows) {
		return name + " takes an f32 scalar or vector and answers the predeclared result of its " +
			"width, as WGSL's";
	}
	return "";
}

export function isAtomic(op: Intrinsic): boolean {
	return match (op) {
		Intrinsic.AtomicLoad | Intrinsic.AtomicStore | Intrinsic.AtomicAdd | Intrinsic.AtomicSub |
		Intrinsic.AtomicMax | Intrinsic.AtomicMin | Intrinsic.AtomicAnd | Intrinsic.AtomicOr |
		Intrinsic.AtomicXor | Intrinsic.AtomicExchange |
		Intrinsic.AtomicCompareExchangeWeak => true,
		_ => false,
	};
}

export function isEffect(op: Intrinsic): boolean {
	return op == Intrinsic.TextureStore || op == Intrinsic.WorkgroupBarrier ||
		op == Intrinsic.StorageBarrier || op == Intrinsic.TextureBarrier ||
		op == Intrinsic.WorkgroupUniformLoad || isAtomic(op) && op != Intrinsic.AtomicLoad;
}

export class ShaderExpr {
	kind: ExprKind = ExprKind.Literal;
	type: ShaderType = new ShaderType();
	value: float64 = 0.0;
	index: int32 = -1;
	member: int32 = -1;
	unary: UnaryOp = UnaryOp.Negate;
	binary: BinaryOp = BinaryOp.Add;
	intrinsic: Intrinsic = Intrinsic.Abs;
	components: int32[] = [];
	rgba: boolean = false;
	operands: ShaderExpr[] = [];
}

export enum StmtKind {
	Block,
	Let,
	Assign,
	Call,
	If,
	FeatureIf,
	While,
	For,
	Switch,
	Break,
	Continue,
	Return,
	Discard,
}

export enum AssignOp {
	Set,
	Add,
	Sub,
	Mul,
	Div,
	Mod,
	Increment,
	Decrement,
}

export class ShaderCase {
	labels: ShaderExpr[] = [];
	isDefault: boolean = false;
	body: ShaderStmt[] = [];
}

export class ShaderStmt {
	kind: StmtKind = StmtKind.Block;
	local: int32 = -1;
	assign: AssignOp = AssignOp.Set;
	target: ShaderExpr = new ShaderExpr();
	expr: ShaderExpr = new ShaderExpr();
	condition: FeatureCondition = new FeatureCondition();
	init: ShaderStmt[] = [];
	update: ShaderStmt[] = [];
	body: ShaderStmt[] = [];
	otherwise: ShaderStmt[] = [];
	cases: ShaderCase[] = [];
}

export class ShaderField {
	name: string = "";
	type: ShaderType = new ShaderType();
}

export class ShaderStruct {
	name: string = "";
	members: ShaderField[] = [];
}

export class ShaderConstant {
	name: string = "";
	type: ShaderType = new ShaderType();
	value: ShaderExpr = new ShaderExpr();
}

export enum ResourceKind {
	UniformBlock,
	Texture,
	Sampler,
	StorageBuffer,
	StorageTexture,
}

export enum SampleType {
	Float,
	UnfilterableFloat,
	Depth,
	Sint,
	Uint,
}

export enum SamplerType {
	Filtering,
	NonFiltering,
	Comparison,
}

export class ShaderResource {
	kind: ResourceKind = ResourceKind.UniformBlock;
	name: string = "";
	group: int32 = 0;
	binding: int32 = -1;
	type: ShaderType = new ShaderType();
	access: Access = Access.Read;
	sampleType: SampleType = SampleType.Float;
	samplerType: SamplerType = SamplerType.Filtering;
	condition: FeatureCondition = new FeatureCondition();
}

export enum ShaderStage {
	Vertex,
	Fragment,
	Compute,
}

export enum IoDirection {
	In,
	Out,
}

export enum Builtin {
	None,
	VertexIndex,
	InstanceIndex,
	Position,
	FrontFacing,
	FragDepth,
	LocalInvocationId,
	LocalInvocationIndex,
	GlobalInvocationId,
	WorkgroupId,
	NumWorkgroups,
	SampleIndex,
	SampleMask,
	PrimitiveIndex,
}

export enum Interpolation {
	Perspective,
	Linear,
	Flat,
}

export enum Sampling {
	Center,
	Centroid,
	Sample,
}

export class ShaderIo {
	name: string = "";
	stage: ShaderStage = ShaderStage.Vertex;
	direction: IoDirection = IoDirection.In;
	type: ShaderType = new ShaderType();
	location: int32 = -1;
	builtin: Builtin = Builtin.None;
	interpolation: Interpolation = Interpolation.Perspective;
	sampling: Sampling = Sampling.Center;
	condition: FeatureCondition = new FeatureCondition();
}

export class ShaderFunction {
	name: string = "";
	params: ShaderField[] = [];
	locals: ShaderField[] = [];
	result: ShaderType = new ShaderType();
	body: ShaderStmt[] = [];
	condition: FeatureCondition = new FeatureCondition();
}

export class ShaderEntry {
	name: string = "";
	stage: ShaderStage = ShaderStage.Vertex;
	functionIndex: int32 = -1;
	workgroupSize: int32[] = [1, 1, 1];
}

export enum DeclarationKind {
	Struct,
	Constant,
	Function,
	Workgroup,
}

export class ShaderDeclaration {
	kind: DeclarationKind = DeclarationKind.Struct;
	index: int32 = -1;
}

export class ShaderModule {
	features: string[] = [];
	structs: ShaderStruct[] = [];
	constants: ShaderConstant[] = [];
	resources: ShaderResource[] = [];
	ios: ShaderIo[] = [];
	functions: ShaderFunction[] = [];
	entries: ShaderEntry[] = [];
	declarations: ShaderDeclaration[] = [];
	workgroups: ShaderField[] = [];
}

export function scalarType(scalar: ScalarKind): ShaderType {
	let t = new ShaderType();
	t.kind = ShaderTypeKind.Scalar;
	t.scalar = scalar;
	return t;
}

export function vectorType(scalar: ScalarKind, rows: int32): ShaderType {
	let t = scalarType(scalar);
	t.kind = ShaderTypeKind.Vector;
	t.rows = rows;
	return t;
}

export function matrixType(columns: int32, rows: int32): ShaderType {
	let t = vectorType(ScalarKind.F32, rows);
	t.kind = ShaderTypeKind.Matrix;
	t.columns = columns;
	return t;
}

export function arrayType(element: ShaderType, length: int32): ShaderType {
	let t = new ShaderType();
	t.kind = length < 0 ? ShaderTypeKind.RuntimeArray : ShaderTypeKind.Array;
	t.length = length;
	t.element = [element];
	return t;
}

export function structType(structIndex: int32): ShaderType {
	let t = new ShaderType();
	t.kind = ShaderTypeKind.Struct;
	t.structIndex = structIndex;
	return t;
}

export function textureType(shape: TextureShape, texel: ScalarKind): ShaderType {
	let t = scalarType(texel);
	t.kind = ShaderTypeKind.Texture;
	t.shape = shape;
	return t;
}

export function samplerType(): ShaderType {
	let t = new ShaderType();
	t.kind = ShaderTypeKind.Sampler;
	return t;
}

export function storageTextureType(
	format: TexelFormat,
	access: Access,
	shape: TextureShape = TextureShape.D2,
): ShaderType {
	let t = new ShaderType();
	t.kind = ShaderTypeKind.StorageTexture;
	t.format = format;
	t.access = access;
	t.shape = shape;
	return t;
}

export function atomicType(scalar: ScalarKind): ShaderType {
	let t = scalarType(scalar);
	t.kind = ShaderTypeKind.Atomic;
	return t;
}

// WGSL's __atomic_compare_exchange_result<T>: member 0 is old_value, member 1 exchanged.
export function exchangeResultType(scalar: ScalarKind): ShaderType {
	let t = scalarType(scalar);
	t.kind = ShaderTypeKind.ExchangeResult;
	return t;
}

// WGSL's __modf_result_* and __frexp_result_*: rows is 1 for the f32 forms and the width of a
// vector
// form otherwise. Member 0 is fract, member 1 whole for modf and exp for frexp.
export function modfResultType(rows: int32): ShaderType {
	let t = scalarType(ScalarKind.F32);
	t.kind = ShaderTypeKind.ModfResult;
	t.rows = rows;
	return t;
}

export function frexpResultType(rows: int32): ShaderType {
	let t = modfResultType(rows);
	t.kind = ShaderTypeKind.FrexpResult;
	return t;
}

export function isPredeclaredResult(t: ShaderType): boolean {
	return t.kind == ShaderTypeKind.ExchangeResult || t.kind == ShaderTypeKind.ModfResult ||
		t.kind == ShaderTypeKind.FrexpResult;
}

function shapeOf(scalar: ScalarKind, rows: int32): ShaderType {
	return rows == 1 ? scalarType(scalar) : vectorType(scalar, rows);
}

export function predeclaredMemberType(t: ShaderType, member: int32): ShaderType {
	const exponent = t.kind == ShaderTypeKind.FrexpResult && member == 1;
	return shapeOf(exponent ? ScalarKind.I32 : ScalarKind.F32, t.rows);
}

export function sameShaderType(a: ShaderType, b: ShaderType): boolean {
	if (a.kind != b.kind || a.scalar != b.scalar || a.rows != b.rows || a.columns != b.columns ||
		a.length != b.length || a.structIndex != b.structIndex || a.shape != b.shape ||
		a.format != b.format || a.access != b.access || a.element.length != b.element.length) {
		return false;
	}
	return a.element.length == 0 || sameShaderType(a.element[0], b.element[0]);
}

export function featureOn(feature: string): FeatureCondition {
	let c = new FeatureCondition();
	c.kind = ConditionKind.Feature;
	c.feature = feature;
	return c;
}

export function conditionOf(kind: ConditionKind, operands: FeatureCondition[]): FeatureCondition {
	let c = new FeatureCondition();
	c.kind = kind;
	c.operands = operands;
	return c;
}

export function holds(c: FeatureCondition, on: string[]): boolean {
	return match (c.kind) {
		ConditionKind.Always => true,
		ConditionKind.Feature => on.includes(c.feature),
		ConditionKind.Not => !holds(c.operands[0], on),
		ConditionKind.All => !c.operands.some((o) => !holds(o, on)),
		ConditionKind.Any => c.operands.some((o) => holds(o, on)),
	};
}

export function sameCondition(a: FeatureCondition, b: FeatureCondition): boolean {
	if (a.kind != b.kind || a.feature != b.feature || a.operands.length != b.operands.length) {
		return false;
	}
	for (let i = 0; i < a.operands.length; i++) {
		if (!sameCondition(a.operands[i], b.operands[i])) { return false; }
	}
	return true;
}

export function exprOf(kind: ExprKind, type: ShaderType, index: int32,
	operands: ShaderExpr[]): ShaderExpr {
	let e = new ShaderExpr();
	e.kind = kind;
	e.type = type;
	e.index = index;
	e.operands = operands;
	return e;
}

export function literal(type: ShaderType, value: float64): ShaderExpr {
	let e = exprOf(ExprKind.Literal, type, -1, []);
	e.value = value;
	return e;
}

export function binaryOf(op: BinaryOp, type: ShaderType, left: ShaderExpr,
	right: ShaderExpr): ShaderExpr {
	let e = exprOf(ExprKind.Binary, type, -1, [left, right]);
	e.binary = op;
	return e;
}

export function intrinsicOf(op: Intrinsic, type: ShaderType, args: ShaderExpr[]): ShaderExpr {
	let e = exprOf(ExprKind.Intrinsic, type, -1, args);
	e.intrinsic = op;
	return e;
}

export function stmtOf(kind: StmtKind, expr: ShaderExpr, body: ShaderStmt[]): ShaderStmt {
	let s = new ShaderStmt();
	s.kind = kind;
	s.expr = expr;
	s.body = body;
	return s;
}

export function assignOf(target: ShaderExpr, value: ShaderExpr): ShaderStmt {
	let s = stmtOf(StmtKind.Assign, value, []);
	s.target = target;
	return s;
}

function builtinStages(b: Builtin, direction: IoDirection): ShaderStage[] {
	if (direction == IoDirection.Out) {
		return match (b) {
			Builtin.Position => [ShaderStage.Vertex],
			Builtin.FragDepth | Builtin.SampleMask => [ShaderStage.Fragment],
			Builtin.None | Builtin.VertexIndex | Builtin.InstanceIndex | Builtin.FrontFacing |
				Builtin.LocalInvocationId | Builtin.LocalInvocationIndex |
				Builtin.GlobalInvocationId | Builtin.WorkgroupId | Builtin.NumWorkgroups |
				Builtin.SampleIndex | Builtin.PrimitiveIndex => [],
		};
	}
	return match (b) {
		Builtin.VertexIndex | Builtin.InstanceIndex => [ShaderStage.Vertex],
		Builtin.Position | Builtin.FrontFacing | Builtin.SampleIndex | Builtin.SampleMask |
			Builtin.PrimitiveIndex => [ShaderStage.Fragment],
		Builtin.None | Builtin.FragDepth => [],
		Builtin.LocalInvocationId | Builtin.LocalInvocationIndex | Builtin.GlobalInvocationId |
			Builtin.WorkgroupId | Builtin.NumWorkgroups => [ShaderStage.Compute],
	};
}

function isIntegral(t: ShaderType): boolean {
	const own = t.kind == ShaderTypeKind.Array ? t.element[0] : t;
	return (own.kind == ShaderTypeKind.Scalar || own.kind == ShaderTypeKind.Vector) &&
		(own.scalar == ScalarKind.I32 || own.scalar == ScalarKind.U32);
}

function isBlockMember(t: ShaderType): boolean {
	const own = t.kind == ShaderTypeKind.Array ? t.element[0] : t;
	return own.kind == ShaderTypeKind.Scalar || own.kind == ShaderTypeKind.Vector ||
		own.kind == ShaderTypeKind.Matrix;
}

function isWorkgroupType(t: ShaderType): boolean {
	const own = t.kind == ShaderTypeKind.Array && t.length > 0 ? t.element[0] : t;
	return own.kind == ShaderTypeKind.Scalar || own.kind == ShaderTypeKind.Vector ||
		own.kind == ShaderTypeKind.Atomic;
}

function holdsAtomic(m: ShaderModule, t: ShaderType): boolean {
	if (t.kind == ShaderTypeKind.Atomic) { return true; }
	if (t.kind == ShaderTypeKind.Struct) {
		return t.structIndex >= 0 && t.structIndex < m.structs.length &&
			m.structs[t.structIndex].members.some((f) => holdsAtomic(m, f.type));
	}
	return t.element.some((e) => holdsAtomic(m, e));
}

function holdsBool(m: ShaderModule, t: ShaderType, seen: int32[]): boolean {
	if ((t.kind == ShaderTypeKind.Scalar || t.kind == ShaderTypeKind.Vector) &&
		t.scalar == ScalarKind.Bool) {
		return true;
	}
	if (t.kind == ShaderTypeKind.Struct) {
		if (t.structIndex < 0 || t.structIndex >= m.structs.length ||
			seen.includes(t.structIndex)) {
			return false;
		}
		seen.push(t.structIndex);
		return m.structs[t.structIndex].members.some((f) => holdsBool(m, f.type, seen));
	}
	return t.element.some((e) => holdsBool(m, e, seen));
}

const RUNTIME_ARRAY = "is a runtime array, which only a storage buffer is";

function holdsRuntimeArray(t: ShaderType): boolean {
	return t.kind == ShaderTypeKind.RuntimeArray || t.element.some((e) => holdsRuntimeArray(e));
}

class Checker {
	module: ShaderModule = new ShaderModule();
	errors: string[] = [];
	current: int32 = -1;
	callees: int32[][] = [];
	fragmentOnly: string[][] = [];
	computeOnly: string[][] = [];
	uniformLoads: int32 = 0;
}

export function isDerivative(op: Intrinsic): boolean {
	return op == Intrinsic.Dpdx || op == Intrinsic.Dpdy || op == Intrinsic.Fwidth ||
		op == Intrinsic.DpdxCoarse || op == Intrinsic.DpdxFine || op == Intrinsic.DpdyCoarse ||
		op == Intrinsic.DpdyFine || op == Intrinsic.FwidthCoarse || op == Intrinsic.FwidthFine;
}

function isFragmentOnly(op: Intrinsic): boolean {
	return isDerivative(op) || op == Intrinsic.TextureSampleBias ||
		op == Intrinsic.TextureSampleCompare;
}

function isComputeOnly(op: Intrinsic): boolean {
	return op == Intrinsic.WorkgroupBarrier || op == Intrinsic.StorageBarrier ||
		op == Intrinsic.TextureBarrier || op == Intrinsic.WorkgroupUniformLoad;
}

function noted(list: string[], what: string): void {
	if (!list.includes(what)) { list.push(what); }
}

function stageOnlyErrors(c: Checker, e: ShaderEntry, owner: string): void {
	let reached = [e.functionIndex];
	for (let k = 0; k < reached.length; k++) {
		for (const callee of c.callees[reached[k]]) {
			if (!reached.includes(callee)) { reached.push(callee); }
		}
	}
	let refused: string[] = [];
	for (const i of reached) {
		if (e.stage != ShaderStage.Fragment) {
			for (const what of c.fragmentOnly[i]) {
				noted(refused, what + " outside a fragment entry");
			}
		}
		if (e.stage != ShaderStage.Compute) {
			for (const what of c.computeOnly[i]) {
				noted(refused, what + " outside a compute entry");
			}
		}
	}
	for (const message of refused) { c.errors.push(owner + ": " + message); }
}

function conditionErrors(c: Checker, cond: FeatureCondition, owner: string): void {
	if (cond.kind == ConditionKind.Feature && !c.module.features.includes(cond.feature)) {
		c.errors.push(owner + ": feature '" + cond.feature + "' is not in the module's features");
	}
	for (const o of cond.operands) { conditionErrors(c, o, owner); }
}

function inRange(c: Checker, index: int32, count: int32, what: string, owner: string): void {
	if (index < 0 || index >= count) {
		c.errors.push(owner + ": " + what + " " + String(index) + " is out of range");
	}
}

function literalFault(s: ScalarKind, v: float64): string {
	if (v - v != 0.0) { return "a literal that is not finite"; }
	if (s != ScalarKind.F32 && s != ScalarKind.Bool && v != Math.floor(v)) {
		return "an integer literal with a fraction";
	}
	return "";
}

function literalError(e: ShaderExpr): string {
	const t = e.type;
	const spelled = t.kind == ShaderTypeKind.Scalar || t.kind == ShaderTypeKind.Vector;
	if (e.kind != ExprKind.Literal || !spelled) { return ""; }
	return literalFault(t.scalar, e.value);
}

function constantErrors(c: Checker, e: ShaderExpr, owner: string): void {
	const fault = literalError(e);
	if (fault != "") { c.errors.push(owner + ": " + fault); }
	for (const o of e.operands) { constantErrors(c, o, owner); }
}

function exprErrors(c: Checker, e: ShaderExpr, f: ShaderFunction, owner: string): void {
	const m = c.module;
	match (e.kind) {
		ExprKind.Local => inRange(c, e.index, f.locals.length as int32, "local", owner),
		ExprKind.Param => inRange(c, e.index, f.params.length as int32, "parameter", owner),
		ExprKind.Constant => inRange(c, e.index, m.constants.length as int32, "constant", owner),
		ExprKind.Io => inRange(c, e.index, m.ios.length as int32, "io", owner),
		ExprKind.Resource | ExprKind.BlockMember =>
			inRange(c, e.index, m.resources.length as int32, "resource", owner),
		ExprKind.Call => {
			inRange(c, e.index, m.functions.length as int32, "function", owner);
			if (e.index >= 0 && e.index < m.functions.length) {
				c.callees[c.current].push(e.index);
			}
		},
		ExprKind.Workgroup =>
			inRange(c, e.index, m.workgroups.length as int32, "workgroup variable", owner),
		_ => {},
	}
	if (e.kind == ExprKind.Intrinsic && isFragmentOnly(e.intrinsic)) {
		noted(c.fragmentOnly[c.current], e.intrinsic.toString());
	}
	if (e.kind == ExprKind.Intrinsic && isComputeOnly(e.intrinsic)) {
		noted(c.computeOnly[c.current], e.intrinsic.toString());
	}
	const fault = literalError(e);
	if (fault != "") { c.errors.push(owner + ": " + fault); }
	if (e.type.kind == ShaderTypeKind.RuntimeArray && e.kind != ExprKind.Resource) {
		c.errors.push(owner + ": a runtime array is read only through its storage buffer");
	}
	const shift = e.kind == ExprKind.Binary && isShift(e.binary);
	if (shift && (e.operands.length != 2 || e.operands[1].type.scalar != ScalarKind.U32)) {
		c.errors.push(owner + ": a shift amount is a u32, as WGSL's");
	}
	if (e.kind == ExprKind.Intrinsic && isExplicitSample(e.intrinsic)) {
		const error = explicitSampleError(e);
		if (error != "") { c.errors.push(owner + ": " + error); }
	}
	if (e.kind == ExprKind.Intrinsic && e.intrinsic == Intrinsic.ArrayLength) {
		const error = arrayLengthError(m, e);
		if (error != "") { c.errors.push(owner + ": " + error); }
	}
	if (isUniformLoad(e)) {
		c.uniformLoads += 1;
		const error = uniformLoadError(e);
		if (error != "") { c.errors.push(owner + ": " + error); }
	}
	if (e.kind == ExprKind.Intrinsic && (e.intrinsic == Intrinsic.TextureLoad ||
		e.intrinsic == Intrinsic.TextureDimensions || e.intrinsic == Intrinsic.TextureNumSamples)) {
		const error = multisampleError(e);
		if (error != "") { c.errors.push(owner + ": " + error); }
	}
	if (e.kind == ExprKind.Intrinsic && (e.intrinsic == Intrinsic.TextureLoad ||
		e.intrinsic == Intrinsic.TextureStore)) {
		const error = storageTexelError(e);
		if (error != "") { c.errors.push(owner + ": " + error); }
	}
	if (e.kind == ExprKind.Intrinsic && isSampling(e.intrinsic)) {
		const error = sampleError(m, e);
		if (error != "") { c.errors.push(owner + ": " + error); }
		const offset = offsetError(e);
		if (offset != "") { c.errors.push(owner + ": " + offset); }
	}
	if (e.kind == ExprKind.Intrinsic && isBitsOp(e.intrinsic)) {
		const error = bitsError(e);
		if (error != "") { c.errors.push(owner + ": " + error); }
	}
	if (e.kind == ExprKind.Intrinsic && isMixedMath(e.intrinsic)) {
		const error = mixedMathError(e);
		if (error != "") { c.errors.push(owner + ": " + error); }
	}
	if (e.kind == ExprKind.Intrinsic &&
		(e.intrinsic == Intrinsic.Modf || e.intrinsic == Intrinsic.Frexp)) {
		const error = splitError(e);
		if (error != "") { c.errors.push(owner + ": " + error); }
	}
	const atomic = e.kind == ExprKind.Intrinsic && isAtomic(e.intrinsic);
	if (atomic && (e.operands.length == 0 || e.operands[0].type.kind != ShaderTypeKind.Atomic)) {
		c.errors.push(owner + ": " + e.intrinsic.toString() + " works on an atomic, as WGSL's");
	}
	for (let i = 0; i < e.operands.length; i++) {
		const o = e.operands[i];
		const place = atomic && i == 0 || o.type.kind == ShaderTypeKind.Struct ||
			o.type.kind == ShaderTypeKind.Array || o.type.kind == ShaderTypeKind.RuntimeArray;
		if (!place && holdsAtomic(m, o.type)) {
			c.errors.push(owner + ": an atomic is read and written only through atomic " +
				"operations, as WGSL's");
		}
		exprErrors(c, o, f, owner);
	}
}

export function rootOf(e: ShaderExpr): ShaderExpr {
	const through = e.kind == ExprKind.Field || e.kind == ExprKind.Swizzle ||
		e.kind == ExprKind.Index;
	return through && e.operands.length > 0 ? rootOf(e.operands[0]) : e;
}

function stmtErrors(c: Checker, s: ShaderStmt, f: ShaderFunction, owner: string): void {
	const loadsBefore = c.uniformLoads;
	exprErrors(c, s.expr, f, owner);
	exprErrors(c, s.target, f, owner);
	const loads = c.uniformLoads - loadsBefore;
	if (loads > 0 && !(loads == 1 && s.kind == StmtKind.Let && isUniformLoad(s.expr))) {
		c.errors.push(owner +
			": a WorkgroupUniformLoad is the initializer of a const or let of its " +
			"own, because the barriers around it sit between two statements");
	}
	if (s.kind == StmtKind.For) {
		for (const inner of s.init.concat(s.update)) {
			if (isUniformLoad(inner.expr)) {
				c.errors.push(owner + ": a WorkgroupUniformLoad is no part of a for header");
			}
		}
	}
	const root = rootOf(s.target);
	if (s.kind == StmtKind.Assign && root.kind == ExprKind.Resource &&
		root.index >= 0 && root.index < c.module.resources.length) {
		const r = c.module.resources[root.index];
		if (r.kind == ResourceKind.StorageBuffer && r.access != Access.ReadWrite) {
			c.errors.push(owner + ": a write to storage buffer '" + r.name +
				"', whose access is " + r.access.toString().toLowerCase() + ", not read_write");
		}
	}
	if (holdsAtomic(c.module, s.expr.type) || holdsAtomic(c.module, s.target.type)) {
		c.errors.push(owner + ": an atomic is read and written only through atomic operations, " +
			"as WGSL's");
	}
	if (s.kind == StmtKind.Let) {
		inRange(c, s.local, f.locals.length as int32, "local", owner);
	}
	if (s.kind == StmtKind.FeatureIf) { conditionErrors(c, s.condition, owner); }
	if (s.kind == StmtKind.Discard) { noted(c.fragmentOnly[c.current], "Discard"); }
	for (const list of [s.init, s.update, s.body, s.otherwise]) {
		for (const inner of list) { stmtErrors(c, inner, f, owner); }
	}
	for (const k of s.cases) {
		for (const label of k.labels) { exprErrors(c, label, f, owner); }
		for (const inner of k.body) { stmtErrors(c, inner, f, owner); }
	}
}

function reaches(callees: int32[][], start: int32, target: int32, seen: int32[]): boolean {
	if (seen.includes(start)) { return false; }
	seen.push(start);
	for (const next of callees[start]) {
		if (next == target || reaches(callees, next, target, seen)) { return true; }
	}
	return false;
}

function varyings(m: ShaderModule, stage: ShaderStage, direction: IoDirection): ShaderIo[] {
	return m.ios.filter((io) => io.stage == stage && io.direction == direction &&
		io.builtin == Builtin.None);
}

export function irErrors(m: ShaderModule): string[] {
	let c = new Checker();
	c.module = m;
	for (let i = 0; i < m.resources.length; i++) {
		const r = m.resources[i];
		const owner = "resource '" + r.name + "'";
		conditionErrors(c, r.condition, owner);
		for (let j = 0; j < i; j++) {
			const other = m.resources[j];
			const alternatives = r.kind == other.kind;
			if (other.group == r.group && other.binding == r.binding && !alternatives) {
				c.errors.push(owner + ": binding " + String(r.binding) + " is also '" +
					other.name + "'");
			}
		}
		const shapeHolds = match (r.kind) {
			ResourceKind.UniformBlock => r.type.kind == ShaderTypeKind.Struct &&
				r.type.structIndex >= 0 && r.type.structIndex < m.structs.length &&
				!m.structs[r.type.structIndex].members.some((f) => !isBlockMember(f.type)),
			ResourceKind.Texture => r.type.kind == ShaderTypeKind.Texture,
			ResourceKind.Sampler => r.type.kind == ShaderTypeKind.Sampler,
			ResourceKind.StorageBuffer => r.type.kind == ShaderTypeKind.RuntimeArray &&
				r.type.element[0].kind == ShaderTypeKind.Struct,
			ResourceKind.StorageTexture => r.type.kind == ShaderTypeKind.StorageTexture,
		};
		if (!shapeHolds) {
			c.errors.push(owner + ": its type does not fit a " + r.kind.toString());
		}
		if (r.kind == ResourceKind.StorageTexture && r.type.shape != TextureShape.D1 &&
			r.type.shape != TextureShape.D2 && r.type.shape != TextureShape.D2Array &&
			r.type.shape != TextureShape.D3) {
			c.errors.push(owner + ": a storage texture of shape " + r.type.shape.toString() +
				", where WGSL's is 1d, 2d, 2d array or 3d");
		}
		const shared = r.kind == ResourceKind.UniformBlock || r.kind == ResourceKind.StorageBuffer;
		if (shared && holdsBool(m, r.type, [])) {
			c.errors.push(owner + ": a bool is no uniform or storage member, as WGSL's");
		}
		if (r.kind == ResourceKind.StorageBuffer && r.access != Access.ReadWrite &&
			holdsAtomic(m, r.type)) {
			c.errors.push(owner + ": it holds atomics, so its access is read_write, as WGSL's");
		}
	}
	for (const io of m.ios) {
		const owner = "io '" + io.name + "'";
		conditionErrors(c, io.condition, owner);
		if (io.builtin != Builtin.None &&
			!builtinStages(io.builtin, io.direction).includes(io.stage)) {
			c.errors.push(owner + ": " + io.builtin.toString() + " is no " + io.stage.toString() +
				" " + io.direction.toString().toLowerCase() + "put");
		}
		const varying = io.builtin == Builtin.None &&
			(io.stage == ShaderStage.Vertex && io.direction == IoDirection.Out ||
				io.stage == ShaderStage.Fragment && io.direction == IoDirection.In);
		if (varying && isIntegral(io.type) && io.interpolation != Interpolation.Flat) {
			c.errors.push(owner + ": an integer varying is flat");
		}
		if (varying && io.interpolation == Interpolation.Flat && io.sampling != Sampling.Center) {
			c.errors.push(owner + ": a flat varying takes no sampling, as WGSL's");
		}
		if (holdsRuntimeArray(io.type)) { c.errors.push(owner + ": it " + RUNTIME_ARRAY); }
		if (io.builtin == Builtin.None && holdsBool(m, io.type, [])) {
			c.errors.push(owner + ": a bool is no attribute, varying or output, as WGSL's");
		}
		if (io.builtin == Builtin.None && io.type.kind == ShaderTypeKind.Array) {
			c.errors.push(owner + ": an attribute, varying or output is no array, as WGSL's");
		}
	}
	for (const s of m.structs) {
		for (const f of s.members) {
			if (holdsRuntimeArray(f.type)) {
				c.errors.push("struct '" + s.name + "': member '" + f.name + "' " + RUNTIME_ARRAY);
			}
			if (isPredeclaredResult(f.type)) {
				c.errors.push("struct '" + s.name + "': member '" + f.name +
					"' is a predeclared result, " +
					"which WGSL cannot name");
			}
		}
	}
	for (const k of m.constants) {
		const owner = "constant '" + k.name + "'";
		if (holdsRuntimeArray(k.type)) { c.errors.push(owner + ": it " + RUNTIME_ARRAY); }
		constantErrors(c, k.value, owner);
	}
	c.callees = m.functions.map((): int32[] => []);
	c.fragmentOnly = m.functions.map((): string[] => []);
	c.computeOnly = m.functions.map((): string[] => []);
	for (let i = 0; i < m.functions.length; i++) {
		const f = m.functions[i];
		c.current = i;
		const owner = "function '" + f.name + "'";
		conditionErrors(c, f.condition, owner);
		if (holdsRuntimeArray(f.result)) { c.errors.push(owner + ": its result " + RUNTIME_ARRAY); }
		for (const v of f.params.concat(f.locals)) {
			if (holdsRuntimeArray(v.type)) {
				c.errors.push(owner + ": '" + v.name + "' " + RUNTIME_ARRAY);
			}
			if (holdsAtomic(m, v.type)) {
				c.errors.push(owner + ": '" + v.name + "' holds an atomic, which lives only in a " +
					"storage buffer or workgroup memory, as WGSL's");
			}
		}
		for (const s of f.body) { stmtErrors(c, s, f, owner); }
	}
	for (let i = 0; i < m.functions.length; i++) {
		if (reaches(c.callees, i, i, [])) {
			c.errors.push("function '" + m.functions[i].name + "' is recursive");
		}
	}
	for (const w of m.workgroups) {
		if (!isWorkgroupType(w.type)) {
			c.errors.push("workgroup variable '" + w.name + "': it holds a scalar, a vector or " +
				"an array of them");
		}
	}
	for (const d of m.declarations) {
		const count = match (d.kind) {
			DeclarationKind.Struct => m.structs.length,
			DeclarationKind.Constant => m.constants.length,
			DeclarationKind.Function => m.functions.length,
			DeclarationKind.Workgroup => m.workgroups.length,
		};
		inRange(c, d.index, count as int32, d.kind.toString().toLowerCase(), "declarations");
	}
	let stages: ShaderStage[] = [];
	for (const e of m.entries) {
		const owner = "entry '" + e.name + "'";
		inRange(c, e.functionIndex, m.functions.length as int32, "function", owner);
		if (e.functionIndex >= 0 && e.functionIndex < m.functions.length) {
			stageOnlyErrors(c, e, owner);
		}
		stages.push(e.stage);
		const outputs = m.ios.filter((io) => io.stage == e.stage &&
			io.direction == IoDirection.Out);
		if (e.stage == ShaderStage.Vertex &&
			!outputs.some((io) => io.builtin == Builtin.Position)) {
			c.errors.push(owner + ": a vertex entry writes Position");
		}
		if (e.stage == ShaderStage.Compute && outputs.length > 0) {
			c.errors.push(owner + ": a compute entry has no outputs");
		}
		if (e.workgroupSize.length != 3 || e.workgroupSize.some((n) => n < 1)) {
			c.errors.push(owner + ": the workgroup size is three counts of at least 1");
		}
	}
	if (stages.includes(ShaderStage.Vertex) && stages.includes(ShaderStage.Fragment)) {
		const written = varyings(m, ShaderStage.Vertex, IoDirection.Out);
		const read = varyings(m, ShaderStage.Fragment, IoDirection.In);
		for (let i = 0; i < written.length || i < read.length; i++) {
			const linked = i < written.length && i < read.length &&
				written[i].name == read[i].name && sameShaderType(written[i].type, read[i].type) &&
				sameCondition(written[i].condition, read[i].condition);
			if (!linked) {
				c.errors.push("varying " + String(i) + " differs between the vertex output and " +
					"the fragment input");
			} else if (written[i].interpolation != read[i].interpolation ||
				written[i].sampling != read[i].sampling) {
				c.errors.push("varying " + String(i) +
					" is interpolated differently by the vertex " +
					"output and the fragment input");
			}
		}
	}
	return c.errors;
}
