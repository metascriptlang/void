// The frame profiler as C callers see it: frameClock.ms, reached through frameClockExports.cms.
#ifndef VOID_FRAME_CLOCK_H
#define VOID_FRAME_CLOCK_H

#include <stdint.h>

static const int32_t VOID_COUNTER_DRAWS = 0;
static const int32_t VOID_COUNTER_UI_INSTANCES = 1;
static const int32_t VOID_COUNTER_SPRITE_INSTANCES = 2;
static const int32_t VOID_COUNTER_UPLOAD_BYTES = 3;
static const int32_t VOID_COUNTER_UPLOADS = 4;
static const int32_t VOID_COUNTER_COVERED_PIXELS = 5;
static const int32_t VOID_COUNTER_TARGET_PIXELS = 6;
static const int32_t VOID_COUNTER_OPAQUE_PIXELS = 7;
static const int32_t VOID_COUNTER_FRAME_PIXELS = 8;
#define VOID_COUNTER_VOID2D_SLOTS 9

void voidProfileInput(void);
void voidProfileBegin(void);
void voidProfileCommit(int32_t serial, const int32_t *void2dCounters);

#endif
