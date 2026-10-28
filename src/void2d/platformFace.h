#ifndef VOID2D_PLATFORM_FACE_H
#define VOID2D_PLATFORM_FACE_H

#if defined(__APPLE__) || defined(__EMSCRIPTEN__)
	#define VOID2D_PLATFORM_FACES 1
#endif

#if defined(__EMSCRIPTEN__)
	#define VOID2D_BROWSER_FACES 1
	#define VOID2D_BROWSER_UNITS_PER_EM 2048
#endif

void *void2dPlatformFaceOpen(const char *path, const unsigned char *bytes, int length,
                             const char *postScriptName, int glyphCount, int unitsPerEm);
void void2dPlatformFaceUnitsBox(void *face, int glyph, float *box);
void void2dPlatformFaceBox(void *face, int glyph, float sizePx, float shiftX, float skew,
                           float emboldenPx, int *box);
int void2dPlatformFaceFill(void *face, int glyph, float sizePx, float shiftX, float skew,
                           float emboldenPx, unsigned char *at, int w, int h, int stride);

#ifdef VOID2D_BROWSER_FACES
void *void2dPlatformFaceOpenBrowser(const char *style, const char *family);
int void2dPlatformFaceGlyph(void *face, int codepoint);
void void2dPlatformFaceVMetrics(void *face, int *ascent, int *descent, int *lineGap);
int void2dPlatformFaceAdvance(void *face, int glyph);
#endif

#endif
