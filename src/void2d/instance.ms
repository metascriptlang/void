// The per-instance byte layout — P2's single stride, and the arithmetic that decides whether
// one stride is enough.
//
// Two pipelines, as VOID2D.md "P2" states them. The sprite pipeline never runs SDF maths and
// carries only what a textured quad needs. The UI pipeline carries every mode — box, shadow,
// glyph, image, underline, selection — behind one stride and one `mode` field, so a UI subtree
// in tree order is one draw instead of one draw per kind, and so P3 writes the glyph layer
// against a layout that is already final.

import { Color, Transform2D, rgba } from "./types";
import { UI_STRIDE, SPRITE_STRIDE } from "./instanceLayout";

// One per-instance `mode`, read by the fragment stage to pick its branch. The order is the
// order VOID2D.md "P2 — Lands" lists them in, so a reader can diff the two.
export enum InstanceMode {
	Box,
	Shadow,
	Glyph,
	Image,
	Underline,
	Selection,
}

export const UI_MODE_COUNT: int32 = 6;

// WebGL2's per-buffer stride ceiling (MAKEPAD.md:23). Past it, P2's stated fallback is two
// strides — a narrow box/glyph one and a wide one for gradients and shadows. `UI_STRIDE`
// is 108, so the fallback is NOT taken; the test pins that as arithmetic rather than
// leaving it as a thing someone remembers.
export const MAX_WEB_STRIDE: int32 = 255;

export struct UiInstance {
	mode: InstanceMode;
	affine: Transform2D;
	x: float32;
	y: float32;
	w: float32;
	h: float32;
	uvRadii: [float32, float32, float32, float32];
	borders: [float32, float32, float32, float32];
	params: [float32, float32, float32];
	params1: [float32, float32, float32, float32];
	fill: Color;
	border: Color;
	extra: Color;
}

export function uiInstance(
	mode: InstanceMode,
	affine: Transform2D,
	x: float32,
	y: float32,
	w: float32,
	h: float32,
	fill: Color,
): UiInstance {
	const clear: Color = rgba(0.0, 0.0, 0.0, 0.0);
	return {
		mode: mode, affine: affine, x: x, y: y, w: w, h: h,
		uvRadii: [0.0, 0.0, 0.0, 0.0], borders: [0.0, 0.0, 0.0, 0.0], params: [0.0, 0.0, 0.0],
		params1: [0.0, 0.0, 0.0, 0.0], fill: fill, border: clear, extra: clear,
	};
}

// The mode lives in a float lane rather than its own attribute: it costs nothing there and
// keeps the UI pipeline at nine vertex attributes, against the 16 the web intersection gives.
export const UI_PARAM_MODE: int32 = 0;

// Today's path, kept so the T0 test can state the change as a ratio rather than a claim:
// six vertices of eight floats, re-transformed on the CPU every frame.
export const LEGACY_QUAD_BYTES: int32 = 192;

// A colour channel as the GPU will store it. Rounding, not truncation: truncation loses a
// full level at every channel and turns 1.0 into 254. Guardrail 9 needs this to be the same
// arithmetic everywhere, so it lives here and is tested rather than being open-coded in C.
export function packChannel(value: float32): int32 {
	const scaled: float32 = value * 255.0 + 0.5;
	if (scaled <= 0.0) { return 0; }
	if (scaled >= 255.0) { return 255; }
	return scaled as int32;
}

export function uiInstanceBytes(instances: int32): int32 {
	return instances * UI_STRIDE;
}

export function spriteInstanceBytes(instances: int32): int32 {
	return instances * SPRITE_STRIDE;
}

// True when one stride serves every UI mode on the narrowest backend this ships on. False is
// not a failure, it is the trigger for P2's two-stride fallback — so it is a function with a
// reason, not an assertion buried in a comment.
export function oneStrideFitsWeb(): boolean {
	return UI_STRIDE <= MAX_WEB_STRIDE;
}
