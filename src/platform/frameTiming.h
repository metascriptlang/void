// The frame duration sokol_app.h reports. The arithmetic is frameTiming.ms, reached through
// frameTimingExports.cms; this header holds its layout and reads the platform clock.
#ifndef VOID_PLATFORM_FRAME_TIMING_H
#define VOID_PLATFORM_FRAME_TIMING_H

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

void voidFrameTimingReset(VoidFrameTiming *t);
double voidFrameTimingClamp(const VoidFrameTiming *t, double dt);
void voidFrameTimingDelta(VoidFrameTiming *t, double dt);
void voidFrameTimingStep(VoidFrameTiming *t, double nowSeconds);

static inline void voidFrameTimingInit(VoidFrameTiming *t) {
	voidPlatformClockNow();
	voidFrameTimingReset(t);
}

// nowSeconds 0 reads the platform clock; the browser passes its animation frame time.
static inline void voidFrameTimingUpdate(VoidFrameTiming *t, double nowSeconds) {
	voidFrameTimingStep(t, nowSeconds == 0.0 ? (double)voidPlatformClockNow() / 1000000000.0 : nowSeconds);
}

#endif
