// Void driven by an Ion window on Windows: two views, each a visual under the window's root.
//   msc build examples/ionViews.ms --output=out/ionViews.exe
// WebView2Loader.dll must sit next to the exe (../ion/vendor/webview2/runtime/x64/).

import {
	createWindow, defaultOptions, runLoop, windowRoot, windowDevice, commit,
	setFramePolicy, requestFrame, FrameOnDemand, onPointer, onResize, onFrame,
	PointerEvent, PointerKind, Window,
} from "../../ion/src/index";
import { exit } from "std/process";
import {
	embedRegister, viewCreate, viewResize, viewFrame, viewSwapChain, currentView,
	gfxSetup, ViewId, ViewInvalid,
} from "../src/sokol/gpu";
import { setup2d } from "../src/void2d/draw";
import { Scene2D } from "../src/void2d/node";
import { present } from "../src/void2d/scene";
import {
	BoardState, boardState, boardScene, layoutBoard, toggleTileAt,
	OverlayState, overlayState, overlayScene, layoutOverlay, overlayHit, bumpOverlay,
} from "../src/examples/viewScenes";

when (windows) {
	@compile("./swapChainVisual.cpp");
}
@include("./swapChainVisual.h");

extern function swapChainVisualAttach(device: Ptr<void>, root: Ptr<void>, swapChain: int64): Ptr<void>;

struct Area {
	view: ViewId;
	dirty: boolean;
}

let _win: Window | null = null;
let _width: int32 = 0 as int32;
let _height: int32 = 0 as int32;
let _scale: float32 = 1.0;
let _board: Area = { view: ViewInvalid, dirty: false };
let _overlay: Area = { view: ViewInvalid, dirty: false };
let _boardState: BoardState = boardState(6 as int32, 4 as int32);
let _overlayState: OverlayState = overlayState();
let _boardScene: Scene2D | null = null;
let _overlayScene: Scene2D | null = null;

function initViews(): void {
	gfxSetup();
	setup2d();
	_boardScene = boardScene(_boardState);
	_overlayScene = overlayScene(_overlayState);
}

function logicalWidth(): float32 { return (_width as float32) / _scale; }
function logicalHeight(): float32 { return (_height as float32) / _scale; }

function frameView(): void {
	const v = currentView();
	if (v === _board.view && _boardScene !== null) {
		layoutBoard(_boardState, logicalWidth(), logicalHeight());
		_boardScene.present();
	} else if (v === _overlay.view && _overlayScene !== null) {
		layoutOverlay(_overlayState, logicalWidth(), logicalHeight());
		_overlayScene.present();
	} else {
		console.log(`ionViews: no scene for view ${v}`);
		exit(3);
	}
}

function resized(win: Window, a: Area): Area {
	if (a.view !== ViewInvalid) {
		viewResize(a.view, _width, _height, _scale);
		return { ...a, dirty: true };
	}
	const view = viewCreate(0 as int64, _width, _height, _scale);
	if (swapChainVisualAttach(windowDevice(win), windowRoot(win), viewSwapChain(view)) === null) {
		console.log(`ionViews: window ${win.id} refused the swapchain of view ${view}`);
		exit(4);
	}
	return { view, dirty: true };
}

function onWindowResize(window: int32, width: int32, height: int32, scale: float64): void {
	if (_win === null || window !== _win.id) return;
	if (width <= (0 as int32) || height <= (0 as int32)) return;
	console.log(`resize window=${window} ${width}x${height} scale=${scale}`);
	_width = width;
	_height = height;
	_scale = scale as float32;
	_board = resized(_win, _board);
	_overlay = resized(_win, _overlay);
	commit(_win);
	requestFrame(_win);
}

function onWindowPointer(e: PointerEvent): void {
	if (_win === null || e.window !== _win.id) return;
	if (e.kind !== PointerKind.Button || !e.pressed || _board.view === ViewInvalid) return;
	const lx: float32 = (e.x as float32) / _scale;
	const ly: float32 = (e.y as float32) / _scale;
	if (overlayHit(_overlayState, lx, ly)) {
		bumpOverlay(_overlayState);
		_overlay = { ..._overlay, dirty: true };
	} else if (toggleTileAt(_boardState, lx, ly)) {
		_board = { ..._board, dirty: true };
	} else {
		return;
	}
	requestFrame(_win);
}

function drawDirty(a: Area): Area {
	if (!a.dirty || a.view === ViewInvalid) return a;
	viewFrame(a.view);
	return { ...a, dirty: false };
}

function main(): int32 {
	const win = createWindow("main", defaultOptions("Void views on Ion", 960 as int32, 600 as int32));
	if (win === null) return 1;
	_win = win;
	setFramePolicy(win, FrameOnDemand);
	embedRegister(initViews, frameView);
	onResize(onWindowResize);
	onPointer(onWindowPointer);
	onFrame((window: int32, timeMs: float64): void => {
		if (window !== win.id) return;
		_board = drawDirty(_board);
		_overlay = drawDirty(_overlay);
	});
	runLoop();
	return 0;
}

exit(main());
