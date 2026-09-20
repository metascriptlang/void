// T0 — P2's instance layout as arithmetic (docs/TESTING.md "T0").
//
// The stride decides the phase's stated fallback: past WebGL2's 255-byte ceiling, P2 splits
// into two strides. That decision is arithmetic, so it is asserted here rather than recalled
// from a comment. `uiInstanceStride()` and `spriteInstanceStride()` come from `sizeof` in
// batcher.c, so these tests compare the emitter's claim against the bytes sokol is handed —
// change either side alone and this file goes red before a pixel is drawn.

import {
	InstanceMode, UI_MODE_COUNT, MAX_WEB_STRIDE,
	UI_AFFINE, UI_ORIGIN_SIZE, UI_UV_RADII, UI_BORDERS, UI_PARAMS0, UI_PARAMS1,
	UI_COLOR_FILL, UI_COLOR_BORDER, UI_COLOR_EXTRA, UI_STRIDE, UI_ATTRIBUTES,
	SPRITE_AFFINE, SPRITE_ORIGIN_SIZE, SPRITE_UV, SPRITE_COLOR, SPRITE_STRIDE,
	SPRITE_ATTRIBUTES, LEGACY_QUAD_BYTES,
	uiInstanceBytes, spriteInstanceBytes, oneStrideFitsWeb,
} from "../void2d/instance";
import { uiInstanceStride, spriteInstanceStride } from "../void2d/draw";

const FLOAT4: int32 = 16;
const UBYTE4N: int32 = 4;

test "the UI stride the emitter claims is the stride sokol is handed" {
	assert UI_STRIDE == uiInstanceStride();
}

test "the sprite stride the emitter claims is the stride sokol is handed" {
	assert SPRITE_STRIDE == spriteInstanceStride();
}

test "UI fields are laid out end to end with no gap and no overlap" {
	assert UI_AFFINE == 0;
	assert UI_ORIGIN_SIZE == UI_AFFINE + FLOAT4;
	assert UI_UV_RADII == UI_ORIGIN_SIZE + FLOAT4;
	assert UI_BORDERS == UI_UV_RADII + FLOAT4;
	assert UI_PARAMS0 == UI_BORDERS + FLOAT4;
	assert UI_PARAMS1 == UI_PARAMS0 + FLOAT4;
	assert UI_COLOR_FILL == UI_PARAMS1 + FLOAT4;
	assert UI_COLOR_BORDER == UI_COLOR_FILL + UBYTE4N;
	assert UI_COLOR_EXTRA == UI_COLOR_BORDER + UBYTE4N;
	assert UI_STRIDE == UI_COLOR_EXTRA + UBYTE4N;
}

test "sprite fields are laid out end to end with no gap and no overlap" {
	assert SPRITE_AFFINE == 0;
	assert SPRITE_ORIGIN_SIZE == SPRITE_AFFINE + FLOAT4;
	assert SPRITE_UV == SPRITE_ORIGIN_SIZE + FLOAT4;
	assert SPRITE_COLOR == SPRITE_UV + FLOAT4;
	assert SPRITE_STRIDE == SPRITE_COLOR + FLOAT4;
}

test "every UI field starts on a four-byte boundary" {
	assert UI_AFFINE % 4 == 0;
	assert UI_ORIGIN_SIZE % 4 == 0;
	assert UI_UV_RADII % 4 == 0;
	assert UI_BORDERS % 4 == 0;
	assert UI_PARAMS0 % 4 == 0;
	assert UI_PARAMS1 % 4 == 0;
	assert UI_COLOR_FILL % 4 == 0;
	assert UI_COLOR_BORDER % 4 == 0;
	assert UI_COLOR_EXTRA % 4 == 0;
	assert UI_STRIDE % 4 == 0;
}

// The phase's risk line: "past 15 vec4 it breaks WebGL2's 255-byte stride ceiling". This is
// the assertion that says the two-stride fallback is NOT being taken, and the one that will
// go red on the commit that first overflows it — which is the commit that has to take it.
test "one stride serves every UI mode inside WebGL2's ceiling" {
	assert oneStrideFitsWeb();
	assert UI_STRIDE <= MAX_WEB_STRIDE;
	assert UI_STRIDE == 108;
}

test "both pipelines stay inside the sixteen vertex attributes the web intersection gives" {
	assert UI_ATTRIBUTES == 9;
	assert SPRITE_ATTRIBUTES == 4;
	assert UI_ATTRIBUTES + 1 <= 16;
	assert SPRITE_ATTRIBUTES + 1 <= 16;
}

test "the sprite instance is the 64 bytes the roadmap sized it at" {
	assert SPRITE_STRIDE == 64;
}

// Guardrail 8 as a number: a sprite pays the sprite stride and never the UI one.
test "a sprite instance is smaller than a UI instance" {
	assert SPRITE_STRIDE < UI_STRIDE;
}

test "one instance replaces six vertices, so bytes per quad fall either way" {
	assert UI_STRIDE < LEGACY_QUAD_BYTES;
	assert SPRITE_STRIDE < LEGACY_QUAD_BYTES;
	assert LEGACY_QUAD_BYTES == 192;
}

test "instance bytes are linear in the instance count" {
	assert uiInstanceBytes(0) == 0;
	assert uiInstanceBytes(1) == UI_STRIDE;
	assert uiInstanceBytes(20000) == 2160000;
	assert spriteInstanceBytes(10000) == 640000;
}

test "the modes are the six the roadmap lists, distinct and dense from zero" {
	assert (InstanceMode.Box as int32) == 0;
	assert (InstanceMode.Shadow as int32) == 1;
	assert (InstanceMode.Glyph as int32) == 2;
	assert (InstanceMode.Image as int32) == 3;
	assert (InstanceMode.Underline as int32) == 4;
	assert (InstanceMode.Selection as int32) == 5;
	assert UI_MODE_COUNT == 6;
	assert (InstanceMode.Selection as int32) == UI_MODE_COUNT - 1;
}
