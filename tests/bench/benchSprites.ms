// T4 entry: the sprite-only scene of src/examples/bench2d.ms — 10 000 sprites on one
// texture, one draw call. It is the guardrail-8 control: "a sprite-only scene must not
// regress at any step", so this row is what says a change paid only for what uses it.
//
// sample_count 1 and high_dpi 0, as in tests/golden/runner.ms: the numbers then do not
// depend on the host display, and they are comparable with iOS, Android and the embed
// bridges, none of which turn MSAA on.

import { benchInit, benchFrame, BenchKind } from "../../src/examples/bench2d";

@include("../../src/sokol/bridge.h");

extern function voidRunConfigured(
	w: int32,
	h: int32,
	sampleCount: int32,
	highDpi: int32,
	init: () => void,
	frame: () => void,
): void;

function init(): void { benchInit(BenchKind.Sprites); }

voidRunConfigured(1280, 720, 1, 0, init, benchFrame);
