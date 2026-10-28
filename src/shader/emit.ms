// The node walk sits in functions nested in the macro body: only there are Node fields readable.

import {
	DeclKind,
	Node,
	NodeKind,
	StringLiteralData,
	SymbolKind,
	TypeArrayData,
	TypeKind,
	TypeObjectData,
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
	AtomicExchangeI32,
	AtomicExchangeU32,
	AtomicI32,
	AtomicU32,
	FrexpResultF32,
	FrexpResultVec2f,
	FrexpResultVec3f,
	FrexpResultVec4f,
	Mat2x2f,
	Mat2x3f,
	Mat2x4f,
	Mat3x3f,
	Mat4x4f,
	Mat3x2f,
	Mat3x4f,
	Mat4x2f,
	Mat4x3f,
	ModfResultF32,
	ModfResultVec2f,
	ModfResultVec3f,
	ModfResultVec4f,
	Sampler,
	SamplerComparison,
	StorageTexture1d,
	StorageTexture2d,
	StorageTexture2dArray,
	StorageTexture2dArrayI32,
	StorageTexture2dArrayU32,
	StorageTexture2dI32,
	StorageTexture2dU32,
	StorageTexture3d,
	StorageTexture3dI32,
	StorageTexture3dU32,
	Texture1d,
	Texture2d,
	Texture2dArray,
	Texture2dArrayI32,
	Texture2dArrayU32,
	Texture2dI32,
	Texture2dU32,
	Texture3d,
	Texture3dI32,
	Texture3dU32,
	TextureCube,
	TextureDepth2d,
	TextureDepth2dArray,
	TextureDepthCube,
	TextureMultisampled2d,
	Vec2b,
	Vec2f,
	Vec2i,
	Vec2u,
	Vec3b,
	Vec3f,
	Vec3i,
	Vec3u,
	Vec4b,
	Vec4f,
	Vec4i,
	Vec4u,
} from "./std";

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
	OFFSET_MAX,
	OFFSET_MIN,
	ResourceKind,
	SampleType,
	Sampling,
	SamplerType,
	ShaderCase,
	ShaderConstant,
	ShaderDeclaration,
	ShaderEntry,
	ShaderExpr,
	ShaderField,
	ShaderFunction,
	ShaderIo,
	ShaderModule,
	ShaderResource,
	ShaderStage,
	ShaderStmt,
	ShaderStruct,
	ShaderType,
	ShaderTypeKind,
	ScalarKind,
	StmtKind,
	TexelFormat,
	TextureShape,
	UnaryOp,
	arrayType,
	assignOf,
	atomicType,
	binaryOf,
	conditionOf,
	exchangeResultType,
	exprOf,
	featureOn,
	frexpResultType,
	hasOffset,
	holds,
	intrinsicOf,
	irErrors,
	isSampling,
	literal,
	matrixType,
	modfResultType,
	offsetRows,
	predeclaredMemberType,
	sameCondition,
	sampleBase,
	samplerType,
	scalarType,
	stmtOf,
	storageTextureType,
	structType,
	texelScalar,
	textureType,
	vectorType,
} from "./ir";
import { suffixed } from "./names";
import { irText } from "./irText";
import { printGlsl450 } from "./printGlsl450";

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
	return {
		kind: NodeKind.CallExpr,
		line: entry.line,
		column: entry.column,
		callee: bindSym("glslAs"),
		arguments: [
			entry,
			{ kind: NodeKind.StringLiteral, line: entry.line, column: entry.column, value: "glsl" },
		],
	};
}

export macro glslIr(entry: Node): Node {
	return {
		kind: NodeKind.CallExpr,
		line: entry.line,
		column: entry.column,
		callee: bindSym("glslAs"),
		arguments: [
			entry,
			{ kind: NodeKind.StringLiteral, line: entry.line, column: entry.column, value: "ir" },
		],
	};
}

export macro glslAs(entry: Node, form: Node): Node {
	const signature = getType(entry);
	if (signature == null || signature.kind != NodeKind.TypeFunction) {
		error("glsl: the entry must be a function", entry);
	}
	const output = getTypeImpl(signature.typExprReturn);
	let vertex = false;
	if (output != null && output.kind == NodeKind.TypeObject) {
		for (const decorators of output.typExprFieldDecorators) {
			for (const d of decorators) {
				if (d.macroName == "builtin" && d.macroArgs.length == 1 &&
					d.macroArgs[0].name == "position") { vertex = true; }
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
	return { kind: NodeKind.CallExpr, line: entry.line, column: entry.column,
		callee: bindSym("glslStage"), arguments: [entry, { kind: NodeKind.ArrayLiteral,
			line: entry.line, column: entry.column, elements: [] }, entry, form] };
}

export macro glslLinked(fragment: Node, vertex: Node): Node {
	return {
		kind: NodeKind.CallExpr,
		line: fragment.line,
		column: fragment.column,
		callee: bindSym("glslLinkedAs"),
		arguments: [
			fragment,
			vertex,
			{
				kind: NodeKind.StringLiteral,
				line: fragment.line,
				column: fragment.column,
				value: "glsl",
			},
		],
	};
}

export macro glslLinkedIr(fragment: Node, vertex: Node): Node {
	return {
		kind: NodeKind.CallExpr,
		line: fragment.line,
		column: fragment.column,
		callee: bindSym("glslLinkedAs"),
		arguments: [
			fragment,
			vertex,
			{
				kind: NodeKind.StringLiteral,
				line: fragment.line,
				column: fragment.column,
				value: "ir",
			},
		],
	};
}

export macro glslLinkedAs(fragment: Node, vertex: Node, form: Node): Node {
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

	const fragmentSignature = getType(fragment);
	const vertexSignature = getType(vertex);
	if (fragmentSignature == null || fragmentSignature.kind != NodeKind.TypeFunction ||
		vertexSignature == null || vertexSignature.kind != NodeKind.TypeFunction) {
		error("glslLinked: both stages must be functions", fragment);
	}
	let input: Node | null = null;
	for (const t of fragmentSignature.typExprParams) {
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
	const reads = input == null ? [] : varyingNames(input, fragment);
	const writes = varyingNames(vertexSignature.typExprReturn, vertex);
	const readTypes = input == null ? [] : varyingTypes(input, fragment);
	const writeTypes = varyingTypes(vertexSignature.typExprReturn, vertex);
	const readGates = input == null ? [] : varyingFeatures(input, fragment);
	const writeGates = varyingFeatures(vertexSignature.typExprReturn, vertex);
	for (let i = 0; i < reads.length || i < writes.length; i++) {
		const read = i < reads.length ? reads[i] : "";
		const written = i < writes.length ? writes[i] : "";
		if (read == "") {
			error("glslLinked: the fragment input does not declare varying '" + written +
				"' of the vertex output; every varying is declared, read or not", fragment);
		}
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
	return { kind: NodeKind.CallExpr, line: fragment.line, column: fragment.column,
		callee: bindSym("glslStage"), arguments: [fragment, { kind: NodeKind.ArrayLiteral,
			line: fragment.line, column: fragment.column, elements: [] }, vertex, form] };
}

export macro glslCompute(entry: Node, workgroupSize: Node): Node {
	return {
		kind: NodeKind.CallExpr,
		line: entry.line,
		column: entry.column,
		callee: bindSym("glslComputeAs"),
		arguments: [
			entry,
			workgroupSize,
			{ kind: NodeKind.StringLiteral, line: entry.line, column: entry.column, value: "glsl" },
		],
	};
}

export macro glslComputeIr(entry: Node, workgroupSize: Node): Node {
	return {
		kind: NodeKind.CallExpr,
		line: entry.line,
		column: entry.column,
		callee: bindSym("glslComputeAs"),
		arguments: [
			entry,
			workgroupSize,
			{ kind: NodeKind.StringLiteral, line: entry.line, column: entry.column, value: "ir" },
		],
	};
}

export macro glslComputeAs(entry: Node, workgroupSize: Node, form: Node): Node {
	if (workgroupSize.kind != NodeKind.ArrayLiteral || workgroupSize.elements.length < 1 ||
		workgroupSize.elements.length > 3) {
		error("glslCompute: the workgroup size is an array of one to three numbers", workgroupSize);
	}
	return { kind: NodeKind.CallExpr, line: entry.line, column: entry.column,
		callee: bindSym("glslStage"), arguments: [entry, workgroupSize, entry, form] };
}

function shaderField(name: string, type: ShaderType): ShaderField {
	let f = new ShaderField();
	f.name = name;
	f.type = type;
	return f;
}

function featureIf(gate: FeatureCondition, body: ShaderStmt[]): ShaderStmt {
	let s = stmtOf(StmtKind.FeatureIf, new ShaderExpr(), body);
	s.condition = gate;
	return s;
}

function negated(c: FeatureCondition): FeatureCondition {
	return c.kind == ConditionKind.Not ? c.operands[0] : conditionOf(ConditionKind.Not, [c]);
}

function includesCondition(list: FeatureCondition[], c: FeatureCondition): boolean {
	return list.some((o) => sameCondition(o, c));
}

function sameProduct(a: FeatureCondition[], b: FeatureCondition[]): boolean {
	if (a.length != b.length) { return false; }
	for (let i = 0; i < a.length; i++) {
		if (!sameCondition(a[i], b[i])) { return false; }
	}
	return true;
}

function covers(a: FeatureCondition[], b: FeatureCondition[]): boolean {
	return !a.some((c) => !includesCondition(b, c));
}

function joined(a: FeatureCondition[], b: FeatureCondition[]): FeatureCondition[] | null {
	if (a.length != b.length) { return null; }
	const own = a.filter((c) => !includesCondition(b, c));
	const other = b.filter((c) => !includesCondition(a, c));
	if (own.length != 1 || other.length != 1 || !sameCondition(other[0], negated(own[0]))) {
		return null;
	}
	return a.filter((c) => !sameCondition(c, own[0]));
}

function featureNames(c: FeatureCondition, names: string[]): void {
	if (c.kind == ConditionKind.Feature && !names.includes(c.feature)) { names.push(c.feature); }
	for (const o of c.operands) { featureNames(o, names); }
}

function featureSets(names: string[]): string[][] {
	let sets: string[][] = [[]];
	for (const name of names) {
		const count = sets.length;
		for (let k = 0; k < count; k++) {
			let grown = sets[k].slice(0);
			grown.push(name);
			sets.push(grown);
		}
	}
	return sets;
}

function productHolds(p: FeatureCondition[], on: string[]): boolean {
	return !p.some((c) => !holds(c, on));
}

function anyHolds(products: FeatureCondition[][], on: string[]): boolean {
	return products.some((p) => productHolds(p, on));
}

function simplest(contexts: FeatureCondition[][]): FeatureCondition[][] {
	let products: FeatureCondition[][] = [];
	for (const c of contexts) { products.push(c.slice(0)); }
	let changed = true;
	while (changed) {
		changed = false;
		for (let i = 0; i < products.length && !changed; i++) {
			for (let j = 0; j < products.length && !changed; j++) {
				if (i == j) { continue; }
				const join = joined(products[i], products[j]);
				if (covers(products[i], products[j])) {
					products.splice(j, 1);
					changed = true;
				} else if (join != null) {
					products[i] = join;
					products.splice(j, 1);
					changed = true;
				}
			}
		}
	}
	let names: string[] = [];
	for (const p of products) {
		for (const c of p) { featureNames(c, names); }
	}
	const sets = featureSets(names);
	for (let i = products.length - 1; i >= 0 && products.length > 1; i--) {
		const others = products.filter((p, k) => k != i);
		let held = true;
		for (const on of sets) {
			if (productHolds(products[i], on) && !anyHolds(others, on)) { held = false; }
		}
		if (held) { products.splice(i, 1); }
	}
	let always = true;
	for (const on of sets) {
		if (!anyHolds(products, on)) { always = false; }
	}
	return always ? [[]] : products;
}

function conjunctOf(c: FeatureCondition, gate: FeatureCondition): boolean {
	return sameCondition(c, gate) ||
		c.kind == ConditionKind.All && c.operands.some((o) => conjunctOf(o, gate));
}

function union(a: FeatureCondition[], b: FeatureCondition[]): FeatureCondition[] {
	let all = a.slice(0);
	for (const g of b) {
		if (!includesCondition(all, g)) { all.push(g); }
	}
	return all;
}

function productCondition(p: FeatureCondition[]): FeatureCondition {
	return p.length == 1 ? p[0] : conditionOf(ConditionKind.All, p);
}

function declarationCondition(contexts: FeatureCondition[][]): FeatureCondition {
	if (contexts.length == 0) { return conditionOf(ConditionKind.Any, []); }
	const products = simplest(contexts);
	if (products.some((p) => p.length == 0)) { return new FeatureCondition(); }
	if (products.length == 1) { return productCondition(products[0]); }
	return conditionOf(ConditionKind.Any, products.map((p) => productCondition(p)));
}

function notAShaderValue(): string {
	return "a shader value is float32, int32, uint32, boolean, a ./std vector or matrix, " +
		"or a struct of those";
}

export class ShaderTypeNodes {
	stdModule: string = "";
	atomics: Node[] = [];
	exchanges: Node[] = [];
	modfs: Node[] = [];
	frexps: Node[] = [];
	vectors: Node[] = [];
	vectorNames: string[] = [];
	firstMatrix: int32 = 0;
}

// One field per std type the lowering recognises, in the order shaderTypeNodes reads them. A macro
// reads a std type's node only from its own body, so the macros that need them hand this struct's.
export struct ShaderTypeRegistry {
	atomicI32: AtomicI32;
	atomicU32: AtomicU32;
	exchangeI32: AtomicExchangeI32;
	exchangeU32: AtomicExchangeU32;
	modfF32: ModfResultF32;
	modfVec2f: ModfResultVec2f;
	modfVec3f: ModfResultVec3f;
	modfVec4f: ModfResultVec4f;
	frexpF32: FrexpResultF32;
	frexpVec2f: FrexpResultVec2f;
	frexpVec3f: FrexpResultVec3f;
	frexpVec4f: FrexpResultVec4f;
	vec2f: Vec2f;
	vec3f: Vec3f;
	vec4f: Vec4f;
	vec2i: Vec2i;
	vec3i: Vec3i;
	vec4i: Vec4i;
	vec2u: Vec2u;
	vec3u: Vec3u;
	vec4u: Vec4u;
	vec2b: Vec2b;
	vec3b: Vec3b;
	vec4b: Vec4b;
	mat2x2f: Mat2x2f;
	mat3x3f: Mat3x3f;
	mat4x4f: Mat4x4f;
	mat2x3f: Mat2x3f;
	mat2x4f: Mat2x4f;
	mat3x2f: Mat3x2f;
	mat3x4f: Mat3x4f;
	mat4x2f: Mat4x2f;
	mat4x3f: Mat4x3f;
}

function typesFrom(types: Node[], first: int32, count: int32): Node[] {
	let out: Node[] = [];
	for (let i = first; i < first + count; i++) { out.push(types[i]); }
	return out;
}

function groupStart(names: string[], first: string): int32 {
	const at = names.indexOf(first);
	if (at < 0) { throw new Error("ShaderTypeRegistry has no field " + first); }
	return at as int32;
}

export function shaderTypeNodes(registry: Node): ShaderTypeNodes {
	const fields = objectFields(registry)!;
	const types = fields.typExprFieldTypes;
	const names = fields.typExprFieldNames;
	const atomics = groupStart(names, "atomicI32");
	const exchanges = groupStart(names, "exchangeI32");
	const modfs = groupStart(names, "modfF32");
	const frexps = groupStart(names, "frexpF32");
	const vectors = groupStart(names, "vec2f");
	let nodes = new ShaderTypeNodes();
	nodes.stdModule = types[0].resolvedSym!.modulePath;
	nodes.atomics = typesFrom(types, atomics, exchanges - atomics);
	nodes.exchanges = typesFrom(types, exchanges, modfs - exchanges);
	nodes.modfs = typesFrom(types, modfs, frexps - modfs);
	nodes.frexps = typesFrom(types, frexps, vectors - frexps);
	nodes.vectors = typesFrom(types, vectors, (types.length - vectors) as int32);
	nodes.vectorNames = names.slice(vectors);
	nodes.firstMatrix = groupStart(names, "mat2x2f") - vectors;
	return nodes;
}

function scalarOfLetter(letter: string): ScalarKind {
	return letter == "f" ? ScalarKind.F32 : letter == "i" ? ScalarKind.I32 :
		letter == "u" ? ScalarKind.U32 : ScalarKind.Bool;
}

function vectorAt(nodes: ShaderTypeNodes, i: number): ShaderType {
	const name = nodes.vectorNames[i];
	const leading = ("234".indexOf(name.slice(3, 4)) + 2) as int32;
	if (i >= nodes.firstMatrix) {
		return matrixType(leading, ("234".indexOf(name.slice(5, 6)) + 2) as int32);
	}
	return vectorType(scalarOfLetter(name.slice(4, 5)), leading);
}

function predeclaredTypeOf(nodes: ShaderTypeNodes, t: Node): ShaderType | null {
	for (let i = 0; i < nodes.atomics.length; i++) {
		// card: 2026-10-28-macro-vm-enum-array-element-value
		const scalar: ScalarKind = i == 0 ? ScalarKind.I32 : ScalarKind.U32;
		if (sameType(t, nodes.atomics[i])) { return atomicType(scalar); }
		if (sameType(t, nodes.exchanges[i])) { return exchangeResultType(scalar); }
	}
	for (let i = 0; i < nodes.modfs.length; i++) {
		if (sameType(t, nodes.modfs[i])) { return modfResultType((i + 1) as int32); }
		if (sameType(t, nodes.frexps[i])) { return frexpResultType((i + 1) as int32); }
	}
	return null;
}

// Null when the type is no shader value.
export function shaderTypeOf(nodes: ShaderTypeNodes, t: Node): ShaderType | null {
	const predeclared = predeclaredTypeOf(nodes, t);
	if (predeclared != null) { return predeclared; }
	match (typeKind(t)) {
		TypeKind.Float32 => { return scalarType(ScalarKind.F32); },
		TypeKind.Int32 => { return scalarType(ScalarKind.I32); },
		TypeKind.Uint32 => { return scalarType(ScalarKind.U32); },
		TypeKind.Boolean => { return scalarType(ScalarKind.Bool); },
		TypeKind.SizedArray => {
			const array = getTypeImpl(t) as TypeArrayData;
			const element = shaderTypeOf(nodes, array.typExprElement);
			return element == null ? null : arrayType(element, array.typExprSize as int32);
		},
		_ => {},
	}
	for (let i = 0; i < nodes.vectors.length; i++) {
		if (sameType(t, nodes.vectors[i])) { return vectorAt(nodes, i); }
	}
	return null;
}

function objectFields(t: Node | null): TypeObjectData | null {
	if (t == null) { return null; }
	const fields = getTypeImpl(t);
	return fields != null && fields.kind == NodeKind.TypeObject ? fields as TypeObjectData : null;
}

function isAuthorStructOf(stdModule: string, t: Node | null): boolean {
	if (t == null || objectFields(t) == null) { return false; }
	return t.resolvedSym != null && t.resolvedSym.modulePath != stdModule;
}

// The type of a field of an interface struct: a uniform block member, attribute, varying or output.
export function interfaceMemberType(nodes: ShaderTypeNodes, t: Node, name: string):
	Result<ShaderType, string> {
	const array = t.kind == NodeKind.TypeArray ? t as TypeArrayData : null;
	if (isAuthorStructOf(nodes.stdModule, array == null ? t : array.typExprElement)) {
		return Result.err("interface field '" + name + "' is a struct: a uniform block member, " +
			"attribute, varying or output is a scalar, vector or matrix");
	}
	const sized = array != null && array.typExprSize > 0;
	const own = shaderTypeOf(nodes, sized ? array.typExprElement : t);
	if (own == null) { return Result.err(notAShaderValue()); }
	return Result.ok(sized ? arrayType(own, array.typExprSize as int32) : own);
}

function blockMemberOf(nodes: ShaderTypeNodes, fields: TypeObjectData, k: int32):
	Result<ShaderField, string> {
	const name = fields.typExprFieldNames[k];
	const own = interfaceMemberType(nodes, fields.typExprFieldTypes[k], name);
	if (!own.ok) { return Result.err(own.error); }
	return Result.ok(shaderField(name, own.value));
}

// The struct a shader declares as a uniform block, built as the lowering of a binding field builds
// it: one struct and one UniformBlock resource at index 0, ready for uniformBlockLayout.
export function uniformBlockOf(registry: Node, block: Node): Result<ShaderModule, string> {
	const nodes = shaderTypeNodes(registry);
	const fields = objectFields(block);
	if (fields == null) { return Result.err("a uniform block is a struct"); }
	let layout = new ShaderStruct();
	layout.name = fields.typExprTypeName;
	for (let k = 0; k < fields.typExprFieldNames.length; k++) {
		const member = blockMemberOf(nodes, fields, k as int32);
		if (!member.ok) {
			return Result.err("uniform member '" + fields.typExprFieldNames[k] + "': " +
				member.error);
		}
		layout.members.push(member.value);
	}
	let m = new ShaderModule();
	m.structs.push(layout);
	let r = new ShaderResource();
	r.kind = ResourceKind.UniformBlock;
	r.name = layout.name;
	r.type = structType(0);
	m.resources.push(r);
	return Result.ok(m);
}

export macro glslStage(entry: Node, workgroupSize: Node, feeder: Node, form: Node): Node {
	function fail(n: Node, msg: string): never {
		error("glsl: " + msg, n);
	}

	const typeNodes = shaderTypeNodes(getTypeImpl(ShaderTypeRegistry)!);
	const stdModule = typeNodes.stdModule;
	const textureNode = getTypeImpl(Texture2d);
	const samplerNode = getTypeImpl(Sampler);
	const storageTextureNodes = [getTypeImpl(StorageTexture2d),
		getTypeImpl(StorageTexture2dArray), getTypeImpl(StorageTexture3d),
		getTypeImpl(StorageTexture2dU32), getTypeImpl(StorageTexture2dArrayU32),
		getTypeImpl(StorageTexture3dU32), getTypeImpl(StorageTexture2dI32),
		getTypeImpl(StorageTexture2dArrayI32), getTypeImpl(StorageTexture3dI32),
		getTypeImpl(StorageTexture1d)];
	const storageShapes = [TextureShape.D2, TextureShape.D2Array, TextureShape.D3,
		TextureShape.D2, TextureShape.D2Array, TextureShape.D3,
		TextureShape.D2, TextureShape.D2Array, TextureShape.D3, TextureShape.D1];
	const storageChannels = [ScalarKind.F32, ScalarKind.F32, ScalarKind.F32,
		ScalarKind.U32, ScalarKind.U32, ScalarKind.U32,
		ScalarKind.I32, ScalarKind.I32, ScalarKind.I32, ScalarKind.F32];
	function channelName(s: ScalarKind): string {
		return s == ScalarKind.F32 ? "f32" : s == ScalarKind.U32 ? "u32" : "i32";
	}
	const viewNodes = [getTypeImpl(Texture2dU32), getTypeImpl(Texture2dArray),
		getTypeImpl(TextureCube), getTypeImpl(Texture2dI32), getTypeImpl(Texture3d),
		getTypeImpl(TextureDepth2d), getTypeImpl(TextureDepth2dArray),
		getTypeImpl(TextureDepthCube), getTypeImpl(TextureMultisampled2d),
		getTypeImpl(Texture2dArrayU32), getTypeImpl(Texture2dArrayI32),
		getTypeImpl(Texture3dU32), getTypeImpl(Texture3dI32), getTypeImpl(Texture1d)];
	const viewShapes = [TextureShape.D2, TextureShape.D2Array, TextureShape.Cube, TextureShape.D2,
		TextureShape.D3, TextureShape.Depth2d, TextureShape.Depth2dArray, TextureShape.DepthCube,
		TextureShape.Multisampled2d, TextureShape.D2Array, TextureShape.D2Array, TextureShape.D3,
		TextureShape.D3, TextureShape.D1];
	const viewTexels = [ScalarKind.U32, ScalarKind.F32, ScalarKind.F32, ScalarKind.I32,
		ScalarKind.F32, ScalarKind.F32, ScalarKind.F32, ScalarKind.F32, ScalarKind.F32,
		ScalarKind.U32, ScalarKind.I32, ScalarKind.U32, ScalarKind.I32, ScalarKind.F32];
	const viewSamples = [SampleType.Uint, SampleType.Float, SampleType.Float, SampleType.Sint,
		SampleType.Float, SampleType.Depth, SampleType.Depth, SampleType.Depth,
		SampleType.UnfilterableFloat, SampleType.Uint, SampleType.Sint, SampleType.Uint,
		SampleType.Sint, SampleType.Float];
	const comparisonNode = getTypeImpl(SamplerComparison);
	const vectorTypes = typeNodes.vectors;
	const constructors = [
		"vec2f", "vec3f", "vec4f", "vec2i", "vec3i", "vec4i", "vec2u", "vec3u", "vec4u",
		"vec2b", "vec3b", "vec4b",
		"mat2x2f", "mat3x3f", "mat4x4f",
		"mat2x3f", "mat2x4f", "mat3x2f", "mat3x4f", "mat4x2f", "mat4x3f",
	];
	function matrixColumns(n: Node): boolean {
		if (n.kind != NodeKind.MemberExpr || n.property != "columns") { return false; }
		const t = getType(n.object);
		for (let i = typeNodes.firstMatrix; i < vectorTypes.length; i++) {
			if (t != null && sameType(t, vectorTypes[i])) { return true; }
		}
		return false;
	}

	function predeclaredType(t: Node): ShaderType | null {
		return predeclaredTypeOf(typeNodes, t);
	}

	function glslType(t: Node | null, at: Node): ShaderType {
		if (t == null) { fail(at, "the expression has no type"); }
		const found = shaderTypeOf(typeNodes, t);
		if (found == null) { fail(at, notAShaderValue()); }
		return found;
	}

	function decorator(decorators: Node[], name: string): Node | null {
		for (const d of decorators) {
			if (d.macroName == name) { return d; }
		}
		return null;
	}

	function argument(d: Node): Node {
		if (d.macroArgs.length != 1) { fail(d, "@" + d.macroName + " takes one argument"); }
		return d.macroArgs[0];
	}

	function argumentName(d: Node): string {
		const a = argument(d);
		if (a.kind != NodeKind.Identifier) { fail(d, "@" + d.macroName + " takes a name"); }
		return a.name;
	}

	function argumentNumber(d: Node): int32 {
		const a = argument(d);
		if (a.kind != NodeKind.NumberLiteral) { fail(d, "@" + d.macroName + " takes a number"); }
		return intValue(a) as int32;
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

	function hasPosition(fields: Node): boolean {
		for (const decorators of fields.typExprFieldDecorators) {
			const builtin = decorator(decorators, "builtin");
			if (builtin != null && argumentName(builtin) == "position") { return true; }
		}
		return false;
	}

	function isAuthorStruct(t: Node | null): boolean {
		return isAuthorStructOf(stdModule, t);
	}

	const fn = getImpl(entry);
	const signature = getType(entry);
	if (fn == null || fn.kind != NodeKind.FunctionDecl || signature == null ||
		signature.kind != NodeKind.TypeFunction || entry.resolvedSym == null) {
		fail(entry, "the entry must be a function");
	}

	const declared: Node = fn;

	function fieldSite(decorators: Node[]): Node {
		return decorators.length > 0 ? decorators[0] : declared;
	}

	const outputType = signature.typExprReturn;
	const vectorOutput = vectorTypes.some((v) => outputType != null && sameType(outputType, v));
	const outputs = vectorOutput ? null : fieldsOf(outputType);
	const vertex = outputs != null && hasPosition(outputs);
	const computeBuiltins = ["globalInvocationId", "localInvocationId", "localInvocationIndex",
		"workgroupId", "numWorkgroups"];
	const computeKinds = [Builtin.GlobalInvocationId, Builtin.LocalInvocationId,
		Builtin.LocalInvocationIndex, Builtin.WorkgroupId, Builtin.NumWorkgroups];
	let compute = workgroupSize.elements.length > 0;

	let inputType: Node | null = null;
	let bindingsType: Node | null = null;
	let uniformLoadSite: Node | null = null;
	let keyType: Node | null = null;
	for (let i = 0; i < signature.typExprParams.length; i++) {
		const name = signature.typExprParamNames[i];
		const t = signature.typExprParams[i];
		const fields = fieldsOf(t);
		if (fields == null) {
			fail(fn, "parameter '" + name + "' is not the input, bindings or program key struct");
		}
		for (const decorators of fields.typExprFieldDecorators) {
			const builtin = decorator(decorators, "builtin");
			if (builtin != null && computeBuiltins.indexOf(argumentName(builtin)) >= 0) {
				if (!compute) {
					fail(entry, "a compute entry is written glslCompute(entry, [x, y, z]), " +
						"with its workgroup size");
				}
			}
		}
		if (hasDecorator(fields, "binding")) {
			if (bindingsType != null) { fail(fn, "two bindings structs: '" + name + "'"); }
			bindingsType = t;
		} else if (fields.typExprFieldNames.length > 0 && everyDecorated(fields, "feature")) {
			if (keyType != null) { fail(fn, "two program key structs: '" + name + "'"); }
			keyType = t;
		} else {
			if (inputType != null) { fail(fn, "two stage input structs: '" + name + "'"); }
			inputType = t;
		}
	}

	function isType(n: Node, t: Node | null): boolean {
		if (t == null) { return false; }
		const own = getType(n);
		return own != null && sameType(own, t);
	}

	let m = new ShaderModule();
	const stage = compute ? ShaderStage.Compute :
		vertex ? ShaderStage.Vertex : ShaderStage.Fragment;
	let features: FeatureCondition[] = [];
	let globals: string[] = [];
	let memberNames: string[] = [];
	let memberSlots: int32[] = [];
	let resourceContexts: FeatureCondition[][][] = [];
	let ioFixed: FeatureCondition[] = [];
	let functionContexts: FeatureCondition[][][] = [];
	let storageResources: int32[] = [];
	let storageElements: Node[] = [];
	let storageSites: Node[] = [];
	const resourceRead = 0;
	const ioRead = 1;
	const callRead = 2;

	function claim(name: string, at: Node): void {
		if (globals.indexOf(name) >= 0) {
			fail(at, "'" + name + "' names two things in one stage");
		}
		globals.push(name);
	}

	function claimMember(name: string, slot: int32, at: Node): void {
		const seen = memberNames.indexOf(name);
		if (seen >= 0 && memberSlots[seen] == slot) { return; }
		claim(name, at);
		memberNames.push(name);
		memberSlots.push(slot);
	}

	function noted(c: FeatureCondition): FeatureCondition {
		featureNames(c, m.features);
		return c;
	}

	function addResource(kind: ResourceKind, name: string, slot: int32, type: ShaderType,
		at: Node): ShaderResource {
		claim(name, at);
		let r = new ShaderResource();
		r.kind = kind;
		r.name = name;
		r.binding = slot;
		r.group = kind == ResourceKind.UniformBlock ? 0 : kind == ResourceKind.Sampler ? 2 : 1;
		r.type = type;
		m.resources.push(r);
		resourceContexts.push([]);
		return r;
	}

	function addIo(ioStage: ShaderStage, name: string, direction: IoDirection, type: ShaderType,
		builtin: Builtin, condition: FeatureCondition): int32 {
		let io = new ShaderIo();
		io.stage = ioStage;
		io.name = name;
		io.direction = direction;
		io.type = type;
		io.builtin = builtin;
		io.condition = condition;
		m.ios.push(io);
		ioFixed.push(condition);
		return (m.ios.length - 1) as int32;
	}

	function featureCondition(decorators: Node[]): FeatureCondition {
		const feature = decorator(decorators, "feature");
		return feature == null ? new FeatureCondition() : noted(featureOn(argumentName(feature)));
	}

	function interpolationOf(t: Node, at: Node, decorators: Node[]): Interpolation {
		const own = glslType(t.kind == NodeKind.TypeArray ? t.typExprElement : t, at);
		const integral = (own.kind == ShaderTypeKind.Scalar || own.kind == ShaderTypeKind.Vector) &&
			(own.scalar == ScalarKind.I32 || own.scalar == ScalarKind.U32);
		const d = decorator(decorators, "interpolate");
		if (d == null) { return integral ? Interpolation.Flat : Interpolation.Perspective; }
		const kind = interpolateWord(d, 0);
		if (kind == "flat") {
			if (d.macroArgs.length > 1) {
				fail(d, "@interpolate(flat) takes no sampling, as WGSL's");
			}
			return Interpolation.Flat;
		}
		if (integral) { fail(d, "an integer varying is @interpolate(flat), as WGSL's"); }
		if (kind == "linear") { return Interpolation.Linear; }
		if (kind == "perspective") { return Interpolation.Perspective; }
		return fail(d, "@interpolate takes flat, linear or perspective, as WGSL's");
	}

	function interpolateWord(d: Node, at: int32): string {
		if (d.macroArgs.length < 1 || d.macroArgs.length > 2) {
			fail(d, "@interpolate takes a kind and an optional sampling");
		}
		const a = d.macroArgs[at];
		if (a.kind != NodeKind.Identifier) { fail(d, "@interpolate takes names"); }
		return a.name;
	}

	function samplingOf(decorators: Node[]): Sampling {
		const d = decorator(decorators, "interpolate");
		if (d == null || d.macroArgs.length < 2) { return Sampling.Center; }
		const word = interpolateWord(d, 1);
		if (word == "center") { return Sampling.Center; }
		if (word == "centroid") { return Sampling.Centroid; }
		if (word == "sample") { return Sampling.Sample; }
		return fail(d, "@interpolate's sampling is center, centroid or sample, as WGSL's");
	}

	function noInterpolate(decorators: Node[], what: string): void {
		const d = decorator(decorators, "interpolate");
		if (d != null) { fail(d, "@interpolate sits on a varying, not " + what + ", as WGSL's"); }
	}

	function arrayVarying(name: string): string {
		return "varying '" + name + "' is an array, which WGSL does not pass between stages: " +
			"declare one varying each";
	}

	function member(t: Node, name: string, at: Node): ShaderType {
		const own = interfaceMemberType(typeNodes, t, name);
		if (!own.ok) { fail(at, own.error); }
		return own.value;
	}

	function sampleTypeOf(d: Node): SampleType {
		const spelled = argumentName(d);
		const names = ["float", "unfilterable_float", "depth", "sint", "uint"];
		const kinds = [SampleType.Float, SampleType.UnfilterableFloat, SampleType.Depth,
			SampleType.Sint, SampleType.Uint];
		const at = names.indexOf(spelled);
		if (at < 0) { fail(d, "@sampleType is float, unfilterable_float, depth, sint or uint"); }
		return kinds[at];
	}

	function samplerTypeOf(d: Node): SamplerType {
		const spelled = argumentName(d);
		const names = ["filtering", "nonfiltering", "comparison"];
		const kinds = [SamplerType.Filtering, SamplerType.NonFiltering, SamplerType.Comparison];
		const at = names.indexOf(spelled);
		if (at < 0) { fail(d, "@samplerType is filtering, nonfiltering or comparison"); }
		return kinds[at];
	}

	const bindings = fieldsOf(bindingsType);
	if (bindings != null) {
		for (let f = 0; f < bindings.typExprFieldNames.length; f++) {
			const name = bindings.typExprFieldNames[f];
			const t = bindings.typExprFieldTypes[f];
			const decorators = bindings.typExprFieldDecorators[f];
			const binding = decorator(decorators, "binding");
			if (binding == null) {
				fail(fieldSite(decorators), "binding '" + name + "' has no @binding(n)");
			}
			const slot = argumentNumber(binding);
			const sampleType = decorator(decorators, "sampleType");
			const samplerKind = decorator(decorators, "samplerType");
			const access = decorator(decorators, "access");
			const writes = access != null && argumentName(access) == "read_write";
			if (access != null && !writes && argumentName(access) != "read" &&
				argumentName(access) != "write") {
				fail(access, "binding '" + name + "': @access is read, write or read_write");
			}
			const shape = getTypeImpl(t);
			if (shape != null && shape.kind == NodeKind.TypeArray && shape.typExprSize < 0) {
				if (access != null && argumentName(access) == "write") {
					fail(access, "storage buffer '" + name + "' cannot be @access(write): WGSL's " +
						"storage buffers are read or read_write, and write is a storage " +
						"texture's mode");
				}
				if (writes && !compute) {
					fail(access, "storage buffer '" + name +
						"' is written only in a compute entry");
				}
				storageResources.push(m.resources.length as int32);
				storageElements.push(shape.typExprElement);
				storageSites.push(binding);
				const r = addResource(ResourceKind.StorageBuffer, name, slot,
					arrayType(structType(-1), -1), binding);
				r.access = writes ? Access.ReadWrite : Access.Read;
				continue;
			}
			const storageShape = storageTextureNodes.findIndex((n) => sameType(t, n));
			if (storageShape >= 0) {
				if (!compute) {
					fail(binding, "storage texture '" + name + "' is a compute binding");
				}
				const format = decorator(decorators, "format");
				if (format == null) {
					fail(binding, "storage texture '" + name + "' has no @format(texel format)");
				}
				const texel = argumentName(format);
				const formats = ["rgba8unorm", "rgba8snorm", "rgba8uint", "rgba8sint",
					"rgba16uint", "rgba16sint", "rgba16float", "r32uint", "r32sint", "r32float",
					"rg32uint", "rg32sint", "rg32float", "rgba32uint", "rgba32sint", "rgba32float",
					"bgra8unorm"];
				const texels = [TexelFormat.Rgba8unorm, TexelFormat.Rgba8snorm,
					TexelFormat.Rgba8uint, TexelFormat.Rgba8sint, TexelFormat.Rgba16uint,
					TexelFormat.Rgba16sint, TexelFormat.Rgba16float, TexelFormat.R32uint,
					TexelFormat.R32sint, TexelFormat.R32float, TexelFormat.Rg32uint,
					TexelFormat.Rg32sint, TexelFormat.Rg32float, TexelFormat.Rgba32uint,
					TexelFormat.Rgba32sint, TexelFormat.Rgba32float, TexelFormat.Bgra8unorm];
				const at = formats.indexOf(texel);
				if (at < 0) {
					fail(format, "storage texture format '" + texel + "' is none of WGSL's core " +
						"storage texel formats: " + formats.join(", "));
				}
				if (texelScalar(texels[at]) != storageChannels[storageShape]) {
					fail(format, "storage texture '" + name + "' holds " +
						channelName(storageChannels[storageShape]) + " texels, and @format(" +
						texel + ") gives " + channelName(texelScalar(texels[at])) +
						": its type is the StorageTexture of that channel type");
				}
				const writeOnly = access == null || argumentName(access) == "write";
				const mode = writeOnly ? Access.Write : writes ? Access.ReadWrite : Access.Read;
				const r = addResource(ResourceKind.StorageTexture, name, slot,
					storageTextureType(texels[at], mode, storageShapes[storageShape]), binding);
				r.access = mode;
				continue;
			}
			const view = viewNodes.findIndex((n) => sameType(t, n));
			if (view >= 0) {
				const r = addResource(ResourceKind.Texture, name, slot,
					textureType(viewShapes[view], viewTexels[view]), binding);
				r.sampleType = viewSamples[view] != SampleType.Float ? viewSamples[view] :
					sampleType == null ? SampleType.Float : sampleTypeOf(sampleType);
			} else if (sameType(t, textureNode)) {
				const kind = sampleType == null ? SampleType.Float : sampleTypeOf(sampleType);
				const r = addResource(ResourceKind.Texture, name, slot,
					textureType(TextureShape.D2, ScalarKind.F32), binding);
				r.sampleType = kind;
			} else if (sameType(t, samplerNode)) {
				const kind = samplerKind == null ? SamplerType.Filtering :
					samplerTypeOf(samplerKind);
				const r = addResource(ResourceKind.Sampler, name, slot, samplerType(), binding);
				r.samplerType = kind;
			} else if (sameType(t, comparisonNode)) {
				const r = addResource(ResourceKind.Sampler, name, slot, samplerType(), binding);
				r.samplerType = SamplerType.Comparison;
			} else {
				const block = fieldsOf(t);
				if (block == null) {
					fail(binding, "binding '" + name +
						"' is not a texture, a sampler or a uniform struct");
				}
				let layout = new ShaderStruct();
				layout.name = block.typExprTypeName;
				for (let k = 0; k < block.typExprFieldNames.length; k++) {
					const memberName = block.typExprFieldNames[k];
					claimMember(memberName, slot, binding);
					const own = blockMemberOf(typeNodes, block as TypeObjectData, k as int32);
					if (!own.ok) { fail(binding, own.error); }
					layout.members.push(own.value);
				}
				m.structs.push(layout);
				addResource(ResourceKind.UniformBlock, name, slot,
					structType((m.structs.length - 1) as int32), binding);
			}
		}
	}

	const inputs = fieldsOf(inputType);
	let builtinInputNames: string[] = [];
	let builtinInputIos: int32[] = [];
	let inputNames: string[] = [];
	let inputIos: int32[] = [];
	let attributeNames: string[] = [];
	const feederType = getType(feeder);
	let outputNames: string[] = [];
	let outputIos: int32[] = [];
	let outputFeatures: FeatureCondition[] = [];
	const noOutput = outputType != null && typeKind(outputType) == TypeKind.Void;

	let structTypes: Node[] = [];
	let structIndices: int32[] = [];

	let recordKinds: int32[][] = [];
	let recordIndices: int32[][] = [];
	let recordGates: FeatureCondition[][][] = [];
	let recordReads: Node[][] = [];
	let recording = -1;

	let functionKeys: string[] = [];
	let functionIndices: int32[] = [];
	let openKeys: string[] = [];
	let constantKeys: string[] = [];
	let constantIndices: int32[] = [];
	let workgroupKeys: string[] = [];
	let workgroupIndices: int32[] = [];
	let scopeModule = "";
	let current = new ShaderFunction();
	let paramNames: string[] = [];
	let localKeys: string[] = [];
	let localIndices: int32[] = [];
	let constLocalIndices: int32[] = [];
	let constLocalValues: ShaderExpr[] = [];
	let inHelper = false;
	let breakOwners: string[] = [];
	let locals: string[] = [];

	const binaryTexts = ["+", "-", "*", "/", "%", "&", "|", "^", "<<", ">>", "&&", "||", "==", "!=",
		"<", "<=", ">", ">="];
	const binaryOps = [BinaryOp.Add, BinaryOp.Sub, BinaryOp.Mul, BinaryOp.Div, BinaryOp.Mod,
		BinaryOp.BitAnd, BinaryOp.BitOr, BinaryOp.BitXor, BinaryOp.ShiftLeft, BinaryOp.ShiftRight,
		BinaryOp.LogicalAnd, BinaryOp.LogicalOr, BinaryOp.Equal,
		BinaryOp.NotEqual, BinaryOp.Less, BinaryOp.LessEqual, BinaryOp.Greater,
		BinaryOp.GreaterEqual];

	const intrinsicNames = [
		"abs", "sign", "floor", "ceil", "trunc", "fract", "sqrt", "exp", "exp2", "log", "log2",
		"sin", "cos", "tan", "asin", "acos", "atan", "sinh", "cosh", "tanh", "degrees", "radians",
		"max", "min", "clamp", "mix", "step", "smoothstep", "fma", "pow", "dot", "cross", "length",
		"distance", "normalize", "reflect", "refract", "transpose", "determinant", "inverse",
		"round", "inverseSqrt", "atan2", "faceForward", "saturate", "upperLeft3x3", "select", "le",
		"lt", "gt", "ge", "eq", "ne", "any", "all",
		"textureDimensions", "textureStore", "textureLoad", "atomicLoad", "atomicStore",
		"atomicAdd", "atomicSub", "atomicMax", "atomicMin", "atomicAnd", "atomicOr", "atomicXor",
		"atomicExchange", "atomicCompareExchangeWeak",
		"countOneBits", "reverseBits", "firstLeadingBit", "firstTrailingBit", "extractBits",
		"insertBits", "pack4x8unorm", "pack4x8snorm", "pack2x16unorm", "pack2x16snorm",
		"pack2x16float", "unpack4x8unorm", "unpack4x8snorm", "unpack2x16unorm", "unpack2x16snorm",
		"unpack2x16float", "asinh", "acosh", "atanh", "ldexp", "countLeadingZeros",
		"countTrailingZeros", "bitcastF32toU32", "bitcastF32toI32", "bitcastI32toF32",
		"bitcastI32toU32", "bitcastU32toF32", "bitcastU32toI32", "modf", "frexp",
		"textureNumSamples",
	];
	const intrinsics = [
		Intrinsic.Abs, Intrinsic.Sign, Intrinsic.Floor, Intrinsic.Ceil, Intrinsic.Trunc,
		Intrinsic.Fract, Intrinsic.Sqrt, Intrinsic.Exp, Intrinsic.Exp2, Intrinsic.Log,
		Intrinsic.Log2, Intrinsic.Sin, Intrinsic.Cos, Intrinsic.Tan, Intrinsic.Asin,
		Intrinsic.Acos, Intrinsic.Atan, Intrinsic.Sinh, Intrinsic.Cosh, Intrinsic.Tanh,
		Intrinsic.Degrees, Intrinsic.Radians, Intrinsic.Max, Intrinsic.Min, Intrinsic.Clamp,
		Intrinsic.Mix, Intrinsic.Step, Intrinsic.Smoothstep, Intrinsic.Fma, Intrinsic.Pow,
		Intrinsic.Dot, Intrinsic.Cross, Intrinsic.Length, Intrinsic.Distance, Intrinsic.Normalize,
		Intrinsic.Reflect, Intrinsic.Refract, Intrinsic.Transpose, Intrinsic.Determinant,
		Intrinsic.Inverse, Intrinsic.Round, Intrinsic.InverseSqrt, Intrinsic.Atan2,
		Intrinsic.FaceForward, Intrinsic.Saturate, Intrinsic.UpperLeft3x3, Intrinsic.Select,
		Intrinsic.LessThanEqual, Intrinsic.LessThan, Intrinsic.GreaterThan,
		Intrinsic.GreaterThanEqual, Intrinsic.Equal, Intrinsic.NotEqual, Intrinsic.Any,
		Intrinsic.All, Intrinsic.TextureDimensions, Intrinsic.TextureStore,
		Intrinsic.TextureLoad, Intrinsic.AtomicLoad, Intrinsic.AtomicStore, Intrinsic.AtomicAdd,
		Intrinsic.AtomicSub, Intrinsic.AtomicMax, Intrinsic.AtomicMin, Intrinsic.AtomicAnd,
		Intrinsic.AtomicOr, Intrinsic.AtomicXor, Intrinsic.AtomicExchange,
		Intrinsic.AtomicCompareExchangeWeak, Intrinsic.CountOneBits, Intrinsic.ReverseBits,
		Intrinsic.FirstLeadingBit, Intrinsic.FirstTrailingBit, Intrinsic.ExtractBits,
		Intrinsic.InsertBits, Intrinsic.Pack4x8Unorm, Intrinsic.Pack4x8Snorm,
		Intrinsic.Pack2x16Unorm, Intrinsic.Pack2x16Snorm, Intrinsic.Pack2x16Float,
		Intrinsic.Unpack4x8Unorm, Intrinsic.Unpack4x8Snorm, Intrinsic.Unpack2x16Unorm,
		Intrinsic.Unpack2x16Snorm, Intrinsic.Unpack2x16Float, Intrinsic.Asinh, Intrinsic.Acosh,
		Intrinsic.Atanh, Intrinsic.Ldexp, Intrinsic.CountLeadingZeros, Intrinsic.CountTrailingZeros,
		Intrinsic.Bitcast, Intrinsic.Bitcast, Intrinsic.Bitcast, Intrinsic.Bitcast,
		Intrinsic.Bitcast, Intrinsic.Bitcast, Intrinsic.Modf, Intrinsic.Frexp,
		Intrinsic.TextureNumSamples,
	];
	const derivativeNames = ["dpdx", "dpdy", "fwidth", "dpdxCoarse", "dpdxFine", "dpdyCoarse",
		"dpdyFine", "fwidthCoarse", "fwidthFine"];
	const derivatives = [Intrinsic.Dpdx, Intrinsic.Dpdy, Intrinsic.Fwidth, Intrinsic.DpdxCoarse,
		Intrinsic.DpdxFine, Intrinsic.DpdyCoarse, Intrinsic.DpdyFine, Intrinsic.FwidthCoarse,
		Intrinsic.FwidthFine];

	function looseType(t: Node | null): ShaderType {
		if (t == null) { return new ShaderType(); }
		match (typeKind(t)) {
			TypeKind.Float32 | TypeKind.Float64 => { return scalarType(ScalarKind.F32); },
			TypeKind.Int32 => { return scalarType(ScalarKind.I32); },
			TypeKind.Uint32 => { return scalarType(ScalarKind.U32); },
			TypeKind.Boolean => { return scalarType(ScalarKind.Bool); },
			TypeKind.SizedArray => {
				return arrayType(looseType(t.typExprElement), t.typExprSize as int32);
			},
			_ => {},
		}
		for (let i = 0; i < vectorTypes.length; i++) {
			if (sameType(t, vectorTypes[i])) { return vectorAt(typeNodes, i); }
		}
		if (sameType(t, textureNode)) { return textureType(TextureShape.D2, ScalarKind.F32); }
		const view = viewNodes.findIndex((n) => sameType(t, n));
		if (view >= 0) { return textureType(viewShapes[view], viewTexels[view]); }
		if (sameType(t, samplerNode) || sameType(t, comparisonNode)) { return samplerType(); }
		const predeclared = predeclaredType(t);
		if (predeclared != null) { return predeclared; }
		if (isAuthorStruct(t)) { return structType(knownStruct(t)); }
		return new ShaderType();
	}

	function varyingName(name: string): string {
		return suffixed(name, attributeNames);
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

	function checkName(name: string, at: Node): void {
		if (!isGlslIdentifier(name)) {
			fail(at, "'" + name + "' is no GLSL name: only letters, digits and '_', " +
				"without '__' or the prefix 'gl_'");
		}
	}

	function declare(kind: DeclarationKind, index: int32): void {
		let d = new ShaderDeclaration();
		d.kind = kind;
		d.index = index;
		m.declarations.push(d);
	}

	function knownStruct(t: Node): int32 {
		for (let i = 0; i < structTypes.length; i++) {
			if (sameType(t, structTypes[i])) { return structIndices[i]; }
		}
		return -1;
	}

	function valueType(t: Node | null, at: Node): ShaderType {
		if (t != null && typeKind(t) == TypeKind.SizedArray) {
			return arrayType(valueType(t.typExprElement, at), t.typExprSize as int32);
		}
		return t != null && isAuthorStruct(t) ? structType(structIndex(t, at)) : glslType(t, at);
	}

	function structIndex(t: Node, at: Node): int32 {
		const known = knownStruct(t);
		if (known >= 0) { return known; }
		const fields = fieldsOf(t);
		const typeName = fields.typExprTypeName;
		if (isInterface(t)) {
			fail(at, "'" + typeName + "' is a stage interface struct, read one field at a time");
		}
		let s = new ShaderStruct();
		s.name = typeName;
		for (let f = 0; f < fields.typExprFieldNames.length; f++) {
			const name = fields.typExprFieldNames[f];
			const ft = fields.typExprFieldTypes[f];
			const element = ft.kind == NodeKind.TypeArray ? ft.typExprElement : ft;
			if (sameType(element, textureNode) || sameType(element, samplerNode)) {
				fail(at, "struct '" + typeName + "' holds the texture or sampler '" + name +
					"': a GLSL struct holds values, so a binding is passed on its own");
			}
			if (!isGlslIdentifier(name)) {
				fail(at, "field '" + name + "' of struct '" + typeName + "' is no GLSL name");
			}
			s.members.push(shaderField(name, valueType(ft, at)));
		}
		checkName(typeName, at);
		const index = m.structs.length as int32;
		m.structs.push(s);
		declare(DeclarationKind.Struct, index);
		structTypes.push(t);
		structIndices.push(index);
		return index;
	}

	function swizzleOf(
		object: ShaderExpr,
		letters: string,
		at: Node,
		type: ShaderType,
	): ShaderExpr {
		const colour = "rgba".indexOf(letters.slice(0, 1)) >= 0;
		const set = colour ? "rgba" : "xyzw";
		let e = exprOf(ExprKind.Swizzle, type, -1, [object]);
		e.rgba = colour;
		for (let i = 0; i < letters.length; i++) {
			const c = set.indexOf(letters.slice(i, i + 1));
			if (c < 0) { fail(at, "'" + letters + "' has no GLSL form yet"); }
			e.components.push(c as int32);
		}
		return e;
	}

	function memberOf(object: ShaderExpr, n: Node): ShaderExpr {
		const t = getType(n.object);
		const predeclared = t == null ? null : predeclaredType(t);
		if (predeclared != null && predeclared.kind == ShaderTypeKind.Atomic) {
			fail(n, "an atomic is read through atomicLoad and written through atomicStore, " +
				"as WGSL's");
		}
		if (predeclared != null && predeclared.kind != ShaderTypeKind.ExchangeResult) {
			const member = n.property == "fract" ? 0 : 1;
			return exprOf(ExprKind.Field, predeclaredMemberType(predeclared, member), member,
				[object]);
		}
		if (predeclared != null) {
			const old = n.property == "oldValue";
			return exprOf(ExprKind.Field, old ? scalarType(predeclared.scalar) :
				scalarType(ScalarKind.Bool), old ? 0 : 1, [object]);
		}
		if (t == null || !isAuthorStruct(t)) {
			return swizzleOf(object, n.property, n, looseType(getType(n)));
		}
		const s = structIndex(t, n);
		object.type = structType(s);
		const members = m.structs[s].members;
		let at = -1;
		for (let f = 0; f < members.length; f++) {
			if (members[f].name == n.property) { at = f; }
		}
		return exprOf(ExprKind.Field, members[at].type, at as int32, [object]);
	}

	function construction(n: Node): ShaderExpr {
		const t = getType(n);
		const type = valueType(t, n);
		const fields = fieldsOf(t);
		let args: ShaderExpr[] = [];
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
			args.push(lower(n.properties[k]));
		}
		return exprOf(ExprKind.Construct, type, -1, args);
	}

	function useUnder(kind: int32, index: int32, gates: FeatureCondition[], read: Node,
		call: Node | null): void {
		if (kind == ioRead) {
			const fixed = ioFixed[index];
			if (fixed.kind == ConditionKind.Always) { return; }
			for (const g of gates) {
				if (conjunctOf(g, fixed)) { return; }
			}
			const feature = "@feature(" + fixed.feature + ")";
			const message = "'" + read.property + "' is declared only under " + feature + ", and ";
			const advice = " outside it: read it inside an if on the program key field marked " +
				feature;
			if (call == null) { fail(read, message + "this read runs" + advice); }
			fail(call, message + "this call reads it" + advice);
		}
		const contexts = kind == resourceRead ? resourceContexts[index] : functionContexts[index];
		if (!contexts.some((c) => sameProduct(c, gates))) { contexts.push(gates.slice(0)); }
	}

	function use(kind: int32, index: int32, read: Node): void {
		if (recording >= 0) {
			recordKinds[recording].push(kind);
			recordIndices[recording].push(index);
			recordGates[recording].push(features.slice(0));
			recordReads[recording].push(read);
			return;
		}
		useUnder(kind, index, features.slice(0), read, null);
	}

	function replay(f: int32, gates: FeatureCondition[], call: Node): void {
		useUnder(callRead, f, gates, call, call);
		for (let k = 0; k < recordKinds[f].length; k++) {
			const under = union(gates, recordGates[f][k]);
			if (recordKinds[f][k] == callRead) {
				replay(recordIndices[f][k], under, call);
			} else {
				useUnder(recordKinds[f][k], recordIndices[f][k], under, recordReads[f][k], call);
			}
		}
	}

	function addFunction(f: ShaderFunction): int32 {
		const index = m.functions.length as int32;
		m.functions.push(f);
		declare(DeclarationKind.Function, index);
		functionContexts.push([]);
		recordKinds.push([]);
		recordIndices.push([]);
		recordGates.push([]);
		recordReads.push([]);
		return index;
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
		if (constantKeys.includes(key) || workgroupKeys.includes(key)) { return; }
		if (decl.declKind != DeclKind.Const) {
			if (!compute) {
				fail(n, "'" + n.name + "' is a module variable: a shader reads only module " +
					"constants, and a compute entry shares one as workgroup memory");
			}
			defineWorkgroup(n, decl, key);
			return;
		}
		gather(decl.initializer, module, [], decl);
		checkName(decl.declName, n);
		let c = new ShaderConstant();
		c.name = decl.declName;
		const index = m.constants.length as int32;
		m.constants.push(c);
		declare(DeclarationKind.Constant, index);
		c.type = valueType(getType(n), n);
		c.value = lower(decl.initializer);
		constantKeys.push(key);
		constantIndices.push(index);
	}

	function defineWorkgroup(n: Node, decl: Node, key: string): void {
		if (decl.initializer != null) {
			fail(n, "workgroup variable '" + n.name + "' starts at zero, as WGSL's " +
				"var<workgroup>: drop its initializer");
		}
		checkName(decl.declName, n);
		const index = m.workgroups.length as int32;
		m.workgroups.push(shaderField(decl.declName, valueType(getType(n), n)));
		declare(DeclarationKind.Workgroup, index);
		workgroupKeys.push(key);
		workgroupIndices.push(index);
	}

	function workgroupOf(n: Node): int32 {
		if (n.kind != NodeKind.Identifier || symKind(n) != SymbolKind.Variable ||
			n.resolvedSym == null) {
			return -1;
		}
		const at = workgroupKeys.indexOf(declKey(n.resolvedSym.modulePath, declaration(n)));
		return at < 0 ? -1 : workgroupIndices[at];
	}

	function zeroed(place: ShaderExpr): ShaderStmt {
		const t = place.type;
		if (t.kind == ShaderTypeKind.Atomic) {
			return stmtOf(StmtKind.Call, intrinsicOf(Intrinsic.AtomicStore, new ShaderType(),
				[place, literal(scalarType(t.scalar), 0.0)]), []);
		}
		if (t.kind == ShaderTypeKind.Scalar) { return assignOf(place, literal(t, 0.0)); }
		return assignOf(place, exprOf(ExprKind.Construct, t, -1,
			[literal(scalarType(t.scalar), 0.0)]));
	}

	function zeroedWorkgroups(f: ShaderFunction): ShaderStmt[] {
		const u32 = scalarType(ScalarKind.U32);
		let index = m.ios.findIndex((io) => io.stage == stage &&
			io.builtin == Builtin.LocalInvocationIndex);
		if (index < 0) {
			index = addIo(stage, "localInvocationIndex", IoDirection.In, u32,
				Builtin.LocalInvocationIndex, new FeatureCondition());
		}
		let zeroes: ShaderStmt[] = [];
		for (let w = 0; w < m.workgroups.length; w++) {
			const t = m.workgroups[w].type;
			const variable = exprOf(ExprKind.Workgroup, t, w as int32, []);
			if (t.kind != ShaderTypeKind.Array) {
				zeroes.push(zeroed(variable));
				continue;
			}
			const at = f.locals.length as int32;
			f.locals.push(shaderField("zeroAt", u32));
			const counter = exprOf(ExprKind.Local, u32, at, []);
			let start = stmtOf(StmtKind.Let, literal(u32, 0.0), []);
			start.local = at;
			let step = assignOf(counter, new ShaderExpr());
			step.assign = AssignOp.Increment;
			let loop = stmtOf(StmtKind.For,
				binaryOf(BinaryOp.Less, scalarType(ScalarKind.Bool), counter,
					literal(u32, t.length as float64)),
				[zeroed(exprOf(ExprKind.Index, t.element[0], -1, [variable, counter]))]);
			loop.init = [start];
			loop.update = [step];
			zeroes.push(loop);
		}
		const first = binaryOf(BinaryOp.Equal, scalarType(ScalarKind.Bool),
			exprOf(ExprKind.Io, u32, index as int32, []), literal(u32, 0.0));
		const barrier = intrinsicOf(Intrinsic.WorkgroupBarrier, new ShaderType(), []);
		return [stmtOf(StmtKind.If, first, zeroes), stmtOf(StmtKind.Call, barrier, [])];
	}

	function enterScope(module: string, f: ShaderFunction): void {
		scopeModule = module;
		current = f;
		paramNames = [];
		localKeys = [];
		localIndices = [];
		constLocalIndices = [];
		constLocalValues = [];
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

		let params: ShaderField[] = [];
		for (let i = 0; i < helperType.typExprParams.length; i++) {
			const t = helperType.typExprParams[i];
			if (isInterface(t)) { continue; }
			params.push(shaderField(helperType.typExprParamNames[i], valueType(t, callee)));
		}
		checkName(helper.fnName, callee);
		let f = new ShaderFunction();
		f.name = helper.fnName;
		const index = addFunction(f);
		functionKeys.push(key);
		functionIndices.push(index);

		enterScope(module, f);
		for (const p of params) {
			checkName(p.name, callee);
			f.params.push(p);
			paramNames.push(p.name);
		}
		const outer = recording;
		recording = index;
		inHelper = true;
		f.body = lowerBody(helper.fnBody);
		inHelper = false;
		recording = outer;
		f.result = valueType(helperType.typExprReturn, callee);
	}

	function local(n: Node, type: ShaderType, value: ShaderExpr): int32 {
		checkName(n.declName, n);
		const index = current.locals.length as int32;
		current.locals.push(shaderField(n.declName, type));
		localKeys.push(declKey(scopeModule, n));
		localIndices.push(index);
		if (n.declKind == DeclKind.Const) {
			constLocalIndices.push(index);
			constLocalValues.push(value);
		}
		return index;
	}

	function identifier(n: Node): ShaderExpr {
		const kind = symKind(n);
		if (kind == SymbolKind.Parameter && paramNames.includes(n.name)) {
			const i = paramNames.indexOf(n.name);
			return exprOf(ExprKind.Param, current.params[i].type, i as int32, []);
		}
		if (kind == SymbolKind.Variable && n.resolvedSym != null) {
			const key = declKey(n.resolvedSym.modulePath, declaration(n));
			if (localKeys.includes(key)) {
				const i = localIndices[localKeys.indexOf(key)];
				return exprOf(ExprKind.Local, current.locals[i].type, i, []);
			}
			if (constantKeys.includes(key)) {
				const i = constantIndices[constantKeys.indexOf(key)];
				return exprOf(ExprKind.Constant, m.constants[i].type, i, []);
			}
			const w = workgroupOf(n);
			if (w >= 0) { return exprOf(ExprKind.Workgroup, m.workgroups[w].type, w, []); }
		}
		fail(n, "'" + n.name + "' has no GLSL form yet");
	}

	function call(n: Node, callee: Node, impl: Node): ShaderExpr {
		const key = declKey(callee.resolvedSym.modulePath, impl);
		if (callee.kind != NodeKind.Identifier || !functionKeys.includes(key)) {
			fail(n, "method calls have no GLSL form yet");
		}
		const f = functionIndices[functionKeys.indexOf(key)];
		if (recording >= 0) {
			recordKinds[recording].push(callRead);
			recordIndices[recording].push(f);
			recordGates[recording].push(features.slice(0));
			recordReads[recording].push(n);
		} else {
			replay(f, features.slice(0), n);
		}
		let args: ShaderExpr[] = [];
		for (const a of n.arguments) {
			if (!isInterface(getType(a))) { args.push(lower(a)); }
		}
		return exprOf(ExprKind.Call, m.functions[f].result, f, args);
	}

	function number(n: Node): ShaderExpr {
		const kind = typeKind(getType(n));
		if (kind == TypeKind.Float32 || kind == TypeKind.Float64) {
			return literal(scalarType(ScalarKind.F32), floatValue(n));
		}
		const scalar = kind == TypeKind.Uint32 ? ScalarKind.U32 : ScalarKind.I32;
		return literal(scalarType(scalar), intValue(n) as float64);
	}

	function featureOf(n: Node): FeatureCondition | null {
		if (n.kind == NodeKind.MemberExpr && isType(n.object, keyType)) {
			const keys = fieldsOf(keyType);
			const f = keys.typExprFieldNames.indexOf(n.property);
			const feature = decorator(keys.typExprFieldDecorators[f], "feature");
			if (feature == null) {
				fail(n, "key field '" + n.property + "' has no @feature(NAME)");
			}
			return noted(featureOn(argumentName(feature)));
		}
		if (n.kind == NodeKind.UnaryExpr && n.unaryOp == "!") {
			const inner = featureOf(n.operand);
			return inner == null ? null : negated(inner);
		}
		if (n.kind == NodeKind.BinaryExpr && (n.operator == "&&" || n.operator == "||")) {
			const left = featureOf(n.left);
			const right = featureOf(n.right);
			if (left == null && right == null) { return null; }
			if (left == null || right == null) {
				fail(n, "a condition reads program key features and values together; " +
					"write the key's part as its own if");
			}
			return conditionOf(n.operator == "&&" ? ConditionKind.All : ConditionKind.Any,
				[left, right]);
		}
		return null;
	}

	function kindOf(n: Node): TypeKind { return typeKind(getType(n)); }

	function scalar(n: Node): boolean {
		return match (kindOf(n)) {
			TypeKind.Float32 | TypeKind.Int32 | TypeKind.Uint32 | TypeKind.Boolean => true,
			_ => false,
		};
	}

	function integer(n: Node): boolean {
		return match (kindOf(n)) {
			TypeKind.Int32 | TypeKind.Uint32 => true,
			_ => false,
		};
	}

	function unsigned(n: Node): boolean {
		return kindOf(n.left) == TypeKind.Uint32 && kindOf(n.right) == TypeKind.Uint32;
	}

	function integral(n: Node): boolean {
		const t = looseType(getType(n));
		return (t.kind == ShaderTypeKind.Scalar || t.kind == ShaderTypeKind.Vector) &&
			(t.scalar == ScalarKind.I32 || t.scalar == ScalarKind.U32);
	}

	function shiftAmount(n: Node): ShaderExpr {
		const e = lower(n);
		if (e.kind == ExprKind.Literal) {
			return literal(scalarType(ScalarKind.U32), ((e.value as int64) & 31) as float64);
		}
		if (e.type.scalar == ScalarKind.U32) { return e; }
		const type = e.type.kind == ShaderTypeKind.Vector ?
			vectorType(ScalarKind.U32, e.type.rows) : scalarType(ScalarKind.U32);
		return exprOf(ExprKind.Convert, type, -1, [e]);
	}

	function condition(n: Node): ShaderExpr {
		if (kindOf(n) != TypeKind.Boolean) { fail(n, "a shader condition is a boolean"); }
		return lower(n);
	}

	function binary(n: Node): ShaderExpr {
		const op = n.operator == "===" ? "==" : n.operator == "!==" ? "!=" : n.operator;
		match (op) {
			"&&" | "||" => {
				if (kindOf(n.left) != TypeKind.Boolean || kindOf(n.right) != TypeKind.Boolean) {
					fail(n, "'" + op + "' takes booleans in a shader");
				}
			},
			"<" | "<=" | ">" | ">=" | "==" | "!=" => {
				if (!scalar(n.left)) { fail(n, "'" + op + "' compares scalars in a shader"); }
			},
			"%" => {
				if (integer(n.left) && !unsigned(n)) {
					fail(n, "'%' has a GLSL form for uint32 operands only: GLSL leaves a " +
						"negative int32 operand undefined");
				}
			},
			"/" => {
				if (integer(n.left) && !unsigned(n)) {
					fail(n, "'/' has no GLSL form: GLSL does not truncate as MetaScript does");
				}
			},
			"&" | "|" | "^" | "<<" | ">>" => {
				if (!integral(n.left)) { fail(n, "'" + op + "' takes integers in a shader"); }
			},
			"+" | "-" | "*" => {},
			_ => { fail(n, "operator '" + op + "' has no GLSL form yet"); },
		}
		const left = lower(n.left);
		const right = op == "<<" || op == ">>" ? shiftAmount(n.right) : lower(n.right);
		const type = looseType(getType(n));
		if ((op == "/" || op == "%") &&
			(type.scalar == ScalarKind.I32 || type.scalar == ScalarKind.U32) &&
			constantExpr(left) && constantExpr(right) && zeroComponent(right)) {
			fail(n, "'" + op + "' by a constant zero: an integer " +
				(op == "/" ? "division" : "remainder") +
				" of const-expressions by zero is a shader-creation error in WGSL");
		}
		return binaryOf(binaryOps[binaryTexts.indexOf(op)], type, left, right);
	}

	function builtinCall(n: Node, name: string): ShaderExpr {
		let args: ShaderExpr[] = [];
		for (const a of n.arguments) { args.push(lower(a)); }
		const type = looseType(getType(n));
		const made = constructors.indexOf(name);
		if (name != "" && made >= 0) {
			return exprOf(ExprKind.Construct, vectorAt(typeNodes, made), -1, args);
		}
		const direct = intrinsicNames.indexOf(name);
		if (direct >= 0) { return intrinsicOf(intrinsics[direct], type, args); }
		if (name == "not") {
			let negated = exprOf(ExprKind.Unary, type, -1, args);
			negated.unary = UnaryOp.Not;
			return negated;
		}
		const outsideFragment = vertex || compute;
		const derivative = derivativeNames.indexOf(name);
		if (derivative >= 0) {
			return outsideFragment ?
				fail(n, name + " exists only in a fragment entry, as WGSL's does") :
				intrinsicOf(derivatives[derivative], type, args);
		}
		const computeOnly = ["workgroupBarrier", "storageBarrier", "textureBarrier",
			"workgroupUniformLoad"];
		if (!compute && computeOnly.includes(name)) {
			fail(n, name + " exists only in a compute entry, as WGSL's does");
		}
		const fragmentSamples = ["textureSample", "textureSampleBias", "textureSampleCompare"];
		if (outsideFragment && fragmentSamples.includes(name)) {
			fail(n, name + " samples only in a fragment entry, as WGSL's does");
		}
		return withConstantOffset(n, name, match (name) {
			"workgroupBarrier" | "storageBarrier" =>
				intrinsicOf(name == "workgroupBarrier" ? Intrinsic.WorkgroupBarrier :
					Intrinsic.StorageBarrier, type, args),
			"textureBarrier" => intrinsicOf(Intrinsic.TextureBarrier, type, args),
			"workgroupUniformLoad" => n != uniformLoadSite ?
				fail(n, name + " is the initializer of a const or let of its own, because the " +
					"barriers around it sit between two statements") :
				intrinsicOf(Intrinsic.WorkgroupUniformLoad, type, args),
			"textureSample" | "textureSampleBias" =>
				intrinsicOf(name == "textureSample" ? Intrinsic.TextureSample :
					Intrinsic.TextureSampleBias, type, args),
			"textureSampleCompare" =>
				intrinsicOf(Intrinsic.TextureSampleCompare, type, args),
			"textureSampleCompareLevel" =>
				intrinsicOf(Intrinsic.TextureSampleCompareLevel, type, args),
			"textureSampleLevel" => intrinsicOf(Intrinsic.TextureSampleLevel, type, args),
			"textureSampleGrad" => intrinsicOf(Intrinsic.TextureSampleGrad, type, args),
			_ => { fail(n, "./std's '" + name + "' has no GLSL spelling"); },
		});
	}

	function folded(e: ShaderExpr): ShaderExpr {
		if (e.kind == ExprKind.Constant) { return folded(m.constants[e.index].value); }
		if (e.kind == ExprKind.Local && constLocalIndices.includes(e.index)) {
			return folded(constLocalValues[constLocalIndices.indexOf(e.index)]);
		}
		return e;
	}

	function integerConstant(e: ShaderExpr): ShaderExpr | null {
		e = folded(e);
		if (e.kind == ExprKind.Literal && e.type.scalar == ScalarKind.I32) { return e; }
		if (e.kind == ExprKind.Unary && e.unary == UnaryOp.Negate) {
			const inner = integerConstant(e.operands[0]);
			return inner == null ? null : literal(inner.type, -inner.value);
		}
		return null;
	}

	function constantExpr(e: ShaderExpr): boolean {
		e = folded(e);
		if (e.kind == ExprKind.Literal) { return true; }
		if (e.kind != ExprKind.Unary && e.kind != ExprKind.Binary && e.kind != ExprKind.Construct &&
			e.kind != ExprKind.Convert && e.kind != ExprKind.Conditional) {
			return false;
		}
		for (const o of e.operands) {
			if (!constantExpr(o)) { return false; }
		}
		return true;
	}

	function zeroComponent(e: ShaderExpr): boolean {
		e = folded(e);
		if (e.kind == ExprKind.Literal) { return e.value == 0.0; }
		if (e.kind == ExprKind.Unary && e.unary == UnaryOp.Negate) {
			return zeroComponent(e.operands[0]);
		}
		if (e.kind == ExprKind.Convert && e.operands[0].type.scalar != ScalarKind.F32) {
			return zeroComponent(e.operands[0]);
		}
		if (e.kind == ExprKind.Construct) {
			for (const o of e.operands) {
				if (zeroComponent(o)) { return true; }
			}
		}
		return false;
	}

	function constantParts(e: ShaderExpr): ShaderExpr[] {
		let parts: ShaderExpr[] = [];
		e = folded(e);
		if (e.kind != ExprKind.Construct || e.type.kind != ShaderTypeKind.Vector ||
			e.type.scalar != ScalarKind.I32) {
			return parts;
		}
		for (const o of e.operands) {
			const part = integerConstant(o);
			if (part == null) { return []; }
			parts.push(part);
		}
		return parts;
	}

	function withConstantOffset(n: Node, name: string, call: ShaderExpr): ShaderExpr {
		if (call.kind != ExprKind.Intrinsic || !isSampling(call.intrinsic) || !hasOffset(call)) {
			return call;
		}
		const at = sampleBase(call);
		const rows = offsetRows(call.operands[0].type.shape);
		if (rows == 0) {
			fail(n, name + " takes no offset on this texture, as WGSL's");
		}
		let parts = constantParts(call.operands[at]);
		if (parts.length == 1) {
			const only = parts[0];
			parts = [];
			for (let i = 0; i < rows; i++) { parts.push(literal(only.type, only.value)); }
		}
		if (parts.length != rows) {
			fail(n, name + " takes a constant offset: a vec" + String(rows) +
				"i of integer literals, or a const of one (a let, or a const of runtime values, " +
				"is not a const-expression), as WGSL's");
		}
		for (const part of parts) {
			if (part.value < OFFSET_MIN || part.value > OFFSET_MAX) {
				fail(n, name + " takes a constant offset in [-8, 7], as WGSL's, not " +
					String(part.value));
			}
		}
		call.operands[at] = exprOf(ExprKind.Construct, vectorType(ScalarKind.I32, rows), -1, parts);
		return call;
	}

	function lower(n: Node): ShaderExpr {
		match (n.kind) {
			NodeKind.NumberLiteral => { return number(n); },
			NodeKind.BooleanLiteral => {
				return literal(scalarType(ScalarKind.Bool), n.boolValue ? 1.0 : 0.0);
			},
			NodeKind.Identifier => { return identifier(n); },
			NodeKind.BinaryExpr => { return binary(n); },
			NodeKind.UnaryExpr => {
				const op = n.unaryOp;
				if (op == "!" && kindOf(n.operand) == TypeKind.Boolean ||
					op == "~" && integer(n.operand) ||
					op == "-" && kindOf(n.operand) != TypeKind.Uint32) {
					let e = exprOf(ExprKind.Unary, looseType(getType(n)), -1, [lower(n.operand)]);
					e.unary = op == "-" ? UnaryOp.Negate : UnaryOp.Not;
					return e;
				}
				fail(n, "unary '" + op + "' has no GLSL form yet");
			},
			NodeKind.ConditionalExpr => {
				if (kindOf(n.ternaryCondition) != TypeKind.Boolean) {
					fail(n, "a shader condition is a boolean");
				}
				const test = lower(n.ternaryCondition);
				const yes = lower(n.ternaryConsequent);
				const no = lower(n.ternaryAlternate);
				return exprOf(ExprKind.Conditional, looseType(getType(n)), -1, [test, yes, no]);
			},
			NodeKind.ArrayAccess => {
				const array = lower(matrixColumns(n.array) ? n.array.object : n.array);
				const index = lower(n.index);
				return exprOf(ExprKind.Index, looseType(getType(n)), -1, [array, index]);
			},
			NodeKind.ArrayLiteral => {
				let elements: ShaderExpr[] = [];
				for (const e of n.elements) { elements.push(lower(e)); }
				return exprOf(ExprKind.Construct, valueType(getType(n), n), -1, elements);
			},
			NodeKind.TypeAssertion => {
				const from = kindOf(n.asExpr);
				const to = kindOf(n);
				const exact = (from == TypeKind.Float32 || from == TypeKind.Int32) &&
					(to == TypeKind.Float32 || to == TypeKind.Int32) ||
					from == TypeKind.Uint32 && to == TypeKind.Float32;
				if (exact) {
					const type = glslType(getType(n), n);
					return exprOf(ExprKind.Convert, type, -1, [lower(n.asExpr)]);
				}
				if (to == TypeKind.Uint32 && n.asExpr.kind == NodeKind.NumberLiteral &&
					from != TypeKind.Float32 && from != TypeKind.Float64 &&
					intValue(n.asExpr) >= 0) {
					return exprOf(ExprKind.Convert, scalarType(ScalarKind.U32), -1,
						[literal(scalarType(ScalarKind.I32), intValue(n.asExpr) as float64)]);
				}
				fail(n, "'as' converts float32 and int32 both ways, uint32 to float32 and a " +
					"non-negative literal to uint32 in a shader; int32 and uint32 convert by " +
					"their bits through vec2i/vec2u");
			},
			NodeKind.MemberExpr => {
				const object = n.object;
				if (isType(object, inputType)) {
					const b = builtinInputNames.indexOf(n.property);
					const io = b >= 0 ? builtinInputIos[b] :
						inputIos[inputNames.indexOf(n.property)];
					if (b < 0) { use(ioRead, io, n); }
					return exprOf(ExprKind.Io, m.ios[io].type, io, []);
				}
				if (isType(object, bindingsType)) {
					if (isAuthorStruct(getType(n))) {
						fail(n, "uniform block '" + n.property +
							"' is read one member at a time: GLSL declares the block's members, " +
							"not a value of the block");
					}
					const r = resourceNamed(n.property);
					use(resourceRead, r, n);
					return exprOf(ExprKind.Resource, m.resources[r].type, r, []);
				}
				if (object.kind == NodeKind.MemberExpr && isType(object.object, bindingsType)) {
					const r = resourceNamed(object.property);
					use(resourceRead, r, n);
					if (m.resources[r].kind == ResourceKind.StorageBuffer &&
						n.property == "length") {
						return intrinsicOf(Intrinsic.ArrayLength, looseType(getType(n)),
							[exprOf(ExprKind.Resource, m.resources[r].type, r, [])]);
					}
					if (m.resources[r].kind != ResourceKind.UniformBlock) {
						fail(n, "'" + n.property + "' has no GLSL form yet");
					}
					const members = m.structs[m.resources[r].type.structIndex].members;
					let at = -1;
					for (let k = 0; k < members.length; k++) {
						if (members[k].name == n.property) { at = k; }
					}
					let e = exprOf(ExprKind.BlockMember, members[at].type, r, []);
					e.member = at as int32;
					return e;
				}
				if (isType(object, keyType)) {
					fail(n, "a program key feature is read only as an if condition");
				}
				if (matrixColumns(n)) {
					fail(n, "a matrix's columns are read one at a time, as m.columns[i]: GLSL " +
						"has no array of a matrix's columns");
				}
				return memberOf(lower(object), n);
			},
			NodeKind.ObjectLiteral => { return construction(n); },
			NodeKind.CallExpr => {
				const callee = n.callee;
				const impl = getImpl(callee);
				if (callee.resolvedSym == null || impl == null ||
					impl.kind != NodeKind.FunctionDecl) {
					fail(n, "a shader calls only functions");
				}
				if (callee.resolvedSym.modulePath != stdModule) { return call(n, callee, impl); }
				if (callee.kind == NodeKind.MemberExpr) {
					if (!impl.fnName.startsWith("get_")) {
						fail(n, "method calls have no GLSL form yet");
					}
					return swizzleOf(lower(callee.object), impl.fnName.replace("get_", ""), n,
						looseType(getType(n)));
				}
				return builtinCall(n, impl.fnName);
			},
			_ => {},
		}
		fail(n, "this expression has no GLSL form yet (node kind " + String(n.kind) + ")");
	}

	function resourceNamed(name: string): int32 {
		for (let r = 0; r < m.resources.length; r++) {
			if (m.resources[r].name == name) { return r as int32; }
		}
		return -1;
	}

	function output(name: string, value: Node): ShaderStmt {
		const o = outputNames.indexOf(name);
		const io = outputIos[o];
		const gate = outputFeatures[o];
		const gated = gate.kind != ConditionKind.Always;
		if (gated) { features.push(gate); }
		const write = assignOf(exprOf(ExprKind.Io, m.ios[io].type, io, []), lower(value));
		if (!gated) { return write; }
		features.pop();
		return featureIf(gate, [write]);
	}

	function writableStorage(target: Node): ShaderExpr | null {
		if (target.kind != NodeKind.MemberExpr || !isType(target.object, bindingsType)) {
			return null;
		}
		const r = resourceNamed(target.property);
		if (r < 0 || m.resources[r].kind != ResourceKind.StorageBuffer) { return null; }
		if (m.resources[r].access != Access.ReadWrite) {
			fail(target, "storage buffer '" + target.property + "' is read-only: declare it " +
				"@access(read_write) to write it, as WGSL's");
		}
		use(resourceRead, r, target);
		return exprOf(ExprKind.Resource, m.resources[r].type, r, []);
	}

	function assignee(target: Node, n: Node): ShaderExpr {
		const storage = writableStorage(target);
		if (storage != null) { return storage; }
		if (target.kind == NodeKind.Identifier &&
			(locals.includes(target.name) || workgroupOf(target) >= 0)) {
			return identifier(target);
		}
		if (target.kind == NodeKind.MemberExpr) {
			return memberOf(assignee(target.object, n), target);
		}
		if (target.kind == NodeKind.ArrayAccess) {
			const array = matrixColumns(target.array) ? target.array.object : target.array;
			const object = assignee(array, n);
			const index = lower(target.index);
			return exprOf(ExprKind.Index, looseType(getType(target)), -1, [object, index]);
		}
		fail(n, "a shader assigns only to its own locals, their fields and their elements");
	}

	function assignment(n: Node): ShaderStmt {
		const target = n.kind == NodeKind.UpdateExpr ? n.updateArg : n.left;
		const goal = assignee(target, n);
		if (n.kind == NodeKind.UpdateExpr) {
			let s = assignOf(goal, new ShaderExpr());
			s.assign = n.updateOp == "++" ? AssignOp.Increment : AssignOp.Decrement;
			return s;
		}
		if (n.operator == "/=" && integer(target)) {
			fail(n, "'/=' has no GLSL form: GLSL does not truncate as MetaScript does");
		}
		if (n.operator == "%=" && !unsigned(n)) {
			fail(n, "'%=' has a GLSL form for uint32 operands only: GLSL leaves a negative " +
				"int32 operand undefined and has no float '%'");
		}
		const operators = ["=", "+=", "-=", "*=", "/=", "%="];
		const ops = [AssignOp.Set, AssignOp.Add, AssignOp.Sub, AssignOp.Mul, AssignOp.Div,
			AssignOp.Mod];
		const at = operators.indexOf(n.operator);
		if (at < 0) {
			fail(n, "operator '" + n.operator + "' has no GLSL form yet");
		}
		let s = assignOf(goal, lower(n.right));
		s.assign = ops[at];
		return s;
	}

	function stdFunctionName(callee: Node): string {
		const impl = getImpl(callee);
		const inStd = callee.resolvedSym != null && callee.resolvedSym.modulePath == stdModule;
		return inStd && impl != null ? impl.fnName : "";
	}

	function simple(n: Node, alone: boolean): ShaderStmt {
		if (n.kind == NodeKind.ExprStmt) {
			const e = n.expr;
			if (e.kind == NodeKind.CallExpr && stdFunctionName(e.callee) == "discard") {
				return stmtOf(StmtKind.Discard, new ShaderExpr(), []);
			}
			if (e.kind == NodeKind.CallExpr && (typeKind(getType(e)) == TypeKind.Void ||
				stdFunctionName(e.callee).startsWith("atomic"))) {
				return stmtOf(StmtKind.Call, lower(e), []);
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
		uniformLoadSite = alone ? n.initializer : null;
		const value = lower(n.initializer);
		let s = stmtOf(StmtKind.Let, value, []);
		locals.push(n.declName);
		s.local = local(n, type, value);
		return s;
	}

	function lowerBody(n: Node): ShaderStmt[] {
		return lowerBlock(n.kind == NodeKind.BlockStmt ? n.statements : [n]);
	}

	function lowerBlock(statements: Node[]): ShaderStmt[] {
		const outer = locals.length;
		let out: ShaderStmt[] = [];
		for (const s of statements) {
			for (const lowered of lowerStmt(s)) { out.push(lowered); }
		}
		while (locals.length > outer) { locals.pop(); }
		return out;
	}

	function loopBody(n: Node): ShaderStmt[] {
		breakOwners.push("loop");
		const lowered = lowerBody(n);
		breakOwners.pop();
		return lowered;
	}

	function caseLabel(test: Node): ShaderExpr {
		const isLiteral = test.kind == NodeKind.NumberLiteral || test.kind == NodeKind.UnaryExpr &&
			test.unaryOp == "-" && test.operand.kind == NodeKind.NumberLiteral;
		const label = lower(test);
		if (!integer(test) || !isLiteral &&
			!(test.kind == NodeKind.Identifier && label.kind == ExprKind.Constant)) {
			fail(test, "a case is an integer literal or module constant: GLSL takes a " +
				"constant expression");
		}
		return label;
	}

	function caseBody(statements: Node[], owner: string): ShaderStmt[] {
		let kept = statements.slice(0);
		while (owner == "switch" && kept.length > 0 &&
			kept[kept.length - 1].kind == NodeKind.BreakStmt &&
			kept[kept.length - 1].breakLabel == "") {
			kept.pop();
		}
		breakOwners.push(owner);
		const lowered = lowerBlock(kept);
		breakOwners.pop();
		return lowered;
	}

	function choice(n: Node): ShaderStmt {
		const isMatch = n.kind == NodeKind.MatchExpr;
		const scrutinee = isMatch ? n.matchDisc : n.switchDisc;
		if (!integer(scrutinee)) { fail(n, "a shader switch or match takes an int32 or uint32"); }
		let s = stmtOf(StmtKind.Switch, lower(scrutinee), []);
		const cases: Node[] = isMatch ? n.matchCases : n.switchCases;
		for (const c of cases) {
			let k = new ShaderCase();
			let statements: Node[] = [];
			if (isMatch) {
				if (c.caseGuard != null) {
					fail(c, "a match arm with 'when' has no GLSL switch form; write an if");
				}
				for (const p of c.casePatterns) {
					if (p.kind == NodeKind.Identifier && p.name == "_") {
						k.isDefault = true;
					} else {
						k.labels.push(caseLabel(p));
					}
				}
				const arm = c.caseBody;
				statements = arm.kind == NodeKind.BlockStmt ? arm.statements :
					[{ kind: NodeKind.ExprStmt, line: arm.line, column: arm.column, expr: arm }];
			} else {
				k.isDefault = c.isDefault;
				for (const t of c.caseTests) { k.labels.push(caseLabel(t)); }
				statements = c.caseStmts;
			}
			k.body = caseBody(statements, isMatch ? "match" : "switch");
			s.cases.push(k);
		}
		return s;
	}

	function branches(n: Node): ShaderStmt {
		let s = stmtOf(StmtKind.If, condition(n.condition), lowerBody(n.consequent));
		const other = n.alternate;
		if (other == null || other.kind == NodeKind.BlockStmt && other.statements.length == 0) {
			return s;
		}
		if (other.kind == NodeKind.IfStmt) {
			s.otherwise = [branches(other)];
		} else if (other.kind == NodeKind.BlockStmt) {
			s.otherwise = [stmtOf(StmtKind.Block, new ShaderExpr(), lowerBody(other))];
		} else {
			s.otherwise = lowerBody(other);
		}
		return s;
	}

	function returned(n: Node): ShaderStmt[] {
		const result = n.argument;
		if (inHelper) {
			if (result == null) { fail(n, "a shader function returns a value"); }
			return [stmtOf(StmtKind.Return, lower(result), [])];
		}
		if (noOutput && result == null) { return [stmtOf(StmtKind.Return, new ShaderExpr(), [])]; }
		if (result == null) { fail(n, "an entry returns its stage output"); }
		if (outputs == null) { return [stmtOf(StmtKind.Return, lower(result), [])]; }
		if (result.kind != NodeKind.ObjectLiteral) {
			fail(n, "a struct stage output is returned as an object literal");
		}
		let out: ShaderStmt[] = [];
		for (let k = 0; k < result.keys.length; k++) {
			out.push(output(result.keys[k], result.properties[k]));
		}
		out.push(stmtOf(StmtKind.Return, new ShaderExpr(), []));
		return out;
	}

	function lowerStmt(n: Node): ShaderStmt[] {
		match (n.kind) {
			NodeKind.BlockStmt => {
				return [stmtOf(StmtKind.Block, new ShaderExpr(), lowerBody(n))];
			},
			NodeKind.IfStmt => {
				const gate = featureOf(n.condition);
				if (gate == null) { return [branches(n)]; }
				features.push(gate);
				let s = featureIf(gate, lowerBody(n.consequent));
				features.pop();
				if (n.alternate != null) {
					features.push(negated(gate));
					s.otherwise = lowerBody(n.alternate);
					features.pop();
				}
				return [s];
			},
			NodeKind.WhileStmt => {
				if (n.whileLabel != "") { fail(n, "GLSL has no labelled loops"); }
				const test = condition(n.whileCondition);
				return [stmtOf(StmtKind.While, test, loopBody(n.whileBody))];
			},
			NodeKind.ForStmt => {
				if (n.forLabel != "") { fail(n, "GLSL has no labelled loops"); }
				const outer = locals.length;
				const init = simple(n.forInit, false);
				const test = condition(n.forCondition);
				const update = assignment(n.forUpdate);
				let s = stmtOf(StmtKind.For, test, loopBody(n.forBody));
				s.init = [init];
				s.update = [update];
				while (locals.length > outer) { locals.pop(); }
				return [s];
			},
			NodeKind.BreakStmt | NodeKind.ContinueStmt => {
				const label = n.kind == NodeKind.BreakStmt ? n.breakLabel : n.continueLabel;
				if (label != "") { fail(n, "GLSL has no labelled loops"); }
				if (n.kind == NodeKind.BreakStmt && breakOwners.length > 0 &&
					breakOwners[breakOwners.length - 1] == "match") {
					fail(n, "a break in a match arm leaves the loop or switch around the match, " +
						"and in the GLSL switch it would leave only the match; write an if");
				}
				const kind = n.kind == NodeKind.BreakStmt ? StmtKind.Break : StmtKind.Continue;
				return [stmtOf(kind, new ShaderExpr(), [])];
			},
			NodeKind.SwitchStmt => { return [choice(n)]; },
			NodeKind.ExprStmt => {
				if (n.expr.kind == NodeKind.MatchExpr) { return [choice(n.expr)]; }
			},
			NodeKind.ReturnStmt => { return returned(n); },
			_ => {},
		}
		return [simple(n, true)];
	}

	if (feederType != null && feederType.kind == NodeKind.TypeFunction) {
		const fedOutputs = fieldsOf(feederType.typExprReturn);
		const feedsFragments = fedOutputs != null && hasPosition(fedOutputs);
		for (const t of feedsFragments ? feederType.typExprParams : []) {
			const fields = fieldsOf(t);
			if (fields == null || hasDecorator(fields, "binding") ||
				fields.typExprFieldNames.length > 0 && everyDecorated(fields, "feature")) {
				continue;
			}
			for (let f = 0; f < fields.typExprFieldNames.length; f++) {
				if (decorator(fields.typExprFieldDecorators[f], "builtin") == null) {
					attributeNames.push(fields.typExprFieldNames[f]);
					if (!vertex) {
						addIo(ShaderStage.Vertex, fields.typExprFieldNames[f], IoDirection.In,
							looseType(fields.typExprFieldTypes[f]), Builtin.None,
							new FeatureCondition());
					}
				}
			}
		}
	}

	if (inputs != null) {
		for (let f = 0; f < inputs.typExprFieldNames.length; f++) {
			const name = inputs.typExprFieldNames[f];
			const t = inputs.typExprFieldTypes[f];
			const site = fieldSite(inputs.typExprFieldDecorators[f]);
			const builtin = decorator(inputs.typExprFieldDecorators[f], "builtin");
			if (builtin == null) {
				if (t.kind == NodeKind.TypeArray) {
					fail(site, vertex ? "attribute '" + name + "' is an array, which neither " +
						"WGSL nor GLSL ES 3.00 takes as a vertex input: " +
						"declare one attribute each" : arrayVarying(name));
				}
				const spelled = vertex ? name : varyingName(name);
				const type = member(t, spelled, site);
				const gate = featureCondition(inputs.typExprFieldDecorators[f]);
				if (vertex) {
					noInterpolate(inputs.typExprFieldDecorators[f], "a vertex attribute");
				}
				const interpolation = vertex ? Interpolation.Perspective :
					interpolationOf(t, site, inputs.typExprFieldDecorators[f]);
				claim(spelled, site);
				const io = addIo(stage, name, IoDirection.In, type, Builtin.None, gate);
				m.ios[io].interpolation = interpolation;
				m.ios[io].sampling = vertex ? Sampling.Center :
					samplingOf(inputs.typExprFieldDecorators[f]);
				inputNames.push(name);
				inputIos.push(io);
				continue;
			}
			noInterpolate(inputs.typExprFieldDecorators[f], "a builtin");
			const which = argumentName(builtin);
			const computeAt = computeBuiltins.indexOf(which);
			const kind = compute ? (computeAt >= 0 ? computeKinds[computeAt] : Builtin.None) :
				vertex ? (which == "vertexIndex" ? Builtin.VertexIndex :
					which == "instanceIndex" ? Builtin.InstanceIndex : Builtin.None) :
				which == "position" ? Builtin.Position :
				which == "frontFacing" ? Builtin.FrontFacing :
				which == "primitiveIndex" ? Builtin.PrimitiveIndex : Builtin.None;
			if (kind == Builtin.None) {
				fail(builtin, "input field '" + name + "': @builtin(" + which + ") " +
					(which == "primitiveIndex" ? "is read in a fragment entry, as WGSL's is" :
					"has no GLSL form yet"));
			}
			builtinInputNames.push(name);
			builtinInputIos.push(addIo(stage, name, IoDirection.In, looseType(t), kind,
				new FeatureCondition()));
		}
	}

	if (compute && !noOutput) { fail(fn, "a compute entry returns nothing"); }
	if (noOutput) {
		if (vertex) { fail(fn, "a vertex entry returns its outputs"); }
	} else if (outputs == null) {
		const colour = glslType(outputType, fn);
		claim("fragColor", fn);
		const io = addIo(stage, "fragColor", IoDirection.Out, colour, Builtin.None,
			new FeatureCondition());
		m.ios[io].location = 0;
	} else {
		for (let f = 0; f < outputs.typExprFieldNames.length; f++) {
			const name = outputs.typExprFieldNames[f];
			const decorators = outputs.typExprFieldDecorators[f];
			const site = fieldSite(decorators);
			const gate = featureCondition(decorators);
			outputNames.push(name);
			outputFeatures.push(gate);
			const builtin = decorator(decorators, "builtin");
			const t = outputs.typExprFieldTypes[f];
			if (builtin != null) {
				noInterpolate(decorators, "a builtin");
				const which = argumentName(builtin);
				if (vertex ? which != "position" : which != "fragDepth") {
					fail(builtin, "output field '" + name + "': a vertex entry writes " +
						"@builtin(position), a fragment entry @builtin(fragDepth)");
				}
				const kind = vertex ? Builtin.Position : Builtin.FragDepth;
				outputIos.push(addIo(stage, name, IoDirection.Out, looseType(t), kind, gate));
				continue;
			}
			if (vertex) {
				if (t.kind == NodeKind.TypeArray) { fail(site, arrayVarying(name)); }
				const spelled = varyingName(name);
				const type = member(t, spelled, site);
				const interpolation = interpolationOf(t, site, decorators);
				claim(spelled, site);
				const io = addIo(stage, name, IoDirection.Out, type, Builtin.None, gate);
				m.ios[io].interpolation = interpolation;
				m.ios[io].sampling = samplingOf(decorators);
				outputIos.push(io);
				continue;
			}
			noInterpolate(decorators, "a fragment output");
			const location = decorator(decorators, "location");
			if (location == null) {
				fail(site, "fragment output '" + name + "' has no @location(n)");
			}
			const slot = argumentNumber(location);
			if (t.kind == NodeKind.TypeArray) {
				fail(site, "fragment output '" + name + "' is an array, which WGSL does not " +
					"write: declare one output each at its @location");
			}
			const type = member(t, name, site);
			claim(name, site);
			const io = addIo(stage, name, IoDirection.Out, type, Builtin.None, gate);
			m.ios[io].location = slot;
			outputIos.push(io);
		}
	}

	gather(fn.fnBody, entry.resolvedSym.modulePath, [], null);
	let main = new ShaderFunction();
	main.name = fn.fnName;
	const mainIndex = addFunction(main);
	enterScope(entry.resolvedSym.modulePath, main);
	main.body = lowerBody(fn.fnBody);
	if (m.workgroups.length > 0) { main.body = zeroedWorkgroups(main).concat(main.body); }
	for (let s = 0; s < storageResources.length; s++) {
		const element = storageElements[s];
		if (!isAuthorStruct(element)) {
			fail(storageSites[s], "storage buffer '" + m.resources[storageResources[s]].name +
				"' holds no author struct: a storage buffer is one flexible array of structs");
		}
		m.resources[storageResources[s]].type.element[0].structIndex =
			structIndex(element, storageSites[s]);
	}
	for (let r = 0; r < m.resources.length; r++) {
		m.resources[r].condition = declarationCondition(resourceContexts[r]);
	}
	for (let f = 0; f < m.functions.length; f++) {
		if (f != mainIndex) {
			m.functions[f].condition = declarationCondition(functionContexts[f]);
		}
	}
	let stageEntry = new ShaderEntry();
	stageEntry.name = fn.fnName;
	stageEntry.stage = stage;
	stageEntry.functionIndex = mainIndex;
	if (compute) {
		for (let a = 0; a < 3; a++) {
			const n = a < workgroupSize.elements.length ? workgroupSize.elements[a] : null;
			if (n != null && n.kind != NodeKind.NumberLiteral) {
				fail(workgroupSize, "a workgroup size is three numbers");
			}
			stageEntry.workgroupSize[a] = n == null ? 1 : intValue(n) as int32;
		}
	}
	m.entries.push(stageEntry);
	const broken = irErrors(m);
	if (broken.length > 0) {
		fail(entry, "internal: the lowered module breaks the IR: " + broken[0]);
	}
	const formName = form.kind == NodeKind.StringLiteral ? (form as StringLiteralData).value : "";
	if (formName != "glsl" && formName != "ir") {
		fail(form, "internal: the stage form is \"glsl\" or \"ir\"");
	}
	return { kind: NodeKind.StringLiteral, line: entry.line, column: entry.column,
		value: formName == "ir" ? irText(m) : printGlsl450(m) };
}
