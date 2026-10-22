// The frame duration sokol_app.h reports, ported from its _sapp_timing_* (pin 2e75443d): the
// raw delta is clamped to [1 us, 100 ms] and smoothed with an EMA that resets when a delta
// leaves the 4 ms band.
#ifndef VOID_PLATFORM_FRAME_TIMING_H
#define VOID_PLATFORM_FRAME_TIMING_H

#include <math.h>

#include "clock.h"

typedef struct {
	double dtMin;
	double dtMax;
	double dtThreshold;
	double alpha;
	double last;
	double dt;
	double ema;
	double smoothDt;
} VoidFrameTiming;

static inline void voidFrameTimingInit(VoidFrameTiming *t) {
	voidPlatformClockNow();
	t->dtMin = 0.000001;
	t->dtMax = 0.1;
	t->dtThreshold = 0.004;
	t->alpha = 0.025;
	t->last = 0.0;
	t->dt = 1.0 / 60.0;
	t->ema = t->dt;
	t->smoothDt = t->dt;
}

static inline double voidFrameTimingClamp(const VoidFrameTiming *t, double dt) {
	if (dt < t->dtMin) return t->dtMin;
	if (dt > t->dtMax) return t->dtMax;
	return dt;
}

static inline void voidFrameTimingDelta(VoidFrameTiming *t, double dt) {
	dt = voidFrameTimingClamp(t, dt);
	t->dt = dt;
	if (fabs(dt - t->smoothDt) > t->dtThreshold) {
		t->ema = dt;
		t->smoothDt = dt;
	} else {
		t->ema = t->ema + t->alpha * (dt - t->ema);
		t->smoothDt = voidFrameTimingClamp(t, t->ema);
	}
}

// nowSeconds 0 reads the platform clock; the browser passes its animation frame time.
static inline void voidFrameTimingUpdate(VoidFrameTiming *t, double nowSeconds) {
	const double now = nowSeconds == 0.0 ? (double)voidPlatformClockNow() / 1000000000.0 : nowSeconds;
	if (t->last > 0.0) voidFrameTimingDelta(t, now - t->last);
	t->last = now;
}

#endif
