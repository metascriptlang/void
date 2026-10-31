#pragma once
#include <stddef.h>
#include <stdint.h>

typedef struct {
	float affine[4];
	float originSize[4];
	float uvRadii[4];
	float borders[4];
	float params0[4];
	float params1[4];
	uint32_t colorFill;
	uint32_t colorBorder;
	uint32_t colorExtra;
} void2dUiInstance;

typedef struct {
	float affine[4];
	float originSize[4];
	float uv[4];
	float color[4];
} void2dSpriteInstance;

static const size_t void2dUiInstanceOffsets[9] = {
	offsetof(void2dUiInstance, affine),
	offsetof(void2dUiInstance, originSize),
	offsetof(void2dUiInstance, uvRadii),
	offsetof(void2dUiInstance, borders),
	offsetof(void2dUiInstance, params0),
	offsetof(void2dUiInstance, params1),
	offsetof(void2dUiInstance, colorFill),
	offsetof(void2dUiInstance, colorBorder),
	offsetof(void2dUiInstance, colorExtra),
};

static const size_t void2dSpriteInstanceOffsets[4] = {
	offsetof(void2dSpriteInstance, affine),
	offsetof(void2dSpriteInstance, originSize),
	offsetof(void2dSpriteInstance, uv),
	offsetof(void2dSpriteInstance, color),
};

#define VOID2D_SPRITE_REC_FLOATS 16
