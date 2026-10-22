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
	LogicalAnd,
	LogicalOr,
	Equal,
	NotEqual,
	Less,
	LessEqual,
	Greater,
	GreaterEqual,
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
	LessThanEqual,
	Dpdx,
	Dpdy,
	Fwidth,
	TextureSample,
	TextureLoad,
	TextureStore,
	TextureDimensions,
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

export class ShaderModule {
	features: string[] = [];
	structs: ShaderStruct[] = [];
	constants: ShaderConstant[] = [];
	resources: ShaderResource[] = [];
	ios: ShaderIo[] = [];
	functions: ShaderFunction[] = [];
	entries: ShaderEntry[] = [];
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

export function storageTextureType(format: TexelFormat, access: Access): ShaderType {
	let t = new ShaderType();
	t.kind = ShaderTypeKind.StorageTexture;
	t.format = format;
	t.access = access;
	return t;
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
			_ => [],
		};
	}
	return match (b) {
		Builtin.VertexIndex | Builtin.InstanceIndex => [ShaderStage.Vertex],
		Builtin.Position | Builtin.FrontFacing | Builtin.SampleIndex | Builtin.SampleMask =>
			[ShaderStage.Fragment],
		Builtin.None | Builtin.FragDepth => [],
		_ => [ShaderStage.Compute],
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

class Checker {
	module: ShaderModule = new ShaderModule();
	errors: string[] = [];
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

function exprErrors(c: Checker, e: ShaderExpr, f: ShaderFunction, owner: string): void {
	const m = c.module;
	match (e.kind) {
		ExprKind.Local => inRange(c, e.index, f.locals.length as int32, "local", owner),
		ExprKind.Param => inRange(c, e.index, f.params.length as int32, "parameter", owner),
		ExprKind.Constant => inRange(c, e.index, m.constants.length as int32, "constant", owner),
		ExprKind.Io => inRange(c, e.index, m.ios.length as int32, "io", owner),
		ExprKind.Resource | ExprKind.BlockMember =>
			inRange(c, e.index, m.resources.length as int32, "resource", owner),
		ExprKind.Call => inRange(c, e.index, m.functions.length as int32, "function", owner),
		_ => {},
	}
	for (const o of e.operands) { exprErrors(c, o, f, owner); }
}

function stmtErrors(c: Checker, s: ShaderStmt, f: ShaderFunction, owner: string): void {
	exprErrors(c, s.expr, f, owner);
	exprErrors(c, s.target, f, owner);
	if (s.kind == StmtKind.Let) {
		inRange(c, s.local, f.locals.length as int32, "local", owner);
	}
	if (s.kind == StmtKind.FeatureIf) { conditionErrors(c, s.condition, owner); }
	for (const list of [s.init, s.update, s.body, s.otherwise]) {
		for (const inner of list) { stmtErrors(c, inner, f, owner); }
	}
	for (const k of s.cases) {
		for (const label of k.labels) { exprErrors(c, label, f, owner); }
		for (const inner of k.body) { stmtErrors(c, inner, f, owner); }
	}
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
			const alternatives = r.kind == ResourceKind.UniformBlock &&
				other.kind == ResourceKind.UniformBlock;
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
		if (!shapeHolds) { c.errors.push(owner + ": its type does not fit a " + r.kind.toString()); }
	}
	for (const io of m.ios) {
		const owner = "io '" + io.name + "'";
		conditionErrors(c, io.condition, owner);
		if (io.builtin != Builtin.None && !builtinStages(io.builtin, io.direction).includes(io.stage)) {
			c.errors.push(owner + ": " + io.builtin.toString() + " is no " + io.stage.toString() +
				" " + io.direction.toString().toLowerCase() + "put");
		}
		const varying = io.builtin == Builtin.None &&
			(io.stage == ShaderStage.Vertex && io.direction == IoDirection.Out ||
				io.stage == ShaderStage.Fragment && io.direction == IoDirection.In);
		if (varying && isIntegral(io.type) && io.interpolation != Interpolation.Flat) {
			c.errors.push(owner + ": an integer varying is flat");
		}
	}
	for (const f of m.functions) {
		const owner = "function '" + f.name + "'";
		conditionErrors(c, f.condition, owner);
		for (const s of f.body) { stmtErrors(c, s, f, owner); }
	}
	let stages: ShaderStage[] = [];
	for (const e of m.entries) {
		const owner = "entry '" + e.name + "'";
		inRange(c, e.functionIndex, m.functions.length as int32, "function", owner);
		stages.push(e.stage);
		const outputs = m.ios.filter((io) => io.stage == e.stage && io.direction == IoDirection.Out);
		if (e.stage == ShaderStage.Vertex && !outputs.some((io) => io.builtin == Builtin.Position)) {
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
			}
		}
	}
	return c.errors;
}
