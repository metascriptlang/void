// Void 2D Scene — functional take on h2d.Scene: a root container (Object) + the render
// entry that owns the GPU pass. Heaps: `s2d.addChild(o); s2d.render(engine)`.
// Here: `const s = scene(clear); s.add(o); s.present();` — extension methods, no OOP.

import { Scene, NodeRef, DrawKind, NO_NODE } from "./node";
import { sync, draw, releaseTargets } from "./render";
import { begin2d, end2d, flushTargets, setSceneSmooth } from "./draw";
import { advanceBlink, NO_LABEL_TEXT } from "./labelText";
import { Color, Transform2D, ScaleMode, camera, viewMatrix, identity2d, trs2d } from "./types";
import { beginPass, endPass, commit, fbWidth, fbHeight, dpiScale } from "../sokol/gpu";

export function scene(clear: Color): Scene {
	const s: Scene = {
		generations: [], free: [], retired: 0, kinds: [], payloads: [], changed: [], dirty: [],
		structureChanged: true, locals: [], paints: [], contents: [], filters: [], orders: [],
		layouts: [], parents: [], children: [], localMatrices: [], worlds: [], bounds: [],
		anims: [], freeAnims: [], meshes: [], freeMeshes: [], stack: [], root: NO_NODE,
		clear: clear, cam: camera(), scaleMode: ScaleMode.Resize, designW: 0.0, designH: 0.0,
		viewMat: identity2d(), viewInit: false, defaultSmooth: true,
	};
	s.root = s.newRow(DrawKind.Group, NO_NODE);
	return s;
}

export function add(this s: Scene, c: NodeRef): NodeRef {
	return s.refOf(s.root).addChild(c);
}

export function setScaleMode(this s: Scene, mode: ScaleMode, designW: float32, designH: float32): void {
	s.scaleMode = mode;
	s.designW = designW;
	s.designH = designH;
}

export function tick(this s: Scene, dt: float32): void {
	for (let i: int32 = 0; i < (s.kinds.length as int32); i++) {
		const payload: int32 = s.payloads[i];
		match (s.kinds[i]) {
			DrawKind.Anim => {
				s.anims[payload].clock = s.anims[payload].clock + dt;
			},
			DrawKind.Label => {
				if (payload != NO_LABEL_TEXT) { advanceBlink(payload, dt); }
			},
			_ => {},
		}
	}
}

export function sceneViewMatrix(s: Scene, wf: float32, hf: float32): Transform2D {
	if (s.designW <= 0.0 || s.designH <= 0.0) {
		return s.cam.viewMatrix(wf, hf);
	}
	const dw: float32 = s.designW;
	const dh: float32 = s.designH;
	let scaleX: float32 = 1.0;
	let scaleY: float32 = 1.0;
	let offsetX: float32 = 0.0;
	let offsetY: float32 = 0.0;
	match (s.scaleMode) {
		ScaleMode.Resize => {
			return s.cam.viewMatrix(wf, hf);
		},
		ScaleMode.Stretch => {
			scaleX = wf / dw;
			scaleY = hf / dh;
		},
		ScaleMode.LetterBox => {
			const r: float32 = wf / dw < hf / dh ? wf / dw : hf / dh;
			scaleX = r; scaleY = r;
			offsetX = (wf - dw * r) * 0.5;
			offsetY = (hf - dh * r) * 0.5;
		},
		ScaleMode.Fixed => {
			offsetX = (wf - dw) * 0.5;
			offsetY = (hf - dh) * 0.5;
		},
		ScaleMode.Zoom => {
			const r: float32 = wf / dw > hf / dh ? wf / dw : hf / dh;
			scaleX = r; scaleY = r;
			offsetX = (wf - dw * r) * 0.5;
			offsetY = (hf - dh * r) * 0.5;
		},
		ScaleMode.AutoZoom => {
			const ratio: float32 = wf / dw < hf / dh ? wf / dw : hf / dh;
			const ir: int32 = ratio as int32;
			let r: float32;
			if (ir > 0) { r = ir as float32; } else { r = 1.0; }
			scaleX = r; scaleY = r;
			offsetX = (wf - dw * r) * 0.5;
			offsetY = (hf - dh * r) * 0.5;
		},
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
	// Before recording begins, never during the walk: begin2d captures this default in the
	// first run's sampler state.
	setSceneSmooth(s.defaultSmooth);
	begin2d(wf, hf, dpi);
	releaseTargets();
	const nv: Transform2D = sceneViewMatrix(s, wf, hf);
	const viewChanged: boolean = !s.viewInit || nv != s.viewMat;
	if (viewChanged) {
		s.viewMat = nv;
		s.viewInit = true;
	}
	const root: NodeRef = s.refOf(s.root);
	root.sync(s.viewMat, viewChanged);
	root.draw(1.0, wf, hf);
	// Every render-target pass first, with no pass open, then one swapchain pass that is only
	// draws. That ordering is what stops a filter nesting a pass inside the frame's pass, and
	// it is the GPUI frame shape (GPUI.md:18).
	flushTargets();
	beginPass(s.clear.r, s.clear.g, s.clear.b, s.clear.a);
	end2d();
	endPass();
	commit();
	s.clearChanges();
}
