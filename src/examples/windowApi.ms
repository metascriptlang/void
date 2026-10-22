// Void — the window API probe: every sokol_app window feature beyond input events, driven by
// keys and logged to the console. C copies a UTF-8 line, F toggles fullscreen, L toggles the
// mouse lock (a mouse button locks in a browser), M hides and shows the pointer, X cycles the
// cursor, Q asks to quit and the first ask is cancelled. Drop files or touch to see their events.

import "../sokol/gpu";
import { beginScreenPassWith, endPass, commit } from "../gpu/door";
import {
	AppEvent, AppEventType, MouseCursor, onAppEvent, requestQuit, cancelQuit, frameDuration,
	setClipboard, clipboard, setMouseCursor, mouseCursor, showMouse, mouseShown, lockMouse,
	mouseLocked, toggleFullscreen, isFullscreen, droppedFiles,
} from "../sokol/window";

@include("../sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const keyC = 67;
const keyF = 70;
const keyL = 76;
const keyM = 77;
const keyQ = 81;
const keyX = 88;

let quitAsked = false;
let frames = 0;

function onKey(code: int32): void {
	if (code === keyC) {
		setClipboard("Void clipboard ü 漢");
		console.log("clipboard set");
	} else if (code === keyF) {
		toggleFullscreen();
		console.log("fullscreen requested, flag " + isFullscreen());
	} else if (code === keyL) {
		lockMouse(!mouseLocked());
		console.log("lock requested, locked " + mouseLocked());
	} else if (code === keyM) {
		showMouse(!mouseShown());
		console.log("mouse shown " + mouseShown());
	} else if (code === keyX) {
		const next = (((mouseCursor() as int32) + 1) % 11) as MouseCursor;
		setMouseCursor(next);
		console.log("cursor " + (next as int32));
	} else if (code === keyQ) {
		requestQuit();
		console.log("quit requested");
	}
}

function onEvent(e: AppEvent): void {
	switch (e.type) {
		case AppEventType.KeyDown:
			onKey(e.keyCode);
			break;
		case AppEventType.QuitRequested:
			if (!quitAsked) {
				quitAsked = true;
				cancelQuit();
				console.log("quit cancelled; ask again to quit");
			}
			break;
		case AppEventType.ClipboardPasted:
			console.log("pasted: " + clipboard());
			break;
		case AppEventType.FilesDropped:
			console.log("dropped " + droppedFiles().length + " file(s): " + droppedFiles().join(", "));
			break;
		case AppEventType.TouchesBegan:
		case AppEventType.TouchesMoved:
		case AppEventType.TouchesEnded:
		case AppEventType.TouchesCancelled:
			console.log("touches " + e.touches.length);
			break;
		case AppEventType.MouseMove:
			if (mouseLocked()) console.log("locked move " + e.mouseDx + " " + e.mouseDy);
			break;
		default:
			break;
	}
}

function init(): void {
	onAppEvent(onEvent);
}

function frame(): void {
	frames++;
	if (frames % 120 === 0) console.log("frame duration " + frameDuration());
	beginScreenPassWith(0.1, 0.1, 0.15, 1.0);
	endPass();
	commit();
}

function main(): int32 {
	voidRun(800, 600, init, frame);
	return 0;
}

main();
