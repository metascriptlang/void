#pragma once
#include <stdint.h>

void *warpDevice(void);
void *warpContext(void);
int32_t warpReadback(void *texture, void *pixels, int32_t width, int32_t height);
int32_t warpReadbackSubresource(void *texture, int32_t subresource, void *pixels, int32_t width, int32_t height);
void warpRelease(void);
