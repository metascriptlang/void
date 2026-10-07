// Imports no node.ms: Yoga has no web branch yet
// (~/metascript/.inbox/yoga/2026-10-03-yogah-has-no-web-branch-voids-wasm-cannot-link-sync.md).
// Shapes one label and places it under a turn and a zoom every frame, so the shaper (-d:voidShaper)
// and the SDF generator (-d:voidSdfText) are linked when their flag is on and absent when it is off.

import { gfxSetup, dpiScale } from "../../src/sokol/gpu";
import { setup2d } from "../../src/void2d/draw";
import { allocateLabelText, shapeLabel, placeLabel, beginGlyphFrame } from "../../src/void2d/labelText";
import { DEFAULT_FONT } from "../../src/void2d/font";
import { Align } from "../../src/void2d/textLayout";
import { trs2d } from "../../src/void2d/types";

@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const LABEL_TEXT: string = "fn layout(width: f32) -> Size { width } // ffi -> =>";

let label: int32 = -1;
let frames: int32 = 0;

function init(): void {
	gfxSetup();
	setup2d();
	label = allocateLabelText();
	shapeLabel(label, LABEL_TEXT, {
		font: DEFAULT_FONT,
		size: 13.0,
		letterSpacing: 0.0,
		lineSpacing: 0.0,
		maxWidth: 0.0,
		align: Align.Left,
	});
}

function frame(): void {
	frames = frames + 1;
	beginGlyphFrame(frames);
	const turn: float32 = (frames as float32) * 0.01;
	placeLabel(label, trs2d(8.0, 8.0, turn, 1.5 + turn, 1.5 + turn), dpiScale());
}

voidRun(640, 360, init, frame);
