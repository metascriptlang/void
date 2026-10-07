#ifndef VOID_FRAME_CLOCK_H
#define VOID_FRAME_CLOCK_H

#include <stdint.h>

static const int32_t VOID_MARK_BEGIN = 0;
static const int32_t VOID_MARK_COMMIT = 1;
static const int32_t VOID_MARK_PRESENT_START = 2;
static const int32_t VOID_MARK_PRESENT_END = 3;

static const int32_t VOID_COUNTER_DRAWS = 0;
static const int32_t VOID_COUNTER_UI_INSTANCES = 1;
static const int32_t VOID_COUNTER_SPRITE_INSTANCES = 2;
static const int32_t VOID_COUNTER_UPLOAD_BYTES = 3;
static const int32_t VOID_COUNTER_UPLOADS = 4;
static const int32_t VOID_COUNTER_SOKOL_DRAWS = 5;
static const int32_t VOID_COUNTER_SOKOL_PIPELINES = 6;
static const int32_t VOID_COUNTER_SOKOL_PASSES = 7;
static const int32_t VOID_COUNTER_SOKOL_BUFFER_BYTES = 8;
static const int32_t VOID_COUNTER_SOKOL_IMAGE_BYTES = 9;
static const int32_t VOID_COUNTER_SOKOL_MEASURED = 10;
#define VOID_COUNTER_SLOTS 11
static const int32_t VOID_COUNTER_COUNT = VOID_COUNTER_SLOTS;

static const int32_t VOID_FRAME_IDLE = 0;
static const int32_t VOID_FRAME_OPEN = 1;
static const int32_t VOID_FRAME_COMMITTED = 2;
static const int32_t VOID_FRAME_PRESENTED = 3;

int64_t voidClockNow(void);
int32_t voidProfileCompiled(void);
void voidProfileSetup(void);
int32_t voidProfileState(void);
int32_t voidProfileSerial(void);
int32_t voidProfileLost(void);
int64_t voidProfileMark(int32_t which);
int32_t voidProfileCounter(int32_t which);
void voidProfileConsume(void);
void voidProfileBegin(void);
void voidProfileCommit(int32_t serial, const int32_t *void2dCounters);
void voidProfilePresent(int begin);

#endif
