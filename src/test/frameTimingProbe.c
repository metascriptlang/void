#include "frameTimingProbe.h"

#include "../platform/frameTiming.h"

static VoidFrameTiming s_timing;

void frameTimingReset(void) { voidFrameTimingInit(&s_timing); }
void frameTimingPush(double nowSeconds) { voidFrameTimingUpdate(&s_timing, nowSeconds); }
double frameTimingSmooth(void) { return s_timing.smoothDt; }
double frameTimingRaw(void) { return s_timing.dt; }
