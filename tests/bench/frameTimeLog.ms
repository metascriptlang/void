// bevy_diagnostic's frame_time line, for the Bevy comparison benches (scripts/frameTime.sh reads
// it): FrameTimeDiagnosticsPlugin keeps the time between frame starts over 120 frames with an
// EMA of factor 2 / (120 + 1), and LogDiagnosticsPlugin prints both once a second.

import { env } from "std/process";

const HISTORY: int32 = 120;
const SMOOTHING: float64 = 2.0 / 121.0;
const LOG_PERIOD_MS: float64 = 1000.0;

export interface FrameTimeLog {
	times: Vec<float64>;
	sum: float64;
	smoothed: float64;
	lastFrame: float64;
	lastLog: float64;
	lines: int32;
	wantedLines: int32;
	frames: int32;
}

export function positiveEnv(name: string, fallback: int32): int32 {
	const wanted: string = env.get(name);
	if (wanted == "") { return fallback; }
	const value: int32 = parseInt(wanted) as int32;
	if (value <= 0) { console.log(`${name} must be a positive count, got ${wanted}`); unreachable; }
	return value;
}

// `wantedLines` lines are printed before `tick` answers true.
export function startFrameTimeLog(wantedLines: int32): FrameTimeLog {
	const now: float64 = performance.now();
	return {
		times: [], sum: 0.0, smoothed: 0.0, lastFrame: now, lastLog: now, lines: 0,
		wantedLines: wantedLines, frames: 0,
	};
}

// Called at the start of every frame; answers whether the run has printed all its lines.
export function tick(log: FrameTimeLog, now: float64): boolean {
	const frameTime: float64 = now - log.lastFrame;
	log.lastFrame = now;
	log.smoothed = log.frames == 0 ? frameTime :
		log.smoothed + SMOOTHING * (frameTime - log.smoothed);
	log.times.push(frameTime);
	log.sum = log.sum + frameTime;
	if ((log.times.length as int32) > HISTORY) { log.sum = log.sum - log.times.shift(); }
	log.frames = log.frames + 1;
	if (now - log.lastLog < LOG_PERIOD_MS) { return false; }
	log.lastLog = now;
	const average: float64 = log.sum / (log.times.length as float64);
	console.log(`frame_time: ${log.smoothed}ms (avg ${average}ms)`);
	log.lines = log.lines + 1;
	return log.lines >= log.wantedLines;
}

// The time since the previous frame in seconds, as Bevy's Time::delta_secs.
export function lastFrameSeconds(log: FrameTimeLog): float64 {
	return log.times.length == 0 ? 0.0 : log.times[log.times.length - 1] / 1000.0;
}
