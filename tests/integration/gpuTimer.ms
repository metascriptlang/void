import { env } from "std/process";
import { gfxSetup } from "../../src/sokol/gpu";
import { contextGeneration, loseContext } from "../../src/gpu/door";
import {
	doorEnableGpuTimer,
	doorFrameStat,
	DOOR_STAT_PASSES,
	doorGpuTimerState,
	doorGpuTimerFrame,
	doorGpuTimerPassCount,
	doorGpuTimerPassMs,
	doorGpuTimerPassLabel,
} from "../../src/gpu/doorGpu.ms";
import { GPU_TIMER_ON, GPU_TIMER_RING, GPU_TIMER_UNSUPPORTED } from "../../src/gpu/gpuTimer.ms";
import { Scene2D } from "../../src/void2d/node";
import { create } from "../../src/void2d/scene";
import { setup2d } from "../../src/void2d/draw";
import { rgba, outlineFilter } from "../../src/void2d/types";
import { voidCaptureBackend, voidCaptureExit } from "../capture/capture.h";

@include("../../src/sokol/bridge.h");
extern function voidRunConfigured(
	w: int32, h: int32, sampleCount: int32, highDpi: int32,
	init: () => void, frame: () => void,
): void;

const FIRST_FRAME_PASSES: int32 = 3;
const FRAMES: int32 = 8;
const LOSS_AT: int32 = FRAMES;
const scene: Scene2D = Scene2D.create(rgba(0.05, 0.05, 0.1, 1.0));
const ONE_SECOND_MS: float64 = 1000.0;
const RING: int64 = GPU_TIMER_RING as int64;

let callback: int32 = 0;
let passesOf: Vec<int32> = [];
let firstGeneration: int32 = 0;
let framesSinceLoss: int32 = 0;

function fail(message: string): void {
	console.log(`FAIL gpu timer: frame ${callback}: ${message}`);
	voidCaptureExit(1);
}

function maxPasses(): int32 {
	const given = env.get("VOID_GPU_TIMER_MAX");
	return given.equals("") ? FIRST_FRAME_PASSES : (parseInt(given) as int32);
}

function init(): void {
	if (voidCaptureBackend() == 0) { voidCaptureExit(3); }
	gfxSetup();
	setup2d();
	scene.add(scene.rect(40.0, 40.0, rgba(0.9, 0.1, 0.1, 1.0)).at(8.0, 8.0));
	scene.add(scene.rect(40.0, 40.0, rgba(0.2, 0.3, 1.0, 1.0)).at(80.0, 40.0)).setFilter(outlineFilter(rgba(1.0, 1.0, 1.0, 1.0), 2.0, 1.0));
	const state = doorEnableGpuTimer(maxPasses());
	if (state == GPU_TIMER_UNSUPPORTED) {
		console.log("SKIP gpu timer: this device has no timestamp-query, the timer reports unsupported");
		voidCaptureExit(0);
		return;
	}
	if (state != GPU_TIMER_ON) { fail("the timer is not on after enable"); }
}

function checkLag(counted: int32): void {
	const expected: int64 = (counted as int64) - RING;
	if (counted < (GPU_TIMER_RING as int32)) {
		if (doorGpuTimerFrame() != -1) { fail(`a result at ${counted} frames, before the ring has filled`); }
		return;
	}
	if (doorGpuTimerFrame() != expected) {
		fail(`the result belongs to frame ${doorGpuTimerFrame()}, expected ${expected}: lag is not ${GPU_TIMER_RING - 1}`);
	}
	const drawn = passesOf[doorGpuTimerFrame() as int32];
	if (doorGpuTimerPassCount() != drawn) {
		fail(`${doorGpuTimerPassCount()} passes in the result of frame ${doorGpuTimerFrame()}, the door counted ${drawn}`);
	}
	for (let i: int32 = 0; i < doorGpuTimerPassCount(); i++) {
		const ms = doorGpuTimerPassMs(i);
		if (!(ms > 0.0) || !(ms < ONE_SECOND_MS)) { fail(`pass ${i} (${doorGpuTimerPassLabel(i)}) took ${ms} ms`); }
	}
}

function frame(): void {
	if (callback == LOSS_AT + 1) { passesOf.length = 0; }
	if (callback > 0 && callback != LOSS_AT + 1) { passesOf.push(doorFrameStat(DOOR_STAT_PASSES) as int32); }
	if (callback == LOSS_AT) {
		firstGeneration = contextGeneration();
		callback = callback + 1;
		loseContext();
		scene.present();
		return;
	}
	if (callback == LOSS_AT + 1) {
		if (contextGeneration() != firstGeneration + 1) { fail("the context was not rebuilt"); }
		if (doorGpuTimerState() != GPU_TIMER_ON) { fail("the timer did not survive the loss"); }
		if (doorGpuTimerFrame() != -1) { fail("the timer kept a result from before the loss"); }
	}
	const counted = callback <= LOSS_AT ? callback : framesSinceLoss;
	checkLag(counted);
	if (callback == LOSS_AT + 2 + FRAMES) {
		console.log(`PASS gpu timer: 3 passes on the first frame, results lag ${GPU_TIMER_RING - 1} frames, last frame ${doorGpuTimerFrame()}, pass 0 ${doorGpuTimerPassMs(0)} ms, rebuilt after a loss`);
		voidCaptureExit(0);
		return;
	}
	scene.present();
	if (callback > LOSS_AT) { framesSinceLoss = framesSinceLoss + 1; }
	callback = callback + 1;
}

voidRunConfigured(160, 120, 1, 0, init, frame);
