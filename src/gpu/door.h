#ifndef VOID_GPU_DOOR_H
#define VOID_GPU_DOOR_H

#include <stdint.h>

#include "doorWords.h"

// What C layers call; MetaScript defines each (src/gpu/doorGpu.ms, `@exportName`). A pointer
// and int64 pair is one MetaScript Span: the length counts elements.
static const int32_t DOOR_PIXEL_FORMAT_NONE = 0;
static const int32_t DOOR_PIXEL_FORMAT_RGBA8 = 2;
static const int32_t DOOR_PIXEL_FORMAT_DEPTH = 3;
static const int32_t DOOR_PIXEL_FORMAT_BGRA8 = 4;

void doorSetup(void *device, void *context, int32_t colorFormat, int32_t depthFormat, int32_t sampleCount);
void doorShutdown(void);
int32_t doorValid(void);
int32_t doorContextGeneration(void);

uint32_t doorMakeTexture(int32_t width, int32_t height, int32_t format, const uint8_t *data, int64_t length);
uint32_t doorMakeTextureView(uint32_t image);
// The whole swapchain buffer as RGBA8 rows, tightly packed, top row first; BGRA8 is swizzled.
// `outLength` must be voidSwapchainWidth() * voidSwapchainHeight() * 4. 1 on success, 0 on a size mismatch.
int32_t doorReadScreen(uint8_t *out, int64_t outLength);

void doorBeginScreenPass(float red, float green, float blue, float alpha);
void doorBeginColorPass(uint32_t view, float red, float green, float blue, float alpha);
void doorEndPass(void);
void doorCommit(void);
int32_t doorPassState(void);

#endif
