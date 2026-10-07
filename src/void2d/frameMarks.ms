@passC("-DVOID_PROFILER");

import {
	voidClockNow, voidProfileCompiled, voidProfileSetup, voidProfileState, voidProfileSerial,
	voidProfileLost, voidProfileMark, voidProfileCounter, voidProfileConsume,
	voidProfileTakePendingInputs, voidProfileTakeDroppedInputs, voidProfileFirstInput,
	VOID_MARK_BEGIN, VOID_MARK_COMMIT, VOID_MARK_PRESENT_START, VOID_MARK_PRESENT_END,
	VOID_COUNTER_DRAWS, VOID_COUNTER_UI_INSTANCES, VOID_COUNTER_SPRITE_INSTANCES,
	VOID_COUNTER_UPLOAD_BYTES, VOID_COUNTER_UPLOADS, VOID_COUNTER_SOKOL_DRAWS,
	VOID_COUNTER_SOKOL_PIPELINES, VOID_COUNTER_SOKOL_PASSES, VOID_COUNTER_SOKOL_BUFFER_BYTES,
	VOID_COUNTER_SOKOL_IMAGE_BYTES, VOID_COUNTER_SOKOL_MEASURED,
	VOID_FRAME_OPEN, VOID_FRAME_COMMITTED, VOID_FRAME_PRESENTED,
} from "./frameClock.h";
import { void2dProfilerCompiled } from "./batcher.h";
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

export const frameStats: FrameProfiler = frameProfiler();
let lastRecord: FrameRecord = NO_RECORD;
let lastCounters: FrameCounters = noCounters();
let lastSerial: int32 = 0;
let commitsWithoutFrame: int32 = 0;
let agreed: boolean = false;

function agree(): void {
	if (agreed) { return; }
	if (voidProfileCompiled() != 1 || void2dProfilerCompiled() != 1) {
		console.log(
			"void2d profiler: MetaScript has the profiler on but the C side was built without " +
			"VOID_PROFILER; build every unit with -d:voidProfiler",
		);
		unreachable;
	}
	agreed = true;
}

export function profilerSetup(): void {
	agree();
	voidProfileSetup();
}

export function profilerNow(): int64 { return voidClockNow(); }

export function lastFrameRecord(): FrameRecord { return lastRecord; }
export function lastFrameCounters(): FrameCounters { return lastCounters; }
export function frameCommitsWithoutFrame(): int32 { return commitsWithoutFrame; }
export function frameMarksLost(): int32 { return voidProfileLost(); }

function readCounters(): FrameCounters {
	return {
		void2dDraws: voidProfileCounter(VOID_COUNTER_DRAWS),
		uiInstances: voidProfileCounter(VOID_COUNTER_UI_INSTANCES),
		spriteInstances: voidProfileCounter(VOID_COUNTER_SPRITE_INSTANCES),
		uploadBytes: voidProfileCounter(VOID_COUNTER_UPLOAD_BYTES),
		uploads: voidProfileCounter(VOID_COUNTER_UPLOADS),
		sokolMeasured: voidProfileCounter(VOID_COUNTER_SOKOL_MEASURED) != 0,
		sokolDraws: voidProfileCounter(VOID_COUNTER_SOKOL_DRAWS),
		sokolPipelines: voidProfileCounter(VOID_COUNTER_SOKOL_PIPELINES),
		sokolPasses: voidProfileCounter(VOID_COUNTER_SOKOL_PASSES),
		sokolBufferBytes: voidProfileCounter(VOID_COUNTER_SOKOL_BUFFER_BYTES),
		sokolImageBytes: voidProfileCounter(VOID_COUNTER_SOKOL_IMAGE_BYTES),
	};
}

function takeDroppedInputs(): void {
	const dropped: int32 = voidProfileTakeDroppedInputs();
	const now: int64 = voidClockNow();
	for (let i: int32 = 0; i < dropped; i++) { frameStats.inputBegin(now); }
}

function takePendingInputs(): void {
	const pending: int32 = voidProfileTakePendingInputs();
	if (pending == 0) { return; }
	const first: int64 = voidProfileFirstInput();
	for (let i: int32 = 0; i < pending; i++) { frameStats.inputBegin(first); }
}

export function profilerCollect(): boolean {
	const state: int32 = voidProfileState();
	if (state != VOID_FRAME_COMMITTED && state != VOID_FRAME_PRESENTED) { return false; }
	if (frameStats.phase != FramePhase.Drawing) {
		console.log(
			`void2d profiler: frame ${voidProfileSerial()} was committed but its begin was never ` +
			"seen; the begin mark and profilerFrameOpened must come from the same bracket",
		);
		unreachable;
	}
	takeDroppedInputs();
	const serial: int32 = voidProfileSerial();
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
	const commitAt: int64 = voidProfileMark(VOID_MARK_COMMIT);
	frameStats.commit(commitAt);
	let presentStart: int64 = commitAt;
	let presentEnd: int64 = commitAt;
	if (state == VOID_FRAME_PRESENTED) {
		presentStart = voidProfileMark(VOID_MARK_PRESENT_START);
		presentEnd = voidProfileMark(VOID_MARK_PRESENT_END);
	}
	lastRecord = frameStats.present(presentStart, presentEnd);
	lastCounters = readCounters();
	voidProfileConsume();
	return true;
}

export function profilerFrameOpened(): void {
	agree();
	if (frameStats.phase == FramePhase.Drawing) { return; }
	if (voidProfileState() != VOID_FRAME_OPEN) {
		console.log(
			`void2d profiler: void2dFrameBegin left the C frame in state ${voidProfileState()}, ` +
			"not open",
		);
		unreachable;
	}
	takePendingInputs();
	frameStats.drawBegin(voidProfileMark(VOID_MARK_BEGIN));
}

export function profilerInvalidated(): void {
	profilerCollect();
	frameStats.invalidated(voidClockNow());
}

export function profilerPolledDirty(): void {
	profilerCollect();
	if (frameStats.dirtyAt != NO_STAMP) { return; }
	frameStats.invalidated(voidClockNow());
}

export function profilerInputBegin(): void {
	profilerCollect();
	frameStats.inputBegin(voidClockNow());
}
