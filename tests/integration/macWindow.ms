// The macOS window driver behind window.ms: the test is the user. It drives the real NSWindow
// and NSView through what AppKit hands them (sendEvent for keys, buttons, flags; the view's own
// scroll, enter/exit and NSTextInputClient entry points; performDragOperation for a drop) and
// judges what reaches the app event handler and what the window, pasteboard and cursor then
// show. A person's keyboard, mouse and IME are not in it. After the checks it asks to quit and
// the process must end by itself (exit 0).

@include("macWindowHost.h");
@compile("./macWindowHost.m", "-fobjc-arc");
extern function macHostWindowCount(): int32;
extern function macHostTitle(): string;
extern function macHostPasteboard(): string;
extern function macHostClearPasteboard(): void;
extern function macHostCursorIs(cursor: int32): int32;
extern function macHostKey(down: int32, keyCode: int32, chars: cstring, flags: uint32): void;
extern function macHostFlags(flags: uint32): void;
extern function macHostMouse(type: int32, x: float64, y: float64, flags: uint32): void;
extern function macHostScroll(lines: int32): void;
extern function macHostEnter(enter: int32, x: float64, y: float64): void;
extern function macHostMark(text: cstring, caret: int32): void;
extern function macHostInsert(text: cstring): void;
extern function macHostImeRectFits(x: float64, y: float64, w: float64, h: float64): int32;
extern function macHostResignKey(): void;
extern function macHostBecomeKey(): void;
extern function macHostMiniaturize(on: int32): void;
extern function macHostFullscreenStyle(): int32;
extern function macHostSetContentSize(w: int32, h: int32): void;
extern function macHostLayerDrawableWidth(): int32;
extern function macHostLayerDrawableHeight(): int32;
extern function macHostDrop(path: cstring): int32;
extern function macHostScale(): float32;

import { gfxSetup, fbWidth, fbHeight } from "../../src/sokol/gpu";
import { beginScreenPassWith, endPass, commit } from "../../src/gpu/door";
import {
	AppEvent, AppEventType, MouseCursor, onAppEvent, setWindowTitle, requestQuit, cancelQuit,
	frameDuration, setClipboard, clipboard, setMouseCursor, mouseCursor, showMouse, mouseShown,
	lockMouse, mouseLocked, toggleFullscreen, isFullscreen, droppedFiles, setTextInput, setImeRect,
} from "../../src/sokol/window";
import { exit } from "std/process";

@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const shiftFlag: uint32 = 131072;
const commandFlag: uint32 = 1048576;
const keyA: int32 = 65;
const keyS: int32 = 83;
const keyLeft: int32 = 263;
const keyLeftSuper: int32 = 343;
const waitFrames: int32 = 480;

let log: AppEvent[] = [];
let failures: int32 = 0;
let step: int32 = 0;
let waited: int32 = 0;
let markFrame: int32 = 0;
let frames: int32 = 0;
let cancelQuitOnce: boolean = false;
let baseWidth: int32 = 0;

function check(ok: boolean, what: string): void {
	if (ok) return;
	console.log(`FAIL macOS window: ${what}`);
	failures = failures + 1;
}

function onEvent(e: AppEvent): void {
	log.push(e);
	if (e.type === AppEventType.QuitRequested && cancelQuitOnce) {
		cancelQuitOnce = false;
		cancelQuit();
	}
}

function init(): void {
	gfxSetup();
	onAppEvent(onEvent);
}

function count(type: AppEventType): int32 {
	let n: int32 = 0;
	for (const e of log) { if (e.type === type) n = n + 1; }
	return n;
}

function last(type: AppEventType): AppEvent {
	let at: int32 = -1;
	for (let i: int32 = 0; i < log.length; i++) { if (log[i].type === type) at = i; }
	check(at >= 0, `no ${type as int32} event arrived`);
	return log[at < 0 ? 0 : at];
}

function types(): string {
	let out: string = "";
	for (const e of log) { out = `${out}${e.type as int32} `; }
	return out;
}

function until(done: boolean, what: string): void {
	if (done) {
		step = step + 1;
		waited = 0;
		return;
	}
	waited = waited + 1;
	if (waited > waitFrames) {
		console.log(`FAIL macOS window: gave up waiting for ${what}; events ${types()}`);
		exit(1);
	}
}

function fb(points: int32): int32 { return Math.round((points as float64) * (macHostScale() as float64)) as int32; }

function stepTiming(): void {
	if (frames < 30) return;
	const d: float64 = frameDuration();
	check(d > 0.005 && d < 0.05, `frame duration ${d} is outside 5..50 ms`);
	check(macHostTitle() === "Void — sokol", `initial title '${macHostTitle()}'`);
	setWindowTitle("Void ü window");
	check(macHostTitle() === "Void ü window", `title '${macHostTitle()}' after setWindowTitle`);
	step = step + 1;
}

function stepClipboard(): void {
	setClipboard("Void clipboard ü 漢");
	check(clipboard() === "Void clipboard ü 漢", `clipboard read back '${clipboard()}'`);
	check(macHostPasteboard() === "Void clipboard ü 漢", `NSPasteboard holds '${macHostPasteboard()}'`);
	macHostClearPasteboard();
	check(clipboard() === "", `an empty pasteboard read back '${clipboard()}'`);
	step = step + 1;
}

function stepCursor(): void {
	setMouseCursor(MouseCursor.IBeam);
	check(mouseCursor() === MouseCursor.IBeam, "mouseCursor after IBeam");
	check(macHostCursorIs(2) === 1, "NSCursor.currentCursor is not the I-beam");
	setMouseCursor(MouseCursor.PointingHand);
	check(macHostCursorIs(4) === 1, "NSCursor.currentCursor is not the pointing hand");
	setMouseCursor(MouseCursor.Default);
	check(macHostCursorIs(0) === 1, "Default is not the arrow");
	showMouse(false);
	check(!mouseShown(), "mouseShown after showMouse(false)");
	showMouse(true);
	check(mouseShown(), "mouseShown after showMouse(true)");
	lockMouse(true);
	check(mouseLocked(), "mouseLocked after lockMouse(true)");
	lockMouse(false);
	check(!mouseLocked(), "mouseLocked after lockMouse(false)");
	step = step + 1;
}

function stepKeys(): void {
	log = [];
	macHostKey(1, 0, "a", 0);
	macHostKey(0, 0, "a", 0);
	check(types() === "1 3 2 ", `key a: events ${types()}, want KeyDown Char KeyUp`);
	check(log[0].keyCode === keyA && !log[0].keyRepeat && log[0].modifiers === 0, "key a down: code, repeat or modifiers");
	check((log[1].charCode as int32) === 97, `key a char ${log[1].charCode}`);
	check(log[2].keyCode === keyA, "key a up code");
	log = [];
	macHostKey(1, 1, "S", shiftFlag);
	check(log[0].keyCode === keyS && log[0].modifiers === 1, `shift+s: code ${log[0].keyCode} modifiers ${log[0].modifiers}`);
	log = [];
	macHostKey(1, 123, "", 0);
	check(types() === "1 ", `left arrow: events ${types()}, want KeyDown only`);
	check(log[0].keyCode === keyLeft, `left arrow code ${log[0].keyCode}`);
	log = [];
	macHostFlags(commandFlag);
	macHostFlags(0);
	check(types() === "1 2 ", `command flag: events ${types()}`);
	check(log[0].keyCode === keyLeftSuper && log[0].modifiers === 8, `command down: code ${log[0].keyCode} modifiers ${log[0].modifiers}`);
	check(log[1].keyCode === keyLeftSuper, "command up code");
	log = [];
	macHostKey(1, 9, "v", commandFlag);
	check(count(AppEventType.ClipboardPasted) === 1, "Cmd+V sent no ClipboardPasted");
	step = step + 1;
}

function stepMouse(): void {
	log = [];
	const scale: float32 = macHostScale();
	macHostMouse(5, 100.0, 50.0, 0);
	macHostMouse(5, 110.0, 50.0, 0);
	const move: AppEvent = last(AppEventType.MouseMove);
	check(move.mouseX === 110.0 * scale, `mouse x ${move.mouseX}, want ${110.0 * scale}`);
	check(move.mouseY === (fbHeight() as float32) - 50.0 * scale - 1.0, `mouse y ${move.mouseY}`);
	check(move.mouseDx === 10.0 * scale && move.mouseDy === 0.0, `mouse delta ${move.mouseDx} ${move.mouseDy}`);
	log = [];
	macHostMouse(1, 110.0, 50.0, 0);
	macHostMouse(2, 110.0, 50.0, 0);
	macHostMouse(3, 110.0, 50.0, 0);
	macHostMouse(4, 110.0, 50.0, 0);
	check(types() === "4 5 4 5 ", `buttons: events ${types()}`);
	check(log[0].mouseButton === 0 && log[2].mouseButton === 1, "button numbers");
	log = [];
	macHostEnter(1, 5.0, 5.0);
	macHostEnter(0, 5.0, 5.0);
	check(types() === "8 9 ", `enter and leave: events ${types()}`);
	log = [];
	macHostScroll(3);
	check(last(AppEventType.MouseScroll).scrollY > 0.0, "scroll up gave no positive scrollY");
	step = step + 1;
}

function stepText(): void {
	const scale: float64 = macHostScale() as float64;
	setTextInput(true);
	log = [];
	macHostMark("にほ", 2);
	const preedit: AppEvent = last(AppEventType.Preedit);
	check(preedit.text === "にほ" && preedit.cursor === 2, `preedit '${preedit.text}' at ${preedit.cursor}`);
	macHostInsert("日本");
	check(types() === "24 24 25 ", `commit: events ${types()}`);
	check(log[1].text === "" && log[2].text === "日本", `commit text '${log[2].text}'`);
	log = [];
	macHostKey(1, 0, "a", 0);
	check(count(AppEventType.TextInput) === 1 && count(AppEventType.Char) === 0, `typing with text input on: events ${types()}`);
	setImeRect(40, 60, 10, 20);
	check(macHostImeRectFits(40.0 / scale, 60.0 / scale, 10.0 / scale, 20.0 / scale) === 1, "the IME rectangle is not the one setImeRect gave");
	macHostMark("x", 1);
	log = [];
	setTextInput(false);
	check(types() === "24 ", `text input off with a composition: events ${types()}`);
	check(last(AppEventType.Preedit).text === "", "the composition was not cleared");
	log = [];
	macHostKey(1, 0, "a", 0);
	check(count(AppEventType.Char) === 1 && count(AppEventType.TextInput) === 0, `typing with text input off: events ${types()}`);
	step = step + 1;
}

function stepFocus(): void {
	log = [];
	macHostResignKey();
	macHostBecomeKey();
	check(types() === "18 17 ", `resign and become key: events ${types()}`);
	step = step + 1;
}

function stepResize(): void {
	log = [];
	baseWidth = fbWidth();
	macHostSetContentSize(500, 300);
	const resized: AppEvent = last(AppEventType.Resized);
	check(resized.framebufferWidth === fb(500) && resized.framebufferHeight === fb(300), `resized event ${resized.framebufferWidth}x${resized.framebufferHeight}`);
	check(fbWidth() === fb(500) && fbHeight() === fb(300), `fbWidth ${fbWidth()} fbHeight ${fbHeight()}`);
	check(macHostLayerDrawableWidth() === fb(500) && macHostLayerDrawableHeight() === fb(300), `layer drawable ${macHostLayerDrawableWidth()}x${macHostLayerDrawableHeight()}`);
	step = step + 1;
}

function stepFullscreenIn(): void {
	log = [];
	toggleFullscreen();
	check(isFullscreen(), "isFullscreen right after toggleFullscreen");
	step = step + 1;
}

function stepFullscreenWait(): void {
	until(macHostFullscreenStyle() === 1 && fbWidth() > fb(500) && macHostLayerDrawableWidth() === fbWidth(), "the window to enter full screen");
}

function stepFullscreenSettle(): void {
	if (markFrame === 0) markFrame = frames;
	if (frames < markFrame + 120) return;
	markFrame = 0;
	step = step + 1;
}

function stepFullscreenOut(): void {
	check(isFullscreen(), "isFullscreen while full screen");
	toggleFullscreen();
	check(!isFullscreen(), "isFullscreen right after leaving");
	step = step + 1;
}

function stepFullscreenOutWait(): void {
	until(macHostFullscreenStyle() === 0 && fbWidth() === fb(500) && macHostLayerDrawableWidth() === fbWidth(), "the window to leave full screen");
}

function stepIconify(): void {
	log = [];
	macHostMiniaturize(1);
	step = step + 1;
}

function stepIconifyWait(): void {
	until(count(AppEventType.Iconified) === 1, "the Iconified event");
}

function stepRestore(): void {
	macHostMiniaturize(0);
	step = step + 1;
}

function stepRestoreWait(): void {
	until(count(AppEventType.Restored) === 1, "the Restored event");
}

function stepDrop(): void {
	log = [];
	check(macHostDrop("/usr/bin/true") === 1, "performDragOperation refused a file drop");
	check(count(AppEventType.FilesDropped) === 1, "no FilesDropped event");
	const files: string[] = droppedFiles();
	check(files.length === 1 && files[0] === "/usr/bin/true", `dropped files ${files.join(",")}`);
	step = step + 1;
}

function stepQuitCancelled(): void {
	log = [];
	cancelQuitOnce = true;
	requestQuit();
	step = step + 1;
	markFrame = frames;
}

function stepQuitCancelledWait(): void {
	if (count(AppEventType.QuitRequested) === 0) {
		until(false, "the QuitRequested event");
		return;
	}
	if (frames < markFrame + 20) return;
	check(count(AppEventType.QuitRequested) === 1, `${count(AppEventType.QuitRequested)} QuitRequested events for one request`);
	check(macHostWindowCount() >= 1, "the window closed although the quit was cancelled");
	step = step + 1;
	waited = 0;
}

function stepQuit(): void {
	if (failures > 0) {
		console.log(`FAIL macOS window: ${failures} checks failed`);
		exit(1);
	}
	console.log("PASS macOS window: events, text input, clipboard, cursors, resize, full screen, iconify, drop and a cancelled quit");
	requestQuit();
	step = step + 1;
}

function stepQuitWait(): void {
	until(false, "the process to end after requestQuit");
}

function advance(): void {
	if (step === 0) stepTiming();
	else if (step === 1) stepClipboard();
	else if (step === 2) stepCursor();
	else if (step === 3) stepKeys();
	else if (step === 4) stepMouse();
	else if (step === 5) stepText();
	else if (step === 6) stepFocus();
	else if (step === 7) stepResize();
	else if (step === 8) stepFullscreenIn();
	else if (step === 9) stepFullscreenWait();
	else if (step === 10) stepFullscreenSettle();
	else if (step === 11) stepFullscreenOut();
	else if (step === 12) stepFullscreenOutWait();
	else if (step === 13) stepIconify();
	else if (step === 14) stepIconifyWait();
	else if (step === 15) stepRestore();
	else if (step === 16) stepRestoreWait();
	else if (step === 17) stepDrop();
	else if (step === 18) stepQuitCancelled();
	else if (step === 19) stepQuitCancelledWait();
	else if (step === 20) stepQuit();
	else stepQuitWait();
}

function frame(): void {
	frames = frames + 1;
	beginScreenPassWith(0.1, 0.1, 0.15, 1.0);
	endPass();
	commit();
	advance();
}

voidRun(320, 200, init, frame);
