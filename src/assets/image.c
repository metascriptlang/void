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

#define GIF_SCAN_UNDECODABLE (-1)
#define GIF_SCAN_DISPOSAL_3 (-2)
#define GIF_SCAN_MAX_FRAMES 0xFFFFFFF

static int64_t skipSubBlocks(const uint8_t *b, int64_t n, int64_t i) {
	for (;;) {
		if (i >= n) return -1;
		int64_t size = b[i++];
		if (size == 0) return i;
		i += size;
		if (i > n) return -1;
	}
}

int64_t void_gif_scan(const uint8_t *b, int64_t n) {
	if (n < 13 || memcmp(b, "GIF8", 4) != 0 || (b[4] != '7' && b[4] != '9') || b[5] != 'a') {
		return GIF_SCAN_UNDECODABLE;
	}
	const int64_t width = b[6] | (b[7] << 8);
	const int64_t height = b[8] | (b[9] << 8);
	int64_t i = 13;
	if (b[10] & 0x80) i += (int64_t)3 << ((b[10] & 7) + 1);
	int64_t frames = 0;
	int64_t restoringFrame = -1;
	int disposal = 0;
	while (i < n) {
		const uint8_t tag = b[i++];
		if (tag == 0x3B) {
			if (frames == 0 || width == 0 || height == 0) return GIF_SCAN_UNDECODABLE;
			if (restoringFrame >= 0 && restoringFrame < frames - 1) return GIF_SCAN_DISPOSAL_3;
			if (frames > GIF_SCAN_MAX_FRAMES) return GIF_SCAN_UNDECODABLE;
			return (width << 44) | (height << 28) | frames;
		}
		if (tag == 0x21) {
			if (i + 1 >= n) return GIF_SCAN_UNDECODABLE;
			const uint8_t label = b[i++];
			if (label == 0xF9) {
				if (i + 2 >= n) return GIF_SCAN_UNDECODABLE;
				disposal = (b[i + 1] >> 2) & 7;
			}
			i = skipSubBlocks(b, n, i);
		} else if (tag == 0x2C) {
			if (i + 9 >= n) return GIF_SCAN_UNDECODABLE;
			const uint8_t packed = b[i + 8];
			i += 9;
			if (packed & 0x80) i += (int64_t)3 << ((packed & 7) + 1);
			i++;
			if (i >= n) return GIF_SCAN_UNDECODABLE;
			i = skipSubBlocks(b, n, i);
			if (disposal == 3 && frames >= 1 && restoringFrame < 0) restoringFrame = frames;
			frames++;
		} else {
			return GIF_SCAN_UNDECODABLE;
		}
		if (i < 0) return GIF_SCAN_UNDECODABLE;
	}
	return GIF_SCAN_UNDECODABLE;
}

int32_t void_decode_gif(const uint8_t *bytes, int64_t length, uint32_t *pixels, int64_t pixelCount,
	int32_t *delays, int64_t delayCount) {
	int width, height, frames, channels;
	int *stbDelays = NULL;
	if (length <= 0 || length > INT_MAX) return 0;
	stbi_uc *data = stbi_load_gif_from_memory(bytes, (int)length, &stbDelays, &width, &height,
		&frames, &channels, 4);
	if (!data) {
		stbi_image_free(stbDelays);
		return 0;
	}
	int32_t fits = (int64_t)width * height * frames == pixelCount && frames == delayCount;
	if (fits) {
		memcpy(pixels, data, (size_t)pixelCount * 4);
		for (int i = 0; i < frames; i++) delays[i] = stbDelays[i];
	}
	stbi_image_free(data);
	stbi_image_free(stbDelays);
	return fits;
}
