// A uniform block written by field name from the struct the shader declares it with. The offsets come
// from layout.ms over the same members the shader lowering builds (emit.ms uniformBlockOf), so a host
// write and the block a shader reads cannot disagree; every lane the fields leave open is stored as
// zero, because a pooled buffer is reused without a clear.

import {
	ArrayAccessData,
	ArrayLiteralData,
	MemberExprData,
	Node,
	NodeKind,
	ObjectLiteralData,
	SourceLocation,
	TypeArrayData,
	TypeKind,
	TypeObjectData,
	createNodeAt,
	error,
	getType,
	getTypeArg,
	getTypeImpl,
	sameType,
	typeKind,
} from "std/meta";
import { ShaderTypeRegistry, uniformBlockOf } from "./emit";
import { ShaderModule, ShaderType, ShaderTypeKind } from "./ir";
import { columnStride, uniformArrayStride, uniformBlockLayout } from "./layout";

const COMPONENTS = ["x", "y", "z", "w"];

// The store statements of one write, and the first refusal: only a macro body can call `error`, so a
// helper records where the author went wrong and the macro raises it once the walk is over.
class Stores {
	out: Node[] = [];
	covered: boolean[] = [];
	problem: string = "";
	problemAt: SourceLocation | null = null;
	problemNode: Node | null = null;
}

function refuse(s: Stores, message: string, at: SourceLocation): void {
	if (s.problem == "") {
		s.problem = message;
		s.problemAt = at;
	}
}

function refuseAt(s: Stores, message: string, at: Node): void {
	if (s.problem == "") {
		s.problem = message;
		s.problemNode = at;
	}
}

function integer(value: int32, at: Node): Node {
	return createNodeAt(NodeKind.NumberLiteral, {
		value: value as number, isFloat: false, intVal: value as int64,
		outOfRangeText: "", isBitPattern: false,
	}, at.location);
}

function member(value: Node, name: string): Node {
	return createNodeAt(NodeKind.MemberExpr, { object: value, property: name, isOptional: false }, value.location);
}

function index(value: Node, i: int32): Node {
	return createNodeAt(NodeKind.ArrayAccess, { array: value, index: integer(i, value) }, value.location);
}

function isPath(n: Node): boolean {
	if (n.kind == NodeKind.Identifier) { return true; }
	if (n.kind == NodeKind.ArrayAccess) {
		const access = n as ArrayAccessData;
		return isPath(access.array) && (access.index.kind == NodeKind.NumberLiteral || isPath(access.index));
	}
	return n.kind == NodeKind.MemberExpr && isPath((n as MemberExprData).object);
}

// The store repeats the buffer and the offset once per lane, so each is a name, never a call.
function requirePath(s: Stores, n: Node, what: string): void {
	if (!isPath(n)) { refuseAt(s, "writeUniform: " + what + " is a name or a field path, bound before the call", n); }
}

function store(s: Stores, values: Node, at: Node, floatIndex: int32, value: Node): void {
	const slot: Node = createNodeAt(NodeKind.BinaryExpr, { operator: "+", left: at, right: integer(floatIndex, at) }, at.location);
	const target: Node = createNodeAt(NodeKind.ArrayAccess, { array: values, index: slot }, values.location);
	const cast: Node = createNodeAt(NodeKind.TypeAssertion, { asExpr: value, asType: "float32" }, value.location);
	const assign: Node = createNodeAt(NodeKind.BinaryExpr, { operator: "=", left: target, right: cast }, values.location);
	s.out.push(createNodeAt(NodeKind.ExprStmt, { expr: assign }, values.location));
	s.covered[floatIndex] = true;
}

// A number literal is a float32 as written; any other expression is one already, or the author casts.
function requireScalar(s: Stores, value: Node, what: string): void {
	if (value.kind == NodeKind.NumberLiteral) { return; }
	const t = getType(value);
	if (t == null || typeKind(t) != TypeKind.Float32) {
		refuseAt(s, "writeUniform: " + what + " is a float32; a value of another type is cast with 'as float32'", value);
	}
}

// An author's value that is not a literal reads its lanes by field access, so it has the member's type.
function requireValue(s: Stores, value: Node, typeNode: Node, what: string): void {
	requirePath(s, value, what);
	if (s.problem == "" && !sameType(getType(value), typeNode)) {
		refuseAt(s, "writeUniform: " + what + " is not of the block member's type", value);
	}
}

// The lane values of a vector; typeNode is null for a value this macro built itself.
function vectorLanes(s: Stores, value: Node, typeNode: Node | null, rows: int32, what: string): Node[] {
	let lanes: Node[] = [];
	if (value.kind == NodeKind.ObjectLiteral) {
		const o = value as ObjectLiteralData;
		for (let i = 0; i < o.keys.length; i += 1) {
			const at = COMPONENTS.indexOf(o.keys[i]);
			if (at < 0 || at >= rows) { refuse(s, "writeUniform: " + what + " has no '" + o.keys[i] + "'", o.keyLocations[i]); }
		}
		for (let k = 0; k < rows && s.problem == ""; k += 1) {
			const at = o.keys.indexOf(COMPONENTS[k]);
			if (at < 0) {
				refuseAt(s, "writeUniform: " + what + " is missing '" + COMPONENTS[k] + "'", value);
			} else {
				requireScalar(s, o.properties[at], what + "." + COMPONENTS[k]);
				lanes.push(o.properties[at]);
			}
		}
		return lanes;
	}
	if (typeNode != null) { requireValue(s, value, typeNode, what); }
	for (let k = 0; k < rows; k += 1) { lanes.push(member(value, COMPONENTS[k])); }
	return lanes;
}

function storeVector(s: Stores, values: Node, at: Node, floatIndex: int32, rows: int32,
	value: Node, typeNode: Node | null, what: string): void {
	const lanes = vectorLanes(s, value, typeNode, rows, what);
	for (let k = 0; k < lanes.length && s.problem == ""; k += 1) { store(s, values, at, floatIndex + k, lanes[k]); }
}

function arrayItems(s: Stores, value: Node, count: int32, what: string): Node[] {
	const items = (value as ArrayLiteralData).elements;
	if (items.length != count) {
		refuseAt(s, "writeUniform: " + what + " has " + String(count) + " elements, the literal " + String(items.length), value);
		return [];
	}
	return items;
}

// The column values of a matrix: the literal's own, or a read of each column of the matrix value.
function matrixColumns(s: Stores, value: Node, typeNode: Node | null, columns: int32, what: string): Node[] {
	if (value.kind == NodeKind.ObjectLiteral) {
		const o = value as ObjectLiteralData;
		if (o.keys.length != 1 || o.keys[0] != "columns") {
			refuseAt(s, "writeUniform: " + what + " is { columns: [...] }", value);
			return [];
		}
		if (o.properties[0].kind != NodeKind.ArrayLiteral) {
			refuseAt(s, "writeUniform: " + what + ".columns is an array literal", o.properties[0]);
			return [];
		}
		return arrayItems(s, o.properties[0], columns, what + ".columns");
	}
	if (typeNode != null) { requireValue(s, value, typeNode, what); }
	let items: Node[] = [];
	for (let j = 0; j < columns; j += 1) { items.push(index(member(value, "columns"), j)); }
	return items;
}

// authored: the value and typeNode are the author's, to be checked; false for a read this macro built.
function storeMember(s: Stores, m: ShaderModule, values: Node, at: Node, floatIndex: int32,
	t: ShaderType, value: Node, typeNode: Node, authored: boolean, what: string): void {
	if (s.problem != "") { return; }
	if (t.kind == ShaderTypeKind.Scalar) {
		requireScalar(s, value, what);
		store(s, values, at, floatIndex, value);
	} else if (t.kind == ShaderTypeKind.Vector) {
		storeVector(s, values, at, floatIndex, t.rows, value, authored ? typeNode : null, what);
	} else if (t.kind == ShaderTypeKind.Matrix) {
		const columns = matrixColumns(s, value, authored ? typeNode : null, t.columns, what);
		const columnType = ((getTypeImpl(typeNode) as TypeObjectData).typExprFieldTypes[0] as TypeArrayData).typExprElement;
		const literal = value.kind == NodeKind.ObjectLiteral;
		for (let c = 0; c < columns.length; c += 1) {
			storeVector(s, values, at, floatIndex + c * columnStride(t.rows) / 4, t.rows, columns[c],
				literal ? columnType : null, what + ".columns[" + String(c) + "]");
		}
	} else if (t.kind == ShaderTypeKind.Array) {
		const elementType = (typeNode as TypeArrayData).typExprElement;
		const literal = value.kind == NodeKind.ArrayLiteral;
		let items: Node[] = [];
		if (literal) {
			items = arrayItems(s, value, t.length, what);
		} else {
			if (authored) { requireValue(s, value, typeNode, what); }
			for (let i = 0; i < t.length; i += 1) { items.push(index(value, i)); }
		}
		for (let i = 0; i < items.length; i += 1) {
			storeMember(s, m, values, at, floatIndex + i * uniformArrayStride(m, t) / 4, t.element[0], items[i],
				elementType, literal, what + "[" + String(i) + "]");
		}
	} else {
		throw new Error("writeUniform: unreachable member kind " + t.kind.toString());
	}
}

export macro writeUniform(values: Node, at: Node, literal: Node): Node {
	const type = getTypeArg();
	const fields = getTypeImpl(type) as TypeObjectData;
	const name = fields.typExprTypeName;
	const block = uniformBlockOf(getTypeImpl(ShaderTypeRegistry)!, type);
	if (!block.ok) { error("writeUniform<" + name + ">: " + block.error, type); }
	const m = block.value;
	const layout = uniformBlockLayout(m, 0);
	if (!layout.ok) { error("writeUniform<" + name + ">: " + layout.error, type); }
	if (literal.kind != NodeKind.ObjectLiteral) {
		error("writeUniform<" + name + ">: the values are an object literal of the block's fields", literal);
	}
	let s = new Stores();
	requirePath(s, values, "the buffer");
	if (at.kind != NodeKind.NumberLiteral) { requirePath(s, at, "the offset"); }
	const o = literal as ObjectLiteralData;
	const members = m.structs[0].members;
	for (let i = 0; i < o.keys.length; i += 1) {
		if (!members.some((f) => f.name == o.keys[i])) {
			error("writeUniform<" + name + ">: unknown field '" + o.keys[i] + "'", o.keyLocations[i]);
		}
	}
	for (let i = 0; i < layout.value.size / 4; i += 1) { s.covered.push(false); }
	for (let i = 0; i < members.length; i += 1) {
		const given = o.keys.indexOf(members[i].name);
		if (given < 0) { error("writeUniform<" + name + ">: field '" + members[i].name + "' is missing", literal); }
		storeMember(s, m, values, at, layout.value.offsets[i] / 4, members[i].type, o.properties[given],
			fields.typExprFieldTypes[i], true, name + "." + members[i].name);
	}
	if (s.problemNode != null) { error(s.problem, s.problemNode); }
	if (s.problem != "") { error(s.problem, s.problemAt); }
	const zero = integer(0, literal);
	for (let i = 0; i < s.covered.length; i += 1) {
		if (!s.covered[i]) { store(s, values, at, i, zero); }
	}
	return createNodeAt(NodeKind.SpliceMany, { spliceNodes: s.out }, literal.location);
}

// The block's size in bytes, as the shader's binding reflects it.
export macro uniformSize(): Node {
	const type = getTypeArg();
	const block = uniformBlockOf(getTypeImpl(ShaderTypeRegistry)!, type);
	if (!block.ok) { error("uniformSize: " + block.error, type); }
	const layout = uniformBlockLayout(block.value, 0);
	if (!layout.ok) { error("uniformSize: " + layout.error, type); }
	return integer(layout.value.size, type);
}
