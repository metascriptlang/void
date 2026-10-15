// glsl(entry) reads a vertex entry, or a fragment entry that reads no varyings, and returns it as
// Vulkan-style GLSL 450 for sokol-shdc: the signature becomes the stage's interface, the body
// becomes main(), and each function and module constant the body reaches is defined above main(),
// after what it reads. glslLinked(fragment, vertex) does the same for a fragment fed by that vertex
// entry, after checking its varyings are the vertex outputs: shdc numbers varyings in declaration
// order, so a name, type or place that differs would read another output with no error.
// The node walk sits in functions nested in the macro body: only there are Node fields readable.

import {
	DeclKind,
	Node,
	NodeKind,
	SymbolKind,
	TypeKind,
	bindSym,
	childAt,
	childCount,
	floatValue,
	getImpl,
	getType,
	getTypeImpl,
	intValue,
	sameType,
	symKind,
	typeKind,
} from "std/meta";
import {
	Mat2x2f,
	Mat3x3f,
	Mat4x4f,
	Sampler,
	StorageTexture2d,
	Texture2d,
	Texture2dArray,
	Texture2dU32,
	Vec2f,
	Vec2i,
	Vec2u,
	Vec3f,
	Vec3i,
	Vec3u,
	Vec4f,
	Vec4i,
	Vec4u,
	textureLoad,
} from "./std";

// GLSL 4.50 keywords and reserved words (section 3.6), builtin functions (section 8) and the
// texture and sampler types of Vulkan GLSL.
function glslReservedWords(): string[] {
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

function isGlslIdentifier(name: string): boolean {
	if (name.startsWith("gl_") || name.indexOf("__") >= 0) { return false; }
	for (let i = 0; i < name.length; i++) {
		const c = name.charCodeAt(i);
		const letter = (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95;
		if (!letter && !(i > 0 && c >= 48 && c <= 57)) { return false; }
	}
	return true;
}

export macro glsl(entry: Node): Node {
	const signature = getType(entry);
	if (signature == null || signature.kind != NodeKind.TypeFunction) {
		error("glsl: the entry must be a function", entry);
	}
	const output = getTypeImpl(signature.typExprReturn);
	let vertex = false;
	if (output != null && output.kind == NodeKind.TypeObject) {
		for (const decorators of output.typExprFieldDecorators) {
			for (const d of decorators) {
				if (d.macroName == "builtin") { vertex = true; }
			}
		}
	}
	for (const t of signature.typExprParams) {
		const fields = getTypeImpl(t);
		if (vertex || fields == null || fields.kind != NodeKind.TypeObject) { continue; }
		let bindings = false;
		let features = 0;
		let varyings = 0;
		for (const decorators of fields.typExprFieldDecorators) {
			let builtin = false;
			for (const d of decorators) {
				if (d.macroName == "binding") { bindings = true; }
				if (d.macroName == "feature") { features += 1; }
				if (d.macroName == "builtin") { builtin = true; }
			}
			if (!builtin) { varyings += 1; }
		}
		const key = features == fields.typExprFieldNames.length;
		if (!bindings && !key && varyings > 0) {
			error("glsl: a fragment entry that reads varyings is written " +
				"glslLinked(fragment, vertex), so its varyings are checked against the vertex " +
				"outputs", entry);
		}
	}
	return {
		kind: NodeKind.CallExpr,
		line: entry.line,
		column: entry.column,
		callee: bindSym("glslStage"),
		arguments: [entry, { kind: NodeKind.ArrayLiteral, line: entry.line, column: entry.column,
			elements: [] }, entry],
	};
}

export macro glslLinked(fragment: Node, vertex: Node): Node {
	function fieldsAt(t: Node | null, at: Node): Node {
		const fields = t == null ? null : getTypeImpl(t);
		if (fields == null || fields.kind != NodeKind.TypeObject) {
			error("glslLinked: the stage interface is not a struct", at);
		}
		return fields;
	}

	function isVarying(fields: Node, f: number): boolean {
		for (const d of fields.typExprFieldDecorators[f]) {
			if (d.macroName == "builtin") { return false; }
		}
		return true;
	}

	function varyingNames(t: Node | null, at: Node): string[] {
		const fields = fieldsAt(t, at);
		let names: string[] = [];
		for (let f = 0; f < fields.typExprFieldNames.length; f++) {
			if (isVarying(fields, f)) { names.push(fields.typExprFieldNames[f]); }
		}
		return names;
	}

	function varyingFeatures(t: Node | null, at: Node): string[] {
		const fields = fieldsAt(t, at);
		let gates: string[] = [];
		for (let f = 0; f < fields.typExprFieldNames.length; f++) {
			if (!isVarying(fields, f)) { continue; }
			let gate = "";
			for (const d of fields.typExprFieldDecorators[f]) {
				if (d.macroName == "feature" && d.macroArgs.length == 1 &&
					d.macroArgs[0].kind == NodeKind.Identifier) {
					gate = d.macroArgs[0].name;
				}
			}
			gates.push(gate);
		}
		return gates;
	}

	function varyingTypes(t: Node | null, at: Node): Node[] {
		const fields = fieldsAt(t, at);
		let types: Node[] = [];
		for (let f = 0; f < fields.typExprFieldNames.length; f++) {
			if (isVarying(fields, f)) { types.push(fields.typExprFieldTypes[f]); }
		}
		return types;
	}

	const fs = getType(fragment);
	const vs = getType(vertex);
	if (fs == null || fs.kind != NodeKind.TypeFunction || vs == null ||
		vs.kind != NodeKind.TypeFunction) {
		error("glslLinked: both stages must be functions", fragment);
	}
	let input: Node | null = null;
	for (const t of fs.typExprParams) {
		const fields = getTypeImpl(t);
		if (fields == null || fields.kind != NodeKind.TypeObject) { continue; }
		let bindings = false;
		let features = 0;
		for (const decorators of fields.typExprFieldDecorators) {
			for (const d of decorators) {
				if (d.macroName == "binding") { bindings = true; }
				if (d.macroName == "feature") { features += 1; }
			}
		}
		if (!bindings && features < fields.typExprFieldNames.length) { input = t; }
	}
	const reads = varyingNames(input, fragment);
	const writes = varyingNames(vs.typExprReturn, vertex);
	const readTypes = varyingTypes(input, fragment);
	const writeTypes = varyingTypes(vs.typExprReturn, vertex);
	const readGates = varyingFeatures(input, fragment);
	const writeGates = varyingFeatures(vs.typExprReturn, vertex);
	for (let i = 0; i < reads.length || i < writes.length; i++) {
		const read = i < reads.length ? reads[i] : "";
		const written = i < writes.length ? writes[i] : "";
		if (read != written) {
			error("glslLinked: varying " + String(i) + " is '" + read +
				"' in the fragment input and '" + written +
				"' in the vertex output; they match by name, type and order", fragment);
		}
		if (!sameType(readTypes[i], writeTypes[i])) {
			error("glslLinked: varying '" + read + "' has another type in the vertex output",
				fragment);
		}
		if (readGates[i] != writeGates[i]) {
			error("glslLinked: varying '" + read + "' is declared under another @feature in the " +
				"vertex output", fragment);
		}
	}
	return {
		kind: NodeKind.CallExpr,
		line: fragment.line,
		column: fragment.column,
		callee: bindSym("glslStage"),
		arguments: [fragment, { kind: NodeKind.ArrayLiteral, line: fragment.line,
			column: fragment.column, elements: [] }, vertex],
	};
}

// glslCompute(entry, [x, y, z]) for a compute entry: its workgroup size is WGSL's
// @workgroup_size, written where the stage is generated as shdc's local_size.
export macro glslCompute(entry: Node, workgroupSize: Node): Node {
	if (workgroupSize.kind != NodeKind.ArrayLiteral || workgroupSize.elements.length < 1 ||
		workgroupSize.elements.length > 3) {
		error("glslCompute: the workgroup size is an array of one to three numbers", workgroupSize);
	}
	return {
		kind: NodeKind.CallExpr,
		line: entry.line,
		column: entry.column,
		callee: bindSym("glslStage"),
		arguments: [entry, workgroupSize, entry],
	};
}

// The stage both glsl and glslLinked expand to, once their checks hold.
export macro glslStage(entry: Node, workgroupSize: Node, feeder: Node): Node {
	function fail(n: Node, msg: string): never {
		error("glsl: " + msg, n);
	}

	const stdSymbol = bindSym("textureLoad");
	if (stdSymbol == null || stdSymbol.resolvedSym == null) {
		fail(entry, "./std did not resolve");
	}
	const stdModule = stdSymbol.resolvedSym.modulePath;
	const textureType = getTypeImpl(Texture2d);
	const samplerType = getTypeImpl(Sampler);
	const storageTextureType = getTypeImpl(StorageTexture2d);
	const uintTextureType = getTypeImpl(Texture2dU32);
	const arrayTextureType = getTypeImpl(Texture2dArray);
	const vectorTypes = [
		getTypeImpl(Vec2f),
		getTypeImpl(Vec3f),
		getTypeImpl(Vec4f),
		getTypeImpl(Vec2i),
		getTypeImpl(Vec3i),
		getTypeImpl(Vec4i),
		getTypeImpl(Vec2u),
		getTypeImpl(Vec3u),
		getTypeImpl(Vec4u),
		getTypeImpl(Mat2x2f),
		getTypeImpl(Mat3x3f),
		getTypeImpl(Mat4x4f),
	];
	const vectorNames = [
		"vec2", "vec3", "vec4", "ivec2", "ivec3", "ivec4", "uvec2", "uvec3", "uvec4", "mat2",
		"mat3", "mat4",
	];

	function matrixColumns(n: Node): boolean {
		if (n.kind != NodeKind.MemberExpr || n.property != "columns") { return false; }
		const t = getType(n.object);
		for (let i = vectorNames.indexOf("mat2"); i < vectorTypes.length; i++) {
			if (t != null && sameType(t, vectorTypes[i])) { return true; }
		}
		return false;
	}

	function glslType(t: Node | null, at: Node): string {
		if (t == null) { fail(at, "the expression has no type"); }
		const kind = typeKind(t);
		if (kind == TypeKind.Float32) { return "float"; }
		if (kind == TypeKind.Int32) { return "int"; }
		if (kind == TypeKind.Uint32) { return "uint"; }
		if (kind == TypeKind.Boolean) { return "bool"; }
		if (kind == TypeKind.SizedArray) {
			return glslType(t.typExprElement, at) + "[" + String(t.typExprSize) + "]";
		}
		for (let i = 0; i < vectorTypes.length; i++) {
			if (sameType(t, vectorTypes[i])) { return vectorNames[i]; }
		}
		fail(at, "a shader value is float32, int32, uint32, boolean, a ./std vector or matrix, " +
			"or a struct of those");
	}

	function decorator(decorators: Node[], name: string): Node | null {
		for (const d of decorators) {
			if (d.macroName == name) { return d; }
		}
		return null;
	}

	function argument(d: Node, at: Node): Node {
		if (d.macroArgs.length != 1) { fail(at, "@" + d.macroName + " takes one argument"); }
		return d.macroArgs[0];
	}

	function argumentName(d: Node, at: Node): string {
		const a = argument(d, at);
		if (a.kind != NodeKind.Identifier) { fail(at, "@" + d.macroName + " takes a name"); }
		return a.name;
	}

	function argumentNumber(d: Node, at: Node): string {
		const a = argument(d, at);
		if (a.kind != NodeKind.NumberLiteral) { fail(at, "@" + d.macroName + " takes a number"); }
		return String(intValue(a));
	}

	function fieldsOf(t: Node | null): Node | null {
		if (t == null) { return null; }
		const fields = getTypeImpl(t);
		return fields != null && fields.kind == NodeKind.TypeObject ? fields : null;
	}

	function everyDecorated(fields: Node, name: string): boolean {
		for (const decorators of fields.typExprFieldDecorators) {
			if (decorator(decorators, name) == null) { return false; }
		}
		return true;
	}

	function hasDecorator(fields: Node, name: string): boolean {
		for (const decorators of fields.typExprFieldDecorators) {
			if (decorator(decorators, name) != null) { return true; }
		}
		return false;
	}

	function isAuthorStruct(t: Node | null): boolean {
		if (t == null || fieldsOf(t) == null) { return false; }
		const opaque = [textureType, samplerType, storageTextureType, uintTextureType,
			arrayTextureType];
		for (const own of vectorTypes.concat(opaque)) {
			if (sameType(t, own)) { return false; }
		}
		return true;
	}

	const fn = getImpl(entry);
	const signature = getType(entry);
	if (fn == null || fn.kind != NodeKind.FunctionDecl || signature == null ||
		signature.kind != NodeKind.TypeFunction || entry.resolvedSym == null) {
		fail(entry, "the entry must be a function");
	}

	const outputType = signature.typExprReturn;
	let vectorOutput = false;
	for (const v of vectorTypes) {
		if (outputType != null && sameType(outputType, v)) { vectorOutput = true; }
	}
	const outputs = vectorOutput ? null : fieldsOf(outputType);
	const vertex = outputs != null && hasDecorator(outputs, "builtin");
	const computeBuiltins = ["globalInvocationId", "localInvocationId", "localInvocationIndex",
		"workgroupId", "numWorkgroups"];
	const computeNames = ["gl_GlobalInvocationID", "gl_LocalInvocationID",
		"gl_LocalInvocationIndex", "gl_WorkGroupID", "gl_NumWorkGroups"];
	let compute = workgroupSize.elements.length > 0;

	let inputType: Node | null = null;
	let bindingsType: Node | null = null;
	let keyType: Node | null = null;
	for (let i = 0; i < signature.typExprParams.length; i++) {
		const name = signature.typExprParamNames[i];
		const t = signature.typExprParams[i];
		const fields = fieldsOf(t);
		if (fields == null) {
			fail(entry, "parameter '" + name +
				"' is not the input, bindings or program key struct");
		}
		for (const decorators of fields.typExprFieldDecorators) {
			const builtin = decorator(decorators, "builtin");
			if (builtin != null && computeBuiltins.indexOf(argumentName(builtin, entry)) >= 0) {
				if (!compute) {
					fail(entry, "a compute entry is written glslCompute(entry, [x, y, z]), " +
						"with its workgroup size");
				}
			}
		}
		if (hasDecorator(fields, "binding")) {
			if (bindingsType != null) { fail(entry, "two bindings structs: '" + name + "'"); }
			bindingsType = t;
		} else if (fields.typExprFieldNames.length > 0 && everyDecorated(fields, "feature")) {
			if (keyType != null) { fail(entry, "two program key structs: '" + name + "'"); }
			keyType = t;
		} else {
			if (inputType != null) { fail(entry, "two stage input structs: '" + name + "'"); }
			inputType = t;
		}
	}

	function isType(n: Node, t: Node | null): boolean {
		if (t == null) { return false; }
		const own = getType(n);
		return own != null && sameType(own, t);
	}

	// Declarations come out in interface order, each under the conditions its reads run under, and
	// are left out when nothing reads them: a declared but unread uniform or texture is still one
	// the draw must bind. A condition is a preprocessor expression over the program key's
	// features; `features` holds the clauses around the code being written.
	let declNames: string[] = [];
	let declTexts: string[] = [];
	let declContexts: string[][] = [];
	let declAlways: boolean[] = [];
	let declFixed: string[] = [];
	let features: string[] = [];
	const reservedWords = glslReservedWords();
	let valueNames = ["main", "fragColor"];
	let functionNames: string[] = [];
	let functionSignatures: string[] = [];
	let functionKeys: string[] = [];
	let openKeys: string[] = [];
	let constantNames: string[] = [];
	let constantKeys: string[] = [];
	let constants = "";
	let functions = "";
	let scopeModule = "";
	let paramNames: string[] = [];
	let paramGlslNames: string[] = [];
	let localKeys: string[] = [];
	let localGlslNames: string[] = [];
	let inHelper = false;
	let breakOwners: string[] = [];
	let structTypes: Node[] = [];
	let structNames: string[] = [];
	let structFields: string[][] = [];
	let structGlslFields: string[][] = [];

	let globals: string[] = [];
	let storageNames: string[] = [];
	let storageElements: Node[] = [];
	let storageHeads: string[] = [];
	let locals: string[] = [];
	let memberNames: string[] = [];
	let memberSlots: string[] = [];
	function claim(name: string, at: Node): void {
		if (globals.indexOf(name) >= 0) {
			fail(at, "'" + name + "' names two things in one stage");
		}
		globals.push(name);
	}

	// Blocks at one binding are alternatives a variant chooses between, so they may share members.
	function claimMember(name: string, slot: string, at: Node): void {
		const m = memberNames.indexOf(name);
		if (m >= 0 && memberSlots[m] == slot) { return; }
		claim(name, at);
		memberNames.push(name);
		memberSlots.push(slot);
	}

	function declare(name: string, text: string, always: boolean): void {
		claim(name, entry);
		declNames.push(name);
		declTexts.push(text);
		declContexts.push([]);
		declAlways.push(always);
		declFixed.push("");
	}

	function declareUnder(name: string, text: string, condition: string): void {
		declare(name, text, condition == "");
		declFixed[declFixed.length - 1] = condition;
	}

	function grouped(condition: string): string {
		return condition.indexOf(" ") < 0 ? condition : "(" + condition + ")";
	}

	function useUnder(name: string, gates: string[]): void {
		const i = declNames.indexOf(name);
		if (i < 0 || declFixed[i] != "") { return; }
		let clauses: string[] = [];
		for (const g of gates) { clauses.push(grouped(g)); }
		const context = clauses.join(" && ");
		if (declContexts[i].indexOf(context) < 0) { declContexts[i].push(context); }
	}

	// A helper's body is written once, with no features on; what it reads is kept as a record
	// and counted at each call, under the features around that call.
	let recordKeys: string[] = [];
	let records: string[][] = [];
	let recording = -1;

	function record(name: string): void {
		records[recording].push(name + "\t" + features.join(";;"));
	}

	function use(name: string): void {
		if (recording >= 0) {
			record(name);
			return;
		}
		useUnder(name, features.slice(0));
	}

	function union(a: string[], b: string[]): string[] {
		let all = a.slice(0);
		for (const g of b) {
			if (g != "" && all.indexOf(g) < 0) { all.push(g); }
		}
		return all;
	}

	function replay(key: string, gates: string[]): void {
		useUnder("call:" + key, gates);
		for (const item of records[recordKeys.indexOf(key)]) {
			const tab = item.indexOf("\t");
			const name = item.slice(0, tab);
			const under = union(gates, item.slice(tab + 1).split(";;"));
			if (name.startsWith("call:")) {
				replay(name.replace("call:", ""), under);
			} else {
				useUnder(name, under);
			}
		}
	}

	function opening(condition: string): string {
		const simple = condition.indexOf(" ") < 0 && condition.endsWith(")");
		if (simple && condition.startsWith("defined(")) {
			return "#ifdef " + condition.slice(8, condition.length - 1);
		}
		if (simple && condition.startsWith("!defined(")) {
			return "#ifndef " + condition.slice(9, condition.length - 1);
		}
		return "#if " + condition;
	}

	function featureCondition(decorators: Node[], at: Node): string {
		const feature = decorator(decorators, "feature");
		return feature == null ? "" : "defined(" + argumentName(feature, at) + ")";
	}

	function interpolation(t: Node): string {
		const spelled = glslType(t.kind == NodeKind.TypeArray ? t.typExprElement : t, entry);
		const integral = spelled.startsWith("int") || spelled.startsWith("uint") ||
			spelled.startsWith("ivec") || spelled.startsWith("uvec");
		return integral ? "flat " : "";
	}

	function member(t: Node, name: string, at: Node): string {
		if (isAuthorStruct(t.kind == NodeKind.TypeArray ? t.typExprElement : t)) {
			fail(at, "interface field '" + name + "' is a struct: a uniform block member, " +
				"attribute, varying or output is a scalar, vector or matrix");
		}
		if (t.kind == NodeKind.TypeArray && t.typExprSize > 0) {
			return glslType(t.typExprElement, at) + " " + name + "[" + String(t.typExprSize) + "]";
		}
		return glslType(t, at) + " " + name;
	}

	const bindings = fieldsOf(bindingsType);
	if (bindings != null) {
		for (let f = 0; f < bindings.typExprFieldNames.length; f++) {
			const name = bindings.typExprFieldNames[f];
			const t = bindings.typExprFieldTypes[f];
			const decorators = bindings.typExprFieldDecorators[f];
			const binding = decorator(decorators, "binding");
			if (binding == null) { fail(entry, "binding '" + name + "' has no @binding(n)"); }
			const slot = "layout(binding=" + argumentNumber(binding, entry) + ") uniform ";
			const sampleType = decorator(decorators, "sampleType");
			const samplerKind = decorator(decorators, "samplerType");
			const access = decorator(decorators, "access");
			const writes = access != null && argumentName(access, entry) == "read_write";
			if (access != null && !writes && argumentName(access, entry) != "read" &&
				argumentName(access, entry) != "write") {
				fail(entry, "binding '" + name + "': @access is read, write or read_write");
			}
			const shape = getTypeImpl(t);
			if (shape != null && shape.kind == NodeKind.TypeArray && shape.typExprSize < 0) {
				if (writes && !compute) {
					fail(entry, "storage buffer '" + name + "' is written only in a compute entry");
				}
				storageNames.push(name);
				storageElements.push(shape.typExprElement);
				storageHeads.push("layout(binding=" + argumentNumber(binding, entry) + ") " +
					(writes ? "" : "readonly ") + "buffer " + name + "Buffer {\n    ");
				declare(name, "", false);
				continue;
			}
			if (sameType(t, storageTextureType)) {
				if (!compute) {
					fail(entry, "storage texture '" + name + "' is a compute binding");
				}
				const format = decorator(decorators, "format");
				if (format == null) {
					fail(entry, "storage texture '" + name + "' has no @format(texel format)");
				}
				const texel = argumentName(format, entry);
				const formats = ["rgba8unorm", "rgba8snorm", "rgba8uint", "rgba16float",
					"rgba32float", "r32float", "r32uint", "rg32float"];
				const spellings = ["rgba8", "rgba8_snorm", "rgba8ui", "rgba16f", "rgba32f", "r32f",
					"r32ui", "rg32f"];
				const at = formats.indexOf(texel);
				if (at < 0) {
					fail(entry, "storage texture format '" + texel + "' has no GLSL form yet");
				}
				const writeOnly = access == null || argumentName(access, entry) == "write";
				const mode = writeOnly ? "writeonly " : writes ? "" : "readonly ";
				declare(name, "layout(binding=" + argumentNumber(binding, entry) + ", " +
					spellings[at] + ") uniform " + mode + "image2D " + name + ";\n", false);
				continue;
			}
			if (sameType(t, uintTextureType) || sameType(t, arrayTextureType)) {
				const uint = sameType(t, uintTextureType);
				const tag = uint ? "@image_sample_type " + name + " uint\n" : "";
				const kind = uint ? "utexture2D " : "texture2DArray ";
				declare(name, tag + slot + kind + name + ";\n", false);
			} else if (sameType(t, textureType)) {
				const tag = sampleType == null ? "" : "@image_sample_type " + name + " " +
					argumentName(sampleType, entry) + "\n";
				declare(name, tag + slot + "texture2D " + name + ";\n", false);
			} else if (sameType(t, samplerType)) {
				const tag = samplerKind == null ? "" : "@sampler_type " + name + " " +
					argumentName(samplerKind, entry) + "\n";
				declare(name, tag + slot + "sampler " + name + ";\n", false);
			} else {
				const block = fieldsOf(t);
				if (block == null) {
					fail(entry, "binding '" + name +
						"' is not a texture, a sampler or a uniform struct");
				}
				let text = slot + name + " {\n";
				for (let m = 0; m < block.typExprFieldNames.length; m++) {
					const memberName = block.typExprFieldNames[m];
					claimMember(memberName, slot, entry);
					const blockMember = member(block.typExprFieldTypes[m], memberName, entry);
					text += "    " + blockMember + ";\n";
				}
				declare(name, text + "};\n", false);
			}
		}
	}

	const inputs = fieldsOf(inputType);
	let builtinInputs: string[] = [];
	let builtinInputNames: string[] = [];
	let attributeNames: string[] = [];
	const feederType = getType(feeder);
	if (feederType != null && feederType.kind == NodeKind.TypeFunction) {
		const fedOutputs = fieldsOf(feederType.typExprReturn);
		const feedsFragments = fedOutputs != null && hasDecorator(fedOutputs, "builtin");
		for (const t of feedsFragments ? feederType.typExprParams : []) {
			const fields = fieldsOf(t);
			if (fields == null || hasDecorator(fields, "binding") ||
				fields.typExprFieldNames.length > 0 && everyDecorated(fields, "feature")) {
				continue;
			}
			for (let f = 0; f < fields.typExprFieldNames.length; f++) {
				if (decorator(fields.typExprFieldDecorators[f], "builtin") == null) {
					attributeNames.push(fields.typExprFieldNames[f]);
				}
			}
		}
	}

	function varyingName(name: string): string {
		let unique = name;
		let suffix = 0;
		while (attributeNames.indexOf(unique) >= 0) {
			suffix += 1;
			unique = name + "_" + String(suffix);
		}
		return unique;
	}

	if (inputs != null) {
		for (let f = 0; f < inputs.typExprFieldNames.length; f++) {
			const name = inputs.typExprFieldNames[f];
			const builtin = decorator(inputs.typExprFieldDecorators[f], "builtin");
			if (builtin == null) {
				// Every input is declared, read or not: shdc numbers them in declaration order.
				if (vertex && inputs.typExprFieldTypes[f].kind == NodeKind.TypeArray) {
					fail(entry, "attribute '" + name + "' is an array, and shdc's GLES3 " +
						"(WebGL2) output has no array vertex inputs: declare one attribute each");
				}
				const glslName = vertex ? name : varyingName(name);
				const varying = member(inputs.typExprFieldTypes[f], glslName, entry);
				const gate = featureCondition(inputs.typExprFieldDecorators[f], entry);
				const qualifier = vertex ? "" : interpolation(inputs.typExprFieldTypes[f]);
				declareUnder(glslName, qualifier + "in " + varying + ";\n", gate);
				continue;
			}
			const which = argumentName(builtin, entry);
			const computeAt = computeBuiltins.indexOf(which);
			const glslName = compute ? (computeAt >= 0 ? computeNames[computeAt] : "") :
				vertex ? (which == "vertexIndex" ? "gl_VertexIndex" :
					which == "instanceIndex" ? "gl_InstanceIndex" : "") :
				which == "position" ? "gl_FragCoord" :
				which == "frontFacing" ? "gl_FrontFacing" : "";
			if (glslName == "") {
				fail(entry, "input field '" + name + "': @builtin(" + which +
					") has no GLSL form yet");
			}
			builtinInputs.push(glslName);
			builtinInputNames.push(name);
		}
	}

	let outputNames: string[] = [];
	let outputTargets: string[] = [];
	let outputFeatures: string[] = [];
	const noOutput = outputType != null && typeKind(outputType) == TypeKind.Void;
	if (compute && !noOutput) { fail(entry, "a compute entry returns nothing"); }
	if (noOutput) {
		if (vertex) { fail(entry, "a vertex entry returns its outputs"); }
	} else if (outputs == null) {
		const colour = glslType(outputType, entry);
		declare("fragColor", "layout(location=0) out " + colour + " fragColor;\n", true);
	} else {
		for (let f = 0; f < outputs.typExprFieldNames.length; f++) {
			const name = outputs.typExprFieldNames[f];
			const decorators = outputs.typExprFieldDecorators[f];
			const gate = featureCondition(decorators, entry);
			outputNames.push(name);
			outputFeatures.push(gate);
			const builtin = decorator(decorators, "builtin");
			if (builtin != null) {
				if (!vertex || argumentName(builtin, entry) != "position") {
					fail(entry, "output field '" + name +
						"': only a vertex @builtin(position) yet");
				}
				outputTargets.push("gl_Position");
				continue;
			}
			const t = outputs.typExprFieldTypes[f];
			if (vertex) {
				const glslName = varyingName(name);
				outputTargets.push(glslName);
				const varying = member(t, glslName, entry);
				declareUnder(glslName, interpolation(t) + "out " + varying + ";\n", gate);
				continue;
			}
			outputTargets.push(name);
			const location = decorator(decorators, "location");
			if (location == null) {
				fail(entry, "fragment output '" + name + "' has no @location(n)");
			}
			const slot = "layout(location=" + argumentNumber(location, entry) + ") out ";
			declareUnder(name, slot + member(t, name, entry) + ";\n", gate);
		}
	}

	function isInterface(t: Node | null): boolean {
		if (t == null) { return false; }
		for (const own of [inputType, bindingsType, keyType]) {
			if (own != null && sameType(t, own)) { return true; }
		}
		return false;
	}

	function declKey(module: string, decl: Node): string {
		return module + ":" + String(decl.line) + ":" + String(decl.column);
	}

	function declaration(n: Node): Node {
		const decl = getImpl(n);
		if (decl == null) { fail(n, "'" + n.name + "' has no declaration"); }
		return decl;
	}

	function isTaken(name: string, parameterTypes: string, local: boolean): boolean {
		if (reservedWords.includes(name) || valueNames.includes(name) || globals.includes(name)) {
			return true;
		}
		if (parameterTypes != "") { return functionSignatures.includes(name + parameterTypes); }
		if (functionNames.includes(name) || constantNames.includes(name)) { return true; }
		return local && (paramGlslNames.includes(name) || localGlslNames.includes(name));
	}

	function glslName(name: string, at: Node, parameterTypes: string, local: boolean): string {
		if (!isGlslIdentifier(name)) {
			fail(at, "'" + name + "' is no GLSL name: only letters, digits and '_', " +
				"without '__' or the prefix 'gl_'");
		}
		let unique = name;
		let suffix = 0;
		while (isTaken(unique, parameterTypes, local)) {
			suffix += 1;
			unique = name + "_" + String(suffix);
		}
		return unique;
	}

	function valueType(t: Node | null, at: Node): string {
		if (t != null && typeKind(t) == TypeKind.SizedArray) {
			return valueType(t.typExprElement, at) + "[" + String(t.typExprSize) + "]";
		}
		return t != null && isAuthorStruct(t) ? structName(t, at) : glslType(t, at);
	}

	function structName(t: Node, at: Node): string {
		for (let i = 0; i < structTypes.length; i++) {
			if (sameType(t, structTypes[i])) { return structNames[i]; }
		}
		const fields = fieldsOf(t);
		const typeName = fields.typExprTypeName;
		if (isInterface(t)) {
			fail(at, "'" + typeName + "' is a stage interface struct, read one field at a time");
		}
		let glslFields: string[] = [];
		let text = "";
		for (let f = 0; f < fields.typExprFieldNames.length; f++) {
			const name = fields.typExprFieldNames[f];
			const ft = fields.typExprFieldTypes[f];
			const element = ft.kind == NodeKind.TypeArray ? ft.typExprElement : ft;
			if (sameType(element, textureType) || sameType(element, samplerType)) {
				fail(at, "struct '" + typeName + "' holds the texture or sampler '" + name +
					"': a GLSL struct holds values, so a binding is passed on its own");
			}
			if (!isGlslIdentifier(name)) {
				fail(at, "field '" + name + "' of struct '" + typeName + "' is no GLSL name");
			}
			let unique = name;
			let suffix = 0;
			while (reservedWords.includes(unique) || glslFields.includes(unique) ||
				unique != name && fields.typExprFieldNames.includes(unique)) {
				suffix += 1;
				unique = name + "_" + String(suffix);
			}
			glslFields.push(unique);
			text += "    " + valueType(ft, at) + " " + unique + ";\n";
		}
		const spelled = glslName(typeName, at, "", false);
		valueNames.push(spelled);
		structTypes.push(t);
		structNames.push(spelled);
		structFields.push(fields.typExprFieldNames);
		structGlslFields.push(glslFields);
		declare("struct:" + spelled, "struct " + spelled + " {\n" + text + "};\n", true);
		return spelled;
	}

	function field(n: Node): string {
		const t = getType(n.object);
		if (t == null || !isAuthorStruct(t)) { return n.property; }
		const s = structNames.indexOf(structName(t, n));
		return structGlslFields[s][structFields[s].indexOf(n.property)];
	}

	function construction(n: Node): string {
		const t = getType(n);
		const type = valueType(t, n);
		const fields = fieldsOf(t);
		let args: string[] = [];
		for (let f = 0; f < fields.typExprFieldNames.length; f++) {
			const name = fields.typExprFieldNames[f];
			const k = n.keys.indexOf(name);
			if (k < 0) {
				fail(n, "the literal leaves out field '" + name +
					"', and GLSL constructs a struct from every field");
			}
			const kind = typeKind(fields.typExprFieldTypes[f]);
			if (!isAuthorStruct(t) && kind != TypeKind.Float32 && kind != TypeKind.Int32 &&
				kind != TypeKind.Uint32 && kind != TypeKind.Boolean) {
				fail(n, "a ./std matrix is built with its constructor, as mat4x4f(...)");
			}
			args.push(expr(n.properties[k]));
		}
		return type + "(" + args.join(", ") + ")";
	}

	function gather(n: Node, module: string, locals: string[], constant: Node | null): void {
		if (n.kind == NodeKind.VariableDecl) { locals.push(declKey(module, n)); }
		if (n.kind == NodeKind.Identifier && n.resolvedSym != null &&
			n.resolvedSym.modulePath != stdModule) {
			const kind = symKind(n);
			if (kind == SymbolKind.Function) {
				if (constant != null) {
					fail(constant, "module constant '" + constant.declName + "' calls '" + n.name +
						"', and a GLSL constant takes a constant expression");
				}
				defineFunction(n);
			} else if (kind == SymbolKind.Variable &&
				!locals.includes(declKey(n.resolvedSym.modulePath, declaration(n)))) {
				defineConstant(n);
			}
		}
		for (let i = 0; i < childCount(n); i++) { gather(childAt(n, i), module, locals, constant); }
	}

	function defineConstant(n: Node): void {
		const decl = declaration(n);
		const module = n.resolvedSym.modulePath;
		const key = declKey(module, decl);
		if (constantKeys.includes(key)) { return; }
		if (decl.declKind != DeclKind.Const) {
			fail(n, "'" + n.name + "' is a module variable: a shader reads only module constants");
		}
		gather(decl.initializer, module, [], decl);
		const name = glslName(decl.declName, n, "", false);
		declare("const:" + key, "const " + valueType(getType(n), n) + " " + name + " = " +
			expr(decl.initializer) + ";\n", true);
		constantKeys.push(key);
		constantNames.push(name);
	}

	function defineFunction(callee: Node): void {
		const helper = getImpl(callee);
		const helperType = getType(callee);
		if (helper == null || helper.kind != NodeKind.FunctionDecl || helperType == null ||
			helperType.kind != NodeKind.TypeFunction) {
			fail(callee, "'" + callee.name + "' is not a function");
		}
		const module = callee.resolvedSym.modulePath;
		const key = declKey(module, helper);
		if (openKeys.includes(key)) {
			fail(callee, "'" + helper.fnName + "' calls itself, and GLSL has no recursion");
		}
		if (functionKeys.includes(key)) { return; }
		openKeys.push(key);
		gather(helper.fnBody, module, [], null);
		openKeys.pop();

		let types: string[] = [];
		let kept: string[] = [];
		for (let i = 0; i < helperType.typExprParams.length; i++) {
			const t = helperType.typExprParams[i];
			if (isInterface(t)) { continue; }
			types.push(valueType(t, callee));
			kept.push(helperType.typExprParamNames[i]);
		}
		const parameterTypes = "(" + types.join(", ") + ")";
		const name = glslName(helper.fnName, callee, parameterTypes, false);
		functionKeys.push(key);
		functionNames.push(name);
		functionSignatures.push(name + parameterTypes);

		enterScope(module, kept);
		let params: string[] = [];
		for (let i = 0; i < types.length; i++) {
			paramGlslNames.push(glslName(paramNames[i], callee, "", true));
			params.push(types[i] + " " + paramGlslNames[i]);
		}
		recordKeys.push(key);
		records.push([]);
		const outer = recording;
		recording = records.length - 1;
		inHelper = true;
		const text = body(helper.fnBody, "    ");
		inHelper = false;
		recording = outer;
		declare("call:" + key, valueType(helperType.typExprReturn, callee) + " " + name + "(" +
			params.join(", ") + ") {\n" + text + "}\n", false);
	}

	function enterScope(module: string, names: string[]): void {
		scopeModule = module;
		paramNames = names;
		paramGlslNames = [];
		localKeys = [];
		localGlslNames = [];
	}

	function local(n: Node): string {
		const name = glslName(n.declName, n, "", true);
		localKeys.push(declKey(scopeModule, n));
		localGlslNames.push(name);
		return name;
	}

	function identifier(n: Node): string {
		const kind = symKind(n);
		if (kind == SymbolKind.Parameter && paramNames.includes(n.name)) {
			return paramGlslNames[paramNames.indexOf(n.name)];
		}
		if (kind == SymbolKind.Variable && n.resolvedSym != null) {
			const key = declKey(n.resolvedSym.modulePath, declaration(n));
			if (localKeys.includes(key)) { return localGlslNames[localKeys.indexOf(key)]; }
			if (constantKeys.includes(key)) { return constantNames[constantKeys.indexOf(key)]; }
		}
		fail(n, "'" + n.name + "' has no GLSL form yet");
	}

	function call(n: Node, callee: Node, impl: Node): string {
		const key = declKey(callee.resolvedSym.modulePath, impl);
		if (callee.kind != NodeKind.Identifier || !functionKeys.includes(key)) {
			fail(n, "method calls have no GLSL form yet");
		}
		if (recording >= 0) {
			record("call:" + key);
		} else {
			replay(key, features.slice(0));
		}
		let args: string[] = [];
		for (const a of n.arguments) {
			if (!isInterface(getType(a))) { args.push(expr(a)); }
		}
		return functionNames[functionKeys.indexOf(key)] + "(" + args.join(", ") + ")";
	}

	function number(n: Node): string {
		const kind = typeKind(getType(n));
		if (kind == TypeKind.Float32 || kind == TypeKind.Float64) {
			const text = String(floatValue(n));
			return text.indexOf(".") >= 0 || text.indexOf("e") >= 0 ? text : text + ".0";
		}
		return String(intValue(n));
	}

	function featureOf(n: Node): string {
		if (n.kind == NodeKind.MemberExpr && isType(n.object, keyType)) {
			const keys = fieldsOf(keyType);
			const f = keys.typExprFieldNames.indexOf(n.property);
			const feature = decorator(keys.typExprFieldDecorators[f], "feature");
			if (feature == null) {
				fail(n, "key field '" + n.property + "' has no @feature(NAME)");
			}
			return "defined(" + argumentName(feature, n) + ")";
		}
		if (n.kind == NodeKind.UnaryExpr && n.unaryOp == "!") {
			const inner = featureOf(n.operand);
			return inner == "" ? "" : "!" + grouped(inner);
		}
		if (n.kind == NodeKind.BinaryExpr && (n.operator == "&&" || n.operator == "||")) {
			const left = featureOf(n.left);
			const right = featureOf(n.right);
			if (left == "" && right == "") { return ""; }
			if (left == "" || right == "") {
				fail(n, "a condition reads program key features and values together; " +
					"write the key's part as its own if");
			}
			return grouped(left) + " " + n.operator + " " + grouped(right);
		}
		return "";
	}

	function kindOf(n: Node): TypeKind { return typeKind(getType(n)); }

	function scalar(n: Node): boolean {
		const kind = kindOf(n);
		return kind == TypeKind.Float32 || kind == TypeKind.Int32 || kind == TypeKind.Uint32 ||
			kind == TypeKind.Boolean;
	}

	function integer(n: Node): boolean {
		return kindOf(n) == TypeKind.Int32 || kindOf(n) == TypeKind.Uint32;
	}

	function unsigned(n: Node): boolean {
		return kindOf(n.left) == TypeKind.Uint32 && kindOf(n.right) == TypeKind.Uint32;
	}

	function condition(n: Node): string {
		if (kindOf(n) != TypeKind.Boolean) { fail(n, "a shader condition is a boolean"); }
		return value(n);
	}

	function value(n: Node): string {
		if (n.kind == NodeKind.BinaryExpr) {
			const op = n.operator == "===" ? "==" : n.operator == "!==" ? "!=" : n.operator;
			if (["&&", "||"].includes(op)) {
				if (kindOf(n.left) != TypeKind.Boolean || kindOf(n.right) != TypeKind.Boolean) {
					fail(n, "'" + op + "' takes booleans in a shader");
				}
			} else if (["<", "<=", ">", ">=", "==", "!="].includes(op)) {
				if (!scalar(n.left)) { fail(n, "'" + op + "' compares scalars in a shader"); }
			} else if (op == "%" && integer(n.left) && !unsigned(n)) {
				fail(n, "'%' has a GLSL form for uint32 operands only: GLSL leaves a negative " +
					"int32 operand undefined");
			} else if (op == "/" && integer(n.left) && !unsigned(n)) {
				fail(n, "'/' has no GLSL form: GLSL does not truncate as MetaScript does");
			} else if (op == "%" && !integer(n.left)) {
				const a = expr(n.left);
				const b = expr(n.right);
				return a + " - " + b + " * trunc(" + a + " / " + b + ")";
			} else if (op != "+" && op != "-" && op != "*" && op != "/" && op != "%") {
				fail(n, "operator '" + op + "' has no GLSL form yet");
			}
			return expr(n.left) + " " + op + " " + expr(n.right);
		}
		if (n.kind == NodeKind.UnaryExpr) {
			const op = n.unaryOp;
			if (op == "!" && kindOf(n.operand) == TypeKind.Boolean ||
				op == "-" && kindOf(n.operand) != TypeKind.Uint32) {
				return op + expr(n.operand);
			}
			fail(n, "unary '" + op + "' has no GLSL form yet");
		}
		if (n.kind == NodeKind.ConditionalExpr) {
			if (kindOf(n.ternaryCondition) != TypeKind.Boolean) {
				fail(n, "a shader condition is a boolean");
			}
			return expr(n.ternaryCondition) + " ? " + expr(n.ternaryConsequent) + " : " +
				expr(n.ternaryAlternate);
		}
		return expr(n);
	}

	function expr(n: Node): string {
		if (n.kind == NodeKind.NumberLiteral) { return number(n); }
		if (n.kind == NodeKind.BooleanLiteral) { return n.boolValue ? "true" : "false"; }
		if (n.kind == NodeKind.Identifier) { return identifier(n); }
		if (n.kind == NodeKind.BinaryExpr || n.kind == NodeKind.UnaryExpr ||
			n.kind == NodeKind.ConditionalExpr) {
			return "(" + value(n) + ")";
		}
		if (n.kind == NodeKind.ArrayAccess) {
			const array = matrixColumns(n.array) ? n.array.object : n.array;
			return expr(array) + "[" + value(n.index) + "]";
		}
		if (n.kind == NodeKind.ArrayLiteral) {
			let elements: string[] = [];
			for (const e of n.elements) { elements.push(expr(e)); }
			return valueType(getType(n), n) + "(" + elements.join(", ") + ")";
		}
		if (n.kind == NodeKind.TypeAssertion) {
			const from = kindOf(n.asExpr);
			const to = kindOf(n);
			const exact = (from == TypeKind.Float32 || from == TypeKind.Int32) &&
				(to == TypeKind.Float32 || to == TypeKind.Int32) ||
				from == TypeKind.Uint32 && to == TypeKind.Float32;
			if (exact) {
				return glslType(getType(n), n) + "(" + value(n.asExpr) + ")";
			}
			fail(n, "'as' converts float32 and int32 both ways and uint32 to float32 in a " +
				"shader; int32 and uint32 convert by their bits through vec2i/vec2u");
		}
		if (n.kind == NodeKind.MemberExpr) {
			const object = n.object;
			if (isType(object, inputType)) {
				const b = builtinInputNames.indexOf(n.property);
				if (b >= 0) { return builtinInputs[b]; }
				const read = vertex ? n.property : varyingName(n.property);
				use(read);
				return read;
			}
			if (isType(object, bindingsType)) {
				if (isAuthorStruct(getType(n))) {
					fail(n, "uniform block '" + n.property + "' is read one member at a time: " +
						"GLSL declares the block's members, not a value of the block");
				}
				use(n.property);
				return n.property;
			}
			if (object.kind == NodeKind.MemberExpr && isType(object.object, bindingsType)) {
				use(object.property);
				return n.property;
			}
			if (isType(object, keyType)) {
				fail(n, "a program key feature is read only as an if condition");
			}
			if (matrixColumns(n)) {
				fail(n, "a matrix's columns are read one at a time, as m.columns[i]: GLSL has " +
					"no array of a matrix's columns");
			}
			return expr(object) + "." + field(n);
		}
		if (n.kind == NodeKind.ObjectLiteral) { return construction(n); }
		if (n.kind == NodeKind.CallExpr) {
			const callee = n.callee;
			const impl = getImpl(callee);
			if (callee.resolvedSym == null || impl == null || impl.kind != NodeKind.FunctionDecl) {
				fail(n, "a shader calls only functions");
			}
			if (callee.resolvedSym.modulePath != stdModule) { return call(n, callee, impl); }
			if (callee.kind == NodeKind.MemberExpr) {
				if (!impl.fnName.startsWith("get_")) {
					fail(n, "method calls have no GLSL form yet");
				}
				return expr(callee.object) + "." + impl.fnName.replace("get_", "");
			}
			let args: string[] = [];
			for (const a of n.arguments) { args.push(expr(a)); }
			const listed = "(" + args.join(", ") + ")";
			const first = n.arguments.length > 0 ? getType(n.arguments[0]) : null;
			const uintTexture = first != null && sameType(first, uintTextureType);
			const arrayTexture = first != null && sameType(first, arrayTextureType);
			const shape = uintTexture ? "usampler2D(" : arrayTexture ? "sampler2DArray(" :
				"sampler2D(";
			const layered = shape == "sampler2DArray(";
			const sampled = args.length >= 2 ? shape + args[0] + ", " + args[1] + ")" : "";
			return match (impl.fnName) {
				"abs" | "sign" | "floor" | "ceil" | "trunc" | "fract" | "sqrt" | "exp" | "exp2" |
				"log" | "log2" | "sin" | "cos" | "tan" | "asin" | "acos" | "atan" | "sinh" |
				"cosh" | "tanh" | "degrees" | "radians" | "max" | "min" | "clamp" | "mix" | "step" |
				"smoothstep" | "fma" | "pow" | "dot" | "cross" | "length" | "distance" |
				"normalize" | "reflect" | "refract" | "transpose" | "determinant" |
				"inverse" => impl.fnName + listed,
				"round" => "roundEven" + listed,
				"inverseSqrt" => "inversesqrt" + listed,
				"atan2" => "atan" + listed,
				"faceForward" => "faceforward" + listed,
				"saturate" => "clamp(" + args[0] + ", 0.0, 1.0)",
				"dpdx" | "dpdy" | "fwidth" => vertex || compute ?
					fail(n, impl.fnName + " exists only in a fragment entry, as WGSL's does") :
					impl.fnName.replace("dpdx", "dFdx").replace("dpdy", "dFdy") + listed,
				"vec2f" => "vec2" + listed,
				"vec3f" => "vec3" + listed,
				"vec4f" => "vec4" + listed,
				"vec2i" => "ivec2" + listed,
				"vec3i" => "ivec3" + listed,
				"vec4i" => "ivec4" + listed,
				"vec2u" => "uvec2" + listed,
				"vec3u" => "uvec3" + listed,
				"vec4u" => "uvec4" + listed,
				"mat2x2f" => "mat2" + listed,
				"mat3x3f" | "upperLeft3x3" => "mat3" + listed,
				"mat4x4f" => "mat4" + listed,
				"select" => "(" + args[2] + " ? " + args[1] + " : " + args[0] + ")",
				"textureDimensions" => args.length == 1 ? "imageSize(" + args[0] + ")" :
					"textureSize(" + sampled + ", " + args[2] + ")",
				"textureStore" => "imageStore(" + args.join(", ") + ")",
				"textureLoad" => layered ?
					"texelFetch(" + sampled + ", ivec3(" + args[2] + ", " + args[3] + "), " + args[4] + ")" :
					"texelFetch(" + sampled + ", " + args[2] + ", " + args[3] + ")",
				"textureSample" => vertex || compute ?
					fail(n, "textureSample samples only in a fragment entry, as WGSL's does") :
					layered ? "texture(" + sampled + ", vec3(" + args[2] + ", float(" + args[3] + ")))" :
					"texture(" + sampled + ", " + args[2] + ")",
				_ => fail(n, "./std's '" + impl.fnName + "' has no GLSL spelling"),
			};
		}
		fail(n, "this expression has no GLSL form yet (node kind " + String(n.kind) + ")");
	}

	function output(name: string, value: Node, indent: string): string {
		const o = outputNames.indexOf(name);
		const target = outputTargets[o];
		const gate = outputFeatures[o];
		if (gate != "") { features.push(gate); }
		use(target);
		const text = indent + target + " = " + expr(value) + ";\n";
		if (gate == "") { return text; }
		features.pop();
		return opening(gate) + "\n" + text + "#endif\n";
	}

	function assignee(target: Node, n: Node): string {
		if (target.kind == NodeKind.Identifier && locals.includes(target.name)) {
			return identifier(target);
		}
		if (target.kind == NodeKind.MemberExpr) {
			return assignee(target.object, n) + "." + field(target);
		}
		if (target.kind == NodeKind.ArrayAccess) {
			const array = matrixColumns(target.array) ? target.array.object : target.array;
			return assignee(array, n) + "[" + value(target.index) + "]";
		}
		fail(n, "a shader assigns only to its own locals, their fields and their elements");
	}

	function assignment(n: Node): string {
		const target = n.kind == NodeKind.UpdateExpr ? n.updateArg : n.left;
		const name = assignee(target, n);
		if (n.kind == NodeKind.UpdateExpr) { return name + n.updateOp; }
		if (n.operator == "/=" && integer(target)) {
			fail(n, "'/=' has no GLSL form: GLSL does not truncate as MetaScript does");
		}
		if (n.operator == "%=" && !unsigned(n)) {
			fail(n, "'%=' has a GLSL form for uint32 operands only: GLSL leaves a negative " +
				"int32 operand undefined and has no float '%'");
		}
		if (!["=", "+=", "-=", "*=", "/=", "%="].includes(n.operator)) {
			fail(n, "operator '" + n.operator + "' has no GLSL form yet");
		}
		return name + " " + n.operator + " " + value(n.right);
	}

	function isDiscard(callee: Node): boolean {
		const impl = getImpl(callee);
		return callee.resolvedSym != null && callee.resolvedSym.modulePath == stdModule &&
			impl != null && impl.fnName == "discard";
	}

	function simple(n: Node): string {
		if (n.kind == NodeKind.ExprStmt) {
			const e = n.expr;
			if (e.kind == NodeKind.CallExpr && isDiscard(e.callee)) { return "discard"; }
			if (e.kind == NodeKind.CallExpr && typeKind(getType(e)) == TypeKind.Void) {
				return expr(e);
			}
			if (e.kind != NodeKind.UpdateExpr && e.kind != NodeKind.BinaryExpr) {
				fail(n, "a shader statement is an assignment, not a value (node kind " +
					String(e.kind) + ")");
			}
			return assignment(e);
		}
		if (n.kind != NodeKind.VariableDecl) {
			fail(n, "this statement has no GLSL form yet (node kind " + String(n.kind) + ")");
		}
		if (n.initializer == null) { fail(n, "a shader local is declared with its value"); }
		const type = valueType(getType(n.initializer), n);
		const initial = value(n.initializer);
		locals.push(n.declName);
		return type + " " + local(n) + " = " + initial;
	}

	function body(n: Node, indent: string): string {
		return block(n.kind == NodeKind.BlockStmt ? n.statements : [n], indent);
	}

	function block(statements: Node[], indent: string): string {
		const outer = locals.length;
		let out = "";
		for (const s of statements) { out += stmt(s, indent); }
		while (locals.length > outer) { locals.pop(); }
		return out;
	}

	function loopBody(n: Node, indent: string): string {
		breakOwners.push("loop");
		const text = body(n, indent);
		breakOwners.pop();
		return text;
	}

	function caseLabel(test: Node): string {
		const literal = test.kind == NodeKind.NumberLiteral || test.kind == NodeKind.UnaryExpr &&
			test.unaryOp == "-" && test.operand.kind == NodeKind.NumberLiteral;
		const text = value(test);
		if (!integer(test) || !literal &&
			!(test.kind == NodeKind.Identifier && constantNames.includes(text))) {
			fail(test, "a case is an integer literal or module constant: GLSL takes a " +
				"constant expression");
		}
		return "case " + text + ":";
	}

	function caseBody(statements: Node[], owner: string, indent: string): string {
		let kept = statements.slice(0);
		while (owner == "switch" && kept.length > 0 &&
			kept[kept.length - 1].kind == NodeKind.BreakStmt &&
			kept[kept.length - 1].breakLabel == "") {
			kept.pop();
		}
		breakOwners.push(owner);
		let text = block(kept, indent);
		breakOwners.pop();
		const last = kept.length > 0 ? kept[kept.length - 1].kind : NodeKind.BlockStmt;
		if (last != NodeKind.ReturnStmt && last != NodeKind.ContinueStmt) {
			text += indent + "break;\n";
		}
		return text;
	}

	function choice(n: Node, indent: string): string {
		const isMatch = n.kind == NodeKind.MatchExpr;
		const scrutinee = isMatch ? n.matchDisc : n.switchDisc;
		if (!integer(scrutinee)) { fail(n, "a shader switch or match takes an int32 or uint32"); }
		const inner = indent + "    ";
		let text = indent + "switch (" + value(scrutinee) + ") {\n";
		const cases: Node[] = isMatch ? n.matchCases : n.switchCases;
		for (let k = 0; k < cases.length; k++) {
			const c = cases[k];
			let labels: string[] = [];
			let statements: Node[] = [];
			if (isMatch) {
				if (c.caseGuard != null) {
					fail(c, "a match arm with 'when' has no GLSL switch form; write an if");
				}
				for (const p of c.casePatterns) {
					labels.push(p.kind == NodeKind.Identifier && p.name == "_" ? "default:" :
						caseLabel(p));
				}
				const arm = c.caseBody;
				statements = arm.kind == NodeKind.BlockStmt ? arm.statements :
					[{ kind: NodeKind.ExprStmt, line: arm.line, column: arm.column, expr: arm }];
			} else {
				if (c.caseStmts.length == 0 && k + 1 < cases.length) {
					fail(c, "an empty case runs nothing in msc, where TypeScript runs the next " +
						"case's body (~/metascript/.inbox/compiler/" +
						"2026-10-15-empty-switch-case-does-not-group.md); write the labels as " +
						"one match arm, 1 | 2 => { ... }");
				}
				if (c.isDefault) { labels.push("default:"); }
				for (const t of c.caseTests) { labels.push(caseLabel(t)); }
				statements = c.caseStmts;
			}
			text += inner + labels.join(" ") + " {\n" +
				caseBody(statements, isMatch ? "match" : "switch", inner + "    ") + inner + "}\n";
		}
		return text + indent + "}\n";
	}

	function branches(n: Node, indent: string): string {
		const inner = indent + "    ";
		const out = "if (" + condition(n.condition) + ") {\n" + body(n.consequent, inner) +
			indent + "}";
		const other = n.alternate;
		if (other == null || other.kind == NodeKind.BlockStmt && other.statements.length == 0) {
			return out;
		}
		if (other.kind == NodeKind.IfStmt) { return out + " else " + branches(other, indent); }
		return out + " else {\n" + body(other, inner) + indent + "}";
	}

	function stmt(n: Node, indent: string): string {
		const inner = indent + "    ";
		if (n.kind == NodeKind.BlockStmt) {
			return indent + "{\n" + body(n, inner) + indent + "}\n";
		}
		if (n.kind == NodeKind.IfStmt && featureOf(n.condition) != "") {
			const gate = featureOf(n.condition);
			features.push(gate);
			let text = opening(gate) + "\n" + body(n.consequent, indent);
			features.pop();
			if (n.alternate != null) {
				features.push("!" + grouped(gate));
				const otherwise = body(n.alternate, indent);
				features.pop();
				if (otherwise != "") { text += "#else\n" + otherwise; }
			}
			return text + "#endif\n";
		}
		if (n.kind == NodeKind.IfStmt) { return indent + branches(n, indent) + "\n"; }
		if (n.kind == NodeKind.WhileStmt) {
			if (n.whileLabel != "") { fail(n, "GLSL has no labelled loops"); }
			return indent + "while (" + condition(n.whileCondition) + ") {\n" +
				loopBody(n.whileBody, inner) + indent + "}\n";
		}
		if (n.kind == NodeKind.ForStmt) {
			if (n.forLabel != "") { fail(n, "GLSL has no labelled loops"); }
			const outer = locals.length;
			const head = "for (" + simple(n.forInit) + "; " + condition(n.forCondition) + "; " +
				assignment(n.forUpdate) + ") {\n";
			const out = indent + head + loopBody(n.forBody, inner) + indent + "}\n";
			while (locals.length > outer) { locals.pop(); }
			return out;
		}
		if (n.kind == NodeKind.BreakStmt || n.kind == NodeKind.ContinueStmt) {
			const label = n.kind == NodeKind.BreakStmt ? n.breakLabel : n.continueLabel;
			if (label != "") { fail(n, "GLSL has no labelled loops"); }
			if (n.kind == NodeKind.BreakStmt && breakOwners.length > 0 &&
				breakOwners[breakOwners.length - 1] == "match") {
				fail(n, "a break in a match arm leaves the loop or switch around the match, " +
					"and in the GLSL switch it would leave only the match; write an if");
			}
			return indent + (n.kind == NodeKind.BreakStmt ? "break" : "continue") + ";\n";
		}
		if (n.kind == NodeKind.SwitchStmt) { return choice(n, indent); }
		if (n.kind == NodeKind.ExprStmt && n.expr.kind == NodeKind.MatchExpr) {
			return choice(n.expr, indent);
		}
		if (n.kind == NodeKind.ReturnStmt) {
			const result = n.argument;
			if (inHelper) {
				if (result == null) { fail(n, "a shader function returns a value"); }
				return indent + "return " + value(result) + ";\n";
			}
			if (noOutput && result == null) { return indent + "return;\n"; }
			if (result == null) { fail(n, "an entry returns its stage output"); }
			if (outputs == null) {
				use("fragColor");
				return indent + "fragColor = " + value(result) + ";\n" + indent + "return;\n";
			}
			if (result.kind != NodeKind.ObjectLiteral) {
				fail(n, "a struct stage output is returned as an object literal");
			}
			let text = "";
			for (let k = 0; k < result.keys.length; k++) {
				text += output(result.keys[k], result.properties[k], indent);
			}
			return text + indent + "return;\n";
		}
		return indent + simple(n) + ";\n";
	}

	gather(fn.fnBody, entry.resolvedSym.modulePath, [], null);
	enterScope(entry.resolvedSym.modulePath, signature.typExprParamNames);
	paramGlslNames = signature.typExprParamNames;
	const main = body(fn.fnBody, "    ");
	for (let s = 0; s < storageNames.length; s++) {
		const element = storageElements[s];
		if (!isAuthorStruct(element)) {
			fail(entry, "storage buffer '" + storageNames[s] + "' holds an author struct: shdc " +
				"takes one flexible array of structs per buffer");
		}
		declTexts[declNames.indexOf(storageNames[s])] = storageHeads[s] +
			structName(element, entry) + " " + storageNames[s] + "[];\n};\n";
	}
	let header = "";
	let structs = "";
	for (let i = 0; i < declNames.length; i++) {
		const contexts = declContexts[i];
		if (!declAlways[i] && declFixed[i] == "" && contexts.length == 0) { continue; }
		let gate = declFixed[i];
		if (!declAlways[i] && gate == "" && contexts.indexOf("") < 0) {
			let any: string[] = [];
			for (const c of contexts) { any.push(contexts.length == 1 ? c : grouped(c)); }
			gate = any.join(" || ");
		}
		const text = gate == "" ? declTexts[i] : opening(gate) + "\n" + declTexts[i] + "#endif\n";
		if (declNames[i].startsWith("struct:")) {
			structs += text;
		} else {
			header += text;
		}
	}
	let size = "";
	if (compute) {
		const axes = ["x", "y", "z"];
		for (let a = 0; a < 3; a++) {
			const n = a < workgroupSize.elements.length ? workgroupSize.elements[a] : null;
			if (n != null && n.kind != NodeKind.NumberLiteral) {
				fail(workgroupSize, "a workgroup size is three numbers");
			}
			size += (a == 0 ? "" : ", ") + "local_size_" + axes[a] + "=" +
				(n == null ? "1" : String(intValue(n)));
		}
		let invocations: int64 = 1;
		for (const n of workgroupSize.elements) { invocations *= intValue(n); }
		if (invocations % 32 != 0) {
			fail(workgroupSize, "a workgroup is a multiple of 32 invocations, as shdc requires");
		}
		size = "layout(" + size + ") in;\n";
	}
	const source = size + structs + header + "void main() {\n" + main + "}\n";
	return { kind: NodeKind.StringLiteral, line: entry.line, column: entry.column, value: source };
}
