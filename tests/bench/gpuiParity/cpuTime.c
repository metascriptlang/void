#include "cpuTime.h"
#include <time.h>
uint64_t processCpuNs(void) {
	struct timespec ts;
	if (clock_gettime(CLOCK_PROCESS_CPUTIME_ID, &ts) != 0) return 0;
	return (uint64_t)ts.tv_sec * 1000000000ull + (uint64_t)ts.tv_nsec;
}
