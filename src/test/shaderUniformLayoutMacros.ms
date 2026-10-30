import { Node, NodeKind, createNodeAt, error, getTypeArg, getTypeImpl } from "std/meta";
import { ShaderTypeRegistry, uniformBlockOf } from "../shader/emit";
import { ScalarKind, ShaderModule, ShaderType, ShaderTypeKind } from "../shader/ir";
import { uniformBlockLayout } from "../shader/layout";

function shapeText(t: ShaderType): string {
	if (t.kind == ShaderTypeKind.Array) { return "[" + shapeText(t.element[0]) + "; " + String(t.length) + "]"; }
	const scalar = t.scalar == ScalarKind.F32 ? "f32" : t.scalar == ScalarKind.I32 ? "i32" :
		t.scalar == ScalarKind.U32 ? "u32" : "bool";
	if (t.kind == ShaderTypeKind.Scalar) { return scalar; }
	if (t.kind == ShaderTypeKind.Vector) { return scalar + "x" + String(t.rows); }
	if (t.kind == ShaderTypeKind.Matrix) { return "mat" + String(t.columns) + "x" + String(t.rows); }
	throw new Error("shapeText: a uniform member is a scalar, vector, matrix or array of them");
}

export function layoutText(m: ShaderModule, resource: int32): string {
	const layout = uniformBlockLayout(m, resource);
	if (!layout.ok) { return layout.error; }
	const members = m.structs[m.resources[resource].type.structIndex].members;
	let text = "";
	for (let i = 0; i < members.length; i++) {
		text += members[i].name + ":" + shapeText(members[i].type) + "@" + String(layout.value.offsets[i]) + "; ";
	}
	return text + "size " + String(layout.value.size);
}

export macro uniformLayoutText(): Node {
	const type = getTypeArg();
	const block = uniformBlockOf(getTypeImpl(ShaderTypeRegistry)!, type);
	if (!block.ok) { error(block.error, type); }
	return createNodeAt(NodeKind.StringLiteral, { value: layoutText(block.value, 0) }, type.location);
}
