import {
	frameTimingReset,
	frameTimingPush,
	frameTimingSmooth,
	frameTimingRaw,
} from "./frameTimingProbe.h";

function near(a: float64, b: float64): boolean {
	return Math.abs(a - b) < 1e-9;
}

const sixty = 1.0 / 60.0;

test "the frame duration starts at 1/60 and the first update measures no delta" {
	frameTimingReset();
	assert near(frameTimingSmooth(), sixty);
	frameTimingPush(1.0);
	assert near(frameTimingSmooth(), sixty);
	assert near(frameTimingRaw(), sixty);
}

test "a steady 60 Hz stream keeps the smoothed duration at 1/60" {
	frameTimingReset();
	let now = 1.0;
	for (let i = 0; i < 200; i++) {
		frameTimingPush(now);
		now += sixty;
	}
	assert near(frameTimingSmooth(), sixty);
}

test "a delta inside the 4 ms band moves the smoothed duration by alpha of the error" {
	frameTimingReset();
	frameTimingPush(1.0);
	frameTimingPush(1.0 + sixty + 0.002);
	assert near(frameTimingRaw(), sixty + 0.002);
	assert near(frameTimingSmooth(), sixty + 0.025 * 0.002);
}

test "a delta outside the band resets the smoothed duration to it" {
	frameTimingReset();
	frameTimingPush(1.0);
	frameTimingPush(1.05);
	assert near(frameTimingRaw(), 0.05);
	assert near(frameTimingSmooth(), 0.05);
}

test "a delta is clamped to 1 microsecond and 100 ms" {
	frameTimingReset();
	frameTimingPush(1.0);
	frameTimingPush(11.0);
	assert near(frameTimingRaw(), 0.1);
	frameTimingPush(11.0);
	assert near(frameTimingRaw(), 0.000001);
}
