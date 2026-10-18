// A frame that commits nothing keeps the window's previous picture, and the idle frame loop
// stays paced. Red frames, then one green frame, then only frames that draw nothing.
import { gfxSetup } from "../../src/sokol/gpu";
import { endPass, commit } from "../../src/gpu/door";
import { beginScreenPass } from "../../src/gpu/target";
import {
	voidCaptureGrabWindow, voidCapturePixel, voidCaptureWidth, voidCaptureHeight, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const RED_FRAMES: int32 = 10;
const GREEN_FRAME: int32 = RED_FRAMES + 1;
const IDLE_BEFORE_CAPTURE: int32 = 30;
const CAPTURES: int32 = 4;
const LAST_FRAME: int32 = GREEN_FRAME + IDLE_BEFORE_CAPTURE + CAPTURES;
const MIN_IDLE_MS_PER_FRAME: float64 = 2.0;
const GREEN_RGB: int64 = 0x00FF00;
const RED_RGB: int64 = 0xFF0000;

let frameIndex: int32 = 0;
let idleStart: float64 = 0.0;

function fail(message: string): void {
	console.log(`FAIL skipped frame: ${message}`);
	voidCaptureExit(1);
}

function init(): void {
	gfxSetup();
}

function frame(): void {
	frameIndex++;
	if (frameIndex <= RED_FRAMES) {
		beginScreenPass({ x: 1.0, y: 0.0, z: 0.0, w: 1.0 });
		endPass();
		commit();
		return;
	}
	if (frameIndex == GREEN_FRAME) {
		beginScreenPass({ x: 0.0, y: 1.0, z: 0.0, w: 1.0 });
		endPass();
		commit();
		idleStart = performance.now();
		return;
	}
	if (frameIndex <= GREEN_FRAME + IDLE_BEFORE_CAPTURE) { return; }
	const grabbed: int32 = voidCaptureGrabWindow(0);
	if (grabbed == 0) {
		console.log("SKIP skipped frame: this build has no window capture (Windows only)");
		voidCaptureExit(0);
	}
	if (grabbed < 0) { fail(`idle frame ${frameIndex}: the window capture failed`); }
	const rgb: int64 = voidCapturePixel(0, voidCaptureWidth(0) / 2, voidCaptureHeight(0) / 2) >> 8;
	if (rgb == RED_RGB) { fail(`idle frame ${frameIndex} shows the red frame before the last drawn one`); }
	if (rgb != GREEN_RGB) { fail(`idle frame ${frameIndex} shows ${rgb}, expected the green frame ${GREEN_RGB}`); }
	if (frameIndex < LAST_FRAME) { return; }
	const idleFrames: int32 = LAST_FRAME - GREEN_FRAME;
	const idleMs: float64 = performance.now() - idleStart;
	if (idleMs < idleFrames * MIN_IDLE_MS_PER_FRAME) {
		fail(`${idleFrames} idle frames took ${idleMs} ms: the loop spins without a present to wait on`);
	}
	console.log(`PASS skipped frame: ${CAPTURES} captures over ${idleFrames} idle frames keep the green ` +
		`picture, paced at ${idleMs / idleFrames} ms per frame`);
	voidCaptureExit(0);
}

voidRunConfigured(160, 120, 1, 0, init, frame);
