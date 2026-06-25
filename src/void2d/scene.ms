// Void 2D Scene — functional take on h2d.Scene: a root container (Object) + the render
// entry that owns the GPU pass. Heaps: `s2d.addChild(o); s2d.render(engine)`.
// Here: `const s = scene(clear); s.add(o); s.present();` — extension methods, no OOP.

import { Node2D, group, addChild, render, update } from "./node";
import { begin2d, end2d } from "./draw";
import { Color, Camera, camera, viewMatrix } from "./types";
import { beginPass, endPass, commit, fbWidth, fbHeight } from "../sokol/gpu";

export interface Scene {
	root: Node2D;
	clear: Color;
	cam: Camera;
}

export function scene(clear: Color): Scene {
	return { root: group(), clear: clear, cam: camera() };
}

export function add(this s: Scene, c: Node2D): Node2D {
	return s.root.addChild(c);
}

// Advance time-based state (Anim) before present. dt in seconds.
export function tick(this s: Scene, dt: float32): void {
	s.root.update(dt);
}

// One frame: clear + walk the scene through the camera + flush. Owns the swapchain pass.
export function present(this s: Scene): void {
	const w: int32 = fbWidth();
	const h: int32 = fbHeight();
	beginPass(s.clear.r, s.clear.g, s.clear.b, s.clear.a);
	begin2d(w, h);
	s.root.render(s.cam.viewMatrix(w as float32, h as float32), 1.0);
	end2d();
	endPass();
	commit();
}
