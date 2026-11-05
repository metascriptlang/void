// Two host views in one X11 window, as Ion hands Void one child area per Neon area on Linux: each
// view draws a board into its own area, then one area is resized. Pixels are read from the X
// server, so they are what the window shows. Needs DISPLAY; on Xvfb build with -d:voidEgl, whose
// GLX lacks ARB_create_context_robustness.

import {
	embedRegister, viewCreate, viewResize, viewFrame, viewSwapChain, currentView,
	fbWidth, fbHeight, dpiScale, gfxSetup, ViewId, ViewInvalid,
} from "../../src/host/gpu";
import { setup2d } from "../../src/void2d/draw";
import { Scene2D } from "../../src/void2d/node";
import { present } from "../../src/void2d/scene";
import { BoardState, boardState, boardScene, layoutBoard, toggleTileAt } from "../../src/examples/viewScenes";
import { x11HostOpen, x11HostArea, x11HostResizeArea, x11HostPixel } from "./x11Host.h";
import { voidCaptureExit } from "../capture/capture.h";

const TOLERANCE: int64 = 3 as int64;
const EDGE_RGB: int64 = 0x4DCCF2 as int64;
const BOARD_RGB: int64 = 0x12141C as int64;
const TILE_ON_RGB: int64 = 0xF2B840 as int64;
const TILE_OFF_RGB: int64 = 0x2E3647 as int64;

let _left: BoardState = boardState(6 as int32, 4 as int32);
let _right: BoardState = boardState(3 as int32, 2 as int32);
let _leftScene: Scene2D | null = null;
let _rightScene: Scene2D | null = null;
let _leftView: ViewId = ViewInvalid;
let _rightView: ViewId = ViewInvalid;
let _failures: int32 = 0 as int32;

function check(ok: boolean, what: string): void {
	if (ok) return;
	console.log(`FAIL linux views: ${what}`);
	_failures = _failures + (1 as int32);
}

function init(): void {
	gfxSetup();
	setup2d();
	_leftScene = boardScene(_left);
	_rightScene = boardScene(_right);
}

function frame(): void {
	const w: float32 = (fbWidth() as float32) / dpiScale();
	const h: float32 = (fbHeight() as float32) / dpiScale();
	const view = currentView();
	if (view === _leftView && _leftScene !== null) {
		layoutBoard(_left, w, h);
		_leftScene.present();
	} else if (view === _rightView && _rightScene !== null) {
		layoutBoard(_right, w, h);
		_rightScene.present();
	} else {
		console.log(`FAIL linux views: a frame for unknown view ${view}`);
		voidCaptureExit(1);
	}
}

function near(a: int64, b: int64): boolean { return a - b <= TOLERANCE && b - a <= TOLERANCE; }

function expectRgb(view: ViewId, x: int32, y: int32, rgb: int64, what: string): void {
	const p = x11HostPixel(viewSwapChain(view), x, y);
	const ok = near((p >> (16 as int64)) & (0xFF as int64), (rgb >> (16 as int64)) & (0xFF as int64))
		&& near((p >> (8 as int64)) & (0xFF as int64), (rgb >> (8 as int64)) & (0xFF as int64))
		&& near(p & (0xFF as int64), rgb & (0xFF as int64));
	check(p >= (0 as int64) && ok, `${what}: pixel (${x}, ${y}) is ${p.toString(16)}, expected ${rgb.toString(16)}`);
}

function checkBoard(view: ViewId, w: int32, h: int32, scale: float32, lit: boolean, what: string): void {
	check(viewFrame(view), `${what}: viewFrame returned false`);
	const mid: int32 = (h / (2 as int32)) as int32;
	const edgePx: int32 = Math.ceil(3.0 * scale) as int32;
	expectRgb(view, 0 as int32, mid, EDGE_RGB, `${what}: left edge`);
	expectRgb(view, w - (1 as int32), mid, EDGE_RGB, `${what}: right edge`);
	expectRgb(view, mid, h - (1 as int32), EDGE_RGB, `${what}: bottom edge`);
	expectRgb(view, edgePx + (2 as int32), mid, BOARD_RGB, `${what}: inside the left edge`);
	expectRgb(view, w - edgePx - (3 as int32), mid, BOARD_RGB, `${what}: inside the right edge`);
	const tile: int32 = Math.ceil(30.0 * scale) as int32;
	expectRgb(view, tile, tile, lit ? TILE_ON_RGB : TILE_OFF_RGB, `${what}: the first tile`);
}

function run(): int32 {
	x11HostOpen(900 as int32, 400 as int32);
	const leftArea = x11HostArea(0 as int32, 0 as int32, 480 as int32, 300 as int32);
	const rightArea = x11HostArea(500 as int32, 20 as int32, 360 as int32, 240 as int32);
	embedRegister(init, frame);
	_leftView = viewCreate(leftArea, 480 as int32, 300 as int32, 1.0);
	_rightView = viewCreate(rightArea, 360 as int32, 240 as int32, 1.25);
	check(viewSwapChain(_leftView) !== viewSwapChain(_rightView), "two views share one X11 window");
	layoutBoard(_left, 480.0, 300.0);
	toggleTileAt(_left, 30.0, 30.0);

	checkBoard(_leftView, 480 as int32, 300 as int32, 1.0, true, "left");
	checkBoard(_rightView, 360 as int32, 240 as int32, 1.25, false, "right");
	expectRgb(_leftView, 30 as int32, 30 as int32, TILE_ON_RGB, "left after the right view drew");

	x11HostResizeArea(leftArea, 400 as int32, 260 as int32);
	viewResize(_leftView, 400 as int32, 260 as int32, 1.25);
	checkBoard(_leftView, 400 as int32, 260 as int32, 1.25, true, "left resized");
	expectRgb(_rightView, 4 as int32 + (Math.ceil(3.0 * 1.25) as int32), 120 as int32, BOARD_RGB,
		"right after the left view resized");

	if (_failures === (0 as int32)) {
		console.log("PASS linux views: 480x300@1 and 360x240@1.25 in one X11 window, then the left at 400x260@1.25");
	}
	return _failures === (0 as int32) ? (0 as int32) : (1 as int32);
}

voidCaptureExit(run());
