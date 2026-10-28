// The browser window's text-input decisions, as bridgeWeb.c held them in s_textInput, s_imeX..H
// and its _event wrapper: whether text input is on, the caret rectangle in framebuffer pixels
// and its CSS form, the keys an IME composition takes, and the keys kept from the browser. The
// wasm window reaches it through imeInputExports.cms and imeInput.h; the js window imports it.

import { AppEventType, KeyCode } from "../appEvent";

const INPUT_UNSET: int32 = -1;

export class ImeInput {
	textInput: int32 = INPUT_UNSET;
	x: int32 = 0;
	y: int32 = 0;
	w: int32 = 0;
	h: int32 = 0;
	ready: boolean = false;

	setTextInput(on: int32): void { this.textInput = on != 0 ? 1 : 0; }

	setRect(x: int32, y: int32, w: int32, h: int32): void {
		this.x = x;
		this.y = y;
		this.w = w;
		this.h = h;
	}

	focus(): int32 { return this.ready && this.textInput != INPUT_UNSET ? this.textInput : INPUT_UNSET; }

	cssRect(scale: float64): float64[] {
		return [
			(this.x as float64) / scale,
			(this.y as float64) / scale,
			(this.w as float64) / scale,
			(this.h as float64) / scale,
		];
	}

	tookKey(composing: boolean, type: AppEventType): boolean {
		return this.ready && composing &&
			(type == AppEventType.KeyDown || type == AppEventType.KeyUp || type == AppEventType.Char);
	}

	keepsFromBrowser(type: AppEventType, keyCode: int32): boolean {
		if (this.textInput == 1) { return false; }
		return type == AppEventType.Char ||
			((type == AppEventType.KeyDown || type == AppEventType.KeyUp) && keyCode >= (KeyCode.World1 as int32));
	}
}
