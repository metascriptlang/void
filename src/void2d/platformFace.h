#ifndef VOID2D_PLATFORM_FACE_H
#define VOID2D_PLATFORM_FACE_H

#if defined(__APPLE__)
	#define VOID2D_PLATFORM_FACES 1
#endif

void *void2dPlatformFaceOpen(const char *path, const unsigned char *bytes, int length,
                             const char *postScriptName, int glyphCount, int unitsPerEm);
void void2dPlatformFaceUnitsBox(void *face, int glyph, float *box);
void void2dPlatformFaceBox(void *face, int glyph, float sizePx, float shiftX, float skew,
                           float emboldenPx, int *box);
int void2dPlatformFaceFill(void *face, int glyph, float sizePx, float shiftX, float skew,
                           float emboldenPx, unsigned char *at, int w, int h, int stride);

#endif
