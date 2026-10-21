// The window's events, IME and title, on the window drivers: Windows (D3D11 and
// -d:voidGlCore), the browser and the iOS app. Import beside ./gpu, which compiles their C.

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

let _handler: ((e: AppEvent) => void) | null = null;

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
	(_handler as (e: AppEvent) => void)(currentEvent());
}

// Every window event reaches `handler`, Escape included: once one is set, Escape no
// longer quits the app. Call it before voidRun or from its init closure.
export function onAppEvent(handler: (e: AppEvent) => void): void {
	_handler = handler;
	voidSetEventHandler(dispatchEvent);
}

export function setWindowTitle(title: string): void { voidSetWindowTitle(title); }

// While on, an IME composition reaches the event handler as Preedit events (`text` with its
// caret `cursor` in UTF-16 units; an empty text ends it) and its result as one TextInput
// event, never also as Char.
export function setTextInput(on: boolean): void { voidSetTextInput(on ? 1 as int32 : 0 as int32); }

// The caret the candidate window opens below, in framebuffer pixels.
export function setImeRect(x: int32, y: int32, w: int32, h: int32): void { voidSetImeRect(x, y, w, h); }

export function safeArea(): SafeArea {
	return {
		top: voidSafeAreaTop(),
		left: voidSafeAreaLeft(),
		bottom: voidSafeAreaBottom(),
		right: voidSafeAreaRight(),
	};
}
