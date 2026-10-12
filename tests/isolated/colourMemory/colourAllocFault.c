#include "colourAllocFault.h"
#include <stdlib.h>

static int pending;
static int failures;

void retryColourArm(int stage) {
	pending = stage;
	failures = 0;
}

int retryColourFailures(void) { return failures; }

static int fail(int stage) {
	if (pending != stage) { return 0; }
	pending = 0;
	failures++;
	return 1;
}

void *retryColourLayerCalloc(size_t count, size_t size) {
	return fail(1) ? NULL : calloc(count, size);
}

void *retryColourSourceMalloc(size_t size) {
	return fail(2) ? NULL : malloc(size);
}

void *retryColourPngMalloc(size_t size) {
	return fail(3) ? NULL : malloc(size);
}

void *retryColourPngRealloc(void *ptr, size_t oldSize, size_t newSize) {
	(void)oldSize;
	return fail(3) ? NULL : realloc(ptr, newSize);
}
