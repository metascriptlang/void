#ifndef VOID2D_SFNT_H
#define VOID2D_SFNT_H

#define VOID2D_SFNT_UNREADABLE -1
#define VOID2D_SFNT_NOT_AN_SFNT -2
#define VOID2D_SFNT_NO_MEMORY -3

#define VOID2D_SFNT_DRAWABLE 1
#define VOID2D_SFNT_COLOUR_BITMAP 2
#define VOID2D_SFNT_COLOUR_LAYERS 4

#define VOID2D_SFNT_NO_SEQUENCE 0
#define VOID2D_SFNT_DEFAULT_SEQUENCE 1
#define VOID2D_SFNT_SPECIFIC_SEQUENCE 2

int void2dSfntPeek(const char *path);
int void2dSfntCovers(int summary, int codepoint);
int void2dSfntSequence(int summary, int codepoint, int selector);
int void2dSfntFlags(int summary);
int void2dSfntSummariesRead(void);

#endif
