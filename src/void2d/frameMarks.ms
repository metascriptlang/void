@passC("-DVOID_PROFILER");

import {
	voidClockNow, voidProfileCompiled, voidProfileSetup, voidProfileState, voidProfileSerial,
	voidProfileLost, voidProfileMark, voidProfileConsume,
	VOID_MARK_BEGIN, VOID_MARK_COMMIT, VOID_MARK_PRESENT_START, VOID_MARK_PRESENT_END,
	VOID_FRAME_OPEN, VOID_FRAME_COMMITTED, VOID_FRAME_PRESENTED,
} from "./frameClock.h";
import { void2dProfilerCompiled } from "./batcher.h";
import {
	NO_STAMP, FrameProfiler, FrameRecord, FramePhase, frameProfiler,
	drawBegin, commit, present,
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
export function frameCommitsWithoutFrame(): int32 { return commitsWithoutFrame; }
export function frameMarksLost(): int32 { return voidProfileLost(); }

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
	const serial: int32 = voidProfileSerial();
	if (lastSerial != 0 && serial - lastSerial > 1) {
		const gap: int32 = serial - lastSerial - 1;
		commitsWithoutFrame = commitsWithoutFrame + gap;
		console.log(
			`void2d profiler: ${gap} commit(s) between frame serial ${lastSerial} and ${serial} ` +
			"had no void2d frame",
		);
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
	frameStats.drawBegin(voidProfileMark(VOID_MARK_BEGIN));
}
