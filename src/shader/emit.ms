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
	Mat3x3f,
	Mat4x4f,
	Sampler,
	Texture2d,
	Vec2f,
	Vec2i,
	Vec3f,
	Vec4f,
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
		let interfaceOnly = true;
		let varyings = 0;
		for (const decorators of fields.typExprFieldDecorators) {
			let builtin = false;
			for (const d of decorators) {
				if (d.macroName == "binding" || d.macroName == "feature") { interfaceOnly = false; }
				if (d.macroName == "builtin") { builtin = true; }
			}
			if (!builtin) { varyings += 1; }
		}
		if (interfaceOnly && varyings > 0) {
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
		arguments: [entry],
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
		let interfaceOnly = true;
		for (const decorators of fields.typExprFieldDecorators) {
			for (const d of decorators) {
				if (d.macroName == "binding" || d.macroName == "feature") { interfaceOnly = false; }
			}
		}
		if (interfaceOnly) { input = t; }
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
		arguments: [fragment],
	};
}

// The stage both glsl and glslLinked expand to, once their checks hold.
export macro glslStage(entry: Node): Node {
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
	const vectorTypes = [
		getTypeImpl(Vec2f),
		getTypeImpl(Vec3f),
		getTypeImpl(Vec4f),
		getTypeImpl(Vec2i),
		getTypeImpl(Mat3x3f),
		getTypeImpl(Mat4x4f),
	];
	const vectorNames = ["vec2", "vec3", "vec4", "ivec2", "mat3", "mat4"];

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
		fail(at, "a shader value is float32, int32, uint32, boolean, or a ./std vector or matrix");
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

	function hasDecorator(fields: Node, name: string): boolean {
		for (const decorators of fields.typExprFieldDecorators) {
			if (decorator(decorators, name) != null) { return true; }
		}
		return false;
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
		if (hasDecorator(fields, "binding")) {
			if (bindingsType != null) { fail(entry, "two bindings structs: '" + name + "'"); }
			bindingsType = t;
		} else if (hasDecorator(fields, "feature")) {
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


	let globals: string[] = [];
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

	function useUnder(name: string, gates: string[]): void {
		const i = declNames.indexOf(name);
		if (i < 0 || declFixed[i] != "") { return; }
		const context = gates.join(" && ");
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

	function grouped(condition: string): string {
		return condition.indexOf(" ") < 0 ? condition : "(" + condition + ")";
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

	function member(t: Node, name: string, at: Node): string {
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
			if (sameType(t, textureType)) {
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
	if (inputs != null) {
		for (let f = 0; f < inputs.typExprFieldNames.length; f++) {
			const name = inputs.typExprFieldNames[f];
			const builtin = decorator(inputs.typExprFieldDecorators[f], "builtin");
			if (builtin == null) {
				// Every input is declared, read or not: shdc numbers them in declaration order.
				const varying = member(inputs.typExprFieldTypes[f], name, entry);
				const gate = featureCondition(inputs.typExprFieldDecorators[f], entry);
				declareUnder(name, "in " + varying + ";\n", gate);
				continue;
			}
			const which = argumentName(builtin, entry);
			const glslName = vertex ? "" : which == "position" ? "gl_FragCoord" :
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
			outputTargets.push(name);
			const t = outputs.typExprFieldTypes[f];
			if (vertex) {
				declareUnder(name, "out " + member(t, name, entry) + ";\n", gate);
				continue;
			}
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
		declare("const:" + key, "const " + glslType(getType(n), n) + " " + name + " = " +
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
			types.push(glslType(t, callee));
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
		declare("call:" + key, glslType(helperType.typExprReturn, callee) + " " + name + "(" +
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
			} else if (op == "%" || op == "/" && integer(n.left)) {
				fail(n, "'" + op + "' has no GLSL form: GLSL does not truncate as MetaScript does");
			} else if (op != "+" && op != "-" && op != "*" && op != "/") {
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
		if (n.kind == NodeKind.ArrayAccess) { return expr(n.array) + "[" + value(n.index) + "]"; }
		if (n.kind == NodeKind.ArrayLiteral) {
			let elements: string[] = [];
			for (const e of n.elements) { elements.push(expr(e)); }
			return glslType(getType(n), n) + "(" + elements.join(", ") + ")";
		}
		if (n.kind == NodeKind.TypeAssertion) {
			const from = kindOf(n.asExpr);
			const to = kindOf(n);
			if ((from == TypeKind.Float32 || from == TypeKind.Int32) &&
				(to == TypeKind.Float32 || to == TypeKind.Int32)) {
				return glslType(getType(n), n) + "(" + value(n.asExpr) + ")";
			}
			fail(n, "'as' converts between float32 and int32 only in a shader");
		}
		if (n.kind == NodeKind.MemberExpr) {
			const object = n.object;
			if (isType(object, inputType)) {
				const b = builtinInputNames.indexOf(n.property);
				if (b >= 0) { return builtinInputs[b]; }
				use(n.property);
				return n.property;
			}
			if (isType(object, bindingsType)) {
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
			return expr(object) + "." + n.property;
		}
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
			const sampled = args.length >= 2 ? "sampler2D(" + args[0] + ", " + args[1] + ")" : "";
			return match (impl.fnName) {
				"max" | "min" | "clamp" | "mix" | "pow" | "dot" | "length" | "normalize" =>
					impl.fnName + listed,
				"vec2f" => "vec2" + listed,
				"vec3f" => "vec3" + listed,
				"vec4f" => "vec4" + listed,
				"vec2i" => "ivec2" + listed,
				"mat3x3f" | "upperLeft3x3" => "mat3" + listed,
				"mat4x4f" => "mat4" + listed,
				"select" => "(" + args[2] + " ? " + args[1] + " : " + args[0] + ")",
				"textureDimensions" => "textureSize(" + sampled + ", " + args[2] + ")",
				"textureLoad" => "texelFetch(" + sampled + ", " + args[2] + ", " + args[3] + ")",
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

	function assignment(n: Node): string {
		const target = n.kind == NodeKind.UpdateExpr ? n.updateArg : n.left;
		if (target.kind != NodeKind.Identifier || !locals.includes(target.name)) {
			fail(n, "a shader assigns only to its own locals");
		}
		const name = identifier(target);
		if (n.kind == NodeKind.UpdateExpr) { return name + n.updateOp; }
		if (n.operator == "/=" && integer(target)) {
			fail(n, "'/=' has no GLSL form: GLSL does not truncate as MetaScript does");
		}
		if (!["=", "+=", "-=", "*=", "/="].includes(n.operator)) {
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
		const type = glslType(getType(n.initializer), n);
		const initial = value(n.initializer);
		locals.push(n.declName);
		return type + " " + local(n) + " = " + initial;
	}

	function body(n: Node, indent: string): string {
		const outer = locals.length;
		let out = "";
		const statements = n.kind == NodeKind.BlockStmt ? n.statements : [n];
		for (const s of statements) { out += stmt(s, indent); }
		while (locals.length > outer) { locals.pop(); }
		return out;
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
				body(n.whileBody, inner) + indent + "}\n";
		}
		if (n.kind == NodeKind.ForStmt) {
			if (n.forLabel != "") { fail(n, "GLSL has no labelled loops"); }
			const outer = locals.length;
			const head = "for (" + simple(n.forInit) + "; " + condition(n.forCondition) + "; " +
				assignment(n.forUpdate) + ") {\n";
			const out = indent + head + body(n.forBody, inner) + indent + "}\n";
			while (locals.length > outer) { locals.pop(); }
			return out;
		}
		if (n.kind == NodeKind.BreakStmt || n.kind == NodeKind.ContinueStmt) {
			const label = n.kind == NodeKind.BreakStmt ? n.breakLabel : n.continueLabel;
			if (label != "") { fail(n, "GLSL has no labelled loops"); }
			return indent + (n.kind == NodeKind.BreakStmt ? "break" : "continue") + ";\n";
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
	let header = "";
	for (let i = 0; i < declNames.length; i++) {
		const contexts = declContexts[i];
		if (!declAlways[i] && declFixed[i] == "" && contexts.length == 0) { continue; }
		let gate = declFixed[i];
		if (!declAlways[i] && gate == "" && contexts.indexOf("") < 0) {
			let any: string[] = [];
			for (const c of contexts) { any.push(contexts.length == 1 ? c : grouped(c)); }
			gate = any.join(" || ");
		}
		header += gate == "" ? declTexts[i] : opening(gate) + "\n" + declTexts[i] + "#endif\n";
	}
	const source = header + "void main() {\n" + main + "}\n";
	return { kind: NodeKind.StringLiteral, line: entry.line, column: entry.column, value: source };
}
