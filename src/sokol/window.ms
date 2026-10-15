// The sokol_app window's events and title, on the window drivers: Windows (D3D11 and
// -d:voidGlCore) and the browser. Import beside ./gpu, which compiles their C.

@include("bridge.h");

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
extern function voidSetWindowTitle(title: cstring): void;

// The ordinals of sokol_app.h's sapp_event_type: keep the order.
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
}

let _handler: ((e: AppEvent) => void) | null = null;

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
	};
}

function dispatchEvent(): void {
	(_handler as (e: AppEvent) => void)(currentEvent());
}

// Every sokol_app event reaches `handler`, Escape included: once one is set, Escape no
// longer quits the app. Call it before voidRun or from its init closure.
export function onAppEvent(handler: (e: AppEvent) => void): void {
	_handler = handler;
	voidSetEventHandler(dispatchEvent);
}

export function setWindowTitle(title: string): void { voidSetWindowTitle(title); }
