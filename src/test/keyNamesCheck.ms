// The DOM key names of the wasm window's keyTable, as the C window.c held it before keyNames.ms
// replaced it, with the key code each gave, and names it left unknown; src/platform/web/keyNames.ms
// must give the same on the native and js targets.

import { KeyCode } from "../platform/appEvent";
import { translateKey } from "../platform/web/keyNames";

struct KeyRow {
	name: string;
	code: int32;
}

const RECORDED_KEYS: KeyRow[] = [
	{ name: "Backspace", code: 259 },
	{ name: "Tab", code: 258 },
	{ name: "Enter", code: 257 },
	{ name: "ShiftLeft", code: 340 },
	{ name: "ShiftRight", code: 344 },
	{ name: "ControlLeft", code: 341 },
	{ name: "ControlRight", code: 345 },
	{ name: "AltLeft", code: 342 },
	{ name: "AltRight", code: 346 },
	{ name: "Pause", code: 284 },
	{ name: "CapsLock", code: 280 },
	{ name: "Escape", code: 256 },
	{ name: "Space", code: 32 },
	{ name: "PageUp", code: 266 },
	{ name: "PageDown", code: 267 },
	{ name: "End", code: 269 },
	{ name: "Home", code: 268 },
	{ name: "ArrowLeft", code: 263 },
	{ name: "ArrowUp", code: 265 },
	{ name: "ArrowRight", code: 262 },
	{ name: "ArrowDown", code: 264 },
	{ name: "PrintScreen", code: 283 },
	{ name: "Insert", code: 260 },
	{ name: "Delete", code: 261 },
	{ name: "Digit0", code: 48 },
	{ name: "Digit1", code: 49 },
	{ name: "Digit2", code: 50 },
	{ name: "Digit3", code: 51 },
	{ name: "Digit4", code: 52 },
	{ name: "Digit5", code: 53 },
	{ name: "Digit6", code: 54 },
	{ name: "Digit7", code: 55 },
	{ name: "Digit8", code: 56 },
	{ name: "Digit9", code: 57 },
	{ name: "KeyA", code: 65 },
	{ name: "KeyB", code: 66 },
	{ name: "KeyC", code: 67 },
	{ name: "KeyD", code: 68 },
	{ name: "KeyE", code: 69 },
	{ name: "KeyF", code: 70 },
	{ name: "KeyG", code: 71 },
	{ name: "KeyH", code: 72 },
	{ name: "KeyI", code: 73 },
	{ name: "KeyJ", code: 74 },
	{ name: "KeyK", code: 75 },
	{ name: "KeyL", code: 76 },
	{ name: "KeyM", code: 77 },
	{ name: "KeyN", code: 78 },
	{ name: "KeyO", code: 79 },
	{ name: "KeyP", code: 80 },
	{ name: "KeyQ", code: 81 },
	{ name: "KeyR", code: 82 },
	{ name: "KeyS", code: 83 },
	{ name: "KeyT", code: 84 },
	{ name: "KeyU", code: 85 },
	{ name: "KeyV", code: 86 },
	{ name: "KeyW", code: 87 },
	{ name: "KeyX", code: 88 },
	{ name: "KeyY", code: 89 },
	{ name: "KeyZ", code: 90 },
	{ name: "MetaLeft", code: 343 },
	{ name: "MetaRight", code: 347 },
	{ name: "Numpad0", code: 320 },
	{ name: "Numpad1", code: 321 },
	{ name: "Numpad2", code: 322 },
	{ name: "Numpad3", code: 323 },
	{ name: "Numpad4", code: 324 },
	{ name: "Numpad5", code: 325 },
	{ name: "Numpad6", code: 326 },
	{ name: "Numpad7", code: 327 },
	{ name: "Numpad8", code: 328 },
	{ name: "Numpad9", code: 329 },
	{ name: "NumpadMultiply", code: 332 },
	{ name: "NumpadAdd", code: 334 },
	{ name: "NumpadSubtract", code: 333 },
	{ name: "NumpadDecimal", code: 330 },
	{ name: "NumpadDivide", code: 331 },
	{ name: "F1", code: 290 },
	{ name: "F2", code: 291 },
	{ name: "F3", code: 292 },
	{ name: "F4", code: 293 },
	{ name: "F5", code: 294 },
	{ name: "F6", code: 295 },
	{ name: "F7", code: 296 },
	{ name: "F8", code: 297 },
	{ name: "F9", code: 298 },
	{ name: "F10", code: 299 },
	{ name: "F11", code: 300 },
	{ name: "F12", code: 301 },
	{ name: "NumLock", code: 282 },
	{ name: "ScrollLock", code: 281 },
	{ name: "Semicolon", code: 59 },
	{ name: "Equal", code: 61 },
	{ name: "Comma", code: 44 },
	{ name: "Minus", code: 45 },
	{ name: "Period", code: 46 },
	{ name: "Slash", code: 47 },
	{ name: "Backquote", code: 96 },
	{ name: "BracketLeft", code: 91 },
	{ name: "Backslash", code: 92 },
	{ name: "BracketRight", code: 93 },
	{ name: "Quote", code: 39 },
];

const UNKNOWN_NAMES: string[] = [
	"",
	"Unidentified",
	"Dead",
	"a",
	"A",
	"Enter ",
	"Numpad",
	"NumpadEnter",
	"IntlBackslash",
	"ContextMenu",
	"F13",
	"AudioVolumeUp",
	"Process",
	"keya",
	"ShiftLeftX",
	"Shift",
	"Meta",
	" ",
];

test "every name of the recorded key table gives the code the C table gave" {
	for (const row of RECORDED_KEYS) {
		assert translateKey(row.name) == row.code;
	}
}

test "a name outside the table is no key" {
	for (const name of UNKNOWN_NAMES) {
		assert translateKey(name) == 0;
	}
}

test "Quote is the apostrophe key and Backquote the grave accent" {
	assert translateKey("Quote") == KeyCode.Apostrophe as int32;
	assert translateKey("Backquote") == KeyCode.GraveAccent as int32;
}
