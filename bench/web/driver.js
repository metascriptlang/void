// Loaded before every implementation's code. It times each requestAnimationFrame callback, so the
// same clock measures every library without touching its loop: CPU is the time spent in the
// callbacks of one frame, interval the time between two frames. window.benchResult holds the
// summary once WARMUP + FRAMES frames ran.
(() => {
	const WARMUP = 120;
	const FRAMES = 600;
	const raf = window.requestAnimationFrame.bind(window);
	const frames = [];
	let current = null;
	let firstFrameMs = null;
	window.benchResult = null;
	window.benchErrors = [];
	window.addEventListener('error', (e) => window.benchErrors.push(String(e.error?.stack ?? e.message)));
	window.addEventListener('unhandledrejection', (e) => window.benchErrors.push(String(e.reason?.stack ?? e.reason)));
	const median = (v) => { const s = [...v].sort((a, b) => a - b); return s[Math.floor(s.length / 2)]; };
	const p95 = (v) => { const s = [...v].sort((a, b) => a - b); return s[Math.min(s.length - 1, Math.floor(s.length * 0.95))]; };
	function finish() {
		const measured = frames.slice(WARMUP, WARMUP + FRAMES);
		const cpu = measured.map((f) => f.cpu);
		const interval = measured.slice(1).map((f, i) => f.t - measured[i].t);
		window.benchResult = {
			firstFrameMs,
			cpuMedianMs: median(cpu), cpuP95Ms: p95(cpu),
			intervalMedianMs: median(interval), intervalP95Ms: p95(interval),
			jsHeapMB: performance.memory ? performance.memory.usedJSHeapSize / 1048576 : null,
			isolated: self.crossOriginIsolated,
		};
	}
	window.requestAnimationFrame = (callback) => raf((t) => {
		if (current === null || current.t !== t) {
			if (frames.length >= WARMUP + FRAMES) { if (window.benchResult === null) finish(); }
			else { current = { t, cpu: 0 }; frames.push(current); }
		}
		const started = performance.now();
		try { callback(t); } finally {
			const ended = performance.now();
			if (current !== null && current.t === t) current.cpu += ended - started;
			if (firstFrameMs === null) firstFrameMs = ended;
		}
	});
})();
