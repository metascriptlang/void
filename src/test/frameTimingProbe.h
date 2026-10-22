#ifndef VOID_TEST_FRAME_TIMING_H
#define VOID_TEST_FRAME_TIMING_H

void frameTimingReset(void);
void frameTimingPush(double nowSeconds);
double frameTimingSmooth(void);
double frameTimingRaw(void);

#endif
