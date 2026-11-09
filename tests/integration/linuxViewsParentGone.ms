// The host destroys the X11 window around a view before it releases the view, as Ion's closeWindow
// does today: the child Void drew into dies with it. The process must survive the release, keep
// the host's X error handler, and draw a new view afterwards. Needs DISPLAY; on Xvfb build with
// -d:voidEgl, whose GLX lacks ARB_create_context_robustness.

import { embedRegister, viewCreate, viewDestroy, viewFrame, viewSwapChain, fbWidth, fbHeight, dpiScale, gfxSetup } from "../../src/host/gpu";
import { setup2d } from "../../src/void2d/draw";
import { Scene2D } from "../../src/void2d/node";
import { present } from "../../src/void2d/scene";
import { BoardState, boardState, boardScene, layoutBoard } from "../../src/examples/viewScenes";
import { x11HostOpen, x11HostArea, x11HostDestroyArea, x11HostWatchErrors, x11HostHandlerKept, x11HostForeignErrors, x11HostPixel } from "./x11Host.h";
import { voidCaptureExit } from "../capture/capture.h";

const EDGE_RGB: int64 = 0x4DCCF2 as int64;

let _board: BoardState = boardState(3 as int32, 2 as int32);
let _scene: Scene2D | null = null;
let _failures: int32 = 0 as int32;

function check(ok: boolean, what: string): void {
	if (ok) return;
	console.log(`FAIL linux views parent gone: ${what}`);
	_failures = _failures + (1 as int32);
}

function init(): void {
	gfxSetup();
	setup2d();
	_scene = boardScene(_board);
}

function frame(): void {
	layoutBoard(_board, (fbWidth() as float32) / dpiScale(), (fbHeight() as float32) / dpiScale());
	if (_scene !== null) _scene.present();
}

function near(a: int64, b: int64): boolean { return a - b <= (3 as int64) && b - a <= (3 as int64); }

function nearRgb(p: int64, rgb: int64): boolean {
	return p >= (0 as int64) && near((p >> (16 as int64)) & (0xFF as int64), (rgb >> (16 as int64)) & (0xFF as int64))
		&& near((p >> (8 as int64)) & (0xFF as int64), (rgb >> (8 as int64)) & (0xFF as int64))
		&& near(p & (0xFF as int64), rgb & (0xFF as int64));
}

function run(): int32 {
	x11HostOpen(600 as int32, 240 as int32);
	x11HostWatchErrors();
	embedRegister(init, frame);
	const firstArea = x11HostArea(0 as int32, 0 as int32, 280 as int32, 200 as int32);
	const first = viewCreate(firstArea, 280 as int32, 200 as int32, 1.0);
	check(x11HostHandlerKept() !== (0 as int32), "creating a view replaced the host's X error handler");
	check(viewFrame(first), "the first view did not draw");

	x11HostDestroyArea(firstArea);
	viewDestroy(first);

	const secondArea = x11HostArea(300 as int32, 0 as int32, 280 as int32, 200 as int32);
	const second = viewCreate(secondArea, 280 as int32, 200 as int32, 1.0);
	check(viewFrame(second), "the view made after the release did not draw");
	const p = x11HostPixel(viewSwapChain(second), 0 as int32, 100 as int32);
	check(nearRgb(p, EDGE_RGB), `the new view's left edge is ${p.toString(16)}, expected ${EDGE_RGB.toString(16)}`);
	check(x11HostHandlerKept() !== (0 as int32), "releasing a view replaced the host's X error handler");
	const foreign = x11HostForeignErrors();
	check(foreign === (0 as int32), `the host's handler received ${foreign} X errors from Void's connection`);

	if (_failures === (0 as int32)) console.log("PASS linux views parent gone: released after its host window died, then a new view drew");
	return _failures === (0 as int32) ? (0 as int32) : (1 as int32);
}

voidCaptureExit(run());
