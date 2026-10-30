@passC("-DVOID_PROFILER");

import {
	frameClock, profileNow, profilePresent, MARK_BEGIN, MARK_COMMIT, MARK_PRESENT_START, MARK_PRESENT_END,
	COUNTER_DRAWS, COUNTER_UI_INSTANCES, COUNTER_SPRITE_INSTANCES, COUNTER_UPLOAD_BYTES,
	COUNTER_UPLOADS, COUNTER_COVERED_PIXELS, COUNTER_TARGET_PIXELS, COUNTER_OPAQUE_PIXELS,
	COUNTER_FRAME_PIXELS, COUNTER_SOKOL_DRAWS, COUNTER_SOKOL_PIPELINES, COUNTER_SOKOL_PASSES,
	COUNTER_SOKOL_BUFFER_BYTES, COUNTER_SOKOL_IMAGE_BYTES, COUNTER_SOKOL_MEASURED,
	FRAME_OPEN, FRAME_COMMITTED, FRAME_PRESENTED,
} from "./frameClock";
when (c) {
	import "./frameClockExports";
}
import { setPresentHook } from "../gpu/frameCommit";
import {
	NO_STAMP, FrameProfiler, FrameRecord, FrameCounters, FramePhase, frameProfiler, noCounters,
	invalidated, inputBegin, drawBegin, commit, present,
} from "./profiler";

const NO_RECORD: FrameRecord = {
	serial: 0,
	drawNs: 0,
	presentNs: 0,
	dirtyToPresentNs: NO_STAMP,
	invalidations: 0,
	inputLatencyNs: NO_STAMP,
	inputEvents: 0,
	droppedInputs: 0,
};

export struct FrameCoverage {
	coveredPixels: int32;
	targetPixels: int32;
	opaquePixels: int32;
	framePixels: int32;
}

export function overdraw(c: FrameCoverage): float64 {
	return c.framePixels > 0 ? (c.coveredPixels as float64) / (c.framePixels as float64) : 0.0;
}

export const frameStats: FrameProfiler = frameProfiler();
let lastRecord: FrameRecord = NO_RECORD;
let lastCounters: FrameCounters = noCounters();
let lastCoverage: FrameCoverage = { coveredPixels: 0, targetPixels: 0, opaquePixels: 0, framePixels: 0 };
let lastSerial: int32 = 0;
let commitsWithoutFrame: int32 = 0;

export function profilerSetup(): void {
	setPresentHook(profilePresent);
}

export function profilerNow(): int64 { return profileNow(); }

export function lastFrameRecord(): FrameRecord { return lastRecord; }
export function lastFrameCounters(): FrameCounters { return lastCounters; }
export function lastFrameCoverage(): FrameCoverage { return lastCoverage; }
export function frameCommitsWithoutFrame(): int32 { return commitsWithoutFrame; }
export function frameMarksLost(): int32 { return frameClock.lost; }

function readCounters(): FrameCounters {
	return {
		void2dDraws: frameClock.counter(COUNTER_DRAWS),
		uiInstances: frameClock.counter(COUNTER_UI_INSTANCES),
		spriteInstances: frameClock.counter(COUNTER_SPRITE_INSTANCES),
		uploadBytes: frameClock.counter(COUNTER_UPLOAD_BYTES),
		uploads: frameClock.counter(COUNTER_UPLOADS),
		sokolMeasured: frameClock.counter(COUNTER_SOKOL_MEASURED) != 0,
		sokolDraws: frameClock.counter(COUNTER_SOKOL_DRAWS),
		sokolPipelines: frameClock.counter(COUNTER_SOKOL_PIPELINES),
		sokolPasses: frameClock.counter(COUNTER_SOKOL_PASSES),
		sokolBufferBytes: frameClock.counter(COUNTER_SOKOL_BUFFER_BYTES),
		sokolImageBytes: frameClock.counter(COUNTER_SOKOL_IMAGE_BYTES),
	};
}

function takeDroppedInputs(): void {
	const dropped: int32 = frameClock.takeDroppedInputs();
	const now: int64 = profileNow();
	for (let i: int32 = 0; i < dropped; i++) { frameStats.inputBegin(now); }
}

function takePendingInputs(): void {
	const pending: int32 = frameClock.takePendingInputs();
	if (pending == 0) { return; }
	const first: int64 = frameClock.firstInput;
	for (let i: int32 = 0; i < pending; i++) { frameStats.inputBegin(first); }
}

export function profilerCollect(): boolean {
	const state: int32 = frameClock.state;
	if (state != FRAME_COMMITTED && state != FRAME_PRESENTED) { return false; }
	if (frameStats.phase != FramePhase.Drawing) {
		console.log(
			`void2d profiler: frame ${frameClock.serial} was committed but its begin was never ` +
			"seen; the begin mark and profilerFrameOpened must come from the same bracket",
		);
		unreachable;
	}
	takeDroppedInputs();
	const serial: int32 = frameClock.serial;
	if (lastSerial != 0 && serial - lastSerial > 1) {
		const gap: int32 = serial - lastSerial - 1;
		if (commitsWithoutFrame == 0) {
			console.log(
				`void2d profiler: ${gap} commit(s) between frame serial ${lastSerial} and ` +
				`${serial} had no void2d frame; later ones are counted without a line`,
			);
		}
		commitsWithoutFrame = commitsWithoutFrame + gap;
	}
	lastSerial = serial;
	const commitAt: int64 = frameClock.mark(MARK_COMMIT);
	frameStats.commit(commitAt);
	let presentStart: int64 = commitAt;
	let presentEnd: int64 = commitAt;
	if (state == FRAME_PRESENTED) {
		presentStart = frameClock.mark(MARK_PRESENT_START);
		presentEnd = frameClock.mark(MARK_PRESENT_END);
	}
	lastRecord = frameStats.present(presentStart, presentEnd);
	lastCounters = readCounters();
	lastCoverage = {
		coveredPixels: frameClock.counter(COUNTER_COVERED_PIXELS),
		targetPixels: frameClock.counter(COUNTER_TARGET_PIXELS),
		opaquePixels: frameClock.counter(COUNTER_OPAQUE_PIXELS),
		framePixels: frameClock.counter(COUNTER_FRAME_PIXELS),
	};
	frameClock.consume();
	return true;
}

export function profilerFrameOpened(): void {
	if (frameStats.phase == FramePhase.Drawing) { return; }
	if (frameClock.state != FRAME_OPEN) {
		console.log(
			`void2d profiler: void2dFrameBegin left the C frame in state ${frameClock.state}, ` +
			"not open",
		);
		unreachable;
	}
	takePendingInputs();
	frameStats.drawBegin(frameClock.mark(MARK_BEGIN));
}

export function profilerInvalidated(): void {
	profilerCollect();
	frameStats.invalidated(profileNow());
}

export function profilerPolledDirty(): void {
	profilerCollect();
	if (frameStats.dirtyAt != NO_STAMP) { return; }
	frameStats.invalidated(profileNow());
}

export function profilerInputBegin(): void {
	profilerCollect();
	frameStats.inputBegin(profileNow());
}
