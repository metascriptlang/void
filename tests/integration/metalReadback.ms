// The macOS window readback: a grab after commit() reads the frame, and VOID_READBACK_OPEN=1
// also grabs before it, which reads the same frame.
import { gfxSetup } from "../../src/host/gpu";
import { endPass, commit } from "../../src/gpu/door";
import { beginScreenPass } from "../../src/gpu/target";
import {
	voidCaptureBackend, voidCaptureGrab, voidCapturePixel, voidCaptureExit, voidCaptureEnvInt,
} from "../capture/capture.h";

@include("../../src/host/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const grabOpen: boolean = voidCaptureEnvInt("VOID_READBACK_OPEN", 0) != 0;

function init(): void { gfxSetup(); }
function readBlue(when: string): void {
	if (voidCaptureGrab(0) == 0) {
		console.log(`FAIL metal readback: the grab ${when} commit returned nothing`);
		voidCaptureExit(1);
	}
	const pixel: int64 = voidCapturePixel(0, 10, 10);
	if (pixel != 0x0000FFFF) {
		console.log(`FAIL metal readback: pixel ${pixel} ${when} commit, expected the blue clear`);
		voidCaptureExit(1);
	}
	console.log(`PASS metal readback: a grab ${when} commit reads the cleared frame`);
}
function frame(): void {
	beginScreenPass({ x: 0.0, y: 0.0, z: 1.0, w: 1.0 });
	endPass();
	if (grabOpen) { readBlue("before"); }
	commit();
	readBlue("after");
	voidCaptureExit(0);
}
if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
voidRunConfigured(64, 32, 1, 0, init, frame);
