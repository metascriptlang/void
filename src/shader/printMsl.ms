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
	ShaderExpr,
	ShaderFunction,
	ShaderIo,
	ShaderModule,
	ShaderStage,
	ShaderStmt,
	ShaderType,
	ShaderTypeKind,
	StmtKind,
	TextureShape,
	UnaryOp,
	sameShaderType,
	hasOffset,
	isShift,
	offsetOf,
	isAtomic,
	frexpResultType,
	modfResultType,
	isEffect,
	texelScalar,
} from "./ir";
import { BindingSlot, StructLayout, storageElementLayout, uniformBlockLayout } from "./layout";
import { builtinType, functionOrder, ioLocation, structOrder } from "./irWalk";
import { claimName } from "./names";
import { printableEntry, readsFrom } from "./specialize";
import {
	binaryOperator,
	componentCompare,
	floatText,
	isComponentCompare,
	isIntMin,
	isMath,
	mathName,
	splitHelperName,
	splitMember,
	splitStructName,
	pointed,
	repeatedBitsOperand,
} from "./spelling";

function mslReservedWords(): string[] {
	let words = [
		"alignas", "alignof", "and", "and_eq", "asm", "auto", "bitand", "bitor", "bool", "break",
		"case", "catch", "char", "char16_t", "char32_t", "class", "compl", "const", "constexpr",
		"const_cast", "continue", "decltype", "default", "delete", "do", "double", "dynamic_cast",
		"else", "enum", "explicit", "export", "extern", "false", "final", "float", "for", "friend",
		"goto", "if", "inline", "int", "long", "mutable", "namespace", "new", "noexcept", "not",
		"not_eq", "nullptr", "operator", "or", "or_eq", "override", "private", "protected",
		"public", "register", "reinterpret_cast", "return", "short", "signed", "sizeof", "static",
		"static_assert", "static_cast", "struct", "switch", "template", "this", "thread_local",
		"throw", "true", "try", "typedef", "typeid", "typename", "union", "unsigned", "using",
		"virtual", "void", "volatile", "wchar_t", "while", "xor", "xor_eq",
		"metal", "std", "main", "kernel", "vertex", "fragment", "compute", "device", "constant",
		"thread", "threadgroup", "threadgroup_imageblock", "ray_data", "object_data", "stage_in",
		"half", "uint", "ushort", "uchar", "size_t", "ptrdiff_t", "access", "array", "vec",
		"matrix", "packed_float2", "packed_float3", "packed_float4", "sampler", "texture1d",
		"texture2d", "texture3d", "texturecube", "texture2d_array", "texturecube_array",
		"texture2d_ms", "depth2d", "depth2d_array", "depthcube", "depth2d_ms", "level", "bias",
		"discard_fragment", "select", "fmod", "rint", "rsqrt", "faceforward", "dfdx", "dfdy",
		"all", "any", "as_type", "ctz", "clz", "extract_bits", "insert_bits", "popcount", "reverse_bits",
		"half", "modf", "frexp",
	];
	for (const scalar of ["float", "int", "uint", "bool", "half"]) {
		for (let n = 2; n <= 4; n++) {
			words.push(scalar + String(n));
			if (scalar == "float" || scalar == "half") {
				for (let r = 2; r <= 4; r++) { words.push(scalar + String(n) + "x" + String(r)); }
			}
		}
	}
	for (let i = 0; i <= (Intrinsic.TextureDimensions as int32); i++) {
		const op = i as Intrinsic;
		if (!isMath(op)) { continue; }
		const name = builtinName(op);
		if (name != "") { words.push(name); }
	}
	return words;
}

function builtinName(op: Intrinsic): string {
	return match (op) {
		Intrinsic.Round => "rint",
		Intrinsic.InverseSqrt => "rsqrt",
		Intrinsic.Dpdx => "dfdx",
		Intrinsic.Dpdy => "dfdy",
		Intrinsic.DpdxCoarse | Intrinsic.DpdxFine => "dfdx",
		Intrinsic.DpdyCoarse | Intrinsic.DpdyFine => "dfdy",
		Intrinsic.FwidthCoarse | Intrinsic.FwidthFine => "fwidth",
		Intrinsic.CountLeadingZeros => "clz",
		Intrinsic.CountTrailingZeros => "ctz",
		Intrinsic.CountOneBits => "popcount",
		Intrinsic.ReverseBits => "reverse_bits",
		Intrinsic.Pack4x8Unorm => "pack_float_to_unorm4x8",
		Intrinsic.Pack4x8Snorm => "pack_float_to_snorm4x8",
		Intrinsic.Pack2x16Unorm => "pack_float_to_unorm2x16",
		Intrinsic.Pack2x16Snorm => "pack_float_to_snorm2x16",
		Intrinsic.Unpack4x8Unorm => "unpack_unorm4x8_to_float",
		Intrinsic.Unpack4x8Snorm => "unpack_snorm4x8_to_float",
		Intrinsic.Unpack2x16Unorm => "unpack_unorm2x16_to_float",
		Intrinsic.Unpack2x16Snorm => "unpack_snorm2x16_to_float",
		Intrinsic.FirstLeadingBit | Intrinsic.FirstTrailingBit | Intrinsic.ExtractBits |
			Intrinsic.InsertBits | Intrinsic.Pack2x16Float | Intrinsic.Unpack2x16Float => "",
		Intrinsic.Sign | Intrinsic.Degrees | Intrinsic.Radians | Intrinsic.Modf | Intrinsic.Frexp => "",
		_ => mathName(op),
	};
}

const UPPER_LEFT = "upperLeft3x3";

function inverseName(n: int32): string { return "inverse" + String(n) + "x" + String(n); }

function exchangeSuffix(slot: int32): string { return slot == 0 ? "I32" : "U32"; }

function exchangeText(slot: int32): string {
	const scalar = slot == 0 ? "int" : "uint";
	const result = "AtomicExchange" + exchangeSuffix(slot);
	return "struct " + result + " {\n  " + scalar + " old_value;\n  bool exchanged;\n};\n\n" +
		"template <typename A>\nstatic inline " + result + " atomicCompareExchangeWeak" +
		exchangeSuffix(slot) + "(A place, " + scalar + " compare, " + scalar + " value) {\n" +
		"  bool exchanged = atomic_compare_exchange_weak_explicit(place, &compare, value, " +
		"memory_order_relaxed, memory_order_relaxed);\n  return " + result +
		"{compare, exchanged};\n}";
}

function inverseText(n: int32): string {
	const mat = "float" + String(n) + "x" + String(n);
	const body = match (n) {
		2 => [
			"float k = 1.0 / determinant(m);",
			"return float2x2(float2(m[1].y, -m[0].y) * k, float2(-m[1].x, m[0].x) * k);",
		],
		3 => [
			"float k = 1.0 / determinant(m);",
			"return transpose(float3x3(cross(m[1], m[2]) * k, cross(m[2], m[0]) * k, " +
				"cross(m[0], m[1]) * k));",
		],
		_ => [
			"float3 a = m[0].xyz;",
			"float3 b = m[1].xyz;",
			"float3 c = m[2].xyz;",
			"float3 d = m[3].xyz;",
			"float3 s = cross(a, b);",
			"float3 t = cross(c, d);",
			"float3 u = a * m[1].w - b * m[0].w;",
			"float3 v = c * m[3].w - d * m[2].w;",
			"float k = 1.0 / (dot(s, v) + dot(t, u));",
			"return transpose(float4x4(",
			"  float4(cross(b, v * k) + t * k * m[1].w, -dot(b, t * k)),",
			"  float4(cross(v * k, a) - t * k * m[0].w, dot(a, t * k)),",
			"  float4(cross(d, u * k) + s * k * m[3].w, -dot(d, s * k)),",
			"  float4(cross(u * k, c) - s * k * m[2].w, dot(c, s * k))));",
		],
	};
	return "static inline " + mat + " " + inverseName(n) + "(" + mat + " m) {\n" +
		body.map((line) => "  " + line + "\n").join("") + "}";
}

class Threaded {
	stageIn: boolean = false;
	stageOut: boolean = false;
	builtins: int32[] = [];
	resources: int32[] = [];
	workgroups: int32[] = [];
}

class Printer {
	module: ShaderModule = new ShaderModule();
	stage: ShaderStage = ShaderStage.Vertex;
	taken: string[] = [];
	structs: string[] = [];
	members: string[][] = [];
	constants: string[] = [];
	resources: string[] = [];
	ios: string[] = [];
	functions: string[] = [];
	workgroups: string[] = [];
	threaded: Threaded[] = [];
	fn: ShaderFunction = new ShaderFunction();
	scope: string[] = [];
	params: string[] = [];
	locals: string[] = [];
	upperLeft: boolean = false;
	inverses: int32[] = [];
	exchanges: boolean[] = [false, false];
	splits: ShaderType[] = [];
	error: string = "";
	lines: string[] = [];
	reserved: string[] = [];
}

function fail(p: Printer, what: string): string {
	if (p.error == "") { p.error = "printMsl: " + what; }
	return "";
}

function isIdentifier(name: string): boolean {
	if (name == "" || name == "_" || name.startsWith("__")) { return false; }
	for (let i = 0; i < name.length; i++) {
		const c = name.charCodeAt(i);
		const letter = (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95;
		if (!letter && !(i > 0 && c >= 48 && c <= 57)) { return false; }
	}
	return true;
}

function nameIn(p: Printer, scope: string[], name: string): string {
	if (!isIdentifier(name)) { return fail(p, "'" + name + "' is no MSL identifier"); }
	return claimName(scope, (n) => p.reserved.includes(n), name);
}

function scalarText(s: ScalarKind): string {
	return match (s) {
		ScalarKind.F32 => "float",
		ScalarKind.I32 => "int",
		ScalarKind.U32 => "uint",
		ScalarKind.Bool => "bool",
	};
}

function texelText(p: Printer, s: ScalarKind): string {
	if (s == ScalarKind.Bool) { return fail(p, "a texture of bool texels"); }
	return scalarText(s);
}

function textureText(p: Printer, t: ShaderType): string {
	const texel = "<" + texelText(p, t.scalar) + ">";
	return match (t.shape) {
		TextureShape.D2 => "texture2d" + texel,
		TextureShape.D2Array => "texture2d_array" + texel,
		TextureShape.D3 => "texture3d" + texel,
		TextureShape.Cube => "texturecube" + texel,
		TextureShape.CubeArray => "texturecube_array" + texel,
		TextureShape.Depth2d => "depth2d<float>",
		TextureShape.Depth2dArray => "depth2d_array<float>",
		TextureShape.DepthCube => "depthcube<float>",
		TextureShape.Multisampled2d => "texture2d_ms" + texel,
	};
}

function accessText(a: Access): string {
	return match (a) {
		Access.Read => "access::read",
		Access.Write => "access::write",
		Access.ReadWrite => "access::read_write",
	};
}

function typeText(p: Printer, t: ShaderType): string {
	const n = String(t.rows);
	return match (t.kind) {
		ShaderTypeKind.Scalar => scalarText(t.scalar),
		ShaderTypeKind.Vector => scalarText(t.scalar) + n,
		ShaderTypeKind.Matrix => "float" + String(t.columns) + "x" + n,
		ShaderTypeKind.Array => fail(p, "an array where only a declaration can hold one"),
		ShaderTypeKind.RuntimeArray => fail(p, "a runtime array outside a storage buffer"),
		ShaderTypeKind.Struct => p.structs[t.structIndex],
		ShaderTypeKind.Texture => textureText(p, t),
		ShaderTypeKind.Sampler => "sampler",
		ShaderTypeKind.StorageTexture => storageShapeText(p, t.shape) + "<" +
			scalarText(texelScalar(t.format)) + ", " + accessText(t.access) + ">",
		ShaderTypeKind.Atomic => "atomic_" + scalarText(t.scalar),
		ShaderTypeKind.ExchangeResult => "AtomicExchange" +
			exchangeSuffix(t.scalar == ScalarKind.I32 ? 0 : 1),
		ShaderTypeKind.ModfResult | ShaderTypeKind.FrexpResult => usedSplit(p, t),
		ShaderTypeKind.Void => "void",
	};
}

function splitTypes(t: ShaderType): string[] {
	const fract = t.rows == 1 ? "float" : "float" + String(t.rows);
	if (t.kind == ShaderTypeKind.ModfResult) { return [fract, fract]; }
	return [fract, t.rows == 1 ? "int" : "int" + String(t.rows)];
}

function splitText(t: ShaderType): string {
	const types = splitTypes(t);
	const result = splitStructName(t);
	const call = t.kind == ShaderTypeKind.ModfResult ? "modf" : "frexp";
	return "struct " + result + " {\n  " + types[0] + " " + splitMember(t, 0) + ";\n  " + types[1] + " " +
		splitMember(t, 1) + ";\n};\n\nstatic inline " + result + " " + splitHelperName(t) + "(" +
		types[0] + " arg) {\n  " + types[1] + " other;\n  " + types[0] + " part = " + call +
		"(arg, other);\n  return " + result + "{part, other};\n}";
}

function usedSplit(p: Printer, t: ShaderType): string {
	if (!p.splits.some((s) => sameShaderType(s, t))) { p.splits.push(t); }
	return splitStructName(t);
}

function splitCallName(p: Printer, t: ShaderType): string {
	usedSplit(p, t);
	return splitHelperName(t);
}

function atomicText(p: Printer, e: ShaderExpr): string {
	const o = e.operands;
	const place = "&" + exprText(p, o[0]);
	const rest = o.slice(1).map((a) => ", " + exprText(p, a)).join("");
	if (e.intrinsic == Intrinsic.AtomicCompareExchangeWeak) {
		const slot = o[0].type.scalar == ScalarKind.I32 ? 0 : 1;
		p.exchanges[slot] = true;
		return "atomicCompareExchangeWeak" + exchangeSuffix(slot) + "(" + place + rest + ")";
	}
	const name = match (e.intrinsic) {
		Intrinsic.AtomicLoad => "atomic_load_explicit",
		Intrinsic.AtomicStore => "atomic_store_explicit",
		Intrinsic.AtomicAdd => "atomic_fetch_add_explicit",
		Intrinsic.AtomicSub => "atomic_fetch_sub_explicit",
		Intrinsic.AtomicMax => "atomic_fetch_max_explicit",
		Intrinsic.AtomicMin => "atomic_fetch_min_explicit",
		Intrinsic.AtomicAnd => "atomic_fetch_and_explicit",
		Intrinsic.AtomicOr => "atomic_fetch_or_explicit",
		Intrinsic.AtomicXor => "atomic_fetch_xor_explicit",
		Intrinsic.AtomicExchange => "atomic_exchange_explicit",
		_ => fail(p, e.intrinsic.toString() + " has no MSL atomic spelling"),
	};
	return name + "(" + place + rest + ", memory_order_relaxed)";
}

function declText(p: Printer, t: ShaderType, name: string): string {
	if (t.kind == ShaderTypeKind.Array) {
		return declText(p, t.element[0], name + "[" + String(t.length) + "]");
	}
	if (t.kind == ShaderTypeKind.Void) { return fail(p, "a value of type void"); }
	return typeText(p, t) + " " + name;
}

function numberText(value: float64): string {
	const text = pointed(floatText(value));
	return text.startsWith("-") ? "(" + text + ")" : text;
}

function scalarLiteral(s: ScalarKind, value: float64): string {
	if (s == ScalarKind.Bool) { return value != 0.0 ? "true" : "false"; }
	if (s == ScalarKind.F32) { return numberText(value); }
	if (isIntMin(s, value)) { return "(-2147483647 - 1)"; }
	const text = String(value as int64) + (s == ScalarKind.U32 ? "u" : "");
	return value < 0.0 ? "(" + text + ")" : text;
}

function literalText(p: Printer, t: ShaderType, value: float64): string {
	if (t.kind == ShaderTypeKind.Scalar) { return scalarLiteral(t.scalar, value); }
	if (t.kind == ShaderTypeKind.Vector) {
		return typeText(p, t) + "(" + scalarLiteral(t.scalar, value) + ")";
	}
	return fail(p, "a literal of a " + t.kind.toString());
}

function argsText(p: Printer, args: ShaderExpr[]): string {
	return args.map((a) => exprText(p, a)).join(", ");
}

function isFloat(t: ShaderType): boolean {
	return (t.kind == ShaderTypeKind.Scalar || t.kind == ShaderTypeKind.Vector) &&
		t.scalar == ScalarKind.F32;
}

function binaryText(p: Printer, e: ShaderExpr): string {
	const left = e.operands[0];
	if (e.binary == BinaryOp.Mod && isFloat(e.type)) {
		return "fmod(" + argsText(p, e.operands) + ")";
	}
	const right = e.operands[1];
	const amount = isShift(e.binary) && right.kind != ExprKind.Literal ?
		"(" + exprText(p, right) + " & 31u)" : exprText(p, right);
	const text = "(" + exprText(p, left) + " " + binaryOperator(e.binary) + " " + amount + ")";
	const whole = (e.binary == BinaryOp.Equal || e.binary == BinaryOp.NotEqual) &&
		e.type.kind == ShaderTypeKind.Scalar;
	if (!whole || left.type.kind == ShaderTypeKind.Scalar) { return text; }
	if (left.type.kind != ShaderTypeKind.Vector) {
		return fail(p, "'" + binaryOperator(e.binary) + "' on a " + left.type.kind.toString());
	}
	return (e.binary == BinaryOp.Equal ? "all" : "any") + text;
}

function hasEffect(e: ShaderExpr): boolean {
	if (e.kind == ExprKind.Call || e.kind == ExprKind.Intrinsic && isEffect(e.intrinsic)) {
		return true;
	}
	return e.operands.some((o) => hasEffect(o));
}

function withoutSamplers(args: ShaderExpr[]): ShaderExpr[] {
	return args.filter((a) => a.type.kind != ShaderTypeKind.Sampler);
}

function isArrayed(t: ShaderType): boolean {
	return t.shape == TextureShape.D2Array || t.shape == TextureShape.CubeArray ||
		t.shape == TextureShape.Depth2dArray;
}

function texelCoordinate(p: Printer, at: ShaderExpr): string {
	const rows = at.type.kind == ShaderTypeKind.Vector ? String(at.type.rows) : "";
	return "uint" + rows + "(" + exprText(p, at) + ")";
}

function isComparisonSampler(p: Printer, sampler: ShaderExpr): boolean {
	return sampler.kind == ExprKind.Resource &&
		p.module.resources[sampler.index].samplerType == SamplerType.Comparison;
}

function sampleText(p: Printer, e: ShaderExpr): string {
	const o = e.operands;
	if (o.length < 3 || o[0].type.kind != ShaderTypeKind.Texture ||
		o[1].type.kind != ShaderTypeKind.Sampler) {
		return fail(p, "TextureSample takes a texture, a sampler and coordinates");
	}
	const t = o[0].type;
	if (t.shape == TextureShape.Multisampled2d) {
		return fail(p, "TextureSample of a multisampled texture");
	}
	if (isComparisonSampler(p, o[1])) {
		return fail(p, "TextureSample through a comparison sampler, which needs a depth reference");
	}
	let args = [exprText(p, o[1]), exprText(p, o[2])];
	if (isArrayed(t)) {
		if (o.length < 4) { return fail(p, "TextureSample of an array texture without a layer"); }
		args.push("uint(" + exprText(p, o[3]) + ")");
	}
	if (p.stage != ShaderStage.Fragment) { args.push("level(0.0)"); }
	if (hasOffset(e)) { args.push(exprText(p, offsetOf(e))); }
	return exprText(p, o[0]) + ".sample(" + args.join(", ") + ")";
}

function gradientName(p: Printer, shape: TextureShape): string {
	return match (shape) {
		TextureShape.D3 => "gradient3d(",
		TextureShape.Cube | TextureShape.CubeArray | TextureShape.DepthCube => "gradientcube(",
		TextureShape.D2 | TextureShape.D2Array | TextureShape.Depth2d |
			TextureShape.Depth2dArray => "gradient2d(",
		TextureShape.Multisampled2d => fail(p, "a gradient sample of a multisampled texture"),
	};
}

function explicitSampleText(p: Printer, e: ShaderExpr): string {
	const o = e.operands;
	const t = o[0].type;
	if (isComparisonSampler(p, o[1])) {
		return fail(p, e.intrinsic.toString() + " through a comparison sampler, which needs a " +
			"depth reference");
	}
	const layer = isArrayed(t) ? 1 : 0;
	let args = [exprText(p, o[1]), exprText(p, o[2])];
	if (layer == 1) { args.push("uint(" + exprText(p, o[3]) + ")"); }
	const at = 3 + layer;
	args.push(match (e.intrinsic) {
		Intrinsic.TextureSampleLevel => "level(" + exprText(p, o[at]) + ")",
		Intrinsic.TextureSampleBias => "bias(" + exprText(p, o[at]) + ")",
		Intrinsic.TextureSampleGrad => gradientName(p, t.shape) + exprText(p, o[at]) + ", " +
			exprText(p, o[at + 1]) + ")",
		_ => fail(p, e.intrinsic.toString() + " is no explicit sample"),
	});
	if (hasOffset(e)) { args.push(exprText(p, offsetOf(e))); }
	return exprText(p, o[0]) + ".sample(" + args.join(", ") + ")";
}

function compareText(p: Printer, e: ShaderExpr, level: boolean): string {
	const o = e.operands;
	const name = e.intrinsic.toString();
	const layered = o.length > 0 && o[0].type.shape == TextureShape.Depth2dArray;
	const base = layered ? 5 : 4;
	if (o.length != base && o.length != base + 1 || o[0].type.kind != ShaderTypeKind.Texture ||
		o[1].type.kind != ShaderTypeKind.Sampler) {
		return fail(p, name + " takes a texture, a sampler, coordinates, for an array texture a " +
			"layer, a depth reference, and an optional constant offset");
	}
	if (!isComparisonSampler(p, o[1])) {
		return fail(p, name + " through a sampler that is no comparison sampler binding");
	}
	const shape = o[0].type.shape;
	if (shape != TextureShape.Depth2d && shape != TextureShape.Depth2dArray &&
		shape != TextureShape.DepthCube) {
		return fail(p, name + " of a " + shape.toString() + " texture, which holds no depth");
	}
	let args = [exprText(p, o[1]), exprText(p, o[2])];
	if (layered) { args.push("uint(" + exprText(p, o[3]) + ")"); }
	args.push(exprText(p, o[base - 1]));
	if (level) { args.push("level(0.0)"); }
	if (o.length == base + 1) { args.push(exprText(p, o[base])); }
	return exprText(p, o[0]) + ".sample_compare(" + args.join(", ") + ")";
}

function loadText(p: Printer, e: ShaderExpr): string {
	const o = withoutSamplers(e.operands);
	if (o.length < 2) { return fail(p, "TextureLoad without coordinates"); }
	const t = o[0].type;
	const texture = exprText(p, o[0]);
	const at = texelCoordinate(p, o[1]);
	if (t.kind == ShaderTypeKind.StorageTexture) {
		if (t.access == Access.Write) {
			return fail(p, "TextureLoad of a write-only storage texture");
		}
		return texture + ".read(" + at + layerText(p, o) + ")";
	}
	if (t.kind != ShaderTypeKind.Texture) {
		return fail(p, "TextureLoad of a " + t.kind.toString());
	}
	if (t.shape == TextureShape.Cube || t.shape == TextureShape.CubeArray ||
		t.shape == TextureShape.DepthCube) {
		return fail(p, "TextureLoad of a cube texture, which names no face");
	}
	const wanted = isArrayed(t) ? 4 : 3;
	if (o.length < wanted) {
		return fail(p, t.shape == TextureShape.Multisampled2d ?
			"TextureLoad of a multisampled texture takes a sample index" :
			"TextureLoad of a sampled texture takes a level");
	}
	let args = [at];
	for (let k = 2; k < wanted; k++) { args.push("uint(" + exprText(p, o[k]) + ")"); }
	return texture + ".read(" + args.join(", ") + ")";
}

function storageShapeText(p: Printer, shape: TextureShape): string {
	return match (shape) {
		TextureShape.D2 => "texture2d",
		TextureShape.D2Array => "texture2d_array",
		TextureShape.D3 => "texture3d",
		_ => fail(p, "a storage texture of shape " + shape.toString()),
	};
}

function layerText(p: Printer, o: ShaderExpr[]): string {
	return o[0].type.shape == TextureShape.D2Array ? ", uint(" + exprText(p, o[2]) + ")" : "";
}

function storeText(p: Printer, e: ShaderExpr): string {
	const o = e.operands;
	const wanted = o.length > 0 && o[0].type.shape == TextureShape.D2Array ? 4 : 3;
	if (o.length != wanted || o[0].type.kind != ShaderTypeKind.StorageTexture) {
		return fail(p, "TextureStore takes a storage texture, coordinates, a layer of an " +
			"array, and a value");
	}
	if (o[0].type.access == Access.Read) {
		return fail(p, "TextureStore to a read-only storage texture");
	}
	return exprText(p, o[0]) + ".write(" + exprText(p, o[wanted - 1]) + ", " +
		texelCoordinate(p, o[1]) + layerText(p, o) + ")";
}

function dimensionsText(p: Printer, e: ShaderExpr): string {
	const o = withoutSamplers(e.operands);
	const t = o[0].type;
	if (t.kind != ShaderTypeKind.Texture && t.kind != ShaderTypeKind.StorageTexture) {
		return fail(p, "TextureDimensions of a " + t.kind.toString());
	}
	const levelled = t.kind == ShaderTypeKind.Texture && t.shape != TextureShape.Multisampled2d &&
		o.length > 1;
	if (levelled && hasEffect(o[1])) {
		return fail(p, "TextureDimensions whose level calls a function");
	}
	const level = levelled ? "uint(" + exprText(p, o[1]) + ")" : "";
	const texture = exprText(p, o[0]);
	let sizes = [texture + ".get_width(" + level + ")", texture + ".get_height(" + level + ")"];
	if (t.shape == TextureShape.D3) {
		sizes.push(texture + ".get_depth(" + level + ")");
	}
	if (e.type.kind != ShaderTypeKind.Vector || e.type.rows != sizes.length) {
		return fail(p, "TextureDimensions of " + String(sizes.length) + " sizes into a " +
			e.type.kind.toString());
	}
	return typeText(p, e.type) + "(" + sizes.join(", ") + ")";
}

function samplesText(p: Printer, e: ShaderExpr): string {
	const t = e.operands[0].type;
	if (t.kind != ShaderTypeKind.Texture || t.shape != TextureShape.Multisampled2d) {
		return fail(p, "TextureNumSamples takes a multisampled texture");
	}
	return typeText(p, e.type) + "(" + exprText(p, e.operands[0]) + ".get_num_samples())";
}

function signText(p: Printer, e: ShaderExpr): string {
	const x = e.operands[0];
	if (isFloat(x.type)) { return "sign(" + exprText(p, x) + ")"; }
	if (hasEffect(x)) { return fail(p, "Sign of an integer whose operand calls a function"); }
	const zero = literalText(p, x.type, 0.0);
	const resultText = typeText(p, e.type);
	const operand = exprText(p, x);
	return "(" + resultText + "(" + operand + " > " + zero + ") - " + resultText + "(" + operand +
		" < " + zero + "))";
}

function selectText(p: Printer, e: ShaderExpr): string {
	const o = e.operands;
	const condition = exprText(p, o[2]);
	const splat = o[2].type.kind == ShaderTypeKind.Scalar && e.type.kind == ShaderTypeKind.Vector;
	return "select(" + exprText(p, o[0]) + ", " + exprText(p, o[1]) + ", " +
		(splat ? "bool" + String(e.type.rows) + "(" + condition + ")" : condition) + ")";
}

function inverseCall(p: Printer, e: ShaderExpr): string {
	const t = e.type;
	if (t.kind != ShaderTypeKind.Matrix || t.columns != t.rows) {
		return fail(p, "Inverse of a " + t.kind.toString() + " that is no square matrix");
	}
	if (!p.inverses.includes(t.rows)) { p.inverses.push(t.rows); }
	return inverseName(t.rows) + "(" + exprText(p, e.operands[0]) + ")";
}

// The compound spellings, as naga's back-end writes them: ctz and clz count the full width, where
// WGSL answers -1 for no bit, and extract_bits and insert_bits are undefined past the 32 bits
// WGSL clamps to. An operand printed more than once must not call a function.
function bitsText(p: Printer, e: ShaderExpr): string {
	const o = e.operands;
	const op = e.intrinsic;
	const x = exprText(p, o[0]);
	const repeated = op == Intrinsic.FirstLeadingBit ? 0 : repeatedBitsOperand(op);
	if (repeated >= 0 && hasEffect(o[repeated])) {
		return fail(p, op.toString() + " prints an operand more than once, and it calls a function");
	}
	if (op == Intrinsic.FirstTrailingBit) {
		return "(((ctz(" + x + ") + 1) % 33) - 1)";
	}
	if (op == Intrinsic.FirstLeadingBit) {
		const none = typeText(p, e.type) + "(-1)";
		if (e.type.scalar == ScalarKind.I32) {
			return "select(31 - clz(select(" + x + ", ~" + x + ", " + x + " < 0)), " + none + ", " +
				x + " == 0 || " + x + " == -1)";
		}
		return "select(31 - clz(" + x + "), " + none + ", " + x + " == 0)";
	}
	if (op == Intrinsic.Pack2x16Float) { return "as_type<uint>(half2(" + x + "))"; }
	if (op == Intrinsic.Unpack2x16Float) { return "float2(as_type<half2>(" + x + "))"; }
	const offset = exprText(p, o[op == Intrinsic.ExtractBits ? 1 : 2]);
	const count = exprText(p, o[op == Intrinsic.ExtractBits ? 2 : 3]);
	const clamped = "min(" + offset + ", 32u), min(" + count + ", 32u - min(" + offset + ", 32u))";
	if (op == Intrinsic.ExtractBits) { return "extract_bits(" + x + ", " + clamped + ")"; }
	return "insert_bits(" + x + ", " + exprText(p, o[1]) + ", " + clamped + ")";
}

function intrinsicText(p: Printer, e: ShaderExpr): string {
	const o = e.operands;
	const op = e.intrinsic;
	if (op == Intrinsic.Bitcast) {
		return "as_type<" + typeText(p, e.type) + ">(" + exprText(p, o[0]) + ")";
	}
	const name = isMath(op) ? builtinName(op) : "";
	if (name != "") { return name + "(" + argsText(p, o) + ")"; }
	if (isComponentCompare(op)) {
		return "(" + exprText(p, o[0]) + " " + binaryOperator(componentCompare(op)) + " " +
			exprText(p, o[1]) + ")";
	}
	if (op == Intrinsic.UpperLeft3x3) { p.upperLeft = true; }
	return match (op) {
		Intrinsic.FirstLeadingBit | Intrinsic.FirstTrailingBit | Intrinsic.ExtractBits |
			Intrinsic.InsertBits | Intrinsic.Pack2x16Float | Intrinsic.Unpack2x16Float =>
			bitsText(p, e),
		Intrinsic.Sign => signText(p, e),
		Intrinsic.Modf | Intrinsic.Frexp => splitCallName(p, e.type) + "(" + exprText(p, o[0]) + ")",
		Intrinsic.Degrees => "(" + exprText(p, o[0]) + " * 57.295779513082323)",
		Intrinsic.Radians => "(" + exprText(p, o[0]) + " * 0.017453292519943295)",
		Intrinsic.Inverse => inverseCall(p, e),
		Intrinsic.UpperLeft3x3 => UPPER_LEFT + "(" + exprText(p, o[0]) + ")",
		Intrinsic.Select => selectText(p, e),
		Intrinsic.TextureSample => sampleText(p, e),
		Intrinsic.TextureLoad => loadText(p, e),
		Intrinsic.TextureStore => storeText(p, e),
		Intrinsic.TextureDimensions => dimensionsText(p, e),
		Intrinsic.TextureNumSamples => samplesText(p, e),
		Intrinsic.TextureSampleCompare => compareText(p, e, false),
		Intrinsic.TextureSampleCompareLevel => compareText(p, e, true),
		Intrinsic.TextureSampleLevel | Intrinsic.TextureSampleBias | Intrinsic.TextureSampleGrad =>
			explicitSampleText(p, e),
		Intrinsic.WorkgroupBarrier =>
			"threadgroup_barrier(mem_flags::mem_threadgroup)",
		Intrinsic.StorageBarrier => "threadgroup_barrier(mem_flags::mem_device)",
		_ => isAtomic(op) ? atomicText(p, e) : fail(p, op.toString() + " has no MSL spelling"),
	};
}

function constructText(p: Printer, e: ShaderExpr): string {
	const t = e.type;
	if (t.kind == ShaderTypeKind.Array) {
		return fail(p, "an array value outside a local's or constant's initializer");
	}
	if (t.kind == ShaderTypeKind.Struct) {
		return p.structs[t.structIndex] + "{" + argsText(p, e.operands) + "}";
	}
	const scalars = t.kind == ShaderTypeKind.Matrix && e.operands.length == t.columns * t.rows;
	if (!scalars) { return typeText(p, t) + "(" + argsText(p, e.operands) + ")"; }
	let columns: string[] = [];
	for (let c = 0; c < t.columns; c++) {
		const column = e.operands.slice(c * t.rows, (c + 1) * t.rows);
		columns.push("float" + String(t.rows) + "(" + argsText(p, column) + ")");
	}
	return typeText(p, t) + "(" + columns.join(", ") + ")";
}

function initializerText(p: Printer, e: ShaderExpr): string {
	if (e.type.kind == ShaderTypeKind.Array && e.kind == ExprKind.Construct) {
		return "{" + e.operands.map((o) => initializerText(p, o)).join(", ") + "}";
	}
	return exprText(p, e);
}

function memberName(p: Printer, t: ShaderType, member: int32): string {
	if (t.kind == ShaderTypeKind.ExchangeResult) { return member == 0 ? "old_value" : "exchanged"; }
	if (t.kind == ShaderTypeKind.ModfResult || t.kind == ShaderTypeKind.FrexpResult) {
		return splitMember(t, member);
	}
	if (t.kind != ShaderTypeKind.Struct) { return fail(p, "a field of a " + t.kind.toString()); }
	return p.members[t.structIndex][member];
}

function swizzleText(components: int32[]): string {
	return components.map((c) => "xyzw".substring(c, c + 1)).join("");
}

function ioText(p: Printer, index: int32): string {
	const io = p.module.ios[index];
	if (io.stage != p.stage) {
		return fail(p, "io '" + io.name + "' belongs to the " + io.stage.toString() + " stage");
	}
	if (io.builtin != Builtin.None && io.direction == IoDirection.In) { return p.ios[index]; }
	return (io.direction == IoDirection.In ? "in." : "out.") + p.ios[index];
}

function threadedArgs(p: Printer, index: int32): string[] {
	const t = p.threaded[index];
	let args: string[] = [];
	if (t.stageIn) { args.push("in"); }
	if (t.stageOut) { args.push("out"); }
	for (const b of t.builtins) { args.push(p.ios[b]); }
	for (const r of t.resources) { args.push(p.resources[r]); }
	for (const w of t.workgroups) { args.push(p.workgroups[w]); }
	return args;
}

function callText(p: Printer, e: ShaderExpr): string {
	let args = e.operands.map((a) => exprText(p, a));
	for (const a of threadedArgs(p, e.index)) { args.push(a); }
	return p.functions[e.index] + "(" + args.join(", ") + ")";
}

function exprText(p: Printer, e: ShaderExpr): string {
	const m = p.module;
	const o = e.operands;
	if (e.type.kind == ShaderTypeKind.Array &&
		(e.kind == ExprKind.Conditional || e.kind == ExprKind.Call)) {
		return fail(p, "an array value outside a local's or constant's initializer");
	}
	return match (e.kind) {
		ExprKind.Literal => literalText(p, e.type, e.value),
		ExprKind.Local => p.locals[e.index],
		ExprKind.Param => p.params[e.index],
		ExprKind.Constant => p.constants[e.index],
		ExprKind.Io => ioText(p, e.index),
		ExprKind.Resource => p.resources[e.index],
		ExprKind.Workgroup => p.workgroups[e.index],
		ExprKind.BlockMember => p.resources[e.index] + "." +
			memberName(p, m.resources[e.index].type, e.member),
		ExprKind.Unary => match (e.unary) {
			UnaryOp.Negate => "(-" + exprText(p, o[0]) + ")",
			UnaryOp.Not => (o[0].type.scalar == ScalarKind.Bool ? "(!" : "(~") +
				exprText(p, o[0]) + ")",
		},
		ExprKind.Binary => binaryText(p, e),
		ExprKind.Conditional => "(" + exprText(p, o[0]) + " ? " + exprText(p, o[1]) + " : " +
			exprText(p, o[2]) + ")",
		ExprKind.Call => callText(p, e),
		ExprKind.Intrinsic => intrinsicText(p, e),
		ExprKind.Construct => constructText(p, e),
		ExprKind.Convert => e.type.kind == ShaderTypeKind.Matrix &&
			!sameShaderType(e.type, o[0].type) ? fail(p, "Convert between matrix sizes") :
			typeText(p, e.type) + "(" + exprText(p, o[0]) + ")",
		ExprKind.Field => exprText(p, o[0]) + "." + memberName(p, o[0].type, e.index),
		ExprKind.Swizzle => exprText(p, o[0]) + "." + swizzleText(e.components),
		ExprKind.Index => exprText(p, o[0]) + "[" + exprText(p, o[1]) + "]",
	};
}

function isVoid(e: ShaderExpr): boolean {
	return e.type.kind == ShaderTypeKind.Void;
}

function emit(p: Printer, depth: int32, text: string): void {
	p.lines.push("  ".repeat(depth) + text);
}

function assignText(p: Printer, s: ShaderStmt): string {
	const target = exprText(p, s.target);
	if (s.target.type.kind == ShaderTypeKind.Array) {
		return fail(p, "an assignment of a whole array");
	}
	if (s.assign == AssignOp.Mod && isFloat(s.target.type)) {
		if (hasEffect(s.target)) { return fail(p, "'%=' on a target that calls a function"); }
		return target + " = fmod(" + target + ", " + exprText(p, s.expr) + ")";
	}
	return match (s.assign) {
		AssignOp.Set => target + " = " + exprText(p, s.expr),
		AssignOp.Add => target + " += " + exprText(p, s.expr),
		AssignOp.Sub => target + " -= " + exprText(p, s.expr),
		AssignOp.Mul => target + " *= " + exprText(p, s.expr),
		AssignOp.Div => target + " /= " + exprText(p, s.expr),
		AssignOp.Mod => target + " %= " + exprText(p, s.expr),
		AssignOp.Increment => target + "++",
		AssignOp.Decrement => target + "--",
	};
}

function simpleText(p: Printer, s: ShaderStmt): string {
	return match (s.kind) {
		StmtKind.Let => declText(p, p.fn.locals[s.local].type, p.locals[s.local]) + " = " +
			(isVoid(s.expr) ? "{}" : initializerText(p, s.expr)),
		StmtKind.Assign => assignText(p, s),
		StmtKind.Call => s.expr.kind == ExprKind.Call || isVoid(s.expr) ?
			exprText(p, s.expr) : "(void)" + exprText(p, s.expr),
		_ => fail(p, s.kind.toString() + " is no simple statement"),
	};
}

function stmtsText(p: Printer, stmts: ShaderStmt[], depth: int32): void {
	for (const s of stmts) { stmtText(p, s, depth); }
}

function stmtText(p: Printer, s: ShaderStmt, depth: int32): void {
	match (s.kind) {
		StmtKind.Block => {
			emit(p, depth, "{");
			stmtsText(p, s.body, depth + 1);
			emit(p, depth, "}");
		},
		StmtKind.Let | StmtKind.Assign | StmtKind.Call => emit(p, depth, simpleText(p, s) + ";"),
		StmtKind.If => {
			emit(p, depth, "if (" + exprText(p, s.expr) + ") {");
			stmtsText(p, s.body, depth + 1);
			if (s.otherwise.length > 0) {
				emit(p, depth, "} else {");
				stmtsText(p, s.otherwise, depth + 1);
			}
			emit(p, depth, "}");
		},
		StmtKind.FeatureIf => {
			fail(p, "a feature branch is still undecided: specialize the module first");
		},
		StmtKind.While => {
			emit(p, depth, "while (" + exprText(p, s.expr) + ") {");
			stmtsText(p, s.body, depth + 1);
			emit(p, depth, "}");
		},
		StmtKind.For => forText(p, s, depth),
		StmtKind.Switch => {
			emit(p, depth, "switch (" + exprText(p, s.expr) + ") {");
			for (const arm of s.cases) {
				let labels = arm.labels.map((l) => "case " + exprText(p, l) + ":");
				if (arm.isDefault || arm.labels.length == 0) { labels.push("default:"); }
				emit(p, depth + 1, labels.join(" ") + " {");
				stmtsText(p, arm.body, depth + 2);
				emit(p, depth + 2, "break;");
				emit(p, depth + 1, "}");
			}
			emit(p, depth, "}");
		},
		StmtKind.Break => emit(p, depth, "break;"),
		StmtKind.Continue => emit(p, depth, "continue;"),
		StmtKind.Return => emit(p, depth, isVoid(s.expr) ? "return;" :
			"return " + exprText(p, s.expr) + ";"),
		StmtKind.Discard => emit(p, depth, "discard_fragment();"),
	}
}

function forText(p: Printer, s: ShaderStmt, depth: int32): void {
	const condition = isVoid(s.expr) ? "" : exprText(p, s.expr);
	if (s.update.some((u) => u.kind != StmtKind.Assign && u.kind != StmtKind.Call)) {
		fail(p, "a for update that is no assignment or call");
		return;
	}
	const update = s.update.map((u) => simpleText(p, u)).join(", ");
	const inHeader = s.init.length == 0 || s.init.length == 1 && (s.init[0].kind == StmtKind.Let ||
		s.init[0].kind == StmtKind.Assign || s.init[0].kind == StmtKind.Call);
	if (inHeader) {
		const init = s.init.length == 0 ? "" : simpleText(p, s.init[0]);
		emit(p, depth, "for (" + init + "; " + condition + "; " + update + ") {");
		stmtsText(p, s.body, depth + 1);
		emit(p, depth, "}");
		return;
	}
	emit(p, depth, "{");
	stmtsText(p, s.init, depth + 1);
	emit(p, depth + 1, "for (; " + condition + "; " + update + ") {");
	stmtsText(p, s.body, depth + 2);
	emit(p, depth + 1, "}");
	emit(p, depth, "}");
}

function resourceParam(p: Printer, index: int32): string {
	const r = p.module.resources[index];
	const name = p.resources[index];
	return match (r.kind) {
		ResourceKind.UniformBlock => "constant " + typeText(p, r.type) + "& " + name,
		ResourceKind.StorageBuffer => (r.access == Access.Read ? "const device " : "device ") +
			typeText(p, r.type.element[0]) + "* " + name,
		ResourceKind.Texture | ResourceKind.Sampler | ResourceKind.StorageTexture =>
			typeText(p, r.type) + " " + name,
	};
}

function threadedParams(p: Printer, index: int32): string[] {
	const t = p.threaded[index];
	let params: string[] = [];
	if (t.stageIn) { params.push("thread main0_in& in"); }
	if (t.stageOut) { params.push("thread main0_out& out"); }
	for (const b of t.builtins) {
		params.push("thread " + typeText(p, p.module.ios[b].type) + "& " + p.ios[b]);
	}
	for (const r of t.resources) { params.push(resourceParam(p, r)); }
	for (const w of t.workgroups) {
		const type = p.module.workgroups[w].type;
		params.push("threadgroup " + (type.kind == ShaderTypeKind.Array ?
			declText(p, type, "(&" + p.workgroups[w] + ")") :
			typeText(p, type) + "& " + p.workgroups[w]));
	}
	return params;
}

function functionText(p: Printer, index: int32): string {
	const f = p.module.functions[index];
	p.fn = f;
	p.scope = p.taken.map((n) => n);
	p.params = f.params.map((x) => nameIn(p, p.scope, x.name));
	p.locals = f.locals.map((x) => nameIn(p, p.scope, x.name));
	if (f.result.kind == ShaderTypeKind.Array) {
		return fail(p, "function '" + f.name + "' returns an array");
	}
	let header: string[] = [];
	for (let i = 0; i < f.params.length; i++) {
		if (f.params[i].type.kind == ShaderTypeKind.Array) {
			return fail(p, "function '" + f.name + "' takes an array, which MSL passes by pointer");
		}
		header.push(declText(p, f.params[i].type, p.params[i]));
	}
	for (const extra of threadedParams(p, index)) { header.push(extra); }
	p.lines = [];
	stmtsText(p, f.body, 1);
	return "static inline " + typeText(p, f.result) + " " + p.functions[index] + "(" +
		header.join(", ") + ") {\n" + p.lines.map((l) => l + "\n").join("") + "}";
}

function threadedOf(p: Printer, index: int32): Threaded {
	let t = new Threaded();
	const read = readsFrom(p.module, index);
	if (!read.ok) {
		fail(p, read.error);
		return t;
	}
	let ios = read.value.ios.map((n) => n);
	ios.sort((a, b) => a - b);
	for (const i of ios) {
		const io = p.module.ios[i];
		if (io.stage != p.stage) { continue; }
		if (io.direction == IoDirection.Out) {
			t.stageOut = true;
		} else if (io.builtin == Builtin.None) {
			t.stageIn = true;
		} else {
			t.builtins.push(i);
		}
	}
	t.resources = read.value.resources.map((n) => n);
	t.resources.sort((a, b) => a - b);
	t.workgroups = read.value.workgroups.map((n) => n);
	t.workgroups.sort((a, b) => a - b);
	return t;
}

function naturalExtent(m: ShaderModule, t: ShaderType): [int32, int32] {
	if (t.kind == ShaderTypeKind.Scalar || t.kind == ShaderTypeKind.Atomic) { return [4, 4]; }
	if (t.kind == ShaderTypeKind.Vector) { return t.rows == 2 ? [8, 8] : [16, 16]; }
	if (t.kind == ShaderTypeKind.Matrix) {
		const column = t.rows == 2 ? 8 : 16;
		return [column, column * t.columns];
	}
	if (t.kind == ShaderTypeKind.Array) {
		const [align, size] = naturalExtent(m, t.element[0]);
		return [align, size * t.length];
	}
	let align = 1;
	let end = 0;
	for (const f of m.structs[t.structIndex].members) {
		const [a, size] = naturalExtent(m, f.type);
		end = (end + a - 1) / a * a + size;
		align = a > align ? a : align;
	}
	return [align, (end + align - 1) / align * align];
}

function layoutError(m: ShaderModule, structIndex: int32, layout: StructLayout, owner: string,
	sized: boolean): string {
	const s = m.structs[structIndex];
	let end = 0;
	for (let k = 0; k < s.members.length; k++) {
		const f = s.members[k];
		if (f.type.kind == ShaderTypeKind.Struct) {
			return owner + " nests struct '" + f.name + "'";
		}
		const [align, size] = naturalExtent(m, f.type);
		const offset = (end + align - 1) / align * align;
		if (offset != layout.offsets[k]) {
			return owner + ": member '" + f.name + "' sits at byte " + String(layout.offsets[k]) +
				" in the host layout and " + String(offset) + " in MSL";
		}
		end = offset + size;
	}
	const [_align, natural] = naturalExtent(m, structTypeOf(structIndex));
	if (sized && natural != layout.size) {
		return owner + ": an element is " + String(layout.size) + " bytes in the host layout and " +
			String(natural) + " in MSL";
	}
	return "";
}

function structTypeOf(index: int32): ShaderType {
	let t = new ShaderType();
	t.kind = ShaderTypeKind.Struct;
	t.structIndex = index;
	return t;
}

function bufferLayoutError(m: ShaderModule, index: int32): string {
	const r = m.resources[index];
	if (r.kind == ResourceKind.UniformBlock) {
		const layout = uniformBlockLayout(m, index);
		if (!layout.ok) { return layout.error; }
		return layoutError(m, r.type.structIndex, layout.value, "uniform block '" + r.name + "'",
			false);
	}
	if (r.kind == ResourceKind.StorageBuffer) {
		const layout = storageElementLayout(m, index);
		if (!layout.ok) { return layout.error; }
		return layoutError(m, r.type.element[0].structIndex, layout.value,
			"storage buffer '" + r.name + "'", true);
	}
	return "";
}

function builtinAttribute(b: Builtin): string {
	return match (b) {
		Builtin.None => "",
		Builtin.VertexIndex => "vertex_id",
		Builtin.InstanceIndex => "instance_id",
		Builtin.Position => "position",
		Builtin.FrontFacing => "front_facing",
		Builtin.FragDepth => "depth(any)",
		Builtin.LocalInvocationId => "thread_position_in_threadgroup",
		Builtin.LocalInvocationIndex => "thread_index_in_threadgroup",
		Builtin.GlobalInvocationId => "thread_position_in_grid",
		Builtin.WorkgroupId => "threadgroup_position_in_grid",
		Builtin.NumWorkgroups => "threadgroups_per_grid",
		Builtin.SampleIndex => "sample_id",
		Builtin.SampleMask => "sample_mask",
	};
}

function interpolationText(io: ShaderIo): string {
	if (io.interpolation == Interpolation.Flat) { return ", flat"; }
	const linear = io.interpolation == Interpolation.Linear;
	const where = match (io.sampling) {
		Sampling.Center => "center",
		Sampling.Centroid => "centroid",
		Sampling.Sample => "sample",
	};
	if (!linear && io.sampling == Sampling.Center) { return ""; }
	return ", " + where + (linear ? "_no_perspective" : "_perspective");
}

function interfaceAttribute(p: Printer, io: ShaderIo, ordinal: int32): string {
	if (io.builtin != Builtin.None) {
		const wanted = builtinType(io.builtin);
		if (!sameShaderType(io.type, wanted)) {
			return fail(p, "io '" + io.name + "' is " + typeText(p, io.type) + "; [[" +
				builtinAttribute(io.builtin) + "]] is " + typeText(p, wanted));
		}
		return "[[" + builtinAttribute(io.builtin) + "]]";
	}
	const location = String(ioLocation(io, ordinal));
	if (io.stage == ShaderStage.Vertex && io.direction == IoDirection.In) {
		return "[[attribute(" + location + ")]]";
	}
	if (io.stage == ShaderStage.Fragment && io.direction == IoDirection.Out) {
		return "[[color(" + location + ")]]";
	}
	if (io.stage == ShaderStage.Compute) {
		return fail(p, "io '" + io.name + "' of a compute entry");
	}
	const varying = io.direction == IoDirection.In ? interpolationText(io) : "";
	return "[[user(locn" + location + ")" + varying + "]]";
}

function bindingAttribute(kind: ResourceKind, slot: int32): string {
	return match (kind) {
		ResourceKind.UniformBlock | ResourceKind.StorageBuffer =>
			"[[buffer(" + String(slot) + ")]]",
		ResourceKind.Texture | ResourceKind.StorageTexture => "[[texture(" + String(slot) + ")]]",
		ResourceKind.Sampler => "[[sampler(" + String(slot) + ")]]",
	};
}

function stageKeyword(stage: ShaderStage): string {
	return match (stage) {
		ShaderStage.Vertex => "vertex",
		ShaderStage.Fragment => "fragment",
		ShaderStage.Compute => "kernel",
	};
}

// The workgroup size of a compute entry is no MSL attribute: the host passes it to
// dispatchThreadgroups, from the reflection's workgroupSize.
export function printMsl(m: ShaderModule, entry: int32, bindings: BindingSlot[]):
	Result<string, string> {
	const printable = printableEntry(m, entry);
	if (!printable.ok) { return Result.err("printMsl: " + printable.error); }
	const reads = printable.value;
	const e = m.entries[entry];
	for (const index of reads.resources) {
		const slots = bindings.filter((s) => s.resource == index);
		if (slots.length == 0 || slots[0].nativeSlot < 0) {
			return Result.err("printMsl: resource '" + m.resources[index].name +
				"' has no MSL slot");
		}
		const error = bufferLayoutError(m, index);
		if (error != "") { return Result.err("printMsl: " + error); }
	}

	let p = new Printer();
	p.reserved = mslReservedWords();
	p.module = m;
	p.stage = e.stage;
	p.taken = ["main0", "main0_in", "main0_out", "in", "out", UPPER_LEFT, inverseName(2),
		inverseName(3), inverseName(4), "AtomicExchangeI32", "AtomicExchangeU32",
		"atomicCompareExchangeWeakI32", "atomicCompareExchangeWeakU32"];
	for (let rows = 1; rows <= 4; rows++) {
		for (const t of [modfResultType(rows as int32), frexpResultType(rows as int32)]) {
			p.taken.push(splitStructName(t));
			p.taken.push(splitHelperName(t));
		}
	}
	for (const s of m.structs) {
		p.structs.push(nameIn(p, p.taken, s.name));
		let scope: string[] = [];
		p.members.push(s.members.map((x) => nameIn(p, scope, x.name)));
	}
	p.constants = m.constants.map((c) => nameIn(p, p.taken, c.name));
	p.resources = m.resources.map((r) => nameIn(p, p.taken, r.name));
	p.ios = m.ios.map((io) => io.stage == e.stage ? nameIn(p, p.taken, io.name) : "");
	p.functions = m.functions.map((x) => nameIn(p, p.taken, x.name));
	p.workgroups = m.workgroups.map((w) => nameIn(p, p.taken, w.name));
	p.threaded = m.functions.map((_x) => new Threaded());
	for (const i of reads.functions) { p.threaded[i] = threadedOf(p, i); }

	let order: int32[] = [];
	functionOrder(m, e.functionIndex, [], order);
	const functions = order.map((i) => functionText(p, i));

	let structs: int32[] = [];
	let reached = reads.structs.map((n) => n);
	reached.sort((a, b) => a - b);
	for (const i of reached) { structOrder(m, structTypeOf(i), structs); }
	let inputs: string[] = [];
	let outputs: string[] = [];
	let params: string[] = [];
	let ordinals = [0, 0];
	for (let i = 0; i < m.ios.length; i++) {
		const io = m.ios[i];
		if (io.stage != e.stage) { continue; }
		structOrder(m, io.type, structs);
		const input = io.direction == IoDirection.In;
		const side = input ? 0 : 1;
		const attribute = interfaceAttribute(p, io, ordinals[side]);
		if (io.builtin == Builtin.None) { ordinals[side] += 1; }
		const declared = declText(p, io.type, p.ios[i]) + " " + attribute;
		if (!input) {
			outputs.push("  " + declared + ";\n");
		} else if (io.builtin == Builtin.None) {
			inputs.push("  " + declared + ";\n");
		} else {
			params.push(declared);
		}
	}
	if (inputs.length > 0) { params.splice(0, 0, "main0_in in [[stage_in]]"); }
	let declared: int32[] = [];
	for (const s of bindings) {
		if (reads.resources.includes(s.resource) && !declared.includes(s.resource)) {
			declared.push(s.resource);
			params.push(resourceParam(p, s.resource) + " " +
				bindingAttribute(m.resources[s.resource].kind, s.nativeSlot));
		}
	}

	let decls = ["#include <metal_stdlib>\n\nusing namespace metal;"];
	for (const i of structs) {
		let text = "struct " + p.structs[i] + " {\n";
		for (let k = 0; k < m.structs[i].members.length; k++) {
			text += "  " + declText(p, m.structs[i].members[k].type, p.members[i][k]) + ";\n";
		}
		decls.push(text + "};");
	}
	for (let i = 0; i < m.constants.length; i++) {
		if (!reads.constants.includes(i)) { continue; }
		const c = m.constants[i];
		decls.push("constant " + declText(p, c.type, p.constants[i]) + " = " +
			initializerText(p, c.value) + ";");
	}
	if (inputs.length > 0) { decls.push("struct main0_in {\n" + inputs.join("") + "};"); }
	if (outputs.length > 0) { decls.push("struct main0_out {\n" + outputs.join("") + "};"); }
	if (p.upperLeft) {
		decls.push("static inline float3x3 " + UPPER_LEFT + "(float4x4 m) {\n" +
			"  return float3x3(m[0].xyz, m[1].xyz, m[2].xyz);\n}");
	}
	for (let n = 2; n <= 4; n++) {
		if (p.inverses.includes(n as int32)) { decls.push(inverseText(n as int32)); }
	}
	for (let slot = 0; slot < 2; slot++) {
		if (p.exchanges[slot]) { decls.push(exchangeText(slot as int32)); }
	}
	for (const t of p.splits) { decls.push(splitText(t)); }
	for (const text of functions) { decls.push(text); }
	const returned = outputs.length > 0 ? "main0_out" : "void";
	const shared = reads.workgroups.map((w) => "  threadgroup " +
		declText(p, m.workgroups[w].type, p.workgroups[w]) + ";\n").join("");
	const call = shared + "  " + p.functions[e.functionIndex] + "(" +
		threadedArgs(p, e.functionIndex).join(", ") + ");\n";
	decls.push(stageKeyword(e.stage) + " " + returned + " main0(" + params.join(", ") + ") {\n" +
		(outputs.length > 0 ? "  main0_out out = {};\n" + call + "  return out;\n" : call) + "}");
	if (p.error != "") { return Result.err(p.error); }
	return Result.ok(decls.join("\n\n") + "\n");
}
