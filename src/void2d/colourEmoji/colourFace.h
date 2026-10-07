#ifndef VOID2D_COLOUR_FACE_H
#define VOID2D_COLOUR_FACE_H

#include <stddef.h>

typedef struct ColourFace ColourFace;

#define VOID2D_COLOUR_OK 0
#define VOID2D_COLOUR_NONE 1
#define VOID2D_COLOUR_BAD_TABLE -1
#define VOID2D_COLOUR_NO_MEMORY -2

typedef struct {
	size_t head, hhea, hmtx, hmtxLength;
	int numGlyphs;
	int outlines;
} ColourSfnt;

int void2dColourFaceOpen(const unsigned char *bytes, size_t length, size_t fontStart,
                         ColourFace **out);
int void2dColourFaceSfnt(const ColourFace *face, ColourSfnt *out);
int void2dColourFaceGlyphIndex(const ColourFace *face, int codepoint);
const char *void2dColourFaceReason(void);

#define VOID2D_COLOUR_ABSENT 0
#define VOID2D_COLOUR_PRESENT 1
#define VOID2D_COLOUR_REFUSED -1

typedef struct {
	int width, height;
	int bearingX, bearingY;
	int ppem;
} ColourBox;

int void2dColourGlyphBox(ColourFace *face, int glyph, float sizePx, ColourBox *box);
int void2dColourGlyphRender(ColourFace *face, int glyph, float sizePx, unsigned int *dst,
                            int strideTexels, int width, int height);

typedef struct {
	int glyph;
	unsigned char r, g, b, a;
} ColourLayer;

int void2dColourFaceHasLayers(const ColourFace *face);
int void2dColourGlyphLayers(ColourFace *face, int glyph, ColourLayer *out, int capacity);
void void2dColourCompose(unsigned int *dst, int stride, int dw, int dh,
                         const unsigned char *coverage, int coverageStride, int ox, int oy,
                         int cw, int ch, const ColourLayer *colour);

#define VOID2D_COLOUR_MAX_LAYERS 256
#define VOID2D_COLOUR_MAX_TEXELS (4096 * 4096)
#define VOID2D_COLOUR_MAX_SIZE_PX 16384.0f

int void2dColourFaceSweep(const unsigned char *bytes, size_t length, size_t fontStart,
                          int glyphCount, int step, int *refused);

#endif
