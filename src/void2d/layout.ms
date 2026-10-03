import { NodeRef } from "./node";
import { layoutPass as runLayoutPass, freeLayoutTree } from "../../../yoga/src/index";

export function layoutPass(root: NodeRef, availableWidth: float32, availableHeight: float32): void {
	runLayoutPass(root, availableWidth, availableHeight);
}

export function freeLayout(root: NodeRef): void {
	freeLayoutTree(root);
}
