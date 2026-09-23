#ifndef VOID2D_GLYPH_H
#define VOID2D_GLYPH_H

int void2dGlyphFaceLoad(const char *path);
int void2dGlyphFaceCount(void);
float void2dGlyphScale(int face, float sizePx);
float *void2dGlyphFaceMetrics(int face, float sizePx);
float *void2dGlyphDecoration(int face, float sizePx);
int void2dGlyphIndex(int face, int codepoint);
float void2dGlyphAdvance(int face, int glyph, float sizePx);
float void2dGlyphKern(int face, int left, int right, float sizePx);
int *void2dGlyphBox(int face, int glyph, float sizePx, float shiftX);

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

#endif
