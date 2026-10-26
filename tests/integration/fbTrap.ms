import { gfxSetup } from "../../src/host/gpu";
import {
	voidCaptureBackend, voidCaptureGrab, voidCaptureExit,
} from "../capture/capture.h";

@include("../../src/host/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

function init(): void {
	gfxSetup();
}

function frame(): void {
	if (voidCaptureGrab(0) == 0) {
		console.log("the clamped-window trap read back anyway");
		voidCaptureExit(0);
	}
	console.log("a clamped framebuffer cannot be caught through a zero return");
	voidCaptureExit(0);
}

if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
// macOS keeps a 1x1 window as asked and clamps only one larger than the screen.
when (macos) {
	voidRunConfigured(20000, 20000, 1, 0, init, frame);
} else {
	voidRunConfigured(1, 1, 1, 0, init, frame);
}
