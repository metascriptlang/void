#include "heapBlocks.h"

#if defined(__APPLE__)
#include <malloc/malloc.h>
int64_t heapBlocksInUse(void) {
	malloc_statistics_t stats;
	malloc_zone_statistics(NULL, &stats);
	return (int64_t)stats.blocks_in_use;
}
#else
int64_t heapBlocksInUse(void) { return -1; }
#endif
