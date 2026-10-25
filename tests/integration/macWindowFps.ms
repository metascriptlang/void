// The frame rate the standalone macOS window runs at: the display's maximum while the window is
// visible, and a steady rate while it is minimised, with the display's rate again once it is
// restored. The test counts the frames the window's own loop delivers.

@include("macWindowHost.h");
@compile("./macWindowHost.m", "-fobjc-arc");
extern function macHostMaxFps(): int32;
extern function macHostNowMs(): float64;
extern function macHostMiniaturize(on: int32): void;
extern function macHostMiniaturized(): int32;
extern function macHostRaise(): void;
extern function macHostWindowVisible(): int32;

import { gfxSetup } from "../../src/sokol/gpu";
import { beginScreenPassWith, endPass, commit } from "../../src/gpu/door";
import { frameDuration } from "../../src/sokol/window";
import { exit } from "std/process";

@include("../../src/sokol/bridge.h");
extern function voidRun(w: int32, h: int32, init: () => void, frame: () => void): void;

const WARM_FRAMES: int32 = 60;
const WINDOW_MS: float64 = 1500.0;
const SETTLE_MS: float64 = 1500.0;
const VISIBLE_SHARE: float64 = 0.9;
const MINIMISED_FLOOR: float64 = 30.0;

let maxFps: int32 = 0;
let frames: int32 = 0;
let step: int32 = 0;
let failures: int32 = 0;
let markMs: float64 = 0.0;
let markFrames: int32 = 0;
let visibleFps: float64 = 0.0;
let minimisedFps: float64 = 0.0;
let restoredFps: float64 = 0.0;

function check(ok: boolean, what: string): void {
	if (ok) return;
	console.log(`FAIL macOS frame rate: ${what}`);
	failures = failures + 1;
}

function init(): void {
	gfxSetup();
	maxFps = macHostMaxFps();
}

function mark(): void {
	markMs = macHostNowMs();
	markFrames = frames;
}

function elapsed(): float64 { return macHostNowMs() - markMs; }

function rate(): float64 { return ((frames - markFrames) as float64) * 1000.0 / elapsed(); }

function advance(): void {
	if (step === 0) {
		if (frames < WARM_FRAMES) return;
		mark();
		step = 1;
	} else if (step === 1) {
		if (elapsed() < WINDOW_MS) return;
		visibleFps = rate();
		check(macHostWindowVisible() === 1, "the window is covered by other windows, so it runs at the hidden rate");
		const dt: float64 = frameDuration();
		check(visibleFps >= (maxFps as float64) * VISIBLE_SHARE, `${visibleFps} fps while visible, the display runs up to ${maxFps}`);
		check(dt <= 1.5 / (maxFps as float64), `frame duration ${dt} s while visible, the display period is ${1.0 / (maxFps as float64)} s`);
		macHostMiniaturize(1);
		mark();
		step = 2;
	} else if (step === 2) {
		if (elapsed() < SETTLE_MS) return;
		mark();
		step = 3;
	} else if (step === 3) {
		if (elapsed() < WINDOW_MS) return;
		minimisedFps = rate();
		check(macHostMiniaturized() === 1, "the window did not minimise");
		check(minimisedFps >= MINIMISED_FLOOR, `${minimisedFps} fps while minimised, want at least ${MINIMISED_FLOOR}`);
		macHostMiniaturize(0);
		macHostRaise();
		mark();
		step = 4;
	} else if (step === 4) {
		if (elapsed() < SETTLE_MS) return;
		mark();
		step = 5;
	} else if (step === 5) {
		if (elapsed() < WINDOW_MS) return;
		restoredFps = rate();
		check(macHostWindowVisible() === 1, "the restored window is covered by other windows, so it runs at the hidden rate");
		check(restoredFps >= (maxFps as float64) * VISIBLE_SHARE, `${restoredFps} fps after restoring, the display runs up to ${maxFps}`);
		if (failures > 0) exit(1);
		console.log(`PASS macOS frame rate: display up to ${maxFps} fps; visible ${visibleFps} fps, minimised ${minimisedFps} fps, restored ${restoredFps} fps`);
		exit(0);
	}
}

function frame(): void {
	frames = frames + 1;
	beginScreenPassWith(0.1, 0.1, 0.15, 1.0);
	endPass();
	commit();
	advance();
}

voidRun(320, 200, init, frame);
