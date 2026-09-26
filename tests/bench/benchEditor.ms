// T4 entry: the editor scene of src/examples/bench2d.ms - 200 lines of 80 columns with syntax
// runs, a selection and a caret (docs/VOID2D.md P4 "Measure").

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

function init(): void { benchInit(BenchKind.Editor); }

voidRunConfigured(1280, 720, 1, 0, init, benchFrame);
