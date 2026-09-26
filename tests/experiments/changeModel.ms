import { FontId } from "../../src/void2d/font";
import { gfxSetup } from "../../src/sokol/gpu";
import { setup2d } from "../../src/void2d/draw";
import { Node2D, rect, label, at, addChild } from "../../src/void2d/node";
import { Scene, scene, add, present } from "../../src/void2d/scene";
import { Color, Tile, Smooth, BlendMode, rgba } from "../../src/void2d/types";
import { Align } from "../../src/void2d/textLayout";

@include("../../src/sokol/bridge.h");

extern function voidRunConfigured(
	w: int32,
	h: int32,
	sampleCount: int32,
	highDpi: int32,
	init: () => void,
	frame: () => void,
): void;

const COLUMNS: int32 = 250;
const ROWS: int32 = 200;
const CELL_W: float32 = 5.12;
const CELL_H: float32 = 3.6;
const WARMUP_FRAMES: int32 = 20;
const MEASURED_FRAMES: int32 = 120;

struct Snap {
	x: float32;
	y: float32;
	scaleX: float32;
	scaleY: float32;
	rotation: float32;
	pivotX: float32;
	pivotY: float32;
	alpha: float32;
	visible: boolean;
	smooth: Smooth;
	tileWrap: boolean;
	blend: BlendMode;
	zIndex: int32;
	w: float32;
	h: float32;
	color: Color;
	colorAdd: Color;
	colorKey: Color;
	sheet: Tile;
	borderL: float32;
	borderT: float32;
	borderR: float32;
	borderB: float32;
	text: string;
	size: float32;
	textAlign: Align;
	letterSpacing: float32;
	lineSpacing: float32;
	maxWidth: float32;
	fontId: FontId;
	payload: int32;
	children: int32;
}

function snapOf(n: Node2D): Snap {
	return {
		x: n.x, y: n.y, scaleX: n.scaleX, scaleY: n.scaleY, rotation: n.rotation,
		pivotX: n.pivotX, pivotY: n.pivotY, alpha: n.alpha, visible: n.visible, smooth: n.smooth,
		tileWrap: n.tileWrap, blend: n.blend, zIndex: n.zIndex, w: n.w, h: n.h,
		color: n.color, colorAdd: n.colorAdd, colorKey: n.colorKey, sheet: n.sheet,
		borderL: n.borderL, borderT: n.borderT, borderR: n.borderR, borderB: n.borderB,
		text: n.text, size: n.size, textAlign: n.textAlign, letterSpacing: n.letterSpacing,
		lineSpacing: n.lineSpacing, maxWidth: n.maxWidth, fontId: n.fontId, payload: n.payload,
		children: n.children.length as int32,
	};
}

function changed(n: Node2D, s: Snap): boolean {
	return n.x != s.x || n.y != s.y || n.scaleX != s.scaleX || n.scaleY != s.scaleY
		|| n.rotation != s.rotation || n.pivotX != s.pivotX || n.pivotY != s.pivotY
		|| n.alpha != s.alpha || n.visible != s.visible || n.smooth != s.smooth
		|| n.tileWrap != s.tileWrap || n.blend != s.blend || n.zIndex != s.zIndex
		|| n.w != s.w || n.h != s.h || n.color != s.color || n.colorAdd != s.colorAdd
		|| n.colorKey != s.colorKey || n.sheet != s.sheet
		|| n.borderL != s.borderL || n.borderT != s.borderT || n.borderR != s.borderR
		|| n.borderB != s.borderB || n.text != s.text || n.size != s.size
		|| n.textAlign != s.textAlign || n.letterSpacing != s.letterSpacing
		|| n.lineSpacing != s.lineSpacing || n.maxWidth != s.maxWidth || n.fontId != s.fontId
		|| n.payload != s.payload || (n.children.length as int32) != s.children;
}

const order: Node2D[] = [];
let snaps: Vec<Snap> = new Array(0);

function flatten(n: Node2D): void {
	for (const child of n.children) {
		order.push(child);
		snaps.push(snapOf(child));
		lastX.push(child.x);
		lastY.push(child.y);
		flatten(child);
	}
}

let lastX: Vec<float32> = new Array(0);
let lastY: Vec<float32> = new Array(0);

function sweepTwoFields(): int32 {
	let found: int32 = 0;
	for (let i = 0; i < (order.length as int32); i++) {
		const n: Node2D = order[i];
		if (n.x != lastX[i] || n.y != lastY[i]) {
			lastX[i] = n.x;
			lastY[i] = n.y;
			found = found + 1;
		}
	}
	return found;
}

function sweep(): int32 {
	let found: int32 = 0;
	for (let i = 0; i < (order.length as int32); i++) {
		if (changed(order[i], snaps[i])) {
			snaps[i] = snapOf(order[i]);
			found = found + 1;
		}
	}
	return found;
}

let theScene: Scene | null = null;
let frameIndex: int32 = 0;
let sweepMs: float64 = 0.0;
let sweepChangedMs: float64 = 0.0;
let sweepTwoMs: float64 = 0.0;
let presentMs: float64 = 0.0;
let changesFound: int32 = 0;

function init(): void {
	gfxSetup();
	setup2d();
	const s = scene(rgba(0.08, 0.09, 0.11, 1.0));
	for (let row: int32 = 0; row < ROWS; row++) {
		for (let column: int32 = 0; column < COLUMNS; column++) {
			const card = rect(CELL_W - 0.5, CELL_H - 0.5, rgba(0.2, 0.3, 0.5, 1.0))
				.at((column as float32) * CELL_W, (row as float32) * CELL_H);
			const text: string = String((row * COLUMNS + column) % 100);
			card.addChild(label(text, 3.0, rgba(1.0, 1.0, 1.0, 1.0)));
			s.add(card);
		}
	}
	flatten(s.root);
	theScene = s;
}

function frame(): void {
	if (theScene === null) { return; }
	const s: Scene = theScene;
	frameIndex = frameIndex + 1;
	if (frameIndex <= WARMUP_FRAMES) {
		sweep();
		s.present();
		return;
	}
	const measured: int32 = frameIndex - WARMUP_FRAMES;
	if (measured <= MEASURED_FRAMES) {
		const idleStarted: float64 = performance.now();
		changesFound = changesFound + sweep();
		sweepMs = sweepMs + (performance.now() - idleStarted);
		const twoStarted: float64 = performance.now();
		changesFound = changesFound + sweepTwoFields();
		sweepTwoMs = sweepTwoMs + (performance.now() - twoStarted);
		const presentStarted: float64 = performance.now();
		s.present();
		presentMs = presentMs + (performance.now() - presentStarted);
		return;
	}
	if (measured <= MEASURED_FRAMES * 2) {
		order[(measured * 7919) % (order.length as int32)].x += 0.25;
		const oneStarted: float64 = performance.now();
		changesFound = changesFound + sweep();
		sweepChangedMs = sweepChangedMs + (performance.now() - oneStarted);
		s.present();
		return;
	}
	const frames: float64 = MEASURED_FRAMES as float64;
	console.log(`changeModel.nodes ${order.length}`);
	console.log(`changeModel.changesFound ${changesFound}`);
	console.log(`changeModel.sweep.ms ${sweepMs / frames}`);
	console.log(`changeModel.sweepOneChanged.ms ${sweepChangedMs / frames}`);
	console.log(`changeModel.sweepTwoFields.ms ${sweepTwoMs / frames}`);
	console.log(`changeModel.present.ms ${presentMs / frames}`);
	process.exit(0);
}

voidRunConfigured(1280, 720, 1, 0, init, frame);
