// Void Asset — Image loading via stb_image

#ifndef VOID_ASSET_IMAGE_H
#define VOID_ASSET_IMAGE_H

#include <stdint.h>

void *void_load_image(const char *path, int desired_channels);
int void_image_width(void);
int void_image_height(void);
void void_free_image(void *data);

int64_t void_image_size(const uint8_t *bytes, int64_t length);
int32_t void_decode_image(const uint8_t *bytes, int64_t length, uint32_t *pixels, int64_t count);

int64_t void_gif_scan(const uint8_t *bytes, int64_t length);
int32_t void_decode_gif(const uint8_t *bytes, int64_t length, uint32_t *pixels, int64_t pixelCount,
	int32_t *delays, int64_t delayCount);

#endif
