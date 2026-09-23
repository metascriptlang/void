// Two host views in one process, on the D3D11 view driver with no window: each swapchain is
// read back after its own frame and judged by pixels whose place follows from its own size
// and DPI scale. VOID_VIEWS_OUTSIDE=1 instead asks for fbWidth() with no view frame open,
// which must abort (scripts/gate.sh checks the exit status).

import {
	embedRegister, viewCreate, viewResize, viewFrame, viewSwapChain, currentView,
	fbWidth, fbHeight, dpiScale, gfxSetup, ViewId, ViewInvalid,
} from "../../src/sokol/gpu";
import { setup2d } from "../../src/void2d/draw";
import { Scene, present } from "../../src/void2d/scene";
import {
	BoardState, boardState, boardScene, layoutBoard, toggleTileAt,
	OverlayState, overlayState, overlayScene, layoutOverlay,
} from "../../src/examples/viewScenes";
import {
	voidCaptureGrabSwapChain,
	voidCaptureWidth,
	voidCaptureHeight,
	voidCapturePixel,
	voidCaptureSlotsDiffer,
	voidCaptureEnvInt,
	voidCaptureExit,
} from "../capture/capture.h";

const PRESENTED_BUFFER: int32 = 1 as int32;
const TOLERANCE: int64 = 3 as int64;

const EDGE_RGB: int64 = 0x4DCCF2 as int64;
const BOARD_RGB: int64 = 0x12141C as int64;
const TILE_ON_RGB: int64 = 0xF2B840 as int64;

let _board: BoardState = boardState(6 as int32, 4 as int32);
let _overlay: OverlayState = overlayState();
let _boardScene: Scene | null = null;
let _overlayScene: Scene | null = null;
let _boardView: ViewId = ViewInvalid;
let _overlayView: ViewId = ViewInvalid;
let _seenW: int32 = 0 as int32;
let _seenH: int32 = 0 as int32;
let _seenScale: float32 = 0.0;
let _seenView: ViewId = ViewInvalid;
let _failures: int32 = 0 as int32;

function check(ok: boolean, what: string): void {
	if (ok) return;
	console.log(`FAIL two views: ${what}`);
	_failures = _failures + (1 as int32);
}

function initViews(): void {
	gfxSetup();
	setup2d();
	_boardScene = boardScene(_board);
	_overlayScene = overlayScene(_overlay);
}

function frameViews(): void {
	_seenView = currentView();
	_seenW = fbWidth();
	_seenH = fbHeight();
	_seenScale = dpiScale();
	const w: float32 = (_seenW as float32) / _seenScale;
	const h: float32 = (_seenH as float32) / _seenScale;
	if (_seenView === _boardView && _boardScene !== null) {
		layoutBoard(_board, w, h);
		_boardScene.present();
	} else if (_seenView === _overlayView && _overlayScene !== null) {
		layoutOverlay(_overlay, w, h);
		_overlayScene.present();
	} else {
		console.log(`FAIL two views: a frame for unknown view ${_seenView}`);
		voidCaptureExit(1);
	}
}

function near(a: int64, b: int64): boolean {
	return a - b <= TOLERANCE && b - a <= TOLERANCE;
}

function rgbNear(pixel: int64, rgb: int64): boolean {
	return near((pixel >> (24 as int64)) & (0xFF as int64), (rgb >> (16 as int64)) & (0xFF as int64))
		&& near((pixel >> (16 as int64)) & (0xFF as int64), (rgb >> (8 as int64)) & (0xFF as int64))
		&& near((pixel >> (8 as int64)) & (0xFF as int64), rgb & (0xFF as int64));
}

function alphaOf(pixel: int64): int64 { return pixel & (0xFF as int64); }

function hex(v: int64): string { return v.toString(16); }

function expectRgb(slot: int32, x: int32, y: int32, rgb: int64, what: string): void {
	const p = voidCapturePixel(slot, x, y);
	check(rgbNear(p, rgb), `${what}: pixel (${x}, ${y}) is ${hex(p)}, expected rgb ${hex(rgb)}`);
}

function expectAlpha(slot: int32, x: int32, y: int32, low: int64, high: int64, what: string): void {
	const a = alphaOf(voidCapturePixel(slot, x, y));
	check(a >= low && a <= high, `${what}: alpha at (${x}, ${y}) is ${a}, expected ${low}..${high}`);
}

function drawAndGrab(view: ViewId, slot: int32, w: int32, h: int32, scale: float32, what: string): void {
	check(viewFrame(view), `${what}: viewFrame returned false`);
	check(_seenView === view, `${what}: the frame closure saw view ${_seenView}`);
	check(_seenW === w && _seenH === h, `${what}: the frame saw ${_seenW}x${_seenH}, expected ${w}x${h}`);
	check(_seenScale === scale, `${what}: the frame saw dpiScale ${_seenScale}, expected ${scale}`);
	check(currentView() === ViewInvalid, `${what}: view ${currentView()} is still current after the frame`);
	check(voidCaptureGrabSwapChain(slot, viewSwapChain(view), PRESENTED_BUFFER) !== (0 as int32), `${what}: readback failed`);
	check(voidCaptureWidth(slot) === w && voidCaptureHeight(slot) === h,
		`${what}: the swapchain is ${voidCaptureWidth(slot)}x${voidCaptureHeight(slot)}, expected ${w}x${h}`);
}

function checkBoard(slot: int32, w: int32, h: int32, scale: float32, what: string): void {
	const mid: int32 = (h / (2 as int32)) as int32;
	const edgePx: int32 = Math.ceil(3.0 * scale) as int32;
	expectRgb(slot, 0 as int32, mid, EDGE_RGB, `${what}: left edge`);
	expectRgb(slot, w - (1 as int32), mid, EDGE_RGB, `${what}: right edge`);
	expectRgb(slot, mid, h - (1 as int32), EDGE_RGB, `${what}: bottom edge`);
	expectRgb(slot, edgePx + (2 as int32), mid, BOARD_RGB, `${what}: inside the left edge`);
	expectRgb(slot, w - edgePx - (3 as int32), mid, BOARD_RGB, `${what}: inside the right edge`);
	const tile: int32 = Math.ceil(30.0 * scale) as int32;
	expectRgb(slot, tile, tile, TILE_ON_RGB, `${what}: the lit tile`);
}

function run(): int32 {
	embedRegister(initViews, frameViews);
	check(currentView() === ViewInvalid, "a view is current before any frame");
	_boardView = viewCreate(0 as int64, 480 as int32, 300 as int32, 1.0);
	_overlayView = viewCreate(0 as int64, 600 as int32, 330 as int32, 1.5);
	check(_boardView !== _overlayView, "two views got the same id");
	check(viewSwapChain(_boardView) !== viewSwapChain(_overlayView), "two views share a swapchain");

	layoutBoard(_board, 480.0, 300.0);
	toggleTileAt(_board, 30.0, 30.0);

	drawAndGrab(_boardView, 0 as int32, 480 as int32, 300 as int32, 1.0, "board");
	checkBoard(0 as int32, 480 as int32, 300 as int32, 1.0, "board");

	drawAndGrab(_overlayView, 1 as int32, 600 as int32, 330 as int32, 1.5, "overlay");
	expectAlpha(1 as int32, 5 as int32, 5 as int32, 0 as int64, 0 as int64, "overlay: the clear is transparent");
	expectAlpha(1 as int32, 110 as int32, 200 as int32, 0 as int64, 0 as int64, "overlay: left of the panel at scale 1.5");
	expectAlpha(1 as int32, 118 as int32, 200 as int32, 225 as int64, 245 as int64, "overlay: the panel starts at x 114 at scale 1.5");
	expectAlpha(1 as int32, 560 as int32, 302 as int32, 225 as int64, 245 as int64, "overlay: the panel ends at 564,306");
	expectAlpha(1 as int32, 568 as int32, 310 as int32, 0 as int64, 0 as int64, "overlay: past the panel corner");

	drawAndGrab(_boardView, 1 as int32, 480 as int32, 300 as int32, 1.0, "board after the overlay");
	check(voidCaptureSlotsDiffer() === (0 as int32),
		`board: ${voidCaptureSlotsDiffer()} pixels differ once the overlay has drawn in between`);

	viewResize(_boardView, 360 as int32, 240 as int32, 1.25);
	drawAndGrab(_boardView, 0 as int32, 360 as int32, 240 as int32, 1.25, "board resized");
	checkBoard(0 as int32, 360 as int32, 240 as int32, 1.25, "board resized");

	if (_failures === (0 as int32)) {
		console.log("PASS two views: board 480x300@1 and overlay 600x330@1.5 in one process, then the board at 360x240@1.25");
	}
	return _failures === (0 as int32) ? (0 as int32) : (1 as int32);
}

function outside(): int32 {
	embedRegister(initViews, frameViews);
	viewCreate(0 as int64, 64 as int32, 64 as int32, 1.0);
	console.log(`fbWidth outside a frame returned ${fbWidth()}`);
	return 0 as int32;
}

voidCaptureExit(voidCaptureEnvInt("VOID_VIEWS_OUTSIDE", 0 as int32) !== (0 as int32) ? outside() : run());
