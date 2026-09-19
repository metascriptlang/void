// T4 entry: the UI scene of src/examples/bench2d.ms — 10 000 cards, each a Rect with a
// Label child. Out of the gitignored out/tmp/bench/, which is why the baseline in
// docs/VOID2D.md could not be reproduced by anyone who did not write it.
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

function init(): void { benchInit(BenchKind.Ui); }

voidRunConfigured(1280, 720, 1, 0, init, benchFrame);
