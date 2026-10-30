import { DeltaStream, STREAM_KINDS, STREAM_STEPS } from "./frameTimingStream";
import { FrameTiming, startFrameTiming, clampedDelta, addDelta, advanceTo } from "../platform/frameTiming";

when (js) {
} else {
	import "../platform/frameTimingExports";
	import {
		frameTimingClamp,
		frameTimingDelta,
		frameTimingEma,
		frameTimingRaw,
		frameTimingReset,
		frameTimingSmooth,
	} from "./frameTimingProbe.h";
}

function near(a: float64, b: float64): boolean {
	return Math.abs(a - b) < 1e-9;
}

const sixty = 1.0 / 60.0;

// Per stream kind, the sum over its steps of the EMA and of the smoothed duration, and the last
// raw duration, recorded from the C frameTiming.h before the port replaced it.
const RECORDED_EMA_SUMS: float64[] = [
	6.6427627764437602,
	6.635653573628046,
	36.040610163885866,
	14.700252999999893,
	1.599999997137449,
];
const RECORDED_SMOOTH_SUMS: float64[] = [
	6.6427627764437602,
	6.635653573628046,
	36.040610163885866,
	14.700252999999893,
	1.599999997137449,
];
const RECORDED_LAST_DT: float64[] = [
	0.016726525982778177,
	0.010715738183519742,
	0.10000000000000001,
	0.10000000000000001,
	0.0039999999265681978,
];

test "the frame duration starts at 1/60 and the first update measures no delta" {
	let t = startFrameTiming();
	assert near(t.smoothDt, sixty);
	t.advanceTo(1.0);
	assert near(t.smoothDt, sixty);
	assert near(t.dt, sixty);
}

test "a steady 60 Hz stream keeps the smoothed duration at 1/60" {
	let t = startFrameTiming();
	let now = 1.0;
	for (let i = 0; i < 200; i++) {
		t.advanceTo(now);
		now += sixty;
	}
	assert near(t.smoothDt, sixty);
}

test "a delta inside the 4 ms band moves the smoothed duration by alpha of the error" {
	let t = startFrameTiming();
	t.advanceTo(1.0);
	t.advanceTo(1.0 + sixty + 0.002);
	assert near(t.dt, sixty + 0.002);
	assert near(t.smoothDt, sixty + 0.025 * 0.002);
}

test "a delta outside the band resets the smoothed duration to it" {
	let t = startFrameTiming();
	t.advanceTo(1.0);
	t.advanceTo(1.05);
	assert near(t.dt, 0.05);
	assert near(t.smoothDt, 0.05);
}

test "a delta is clamped to 1 microsecond and 100 ms" {
	let t = startFrameTiming();
	t.advanceTo(1.0);
	t.advanceTo(11.0);
	assert near(t.dt, 0.1);
	t.advanceTo(11.0);
	assert near(t.dt, 0.000001);
}

test "the delta streams reproduce the sums recorded from the C" {
	for (let kind: int32 = 0; kind < STREAM_KINDS; kind++) {
		let t = startFrameTiming();
		const stream = new DeltaStream(kind);
		let emaSum: float64 = 0;
		let smoothSum: float64 = 0;
		for (let i: int32 = 0; i < STREAM_STEPS; i++) {
			t.addDelta(stream.next());
			emaSum += t.ema;
			smoothSum += t.smoothDt;
		}
		assert emaSum == RECORDED_EMA_SUMS[kind];
		assert smoothSum == RECORDED_SMOOTH_SUMS[kind];
		assert t.dt == RECORDED_LAST_DT[kind];
	}
}

when (js) {
} else {
	test "the C header path through the exports follows the same streams" {
		for (let kind: int32 = 0; kind < STREAM_KINDS; kind++) {
			let t = startFrameTiming();
			frameTimingReset();
			const stream = new DeltaStream(kind);
			for (let i: int32 = 0; i < STREAM_STEPS; i++) {
				const dt = stream.next();
				t.addDelta(dt);
				frameTimingDelta(dt);
				assert frameTimingRaw() == t.dt;
				assert frameTimingEma() == t.ema;
				assert frameTimingSmooth() == t.smoothDt;
				assert frameTimingClamp(dt) == t.clampedDelta(dt);
			}
		}
	}
}
