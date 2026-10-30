// The text-input decisions bridgeWeb.c held in s_textInput, s_imeX..H, imeTookKey and
// keepKeysFromBrowser, as rows read from that C before imeInput.ms replaced it (read, not run):
// src/platform/web/imeInput.ms must give the same on the native and js targets.

import { AppEventType } from "../platform/appEvent";
import { ImeInput } from "../platform/web/imeInput";

function near(a: float64, b: float64): boolean { return Math.abs(a - b) < 1e-12; }

test "text input is unset until the app sets it, and any nonzero value is on" {
	let ime = new ImeInput();
	assert ime.textInput == -1;
	ime.setTextInput(7);
	assert ime.textInput == 1;
	ime.setTextInput(0);
	assert ime.textInput == 0;
	ime.setTextInput(-3);
	assert ime.textInput == 1;
}

test "the textarea takes focus only once it exists and text input is set" {
	let ime = new ImeInput();
	assert ime.focus() == -1;
	ime.setTextInput(1);
	assert ime.focus() == -1;
	ime.ready = true;
	assert ime.focus() == 1;
	ime.setTextInput(0);
	assert ime.focus() == 0;
	let unset = new ImeInput();
	unset.ready = true;
	assert unset.focus() == -1;
}

test "the rectangle reaches the textarea in css pixels" {
	let ime = new ImeInput();
	ime.setRect(40, 60, 10, 20);
	const twice = ime.cssRect(2.0);
	assert near(twice[0], 20.0) && near(twice[1], 30.0) && near(twice[2], 5.0) && near(twice[3], 10.0);
	const once = ime.cssRect(1.0);
	assert near(once[0], 40.0) && near(once[1], 60.0) && near(once[2], 10.0) && near(once[3], 20.0);
	const odd = ime.cssRect(1.5);
	assert near(odd[0], 26.666666666666668) && near(odd[1], 40.0) && near(odd[2], 6.666666666666667) && near(odd[3], 13.333333333333334);
	let unset = new ImeInput();
	const zero = unset.cssRect(2.0);
	assert zero[0] == 0.0 && zero[1] == 0.0 && zero[2] == 0.0 && zero[3] == 0.0;
}

test "an IME composition takes only key and char events, and only once the textarea exists" {
	let ime = new ImeInput();
	ime.ready = true;
	for (let kind: int32 = 0; kind <= (AppEventType.TextInput as int32); kind++) {
		const type = kind as AppEventType;
		const taken = type == AppEventType.KeyDown || type == AppEventType.KeyUp || type == AppEventType.Char;
		assert ime.tookKey(true, type) == taken;
		assert !ime.tookKey(false, type);
	}
	let waiting = new ImeInput();
	assert !waiting.tookKey(true, AppEventType.KeyDown);
}

struct KeepRow {
	textInput: int32;
	type: AppEventType;
	keyCode: int32;
	kept: boolean;
}

const KEEP_ROWS: KeepRow[] = [
	{ textInput: -1, type: AppEventType.Char, keyCode: 0, kept: true },
	{ textInput: 0, type: AppEventType.Char, keyCode: 0, kept: true },
	{ textInput: 1, type: AppEventType.Char, keyCode: 0, kept: false },
	{ textInput: -1, type: AppEventType.KeyDown, keyCode: 161, kept: true },
	{ textInput: 0, type: AppEventType.KeyUp, keyCode: 300, kept: true },
	{ textInput: 1, type: AppEventType.KeyDown, keyCode: 161, kept: false },
	{ textInput: 1, type: AppEventType.KeyUp, keyCode: 300, kept: false },
	{ textInput: -1, type: AppEventType.KeyDown, keyCode: 160, kept: false },
	{ textInput: 0, type: AppEventType.KeyUp, keyCode: 65, kept: false },
	{ textInput: 0, type: AppEventType.MouseDown, keyCode: 300, kept: false },
	{ textInput: -1, type: AppEventType.Preedit, keyCode: 300, kept: false },
	{ textInput: 0, type: AppEventType.TextInput, keyCode: 0, kept: false },
];

test "the keys kept from the browser are the chars and the keys from World1 up, until text input is on" {
	for (const row of KEEP_ROWS) {
		let ime = new ImeInput();
		if (row.textInput != -1) { ime.setTextInput(row.textInput); }
		assert ime.keepsFromBrowser(row.type, row.keyCode) == row.kept;
	}
}
