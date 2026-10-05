import { env } from "std/process";
import { contextGeneration, loseContext } from "../../src/gpu/door";
import { initTextured, frameTextured, configureTextured } from "./texturedFrame";
import { voidCaptureBackend, voidCaptureExit } from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const LOST_AT: int32 = 2;
const LAST: int32 = 16;
let frames: int32 = 0;
let firstGeneration: int32 = 0;

function init(): void {
	const preset: string = env.get("VOID_DEVICE_LOSS_PRESET");
	configureTextured(preset.equals("pixelArt"), preset.equals("outlined"), -1);
	initTextured();
	firstGeneration = contextGeneration();
}

function frame(): void {
	frameTextured(frames);
	if (frames == LOST_AT) { loseContext(); }
	if (frames == LAST) {
		if (contextGeneration() != firstGeneration + 1) {
			console.log(`FAIL device loss 3d: the context generation is ${contextGeneration()}, ` +
				`not ${firstGeneration + 1}`);
			voidCaptureExit(1);
		}
		console.log("PASS device loss 3d: the textured frame's checks held across a forced loss");
		voidCaptureExit(0);
	}
	frames = frames + 1;
}

if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
voidRunConfigured(320, 240, 1, 0, init, frame);
