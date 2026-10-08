#ifndef VOID2D_GLYPH_H
#define VOID2D_GLYPH_H

#define VOID2D_FACE_UNREADABLE -1
#define VOID2D_FACE_NOT_A_FONT -2
#define VOID2D_FACE_NO_MEMORY -3
#define VOID2D_FACE_NO_BASE -4
#define VOID2D_FACE_BAD_COLOUR -5

#define VOID2D_POLYGON_TOO_LARGE 1
#define VOID2D_POLYGON_NO_MEMORY 2

int void2dGlyphFaceLoad(const char *path);
int void2dGlyphFaceSynthetic(int face, int bold, int italic);
int void2dGlyphFaceSprite(int base);
int void2dGlyphFaceIsSprite(int face);
int *void2dGlyphSpriteCell(int face, float sizePx);
int void2dGlyphPolygonCoverage(unsigned char *coverage, int width, int height, const double *xy,
                               const int *counts, int contours);
int void2dGlyphFaceCount(void);
float void2dGlyphScale(int face, float sizePx);
float *void2dGlyphFaceMetrics(int face, float sizePx);
float *void2dGlyphDecoration(int face, float sizePx);
float *void2dGlyphFaceHeights(int face);
const unsigned char *void2dGlyphFaceData(int face, int *length);
int void2dGlyphIndex(int face, int codepoint);
unsigned int void2dGlyphLookups(void);
float void2dGlyphAdvance(int face, int glyph, float sizePx);
float void2dGlyphKern(int face, int left, int right, float sizePx);
float void2dGlyphEmbolden(int face, float sizePx);
int *void2dGlyphBox(int face, int glyph, float sizePx, float shiftX);

#define VOID2D_MAX_GLYPH_PAGES 64

#define VOID2D_PAGE_COVERAGE 0
#define VOID2D_PAGE_SDF 1
#define VOID2D_PAGE_RGBA 2
#define VOID2D_PAGE_MASK 3
#define VOID2D_PAGE_KIND_COUNT 4

int void2dGlyphPageKindBuilt(int kind);
int void2dGlyphPageCreate(int size, int kind);
int void2dGlyphPageBytes(int page);
int void2dGlyphPageKind(int page);
int void2dGlyphPageCount(void);
int void2dGlyphPageSize(int page);
void void2dGlyphPageClear(int page);
void void2dGlyphRasterize(int face, int glyph, float sizePx, float shiftX,
                          int page, int x, int y, int w, int h);
int void2dGlyphPageTexel(int page, int x, int y);
unsigned int void2dGlyphPageTexelRgba(int page, int x, int y);
#define VOID2D_BLIT_OK 0
#define VOID2D_BLIT_BAD_HANDLE 1
#define VOID2D_BLIT_WRONG_PAGE_KIND 2
#define VOID2D_BLIT_OUTSIDE_PAGE 3
int void2dGlyphPageBlitRgba(int page, int x, int y, int w, int h,
                            const unsigned int *texels, int stride);
int void2dGlyphPageBlitMask(int page, int x, int y, int w, int h,
                            const unsigned char *alpha, long long count, int stride);
const unsigned char *void2dGlyphPageData(int page);
int void2dGlyphPageUploaded(int page);
int void2dGlyphPageTakeUpload(int page);
void void2dGlyphPagesMarkDirty(void);
void void2dGlyphPagesFrameBegin(void);

int void2dGlyphColourBuilt(void);
int void2dGlyphColourFace(int face);
int void2dGlyphColourOnly(int face);
int *void2dGlyphColourBox(int face, int glyph, float sizePx);
#define VOID2D_COLOUR_RASTER_OK 0
#define VOID2D_COLOUR_RASTER_BAD_HANDLE 1
#define VOID2D_COLOUR_RASTER_WRONG_PAGE_KIND 2
#define VOID2D_COLOUR_RASTER_OUTSIDE_PAGE 3
#define VOID2D_COLOUR_RASTER_REFUSED 4
int void2dGlyphColourRasterize(int face, int glyph, float sizePx, int page, int x, int y,
                               int w, int h);
int void2dGlyphColourLayerCount(int face, int glyph);
int void2dGlyphColourLayerGlyph(int face, int glyph, int index);
unsigned int void2dGlyphColourLayerRgba(int face, int glyph, int index);

int *void2dGlyphSdfBox(int face, int glyph);
#define VOID2D_SDF_OK 0
#define VOID2D_SDF_BAD_HANDLE 1
#define VOID2D_SDF_WRONG_PAGE_KIND 2
#define VOID2D_SDF_OUTSIDE_PAGE 3
#define VOID2D_SDF_BOX_MISMATCH 4
#define VOID2D_SDF_NO_MEMORY 5
int void2dGlyphSdfRasterize(int face, int glyph, int page, int x, int y, int w, int h);
unsigned int void2dGlyphSdfGenerations(void);
int void2dGlyphSdfStbDiff(int face, int glyph, int page, int x, int y);

int *void2dGlyphOutlineBox(int face, int glyph, float sizePx, float shiftX, float widthPx);
int void2dGlyphOutlineRasterize(int face, int glyph, float sizePx, float shiftX, float widthPx,
                                int page, int x, int y, int w, int h);
unsigned int void2dGlyphOutlineGenerations(void);
int *void2dGlyphSdfOutlineBox(int face, int glyph, float biasTexels);
int void2dGlyphSdfOutlineRasterize(int face, int glyph, float biasTexels, int page, int x, int y,
                                   int w, int h);

typedef void (*GlyphRasterBox)(const unsigned char *font, int length, int glyph, float sizePx,
                               float shiftX, int *box);
typedef void (*GlyphRasterFill)(const unsigned char *font, int length, int glyph, float sizePx,
                                float shiftX, unsigned char *out, int w, int h, int stride);
void void2dGlyphSetRasterizer(GlyphRasterBox box, GlyphRasterFill fill);

#endif
