// Node2D opt-in to the shared yoga layout pass (yoga/src/sync.ms protocol).
// The walker itself is generic and lives in the yoga package; this module
// only maps the protocol onto Node2D fields and keeps the old public API.
//
// A node with layoutStyle participates in layout; layoutStyle=null keeps
// manual Heaps-style positioning and is invisible to yoga. Restyle by
// assigning a FRESH FlexStyle object (reference-compared). Writing x/y/w/h
// is enough for Layer B — the render walk detects x != lastX itself
// (render.ms:79).

import { Node2D } from "./node";
import { FlexStyle, layoutPass as runLayoutPass, freeLayoutTree } from "../../../yoga/src/index";

export function layoutGetChildren(this n: Node2D): Node2D[] { return n.children; }
export function layoutGetStyle(this n: Node2D): FlexStyle | null { return n.layoutStyle; }
export function layoutGetLastStyle(this n: Node2D): FlexStyle | null { return n.lastLayoutStyle; }
export function layoutSetLastStyle(this n: Node2D, s: FlexStyle | null): void { n.lastLayoutStyle = s; }
export function layoutGetYg(this n: Node2D): Ptr<void> | null { return n.yg; }
export function layoutSetYg(this n: Node2D, yg: Ptr<void> | null): void { n.yg = yg; }
export function layoutSetFrame(this n: Node2D, x: float32, y: float32, w: float32, h: float32): void {
	n.x = x;
	n.y = y;
	n.w = w;
	n.h = h;
}

export function layoutPass(root: Node2D, availableWidth: float32, availableHeight: float32): void {
	runLayoutPass(root, availableWidth, availableHeight);
}

export function freeLayout(root: Node2D): void {
	freeLayoutTree(root);
}
