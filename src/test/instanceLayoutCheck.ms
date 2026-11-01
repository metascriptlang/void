// T0 — P2's instance layout as arithmetic (docs/TESTING.md "T0").
//
// The stride decides the phase's stated fallback: past WebGL2's 255-byte ceiling, P2 splits
// into two strides. That decision is arithmetic, so it is asserted here rather than recalled
// from a comment. The stride the door is handed is the registered layout's arrayStride,
// compared with the emitter's claim in instanceAttributeCheck.ms.

import {
	InstanceMode, UI_MODE_COUNT, MAX_WEB_STRIDE, LEGACY_QUAD_BYTES,
	uiInstanceBytes, spriteInstanceBytes, oneStrideFitsWeb, packChannel,
} from "../void2d/instance";
import {
	UI_AFFINE, UI_ORIGIN_SIZE, UI_UV_RADII, UI_BORDERS, UI_PARAMS0, UI_PARAMS1,
	UI_CLIP_RECT, UI_COLOR_FILL, UI_COLOR_BORDER, UI_COLOR_EXTRA, UI_STRIDE, UI_ATTRIBUTES,
	SPRITE_AFFINE, SPRITE_ORIGIN_SIZE, SPRITE_UV, SPRITE_COLOR, SPRITE_STRIDE,
	SPRITE_ATTRIBUTES,
	REC_SPRITE_AFFINE, REC_SPRITE_ORIGIN_SIZE, REC_SPRITE_UV, REC_SPRITE_COLOR, REC_SPRITE_FLOATS,
	WORD_UI_AFFINE, WORD_UI_ORIGIN_SIZE, WORD_UI_UV_RADII, WORD_UI_BORDERS, WORD_UI_PARAMS0,
	WORD_UI_PARAMS1, WORD_UI_CLIP_RECT, WORD_UI_COLOR_FILL, WORD_UI_COLOR_BORDER,
	WORD_UI_COLOR_EXTRA, UI_WORDS,
} from "../void2d/instanceLayout";
import { floatBits, floatOfBits } from "../void2d/floatBits";

const FLOAT4: int32 = 16;
const UBYTE4N: int32 = 4;

test "UI fields are laid out end to end with no gap and no overlap" {
	assert UI_AFFINE == 0;
	assert UI_ORIGIN_SIZE == UI_AFFINE + FLOAT4;
	assert UI_UV_RADII == UI_ORIGIN_SIZE + FLOAT4;
	assert UI_BORDERS == UI_UV_RADII + FLOAT4;
	assert UI_PARAMS0 == UI_BORDERS + FLOAT4;
	assert UI_PARAMS1 == UI_PARAMS0 + FLOAT4;
	assert UI_CLIP_RECT == UI_PARAMS1 + FLOAT4;
	assert UI_COLOR_FILL == UI_CLIP_RECT + FLOAT4;
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
	assert UI_CLIP_RECT % 4 == 0;
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
	assert UI_STRIDE == 124;
}

test "both pipelines stay inside the sixteen vertex attributes the web intersection gives" {
	assert UI_ATTRIBUTES == 10;
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
	assert uiInstanceBytes(20000) == 2480000;
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

// ---------------------------------------------------------------------------------------
// The record stream against the GPU stride. Two layouts, one field order — asserted, because
// the emitter writes one and the GPU reads the other and nothing else connects them.

test "every UI word offset is its GPU byte offset over four" {
	assert WORD_UI_AFFINE * 4 == UI_AFFINE;
	assert WORD_UI_ORIGIN_SIZE * 4 == UI_ORIGIN_SIZE;
	assert WORD_UI_UV_RADII * 4 == UI_UV_RADII;
	assert WORD_UI_BORDERS * 4 == UI_BORDERS;
	assert WORD_UI_PARAMS0 * 4 == UI_PARAMS0;
	assert WORD_UI_PARAMS1 * 4 == UI_PARAMS1;
	assert WORD_UI_CLIP_RECT * 4 == UI_CLIP_RECT;
	assert WORD_UI_COLOR_FILL * 4 == UI_COLOR_FILL;
	assert WORD_UI_COLOR_BORDER * 4 == UI_COLOR_BORDER;
	assert WORD_UI_COLOR_EXTRA * 4 == UI_COLOR_EXTRA;
	assert UI_WORDS * 4 == UI_STRIDE;
	assert UI_WORDS == 31;
}

test "floatOfBits undoes floatBits on every float lane value" {
	const values: float32[] = [0.0, -0.0, 1.0, -1.5, 0.1, 3.4e38, 1.0e-45, 255.0];
	for (const v of values) {
		assert floatOfBits(floatBits(v)) == v;
		assert floatBits(floatOfBits(floatBits(v))) == floatBits(v);
	}
	assert floatOfBits(0x3F800000) == 1.0;
	assert floatBits(floatOfBits(0x80000000)) == 0x80000000;
}

test "the sprite record and its GPU stride are the same bytes, since nothing is packed" {
	assert REC_SPRITE_AFFINE * 4 == SPRITE_AFFINE;
	assert REC_SPRITE_ORIGIN_SIZE * 4 == SPRITE_ORIGIN_SIZE;
	assert REC_SPRITE_UV * 4 == SPRITE_UV;
	assert REC_SPRITE_COLOR * 4 == SPRITE_COLOR;
	assert REC_SPRITE_FLOATS * 4 == SPRITE_STRIDE;
}

// Guardrail 9 is "same pixels on every platform", so the colour pack is arithmetic with one
// definition, not a cast that rounds differently in two places.
test "packChannel rounds and clamps instead of truncating" {
	assert packChannel(0.0 as float32) == 0;
	assert packChannel(1.0 as float32) == 255;
	assert packChannel(0.5 as float32) == 128;
	assert packChannel(-1.0 as float32) == 0;
	assert packChannel(2.0 as float32) == 255;
}

test "packChannel never loses the top level the way truncation does" {
	assert packChannel(0.999 as float32) == 255;
	assert packChannel((1.0 / 255.0) as float32) == 1;
}

