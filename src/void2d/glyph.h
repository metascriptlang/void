#ifndef VOID2D_GLYPH_H
#define VOID2D_GLYPH_H

int void2dGlyphFaceLoad(const char *path);
int void2dGlyphFaceSynthetic(int face, int bold, int italic);
int void2dGlyphFaceCount(void);
float void2dGlyphScale(int face, float sizePx);
float *void2dGlyphFaceMetrics(int face, float sizePx);
float *void2dGlyphDecoration(int face, float sizePx);
float *void2dGlyphFaceHeights(int face);
int void2dGlyphIndex(int face, int codepoint);
int void2dGlyphLookups(void);
float void2dGlyphAdvance(int face, int glyph, float sizePx);
float void2dGlyphKern(int face, int left, int right, float sizePx);
int *void2dGlyphBox(int face, int glyph, float sizePx, float shiftX);

#define VOID2D_MAX_GLYPH_PAGES 64

int void2dGlyphPageCreate(int size);
int void2dGlyphPageCount(void);
int void2dGlyphPageSize(int page);
void void2dGlyphPageClear(int page);
void void2dGlyphRasterize(int face, int glyph, float sizePx, float shiftX,
                          int page, int x, int y, int w, int h);
int void2dGlyphPageTexel(int page, int x, int y);
const unsigned char *void2dGlyphPageData(int page);
int void2dGlyphPageDirty(int page);
void void2dGlyphPageClean(int page);

typedef void (*GlyphRasterBox)(const unsigned char *font, int length, int glyph, float sizePx,
                               float shiftX, int *box);
typedef void (*GlyphRasterFill)(const unsigned char *font, int length, int glyph, float sizePx,
                                float shiftX, unsigned char *out, int w, int h, int stride);
void void2dGlyphSetRasterizer(GlyphRasterBox box, GlyphRasterFill fill);

#endif
