#define SOKOL_TIME_IMPL
#include "../../deps/sokol/sokol_time.h"
#include "../sokol/bridge.h"
#include "frameClock.h"

#include <stdio.h>
#include <stdlib.h>

static int s_clockReady;
static int s_state = VOID_FRAME_IDLE;
static int s_presentStarted;
static int32_t s_serial;
static int32_t s_lost;
static int64_t s_marks[4];

int64_t voidClockNow(void) {
	if (!s_clockReady) {
		stm_setup();
		s_clockReady = 1;
	}
	return (int64_t)stm_now();
}

int32_t voidProfileCompiled(void) { return 1; }
void voidProfileSetup(void) { voidSetPresentHook(voidProfilePresent); }
int32_t voidProfileState(void) { return s_state; }
int32_t voidProfileSerial(void) { return s_serial; }
int32_t voidProfileLost(void) { return s_lost; }
void voidProfileConsume(void) { s_state = VOID_FRAME_IDLE; }

static void stopOnIndex(const char *what, int32_t which) {
	fprintf(stderr, "void2d profiler: no %s number %d\n", what, (int)which);
	abort();
}

int64_t voidProfileMark(int32_t which) {
	if (which < 0 || which > 3) { stopOnIndex("frame mark", which); }
	return s_marks[which];
}

void voidProfileBegin(void) {
	if (s_state != VOID_FRAME_IDLE) { s_lost++; }
	s_state = VOID_FRAME_OPEN;
	s_presentStarted = 0;
	s_marks[VOID_MARK_BEGIN] = voidClockNow();
}

void voidProfileCommit(int32_t serial) {
	if (s_state != VOID_FRAME_OPEN) { return; }
	s_marks[VOID_MARK_COMMIT] = voidClockNow();
	s_serial = serial;
	s_state = VOID_FRAME_COMMITTED;
}

void voidProfilePresent(int begin) {
	if (s_state != VOID_FRAME_COMMITTED) { return; }
	if (begin) {
		s_marks[VOID_MARK_PRESENT_START] = voidClockNow();
		s_presentStarted = 1;
		return;
	}
	if (!s_presentStarted) { return; }
	s_marks[VOID_MARK_PRESENT_END] = voidClockNow();
	s_state = VOID_FRAME_PRESENTED;
}
