import { NodeRef } from "./node";
import { FlexStyle, YGNode, layoutPass as runLayoutPass, freeLayoutTree } from "../../../yoga/src/index";

export function layoutGetChildren(this n: NodeRef): NodeRef[] {
	const i: int32 = n.liveRow("layoutGetChildren");
	const out: NodeRef[] = [];
	for (let k: int32 = 0; k < (n.scene.children[i].length as int32); k++) {
		out.push(n.scene.refOf(n.scene.children[i][k]));
	}
	return out;
}

export function layoutGetStyle(this n: NodeRef): FlexStyle | null {
	return n.scene.layouts[n.liveRow("layoutGetStyle")].style;
}

export function layoutGetLastStyle(this n: NodeRef): FlexStyle | null {
	return n.scene.layouts[n.liveRow("layoutGetLastStyle")].lastStyle;
}

export function layoutSetLastStyle(this n: NodeRef, s: FlexStyle | null): void {
	const i: int32 = n.liveRow("layoutSetLastStyle");
	n.scene.layouts[i] = { ...n.scene.layouts[i], lastStyle: s };
}

export function layoutGetYg(this n: NodeRef): Ptr<YGNode> | null {
	return n.scene.layouts[n.liveRow("layoutGetYg")].yg;
}

export function layoutSetYg(this n: NodeRef, yg: Ptr<YGNode> | null): void {
	const i: int32 = n.liveRow("layoutSetYg");
	n.scene.layouts[i] = { ...n.scene.layouts[i], yg: yg };
}

export function layoutSetFrame(
	this n: NodeRef,
	x: float32,
	y: float32,
	w: float32,
	h: float32,
): void {
	n.setPosition(x, y).setSize(w, h);
}

export function layoutPass(root: NodeRef, availableWidth: float32, availableHeight: float32): void {
	runLayoutPass(root, availableWidth, availableHeight);
}

export function freeLayout(root: NodeRef): void {
	freeLayoutTree(root);
}
