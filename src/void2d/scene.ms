// Void 2D Scene — functional take on h2d.Scene: a root container (Object) + the render
// entry that owns the GPU pass. Heaps: `s2d.addChild(o); s2d.render(engine)`.
// Here: `const s = scene(clear); s.add(o); s.present();` — extension methods, no OOP.

import { Node2D, group, addChild, render } from "./node";
import { begin2d, end2d } from "./draw";
import { Color, identity2d } from "./types";
import { beginPass, endPass, commit, fbWidth, fbHeight } from "../sokol/gpu";

export interface Scene {
	root: Node2D;
	clear: Color;
}

export function scene(clear: Color): Scene {
	return { root: group(), clear: clear };
}

export function add(this s: Scene, c: Node2D): Node2D {
	return s.root.addChild(c);
}

// One frame: clear + walk the scene + flush. Owns the swapchain pass (≈ h2d.Scene.render).
export function present(this s: Scene): void {
	beginPass(s.clear.r, s.clear.g, s.clear.b, s.clear.a);
	begin2d(fbWidth(), fbHeight());
	s.root.render(identity2d(), 1.0);
	end2d();
	endPass();
	commit();
}
