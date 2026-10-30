#ifndef VOID_TEST_FRAME_TIMING_H
#define VOID_TEST_FRAME_TIMING_H

void frameTimingReset(void);
void frameTimingPush(double nowSeconds);
void frameTimingDelta(double dt);
double frameTimingSmooth(void);
double frameTimingRaw(void);
double frameTimingEma(void);
double frameTimingClamp(double dt);

#endif
