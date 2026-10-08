// T4 entry: the text scene with a 2 px outline on every line, swept through zoom, built with
// -d:voidTextOutline, for the outline tiles generated in the sweep and in steady frames and the
// atlas pages and bytes beside tests/bench/benchText.ms (docs/VOID2D.md P6 "Text outline").

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

function init(): void { benchInit(BenchKind.TextOutline); }

voidRunConfigured(1280, 720, 1, 0, init, benchFrame);
