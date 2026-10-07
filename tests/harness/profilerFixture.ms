import {
	NS_PER_MS, FrameProfiler, FrameCounters, frameProfiler, invalidated, drawBegin, commit,
	present,
} from "../../src/void2d/profiler";

export const FIXTURE_FRAMES: int32 = 60;

export function fixtureProfiler(): FrameProfiler {
	const p: FrameProfiler = frameProfiler();
	let clock: int64 = 1000 * NS_PER_MS;
	for (let i: int32 = 0; i < FIXTURE_FRAMES; i++) {
		const drawNs: int64 = (2000 + ((i * 37) % 41) * 500) as int64 * 1000;
		if (i % 3 != 0) { p.invalidated(clock - 3 * NS_PER_MS); }
		p.drawBegin(clock);
		p.commit(clock + drawNs);
		p.present(clock + drawNs + 300000, clock + drawNs + NS_PER_MS);
		clock = clock + 20 * NS_PER_MS + drawNs;
	}
	return p;
}

export function fixtureCounters(): FrameCounters {
	return {
		void2dDraws: 2,
		uiInstances: 1240,
		spriteInstances: 0,
		uploadBytes: 133920,
		uploads: 2,
		sokolMeasured: true,
		sokolDraws: 3,
		sokolPipelines: 2,
		sokolPasses: 1,
		sokolBufferBytes: 133920,
		sokolImageBytes: 0,
	};
}
