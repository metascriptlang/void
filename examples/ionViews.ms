// Void driven by an Ion window on Windows: two views, each on its own render surface.
//   msc build examples/ionViews.ms --output=out/ionViews.exe
// WebView2Loader.dll must sit next to the exe (../ion/vendor/webview2/runtime/x64/).

import {
	createWindow, defaultOptions, runLoop, onFrame, onInput, onSurfaceResize,
	renderSurfaceCreate, renderSurfaceAttachSwapChain, webviewSetVisible,
	SurfaceBelow, RenderSurfaceInvalid,
} from "../../ion/src/index";
import { exit } from "std/process";
import {
	embedRegister, viewCreate, viewResize, viewFrame, viewSwapChain, currentView,
	gfxSetup, ViewId, ViewInvalid,
} from "../src/sokol/gpu";
import { setup2d } from "../src/void2d/draw";
import { Scene, present } from "../src/void2d/scene";
import {
	BoardState, boardState, boardScene, layoutBoard, toggleTileAt,
	OverlayState, overlayState, overlayScene, layoutOverlay, overlayHit, bumpOverlay,
} from "../src/examples/viewScenes";

const PAGE = "data:text/html,<body style='margin:0;background:transparent'></body>";
const POINTER_BUTTON: int32 = 1 as int32;

struct Surface {
	surface: int32;
	view: ViewId;
	width: int32;
	height: int32;
	scale: float32;
	dirty: boolean;
}

function surface(id: int32): Surface {
	return { surface: id, view: ViewInvalid, width: 0 as int32, height: 0 as int32, scale: 1.0, dirty: false };
}

let _board: Surface = surface(RenderSurfaceInvalid);
let _overlay: Surface = surface(RenderSurfaceInvalid);
let _boardState: BoardState = boardState(6 as int32, 4 as int32);
let _overlayState: OverlayState = overlayState();
let _boardScene: Scene | null = null;
let _overlayScene: Scene | null = null;

function initViews(): void {
	gfxSetup();
	setup2d();
	_boardScene = boardScene(_boardState);
	_overlayScene = overlayScene(_overlayState);
}

function logicalWidth(s: Surface): float32 { return (s.width as float32) / s.scale; }
function logicalHeight(s: Surface): float32 { return (s.height as float32) / s.scale; }

function frameView(): void {
	const v = currentView();
	if (v === _board.view && _boardScene !== null) {
		layoutBoard(_boardState, logicalWidth(_board), logicalHeight(_board));
		_boardScene.present();
	} else if (v === _overlay.view && _overlayScene !== null) {
		layoutOverlay(_overlayState, logicalWidth(_overlay), logicalHeight(_overlay));
		_overlayScene.present();
	} else {
		console.log(`ionViews: no scene for view ${v}`);
		exit(3);
	}
}

function resized(s: Surface, width: int32, height: int32, scale: float64): Surface {
	const next: Surface = { ...s, width, height, scale: scale as float32, dirty: true };
	if (next.view === ViewInvalid) {
		const view = viewCreate(0 as int64, width, height, next.scale);
		if (!renderSurfaceAttachSwapChain(next.surface, viewSwapChain(view))) {
			console.log(`ionViews: surface ${next.surface} refused the swapchain of view ${view}`);
			exit(4);
		}
		return { ...next, view };
	}
	viewResize(next.view, width, height, next.scale);
	return next;
}

function onResize(id: int32, width: int32, height: int32, scale: float64): void {
	if (width <= (0 as int32) || height <= (0 as int32)) return;
	console.log(`resize surface=${id} ${width}x${height} scale=${scale}`);
	if (id === _board.surface) _board = resized(_board, width, height, scale);
	else if (id === _overlay.surface) _overlay = resized(_overlay, width, height, scale);
}

function onPointer(type: int32, x: float64, y: float64, button: float64, pressed: float64): void {
	if (type !== POINTER_BUTTON || pressed === 0.0 || _board.view === ViewInvalid) return;
	const lx: float32 = (x as float32) * logicalWidth(_board);
	const ly: float32 = (y as float32) * logicalHeight(_board);
	if (overlayHit(_overlayState, lx, ly)) {
		bumpOverlay(_overlayState);
		_overlay = { ..._overlay, dirty: true };
	} else if (toggleTileAt(_boardState, lx, ly)) {
		_board = { ..._board, dirty: true };
	}
}

function drawDirty(s: Surface): Surface {
	if (!s.dirty || s.view === ViewInvalid) return s;
	viewFrame(s.view);
	return { ...s, dirty: false };
}

function main(): int32 {
	const win = createWindow("main", defaultOptions("Void views on Ion", 960 as int32, 600 as int32, PAGE));
	if (win === null) return 1;
	webviewSetVisible(win, false);
	embedRegister(initViews, frameView);
	_board = surface(renderSurfaceCreate(win, SurfaceBelow));
	_overlay = surface(renderSurfaceCreate(win, SurfaceBelow));
	if (_board.surface === RenderSurfaceInvalid || _overlay.surface === RenderSurfaceInvalid) return 2;
	onSurfaceResize(onResize);
	onInput(onPointer);
	onFrame((): void => {
		_board = drawDirty(_board);
		_overlay = drawDirty(_overlay);
	});
	runLoop();
	return 0;
}

exit(main());
