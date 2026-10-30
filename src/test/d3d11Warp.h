#pragma once
#include <stdint.h>

void *warpDevice(void);
void *warpContext(void);
int32_t warpReadback(void *texture, void *pixels, int32_t width, int32_t height);
int32_t warpReadbackSubresource(void *texture, int32_t subresource, void *pixels, int32_t width, int32_t height);
int32_t warpObjectName(void *object, uint8_t *out, int32_t size);
int32_t warpReadback3d(void *texture, int32_t mip, int32_t slice, void *pixels, int32_t width, int32_t height);
void *warpTarget(int32_t width, int32_t height, int32_t sampleCount);
void *warpTargetView(void *texture);
void warpRelease(void);
