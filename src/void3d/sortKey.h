#ifndef VOID_SORT_KEY_H
#define VOID_SORT_KEY_H

#include <stdint.h>
#include <string.h>

// The bits of `f`, flipped so that unsigned order is float order: negatives reversed under
// the positives. -0 sorts just below +0.
static inline uint32_t sortKeyOf(float f) {
	uint32_t u;
	memcpy(&u, &f, sizeof u);
	return (u & 0x80000000u) ? ~u : (u | 0x80000000u);
}

#endif
