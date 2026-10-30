// The window event Void's platform layer delivers, for the MetaScript side. Ordinals, keycodes,
// modifier bits and mouse buttons are sokol_app.h's (pin 2e75443d); the keycodes are GLFW's.
// src/platform/appEvent.h is the C side of the same contract and src/test/appEventPortCheck.ms
// holds the two to each other.

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

export enum KeyCode {
	Invalid = 0,
	Space = 32,
	Apostrophe = 39,
	Comma = 44,
	Minus = 45,
	Period = 46,
	Slash = 47,
	Digit0 = 48,
	Digit1 = 49,
	Digit2 = 50,
	Digit3 = 51,
	Digit4 = 52,
	Digit5 = 53,
	Digit6 = 54,
	Digit7 = 55,
	Digit8 = 56,
	Digit9 = 57,
	Semicolon = 59,
	Equal = 61,
	A = 65,
	B = 66,
	C = 67,
	D = 68,
	E = 69,
	F = 70,
	G = 71,
	H = 72,
	I = 73,
	J = 74,
	K = 75,
	L = 76,
	M = 77,
	N = 78,
	O = 79,
	P = 80,
	Q = 81,
	R = 82,
	S = 83,
	T = 84,
	U = 85,
	V = 86,
	W = 87,
	X = 88,
	Y = 89,
	Z = 90,
	LeftBracket = 91,
	Backslash = 92,
	RightBracket = 93,
	GraveAccent = 96,
	World1 = 161,
	World2 = 162,
	Escape = 256,
	Enter = 257,
	Tab = 258,
	Backspace = 259,
	Insert = 260,
	Delete = 261,
	Right = 262,
	Left = 263,
	Down = 264,
	Up = 265,
	PageUp = 266,
	PageDown = 267,
	Home = 268,
	End = 269,
	CapsLock = 280,
	ScrollLock = 281,
	NumLock = 282,
	PrintScreen = 283,
	Pause = 284,
	F1 = 290,
	F2 = 291,
	F3 = 292,
	F4 = 293,
	F5 = 294,
	F6 = 295,
	F7 = 296,
	F8 = 297,
	F9 = 298,
	F10 = 299,
	F11 = 300,
	F12 = 301,
	F13 = 302,
	F14 = 303,
	F15 = 304,
	F16 = 305,
	F17 = 306,
	F18 = 307,
	F19 = 308,
	F20 = 309,
	F21 = 310,
	F22 = 311,
	F23 = 312,
	F24 = 313,
	F25 = 314,
	Keypad0 = 320,
	Keypad1 = 321,
	Keypad2 = 322,
	Keypad3 = 323,
	Keypad4 = 324,
	Keypad5 = 325,
	Keypad6 = 326,
	Keypad7 = 327,
	Keypad8 = 328,
	Keypad9 = 329,
	KeypadDecimal = 330,
	KeypadDivide = 331,
	KeypadMultiply = 332,
	KeypadSubtract = 333,
	KeypadAdd = 334,
	KeypadEnter = 335,
	KeypadEqual = 336,
	LeftShift = 340,
	LeftControl = 341,
	LeftAlt = 342,
	LeftSuper = 343,
	RightShift = 344,
	RightControl = 345,
	RightAlt = 346,
	RightSuper = 347,
	Menu = 348,
}

export enum MouseButton {
	Left = 0x0,
	Right = 0x1,
	Middle = 0x2,
	Invalid = 0x100,
}

export const EVENT_COUNT: int32 = 26;
export const CURSOR_COUNT: int32 = 11;
export const KEY_COUNT: int32 = 512;
export const MAX_TOUCHPOINTS: int32 = 8;
export const MODIFIER_SHIFT: uint32 = 0x1;
export const MODIFIER_CTRL: uint32 = 0x2;
export const MODIFIER_ALT: uint32 = 0x4;
export const MODIFIER_SUPER: uint32 = 0x8;
export const MODIFIER_LMB: uint32 = 0x100;
export const MODIFIER_RMB: uint32 = 0x200;
export const MODIFIER_MMB: uint32 = 0x400;

export struct NativeTouchPoint {
	identifier: uint64;
	x: float32;
	y: float32;
	changed: boolean;
}

export struct NativeAppEvent {
	frameCount: uint64;
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
	windowWidth: int32;
	windowHeight: int32;
	framebufferWidth: int32;
	framebufferHeight: int32;
	touchCount: int32;
	touches: NativeTouchPoint[8];
}

export function blankAppEvent(type: AppEventType): NativeAppEvent {
	const untouched: NativeTouchPoint = { identifier: 0, x: 0, y: 0, changed: false };
	return {
		frameCount: 0,
		type: type,
		keyCode: 0,
		charCode: 0,
		keyRepeat: false,
		modifiers: 0,
		mouseButton: 0,
		mouseX: 0,
		mouseY: 0,
		mouseDx: 0,
		mouseDy: 0,
		scrollX: 0,
		scrollY: 0,
		windowWidth: 0,
		windowHeight: 0,
		framebufferWidth: 0,
		framebufferHeight: 0,
		touchCount: 0,
		touches: [untouched, untouched, untouched, untouched, untouched, untouched, untouched, untouched],
	};
}

export class KeysHeld {
	down: boolean[] = [];

	constructor() {
		for (let key: int32 = 0; key < KEY_COUNT; key++) { this.down.push(false); }
	}

	track(type: AppEventType, key: int32): void {
		if (key <= 0 || key >= KEY_COUNT) { return; }
		if (type == AppEventType.KeyDown) { this.down[key] = true; }
		else if (type == AppEventType.KeyUp) { this.down[key] = false; }
	}

	isDown(key: int32): boolean { return key > 0 && key < KEY_COUNT && this.down[key]; }

	release(keyUp: (key: int32) => void): void {
		for (let key: int32 = 1; key < KEY_COUNT; key++) {
			if (!this.down[key]) { continue; }
			this.down[key] = false;
			keyUp(key);
		}
	}
}
