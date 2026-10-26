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
	ShaderEntry,
	ShaderExpr,
	ShaderFunction,
	ShaderModule,
	ShaderStage,
	ShaderStmt,
	ShaderType,
	ShaderTypeKind,
	StmtKind,
	TexelFormat,
	TextureShape,
	UnaryOp,
	isArrayTexture,
	hasOffset,
	offsetOf,
	isAtomic,
	isDerivative,
	isEffect,
	sameShaderType,
	scalarType,
	vectorType,
	predeclaredMemberType,
} from "./ir";
import { BindingSlot, StructLayout, storageElementLayout, uniformBlockLayout } from "./layout";
import { builtinType, ioLocation, rootOf } from "./irWalk";
import { Reads, printableEntry } from "./specialize";
import { componentCompare, isComponentCompare, isMath } from "./spelling";

const OP_NAME = 5;
const OP_MEMBER_NAME = 6;
const OP_EXT_INST_IMPORT = 11;
const OP_EXT_INST = 12;
const OP_MEMORY_MODEL = 14;
const OP_ENTRY_POINT = 15;
const OP_EXECUTION_MODE = 16;
const OP_CAPABILITY = 17;
const OP_TYPE_VOID = 19;
const OP_TYPE_BOOL = 20;
const OP_TYPE_INT = 21;
const OP_TYPE_FLOAT = 22;
const OP_TYPE_VECTOR = 23;
const OP_TYPE_MATRIX = 24;
const OP_TYPE_IMAGE = 25;
const OP_TYPE_SAMPLER = 26;
const OP_TYPE_SAMPLED_IMAGE = 27;
const OP_TYPE_ARRAY = 28;
const OP_TYPE_RUNTIME_ARRAY = 29;
const OP_TYPE_STRUCT = 30;
const OP_TYPE_POINTER = 32;
const OP_TYPE_FUNCTION = 33;
const OP_CONSTANT_TRUE = 41;
const OP_CONSTANT_FALSE = 42;
const OP_CONSTANT = 43;
const OP_CONSTANT_COMPOSITE = 44;
const OP_CONSTANT_NULL = 46;
const OP_FUNCTION = 54;
const OP_FUNCTION_PARAMETER = 55;
const OP_FUNCTION_END = 56;
const OP_FUNCTION_CALL = 57;
const OP_VARIABLE = 59;
const OP_LOAD = 61;
const OP_STORE = 62;
const OP_ACCESS_CHAIN = 65;
const OP_DECORATE = 71;
const OP_MEMBER_DECORATE = 72;
const OP_VECTOR_EXTRACT_DYNAMIC = 77;
const OP_VECTOR_SHUFFLE = 79;
const OP_COMPOSITE_CONSTRUCT = 80;
const OP_COMPOSITE_EXTRACT = 81;
const OP_COPY_OBJECT = 83;
const OP_TRANSPOSE = 84;
const OP_SAMPLED_IMAGE = 86;
const OP_IMAGE_SAMPLE_IMPLICIT_LOD = 87;
const OP_IMAGE_SAMPLE_EXPLICIT_LOD = 88;
const OP_IMAGE_SAMPLE_DREF_IMPLICIT_LOD = 89;
const OP_IMAGE_SAMPLE_DREF_EXPLICIT_LOD = 90;
const OP_IMAGE_FETCH = 95;
const OP_IMAGE_READ = 98;
const OP_IMAGE_WRITE = 99;
const OP_IMAGE_QUERY_SIZE_LOD = 103;
const OP_IMAGE_QUERY_SIZE = 104;
const OP_IMAGE_QUERY_SAMPLES = 107;
const OP_CONVERT_F_TO_U = 109;
const OP_CONVERT_F_TO_S = 110;
const OP_CONVERT_S_TO_F = 111;
const OP_CONVERT_U_TO_F = 112;
const OP_BITCAST = 124;
const OP_S_NEGATE = 126;
const OP_F_NEGATE = 127;
const OP_I_ADD = 128;
const OP_F_ADD = 129;
const OP_I_SUB = 130;
const OP_F_SUB = 131;
const OP_I_MUL = 132;
const OP_F_MUL = 133;
const OP_U_DIV = 134;
const OP_S_DIV = 135;
const OP_F_DIV = 136;
const OP_U_MOD = 137;
const OP_F_REM = 140;
const OP_VECTOR_TIMES_SCALAR = 142;
const OP_MATRIX_TIMES_SCALAR = 143;
const OP_VECTOR_TIMES_MATRIX = 144;
const OP_MATRIX_TIMES_VECTOR = 145;
const OP_MATRIX_TIMES_MATRIX = 146;
const OP_DOT = 148;
const OP_ANY = 154;
const OP_ALL = 155;
const OP_LOGICAL_EQUAL = 164;
const OP_LOGICAL_NOT_EQUAL = 165;
const OP_LOGICAL_OR = 166;
const OP_LOGICAL_AND = 167;
const OP_LOGICAL_NOT = 168;
const OP_SELECT = 169;
const OP_I_EQUAL = 170;
const OP_I_NOT_EQUAL = 171;
const OP_U_GREATER_THAN = 172;
const OP_S_GREATER_THAN = 173;
const OP_U_GREATER_THAN_EQUAL = 174;
const OP_S_GREATER_THAN_EQUAL = 175;
const OP_U_LESS_THAN = 176;
const OP_S_LESS_THAN = 177;
const OP_U_LESS_THAN_EQUAL = 178;
const OP_S_LESS_THAN_EQUAL = 179;
const OP_F_ORD_EQUAL = 180;
const OP_F_ORD_NOT_EQUAL = 182;
const OP_F_UNORD_NOT_EQUAL = 183;
const OP_F_ORD_LESS_THAN = 184;
const OP_F_ORD_GREATER_THAN = 186;
const OP_F_ORD_LESS_THAN_EQUAL = 188;
const OP_F_ORD_GREATER_THAN_EQUAL = 190;
const OP_SHIFT_RIGHT_LOGICAL = 194;
const OP_SHIFT_RIGHT_ARITHMETIC = 195;
const OP_SHIFT_LEFT_LOGICAL = 196;
const OP_BITWISE_OR = 197;
const OP_BITWISE_XOR = 198;
const OP_BITWISE_AND = 199;
const OP_NOT = 200;
const OP_BIT_FIELD_INSERT = 201;
const OP_BIT_FIELD_S_EXTRACT = 202;
const OP_BIT_FIELD_U_EXTRACT = 203;
const OP_BIT_REVERSE = 204;
const OP_BIT_COUNT = 205;
const OP_DPDX = 207;
const OP_DPDY = 208;
const OP_FWIDTH = 209;
const OP_DPDX_FINE = 210;
const OP_DPDY_FINE = 211;
const OP_FWIDTH_FINE = 212;
const OP_DPDX_COARSE = 213;
const OP_DPDY_COARSE = 214;
const OP_FWIDTH_COARSE = 215;
const OP_CONTROL_BARRIER = 224;
const OP_ATOMIC_LOAD = 227;
const OP_ATOMIC_STORE = 228;
const OP_ATOMIC_EXCHANGE = 229;
const OP_ATOMIC_COMPARE_EXCHANGE = 230;
const OP_ATOMIC_I_ADD = 234;
const OP_ATOMIC_I_SUB = 235;
const OP_ATOMIC_S_MIN = 236;
const OP_ATOMIC_U_MIN = 237;
const OP_ATOMIC_S_MAX = 238;
const OP_ATOMIC_U_MAX = 239;
const OP_ATOMIC_AND = 240;
const OP_ATOMIC_OR = 241;
const OP_ATOMIC_XOR = 242;
const OP_PHI = 245;
const OP_LOOP_MERGE = 246;
const OP_SELECTION_MERGE = 247;
const OP_LABEL = 248;
const OP_BRANCH = 249;
const OP_BRANCH_CONDITIONAL = 250;
const OP_SWITCH = 251;
const OP_KILL = 252;
const OP_RETURN = 253;
const OP_RETURN_VALUE = 254;

const CAP_SHADER = 1;
const CAP_SAMPLE_RATE_SHADING = 35;
const CAP_SAMPLED_CUBE_ARRAY = 45;
const CAP_STORAGE_IMAGE_EXTENDED_FORMATS = 49;
const CAP_IMAGE_QUERY = 50;
const CAP_DERIVATIVE_CONTROL = 51;

const DECORATION_BLOCK = 2;
const DECORATION_COL_MAJOR = 5;
const DECORATION_ARRAY_STRIDE = 6;
const DECORATION_MATRIX_STRIDE = 7;
const DECORATION_BUILT_IN = 11;
const DECORATION_NO_PERSPECTIVE = 13;
const DECORATION_FLAT = 14;
const DECORATION_CENTROID = 16;
const DECORATION_SAMPLE = 17;
const DECORATION_NON_WRITABLE = 24;
const DECORATION_NON_READABLE = 25;
const DECORATION_LOCATION = 30;
const DECORATION_BINDING = 33;
const DECORATION_DESCRIPTOR_SET = 34;
const DECORATION_OFFSET = 35;

const UNIFORM_CONSTANT = 0;
const INPUT = 1;
const UNIFORM = 2;
const OUTPUT = 3;
const WORKGROUP = 4;
const FUNCTION = 7;
const STORAGE_BUFFER = 12;

const IMAGE_BIAS = 1;
const IMAGE_LOD = 2;
const IMAGE_GRAD = 4;
const IMAGE_CONST_OFFSET = 8;
const IMAGE_SAMPLE = 64;

const GLSL_F_ABS = 4;
const GLSL_S_ABS = 5;
const GLSL_F_SIGN = 6;
const GLSL_S_SIGN = 7;
const GLSL_MATRIX_INVERSE = 34;
const GLSL_F_MIN = 37;
const GLSL_U_MIN = 38;
const GLSL_S_MIN = 39;
const GLSL_F_MAX = 40;
const GLSL_U_MAX = 41;
const GLSL_S_MAX = 42;
const GLSL_F_CLAMP = 43;
const GLSL_FIND_I_LSB = 73;
const GLSL_FIND_S_MSB = 74;
const GLSL_FIND_U_MSB = 75;

const STD140 = 1;
const STD430 = 2;

class Spirv {
	module: ShaderModule = new ShaderModule();
	stage: ShaderStage = ShaderStage.Vertex;
	error: string = "";
	bound: int32 = 1;
	glsl: int32 = 0;
	capabilities: int32[] = [];
	depthReplacing: boolean = false;
	names: int32[] = [];
	annotations: int32[] = [];
	globals: int32[] = [];
	functionWords: int32[] = [];
	keyNames: string[] = [];
	keyIds: int32[] = [];
	constantIds: int32[] = [];
	compositeIds: int32[] = [];
	compositeParts: int32[][] = [];
	structRules: int32[] = [];
	structOffsets: int32[][] = [];
	structSizes: int32[] = [];
	structSlots: int32[][] = [];
	resourceVars: int32[] = [];
	ioVars: int32[] = [];
	workgroupVars: int32[] = [];
	functionIds: int32[] = [];
	constantValues: int32[] = [];
	constantOwner: string = "";
	fn: ShaderFunction = new ShaderFunction();
	localVars: int32[] = [];
	paramVars: int32[] = [];
	vars: int32[] = [];
	body: int32[] = [];
	block: int32 = 0;
	terminated: boolean = false;
	breaks: int32[] = [];
	continues: int32[] = [];
}

class Place {
	id: int32 = 0;
	base: int32 = 0;
	storage: int32 = 0;
	indices: int32[] = [];
}

function refusal(p: Spirv, what: string): int32 {
	if (p.error == "") { p.error = "printSpirv: " + what; }
	return 0;
}

function fresh(p: Spirv): int32 {
	const id = p.bound;
	p.bound++;
	return id;
}

function need(p: Spirv, capability: int32): void {
	if (!p.capabilities.includes(capability)) { p.capabilities.push(capability); }
}

function inst(out: int32[], opcode: int32, operands: int32[]): void {
	out.push((operands.length as int32 + 1) * 65536 + opcode);
	for (const o of operands) { out.push(o); }
}

function stringWords(text: string): int32[] {
	let out: int32[] = [];
	let word: int32 = 0;
	let shift: int32 = 1;
	for (let i = 0; i < text.length; i++) {
		let c = text.charCodeAt(i);
		if (c > 127) { c = 95; }
		word += c * shift;
		if (shift == 16777216) {
			out.push(word);
			word = 0;
			shift = 1;
		} else {
			shift *= 256;
		}
	}
	out.push(word);
	return out;
}

function wordOf(bits: float64): int32 {
	return (bits >= 2147483648.0 ? bits - 4294967296.0 : bits) as int32;
}

function uint32Bits(w: int32): uint32 {
	const wide = w as int64;
	return (wide < (0 as int64) ? wide + (0x100000000 as int64) : wide) as uint32;
}

function powerOfTwo(n: int32): float64 {
	let x = 1.0;
	for (let i: int32 = 0; i < n; i++) { x = x * 2.0; }
	for (let i: int32 = 0; i > n; i--) { x = x / 2.0; }
	return x;
}

function roundEven(x: float64): float64 {
	const below = Math.floor(x);
	const rest = x - below;
	if (rest != 0.5) { return rest < 0.5 ? below : below + 1.0; }
	return Math.floor(below / 2.0) * 2.0 == below ? below : below + 1.0;
}

function f32Bits(v: float64): float64 {
	if (v == 0.0) { return 0.0; }
	const sign = v < 0.0 ? 2147483648.0 : 0.0;
	let a = v < 0.0 ? -v : v;
	let e: int32 = 0;
	while (a >= 2.0) {
		a = a / 2.0;
		e++;
	}
	while (a < 1.0) {
		a = a * 2.0;
		e--;
	}
	const field = e >= -126 ? ((e + 127) as float64) * 8388608.0 + roundEven((a - 1.0) * 8388608.0) :
		roundEven(a * powerOfTwo(e + 149));
	return field >= 2139095040.0 ? -1.0 : sign + field;
}

function cached(p: Spirv, key: string): int32 {
	const at = p.keyNames.indexOf(key);
	return at < 0 ? 0 : p.keyIds[at];
}

function remember(p: Spirv, key: string, id: int32): void {
	p.keyNames.push(key);
	p.keyIds.push(id);
}

function declared(p: Spirv, key: string, opcode: int32, operands: int32[]): int32 {
	const held = cached(p, key);
	if (held != 0) { return held; }
	const id = fresh(p);
	inst(p.globals, opcode, [id].concat(operands));
	remember(p, key, id);
	return id;
}

function name(p: Spirv, id: int32, text: string): void {
	inst(p.names, OP_NAME, [id].concat(stringWords(text)));
}

function decorate(p: Spirv, id: int32, decoration: int32, operands: int32[]): void {
	inst(p.annotations, OP_DECORATE, [id, decoration].concat(operands));
}

function memberDecorate(p: Spirv, id: int32, member: int32, decoration: int32,
	operands: int32[]): void {
	inst(p.annotations, OP_MEMBER_DECORATE, [id, member, decoration].concat(operands));
}

function scalarTypeId(p: Spirv, s: ScalarKind): int32 {
	return match (s) {
		ScalarKind.F32 => declared(p, "f32", OP_TYPE_FLOAT, [32]),
		ScalarKind.I32 => declared(p, "i32", OP_TYPE_INT, [32, 1]),
		ScalarKind.U32 => declared(p, "u32", OP_TYPE_INT, [32, 0]),
		ScalarKind.Bool => declared(p, "bool", OP_TYPE_BOOL, []),
	};
}

function vectorTypeId(p: Spirv, s: ScalarKind, rows: int32): int32 {
	const component = scalarTypeId(p, s);
	return declared(p, "v" + String(component) + "x" + String(rows), OP_TYPE_VECTOR,
		[component, rows]);
}

function matrixTypeId(p: Spirv, columns: int32, rows: int32): int32 {
	const column = vectorTypeId(p, ScalarKind.F32, rows);
	return declared(p, "m" + String(column) + "x" + String(columns), OP_TYPE_MATRIX,
		[column, columns]);
}

function strideOf(p: Spirv, t: ShaderType): int32 {
	return match (t.kind) {
		ShaderTypeKind.Scalar => t.scalar == ScalarKind.Bool ? 0 : 4,
		ShaderTypeKind.Atomic => 4,
		ShaderTypeKind.Vector => t.scalar == ScalarKind.Bool ? 0 : t.rows == 2 ? 8 : 16,
		ShaderTypeKind.Matrix => t.columns * (t.rows == 2 ? 8 : 16),
		ShaderTypeKind.Struct => p.structSizes[t.structIndex],
		ShaderTypeKind.Void | ShaderTypeKind.Array | ShaderTypeKind.RuntimeArray |
			ShaderTypeKind.Texture | ShaderTypeKind.Sampler | ShaderTypeKind.StorageTexture |
			ShaderTypeKind.ExchangeResult | ShaderTypeKind.ModfResult | ShaderTypeKind.FrexpResult => 0,
	};
}

function arrayTypeId(p: Spirv, element: int32, length: int32, stride: int32): int32 {
	const count = wordConstant(p, scalarTypeId(p, ScalarKind.U32), length);
	const key = "a" + String(element) + ":" + String(count) + ":" + String(stride);
	const held = cached(p, key);
	if (held != 0) { return held; }
	const id = declared(p, key, OP_TYPE_ARRAY, [element, count]);
	if (stride > 0) { decorate(p, id, DECORATION_ARRAY_STRIDE, [stride]); }
	return id;
}

function runtimeArrayTypeId(p: Spirv, element: ShaderType): int32 {
	const inner = typeId(p, element);
	const stride = strideOf(p, element);
	const key = "r" + String(inner) + ":" + String(stride);
	const held = cached(p, key);
	if (held != 0) { return held; }
	const id = declared(p, key, OP_TYPE_RUNTIME_ARRAY, [inner]);
	if (stride > 0) { decorate(p, id, DECORATION_ARRAY_STRIDE, [stride]); }
	return id;
}

function isHoisted(p: Spirv, structIndex: int32, t: ShaderType): boolean {
	return p.structRules[structIndex] == STD140 && t.kind == ShaderTypeKind.Matrix && t.rows == 2;
}

function structTypeId(p: Spirv, index: int32): int32 {
	const key = "s" + String(index);
	const held = cached(p, key);
	if (held != 0) { return held; }
	const s = p.module.structs[index];
	const rule = p.structRules[index];
	let members: int32[] = [];
	let slots: int32[] = [];
	for (const f of s.members) {
		slots.push(members.length as int32);
		if (isHoisted(p, index, f.type)) {
			const column = typeId(p, vectorType(ScalarKind.F32, 2));
			for (let c: int32 = 0; c < f.type.columns; c++) { members.push(column); }
		} else {
			members.push(typeId(p, f.type));
		}
	}
	p.structSlots[index] = slots;
	const id = declared(p, key, OP_TYPE_STRUCT, members);
	name(p, id, s.name);
	for (let k: int32 = 0; k < s.members.length; k++) {
		const t = s.members[k].type;
		const at = slots[k];
		if (isHoisted(p, index, t)) {
			for (let c: int32 = 0; c < t.columns; c++) {
				const columnName = s.members[k].name + "_col" + String(c);
				inst(p.names, OP_MEMBER_NAME, [id, at + c].concat(stringWords(columnName)));
				memberDecorate(p, id, at + c, DECORATION_OFFSET, [p.structOffsets[index][k] + 8 * c]);
			}
			continue;
		}
		inst(p.names, OP_MEMBER_NAME, [id, at].concat(stringWords(s.members[k].name)));
		if (rule == 0) { continue; }
		memberDecorate(p, id, at, DECORATION_OFFSET, [p.structOffsets[index][k]]);
		const own = t.kind == ShaderTypeKind.Array ? t.element[0] : t;
		if (own.kind == ShaderTypeKind.Matrix) {
			memberDecorate(p, id, at, DECORATION_COL_MAJOR, []);
			memberDecorate(p, id, at, DECORATION_MATRIX_STRIDE, [own.rows == 2 ? 8 : 16]);
		}
	}
	return id;
}

function hoistedMember(p: Spirv, e: ShaderExpr): boolean {
	return e.kind == ExprKind.BlockMember && e.type.kind == ShaderTypeKind.Matrix &&
		e.type.rows == 2;
}

function loadHoisted(p: Spirv, e: ShaderExpr): int32 {
	const structIndex = p.module.resources[e.index].type.structIndex;
	const at = p.structSlots[structIndex][e.member];
	const column = vectorType(ScalarKind.F32, 2);
	let columns: int32[] = [];
	for (let c: int32 = 0; c < e.type.columns; c++) {
		const place = typed(p, OP_ACCESS_CHAIN, pointerTypeId(p, UNIFORM, typeId(p, column)),
			[p.resourceVars[e.index], intConstant(p, ScalarKind.I32, at + c)]);
		columns.push(typed(p, OP_LOAD, typeId(p, column), [place]));
	}
	return typed(p, OP_COMPOSITE_CONSTRUCT, typeId(p, e.type), columns);
}

function isDepthShape(shape: TextureShape): boolean {
	return shape == TextureShape.Depth2d || shape == TextureShape.Depth2dArray ||
		shape == TextureShape.DepthCube;
}

function imageTypeId(p: Spirv, operands: int32[]): int32 {
	return declared(p, "i" + operands.map((n) => String(n)).join(","), OP_TYPE_IMAGE, operands);
}

function textureTypeId(p: Spirv, t: ShaderType): int32 {
	if (t.scalar == ScalarKind.Bool) { return refusal(p, "a texture of bool texels"); }
	const dim = match (t.shape) {
		TextureShape.D2 | TextureShape.D2Array | TextureShape.Depth2d | TextureShape.Depth2dArray |
			TextureShape.Multisampled2d => 1,
		TextureShape.D3 => 2,
		TextureShape.Cube | TextureShape.CubeArray | TextureShape.DepthCube => 3,
	};
	if (t.shape == TextureShape.CubeArray) { need(p, CAP_SAMPLED_CUBE_ARRAY); }
	return imageTypeId(p, [
		scalarTypeId(p, t.scalar),
		dim,
		isDepthShape(t.shape) ? 1 : 0,
		isArrayTexture(t) ? 1 : 0,
		t.shape == TextureShape.Multisampled2d ? 1 : 0,
		1,
		0,
	]);
}

function storageTextureTypeId(p: Spirv, t: ShaderType): int32 {
	const format = match (t.format) {
		TexelFormat.Rgba8unorm => 4,
		TexelFormat.Rgba8snorm => 5,
		TexelFormat.Rgba8uint => 32,
		TexelFormat.Rgba16float => 2,
		TexelFormat.Rgba32float => 1,
		TexelFormat.R32float => 3,
		TexelFormat.R32uint => 33,
		TexelFormat.Rg32float => 6,
	};
	if (t.format == TexelFormat.Rg32float) { need(p, CAP_STORAGE_IMAGE_EXTENDED_FORMATS); }
	const dim = match (t.shape) {
		TextureShape.D2 | TextureShape.D2Array => 1,
		TextureShape.D3 => 2,
		TextureShape.Cube | TextureShape.CubeArray | TextureShape.Depth2d |
			TextureShape.Depth2dArray | TextureShape.DepthCube | TextureShape.Multisampled2d => 0,
	};
	if (dim == 0) { return refusal(p, "a storage texture of shape " + t.shape.toString()); }
	const uint = t.format == TexelFormat.Rgba8uint || t.format == TexelFormat.R32uint;
	return imageTypeId(p, [
		scalarTypeId(p, uint ? ScalarKind.U32 : ScalarKind.F32),
		dim,
		0,
		isArrayTexture(t) ? 1 : 0,
		0,
		2,
		format,
	]);
}

function exchangeTypeId(p: Spirv, s: ScalarKind): int32 {
	const members = [scalarTypeId(p, s), scalarTypeId(p, ScalarKind.Bool)];
	return declared(p, "x" + String(members[0]), OP_TYPE_STRUCT, members);
}

function splitTypeId(p: Spirv, t: ShaderType): int32 {
	const members = [typeId(p, predeclaredMemberType(t, 0)), typeId(p, predeclaredMemberType(t, 1))];
	return declared(p, "r" + String(members[0]) + ":" + String(members[1]), OP_TYPE_STRUCT, members);
}

function typeId(p: Spirv, t: ShaderType): int32 {
	return match (t.kind) {
		ShaderTypeKind.Void => declared(p, "void", OP_TYPE_VOID, []),
		ShaderTypeKind.Scalar | ShaderTypeKind.Atomic => scalarTypeId(p, t.scalar),
		ShaderTypeKind.Vector => vectorTypeId(p, t.scalar, t.rows),
		ShaderTypeKind.Matrix => matrixTypeId(p, t.columns, t.rows),
		ShaderTypeKind.Array => arrayTypeId(p, typeId(p, t.element[0]), t.length,
			strideOf(p, t.element[0])),
		ShaderTypeKind.RuntimeArray => runtimeArrayTypeId(p, t.element[0]),
		ShaderTypeKind.Struct => structTypeId(p, t.structIndex),
		ShaderTypeKind.Texture => textureTypeId(p, t),
		ShaderTypeKind.Sampler => declared(p, "sampler", OP_TYPE_SAMPLER, []),
		ShaderTypeKind.StorageTexture => storageTextureTypeId(p, t),
		ShaderTypeKind.ExchangeResult => exchangeTypeId(p, t.scalar),
		ShaderTypeKind.ModfResult | ShaderTypeKind.FrexpResult => splitTypeId(p, t),
	};
}

function pointerTypeId(p: Spirv, storage: int32, type: int32): int32 {
	return declared(p, "p" + String(storage) + ":" + String(type), OP_TYPE_POINTER,
		[storage, type]);
}

function functionTypeId(p: Spirv, result: int32, params: int32[]): int32 {
	return declared(p, "f" + String(result) + ":" + params.map((n) => String(n)).join(","),
		OP_TYPE_FUNCTION, [result].concat(params));
}

function constant(p: Spirv, key: string, opcode: int32, type: int32, operands: int32[]): int32 {
	const held = cached(p, key);
	if (held != 0) { return held; }
	const id = fresh(p);
	inst(p.globals, opcode, [type, id].concat(operands));
	remember(p, key, id);
	p.constantIds.push(id);
	return id;
}

function wordConstant(p: Spirv, type: int32, word: int32): int32 {
	return constant(p, "c" + String(type) + ":" + String(word), OP_CONSTANT, type, [word]);
}

function boolConstant(p: Spirv, value: boolean): int32 {
	return constant(p, value ? "true" : "false", value ? OP_CONSTANT_TRUE : OP_CONSTANT_FALSE,
		scalarTypeId(p, ScalarKind.Bool), []);
}

function nullConstant(p: Spirv, type: int32): int32 {
	return constant(p, "n" + String(type), OP_CONSTANT_NULL, type, []);
}

function intConstant(p: Spirv, s: ScalarKind, n: int32): int32 {
	return wordConstant(p, scalarTypeId(p, s), n);
}

function scalarConstant(p: Spirv, s: ScalarKind, v: float64): int32 {
	if (s == ScalarKind.Bool) { return boolConstant(p, v != 0.0); }
	const type = scalarTypeId(p, s);
	if (s == ScalarKind.F32) {
		const bits = f32Bits(v);
		if (bits < 0.0) { return refusal(p, "a literal outside the f32 range"); }
		return wordConstant(p, type, wordOf(bits));
	}
	const low = s == ScalarKind.I32 ? -2147483648.0 : 0.0;
	const high = s == ScalarKind.I32 ? 2147483647.0 : 4294967295.0;
	if (v < low || v > high || v != Math.floor(v)) {
		return refusal(p, "a " + s.toString() + " literal outside its range");
	}
	return wordConstant(p, type, wordOf(v));
}

function isConstant(p: Spirv, id: int32): boolean {
	return p.constantIds.includes(id);
}

function flattened(p: Spirv, parts: int32[]): int32[] {
	let out: int32[] = [];
	for (const x of parts) {
		const at = p.compositeIds.findIndex((c) => c == x);
		if (at < 0) {
			out.push(x);
			continue;
		}
		for (const y of p.compositeParts[at]) { out.push(y); }
	}
	return out;
}

function composite(p: Spirv, t: ShaderType, parts: int32[]): int32 {
	const type = typeId(p, t);
	if (!parts.some((x) => !isConstant(p, x))) {
		const vector = t.kind == ShaderTypeKind.Vector;
		const flat = vector ? flattened(p, parts) : parts;
		if (!vector || flat.length == t.rows) {
			const id = constant(p, "k" + String(type) + ":" + flat.map((n) => String(n)).join(","),
				OP_CONSTANT_COMPOSITE, type, flat);
			if (!p.compositeIds.includes(id)) {
				p.compositeIds.push(id);
				p.compositeParts.push(flat);
			}
			return id;
		}
	}
	return typed(p, OP_COMPOSITE_CONSTRUCT, type, parts);
}

function splat(p: Spirv, t: ShaderType, part: int32): int32 {
	if (t.kind != ShaderTypeKind.Vector) { return part; }
	let parts: int32[] = [];
	for (let i: int32 = 0; i < t.rows; i++) { parts.push(part); }
	return composite(p, t, parts);
}

function shaped(s: ScalarKind, rows: int32): ShaderType {
	return rows == 1 ? scalarType(s) : vectorType(s, rows);
}

function rowsOf(t: ShaderType): int32 {
	return t.kind == ShaderTypeKind.Vector ? t.rows : 1;
}

function emit(p: Spirv, opcode: int32, operands: int32[]): void {
	if (p.constantOwner != "") {
		refusal(p, "constant '" + p.constantOwner + "' is no constant expression");
		return;
	}
	inst(p.body, opcode, operands);
}

function typed(p: Spirv, opcode: int32, type: int32, operands: int32[]): int32 {
	const id = fresh(p);
	emit(p, opcode, [type, id].concat(operands));
	return id;
}

function ext(p: Spirv, t: ShaderType, instruction: int32, args: int32[]): int32 {
	return typed(p, OP_EXT_INST, typeId(p, t), [p.glsl, instruction].concat(args));
}

function label(p: Spirv, id: int32): void {
	emit(p, OP_LABEL, [id]);
	p.block = id;
	p.terminated = false;
}

function branch(p: Spirv, target: int32): void {
	emit(p, OP_BRANCH, [target]);
	p.terminated = true;
}

function localVariable(p: Spirv, t: ShaderType): int32 {
	const type = typeId(p, t);
	const id = fresh(p);
	inst(p.vars, OP_VARIABLE, [pointerTypeId(p, FUNCTION, type), id, FUNCTION,
		nullConstant(p, type)]);
	return id;
}

function effectful(e: ShaderExpr): boolean {
	return e.kind == ExprKind.Call || e.kind == ExprKind.Intrinsic && isEffect(e.intrinsic) ||
		e.operands.some((o) => effectful(o));
}

function isPlace(p: Spirv, e: ShaderExpr): boolean {
	return match (e.kind) {
		ExprKind.Local | ExprKind.Param | ExprKind.Io | ExprKind.Workgroup |
			ExprKind.BlockMember => true,
		ExprKind.Resource => p.module.resources[e.index].kind == ResourceKind.StorageBuffer,
		ExprKind.Field | ExprKind.Index => isPlace(p, e.operands[0]) && !hoistedMember(p, e.operands[0]),
		ExprKind.Swizzle => e.components.length == 1 && isPlace(p, e.operands[0]) &&
			!hoistedMember(p, e.operands[0]),
		ExprKind.Literal | ExprKind.Constant | ExprKind.Unary | ExprKind.Binary |
			ExprKind.Conditional | ExprKind.Call | ExprKind.Intrinsic | ExprKind.Construct |
			ExprKind.Convert => false,
	};
}

function placeOf(p: Spirv, e: ShaderExpr): Place {
	let place = new Place();
	match (e.kind) {
		ExprKind.Local => {
			place.base = p.localVars[e.index];
			place.storage = FUNCTION;
		},
		ExprKind.Param => {
			place.base = p.paramVars[e.index];
			place.storage = FUNCTION;
		},
		ExprKind.Io => {
			const io = p.module.ios[e.index];
			if (io.stage != p.stage) {
				refusal(p, "io '" + io.name + "' belongs to the " + io.stage.toString() + " stage");
			}
			place.base = p.ioVars[e.index];
			place.storage = io.direction == IoDirection.In ? INPUT : OUTPUT;
			if (io.builtin == Builtin.SampleMask) {
				place.indices.push(intConstant(p, ScalarKind.I32, 0));
			}
		},
		ExprKind.Workgroup => {
			place.base = p.workgroupVars[e.index];
			place.storage = WORKGROUP;
		},
		ExprKind.BlockMember => {
			place.base = p.resourceVars[e.index];
			place.storage = UNIFORM;
			place.indices.push(intConstant(p, ScalarKind.I32,
				p.structSlots[p.module.resources[e.index].type.structIndex][e.member]));
		},
		ExprKind.Resource => {
			place.base = p.resourceVars[e.index];
			place.storage = STORAGE_BUFFER;
			place.indices.push(intConstant(p, ScalarKind.I32, 0));
		},
		ExprKind.Field => {
			place = placeOf(p, e.operands[0]);
			place.indices.push(intConstant(p, ScalarKind.I32, e.index));
		},
		ExprKind.Index => {
			place = placeOf(p, e.operands[0]);
			place.indices.push(value(p, e.operands[1]));
		},
		ExprKind.Swizzle => {
			place = placeOf(p, e.operands[0]);
			place.indices.push(intConstant(p, ScalarKind.I32, e.components[0]));
		},
		ExprKind.Literal | ExprKind.Constant | ExprKind.Unary | ExprKind.Binary |
			ExprKind.Conditional | ExprKind.Call | ExprKind.Intrinsic | ExprKind.Construct |
			ExprKind.Convert => { refusal(p, "a " + e.kind.toString() + " is no variable"); },
	}
	return place;
}

function pointer(p: Spirv, e: ShaderExpr): Place {
	let place = placeOf(p, e);
	place.id = place.indices.length == 0 ? place.base : typed(p, OP_ACCESS_CHAIN,
		pointerTypeId(p, place.storage, typeId(p, e.type)), [place.base].concat(place.indices));
	return place;
}

function load(p: Spirv, e: ShaderExpr): int32 {
	if (hoistedMember(p, e)) { return loadHoisted(p, e); }
	const place = pointer(p, e);
	return typed(p, OP_LOAD, typeId(p, e.type), [place.id]);
}

function extracted(p: Spirv, e: ShaderExpr): int32 {
	const base = e.operands[0];
	const whole = value(p, base);
	const type = typeId(p, e.type);
	if (e.kind == ExprKind.Field) { return typed(p, OP_COMPOSITE_EXTRACT, type, [whole, e.index]); }
	if (e.kind == ExprKind.Swizzle) {
		if (e.components.length == 1) {
			return typed(p, OP_COMPOSITE_EXTRACT, type, [whole, e.components[0]]);
		}
		return typed(p, OP_VECTOR_SHUFFLE, type, [whole, whole].concat(e.components));
	}
	const at = e.operands[1];
	if (at.kind == ExprKind.Literal) {
		return typed(p, OP_COMPOSITE_EXTRACT, type, [whole, at.value as int32]);
	}
	const index = value(p, at);
	if (base.type.kind == ShaderTypeKind.Vector) {
		return typed(p, OP_VECTOR_EXTRACT_DYNAMIC, type, [whole, index]);
	}
	const spill = localVariable(p, base.type);
	emit(p, OP_STORE, [spill, whole]);
	const element = typed(p, OP_ACCESS_CHAIN, pointerTypeId(p, FUNCTION, type), [spill, index]);
	return typed(p, OP_LOAD, type, [element]);
}

function literalId(p: Spirv, t: ShaderType, v: float64): int32 {
	return match (t.kind) {
		ShaderTypeKind.Scalar => scalarConstant(p, t.scalar, v),
		ShaderTypeKind.Vector => splat(p, t, scalarConstant(p, t.scalar, v)),
		ShaderTypeKind.Void | ShaderTypeKind.Matrix | ShaderTypeKind.Array |
			ShaderTypeKind.RuntimeArray | ShaderTypeKind.Struct | ShaderTypeKind.Texture |
			ShaderTypeKind.Sampler | ShaderTypeKind.StorageTexture | ShaderTypeKind.Atomic |
			ShaderTypeKind.ExchangeResult | ShaderTypeKind.ModfResult | ShaderTypeKind.FrexpResult =>
				refusal(p, "a literal of a " + t.kind.toString()),
	};
}

function resourceValue(p: Spirv, e: ShaderExpr): int32 {
	const r = p.module.resources[e.index];
	if (r.kind == ResourceKind.UniformBlock || r.kind == ResourceKind.StorageBuffer) {
		return refusal(p, "resource '" + r.name + "' read as a whole");
	}
	return typed(p, OP_LOAD, typeId(p, e.type), [p.resourceVars[e.index]]);
}

function moduleConstant(p: Spirv, index: int32): int32 {
	if (p.constantValues[index] != 0) { return p.constantValues[index]; }
	const c = p.module.constants[index];
	const outer = p.constantOwner;
	p.constantOwner = c.name;
	const id = value(p, c.value);
	p.constantOwner = outer;
	p.constantValues[index] = id;
	return id;
}

function unary(p: Spirv, e: ShaderExpr): int32 {
	const t = e.type;
	const operand = e.operands[0];
	if (p.constantOwner != "" && e.unary == UnaryOp.Negate && operand.kind == ExprKind.Literal &&
		t.kind == ShaderTypeKind.Scalar && t.scalar != ScalarKind.Bool) {
		return scalarConstant(p, t.scalar, -operand.value);
	}
	const x = value(p, e.operands[0]);
	if (t.kind != ShaderTypeKind.Scalar && t.kind != ShaderTypeKind.Vector) {
		return refusal(p, e.unary.toString() + " of a " + t.kind.toString());
	}
	const type = typeId(p, t);
	return match (e.unary) {
		UnaryOp.Negate => t.scalar == ScalarKind.Bool ? refusal(p, "Negate of a bool") :
			typed(p, t.scalar == ScalarKind.F32 ? OP_F_NEGATE : OP_S_NEGATE, type, [x]),
		UnaryOp.Not => typed(p, t.scalar == ScalarKind.Bool ? OP_LOGICAL_NOT : OP_NOT, type, [x]),
	};
}

function isComparison(op: BinaryOp): boolean {
	return op == BinaryOp.Equal || op == BinaryOp.NotEqual || op == BinaryOp.Less ||
		op == BinaryOp.LessEqual || op == BinaryOp.Greater || op == BinaryOp.GreaterEqual;
}

function isBitwise(op: BinaryOp): boolean {
	return op == BinaryOp.BitAnd || op == BinaryOp.BitOr || op == BinaryOp.BitXor ||
		op == BinaryOp.LogicalAnd || op == BinaryOp.LogicalOr;
}

function binaryOpcode(op: BinaryOp, s: ScalarKind): int32 {
	const f = s == ScalarKind.F32;
	const i = s == ScalarKind.I32;
	const b = s == ScalarKind.Bool;
	return match (op) {
		BinaryOp.Add => f ? OP_F_ADD : OP_I_ADD,
		BinaryOp.Sub => f ? OP_F_SUB : OP_I_SUB,
		BinaryOp.Mul => f ? OP_F_MUL : OP_I_MUL,
		BinaryOp.Div => f ? OP_F_DIV : i ? OP_S_DIV : OP_U_DIV,
		BinaryOp.Mod => f ? OP_F_REM : OP_U_MOD,
		BinaryOp.BitAnd => b ? OP_LOGICAL_AND : OP_BITWISE_AND,
		BinaryOp.BitOr => b ? OP_LOGICAL_OR : OP_BITWISE_OR,
		BinaryOp.BitXor => b ? OP_LOGICAL_NOT_EQUAL : OP_BITWISE_XOR,
		BinaryOp.ShiftLeft => OP_SHIFT_LEFT_LOGICAL,
		BinaryOp.ShiftRight => i ? OP_SHIFT_RIGHT_ARITHMETIC : OP_SHIFT_RIGHT_LOGICAL,
		BinaryOp.LogicalAnd => OP_LOGICAL_AND,
		BinaryOp.LogicalOr => OP_LOGICAL_OR,
		BinaryOp.Equal => b ? OP_LOGICAL_EQUAL : f ? OP_F_ORD_EQUAL : OP_I_EQUAL,
		BinaryOp.NotEqual => b ? OP_LOGICAL_NOT_EQUAL : f ? OP_F_ORD_NOT_EQUAL : OP_I_NOT_EQUAL,
		BinaryOp.Less => f ? OP_F_ORD_LESS_THAN : i ? OP_S_LESS_THAN : OP_U_LESS_THAN,
		BinaryOp.LessEqual => f ? OP_F_ORD_LESS_THAN_EQUAL : i ? OP_S_LESS_THAN_EQUAL :
			OP_U_LESS_THAN_EQUAL,
		BinaryOp.Greater => f ? OP_F_ORD_GREATER_THAN : i ? OP_S_GREATER_THAN : OP_U_GREATER_THAN,
		BinaryOp.GreaterEqual => f ? OP_F_ORD_GREATER_THAN_EQUAL : i ? OP_S_GREATER_THAN_EQUAL :
			OP_U_GREATER_THAN_EQUAL,
	};
}

function columnwise(p: Spirv, op: BinaryOp, t: ShaderType, l: int32, r: int32): int32 {
	const column = typeId(p, vectorType(ScalarKind.F32, t.rows));
	let columns: int32[] = [];
	for (let c: int32 = 0; c < t.columns; c++) {
		const x = typed(p, OP_COMPOSITE_EXTRACT, column, [l, c]);
		const y = typed(p, OP_COMPOSITE_EXTRACT, column, [r, c]);
		columns.push(typed(p, op == BinaryOp.Add ? OP_F_ADD : OP_F_SUB, column, [x, y]));
	}
	return typed(p, OP_COMPOSITE_CONSTRUCT, typeId(p, t), columns);
}

function arithmetic(p: Spirv, op: BinaryOp, t: ShaderType, lt: ShaderType, l: int32,
	rt: ShaderType, r: int32): int32 {
	const type = typeId(p, t);
	const MAT = ShaderTypeKind.Matrix;
	const VEC = ShaderTypeKind.Vector;
	const SCA = ShaderTypeKind.Scalar;
	if (op == BinaryOp.Mul && (lt.kind == MAT || rt.kind == MAT)) {
		if (lt.kind == MAT && rt.kind == MAT) { return typed(p, OP_MATRIX_TIMES_MATRIX, type, [l, r]); }
		if (lt.kind == MAT && rt.kind == VEC) { return typed(p, OP_MATRIX_TIMES_VECTOR, type, [l, r]); }
		if (lt.kind == VEC && rt.kind == MAT) { return typed(p, OP_VECTOR_TIMES_MATRIX, type, [l, r]); }
		if (lt.kind == MAT && rt.kind == SCA) { return typed(p, OP_MATRIX_TIMES_SCALAR, type, [l, r]); }
		if (lt.kind == SCA && rt.kind == MAT) { return typed(p, OP_MATRIX_TIMES_SCALAR, type, [r, l]); }
	}
	if ((op == BinaryOp.Add || op == BinaryOp.Sub) && lt.kind == MAT && rt.kind == MAT) {
		return columnwise(p, op, t, l, r);
	}
	const shapes = (lt.kind == SCA || lt.kind == VEC) && (rt.kind == SCA || rt.kind == VEC);
	if (!shapes) {
		return refusal(p, op.toString() + " of a " + (lt.kind == SCA || lt.kind == VEC ? rt.kind :
			lt.kind).toString());
	}
	const s = lt.scalar;
	if (op == BinaryOp.Mul && s == ScalarKind.F32 && lt.kind != rt.kind) {
		return typed(p, OP_VECTOR_TIMES_SCALAR, type, lt.kind == VEC ? [l, r] : [r, l]);
	}
	const rows = lt.kind == VEC ? lt.rows : rowsOf(rt);
	const a = lt.kind == SCA && rows > 1 ? splat(p, vectorType(lt.scalar, rows), l) : l;
	const b = rt.kind == SCA && rows > 1 ? splat(p, vectorType(rt.scalar, rows), r) : r;
	if (isComparison(op)) {
		if (s == ScalarKind.Bool && op != BinaryOp.Equal && op != BinaryOp.NotEqual) {
			return refusal(p, op.toString() + " of bools");
		}
		const compared = typed(p, binaryOpcode(op, s), typeId(p, shaped(ScalarKind.Bool, rows)),
			[a, b]);
		if (t.kind == VEC || rows == 1) { return compared; }
		if (op == BinaryOp.Equal) { return typed(p, OP_ALL, type, [compared]); }
		if (op == BinaryOp.NotEqual) { return typed(p, OP_ANY, type, [compared]); }
		return refusal(p, op.toString() + " of vectors into one bool");
	}
	if (s == ScalarKind.Bool && !isBitwise(op)) { return refusal(p, op.toString() + " of bools"); }
	if (op == BinaryOp.Mod && s == ScalarKind.I32) {
		const quotient = typed(p, OP_S_DIV, type, [a, b]);
		const product = typed(p, OP_I_MUL, type, [quotient, b]);
		return typed(p, OP_I_SUB, type, [a, product]);
	}
	return typed(p, binaryOpcode(op, s), type, [a, b]);
}

function binary(p: Spirv, e: ShaderExpr): int32 {
	const o = e.operands;
	if (e.binary == BinaryOp.LogicalAnd || e.binary == BinaryOp.LogicalOr) {
		return shortCircuit(p, e);
	}
	const l = value(p, o[0]);
	const r = value(p, o[1]);
	return arithmetic(p, e.binary, e.type, o[0].type, l, o[1].type, r);
}

function shortCircuit(p: Spirv, e: ShaderExpr): int32 {
	const and = e.binary == BinaryOp.LogicalAnd;
	const type = typeId(p, e.type);
	const l = value(p, e.operands[0]);
	if (!effectful(e.operands[1])) {
		const r = value(p, e.operands[1]);
		return typed(p, and ? OP_LOGICAL_AND : OP_LOGICAL_OR, type, [l, r]);
	}
	const from = p.block;
	const right = fresh(p);
	const merge = fresh(p);
	emit(p, OP_SELECTION_MERGE, [merge, 0]);
	emit(p, OP_BRANCH_CONDITIONAL, and ? [l, right, merge] : [l, merge, right]);
	label(p, right);
	const r = value(p, e.operands[1]);
	const fromRight = p.block;
	branch(p, merge);
	label(p, merge);
	return typed(p, OP_PHI, type, [boolConstant(p, !and), from, r, fromRight]);
}

function conditionFor(p: Spirv, t: ShaderType, conditionType: ShaderType, c: int32): int32 {
	if (t.kind == ShaderTypeKind.Vector && conditionType.kind == ShaderTypeKind.Scalar) {
		return splat(p, vectorType(ScalarKind.Bool, t.rows), c);
	}
	return c;
}

function conditional(p: Spirv, e: ShaderExpr): int32 {
	const o = e.operands;
	const t = e.type;
	const type = typeId(p, t);
	const c = value(p, o[0]);
	const plain = t.kind == ShaderTypeKind.Scalar || t.kind == ShaderTypeKind.Vector;
	if (plain && !effectful(o[1]) && !effectful(o[2])) {
		const yes = value(p, o[1]);
		const no = value(p, o[2]);
		return typed(p, OP_SELECT, type, [conditionFor(p, t, o[0].type, c), yes, no]);
	}
	const yesLabel = fresh(p);
	const noLabel = fresh(p);
	const merge = fresh(p);
	emit(p, OP_SELECTION_MERGE, [merge, 0]);
	emit(p, OP_BRANCH_CONDITIONAL, [c, yesLabel, noLabel]);
	label(p, yesLabel);
	const yes = value(p, o[1]);
	const fromYes = p.block;
	branch(p, merge);
	label(p, noLabel);
	const no = value(p, o[2]);
	const fromNo = p.block;
	branch(p, merge);
	label(p, merge);
	return typed(p, OP_PHI, type, [yes, fromYes, no, fromNo]);
}

function call(p: Spirv, e: ShaderExpr): int32 {
	const args = e.operands.map((a) => value(p, a));
	const f = p.module.functions[e.index];
	return typed(p, OP_FUNCTION_CALL, typeId(p, f.result), [p.functionIds[e.index]].concat(args));
}

function construct(p: Spirv, e: ShaderExpr): int32 {
	const t = e.type;
	const o = e.operands;
	if (o.length == 0) { return nullConstant(p, typeId(p, t)); }
	const parts = o.map((a) => value(p, a));
	if (o.length == 1 && sameShaderType(o[0].type, t)) { return parts[0]; }
	if (t.kind == ShaderTypeKind.Vector) {
		if (o.length == 1 && o[0].type.kind == ShaderTypeKind.Scalar) { return splat(p, t, parts[0]); }
		if (o.length == 1 && o[0].type.kind == ShaderTypeKind.Vector && o[0].type.rows == t.rows) {
			return converted(p, o[0].type, t, parts[0]);
		}
		let components: int32 = 0;
		for (const a of o) { components += rowsOf(a.type); }
		if (components != t.rows) {
			return refusal(p, "a vector of " + String(t.rows) + " built from " + String(components) +
				" components");
		}
		return composite(p, t, parts);
	}
	if (t.kind == ShaderTypeKind.Matrix) {
		if (o.length == t.columns && !o.some((a) => a.type.kind != ShaderTypeKind.Vector)) {
			return composite(p, t, parts);
		}
		if (o.length == t.columns * t.rows && !o.some((a) => a.type.kind != ShaderTypeKind.Scalar)) {
			const column = vectorType(ScalarKind.F32, t.rows);
			let columns: int32[] = [];
			for (let c: int32 = 0; c < t.columns; c++) {
				columns.push(composite(p, column, parts.slice(c * t.rows, (c + 1) * t.rows)));
			}
			return composite(p, t, columns);
		}
		return refusal(p, "a matrix built from " + String(o.length) + " operands");
	}
	if (t.kind == ShaderTypeKind.Struct || t.kind == ShaderTypeKind.Array ||
		t.kind == ShaderTypeKind.ExchangeResult) {
		return composite(p, t, parts);
	}
	return refusal(p, "a Construct of a " + t.kind.toString());
}

function convert(p: Spirv, e: ShaderExpr): int32 {
	return converted(p, e.operands[0].type, e.type, value(p, e.operands[0]));
}

function converted(p: Spirv, from: ShaderType, t: ShaderType, x: int32): int32 {
	const numeric = t.kind == ShaderTypeKind.Scalar || t.kind == ShaderTypeKind.Vector;
	if (!numeric || from.kind != t.kind || rowsOf(from) != rowsOf(t)) {
		return refusal(p, "a conversion from a " + from.kind.toString() + " to a " +
			t.kind.toString());
	}
	const s = from.scalar;
	const d = t.scalar;
	const type = typeId(p, t);
	if (s == d) { return x; }
	if (d == ScalarKind.Bool) {
		const zero = splat(p, from, scalarConstant(p, s, 0.0));
		return typed(p, s == ScalarKind.F32 ? OP_F_UNORD_NOT_EQUAL : OP_I_NOT_EQUAL, type, [x, zero]);
	}
	if (s == ScalarKind.Bool) {
		const one = splat(p, t, scalarConstant(p, d, 1.0));
		const zero = splat(p, t, scalarConstant(p, d, 0.0));
		return typed(p, OP_SELECT, type, [x, one, zero]);
	}
	if (s == ScalarKind.F32) {
		const signed = d == ScalarKind.I32;
		const low = splat(p, from, scalarConstant(p, ScalarKind.F32, signed ? -2147483648.0 : 0.0));
		const high = splat(p, from, scalarConstant(p, ScalarKind.F32,
			signed ? 2147483520.0 : 4294967040.0));
		const clamped = ext(p, from, GLSL_F_CLAMP, [x, low, high]);
		return typed(p, signed ? OP_CONVERT_F_TO_S : OP_CONVERT_F_TO_U, type, [clamped]);
	}
	if (d == ScalarKind.F32) {
		return typed(p, s == ScalarKind.I32 ? OP_CONVERT_S_TO_F : OP_CONVERT_U_TO_F, type, [x]);
	}
	return typed(p, OP_BITCAST, type, [x]);
}

function glslNumber(op: Intrinsic): int32 {
	if (op == Intrinsic.Round) { return 2; }
	if (op == Intrinsic.Trunc) { return 3; }
	if (op == Intrinsic.Floor) { return 8; }
	if (op == Intrinsic.Ceil) { return 9; }
	if (op == Intrinsic.Fract) { return 10; }
	if (op == Intrinsic.Radians) { return 11; }
	if (op == Intrinsic.Degrees) { return 12; }
	if (op == Intrinsic.Sin) { return 13; }
	if (op == Intrinsic.Cos) { return 14; }
	if (op == Intrinsic.Tan) { return 15; }
	if (op == Intrinsic.Asin) { return 16; }
	if (op == Intrinsic.Acos) { return 17; }
	if (op == Intrinsic.Atan) { return 18; }
	if (op == Intrinsic.Sinh) { return 19; }
	if (op == Intrinsic.Cosh) { return 20; }
	if (op == Intrinsic.Tanh) { return 21; }
	if (op == Intrinsic.Asinh) { return 22; }
	if (op == Intrinsic.Acosh) { return 23; }
	if (op == Intrinsic.Atanh) { return 24; }
	if (op == Intrinsic.Atan2) { return 25; }
	if (op == Intrinsic.Pow) { return 26; }
	if (op == Intrinsic.Exp) { return 27; }
	if (op == Intrinsic.Log) { return 28; }
	if (op == Intrinsic.Exp2) { return 29; }
	if (op == Intrinsic.Log2) { return 30; }
	if (op == Intrinsic.Sqrt) { return 31; }
	if (op == Intrinsic.InverseSqrt) { return 32; }
	if (op == Intrinsic.Determinant) { return 33; }
	if (op == Intrinsic.Mix) { return 46; }
	if (op == Intrinsic.Step) { return 48; }
	if (op == Intrinsic.Smoothstep) { return 49; }
	if (op == Intrinsic.Fma) { return 50; }
	if (op == Intrinsic.Ldexp) { return 53; }
	if (op == Intrinsic.Modf) { return 36; }
	if (op == Intrinsic.Frexp) { return 52; }
	if (op == Intrinsic.Pack4x8Snorm) { return 54; }
	if (op == Intrinsic.Pack4x8Unorm) { return 55; }
	if (op == Intrinsic.Pack2x16Snorm) { return 56; }
	if (op == Intrinsic.Pack2x16Unorm) { return 57; }
	if (op == Intrinsic.Pack2x16Float) { return 58; }
	if (op == Intrinsic.Unpack2x16Snorm) { return 60; }
	if (op == Intrinsic.Unpack2x16Unorm) { return 61; }
	if (op == Intrinsic.Unpack2x16Float) { return 62; }
	if (op == Intrinsic.Unpack4x8Snorm) { return 63; }
	if (op == Intrinsic.Unpack4x8Unorm) { return 64; }
	if (op == Intrinsic.Length) { return 66; }
	if (op == Intrinsic.Distance) { return 67; }
	if (op == Intrinsic.Cross) { return 68; }
	if (op == Intrinsic.Normalize) { return 69; }
	if (op == Intrinsic.FaceForward) { return 70; }
	if (op == Intrinsic.Reflect) { return 71; }
	if (op == Intrinsic.Refract) { return 72; }
	if (op == Intrinsic.FirstTrailingBit) { return GLSL_FIND_I_LSB; }
	return 0;
}

function controlledDerivative(p: Spirv, op: Intrinsic): int32 {
	return match (op) {
		Intrinsic.DpdxCoarse => OP_DPDX_COARSE,
		Intrinsic.DpdxFine => OP_DPDX_FINE,
		Intrinsic.DpdyCoarse => OP_DPDY_COARSE,
		Intrinsic.DpdyFine => OP_DPDY_FINE,
		Intrinsic.FwidthCoarse => OP_FWIDTH_COARSE,
		Intrinsic.FwidthFine => OP_FWIDTH_FINE,
		_ => refusal(p, op.toString() + " is no coarse or fine derivative"),
	};
}

function spreads(op: Intrinsic): boolean {
	return op == Intrinsic.Min || op == Intrinsic.Max || op == Intrinsic.Clamp ||
		op == Intrinsic.Mix || op == Intrinsic.Step || op == Intrinsic.Smoothstep ||
		op == Intrinsic.Fma || op == Intrinsic.Pow || op == Intrinsic.Atan2;
}

function bits(p: Spirv, e: ShaderExpr, args: int32[]): int32 {
	const insert = e.intrinsic == Intrinsic.InsertBits;
	const u32 = scalarType(ScalarKind.U32);
	const width = intConstant(p, ScalarKind.U32, 32);
	const offset = ext(p, u32, GLSL_U_MIN, [args[insert ? 2 : 1], width]);
	const room = typed(p, OP_I_SUB, typeId(p, u32), [width, offset]);
	const count = ext(p, u32, GLSL_U_MIN, [args[insert ? 3 : 2], room]);
	const type = typeId(p, e.type);
	if (insert) { return typed(p, OP_BIT_FIELD_INSERT, type, [args[0], args[1], offset, count]); }
	const signed = e.operands[0].type.scalar == ScalarKind.I32;
	return typed(p, signed ? OP_BIT_FIELD_S_EXTRACT : OP_BIT_FIELD_U_EXTRACT, type,
		[args[0], offset, count]);
}

function math(p: Spirv, e: ShaderExpr): int32 {
	const op = e.intrinsic;
	const t = e.type;
	const s = e.operands[0].type.scalar;
	let args: int32[] = [];
	for (const a of e.operands) {
		const x = value(p, a);
		const widen = spreads(op) && t.kind == ShaderTypeKind.Vector &&
			a.type.kind == ShaderTypeKind.Scalar;
		args.push(widen ? splat(p, vectorType(a.type.scalar, t.rows), x) : x);
	}
	const f = s == ScalarKind.F32;
	const i = s == ScalarKind.I32;
	const type = typeId(p, t);
	if (op == Intrinsic.Abs) {
		return f ? ext(p, t, GLSL_F_ABS, args) : i ? ext(p, t, GLSL_S_ABS, args) :
			typed(p, OP_COPY_OBJECT, type, args);
	}
	if (op == Intrinsic.Sign) {
		return f ? ext(p, t, GLSL_F_SIGN, args) : i ? ext(p, t, GLSL_S_SIGN, args) :
			refusal(p, "Sign of a u32");
	}
	if (op == Intrinsic.Min) { return ext(p, t, f ? GLSL_F_MIN : i ? GLSL_S_MIN : GLSL_U_MIN, args); }
	if (op == Intrinsic.Max) { return ext(p, t, f ? GLSL_F_MAX : i ? GLSL_S_MAX : GLSL_U_MAX, args); }
	if (op == Intrinsic.Clamp) {
		if (f) { return ext(p, t, GLSL_F_CLAMP, args); }
		const raised = ext(p, t, i ? GLSL_S_MAX : GLSL_U_MAX, [args[0], args[1]]);
		return ext(p, t, i ? GLSL_S_MIN : GLSL_U_MIN, [raised, args[2]]);
	}
	if (op == Intrinsic.Saturate) {
		const zero = splat(p, t, scalarConstant(p, ScalarKind.F32, 0.0));
		const one = splat(p, t, scalarConstant(p, ScalarKind.F32, 1.0));
		return ext(p, t, GLSL_F_CLAMP, [args[0], zero, one]);
	}
	if (op == Intrinsic.Dot) {
		return f ? typed(p, OP_DOT, type, args) :
			refusal(p, "Dot of integer vectors is not printed yet");
	}
	if (op == Intrinsic.Transpose) { return typed(p, OP_TRANSPOSE, type, args); }
	if (op == Intrinsic.Dpdx) { return typed(p, OP_DPDX, type, args); }
	if (op == Intrinsic.Dpdy) { return typed(p, OP_DPDY, type, args); }
	if (op == Intrinsic.Fwidth) { return typed(p, OP_FWIDTH, type, args); }
	if (isDerivative(op)) {
		need(p, CAP_DERIVATIVE_CONTROL);
		return typed(p, controlledDerivative(p, op), type, args);
	}
	if (op == Intrinsic.Bitcast) { return typed(p, OP_BITCAST, type, args); }
	if (op == Intrinsic.CountLeadingZeros) {
		const highest = ext(p, t, GLSL_FIND_U_MSB, args);
		return typed(p, OP_I_SUB, type, [splat(p, t, intConstant(p, t.scalar, 31)), highest]);
	}
	if (op == Intrinsic.CountTrailingZeros) {
		const lowest = ext(p, t, GLSL_FIND_I_LSB, args);
		return ext(p, t, GLSL_U_MIN, [splat(p, t, intConstant(p, t.scalar, 32)), lowest]);
	}
	if (op == Intrinsic.CountOneBits) { return typed(p, OP_BIT_COUNT, type, args); }
	if (op == Intrinsic.ReverseBits) { return typed(p, OP_BIT_REVERSE, type, args); }
	if (op == Intrinsic.FirstLeadingBit) {
		return ext(p, t, i ? GLSL_FIND_S_MSB : GLSL_FIND_U_MSB, args);
	}
	if (op == Intrinsic.ExtractBits || op == Intrinsic.InsertBits) { return bits(p, e, args); }
	const instruction = glslNumber(op);
	if (instruction == 0) { return refusal(p, op.toString() + " is not printed yet"); }
	return ext(p, t, instruction, args);
}

function selected(p: Spirv, e: ShaderExpr): int32 {
	const o = e.operands;
	const t = e.type;
	if (t.kind != ShaderTypeKind.Scalar && t.kind != ShaderTypeKind.Vector) {
		return refusal(p, "a Select of a " + t.kind.toString());
	}
	const no = value(p, o[0]);
	const yes = value(p, o[1]);
	const c = value(p, o[2]);
	return typed(p, OP_SELECT, typeId(p, t), [conditionFor(p, t, o[2].type, c), yes, no]);
}

function upperLeft(p: Spirv, e: ShaderExpr): int32 {
	const source = e.operands[0];
	const whole = value(p, source);
	const wide = typeId(p, vectorType(ScalarKind.F32, source.type.rows));
	const narrow = typeId(p, vectorType(ScalarKind.F32, 3));
	let columns: int32[] = [];
	for (let c: int32 = 0; c < 3; c++) {
		const column = typed(p, OP_COMPOSITE_EXTRACT, wide, [whole, c]);
		columns.push(typed(p, OP_VECTOR_SHUFFLE, narrow, [column, column, 0, 1, 2]));
	}
	return typed(p, OP_COMPOSITE_CONSTRUCT, typeId(p, e.type), columns);
}

function barrier(p: Spirv, storage: boolean): int32 {
	emit(p, OP_CONTROL_BARRIER, [
		intConstant(p, ScalarKind.U32, 2),
		intConstant(p, ScalarKind.U32, storage ? 1 : 2),
		intConstant(p, ScalarKind.U32, storage ? 72 : 264),
	]);
	return 0;
}

function atomicOpcode(op: Intrinsic, s: ScalarKind): int32 {
	const signed = s == ScalarKind.I32;
	if (op == Intrinsic.AtomicAdd) { return OP_ATOMIC_I_ADD; }
	if (op == Intrinsic.AtomicSub) { return OP_ATOMIC_I_SUB; }
	if (op == Intrinsic.AtomicMax) { return signed ? OP_ATOMIC_S_MAX : OP_ATOMIC_U_MAX; }
	if (op == Intrinsic.AtomicMin) { return signed ? OP_ATOMIC_S_MIN : OP_ATOMIC_U_MIN; }
	if (op == Intrinsic.AtomicAnd) { return OP_ATOMIC_AND; }
	if (op == Intrinsic.AtomicOr) { return OP_ATOMIC_OR; }
	if (op == Intrinsic.AtomicXor) { return OP_ATOMIC_XOR; }
	if (op == Intrinsic.AtomicExchange) { return OP_ATOMIC_EXCHANGE; }
	return 0;
}

function atomic(p: Spirv, e: ShaderExpr): int32 {
	const op = e.intrinsic;
	const target = e.operands[0];
	if (!isPlace(p, target)) { return refusal(p, op.toString() + " of a value that is no variable"); }
	const place = pointer(p, target);
	const scope = intConstant(p, ScalarKind.U32, place.storage == WORKGROUP ? 2 : 1);
	const relaxed = intConstant(p, ScalarKind.U32, 0);
	const s = target.type.scalar;
	const type = scalarTypeId(p, s);
	const rest = e.operands.slice(1).map((a) => value(p, a));
	if (op == Intrinsic.AtomicLoad) {
		return typed(p, OP_ATOMIC_LOAD, type, [place.id, scope, relaxed]);
	}
	if (op == Intrinsic.AtomicStore) {
		emit(p, OP_ATOMIC_STORE, [place.id, scope, relaxed, rest[0]]);
		return 0;
	}
	if (op == Intrinsic.AtomicCompareExchangeWeak) {
		const old = typed(p, OP_ATOMIC_COMPARE_EXCHANGE, type,
			[place.id, scope, relaxed, relaxed, rest[1], rest[0]]);
		const exchanged = typed(p, OP_I_EQUAL, scalarTypeId(p, ScalarKind.Bool), [old, rest[0]]);
		return typed(p, OP_COMPOSITE_CONSTRUCT, typeId(p, e.type), [old, exchanged]);
	}
	const opcode = atomicOpcode(op, s);
	if (opcode == 0) { return refusal(p, op.toString() + " is not printed yet"); }
	return typed(p, opcode, type, [place.id, scope, relaxed, rest[0]]);
}

function handle(p: Spirv, e: ShaderExpr): int32 {
	if (e.kind != ExprKind.Resource) {
		return refusal(p, "a texture or sampler that is no resource binding");
	}
	return typed(p, OP_LOAD, typeId(p, e.type), [p.resourceVars[e.index]]);
}

function samplerKind(p: Spirv, e: ShaderExpr): SamplerType {
	if (e.kind != ExprKind.Resource) { return SamplerType.Filtering; }
	return p.module.resources[e.index].samplerType;
}

function sampledImage(p: Spirv, texture: ShaderExpr, sampler: ShaderExpr): int32 {
	const image = handle(p, texture);
	const s = handle(p, sampler);
	const imageType = typeId(p, texture.type);
	const type = declared(p, "si" + String(imageType), OP_TYPE_SAMPLED_IMAGE, [imageType]);
	return typed(p, OP_SAMPLED_IMAGE, type, [image, s]);
}

function coordinates(p: Spirv, at: ShaderExpr, layered: boolean, layer: ShaderExpr): int32 {
	const c = value(p, at);
	if (!layered) { return c; }
	const s = at.type.scalar;
	const raw = value(p, layer);
	const from = layer.type.scalar;
	const l = from == s ? raw : s == ScalarKind.F32 ?
		typed(p, from == ScalarKind.I32 ? OP_CONVERT_S_TO_F : OP_CONVERT_U_TO_F,
			scalarTypeId(p, s), [raw]) :
		typed(p, OP_BITCAST, scalarTypeId(p, s), [raw]);
	return typed(p, OP_COMPOSITE_CONSTRUCT, typeId(p, vectorType(s, rowsOf(at.type) + 1)), [c, l]);
}

function texel(p: Spirv, t: ShaderType, wanted: ShaderType): int32 {
	return typeId(p, isDepthShape(t.shape) ? vectorType(ScalarKind.F32, 4) : wanted);
}

function depthTexel(p: Spirv, t: ShaderType, e: ShaderExpr, fetched: int32): int32 {
	if (!isDepthShape(t.shape)) { return fetched; }
	return typed(p, OP_COMPOSITE_EXTRACT, typeId(p, e.type), [fetched, 0]);
}

function floatLevel(p: Spirv, level: ShaderExpr): int32 {
	const x = value(p, level);
	if (level.type.scalar == ScalarKind.F32) { return x; }
	return typed(p, level.type.scalar == ScalarKind.I32 ? OP_CONVERT_S_TO_F : OP_CONVERT_U_TO_F,
		scalarTypeId(p, ScalarKind.F32), [x]);
}

// The image operands of a sample: their mask, then one id per bit in the order of the bits, the
// constant offset's last. The offset of a sample is a constant composite, as the image operand needs.
function imageOperands(p: Spirv, e: ShaderExpr, mask: int32, ids: int32[]): int32[] {
	if (!hasOffset(e)) { return mask == 0 ? [] : [mask].concat(ids); }
	return [mask | IMAGE_CONST_OFFSET].concat(ids).concat([value(p, offsetOf(e))]);
}

function sample(p: Spirv, e: ShaderExpr): int32 {
	const op = e.intrinsic;
	const o = e.operands;
	const name = op.toString();
	if (o.length < 3 || o[0].type.kind != ShaderTypeKind.Texture ||
		o[1].type.kind != ShaderTypeKind.Sampler) {
		return refusal(p, name + " takes a texture, a sampler and coordinates first");
	}
	const t = o[0].type;
	if (t.shape == TextureShape.Multisampled2d) {
		return refusal(p, name + " of a multisampled texture");
	}
	if (samplerKind(p, o[1]) == SamplerType.Comparison) {
		return refusal(p, name + " through a comparison sampler");
	}
	const layered = isArrayTexture(t);
	const next = layered ? 4 : 3;
	const image = sampledImage(p, o[0], o[1]);
	const at = coordinates(p, o[2], layered, o[layered ? 3 : 2]);
	const type = texel(p, t, e.type);
	let fetched = 0;
	if (op == Intrinsic.TextureSample) {
		fetched = p.stage == ShaderStage.Fragment ?
			typed(p, OP_IMAGE_SAMPLE_IMPLICIT_LOD, type,
				[image, at].concat(imageOperands(p, e, 0, []))) :
			typed(p, OP_IMAGE_SAMPLE_EXPLICIT_LOD, type, [image, at].concat(
				imageOperands(p, e, IMAGE_LOD, [scalarConstant(p, ScalarKind.F32, 0.0)])));
	} else if (op == Intrinsic.TextureSampleLevel) {
		fetched = typed(p, OP_IMAGE_SAMPLE_EXPLICIT_LOD, type, [image, at].concat(
			imageOperands(p, e, IMAGE_LOD, [floatLevel(p, o[next])])));
	} else if (op == Intrinsic.TextureSampleBias) {
		fetched = typed(p, OP_IMAGE_SAMPLE_IMPLICIT_LOD, type, [image, at].concat(
			imageOperands(p, e, IMAGE_BIAS, [value(p, o[next])])));
	} else {
		const dx = value(p, o[next]);
		const dy = value(p, o[next + 1]);
		fetched = typed(p, OP_IMAGE_SAMPLE_EXPLICIT_LOD, type, [image, at].concat(
			imageOperands(p, e, IMAGE_GRAD, [dx, dy])));
	}
	return depthTexel(p, t, e, fetched);
}

function compare(p: Spirv, e: ShaderExpr): int32 {
	const o = e.operands;
	const name = e.intrinsic.toString();
	const level = e.intrinsic == Intrinsic.TextureSampleCompareLevel;
	const layered = o.length > 0 && o[0].type.shape == TextureShape.Depth2dArray;
	const base = layered ? 5 : 4;
	if (o.length != base && o.length != base + 1 || o[0].type.kind != ShaderTypeKind.Texture ||
		o[1].type.kind != ShaderTypeKind.Sampler) {
		return refusal(p, name + " takes a texture, a sampler, coordinates, for an array texture " +
			"a layer, a depth reference, and an optional constant offset");
	}
	if (o[1].kind != ExprKind.Resource || samplerKind(p, o[1]) != SamplerType.Comparison) {
		return refusal(p, name + " through a sampler that is no comparison sampler binding");
	}
	if (!isDepthShape(o[0].type.shape)) {
		return refusal(p, name + " of a " + o[0].type.shape.toString() + " texture, which holds " +
			"no depth");
	}
	const image = sampledImage(p, o[0], o[1]);
	const at = coordinates(p, o[2], layered, o[3]);
	const reference = value(p, o[layered ? 4 : 3]);
	const type = scalarTypeId(p, ScalarKind.F32);
	if (!level && p.stage == ShaderStage.Fragment) {
		return typed(p, OP_IMAGE_SAMPLE_DREF_IMPLICIT_LOD, type,
			[image, at, reference].concat(imageOperands(p, e, 0, [])));
	}
	return typed(p, OP_IMAGE_SAMPLE_DREF_EXPLICIT_LOD, type, [image, at, reference].concat(
		imageOperands(p, e, IMAGE_LOD, [scalarConstant(p, ScalarKind.F32, 0.0)])));
}

function withoutSamplers(args: ShaderExpr[]): ShaderExpr[] {
	return args.filter((a) => a.type.kind != ShaderTypeKind.Sampler);
}

function texelLoad(p: Spirv, e: ShaderExpr): int32 {
	const o = withoutSamplers(e.operands);
	const t = o[0].type;
	const layered = isArrayTexture(t);
	if (t.kind == ShaderTypeKind.StorageTexture) {
		const image = handle(p, o[0]);
		const at = coordinates(p, o[1], layered, o[layered ? 2 : 1]);
		return typed(p, OP_IMAGE_READ, typeId(p, e.type), [image, at]);
	}
	if (t.kind != ShaderTypeKind.Texture) { return refusal(p, "TextureLoad of a " + t.kind.toString()); }
	if (o.length < (layered ? 4 : 3)) {
		return refusal(p, "TextureLoad of a sampled texture takes a level");
	}
	const image = handle(p, o[0]);
	const at = coordinates(p, o[1], layered, o[layered ? 2 : 1]);
	const extra = value(p, o[layered ? 3 : 2]);
	const operand = t.shape == TextureShape.Multisampled2d ? IMAGE_SAMPLE : IMAGE_LOD;
	const fetched = typed(p, OP_IMAGE_FETCH, texel(p, t, e.type), [image, at, operand, extra]);
	return depthTexel(p, t, e, fetched);
}

function texelStore(p: Spirv, e: ShaderExpr): int32 {
	const o = e.operands;
	const t = o[0].type;
	if (t.kind != ShaderTypeKind.StorageTexture) {
		return refusal(p, "TextureStore to a " + t.kind.toString());
	}
	const layered = isArrayTexture(t);
	const image = handle(p, o[0]);
	const at = coordinates(p, o[1], layered, o[layered ? 2 : 1]);
	const written = value(p, o[layered ? 3 : 2]);
	emit(p, OP_IMAGE_WRITE, [image, at, written]);
	return 0;
}

function dimensions(p: Spirv, e: ShaderExpr): int32 {
	const o = withoutSamplers(e.operands);
	const t = o[0].type;
	const dims: int32 = t.shape == TextureShape.D3 ? 3 : 2;
	if (e.type.kind != ShaderTypeKind.Vector || e.type.rows != dims) {
		return refusal(p, "TextureDimensions into a " + e.type.kind.toString() + " of " +
			String(rowsOf(e.type)));
	}
	need(p, CAP_IMAGE_QUERY);
	const layered = isArrayTexture(t);
	const queried = vectorType(ScalarKind.U32, layered ? dims + 1 : dims);
	const image = handle(p, o[0]);
	const lod = t.kind == ShaderTypeKind.Texture && t.shape != TextureShape.Multisampled2d;
	const size = lod ?
		typed(p, OP_IMAGE_QUERY_SIZE_LOD, typeId(p, queried),
			[image, o.length > 1 ? value(p, o[1]) : intConstant(p, ScalarKind.I32, 0)]) :
		typed(p, OP_IMAGE_QUERY_SIZE, typeId(p, queried), [image]);
	const unsigned = vectorType(ScalarKind.U32, dims);
	const kept = !layered ? size : typed(p, OP_VECTOR_SHUFFLE, typeId(p, unsigned),
		dims == 3 ? [size, size, 0, 1, 2] : [size, size, 0, 1]);
	return e.type.scalar == ScalarKind.U32 ? kept : typed(p, OP_BITCAST, typeId(p, e.type), [kept]);
}

function sampleCount(p: Spirv, e: ShaderExpr): int32 {
	const t = e.operands[0].type;
	if (t.kind != ShaderTypeKind.Texture || t.shape != TextureShape.Multisampled2d) {
		return refusal(p, "TextureNumSamples takes a multisampled texture");
	}
	need(p, CAP_IMAGE_QUERY);
	const count = typed(p, OP_IMAGE_QUERY_SAMPLES, typeId(p, scalarType(ScalarKind.U32)),
		[handle(p, e.operands[0])]);
	return e.type.scalar == ScalarKind.U32 ? count : typed(p, OP_BITCAST, typeId(p, e.type), [count]);
}

function intrinsic(p: Spirv, e: ShaderExpr): int32 {
	const op = e.intrinsic;
	const o = e.operands;
	if (op == Intrinsic.Any || op == Intrinsic.All) {
		return typed(p, op == Intrinsic.Any ? OP_ANY : OP_ALL, typeId(p, e.type), [value(p, o[0])]);
	}
	if (isMath(op)) { return math(p, e); }
	if (isAtomic(op)) { return atomic(p, e); }
	if (op == Intrinsic.Select) { return selected(p, e); }
	if (isComponentCompare(op)) {
		const l = value(p, o[0]);
		const r = value(p, o[1]);
		return arithmetic(p, componentCompare(op), e.type, o[0].type, l, o[1].type, r);
	}
	if (op == Intrinsic.UpperLeft3x3) { return upperLeft(p, e); }
	if (op == Intrinsic.Inverse) {
		if (e.type.kind != ShaderTypeKind.Matrix || e.type.columns != e.type.rows) {
			return refusal(p, "inverse of a " + e.type.kind.toString() + " that is no square matrix");
		}
		return ext(p, e.type, GLSL_MATRIX_INVERSE, [value(p, o[0])]);
	}
	if (op == Intrinsic.WorkgroupBarrier || op == Intrinsic.StorageBarrier) {
		return barrier(p, op == Intrinsic.StorageBarrier);
	}
	if (op == Intrinsic.TextureSample || op == Intrinsic.TextureSampleLevel ||
		op == Intrinsic.TextureSampleBias || op == Intrinsic.TextureSampleGrad) {
		return sample(p, e);
	}
	if (op == Intrinsic.TextureSampleCompare || op == Intrinsic.TextureSampleCompareLevel) {
		return compare(p, e);
	}
	if (op == Intrinsic.TextureLoad) { return texelLoad(p, e); }
	if (op == Intrinsic.TextureStore) { return texelStore(p, e); }
	if (op == Intrinsic.TextureDimensions) { return dimensions(p, e); }
	if (op == Intrinsic.TextureNumSamples) { return sampleCount(p, e); }
	return refusal(p, op.toString() + " is not printed yet");
}

function value(p: Spirv, e: ShaderExpr): int32 {
	if (p.error != "") { return 0; }
	return match (e.kind) {
		ExprKind.Literal => literalId(p, e.type, e.value),
		ExprKind.Local | ExprKind.Param | ExprKind.Io | ExprKind.Workgroup |
			ExprKind.BlockMember => load(p, e),
		ExprKind.Resource => resourceValue(p, e),
		ExprKind.Constant => moduleConstant(p, e.index),
		ExprKind.Unary => unary(p, e),
		ExprKind.Binary => binary(p, e),
		ExprKind.Conditional => conditional(p, e),
		ExprKind.Call => call(p, e),
		ExprKind.Intrinsic => intrinsic(p, e),
		ExprKind.Construct => construct(p, e),
		ExprKind.Convert => convert(p, e),
		ExprKind.Field | ExprKind.Swizzle | ExprKind.Index =>
			isPlace(p, e) ? load(p, e) : extracted(p, e),
	};
}

function assignBinary(op: AssignOp): BinaryOp {
	if (op == AssignOp.Sub || op == AssignOp.Decrement) { return BinaryOp.Sub; }
	if (op == AssignOp.Mul) { return BinaryOp.Mul; }
	if (op == AssignOp.Div) { return BinaryOp.Div; }
	if (op == AssignOp.Mod) { return BinaryOp.Mod; }
	return BinaryOp.Add;
}

function writable(p: Spirv, target: ShaderExpr): boolean {
	const root = rootOf(target);
	const m = p.module;
	if (root.kind == ExprKind.Io && m.ios[root.index].direction == IoDirection.In) {
		refusal(p, "a write to input io '" + m.ios[root.index].name + "'");
		return false;
	}
	if (root.kind == ExprKind.BlockMember) {
		refusal(p, "a write to uniform block '" + m.resources[root.index].name + "'");
		return false;
	}
	if (root.kind == ExprKind.Resource && m.resources[root.index].access == Access.Read) {
		refusal(p, "a write to read-only storage buffer '" + m.resources[root.index].name + "'");
		return false;
	}
	return true;
}

function swizzleAssign(p: Spirv, s: ShaderStmt): void {
	const target = s.target;
	const base = target.operands[0];
	if (s.assign == AssignOp.Increment || s.assign == AssignOp.Decrement) {
		refusal(p, "an increment of a swizzle");
		return;
	}
	if (!isPlace(p, base)) {
		refusal(p, "a write to a " + base.kind.toString() + ", which is no variable");
		return;
	}
	if (!writable(p, base)) { return; }
	const rhs = value(p, s.expr);
	const place = pointer(p, base);
	const vector = typeId(p, base.type);
	const old = typed(p, OP_LOAD, vector, [place.id]);
	let part = rhs;
	if (s.assign != AssignOp.Set) {
		const current = typed(p, OP_VECTOR_SHUFFLE, typeId(p, target.type),
			[old, old].concat(target.components));
		part = arithmetic(p, assignBinary(s.assign), target.type, target.type, current,
			s.expr.type, rhs);
	}
	let picks: int32[] = [];
	for (let c: int32 = 0; c < base.type.rows; c++) {
		const k = target.components.findIndex((x) => x == c) as int32;
		picks.push(k < 0 ? c : base.type.rows + k);
	}
	emit(p, OP_STORE, [place.id, typed(p, OP_VECTOR_SHUFFLE, vector, [old, part].concat(picks))]);
}

function assign(p: Spirv, s: ShaderStmt): void {
	const target = s.target;
	if (target.kind == ExprKind.Swizzle && target.components.length > 1) {
		swizzleAssign(p, s);
		return;
	}
	if (!isPlace(p, target)) {
		refusal(p, "a write to a " + target.kind.toString() + ", which is no variable");
		return;
	}
	if (!writable(p, target)) { return; }
	const place = pointer(p, target);
	const t = target.type;
	let next = 0;
	if (s.assign == AssignOp.Set) {
		next = value(p, s.expr);
	} else if (s.assign == AssignOp.Increment || s.assign == AssignOp.Decrement) {
		const old = typed(p, OP_LOAD, typeId(p, t), [place.id]);
		const one = splat(p, t, scalarConstant(p, t.scalar, 1.0));
		next = arithmetic(p, assignBinary(s.assign), t, t, old, t, one);
	} else {
		const rhs = value(p, s.expr);
		const old = typed(p, OP_LOAD, typeId(p, t), [place.id]);
		next = arithmetic(p, assignBinary(s.assign), t, t, old, s.expr.type, rhs);
	}
	emit(p, OP_STORE, [place.id, next]);
}

function stmts(p: Spirv, list: ShaderStmt[]): void {
	for (const s of list) {
		if (p.terminated || p.error != "") { return; }
		stmt(p, s);
	}
}

function ifStmt(p: Spirv, s: ShaderStmt): void {
	const c = value(p, s.expr);
	const merge = fresh(p);
	const yes = fresh(p);
	const otherwise = s.otherwise.length > 0;
	const no = otherwise ? fresh(p) : merge;
	emit(p, OP_SELECTION_MERGE, [merge, 0]);
	emit(p, OP_BRANCH_CONDITIONAL, [c, yes, no]);
	label(p, yes);
	stmts(p, s.body);
	if (!p.terminated) { branch(p, merge); }
	if (otherwise) {
		label(p, no);
		stmts(p, s.otherwise);
		if (!p.terminated) { branch(p, merge); }
	}
	label(p, merge);
}

function loop(p: Spirv, condition: ShaderExpr, body: ShaderStmt[], update: ShaderStmt[]): void {
	const header = fresh(p);
	const start = fresh(p);
	const next = fresh(p);
	const merge = fresh(p);
	branch(p, header);
	label(p, header);
	emit(p, OP_LOOP_MERGE, [merge, next, 0]);
	branch(p, start);
	label(p, start);
	if (condition.type.kind != ShaderTypeKind.Void) {
		const c = value(p, condition);
		const stay = fresh(p);
		const leave = fresh(p);
		emit(p, OP_SELECTION_MERGE, [stay, 0]);
		emit(p, OP_BRANCH_CONDITIONAL, [c, stay, leave]);
		label(p, leave);
		branch(p, merge);
		label(p, stay);
	}
	p.breaks.push(merge);
	p.continues.push(next);
	stmts(p, body);
	if (!p.terminated) { branch(p, next); }
	p.breaks.pop();
	p.continues.pop();
	label(p, next);
	stmts(p, update);
	if (!p.terminated) { branch(p, header); }
	label(p, merge);
}

function switchStmt(p: Spirv, s: ShaderStmt): void {
	const selector = value(p, s.expr);
	const merge = fresh(p);
	const labels = s.cases.map((): int32 => fresh(p));
	const fallback = s.cases.findIndex((k) => k.isDefault);
	let targets: int32[] = [selector, fallback < 0 ? merge : labels[fallback]];
	for (let i: int32 = 0; i < s.cases.length; i++) {
		for (const l of s.cases[i].labels) {
			if (l.kind != ExprKind.Literal) {
				refusal(p, "a switch case label that is no literal");
				return;
			}
			targets.push(wordOf(l.value));
			targets.push(labels[i]);
		}
	}
	emit(p, OP_SELECTION_MERGE, [merge, 0]);
	emit(p, OP_SWITCH, targets);
	p.terminated = true;
	p.breaks.push(merge);
	for (let i: int32 = 0; i < s.cases.length; i++) {
		label(p, labels[i]);
		stmts(p, s.cases[i].body);
		if (!p.terminated) { branch(p, merge); }
	}
	p.breaks.pop();
	label(p, merge);
}

function jump(p: Spirv, targets: int32[], what: string): void {
	if (targets.length == 0) {
		refusal(p, "a " + what + " outside a loop");
		return;
	}
	branch(p, targets[targets.length - 1]);
}

function stmt(p: Spirv, s: ShaderStmt): void {
	match (s.kind) {
		StmtKind.Block => { stmts(p, s.body); },
		StmtKind.Let => {
			const local = p.fn.locals[s.local];
			const init = s.expr.type.kind == ShaderTypeKind.Void ?
				nullConstant(p, typeId(p, local.type)) : value(p, s.expr);
			emit(p, OP_STORE, [p.localVars[s.local], init]);
		},
		StmtKind.Assign => { assign(p, s); },
		StmtKind.Call => {
			const _discarded = value(p, s.expr);
		},
		StmtKind.If => { ifStmt(p, s); },
		StmtKind.FeatureIf => {
			refusal(p, "a feature branch is still undecided: specialize the module first");
		},
		StmtKind.While => { loop(p, s.expr, s.body, []); },
		StmtKind.For => {
			stmts(p, s.init);
			loop(p, s.expr, s.body, s.update);
		},
		StmtKind.Switch => { switchStmt(p, s); },
		StmtKind.Break => { jump(p, p.breaks, "break"); },
		StmtKind.Continue => { jump(p, p.continues, "continue"); },
		StmtKind.Return => {
			if (s.expr.type.kind == ShaderTypeKind.Void) {
				emit(p, OP_RETURN, []);
			} else {
				const result = value(p, s.expr);
				emit(p, OP_RETURN_VALUE, [result]);
			}
			p.terminated = true;
		},
		StmtKind.Discard => {
			emit(p, OP_KILL, []);
			p.terminated = true;
		},
	}
}

function isHandle(t: ShaderType): boolean {
	return t.kind == ShaderTypeKind.Texture || t.kind == ShaderTypeKind.Sampler ||
		t.kind == ShaderTypeKind.StorageTexture;
}

function emitFunction(p: Spirv, index: int32): void {
	const f = p.module.functions[index];
	p.fn = f;
	p.body = [];
	p.vars = [];
	p.breaks = [];
	p.continues = [];
	p.terminated = false;
	for (const x of f.params.concat(f.locals)) {
		if (isHandle(x.type)) {
			refusal(p, "function '" + f.name + "': '" + x.name + "' holds a texture or sampler, " +
				"which is not printed yet");
			return;
		}
	}
	const result = typeId(p, f.result);
	const paramTypes = f.params.map((x) => typeId(p, x.type));
	const id = p.functionIds[index];
	let head: int32[] = [];
	inst(head, OP_FUNCTION, [result, id, 0, functionTypeId(p, result, paramTypes)]);
	let params: int32[] = [];
	for (const type of paramTypes) {
		const param = fresh(p);
		params.push(param);
		inst(head, OP_FUNCTION_PARAMETER, [type, param]);
	}
	const first = fresh(p);
	inst(head, OP_LABEL, [first]);
	p.block = first;
	p.localVars = f.locals.map((x) => localVariable(p, x.type));
	p.paramVars = f.params.map((x) => localVariable(p, x.type));
	name(p, id, f.name);
	for (let i: int32 = 0; i < f.params.length; i++) {
		name(p, p.paramVars[i], f.params[i].name);
		emit(p, OP_STORE, [p.paramVars[i], params[i]]);
	}
	for (let i: int32 = 0; i < f.locals.length; i++) { name(p, p.localVars[i], f.locals[i].name); }
	stmts(p, f.body);
	if (!p.terminated) {
		if (f.result.kind == ShaderTypeKind.Void) {
			emit(p, OP_RETURN, []);
		} else {
			emit(p, OP_RETURN_VALUE, [nullConstant(p, result)]);
		}
	}
	inst(p.body, OP_FUNCTION_END, []);
	for (const w of head.concat(p.vars).concat(p.body)) { p.functionWords.push(w); }
}

function laidOut(p: Spirv, index: int32, rule: int32, layout: StructLayout): void {
	const held = p.structRules[index];
	if (held != 0 && held != rule) {
		refusal(p, "struct '" + p.module.structs[index].name + "' is laid out as both std140 " +
			"and std430");
		return;
	}
	p.structRules[index] = rule;
	p.structOffsets[index] = layout.offsets;
	p.structSizes[index] = layout.size;
}

function layouts(p: Spirv, reads: Reads): void {
	const m = p.module;
	for (const index of reads.resources) {
		const r = m.resources[index];
		if (r.kind == ResourceKind.UniformBlock) {
			const layout = uniformBlockLayout(m, index);
			if (!layout.ok) {
				refusal(p, layout.error);
				return;
			}
			laidOut(p, r.type.structIndex, STD140, layout.value);
		}
		if (r.kind == ResourceKind.StorageBuffer) {
			const layout = storageElementLayout(m, index);
			if (!layout.ok) {
				refusal(p, layout.error);
				return;
			}
			const element = r.type.element[0].structIndex;
			for (const f of m.structs[element].members) {
				if (f.type.kind == ShaderTypeKind.Struct || f.type.kind == ShaderTypeKind.Array) {
					refusal(p, "storage buffer '" + r.name + "': member '" + f.name + "' is a " +
						f.type.kind.toString() + "; a struct or array in a storage element is not " +
						"printed yet");
					return;
				}
			}
			laidOut(p, element, STD430, layout.value);
		}
	}
}

function builtinWord(b: Builtin, stage: ShaderStage): int32 {
	return match (b) {
		Builtin.None => -1,
		Builtin.VertexIndex => 42,
		Builtin.InstanceIndex => 43,
		Builtin.Position => stage == ShaderStage.Fragment ? 15 : 0,
		Builtin.FrontFacing => 17,
		Builtin.FragDepth => 22,
		Builtin.LocalInvocationId => 27,
		Builtin.LocalInvocationIndex => 29,
		Builtin.GlobalInvocationId => 28,
		Builtin.WorkgroupId => 26,
		Builtin.NumWorkgroups => 24,
		Builtin.SampleIndex => 18,
		Builtin.SampleMask => 20,
	};
}

function typeText(t: ShaderType): string {
	const s = match (t.scalar) {
		ScalarKind.F32 => "f32",
		ScalarKind.I32 => "i32",
		ScalarKind.U32 => "u32",
		ScalarKind.Bool => "bool",
	};
	if (t.kind == ShaderTypeKind.Scalar) { return s; }
	if (t.kind == ShaderTypeKind.Vector) { return "vec" + String(t.rows) + "<" + s + ">"; }
	return t.kind.toString();
}

function declareIos(p: Spirv, e: ShaderEntry): int32[] {
	const m = p.module;
	let interfaces: int32[] = [];
	let ordinals = [0, 0];
	for (let i: int32 = 0; i < m.ios.length; i++) {
		const io = m.ios[i];
		if (io.stage != e.stage) { continue; }
		const input = io.direction == IoDirection.In;
		const storage = input ? INPUT : OUTPUT;
		if (io.builtin != Builtin.None && !sameShaderType(io.type, builtinType(io.builtin))) {
			refusal(p, "io '" + io.name + "' is " + typeText(io.type) + "; BuiltIn " +
				io.builtin.toString() + " is " + typeText(builtinType(io.builtin)));
			return interfaces;
		}
		const type = io.builtin == Builtin.SampleMask ?
			arrayTypeId(p, scalarTypeId(p, ScalarKind.U32), 1, 0) : typeId(p, io.type);
		const id = fresh(p);
		inst(p.globals, OP_VARIABLE, [pointerTypeId(p, storage, type), id, storage]);
		name(p, id, io.name);
		p.ioVars[i] = id;
		interfaces.push(id);
		if (io.builtin != Builtin.None) {
			decorate(p, id, DECORATION_BUILT_IN, [builtinWord(io.builtin, io.stage)]);
			if (io.builtin == Builtin.SampleIndex) { need(p, CAP_SAMPLE_RATE_SHADING); }
			if (io.builtin == Builtin.FragDepth) { p.depthReplacing = true; }
			const integral = (io.type.kind == ShaderTypeKind.Scalar ||
				io.type.kind == ShaderTypeKind.Vector) && io.type.scalar != ScalarKind.F32;
			if (input && io.stage == ShaderStage.Fragment && integral) {
				decorate(p, id, DECORATION_FLAT, []);
			}
			continue;
		}
		const side = input ? 0 : 1;
		decorate(p, id, DECORATION_LOCATION, [ioLocation(io, ordinals[side])]);
		ordinals[side] += 1;
		const varying = io.stage == ShaderStage.Vertex && !input ||
			io.stage == ShaderStage.Fragment && input;
		if (!varying) { continue; }
		if (io.interpolation == Interpolation.Flat) { decorate(p, id, DECORATION_FLAT, []); }
		if (io.interpolation == Interpolation.Linear) {
			decorate(p, id, DECORATION_NO_PERSPECTIVE, []);
		}
		if (io.sampling == Sampling.Centroid) { decorate(p, id, DECORATION_CENTROID, []); }
		if (io.sampling == Sampling.Sample) {
			decorate(p, id, DECORATION_SAMPLE, []);
			need(p, CAP_SAMPLE_RATE_SHADING);
		}
	}
	return interfaces;
}

function declareResource(p: Spirv, index: int32, slot: BindingSlot): void {
	const r = p.module.resources[index];
	let type = 0;
	let storage = UNIFORM_CONSTANT;
	match (r.kind) {
		ResourceKind.UniformBlock => {
			type = typeId(p, r.type);
			storage = UNIFORM;
			const key = "B" + String(type);
			if (cached(p, key) == 0) {
				remember(p, key, type);
				decorate(p, type, DECORATION_BLOCK, []);
			}
		},
		ResourceKind.StorageBuffer => {
			const array = typeId(p, r.type);
			const key = "w" + String(array);
			const made = cached(p, key) == 0;
			type = declared(p, key, OP_TYPE_STRUCT, [array]);
			if (made) {
				decorate(p, type, DECORATION_BLOCK, []);
				memberDecorate(p, type, 0, DECORATION_OFFSET, [0]);
			}
			storage = STORAGE_BUFFER;
		},
		ResourceKind.Texture | ResourceKind.Sampler | ResourceKind.StorageTexture => {
			type = typeId(p, r.type);
		},
	}
	const id = fresh(p);
	inst(p.globals, OP_VARIABLE, [pointerTypeId(p, storage, type), id, storage]);
	name(p, id, r.name);
	decorate(p, id, DECORATION_DESCRIPTOR_SET, [slot.group]);
	decorate(p, id, DECORATION_BINDING, [slot.binding]);
	if (r.kind == ResourceKind.StorageBuffer && r.access == Access.Read) {
		decorate(p, id, DECORATION_NON_WRITABLE, []);
	}
	if (r.kind == ResourceKind.StorageTexture && r.type.access == Access.Write) {
		decorate(p, id, DECORATION_NON_READABLE, []);
	}
	if (r.kind == ResourceKind.StorageTexture && r.type.access == Access.Read) {
		decorate(p, id, DECORATION_NON_WRITABLE, []);
	}
	p.resourceVars[index] = id;
}

function executionModel(stage: ShaderStage): int32 {
	return match (stage) {
		ShaderStage.Vertex => 0,
		ShaderStage.Fragment => 4,
		ShaderStage.Compute => 5,
	};
}

function assembled(p: Spirv, e: ShaderEntry, interfaces: int32[]): uint32[] {
	let words: int32[] = [119734787, 66304, 0, p.bound, 0];
	inst(words, OP_CAPABILITY, [CAP_SHADER]);
	for (const c of p.capabilities) { inst(words, OP_CAPABILITY, [c]); }
	inst(words, OP_EXT_INST_IMPORT, [p.glsl].concat(stringWords("GLSL.std.450")));
	inst(words, OP_MEMORY_MODEL, [0, 1]);
	const entry = p.functionIds[e.functionIndex];
	inst(words, OP_ENTRY_POINT, [executionModel(e.stage), entry].concat(stringWords("main"))
		.concat(interfaces));
	if (e.stage == ShaderStage.Fragment) {
		inst(words, OP_EXECUTION_MODE, [entry, 7]);
		if (p.depthReplacing) { inst(words, OP_EXECUTION_MODE, [entry, 12]); }
	}
	if (e.stage == ShaderStage.Compute) {
		inst(words, OP_EXECUTION_MODE, [entry, 17].concat(e.workgroupSize));
	}
	for (const section of [p.names, p.annotations, p.globals, p.functionWords]) {
		for (const w of section) { words.push(w); }
	}
	return words.map((w) => uint32Bits(w));
}

export function printSpirv(m: ShaderModule, entry: int32, bindings: BindingSlot[]):
	Result<uint32[], string> {
	const printable = printableEntry(m, entry);
	if (!printable.ok) { return Result.err("printSpirv: " + printable.error); }
	const reads = printable.value;
	for (const index of reads.resources) {
		if (!bindings.some((s) => s.resource == index)) {
			return Result.err("printSpirv: resource '" + m.resources[index].name +
				"' has no binding slot");
		}
	}
	const e = m.entries[entry];
	let p = new Spirv();
	p.module = m;
	p.stage = e.stage;
	p.glsl = fresh(p);
	p.structRules = m.structs.map((): int32 => 0);
	p.structOffsets = m.structs.map((): int32[] => []);
	p.structSizes = m.structs.map((): int32 => 0);
	p.structSlots = m.structs.map((): int32[] => []);
	p.resourceVars = m.resources.map((): int32 => 0);
	p.ioVars = m.ios.map((): int32 => 0);
	p.workgroupVars = m.workgroups.map((): int32 => 0);
	p.functionIds = m.functions.map((): int32 => 0);
	p.constantValues = m.constants.map((): int32 => 0);
	layouts(p, reads);
	const interfaces = declareIos(p, e);
	for (const index of reads.resources) {
		declareResource(p, index, bindings.filter((s) => s.resource == index)[0]);
	}
	for (const w of reads.workgroups) {
		const v = m.workgroups[w];
		const id = fresh(p);
		inst(p.globals, OP_VARIABLE, [pointerTypeId(p, WORKGROUP, typeId(p, v.type)), id, WORKGROUP]);
		name(p, id, v.name);
		p.workgroupVars[w] = id;
	}
	let functions = reads.functions.map((i) => i);
	if (!functions.includes(e.functionIndex)) { functions.push(e.functionIndex); }
	for (const i of functions) { p.functionIds[i] = fresh(p); }
	for (const i of functions) {
		if (p.error == "") { emitFunction(p, i); }
	}
	if (p.error != "") { return Result.err(p.error); }
	return Result.ok(assembled(p, e, interfaces));
}
