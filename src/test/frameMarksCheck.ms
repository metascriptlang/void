import { Scene2D } from "../void2d/node";
import { rgba } from "../void2d/types";
import { paint } from "../void2d/scene";
import { begin2d, frameEnd } from "../void2d/draw";
import {
	voidProfilePresent, voidProfileMark, voidProfileState,
	VOID_MARK_BEGIN, VOID_MARK_COMMIT, VOID_MARK_PRESENT_START, VOID_MARK_PRESENT_END,
	VOID_FRAME_IDLE, VOID_FRAME_COMMITTED, VOID_FRAME_PRESENTED,
} from "../void2d/frameClock.h";
import {
	frameStats, profilerCollect, lastFrameRecord, lastFrameCounters, frameCommitsWithoutFrame,
} from "../void2d/frameMarks";

function drawFrame(s: Scene2D): void {
	s.paint(200.0, 100.0, 1.0);
	frameEnd();
	s.clearChanges();
	s.retryRefused();
}

function settled(): Scene2D {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	s.add(s.rect(10.0, 10.0, rgba(1.0, 1.0, 1.0, 1.0)));
	drawFrame(s);
	profilerCollect();
	return s;
}

test "a frame closed by frameEnd becomes one record and is collected once" {
	const s = settled();
	const before: int32 = frameStats.frames;
	drawFrame(s);
	assert voidProfileState() == VOID_FRAME_COMMITTED;
	assert profilerCollect();
	assert !profilerCollect();
	assert voidProfileState() == VOID_FRAME_IDLE;
	assert frameStats.frames == before + 1;
	assert lastFrameRecord().serial == frameStats.frames;
}

test "the next frame's begin collects the one before it" {
	const s = settled();
	const before: int32 = frameStats.frames;
	drawFrame(s);
	drawFrame(s);
	assert frameStats.frames == before + 1;
	assert profilerCollect();
	assert frameStats.frames == before + 2;
}

test "two brackets before frameEnd are one record" {
	settled();
	const before: int32 = frameStats.frames;
	begin2d(100.0, 50.0, 1.0);
	begin2d(100.0, 50.0, 1.0);
	frameEnd();
	assert profilerCollect();
	assert frameStats.frames == before + 1;
}

test "begin, commit, present start and present end are in order and the record carries them" {
	const s = settled();
	drawFrame(s);
	voidProfilePresent(1);
	voidProfilePresent(0);
	assert voidProfileState() == VOID_FRAME_PRESENTED;
	const begin: int64 = voidProfileMark(VOID_MARK_BEGIN);
	const committed: int64 = voidProfileMark(VOID_MARK_COMMIT);
	const presentStart: int64 = voidProfileMark(VOID_MARK_PRESENT_START);
	const presentEnd: int64 = voidProfileMark(VOID_MARK_PRESENT_END);
	assert begin <= committed && committed <= presentStart && presentStart <= presentEnd;
	assert profilerCollect();
	assert lastFrameRecord().drawNs == committed - begin;
	assert lastFrameRecord().presentNs == presentEnd - presentStart;
}

test "a frame with no present call records a present of no time" {
	const s = settled();
	drawFrame(s);
	assert profilerCollect();
	assert lastFrameRecord().presentNs == 0;
}

test "a present hook for a commit with no void2d frame records nothing" {
	settled();
	voidProfilePresent(1);
	voidProfilePresent(0);
	assert voidProfileState() == VOID_FRAME_IDLE;
	assert !profilerCollect();
}

test "a commit between two frames is counted as a serial gap, not hidden" {
	const s = settled();
	const before: int32 = frameCommitsWithoutFrame();
	frameEnd();
	drawFrame(s);
	assert profilerCollect();
	assert frameCommitsWithoutFrame() == before + 1;
}

test "a headless frame has void2d counters of zero and no sokol measurement" {
	const s = settled();
	drawFrame(s);
	assert profilerCollect();
	const c = lastFrameCounters();
	assert c.void2dDraws == 0 && c.uiInstances == 0 && c.spriteInstances == 0;
	assert !c.sokolMeasured;
}
