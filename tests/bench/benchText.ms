// T4 entry: the text scene of src/examples/bench2d.ms — a 40-line code block swept from
// 0.5x to 4x and back, for the atlas bytes after a zoom sweep and the steady-state
// rasterization count (docs/VOID2D.md P3 "Exit").

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

function init(): void { benchInit(BenchKind.Text); }

voidRunConfigured(1280, 720, 1, 0, init, benchFrame);
