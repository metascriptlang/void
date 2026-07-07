// Void 2D Scene — functional take on h2d.Scene: a root container (Object) + the render
// entry that owns the GPU pass. Heaps: `s2d.addChild(o); s2d.render(engine)`.
// Here: `const s = scene(clear); s.add(o); s.present();` — extension methods, no OOP.

import { Node2D, group, addChild, update } from "./node";
import { sync, draw } from "./render";
import { begin2d, end2d } from "./draw";
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
}

export function scene(clear: Color): Scene {
	return {
		root: group(), clear: clear, cam: camera(),
		scaleMode: ScaleMode.Resize, designW: 0.0, designH: 0.0,
		viewMat: identity2d(), viewInit: false
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
	const fw: int32 = fbWidth();
	const fh: int32 = fbHeight();
	const dpi: float32 = dpiScale();
	const wf: float32 = (fw as float32) / dpi;
	const hf: float32 = (fh as float32) / dpi;
	beginPass(s.clear.r, s.clear.g, s.clear.b, s.clear.a);
	begin2d(wf as int32, hf as int32, dpi);
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
	end2d();
	endPass();
	commit();
}
