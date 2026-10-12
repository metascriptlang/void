#ifndef RETRY_FAULT_COLOUR_H
#define RETRY_FAULT_COLOUR_H

#include <stddef.h>

void retryColourArm(int stage);
int retryColourFailures(void);
void *retryColourLayerCalloc(size_t count, size_t size);
void *retryColourSourceMalloc(size_t size);
void *retryColourPngMalloc(size_t size);
void *retryColourPngRealloc(void *ptr, size_t oldSize, size_t newSize);
const char *retryColourPngReason(void);

#endif
