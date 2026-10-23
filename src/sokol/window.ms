// The window's events, IME and title, on the window drivers: Windows (D3D11 and
// -d:voidGlCore), macOS, the browser and the iOS and Android apps. Import beside ./gpu, which compiles their C.

import { VoidAppEventType, VoidMouseCursor } from "../platform/appEvent.h";

@include("bridge.h");
@include("appText.h");

extern function voidSetEventHandler(handler: () => void): void;
extern function voidEventType(): int32;
extern function voidEventKeyCode(): int32;
extern function voidEventCharCode(): uint32;
extern function voidEventKeyRepeat(): int32;
extern function voidEventModifiers(): uint32;
extern function voidEventMouseButton(): int32;
extern function voidEventMouseX(): float32;
extern function voidEventMouseY(): float32;
extern function voidEventMouseDx(): float32;
extern function voidEventMouseDy(): float32;
extern function voidEventScrollX(): float32;
extern function voidEventScrollY(): float32;
extern function voidEventFramebufferWidth(): int32;
extern function voidEventFramebufferHeight(): int32;
extern function voidEventText(): string;
extern function voidEventCursor(): int32;
extern function voidSetTextInput(on: int32): void;
extern function voidSetImeRect(x: int32, y: int32, w: int32, h: int32): void;
extern function voidSetWindowTitle(title: cstring): void;
extern function voidEventTouchCount(): int32;
extern function voidEventTouchId(index: int32): int64;
extern function voidEventTouchX(index: int32): float32;
extern function voidEventTouchY(index: int32): float32;
extern function voidEventTouchChanged(index: int32): int32;
extern function voidSafeAreaTop(): float32;
extern function voidSafeAreaLeft(): float32;
extern function voidSafeAreaBottom(): float32;
extern function voidSafeAreaRight(): float32;
extern function voidKeyboardHeight(): float32;
extern function voidRequestQuit(): void;
extern function voidCancelQuit(): void;
extern function voidFrameDuration(): float64;
extern function voidSetClipboard(utf8: cstring): void;
extern function voidClipboard(): string;
extern function voidSetMouseCursor(cursor: int32): void;
extern function voidMouseCursor(): int32;
extern function voidShowMouse(shown: int32): void;
extern function voidMouseShown(): int32;
extern function voidLockMouse(locked: int32): void;
extern function voidMouseLocked(): int32;
extern function voidToggleFullscreen(): void;
extern function voidIsFullscreen(): int32;
extern function voidDroppedFileCount(): int32;
extern function voidDroppedFilePath(i: int32): string;

// Mirrors VoidAppEventType in src/platform/appEvent.h; the test at the end holds every member to it.
export enum AppEventType {
	Invalid,
	KeyDown,
	KeyUp,
	Char,
	MouseDown,
	MouseUp,
	MouseScroll,
	MouseMove,
	MouseEnter,
	MouseLeave,
	TouchesBegan,
	TouchesMoved,
	TouchesEnded,
	TouchesCancelled,
	Resized,
	Iconified,
	Restored,
	Focused,
	Unfocused,
	Suspended,
	Resumed,
	QuitRequested,
	ClipboardPasted,
	FilesDropped,
	Preedit,
	TextInput,
}

export enum MouseCursor {
	Default,
	Arrow,
	IBeam,
	Crosshair,
	PointingHand,
	ResizeEW,
	ResizeNS,
	ResizeNWSE,
	ResizeNESW,
	ResizeAll,
	NotAllowed,
}

export struct AppTouch {
	id: int64;
	x: float32;
	y: float32;
	changed: boolean;
}

export struct SafeArea {
	top: float32;
	left: float32;
	bottom: float32;
	right: float32;
}

export struct AppEvent {
	type: AppEventType;
	keyCode: int32;
	charCode: uint32;
	keyRepeat: boolean;
	modifiers: uint32;
	mouseButton: int32;
	mouseX: float32;
	mouseY: float32;
	mouseDx: float32;
	mouseDy: float32;
	scrollX: float32;
	scrollY: float32;
	framebufferWidth: int32;
	framebufferHeight: int32;
	text: string;
	cursor: int32;
	touches: AppTouch[];
}

let eventHandler: ((e: AppEvent) => void) | null = null;

function currentTouches(): AppTouch[] {
	const out: AppTouch[] = [];
	for (let i: int32 = 0; i < voidEventTouchCount(); i++) {
		out.push({
			id: voidEventTouchId(i),
			x: voidEventTouchX(i),
			y: voidEventTouchY(i),
			changed: voidEventTouchChanged(i) !== 0,
		});
	}
	return out;
}

function currentTouches(): AppTouch[] {
	const out: AppTouch[] = [];
	for (let i: int32 = 0; i < voidEventTouchCount(); i++) {
		out.push({
			id: voidEventTouchId(i),
			x: voidEventTouchX(i),
			y: voidEventTouchY(i),
			changed: voidEventTouchChanged(i) !== 0,
		});
	}
	return out;
}

function currentEvent(): AppEvent {
	return {
		type: voidEventType() as AppEventType,
		keyCode: voidEventKeyCode(),
		charCode: voidEventCharCode(),
		keyRepeat: voidEventKeyRepeat() !== 0,
		modifiers: voidEventModifiers(),
		mouseButton: voidEventMouseButton(),
		mouseX: voidEventMouseX(),
		mouseY: voidEventMouseY(),
		mouseDx: voidEventMouseDx(),
		mouseDy: voidEventMouseDy(),
		scrollX: voidEventScrollX(),
		scrollY: voidEventScrollY(),
		framebufferWidth: voidEventFramebufferWidth(),
		framebufferHeight: voidEventFramebufferHeight(),
		text: voidEventText(),
		cursor: voidEventCursor(),
		touches: currentTouches(),
	};
}

function dispatchEvent(): void {
	const handler = eventHandler;
	if (handler === null) {
		console.log("window: an event arrived with no handler; onAppEvent sets it");
		unreachable;
	} else {
		handler(currentEvent());
	}
}

// Every window event reaches `handler`, Escape included: once one is set, Escape no
// longer quits the app. Call it before voidRun or from its init closure.
export function onAppEvent(handler: (e: AppEvent) => void): void {
	eventHandler = handler;
	voidSetEventHandler(dispatchEvent);
}

export function setWindowTitle(title: string): void { voidSetWindowTitle(title); }

// While on, an IME composition reaches the event handler as Preedit events (`text` with its
// caret `cursor` in UTF-16 units; an empty text ends it) and its result as one TextInput
// event, never also as Char.
export function setTextInput(on: boolean): void { voidSetTextInput(on ? 1 as int32 : 0 as int32); }

// The caret the candidate window opens below, in framebuffer pixels.
export function setImeRect(x: int32, y: int32, w: int32, h: int32): void {
	voidSetImeRect(x, y, w, h);
}

// How far a docked software keyboard covers the window from its bottom edge, in framebuffer
// pixels; 0 while it is hidden or floating. A change arrives as a Resized event.
export function keyboardHeight(): float32 { return voidKeyboardHeight(); }

export function safeArea(): SafeArea {
	return {
		top: voidSafeAreaTop(),
		left: voidSafeAreaLeft(),
		bottom: voidSafeAreaBottom(),
		right: voidSafeAreaRight(),
	};
}

export function requestQuit(): void { voidRequestQuit(); }
export function cancelQuit(): void { voidCancelQuit(); }

export function frameDuration(): float64 { return voidFrameDuration(); }

export function setClipboard(text: string): void { voidSetClipboard(text); }
export function clipboard(): string { return voidClipboard(); }

export function setMouseCursor(cursor: MouseCursor): void { voidSetMouseCursor(cursor as int32); }
export function mouseCursor(): MouseCursor { return voidMouseCursor() as MouseCursor; }
export function showMouse(shown: boolean): void { voidShowMouse(shown ? 1 as int32 : 0 as int32); }
export function mouseShown(): boolean { return voidMouseShown() !== 0; }

export function lockMouse(locked: boolean): void {
	voidLockMouse(locked ? 1 as int32 : 0 as int32);
}
export function mouseLocked(): boolean { return voidMouseLocked() !== 0; }

export function toggleFullscreen(): void { voidToggleFullscreen(); }
export function isFullscreen(): boolean { return voidIsFullscreen() !== 0; }

export function droppedFiles(): string[] {
	const paths: string[] = [];
	const count = voidDroppedFileCount();
	for (let i: int32 = 0; i < count; i++) { paths.push(voidDroppedFilePath(i)); }
	return paths;
}

test "AppEventType and MouseCursor agree member by member with src/platform/appEvent.h" {
	assert (AppEventType.Invalid as int32) == (VoidAppEventType.VOID_EVENT_INVALID as int32);
	assert (AppEventType.KeyDown as int32) == (VoidAppEventType.VOID_EVENT_KEY_DOWN as int32);
	assert (AppEventType.KeyUp as int32) == (VoidAppEventType.VOID_EVENT_KEY_UP as int32);
	assert (AppEventType.Char as int32) == (VoidAppEventType.VOID_EVENT_CHAR as int32);
	assert (AppEventType.MouseDown as int32) == (VoidAppEventType.VOID_EVENT_MOUSE_DOWN as int32);
	assert (AppEventType.MouseUp as int32) == (VoidAppEventType.VOID_EVENT_MOUSE_UP as int32);
	assert (AppEventType.MouseScroll as int32) == (VoidAppEventType.VOID_EVENT_MOUSE_SCROLL as int32);
	assert (AppEventType.MouseMove as int32) == (VoidAppEventType.VOID_EVENT_MOUSE_MOVE as int32);
	assert (AppEventType.MouseEnter as int32) == (VoidAppEventType.VOID_EVENT_MOUSE_ENTER as int32);
	assert (AppEventType.MouseLeave as int32) == (VoidAppEventType.VOID_EVENT_MOUSE_LEAVE as int32);
	assert (AppEventType.TouchesBegan as int32) == (VoidAppEventType.VOID_EVENT_TOUCHES_BEGAN as int32);
	assert (AppEventType.TouchesMoved as int32) == (VoidAppEventType.VOID_EVENT_TOUCHES_MOVED as int32);
	assert (AppEventType.TouchesEnded as int32) == (VoidAppEventType.VOID_EVENT_TOUCHES_ENDED as int32);
	assert (AppEventType.TouchesCancelled as int32) == (VoidAppEventType.VOID_EVENT_TOUCHES_CANCELLED as int32);
	assert (AppEventType.Resized as int32) == (VoidAppEventType.VOID_EVENT_RESIZED as int32);
	assert (AppEventType.Iconified as int32) == (VoidAppEventType.VOID_EVENT_ICONIFIED as int32);
	assert (AppEventType.Restored as int32) == (VoidAppEventType.VOID_EVENT_RESTORED as int32);
	assert (AppEventType.Focused as int32) == (VoidAppEventType.VOID_EVENT_FOCUSED as int32);
	assert (AppEventType.Unfocused as int32) == (VoidAppEventType.VOID_EVENT_UNFOCUSED as int32);
	assert (AppEventType.Suspended as int32) == (VoidAppEventType.VOID_EVENT_SUSPENDED as int32);
	assert (AppEventType.Resumed as int32) == (VoidAppEventType.VOID_EVENT_RESUMED as int32);
	assert (AppEventType.QuitRequested as int32) == (VoidAppEventType.VOID_EVENT_QUIT_REQUESTED as int32);
	assert (AppEventType.ClipboardPasted as int32) == (VoidAppEventType.VOID_EVENT_CLIPBOARD_PASTED as int32);
	assert (AppEventType.FilesDropped as int32) == (VoidAppEventType.VOID_EVENT_FILES_DROPPED as int32);
	assert (AppEventType.Preedit as int32) == (VoidAppEventType.VOID_EVENT_PREEDIT as int32);
	assert (AppEventType.TextInput as int32) == (VoidAppEventType.VOID_EVENT_TEXT_INPUT as int32);
	assert (MouseCursor.Default as int32) == (VoidMouseCursor.VOID_CURSOR_DEFAULT as int32);
	assert (MouseCursor.Arrow as int32) == (VoidMouseCursor.VOID_CURSOR_ARROW as int32);
	assert (MouseCursor.IBeam as int32) == (VoidMouseCursor.VOID_CURSOR_IBEAM as int32);
	assert (MouseCursor.Crosshair as int32) == (VoidMouseCursor.VOID_CURSOR_CROSSHAIR as int32);
	assert (MouseCursor.PointingHand as int32) == (VoidMouseCursor.VOID_CURSOR_POINTING_HAND as int32);
	assert (MouseCursor.ResizeEW as int32) == (VoidMouseCursor.VOID_CURSOR_RESIZE_EW as int32);
	assert (MouseCursor.ResizeNS as int32) == (VoidMouseCursor.VOID_CURSOR_RESIZE_NS as int32);
	assert (MouseCursor.ResizeNWSE as int32) == (VoidMouseCursor.VOID_CURSOR_RESIZE_NWSE as int32);
	assert (MouseCursor.ResizeNESW as int32) == (VoidMouseCursor.VOID_CURSOR_RESIZE_NESW as int32);
	assert (MouseCursor.ResizeAll as int32) == (VoidMouseCursor.VOID_CURSOR_RESIZE_ALL as int32);
	assert (MouseCursor.NotAllowed as int32) == (VoidMouseCursor.VOID_CURSOR_NOT_ALLOWED as int32);
}
