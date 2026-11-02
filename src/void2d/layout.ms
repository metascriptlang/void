import { NodeRef } from "./node";
import { freeLayoutTreeAt, layoutPassAt } from "../../../yoga/src/index";

// pointScale is device pixels per point: boxes round to that pixel grid, as React Native passes the screen scale.
export function layoutPass(
	root: NodeRef,
	availableWidth: float32,
	availableHeight: float32,
	pointScale: float32 = 1.0,
): void {
	layoutPassAt(root, availableWidth, availableHeight, "ltr", pointScale);
}

export function freeLayout(root: NodeRef): void {
	freeLayoutTreeAt(root);
}
