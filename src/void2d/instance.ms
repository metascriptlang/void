// The sprite pipeline carries only what a textured quad needs. The UI pipeline carries every
// mode behind one stride and one `mode` field, so a UI subtree in tree order is one draw.

import { Color, Transform2D, rgba } from "./types";
import { UI_STRIDE, SPRITE_STRIDE } from "./instanceLayout";

// The fragment stage branches on these ordinals, so the order is shared with the shader.
export enum InstanceMode {
	Box,
	Shadow,
	Glyph,
	Image,
	Underline,
	Selection,
}

export const UI_MODE_COUNT: int32 = 6;

// WebGL2's per-buffer stride ceiling (docs/MAKEPAD.md:23).
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

export const SDF_GLYPH_FLAG: float32 = 1.0;

// What the vertex path writes per quad: six vertices of eight floats.
export const LEGACY_QUAD_BYTES: int32 = 192;

// A colour channel as the GPU will store it. Rounding, not truncation: truncation loses a
// full level at every channel and turns 1.0 into 254.
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

// False is not a failure: it triggers the two-stride fallback (a narrow box/glyph stride and a
// wide one for gradients and shadows).
export function oneStrideFitsWeb(): boolean {
	return UI_STRIDE <= MAX_WEB_STRIDE;
}
