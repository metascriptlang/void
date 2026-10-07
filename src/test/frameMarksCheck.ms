import { Scene2D, NodeRef } from "../void2d/node";
import { rgba } from "../void2d/types";
import { paint, isDirty } from "../void2d/scene";
import { begin2d, frameEnd } from "../void2d/draw";
import {
	voidProfilePresent, voidProfileMark, voidProfileState, voidProfileInput,
	VOID_MARK_BEGIN, VOID_MARK_COMMIT, VOID_MARK_PRESENT_START, VOID_MARK_PRESENT_END,
	VOID_FRAME_IDLE, VOID_FRAME_COMMITTED, VOID_FRAME_PRESENTED,
} from "../void2d/frameClock.h";
import { NO_STAMP } from "../void2d/profiler";
import {
	frameStats, profilerCollect, profilerInputBegin, lastFrameRecord,
	lastFrameCounters, frameCommitsWithoutFrame,
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

test "a frame the host never invalidated has no dirty-to-present sample" {
	const s = settled();
	drawFrame(s);
	assert profilerCollect();
	assert lastFrameRecord().dirtyToPresentNs == NO_STAMP;
	assert lastFrameRecord().invalidations == 0;
}

test "the first stamp survives a hundred mutations and one node counts once" {
	const s = settled();
	const node: NodeRef = s.rect(4.0, 4.0, rgba(1.0, 0.0, 0.0, 1.0));
	s.add(node);
	drawFrame(s);
	assert profilerCollect();
	assert frameStats.dirtyAt == NO_STAMP;
	node.setX(1.0);
	const first: int64 = frameStats.dirtyAt;
	assert first != NO_STAMP;
	for (let i: int32 = 2; i <= 100; i++) { node.setX(i as float32); }
	assert frameStats.dirtyAt == first;
	assert frameStats.invalidations == 1;
	drawFrame(s);
	assert profilerCollect();
	assert lastFrameRecord().invalidations == 1;
	assert lastFrameRecord().dirtyToPresentNs >= 0;
	assert frameStats.dirtyAt == NO_STAMP;
}

test "a mutation while a frame is open is not an invalidation" {
	const s = settled();
	const node: NodeRef = s.rect(4.0, 4.0, rgba(1.0, 0.0, 0.0, 1.0));
	s.add(node);
	drawFrame(s);
	assert profilerCollect();
	begin2d(100.0, 50.0, 1.0);
	node.setX(9.0);
	assert frameStats.dirtyAt == NO_STAMP;
	assert frameStats.invalidations == 0;
	frameEnd();
	assert profilerCollect();
}

test "a mutation after the commit closes the finished frame and is then stamped" {
	const s = settled();
	const node: NodeRef = s.rect(4.0, 4.0, rgba(1.0, 0.0, 0.0, 1.0));
	s.add(node);
	drawFrame(s);
	assert profilerCollect();
	drawFrame(s);
	const before: int32 = frameStats.frames;
	node.setX(3.0);
	assert frameStats.frames == before + 1;
	assert frameStats.dirtyAt != NO_STAMP;
}

test "a scene dirty only through its camera is stamped at the first poll and counted once" {
	const s = settled();
	assert !s.isDirty();
	assert frameStats.dirtyAt == NO_STAMP;
	s.cam.x = 12.0;
	assert s.isDirty();
	const first: int64 = frameStats.dirtyAt;
	assert first != NO_STAMP;
	assert frameStats.invalidations == 1;
	assert s.isDirty();
	assert frameStats.dirtyAt == first;
	assert frameStats.invalidations == 1;
	drawFrame(s);
	assert profilerCollect();
}

test "inputs between frames become one latency sample and an input during a frame is dropped" {
	const s = settled();
	profilerInputBegin();
	profilerInputBegin();
	profilerInputBegin();
	drawFrame(s);
	assert profilerCollect();
	assert lastFrameRecord().inputEvents == 3;
	assert lastFrameRecord().inputLatencyNs >= 0;
	begin2d(100.0, 50.0, 1.0);
	profilerInputBegin();
	frameEnd();
	assert profilerCollect();
	assert lastFrameRecord().droppedInputs == 1;
	assert lastFrameRecord().inputLatencyNs == NO_STAMP;
}

test "a headless frame has void2d counters of zero and no sokol measurement" {
	const s = settled();
	drawFrame(s);
	assert profilerCollect();
	const c = lastFrameCounters();
	assert c.void2dDraws == 0 && c.uiInstances == 0 && c.spriteInstances == 0;
	assert !c.sokolMeasured;
}

test "window events join the next frame, and events inside a frame are dropped" {
	const s = settled();
	voidProfileInput();
	voidProfileInput();
	drawFrame(s);
	assert profilerCollect();
	assert lastFrameRecord().inputEvents == 2;
	assert lastFrameRecord().inputLatencyNs >= 0;
	begin2d(100.0, 50.0, 1.0);
	voidProfileInput();
	frameEnd();
	assert profilerCollect();
	assert lastFrameRecord().droppedInputs == 1;
	assert lastFrameRecord().inputEvents == 0;
	assert lastFrameRecord().inputLatencyNs == NO_STAMP;
}
