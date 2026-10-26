#ifndef VOID2D_FONT_BYTES_H
#define VOID2D_FONT_BYTES_H

#include <stddef.h>

#define VOID2D_SFNT_NO_MEMORY -3

#define VOID2D_FONT_BYTES_OK 0
#define VOID2D_FONT_BYTES_CONFLICT -4

// A face held in memory under a name, read in place of the file of that path by the peek and the
// load; the bytes are copied and kept for the life of the process.
int void2dFontBytesAdd(const char *name, const unsigned char *bytes, int length);
const unsigned char *void2dFontBytesFind(const char *name, size_t *length);

#endif
