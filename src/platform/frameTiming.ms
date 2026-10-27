// The frame duration sokol_app.h reports, ported from its _sapp_timing_* (pin 2e75443d): the
// raw delta is clampedDelta to [1 us, 100 ms] and smoothed with an EMA that resets when a delta
// leaves the 4 ms band. The C windows reach it through frameTimingExports.cms and
// frameTiming.h, which holds this layout as VoidFrameTiming.

export struct FrameTiming {
	dtMin: float64;
	dtMax: float64;
	dtThreshold: float64;
	alpha: float64;
	last: float64;
	dt: float64;
	ema: float64;
	smoothDt: float64;
}

export function startFrameTiming(): FrameTiming {
	const initial: float64 = 1.0 / 60.0;
	return {
		dtMin: 0.000001,
		dtMax: 0.1,
		dtThreshold: 0.004,
		alpha: 0.025,
		last: 0.0,
		dt: initial,
		ema: initial,
		smoothDt: initial,
	};
}

export function clampedDelta(this t: Readonly<FrameTiming>, dt: float64): float64 {
	if (dt < t.dtMin) { return t.dtMin; }
	if (dt > t.dtMax) { return t.dtMax; }
	return dt;
}

export function addDelta(this ref t: FrameTiming, raw: float64): void {
	const dt = t.clampedDelta(raw);
	t.dt = dt;
	if (Math.abs(dt - t.smoothDt) > t.dtThreshold) {
		t.ema = dt;
		t.smoothDt = dt;
	} else {
		t.ema = t.ema + t.alpha * (dt - t.ema);
		t.smoothDt = t.clampedDelta(t.ema);
	}
}

export function advanceTo(this ref t: FrameTiming, nowSeconds: float64): void {
	if (t.last > 0.0) { t.addDelta(nowSeconds - t.last); }
	t.last = nowSeconds;
}
