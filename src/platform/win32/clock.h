// Nanoseconds since the first call, from QueryPerformanceCounter as sokol_time.h's stm_now
// reads it (pin 2e75443d).
#ifndef VOID_PLATFORM_WIN32_CLOCK_H
#define VOID_PLATFORM_WIN32_CLOCK_H

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <stdint.h>

static int64_t voidWin32ClockNow(void) {
	static LARGE_INTEGER freq;
	static LARGE_INTEGER start;
	LARGE_INTEGER now;
	QueryPerformanceCounter(&now);
	if (freq.QuadPart == 0) {
		QueryPerformanceFrequency(&freq);
		start = now;
	}
	const int64_t ticks = now.QuadPart - start.QuadPart;
	return ticks / freq.QuadPart * 1000000000 + ticks % freq.QuadPart * 1000000000 / freq.QuadPart;
}

#endif
