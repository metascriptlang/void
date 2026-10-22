// The window's events, IME and title, on the window drivers: Windows (D3D11 and
// -d:voidGlCore), the browser and the iOS and Android apps. Import beside ./gpu, which compiles their C.

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

// The ordinals of VoidAppEventType in src/platform/appEvent.h: keep the order.
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

test "the ordinals of AppEventType and MouseCursor follow src/platform/appEvent.h" {
	assert (AppEventType.Preedit as int32) == 24 && (AppEventType.TextInput as int32) == 25;
	assert (MouseCursor.NotAllowed as int32) == 10;
}
