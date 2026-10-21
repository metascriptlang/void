// Nanoseconds since the first call, read per platform as sokol_time.h's stm_setup and stm_now
// read them (pin 2e75443d): QueryPerformanceCounter, mach_absolute_time, emscripten_get_now,
// else clock_gettime(CLOCK_MONOTONIC).
#ifndef VOID_PLATFORM_CLOCK_H
#define VOID_PLATFORM_CLOCK_H

#include <stdint.h>

#if defined(_WIN32)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#elif defined(__APPLE__) && defined(__MACH__)
#include <mach/mach_time.h>
#elif defined(__EMSCRIPTEN__)
#include <emscripten/emscripten.h>
#else
#include <time.h>
#endif

#if defined(_WIN32) || (defined(__APPLE__) && defined(__MACH__))
// value * numer / denom without overflowing 64 bits (sokol_time.h _stm_int64_muldiv).
static int64_t voidClockMulDiv(int64_t value, int64_t numer, int64_t denom) {
	return value / denom * numer + value % denom * numer / denom;
}
#endif

static int64_t voidPlatformClockNow(void) {
#if defined(_WIN32)
	static LARGE_INTEGER freq;
	static LARGE_INTEGER start;
	LARGE_INTEGER now;
	QueryPerformanceCounter(&now);
	if (freq.QuadPart == 0) {
		QueryPerformanceFrequency(&freq);
		start = now;
	}
	return voidClockMulDiv(now.QuadPart - start.QuadPart, 1000000000, freq.QuadPart);
#elif defined(__APPLE__) && defined(__MACH__)
	static mach_timebase_info_data_t timebase;
	static uint64_t start;
	const uint64_t now = mach_absolute_time();
	if (timebase.denom == 0) {
		mach_timebase_info(&timebase);
		start = now;
	}
	return voidClockMulDiv((int64_t)(now - start), (int64_t)timebase.numer, (int64_t)timebase.denom);
#elif defined(__EMSCRIPTEN__)
	static double start = -1.0;
	const double now = emscripten_get_now();
	if (start < 0.0) { start = now; }
	return (int64_t)((now - start) * 1000000.0);
#else
	static int started;
	static int64_t start;
	struct timespec ts;
	clock_gettime(CLOCK_MONOTONIC, &ts);
	const int64_t now = (int64_t)ts.tv_sec * 1000000000 + (int64_t)ts.tv_nsec;
	if (!started) {
		started = 1;
		start = now;
	}
	return now - start;
#endif
}

#endif
