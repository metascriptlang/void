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

int void2dColourFaceSweep(const unsigned char *bytes, size_t length, size_t fontStart,
                          int glyphCount, int step, int *refused);

#endif
