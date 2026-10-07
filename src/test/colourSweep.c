#include "colourSweep.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../void2d/colourEmoji/colourFace.h"

static int s_refused;

int colourSweepRefused(void) { return s_refused; }

static unsigned char *readAll(const char *path, size_t *length) {
	FILE *file = fopen(path, "rb");
	if (!file) { return NULL; }
	fseek(file, 0, SEEK_END);
	long size = ftell(file);
	fseek(file, 0, SEEK_SET);
	unsigned char *bytes = (unsigned char *)malloc(size > 0 ? (size_t)size : 1);
	if (bytes && fread(bytes, 1, (size_t)size, file) != (size_t)size) {
		free(bytes);
		bytes = NULL;
	}
	fclose(file);
	*length = (size_t)size;
	return bytes;
}

static int glyphsOf(const unsigned char *bytes, size_t length) {
	ColourFace *face = NULL;
	ColourSfnt sfnt;
	int glyphs = -1;
	if (void2dColourFaceOpen(bytes, length, 0, &face) == VOID2D_COLOUR_OK &&
		void2dColourFaceSfnt(face, &sfnt) == VOID2D_COLOUR_OK) {
		glyphs = sfnt.numGlyphs;
	}
	free(face);
	return glyphs;
}

int colourSweepRun(const char *path, int step) {
	size_t length = 0;
	unsigned char *bytes = readAll(path, &length);
	s_refused = 0;
	if (!bytes) { return -1; }
	int glyphCount = glyphsOf(bytes, length);
	if (glyphCount < 0) {
		free(bytes);
		return -1;
	}
	int runs = 0;
	if (step < 1) { step = 1; }
	unsigned int tile[64 * 64];
	for (size_t cut = 0; cut <= length; cut += (size_t)step) {
		for (int variant = 0; variant < 2; variant++) {
			size_t usable = variant == 0 ? cut : length;
			unsigned char *copy = (unsigned char *)malloc(usable ? usable : 1);
			if (!copy) { free(bytes); return -1; }
			memcpy(copy, bytes, usable);
			if (variant == 1 && cut + 4 <= length) { memset(copy + cut, 0xFF, 4); }
			ColourFace *face = NULL;
			int status = void2dColourFaceOpen(copy, usable, 0, &face);
			if (status == VOID2D_COLOUR_OK) {
				for (int g = 0; g < glyphCount; g++) {
					ColourLayer layers[VOID2D_COLOUR_MAX_LAYERS];
					if (void2dColourGlyphLayers(face, g, layers, VOID2D_COLOUR_MAX_LAYERS) < 0) {
						s_refused++;
					}
					ColourBox box;
					if (void2dColourGlyphBox(face, g, 16.0f, &box) == VOID2D_COLOUR_PRESENT &&
						box.width <= 64 && box.height <= 64) {
						if (void2dColourGlyphRender(face, g, 16.0f, tile, 64, box.width,
							box.height) == VOID2D_COLOUR_REFUSED) { s_refused++; }
					}
				}
				free(face);
			} else if (status == VOID2D_COLOUR_BAD_TABLE) {
				s_refused++;
			}
			free(copy);
			runs++;
		}
	}
	free(bytes);
	return runs;
}
