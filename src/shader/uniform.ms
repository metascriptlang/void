// A uniform block written from a value of the struct the shader declares it with. The offsets come
// from layout.ms over the same members the shader lowering builds (emit.ms uniformBlockOf), so a host
// write and the block a shader reads cannot disagree; every lane the fields leave open is stored as
// zero, because a pooled buffer is reused without a clear.

import {
	ArrayAccessData,
	MemberExprData,
	Node,
	NodeKind,
	TypeObjectData,
	createNodeAt,
	error,
	getType,
	getTypeArg,
	getTypeImpl,
	sameType,
} from "std/meta";
import { ShaderTypeRegistry, uniformBlockOf } from "./emit";
import { ShaderModule, ShaderType, ShaderTypeKind } from "./ir";
import { columnStride, uniformArrayStride, uniformBlockLayout } from "./layout";

function component(k: int32): string {
	return "xyzw".slice(k, k + 1);
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

class Stores {
	out: Node[] = [];
	covered: boolean[] = [];
}

function store(s: Stores, values: Node, at: Node, floatIndex: int32, value: Node): void {
	const slot: Node = createNodeAt(NodeKind.BinaryExpr, { operator: "+", left: at, right: integer(floatIndex, at) }, at.location);
	const target: Node = createNodeAt(NodeKind.ArrayAccess, { array: values, index: slot }, values.location);
	const assign: Node = createNodeAt(NodeKind.BinaryExpr, { operator: "=", left: target, right: value }, values.location);
	s.out.push(createNodeAt(NodeKind.ExprStmt, { expr: assign }, values.location));
	s.covered[floatIndex] = true;
}

function storeVector(s: Stores, values: Node, at: Node, floatIndex: int32, rows: int32, value: Node): void {
	for (let k = 0; k < rows; k += 1) { store(s, values, at, floatIndex + k, member(value, component(k))); }
}

function storeMember(s: Stores, m: ShaderModule, values: Node, at: Node, floatIndex: int32,
	t: ShaderType, value: Node): void {
	if (t.kind == ShaderTypeKind.Scalar) {
		store(s, values, at, floatIndex, value);
	} else if (t.kind == ShaderTypeKind.Vector) {
		storeVector(s, values, at, floatIndex, t.rows, value);
	} else if (t.kind == ShaderTypeKind.Matrix) {
		for (let c = 0; c < t.columns; c += 1) {
			storeVector(s, values, at, floatIndex + c * columnStride(t.rows) / 4, t.rows, index(member(value, "columns"), c));
		}
	} else if (t.kind == ShaderTypeKind.Array) {
		for (let i = 0; i < t.length; i += 1) {
			storeMember(s, m, values, at, floatIndex + i * uniformArrayStride(m, t) / 4, t.element[0], index(value, i));
		}
	} else {
		throw new Error("writeUniform: unreachable member kind " + t.kind.toString());
	}
}

// Each lane is read from `value` by field path, so the buffer, the offset and the value are names,
// never calls: a call would run once per lane.
export macro writeUniform(values: Node, at: Node, value: Node): Node {
	const type = getTypeArg();
	const name = (getTypeImpl(type) as TypeObjectData).typExprTypeName;
	function fail(n: Node, msg: string): never {
		error("writeUniform<" + name + ">: " + msg, n);
	}
	function requireBound(n: Node, what: string): void {
		if (!isPath(n)) {
			fail(n, "the " + what + " is a name or a field path, bound before the call");
		}
	}
	const block = uniformBlockOf(getTypeImpl(ShaderTypeRegistry)!, type);
	if (!block.ok) { fail(type, block.error); }
	const m = block.value;
	const layout = uniformBlockLayout(m, 0);
	if (!layout.ok) { fail(type, layout.error); }
	requireBound(values, "buffer");
	if (at.kind != NodeKind.NumberLiteral) { requireBound(at, "offset"); }
	requireBound(value, "value");
	if (!sameType(getType(value), type)) { fail(value, "the value is not a " + name); }
	let s = new Stores();
	for (let i = 0; i < layout.value.size / 4; i += 1) { s.covered.push(false); }
	const members = m.structs[0].members;
	for (let i = 0; i < members.length; i += 1) {
		storeMember(s, m, values, at, layout.value.offsets[i] / 4, members[i].type, member(value, members[i].name));
	}
	const zero = integer(0, value);
	for (let i = 0; i < s.covered.length; i += 1) {
		if (!s.covered[i]) { store(s, values, at, i, zero); }
	}
	return createNodeAt(NodeKind.SpliceMany, { spliceNodes: s.out }, value.location);
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
