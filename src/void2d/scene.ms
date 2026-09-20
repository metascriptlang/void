// Void 2D Scene — functional take on h2d.Scene: a root container (Object) + the render
// entry that owns the GPU pass. Heaps: `s2d.addChild(o); s2d.render(engine)`.
// Here: `const s = scene(clear); s.add(o); s.present();` — extension methods, no OOP.

import { Node2D, group, addChild, update } from "./node";
import { sync, draw, releaseTargets } from "./render";
import { begin2d, end2d, flushTargets, frameEnd, setSceneSmooth } from "./draw";
import { Color, Camera, Transform2D, ScaleMode, camera, viewMatrix, identity2d, trs2d } from "./types";
import { beginPass, endPass, commit, fbWidth, fbHeight, dpiScale } from "../sokol/gpu";

export interface Scene {
	root: Node2D;
	clear: Color;
	cam: Camera;
	scaleMode: ScaleMode;
	designW: float32;
	designH: float32;
	viewMat: Transform2D;
	viewInit: boolean;
	// What a node's `Smooth.Inherit` resolves to. h2d keeps this on the render context and
	// defaults it to nearest (`h2d/RenderContext.hx:52`); HEAPS.md "Do not copy from h2d"
	// rejects that default, because scaled UI and text are the common case here, not pixel
	// art. A pixel-art scene sets it false once instead of tagging every node.
	defaultSmooth: boolean;
}

export function scene(clear: Color): Scene {
	return {
		root: group(), clear: clear, cam: camera(),
		scaleMode: ScaleMode.Resize, designW: 0.0, designH: 0.0,
		viewMat: identity2d(), viewInit: false, defaultSmooth: true
	};
}

export function add(this s: Scene, c: Node2D): Node2D {
	return s.root.addChild(c);
}

export function setScaleMode(this s: Scene, mode: ScaleMode, designW: float32, designH: float32): void {
	s.scaleMode = mode;
	s.designW = designW;
	s.designH = designH;
}

export function tick(this s: Scene, dt: float32): void {
	s.root.update(dt);
}

export function sceneViewMatrix(s: Scene, wf: float32, hf: float32): Transform2D {
	if (s.scaleMode === ScaleMode.Resize || s.designW <= 0.0 || s.designH <= 0.0) {
		return s.cam.viewMatrix(wf, hf);
	}
	const dw: float32 = s.designW;
	const dh: float32 = s.designH;
	let scaleX: float32 = 1.0;
	let scaleY: float32 = 1.0;
	let offsetX: float32 = 0.0;
	let offsetY: float32 = 0.0;
	if (s.scaleMode === ScaleMode.Stretch) {
		scaleX = wf / dw;
		scaleY = hf / dh;
	} else if (s.scaleMode === ScaleMode.LetterBox) {
		const r: float32 = wf / dw < hf / dh ? wf / dw : hf / dh;
		scaleX = r; scaleY = r;
		offsetX = (wf - dw * r) * 0.5;
		offsetY = (hf - dh * r) * 0.5;
	} else if (s.scaleMode === ScaleMode.Fixed) {
		offsetX = (wf - dw) * 0.5;
		offsetY = (hf - dh) * 0.5;
	} else if (s.scaleMode === ScaleMode.Zoom) {
		const r: float32 = wf / dw > hf / dh ? wf / dw : hf / dh;
		scaleX = r; scaleY = r;
		offsetX = (wf - dw * r) * 0.5;
		offsetY = (hf - dh * r) * 0.5;
	} else {
		const ratio: float32 = wf / dw < hf / dh ? wf / dw : hf / dh;
		const ir: int32 = ratio as int32;
		let r: float32;
		if (ir > 0) { r = ir as float32; } else { r = 1.0; }
		scaleX = r; scaleY = r;
		offsetX = (wf - dw * r) * 0.5;
		offsetY = (hf - dh * r) * 0.5;
	}
	return trs2d(offsetX, offsetY, 0.0, scaleX, scaleY) * s.cam.viewMatrix(dw, dh);
}

export function present(this s: Scene): void {
	s.presentAt(dpiScale());
}

// h2d has no DPI concept — a Heaps scene is sized in framebuffer pixels. void2d needs one,
// because the pixel-exact text regime and the snapping rules are stated per device pixel.
// `present()` takes the host's ratio; `presentAt` takes an explicit one, which is how a
// golden scene pins DPI 1.25 or 1.5 on a box whose display reports 1.0 (docs/TESTING.md,
// "Determinism preconditions").
export function presentAt(this s: Scene, dpi: float32): void {
	const fw: int32 = fbWidth();
	const fh: int32 = fbHeight();
	const wf: float32 = (fw as float32) / dpi;
	const hf: float32 = (fh as float32) / dpi;
	begin2d(wf, hf, dpi);
	// Before the walk, never during it: two nodes with identical state must not sample
	// differently because the default moved between them.
	setSceneSmooth(s.defaultSmooth);
	releaseTargets();
	const nv: Transform2D = sceneViewMatrix(s, wf, hf);
	const viewChanged: boolean = !s.viewInit
		|| nv.a != s.viewMat.a || nv.b != s.viewMat.b
		|| nv.c != s.viewMat.c || nv.d != s.viewMat.d
		|| nv.tx != s.viewMat.tx || nv.ty != s.viewMat.ty;
	if (viewChanged) {
		s.viewMat = nv;
		s.viewInit = true;
	}
	s.root.sync(s.viewMat, viewChanged);
	s.root.draw(1.0, wf, hf);
	// Every render-target pass first, with no pass open, then one swapchain pass that is only
	// draws. That ordering is what stops a filter nesting a pass inside the frame's pass, and
	// it is the GPUI frame shape (GPUI.md:18).
	flushTargets();
	beginPass(s.clear.r, s.clear.g, s.clear.b, s.clear.a);
	end2d();
	endPass();
	commit();
	// Closes the sokol frame for the batcher. A frame may hold several brackets - the demo
	// runs its manual filter targets in one and the scene in another - and sokol resets a
	// buffer's append cursor only here, so this is the only safe place to re-arm what is
	// per frame rather than per bracket.
	frameEnd();
}
