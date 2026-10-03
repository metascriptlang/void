import { Scene2D, NodeRef, DrawKind, Changed, NO_NODE_2D } from "./node";
import { syncOrder, drawOrder, spliceOrder, patchOrder, refreshScopes, snappedShift } from "./render";
import {
	openBracket,
	startContext,
	finishRecording,
	setSceneSmooth,
	paintIndex,
	endPatch,
	enterCamera,
} from "./draw";
import { DrawContext2D, NO_REPAINT, useContext } from "./displayList";
import { advanceBlink, cursorShown, labelTexts, NO_LABEL_TEXT } from "./labelText";
import {
	Color,
	Transform2D,
	ScaleMode,
	Vec2,
	camera,
	viewMatrix,
	identity2d,
	trs2d,
	vec2,
} from "./types";
import { fbWidth, fbHeight, dpiScale } from "../sokol/gpu";
import { PassState, passState, beginScreenPassWith, endPass, commit } from "../gpu/door";
import { RenderTarget } from "../gpu/target";

export function create(this typeof Scene2D, clear: Color): Scene2D {
	const context: DrawContext2D = DrawContext2D.create();
	const s: Scene2D = {
		generations: [], free: [], retired: 0, kinds: [], payloads: [], changed: [], dirty: [],
		structureChanged: true, locals: [], paints: [], contents: [], filters: [], orders: [],
		layouts: [], parents: [], children: [], order: [], orderEnd: [], slots: [],
		orderBuilds: 0, localMatrices: [], worlds: [], bounds: [], alphas: [], moved: [],
		maskEnds: [], maskKinds: [], lanes: [], laneMarks: [], repaint: [], queued: [], patchSerial: 0, retry: [], scanNeeded: false,
		patches: 0, splices: 0, repainted: NO_REPAINT, reused: 0,
		anims: [], freeAnims: [], colorMatrices: [], freeColorMatrices: [],
		meshes: [], freeMeshes: [], tileGroups: [], tileCells: [],
		tileEdits: [], freeTileGroups: [], retile: [], retiled: 0, scrolls: [], freeScrolls: [],
		stack: [], root: NO_NODE_2D,
		context: context, spareContext: DrawContext2D.twin(context.id),
		clear: clear, cam: camera(), scaleMode: ScaleMode.Resize, designW: 0.0, designH: 0.0,
		viewMat: identity2d(), viewShift: vec2(0.0, 0.0), culledShift: vec2(0.0, 0.0),
		viewInit: false, defaultSmooth: true, culls: [],
	};
	s.root = s.newRow(DrawKind.Group, NO_NODE_2D);
	return s;
}

export function add(this s: Scene2D, c: NodeRef): NodeRef {
	return s.refOf(s.root).addChild(c);
}

export function setScaleMode(this s: Scene2D, mode: ScaleMode, designW: float32, designH: float32): void {
	s.scaleMode = mode;
	s.designW = designW;
	s.designH = designH;
}

export function tick(this s: Scene2D, dt: float32): void {
	for (let i: int32 = 0; i < (s.kinds.length as int32); i++) {
		const payload: int32 = s.payloads[i];
		match (s.kinds[i]) {
			DrawKind.Anim => {
				const shown: int32 = s.anims[payload].frameIndex();
				s.anims[payload].clock = s.anims[payload].clock + dt;
				if (s.anims[payload].frameIndex() != shown) { s.markChanged(i, Changed.Content); }
			},
			DrawKind.Label => {
				if (payload != NO_LABEL_TEXT) {
					const shown: boolean = cursorShown(labelTexts[payload]);
					advanceBlink(payload, dt);
					if (cursorShown(labelTexts[payload]) != shown) { s.markChanged(i, Changed.Text); }
				}
			},
			_ => {},
		}
	}
}

function wholeSceneUnits(window: float32, design: float32, zoom: float64): float32 {
	const covered: float64 = (design as float64) * zoom;
	const margin: float64 = ((window as float64) - covered) / (2.0 * zoom);
	return (Math.floor(margin) * zoom) as float32;
}

export function sceneViewMatrix(s: Scene2D, wf: float32, hf: float32): Transform2D {
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
			const across: float64 = (wf as float64) / (dw as float64);
			const down: float64 = (hf as float64) / (dh as float64);
			const zoom: float64 = across < down ? across : down;
			scaleX = r; scaleY = r;
			offsetX = wholeSceneUnits(wf, dw, zoom);
			offsetY = wholeSceneUnits(hf, dh, zoom);
		},
		ScaleMode.Fixed => {
			offsetX = wholeSceneUnits(wf, dw, 1.0);
			offsetY = wholeSceneUnits(hf, dh, 1.0);
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

export function present(this s: Scene2D): void {
	s.presentAt(dpiScale());
}

// h2d has no DPI concept — a Heaps scene is sized in framebuffer pixels. void2d needs one,
// because the pixel-exact text regime and the snapping rules are stated per device pixel.
// `present()` takes the host's ratio; `presentAt` takes an explicit one, which is how a
// golden scene pins DPI 1.25 or 1.5 on a box whose display reports 1.0 (docs/TESTING.md,
// "Determinism preconditions").
export function isDirty(this s: Scene2D): boolean {
	const l: DrawContext2D = s.context;
	if (!l.painted || s.structureChanged || (s.dirty.length as int32) > 0) { return true; }
	if (s.defaultSmooth != l.paintedSmooth) { return true; }
	const nv: Transform2D = sceneViewMatrix(s, l.paintedW, l.paintedH);
	return linearPart(nv) != s.viewMat || shiftOf(nv, l.paintedDpi) != s.viewShift;
}

function linearPart(m: Transform2D): Transform2D {
	return { ...m, tx: 0.0, ty: 0.0 };
}

function shiftOf(m: Transform2D, dpi: float32): Vec2 {
	return vec2(snappedShift(m.tx, dpi), snappedShift(m.ty, dpi));
}

export function paint(this s: Scene2D, wf: float32, hf: float32, dpi: float32): void {
	s.retiled = 0;
	useContext(s.context);
	setSceneSmooth(s.defaultSmooth);
	openBracket(wf, hf, dpi);
	const nv: Transform2D = sceneViewMatrix(s, wf, hf);
	const linear: Transform2D = linearPart(nv);
	const viewChanged: boolean = !s.viewInit || linear != s.viewMat;
	if (viewChanged) {
		s.viewMat = linear;
		s.viewInit = true;
	}
	s.viewShift = shiftOf(nv, dpi);
	s.refreshOrder();
	const l: DrawContext2D = s.context;
	const kept: boolean = l.painted && !viewChanged &&
		l.paintedW == wf && l.paintedH == hf && l.paintedDpi == dpi &&
		l.paintedSmooth == s.defaultSmooth;
	if (kept && s.patchOrder(wf, hf)) {
		endPatch(l.paintEnd);
		s.patches = s.patches + 1;
		s.repainted = s.repaint.length as int32;
		s.culledShift = s.viewShift;
		return;
	}
	if (kept) {
		const next: DrawContext2D = s.spareContext;
		useContext(next);
		next.frameDpi = dpi;
		next.fbW = wf;
		next.fbH = hf;
		next.targetsFlushed = false;
		next.frameLive = true;
		next.originX = 0.0;
		next.originY = 0.0;
		setSceneSmooth(s.defaultSmooth);
		startContext();
		enterCamera(s.root, s.viewShift.x, s.viewShift.y);
		s.spliceOrder(l, wf, hf);
		s.spareContext = l;
		s.context = next;
		s.splices = s.splices + 1;
		s.repainted = s.repaint.length as int32;
	} else {
		startContext();
		enterCamera(s.root, s.viewShift.x, s.viewShift.y);
		s.syncOrder(s.viewMat, viewChanged);
		s.drawOrder(wf, hf);
		s.repainted = NO_REPAINT;
	}
	s.culledShift = s.viewShift;
	const done: DrawContext2D = s.context;
	finishRecording();
	done.paintEnd = paintIndex();
	done.painted = true;
	done.paintedW = wf;
	done.paintedH = hf;
	done.paintedDpi = dpi;
	done.paintedSmooth = s.defaultSmooth;
}

export function prepare(this s: Scene2D, wf: float32, hf: float32, dpi: float32): void {
	if (s.context.prepared) {
		console.log(`void2d: prepare Scene2D context ${s.context.id} again before drawScreen`);
		unreachable;
	}
	if (passState() != PassState.None) {
		console.log("void2d: prepare Scene2D with a pass already open");
		unreachable;
	}
	s.paint(wf, hf, dpi);
	s.refreshScopes();
	s.context.prepare();
	s.clearChanges();
	s.retryRefused();
}

export function drawScreen(this s: Scene2D): void {
	s.context.drawScreen();
}

export function drawTarget(this s: Scene2D, target: RenderTarget): void {
	s.context.drawTarget(target, s.clear);
}

export function presentAt(this s: Scene2D, dpi: float32): void {
	s.prepare((fbWidth() as float32) / dpi, (fbHeight() as float32) / dpi, dpi);
	beginScreenPassWith(s.clear.r, s.clear.g, s.clear.b, s.clear.a);
	s.drawScreen();
	endPass();
	commit();
}
