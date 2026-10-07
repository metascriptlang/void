import {
	NO_STAMP,
	NS_PER_MS,
	RING_CAPACITY,
	OverlayMode,
	DurationRing,
	durationRing,
	ringPush,
	ringCount,
	ringPercentile,
	ringMax,
	bucketHistogram,
	bucketIndex,
	histogramRecord,
	frameProfiler,
	invalidated,
	inputBegin,
	drawBegin,
	commit,
	present,
	formatMs,
	readoutLines,
	FrameCounters,
	noCounters,
	counterLines,
} from "../void2d/profiler";

function ms(n: int64): int64 { return n * NS_PER_MS; }

function hundredMilliseconds(): DurationRing {
	const r = durationRing(RING_CAPACITY);
	for (let i: int64 = 1; i <= 100; i++) { r.ringPush(ms(i)); }
	return r;
}

test "a percentile is the sorted sample at (n - 1) * numerator / 100" {
	const r = hundredMilliseconds();
	assert r.ringPercentile(0) == ms(1);
	assert r.ringPercentile(50) == ms(50);
	assert r.ringPercentile(90) == ms(90);
	assert r.ringPercentile(99) == ms(99);
	assert r.ringMax() == ms(100);
}

test "a percentile ignores the order the samples arrived in" {
	const r = durationRing(RING_CAPACITY);
	for (let i: int64 = 100; i >= 1; i--) { r.ringPush(ms(i)); }
	assert r.ringPercentile(90) == ms(90);
	assert r.ringMax() == ms(100);
	assert r.last == ms(1);
}

test "a ring holds its capacity and drops the oldest sample on the 1001st" {
	const r = durationRing(RING_CAPACITY);
	for (let i: int64 = 1; i <= 1000; i++) { r.ringPush(ms(i)); }
	assert r.ringCount() == 1000;
	assert r.ringPercentile(0) == ms(1);
	r.ringPush(ms(1001));
	assert r.ringCount() == 1000;
	assert r.ringPercentile(0) == ms(2);
	assert r.ringMax() == ms(1001);
	assert r.last == ms(1001);
	r.ringPush(ms(1002));
	assert r.ringPercentile(0) == ms(3);
}

test "a small ring wraps over its own oldest sample" {
	const r = durationRing(3);
	for (let i: int64 = 1; i <= 5; i++) { r.ringPush(ms(i)); }
	assert r.ringCount() == 3;
	assert r.ringPercentile(0) == ms(3);
	assert r.ringMax() == ms(5);
}

test "a bucket takes its lower edge and a duration on an edge goes up" {
	assert bucketIndex(0) == 0;
	assert bucketIndex(ms(4) - 1) == 0;
	assert bucketIndex(ms(4)) == 1;
	assert bucketIndex(ms(6)) == 2;
	assert bucketIndex(ms(15)) == 6;
	assert bucketIndex(ms(25) - 1) == 7;
	assert bucketIndex(ms(25)) == 8;
	assert bucketIndex(ms(40) - 1) == 8;
}

test "a duration above the last edge lands in the overflow bucket" {
	assert bucketIndex(ms(40)) == 9;
	assert bucketIndex(ms(5000)) == 9;
}

test "a histogram keeps count, sum, max and one bucket per sample" {
	const h = bucketHistogram();
	assert h.counts.length == 10;
	h.histogramRecord(ms(3));
	h.histogramRecord(ms(4));
	h.histogramRecord(ms(4));
	h.histogramRecord(ms(50));
	assert h.count == 4;
	assert h.counts[0] == 1;
	assert h.counts[1] == 2;
	assert h.counts[9] == 1;
	assert h.sumNs == ms(61);
	assert h.maxNs == ms(50);
}

test "a frame records draw, present and dirty-to-present from its stamps" {
	const p = frameProfiler();
	p.invalidated(ms(10));
	p.drawBegin(ms(20));
	p.commit(ms(25));
	const record = p.present(ms(26), ms(30));
	assert record.serial == 1;
	assert record.drawNs == ms(5);
	assert record.presentNs == ms(4);
	assert record.dirtyToPresentNs == ms(20);
	assert record.dirtyToPresentNs >= record.drawNs;
	assert record.invalidations == 1;
	assert p.draws.ringCount() == 1;
	assert p.dirtyToPresent.ringCount() == 1;
	assert p.drawHistogram.count == 1;
	assert p.dirtyHistogram.count == 1;
}

test "the first invalidation since the last draw is the dirty stamp" {
	const p = frameProfiler();
	p.invalidated(ms(10));
	p.invalidated(ms(12));
	p.invalidated(ms(14));
	p.drawBegin(ms(20));
	p.commit(ms(21));
	const record = p.present(ms(21), ms(22));
	assert record.dirtyToPresentNs == ms(12);
	assert record.invalidations == 3;
}

test "an invalidation during a draw is ignored and the next frame starts clean" {
	const p = frameProfiler();
	p.invalidated(ms(10));
	p.drawBegin(ms(20));
	p.invalidated(ms(21));
	p.commit(ms(22));
	p.present(ms(22), ms(23));
	p.drawBegin(ms(30));
	p.commit(ms(31));
	const record = p.present(ms(31), ms(32));
	assert record.dirtyToPresentNs == NO_STAMP;
	assert record.invalidations == 0;
}

test "a frame with no dirty stamp records draw only" {
	const p = frameProfiler();
	p.drawBegin(ms(5));
	p.commit(ms(7));
	const record = p.present(ms(7), ms(8));
	assert record.dirtyToPresentNs == NO_STAMP;
	assert record.inputLatencyNs == NO_STAMP;
	assert p.draws.ringCount() == 1;
	assert p.dirtyToPresent.ringCount() == 0;
	assert p.inputLatency.ringCount() == 0;
	assert p.dirtyHistogram.count == 0;
}

test "an invalidation after a commit belongs to the next frame" {
	const p = frameProfiler();
	p.drawBegin(ms(5));
	p.commit(ms(6));
	p.invalidated(ms(7));
	p.present(ms(8), ms(9));
	p.drawBegin(ms(10));
	p.commit(ms(11));
	const record = p.present(ms(11), ms(12));
	assert record.dirtyToPresentNs == ms(5);
}

test "three inputs in one frame are one latency sample and three events" {
	const p = frameProfiler();
	p.inputBegin(ms(10));
	p.inputBegin(ms(11));
	p.inputBegin(ms(12));
	p.invalidated(ms(10));
	p.drawBegin(ms(20));
	p.commit(ms(24));
	const record = p.present(ms(24), ms(26));
	assert record.inputEvents == 3;
	assert record.inputLatencyNs == ms(16);
	assert record.droppedInputs == 0;
	assert p.inputLatency.ringCount() == 1;
}

test "an input during a draw is counted as dropped and not sampled" {
	const p = frameProfiler();
	p.drawBegin(ms(20));
	p.inputBegin(ms(21));
	p.inputBegin(ms(22));
	p.commit(ms(24));
	const record = p.present(ms(24), ms(26));
	assert record.droppedInputs == 2;
	assert record.inputEvents == 0;
	assert record.inputLatencyNs == NO_STAMP;
	assert p.inputLatency.ringCount() == 0;
	p.drawBegin(ms(30));
	p.commit(ms(31));
	const next = p.present(ms(31), ms(32));
	assert next.droppedInputs == 0;
	assert next.inputEvents == 0;
	assert next.inputLatencyNs == NO_STAMP;
	assert p.inputLatency.ringCount() == 0;
}

test "milliseconds format right-aligned with one decimal, rounding half up" {
	assert formatMs(0) == "  0.0 MS";
	assert formatMs(49999) == "  0.0 MS";
	assert formatMs(50000) == "  0.1 MS";
	assert formatMs(4560000) == "  4.6 MS";
	assert formatMs(ms(16)) == " 16.0 MS";
	assert formatMs(123450000) == "123.5 MS";
}

test "the readout of an empty profiler shows no values" {
	const p = frameProfiler();
	assert p.readoutLines(OverlayMode.Hidden).length == 0;
	const minimal = p.readoutLines(OverlayMode.Minimal);
	assert minimal.length == 1;
	assert minimal[0] == "CUR    -- MS";
	const full = p.readoutLines(OverlayMode.Full);
	assert full.length == 5;
	assert full[1] == "1%     -- MS";
	assert full[2] == "10%    -- MS";
	assert full[3] == "MAX    -- MS";
	assert full[4] == "FRAMES     0";
}

test "the full readout names current, 1%, 10%, max and the frame count" {
	const p = frameProfiler();
	for (let i: int64 = 1; i <= 100; i++) {
		p.drawBegin(ms(i * 1000));
		p.commit(ms(i * 1000 + i));
		p.present(ms(i * 1000 + i), ms(i * 1000 + i));
	}
	const full = p.readoutLines(OverlayMode.Full);
	assert full[0] == "CUR 100.0 MS";
	assert full[1] == "1%   99.0 MS";
	assert full[2] == "10%  90.0 MS";
	assert full[3] == "MAX 100.0 MS";
	assert full[4] == "FRAMES   100";
	assert p.readoutLines(OverlayMode.Minimal)[0] == "CUR 100.0 MS";
}

test "a frame count past five digits saturates to LOTS" {
	const p = frameProfiler();
	p.frames = 99999;
	assert p.readoutLines(OverlayMode.Full)[4] == "FRAMES 99999";
	p.frames = 100000;
	assert p.readoutLines(OverlayMode.Full)[4] == "FRAMES  LOTS";
}

test "the counter lines say which numbers are void2d's and which are sokol's" {
	const c: FrameCounters = {
		...noCounters(),
		void2dDraws: 1,
		uiInstances: 48890,
		spriteInstances: 12,
		uploadBytes: 5280720,
		uploads: 3,
		sokolMeasured: true,
		sokolDraws: 2,
		sokolPipelines: 3,
		sokolPasses: 2,
		sokolBufferBytes: 5280720,
		sokolImageBytes: 4096,
	};
	const lines = counterLines(c);
	assert lines.length == 4;
	assert lines[0] == "VOID2D DRAW 1 UI 48890 SPR 12";
	assert lines[1] == "VOID2D UP 5280720 B IN 3";
	assert lines[2] == "SOKOL DRAW 2 PIPE 3 PASS 2";
	assert lines[3] == "SOKOL BUF 5280720 B IMG 4096 B";
}

test "a frame whose sokol stats were not read prints N/A, not zeros" {
	const lines = counterLines(noCounters());
	assert lines.length == 3;
	assert lines[0] == "VOID2D DRAW 0 UI 0 SPR 0";
	assert lines[2] == "SOKOL N/A";
}
