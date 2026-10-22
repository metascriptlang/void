#ifndef VOID2D_SFNT_H
#define VOID2D_SFNT_H

#include <stddef.h>

#define VOID2D_SFNT_UNREADABLE -1
#define VOID2D_SFNT_NOT_AN_SFNT -2
#define VOID2D_SFNT_NO_MEMORY -3

#define VOID2D_SFNT_DRAWABLE 1
#define VOID2D_SFNT_COLOUR_BITMAP 2
#define VOID2D_SFNT_COLOUR_LAYERS 4
#define VOID2D_SFNT_OS_OUTLINES 8

#define VOID2D_SFNT_NO_SEQUENCE 0
#define VOID2D_SFNT_DEFAULT_SEQUENCE 1
#define VOID2D_SFNT_SPECIFIC_SEQUENCE 2

#define VOID2D_FONT_BYTES_OK 0
#define VOID2D_FONT_BYTES_CONFLICT -4

// A face held in memory under a name, read in place of the file of that path by the peek and the
// load; the bytes are copied and kept for the life of the process.
int void2dFontBytesAdd(const char *name, const unsigned char *bytes, int length);
const unsigned char *void2dFontBytesFind(const char *name, size_t *length);

int void2dSfntPeek(const char *path, int index);
int void2dSfntCovers(int summary, int codepoint);
int void2dSfntSequence(int summary, int codepoint, int selector);
int void2dSfntFlags(int summary);
int void2dSfntSummariesRead(void);

#endif
