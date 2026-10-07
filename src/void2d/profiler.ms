export const RING_CAPACITY: int32 = 1000;
export const NO_STAMP: int64 = -1;
export const NS_PER_MS: int64 = 1000000;
export const FRAME_COUNT_SATURATION: int32 = 99999;
export const BUCKET_EDGES_MS: Vec<int32> = [4, 6, 8, 10, 12, 15, 18, 25, 40];

export enum OverlayMode {
	Hidden,
	Minimal,
	Full,
}

export interface DurationRing {
	samples: Vec<int64>;
	capacity: int32;
	oldest: int32;
	last: int64;
}

export function durationRing(capacity: int32): DurationRing {
	if (capacity <= 0) {
		console.log(`void2d profiler: a duration ring needs a capacity above 0, got ${capacity}`);
		unreachable;
	}
	return { samples: new Array(0), capacity: capacity, oldest: 0, last: NO_STAMP };
}

export function durationCheck(ns: int64, what: string): void {
	if (ns < 0) {
		console.log(`void2d profiler: ${what} is negative (${ns} ns)`);
		unreachable;
	}
}

export function ringCount(this r: DurationRing): int32 {
	return r.samples.length as int32;
}

export function ringPush(this r: DurationRing, ns: int64): void {
	durationCheck(ns, "a ring sample");
	if (r.ringCount() < r.capacity) {
		r.samples.push(ns);
	} else {
		r.samples[r.oldest] = ns;
		r.oldest = (r.oldest + 1) % r.capacity;
	}
	r.last = ns;
}

export function ringSorted(this r: DurationRing): number[] {
	const sorted: number[] = new Array(0);
	const n: int32 = r.ringCount();
	for (let i: int32 = 0; i < n; i++) { sorted.push(r.samples[i] as number); }
	sorted.sort();
	return sorted;
}

export function percentileOf(sorted: number[], numerator: int32): int64 {
	const n: int32 = sorted.length as int32;
	if (n == 0) {
		console.log("void2d profiler: a percentile of an empty ring has no value");
		unreachable;
	}
	if (numerator < 0 || numerator > 100) {
		console.log(`void2d profiler: a percentile is 0 to 100, got ${numerator}`);
		unreachable;
	}
	return sorted[((n - 1) * numerator) / 100] as int64;
}

export function ringPercentile(this r: DurationRing, numerator: int32): int64 {
	return percentileOf(r.ringSorted(), numerator);
}

export function ringMax(this r: DurationRing): int64 {
	return r.ringPercentile(100);
}

export interface BucketHistogram {
	counts: Vec<int32>;
	count: int32;
	sumNs: int64;
	maxNs: int64;
}

export function bucketHistogram(): BucketHistogram {
	let counts: Vec<int32> = new Array(0);
	for (let i: int32 = 0; i <= (BUCKET_EDGES_MS.length as int32); i++) { counts.push(0); }
	return { counts: counts, count: 0, sumNs: 0, maxNs: 0 };
}

export function bucketIndex(ns: int64): int32 {
	durationCheck(ns, "a histogram sample");
	const edges: int32 = BUCKET_EDGES_MS.length as int32;
	for (let i: int32 = 0; i < edges; i++) {
		if (ns < (BUCKET_EDGES_MS[i] as int64) * NS_PER_MS) { return i; }
	}
	return edges;
}

export function histogramRecord(this h: BucketHistogram, ns: int64): void {
	const i: int32 = bucketIndex(ns);
	h.counts[i] = h.counts[i] + 1;
	h.count = h.count + 1;
	h.sumNs = h.sumNs + ns;
	if (ns > h.maxNs) { h.maxNs = ns; }
}

export enum FramePhase {
	Idle,
	Drawing,
	Committed,
}

export struct FrameRecord {
	serial: int32;
	drawNs: int64;
	presentNs: int64;
	dirtyToPresentNs: int64;
	invalidations: int32;
	inputLatencyNs: int64;
	inputEvents: int32;
	droppedInputs: int32;
}

export interface FrameProfiler {
	draws: DurationRing;
	dirtyToPresent: DurationRing;
	inputLatency: DurationRing;
	drawHistogram: BucketHistogram;
	dirtyHistogram: BucketHistogram;
	frames: int32;
	phase: FramePhase;
	dirtyAt: int64;
	invalidations: int32;
	firstInputAt: int64;
	inputEvents: int32;
	drawStart: int64;
	commitAt: int64;
	frameDirtyAt: int64;
	frameInvalidations: int32;
	frameFirstInputAt: int64;
	frameInputEvents: int32;
	frameDroppedInputs: int32;
}

export function frameProfiler(): FrameProfiler {
	return {
		draws: durationRing(RING_CAPACITY),
		dirtyToPresent: durationRing(RING_CAPACITY),
		inputLatency: durationRing(RING_CAPACITY),
		drawHistogram: bucketHistogram(),
		dirtyHistogram: bucketHistogram(),
		frames: 0,
		phase: FramePhase.Idle,
		dirtyAt: NO_STAMP,
		invalidations: 0,
		firstInputAt: NO_STAMP,
		inputEvents: 0,
		drawStart: NO_STAMP,
		commitAt: NO_STAMP,
		frameDirtyAt: NO_STAMP,
		frameInvalidations: 0,
		frameFirstInputAt: NO_STAMP,
		frameInputEvents: 0,
		frameDroppedInputs: 0,
	};
}

export function invalidated(this p: FrameProfiler, now: int64): void {
	durationCheck(now, "an invalidation stamp");
	if (p.phase == FramePhase.Drawing) { return; }
	if (p.dirtyAt == NO_STAMP) { p.dirtyAt = now; }
	p.invalidations = p.invalidations + 1;
}

export function inputBegin(this p: FrameProfiler, now: int64): void {
	durationCheck(now, "an input stamp");
	if (p.phase == FramePhase.Drawing) {
		p.frameDroppedInputs = p.frameDroppedInputs + 1;
		return;
	}
	if (p.firstInputAt == NO_STAMP) { p.firstInputAt = now; }
	p.inputEvents = p.inputEvents + 1;
}

export function drawBegin(this p: FrameProfiler, now: int64): void {
	durationCheck(now, "a drawBegin stamp");
	if (p.phase != FramePhase.Idle) {
		console.log(
			`void2d profiler: drawBegin at ${now} ns while frame ${p.frames} is still open ` +
			`(drawing or committed with no present recorded)`,
		);
		unreachable;
	}
	p.phase = FramePhase.Drawing;
	p.drawStart = now;
	p.frameDirtyAt = p.dirtyAt;
	p.frameInvalidations = p.invalidations;
	p.frameFirstInputAt = p.firstInputAt;
	p.frameInputEvents = p.inputEvents;
	p.frameDroppedInputs = 0;
	p.dirtyAt = NO_STAMP;
	p.invalidations = 0;
	p.firstInputAt = NO_STAMP;
	p.inputEvents = 0;
}

export function commit(this p: FrameProfiler, now: int64): void {
	if (p.phase != FramePhase.Drawing) {
		console.log(`void2d profiler: commit at ${now} ns with no drawBegin open`);
		unreachable;
	}
	if (now < p.drawStart) {
		console.log(
			`void2d profiler: commit at ${now} ns is before drawBegin at ${p.drawStart} ns`,
		);
		unreachable;
	}
	p.phase = FramePhase.Committed;
	p.commitAt = now;
}

export function present(
	this p: FrameProfiler,
	presentStart: int64,
	presentEnd: int64,
): FrameRecord {
	if (p.phase != FramePhase.Committed) {
		console.log(
			`void2d profiler: present at ${presentStart} ns ` +
			`before the frame was drawn and committed`,
		);
		unreachable;
	}
	if (presentStart < p.commitAt) {
		console.log(
			`void2d profiler: present starts at ${presentStart} ns, ` +
			`before commit at ${p.commitAt} ns`,
		);
		unreachable;
	}
	if (presentEnd < presentStart) {
		console.log(
			`void2d profiler: present ends at ${presentEnd} ns, ` +
			`before it started at ${presentStart} ns`,
		);
		unreachable;
	}
	const drawNs: int64 = p.commitAt - p.drawStart;
	const dirtyNs: int64 = p.frameDirtyAt == NO_STAMP ? NO_STAMP : presentEnd - p.frameDirtyAt;
	const inputNs: int64 = p.frameFirstInputAt == NO_STAMP
		? NO_STAMP
		: presentEnd - p.frameFirstInputAt;
	p.phase = FramePhase.Idle;
	p.frames = p.frames + 1;
	p.draws.ringPush(drawNs);
	p.drawHistogram.histogramRecord(drawNs);
	if (dirtyNs != NO_STAMP) {
		p.dirtyToPresent.ringPush(dirtyNs);
		p.dirtyHistogram.histogramRecord(dirtyNs);
	}
	if (inputNs != NO_STAMP) { p.inputLatency.ringPush(inputNs); }
	return {
		serial: p.frames,
		drawNs: drawNs,
		presentNs: presentEnd - presentStart,
		dirtyToPresentNs: dirtyNs,
		invalidations: p.frameInvalidations,
		inputLatencyNs: inputNs,
		inputEvents: p.frameInputEvents,
		droppedInputs: p.frameDroppedInputs,
	};
}

function padLeft(text: string, width: int32): string {
	let out: string = text;
	while ((out.length as int32) < width) { out = " " + out; }
	return out;
}

export function formatMs(ns: int64): string {
	durationCheck(ns, "a formatted duration");
	const tenths: int64 = (ns + 50000) / 100000;
	const whole: int64 = tenths / 10;
	const fraction: int64 = tenths % 10;
	return padLeft(`${whole}.${fraction}`, 5) + " MS";
}

const NO_READING: string = "   -- MS";

export function readoutLines(this p: FrameProfiler, mode: OverlayMode): Vec<string> {
	let lines: Vec<string> = new Array(0);
	if (mode == OverlayMode.Hidden) { return lines; }
	const current: string = p.draws.ringCount() == 0 ? NO_READING : formatMs(p.draws.last);
	lines.push(`CUR ${current}`);
	if (mode == OverlayMode.Minimal) { return lines; }
	if (p.draws.ringCount() == 0) {
		lines.push(`1%  ${NO_READING}`);
		lines.push(`10% ${NO_READING}`);
		lines.push(`MAX ${NO_READING}`);
	} else {
		const sorted: number[] = p.draws.ringSorted();
		lines.push(`1%  ${formatMs(percentileOf(sorted, 99))}`);
		lines.push(`10% ${formatMs(percentileOf(sorted, 90))}`);
		lines.push(`MAX ${formatMs(percentileOf(sorted, 100))}`);
	}
	const shown: string = p.frames > FRAME_COUNT_SATURATION ? "LOTS" : `${p.frames}`;
	lines.push(`FRAMES ${padLeft(shown, 5)}`);
	return lines;
}
