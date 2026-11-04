#pragma once
#include <stdint.h>
/* Own-process CPU time (user+system, all threads) in nanoseconds: clock_gettime(CLOCK_PROCESS_CPUTIME_ID).
   Not cycles: the Windows harness read QueryProcessCycleTime; this macOS one reads ns. */
uint64_t processCpuNs(void);
