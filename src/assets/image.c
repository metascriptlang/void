// Void Asset — Image loading via stb_image

#include "image.h"

#include <limits.h>
#include <string.h>

#define STB_IMAGE_IMPLEMENTATION
#include "../../deps/stb/stb_image.h"

static int s_width = 0, s_height = 0;

void *void_load_image(const char *path, int desired_channels) {
	int channels;
	unsigned char *data = stbi_load(path, &s_width, &s_height, &channels, desired_channels);
	return (void *)data;
}

int void_image_width(void) { return s_width; }
int void_image_height(void) { return s_height; }

void void_free_image(void *data) {
	if (data) stbi_image_free(data);
}

int64_t void_image_size(const uint8_t *bytes, int64_t length) {
	int width, height, channels;
	if (length <= 0 || length > INT_MAX) return -1;
	if (!stbi_info_from_memory(bytes, (int)length, &width, &height, &channels)) return -1;
	return ((int64_t)width << 32) | (int64_t)(uint32_t)height;
}

int32_t void_decode_image(const uint8_t *bytes, int64_t length, uint32_t *pixels, int64_t count) {
	int width, height, channels;
	if (length <= 0 || length > INT_MAX) return 0;
	stbi_uc *data = stbi_load_from_memory(bytes, (int)length, &width, &height, &channels, 4);
	if (!data) return 0;
	int32_t fits = (int64_t)width * height == count;
	if (fits) memcpy(pixels, data, (size_t)count * 4);
	stbi_image_free(data);
	return fits;
}
