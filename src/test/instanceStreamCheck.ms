// T1 — the instance streams as recorded data, with no GPU (docs/TESTING.md "T1").
//
// `instanceLayoutCheck.ms` says where the fields are. This says the emitter puts them there,
// streams — the bug T1 already caught once for the clip rect, where a stale value survived a
// frame boundary and only showed up as a test depending on what ran before it.

import { Color, rgba, identity2d } from "../void2d/types";
import { InstanceMode, uiInstance } from "../void2d/instance";
import {
	REC_UI_AFFINE, REC_UI_ORIGIN_SIZE, REC_UI_UV_RADII, REC_UI_BORDERS, REC_UI_PARAMS0,
	REC_UI_PARAMS1, REC_UI_COLOR_FILL, REC_UI_COLOR_BORDER, REC_UI_COLOR_EXTRA,
	REC_SPRITE_AFFINE, REC_SPRITE_ORIGIN_SIZE, REC_SPRITE_UV, REC_SPRITE_COLOR,
	UI_STRIDE, SPRITE_STRIDE,
} from "../void2d/instanceLayout";
import {
	resetContext, pushUiInstance, pushSpriteInstance,
	uiInstanceCount, spriteInstanceCount, uiInstanceField, spriteInstanceField,
	uiModeCount, instanceUploadBytes,
} from "../void2d/displayList";

function box(mode: InstanceMode, x: float32, fill: Color): void {
	pushUiInstance({
		...uiInstance(mode, identity2d(), x + 5.0, 2.0 + 7.0, 30.0, 40.0, fill),
		uvRadii: [3.0, 4.0, 5.0, 6.0],
		borders: [1.0, 1.0, 1.0, 1.0],
		params: [7.0, 8.0, 9.0],
		params1: [10.0, 11.0, 12.0, 13.0],
		border: rgba(0.0, 0.0, 0.0, 1.0),
	}, 5.0, 7.0);
}

function sprite(x: float32): void {
	pushSpriteInstance(
		2.0 as float32, 0.0 as float32, 0.0 as float32, 2.0 as float32,
		x, 20.0 as float32, 16.0 as float32, 16.0 as float32,
		0.0 as float32, 0.0 as float32, 1.0 as float32, 1.0 as float32,
		rgba(1.0 as float32, 1.0 as float32, 1.0 as float32, 1.0 as float32),
	);
}

test "a recorded UI instance reads back in every lane it was given" {
	resetContext();
	box(InstanceMode.Box, 1.0 as float32,
		rgba(0.25 as float32, 0.5 as float32, 0.75 as float32, 1.0 as float32));
	assert uiInstanceCount() == 1;
	assert uiInstanceField(0, REC_UI_AFFINE) == (1.0 as float32);
	assert uiInstanceField(0, REC_UI_AFFINE + 3) == (1.0 as float32);
	assert uiInstanceField(0, REC_UI_ORIGIN_SIZE) == (1.0 as float32);
	assert uiInstanceField(0, REC_UI_ORIGIN_SIZE + 2) == (30.0 as float32);
	assert uiInstanceField(0, REC_UI_UV_RADII + 1) == (4.0 as float32);
	assert uiInstanceField(0, REC_UI_BORDERS + 3) == (1.0 as float32);
	assert uiInstanceField(0, REC_UI_PARAMS0 + 1) == (7.0 as float32);
	assert uiInstanceField(0, REC_UI_PARAMS1 + 3) == (13.0 as float32);
	assert uiInstanceField(0, REC_UI_COLOR_FILL) == (0.25 as float32);
	assert uiInstanceField(0, REC_UI_COLOR_FILL + 2) == (0.75 as float32);
	assert uiInstanceField(0, REC_UI_COLOR_BORDER + 3) == (1.0 as float32);
	assert uiInstanceField(0, REC_UI_COLOR_EXTRA + 3) == (0.0 as float32);
}

test "a recorded sprite instance reads back in every lane it was given" {
	resetContext();
	sprite(5.0 as float32);
	assert spriteInstanceCount() == 1;
	assert spriteInstanceField(0, REC_SPRITE_AFFINE) == (2.0 as float32);
	assert spriteInstanceField(0, REC_SPRITE_ORIGIN_SIZE) == (5.0 as float32);
	assert spriteInstanceField(0, REC_SPRITE_UV + 2) == (1.0 as float32);
	assert spriteInstanceField(0, REC_SPRITE_COLOR + 3) == (1.0 as float32);
}

test "instances land at their own index and do not overwrite each other" {
	resetContext();
	box(InstanceMode.Box, 100.0 as float32,
		rgba(1.0 as float32, 0.0 as float32, 0.0 as float32, 1.0 as float32));
	box(InstanceMode.Glyph, 200.0 as float32,
		rgba(0.0 as float32, 1.0 as float32, 0.0 as float32, 1.0 as float32));
	assert uiInstanceCount() == 2;
	assert uiInstanceField(0, REC_UI_ORIGIN_SIZE) == (100.0 as float32);
	assert uiInstanceField(1, REC_UI_ORIGIN_SIZE) == (200.0 as float32);
	assert uiInstanceField(0, REC_UI_COLOR_FILL) == (1.0 as float32);
	assert uiInstanceField(1, REC_UI_COLOR_FILL + 1) == (1.0 as float32);
}

// A2's counter, and A4's negative control for it in one test: the mode count is not a
// constant, it moves with what was recorded, and it reads zero for a mode nothing emitted.
test "the per-mode count moves with what was recorded" {
	resetContext();
	assert uiModeCount(InstanceMode.Box as int32) == 0;
	box(InstanceMode.Box, 0.0 as float32,
		rgba(1.0 as float32, 1.0 as float32, 1.0 as float32, 1.0 as float32));
	assert uiModeCount(InstanceMode.Box as int32) == 1;
	box(InstanceMode.Box, 0.0 as float32,
		rgba(1.0 as float32, 1.0 as float32, 1.0 as float32, 1.0 as float32));
	box(InstanceMode.Shadow, 0.0 as float32,
		rgba(1.0 as float32, 1.0 as float32, 1.0 as float32, 1.0 as float32));
	assert uiModeCount(InstanceMode.Box as int32) == 2;
	assert uiModeCount(InstanceMode.Shadow as int32) == 1;
	assert uiModeCount(InstanceMode.Glyph as int32) == 0;
	assert uiModeCount(InstanceMode.Image as int32) == 0;
	assert uiModeCount(InstanceMode.Underline as int32) == 0;
	assert uiModeCount(InstanceMode.Selection as int32) == 0;
}

// B5 as a negative: a sprite-only frame emits nothing into the UI pipeline at all. A mode
// count cannot say this - zero of every mode is also what an empty frame reads - so the
// assertion is on the stream that would have had to grow.
test "a sprite-only frame records no UI instance" {
	resetContext();
	sprite(1.0 as float32);
	sprite(2.0 as float32);
	sprite(3.0 as float32);
	assert spriteInstanceCount() == 3;
	assert uiInstanceCount() == 0;
}

test "upload bytes are the GPU strides, not the wider record" {
	resetContext();
	assert instanceUploadBytes() == 0;
	box(InstanceMode.Box, 0.0 as float32,
		rgba(1.0 as float32, 1.0 as float32, 1.0 as float32, 1.0 as float32));
	assert instanceUploadBytes() == UI_STRIDE;
	sprite(0.0 as float32);
	assert instanceUploadBytes() == UI_STRIDE + SPRITE_STRIDE;
}

test "resetContext clears both streams, so a frame cannot inherit the last one" {
	resetContext();
	box(InstanceMode.Box, 0.0 as float32,
		rgba(1.0 as float32, 1.0 as float32, 1.0 as float32, 1.0 as float32));
	sprite(0.0 as float32);
	assert uiInstanceCount() == 1;
	assert spriteInstanceCount() == 1;
	resetContext();
	assert uiInstanceCount() == 0;
	assert spriteInstanceCount() == 0;
	assert instanceUploadBytes() == 0;
	assert uiModeCount(InstanceMode.Box as int32) == 0;
}
