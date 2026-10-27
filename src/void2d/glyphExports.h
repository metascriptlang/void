#ifndef VOID2D_GLYPH_EXPORTS_H
#define VOID2D_GLYPH_EXPORTS_H

#include <stdint.h>

#define VOID2D_POLYGON_TOO_LARGE 1
#define VOID2D_POLYGON_NO_MEMORY 2
#define VOID2D_MAX_GLYPH_PAGES 64
#define VOID2D_PAGE_COVERAGE 0
#define VOID2D_PAGE_SDF 1
#define VOID2D_PAGE_RGBA 2
#define VOID2D_PAGE_MASK 3

int void2dGlyphPolygonCoverage(unsigned char *coverage, int width, int height, const double *xy,
                               const int *counts, int contours);
const unsigned char *void2dGlyphFaceData(int face, int *length);
unsigned int void2dGlyphPageGeneration(int page);
int void2dGlyphPageBytes(int page);
int void2dGlyphPageKind(int page);
int void2dGlyphPageCount(void);
int void2dGlyphPageSize(int page);
const unsigned char *void2dGlyphPageData(int page);
int void2dGlyphPageTakeUpload(int page);
int *void2dGlyphPageUploadBox(int page);
void void2dGlyphPagesMarkDirty(void);
void void2dGlyphPagesFrameBegin(void);

#endif
