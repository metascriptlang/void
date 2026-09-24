// See pngio.h.

#include "pngio.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define STB_IMAGE_IMPLEMENTATION
#include "../../deps/stb/stb_image.h"

#define STB_IMAGE_WRITE_IMPLEMENTATION
#define STBI_WRITE_NO_STDIO_WARNING
#include "../../deps/stb/stb_image_write.h"

typedef struct {
	unsigned char *rgba;
	int width;
	int height;
} voidPngSlot;

static voidPngSlot s_slots[VOID_PNG_SLOTS];

static int s_differ = -1;
static int s_maxDelta = 0;
static int s_overOne = 0;
static int s_minX = 0;
static int s_minY = 0;
static int s_maxX = -1;
static int s_maxY = -1;
static unsigned char *s_mask = NULL;
static int s_maskWidth = 0;
static int s_maskHeight = 0;

int voidPngLoad(int slot, const char *path) {
	if (slot < 0 || slot >= VOID_PNG_SLOTS) return 0;
	voidPngSlot *s = &s_slots[slot];
	int channels = 0;
	unsigned char *data = stbi_load(path, &s->width, &s->height, &channels, 4);
	if (!data) {
		s->width = 0;
		s->height = 0;
		return 0;
	}
	stbi_image_free(s->rgba);
	s->rgba = data;
	return 1;
}

int voidPngWidth(int slot) {
	if (slot < 0 || slot >= VOID_PNG_SLOTS) return 0;
	return s_slots[slot].width;
}

int voidPngHeight(int slot) {
	if (slot < 0 || slot >= VOID_PNG_SLOTS) return 0;
	return s_slots[slot].height;
}

int voidPngPixel(int slot, int x, int y, int channel) {
	if (slot < 0 || slot >= VOID_PNG_SLOTS) return -1;
	const voidPngSlot *s = &s_slots[slot];
	if (!s->rgba || channel < 0 || channel > 3) return -1;
	if (x < 0 || y < 0 || x >= s->width || y >= s->height) return -1;
	return (int)s->rgba[((size_t)y * (size_t)s->width + (size_t)x) * 4u + (size_t)channel];
}

int voidPngDiff(void) {
	const voidPngSlot *a = &s_slots[0];
	const voidPngSlot *b = &s_slots[1];
	s_differ = -1;
	s_maxDelta = 0;
	s_overOne = 0;
	s_minX = 0;
	s_minY = 0;
	s_maxX = -1;
	s_maxY = -1;
	if (!a->rgba || !b->rgba) return -1;
	if (a->width != b->width || a->height != b->height) return -1;

	free(s_mask);
	s_maskWidth = a->width;
	s_maskHeight = a->height;
	s_mask = (unsigned char *)calloc((size_t)s_maskWidth * (size_t)s_maskHeight * 3u, 1u);

	int differ = 0;
	s_minX = a->width;
	s_minY = a->height;
	for (int y = 0; y < a->height; y++) {
		for (int x = 0; x < a->width; x++) {
			size_t i = ((size_t)y * (size_t)a->width + (size_t)x) * 4u;
			// RGB only: tests/capture/capture.c stores three channels, and stb_image pads
			// the fourth to 255 on load, so a fourth-channel comparison would be a constant.
			int delta = 0;
			for (int c = 0; c < 3; c++) {
				int d = (int)a->rgba[i + (size_t)c] - (int)b->rgba[i + (size_t)c];
				if (d < 0) d = -d;
				if (d > delta) delta = d;
			}
			if (delta == 0) continue;
			differ++;
			if (delta > 1) s_overOne++;
			if (delta > s_maxDelta) s_maxDelta = delta;
			if (x < s_minX) s_minX = x;
			if (y < s_minY) s_minY = y;
			if (x > s_maxX) s_maxX = x;
			if (y > s_maxY) s_maxY = y;
			if (s_mask) {
				size_t m = ((size_t)y * (size_t)s_maskWidth + (size_t)x) * 3u;
				s_mask[m] = 255;
				s_mask[m + 1] = 255;
				s_mask[m + 2] = 255;
			}
		}
	}
	if (differ == 0) {
		s_minX = 0;
		s_minY = 0;
	}
	s_differ = differ;
	return differ;
}

int voidPngDiffMaxDelta(void) { return s_maxDelta; }
int voidPngDiffOverOne(void) { return s_overOne; }
int voidPngDiffMinX(void) { return s_minX; }
int voidPngDiffMinY(void) { return s_minY; }
int voidPngDiffMaxX(void) { return s_maxX; }
int voidPngDiffMaxY(void) { return s_maxY; }

int voidPngWriteDiffMask(const char *path) {
	if (!s_mask || s_maskWidth <= 0 || s_maskHeight <= 0) return 0;
	return stbi_write_png(path, s_maskWidth, s_maskHeight, 3, s_mask, s_maskWidth * 3) != 0 ? 1 : 0;
}
