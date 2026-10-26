// The host-view driver on macOS, with no sokol_app window: the test is the host. It makes an
// NSWindow and its NSView, hands the view to viewCreate, and drives viewFrame. What it judges is
// what the host can observe: the size the frame closure reads, the layer Void put under the
// view, its drawable size after a resize, and a view made with no host view. sokol has no
// Metal readback, so no pixel is read back (tests/capture/capture.h).

@include("macViewsHost.h");
@compile("./macViewsHost.m", "-fobjc-arc");
extern function macHostOpen(width: int32, height: int32): int64;
extern function macHostResize(width: int32, height: int32): void;
extern function macHostPump(): void;
extern function macHostAwaitVsync(): void;
extern function macHostClose(): void;
extern function macHostBackingWidth(): int32;
extern function macHostBackingHeight(): int32;
extern function macHostScale(): float32;
extern function macHostSublayerCount(): int32;
extern function macHostDrawableWidth(): int32;
extern function macHostDrawableHeight(): int32;
extern function macHostLayerDrawableWidth(layer: int64): int32;

import {
	embedRegister, viewCreate, viewResize, viewFrame, viewDestroy, viewSwapChain, currentView,
	fbWidth, fbHeight, dpiScale, gfxSetup, ViewId, ViewInvalid,
} from "../../src/host/gpu";
import { setup2d } from "../../src/void2d/draw";
import { Scene2D } from "../../src/void2d/node";
import { present } from "../../src/void2d/scene";
import { BoardState, boardState, boardScene, layoutBoard } from "../../src/examples/viewScenes";
import { exit } from "std/process";

const FRAMES: int32 = 5 as int32;

let _board: BoardState = boardState(6 as int32, 4 as int32);
let _scene: Scene2D | null = null;
let _seenView: ViewId = ViewInvalid;
let _seenW: int32 = 0 as int32;
let _seenH: int32 = 0 as int32;
let _seenScale: float32 = 0.0;
let _failures: int32 = 0 as int32;

function check(ok: boolean, what: string): void {
	if (ok) return;
	console.log(`FAIL mac views: ${what}`);
	_failures = _failures + (1 as int32);
}

function initViews(): void {
	gfxSetup();
	setup2d();
	_scene = boardScene(_board);
}

function frameView(): void {
	_seenView = currentView();
	_seenW = fbWidth();
	_seenH = fbHeight();
	_seenScale = dpiScale();
	if (_scene === null) { return; }
	layoutBoard(_board, (_seenW as float32) / _seenScale, (_seenH as float32) / _seenScale);
	_scene.present();
}

function drive(view: ViewId, w: int32, h: int32, scale: float32, what: string): void {
	for (let i: int32 = 0 as int32; i < FRAMES; i++) {
		macHostAwaitVsync();
		check(viewFrame(view), `${what}: viewFrame ${i} returned false`);
		check(_seenView === view, `${what}: the frame closure saw view ${_seenView}`);
		check(currentView() === ViewInvalid, `${what}: a view is still current after the frame`);
	}
	check(_seenW === w && _seenH === h, `${what}: the frame saw ${_seenW}x${_seenH}, expected ${w}x${h}`);
	check(_seenScale === scale, `${what}: the frame saw dpiScale ${_seenScale}, expected ${scale}`);
}

function run(): int32 {
	embedRegister(initViews, frameView);
	const host: int64 = macHostOpen(320 as int32, 200 as int32);
	const scale: float32 = macHostScale();
	let w: int32 = macHostBackingWidth();
	let h: int32 = macHostBackingHeight();
	check(w === ((320.0 * scale) as int32) && h === ((200.0 * scale) as int32), `the host view is ${w}x${h} pixels at scale ${scale}`);

	const view: ViewId = viewCreate(host, w, h, scale);
	check(view !== ViewInvalid, "viewCreate on the host NSView returned ViewInvalid");
	check(macHostSublayerCount() === (1 as int32), `the host view has ${macHostSublayerCount()} sublayers, expected 1`);
	check(macHostDrawableWidth() === w && macHostDrawableHeight() === h,
		`the layer is ${macHostDrawableWidth()}x${macHostDrawableHeight()}, expected ${w}x${h}`);
	check(viewSwapChain(view) !== (0 as int64), "viewSwapChain returned no layer");
	drive(view, w, h, scale, "host view");

	macHostResize(240 as int32, 150 as int32);
	w = macHostBackingWidth();
	h = macHostBackingHeight();
	viewResize(view, w, h, scale);
	check(macHostDrawableWidth() === w && macHostDrawableHeight() === h,
		`after resize the layer is ${macHostDrawableWidth()}x${macHostDrawableHeight()}, expected ${w}x${h}`);
	drive(view, w, h, scale, "host view resized");

	const own: ViewId = viewCreate(0 as int64, 200 as int32, 120 as int32, 1.0);
	check(own !== view, "two views got the same id");
	const layer: int64 = viewSwapChain(own);
	check(layer !== (0 as int64) && layer !== viewSwapChain(view), "a view with no host view has no layer of its own");
	check(macHostLayerDrawableWidth(layer) === (200 as int32), "the layer of a view with no host view is not 200 wide");
	check(macHostSublayerCount() === (1 as int32), "a view with no host view attached itself to the host view");
	drive(own, 200 as int32, 120 as int32, 1.0, "own layer");
	drive(view, w, h, scale, "host view after the other drew");

	viewDestroy(view);
	check(macHostSublayerCount() === (0 as int32), "destroying a view left its layer in the host view");
	viewDestroy(own);
	macHostClose();

	if (_failures === (0 as int32)) {
		console.log(`PASS mac views: ${w}x${h}@${scale} host NSView then an own layer 200x120@1, ${FRAMES} frames each, resize and destroy`);
	}
	return _failures === (0 as int32) ? (0 as int32) : (1 as int32);
}

exit(run());
