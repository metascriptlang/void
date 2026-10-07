#ifndef VOID2D_SVG_MASK_H
#define VOID2D_SVG_MASK_H

#include <stdint.h>

#define VOID2D_SVG_NOT_SVG -1
#define VOID2D_SVG_REFUSED -2
#define VOID2D_SVG_NO_SIZE -3
#define VOID2D_SVG_NO_MEMORY -4
#define VOID2D_SVG_BAD_HANDLE -5
#define VOID2D_SVG_BAD_SIZE -6
#define VOID2D_SVG_TOO_LARGE -7

int void2dSvgMaskParse(const char *source);
const char *void2dSvgMaskReason(void);
float void2dSvgMaskWidth(int handle);
float void2dSvgMaskHeight(int handle);
int void2dSvgMaskFree(int handle);
int void2dSvgMaskLive(void);
int void2dSvgMaskParsed(void);
int void2dSvgMaskReleased(void);
int void2dSvgMaskRasterize(int handle, int width, int height, uint8_t *alpha, int64_t count);

#endif
