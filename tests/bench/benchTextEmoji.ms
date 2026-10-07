// T4 entry: the text scene with an emoji line every eighth line, built with -d:voidColourEmoji,
// for the colour pages and rasterizations after a zoom sweep (docs/VOID2D.md P6 "Colour emoji").

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

function init(): void { benchInit(BenchKind.TextEmoji); }

voidRunConfigured(1280, 720, 1, 0, init, benchFrame);
