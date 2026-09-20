// The per-instance byte layout — P2's single stride, and the arithmetic that decides whether
// one stride is enough.
//
// Two pipelines, as VOID2D.md "P2" states them. The sprite pipeline never runs SDF maths and
// carries only what a textured quad needs. The UI pipeline carries every mode — box, shadow,
// glyph, image, underline, selection — behind one stride and one `mode` field, so a UI subtree
// in tree order is one draw instead of one draw per kind, and so P3 writes the glyph layer
// against a layout that is already final.
//
// These constants are a CLAIM. `batcher.c` holds the structs sokol is actually handed, and
// `void2dInstanceLayoutCheck` compares the two at setup — the same mechanism that keeps the
// command layout honest. A field added on one side and not the other fails at setup rather
// than drawing garbage, and the stride below is checked against `sizeof`, never trusted.

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
// below is 108, so the fallback is NOT taken; the test pins that as arithmetic rather than
// leaving it as a thing someone remembers.
export const MAX_WEB_STRIDE: int32 = 255;

// Byte offsets into one UI instance. The affine is carried per instance, not folded into a
// uniform, because the SDF is re-derived in LOCAL space (GPUI.md:35-39) — that is what makes
// a rounded corner survive rotation and scale instead of being baked at record time.
export const UI_AFFINE: int32 = 0;          // float4  a, b, c, d
export const UI_ORIGIN_SIZE: int32 = 16;    // float4  tx, ty, w, h
export const UI_UV_RADII: int32 = 32;       // float4  image u0,v0,u1,v1 | box four radii
export const UI_BORDERS: int32 = 48;        // float4  per-side widths
export const UI_PARAMS0: int32 = 64;        // float4  x = mode, then per-mode params
export const UI_PARAMS1: int32 = 80;        // float4  gradient stops | shadow offset+spread
export const UI_COLOR_FILL: int32 = 96;     // ubyte4n
export const UI_COLOR_BORDER: int32 = 100;  // ubyte4n
export const UI_COLOR_EXTRA: int32 = 104;   // ubyte4n  gradient end | shadow colour
export const UI_STRIDE: int32 = 108;

// The mode lives in a float lane rather than its own attribute: it costs nothing there and
// keeps the UI pipeline at nine vertex attributes, against the 16 the web intersection gives.
export const UI_ATTRIBUTES: int32 = 9;
export const UI_PARAM_MODE: int32 = 0;

export const SPRITE_AFFINE: int32 = 0;       // float4  a, b, c, d
export const SPRITE_ORIGIN_SIZE: int32 = 16; // float4  tx, ty, w, h
export const SPRITE_UV: int32 = 32;          // float4  u0, v0, u1, v1
export const SPRITE_COLOR: int32 = 48;       // float4  straight, not packed
export const SPRITE_STRIDE: int32 = 64;
export const SPRITE_ATTRIBUTES: int32 = 4;

// Today's path, kept so the T0 test can state the change as a ratio rather than a claim:
// six vertices of eight floats, re-transformed on the CPU every frame.
export const LEGACY_QUAD_BYTES: int32 = 192;

// ---------------------------------------------------------------------------------------
// The RECORD layout, which is not the GPU layout, and the two are not allowed to drift
// quietly.
//
// The GPU stride above packs each colour into four bytes. A `Vec<float32>` cannot hold a
// packed RGBA8 — the value exceeds float32's 24-bit mantissa — so the walk records colours
// as four floats each, exactly as the vertex stream already does, and `batcher.c` packs them
// while it copies the frame into the GPU buffer. That is one bridge in one place instead of
// bit-twiddling in the emitter.
//
// So a UI instance is 36 floats on the CPU and 108 bytes on the GPU, and `uploadBytes` counts
// the GPU number because that is what crosses the bus. Both are stated; `instanceLayoutCheck`
// asserts they describe the same fields in the same order.

export const REC_UI_AFFINE: int32 = 0;          // 4 floats
export const REC_UI_ORIGIN_SIZE: int32 = 4;     // 4
export const REC_UI_UV_RADII: int32 = 8;        // 4
export const REC_UI_BORDERS: int32 = 12;        // 4
export const REC_UI_PARAMS0: int32 = 16;        // 4
export const REC_UI_PARAMS1: int32 = 20;        // 4
export const REC_UI_COLOR_FILL: int32 = 24;     // 4 floats -> one ubyte4n
export const REC_UI_COLOR_BORDER: int32 = 28;   // 4 floats -> one ubyte4n
export const REC_UI_COLOR_EXTRA: int32 = 32;    // 4 floats -> one ubyte4n
export const REC_UI_FLOATS: int32 = 36;

export const REC_SPRITE_AFFINE: int32 = 0;
export const REC_SPRITE_ORIGIN_SIZE: int32 = 4;
export const REC_SPRITE_UV: int32 = 8;
export const REC_SPRITE_COLOR: int32 = 12;
export const REC_SPRITE_FLOATS: int32 = 16;

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
