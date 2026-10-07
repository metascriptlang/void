#ifndef VOID2D_SPRITE_GLYPH_H
#define VOID2D_SPRITE_GLYPH_H

#include <stdint.h>

#define VOID2D_SPRITE_OK 0
#define VOID2D_SPRITE_NO_SUCH_ID 1
#define VOID2D_SPRITE_BAD_CELL 2
#define VOID2D_SPRITE_GEOMETRY 3
#define VOID2D_SPRITE_NO_MEMORY 4
#define VOID2D_SPRITE_BAD_BUFFER 5

int void2dSpriteCount(void);
int void2dSpriteIndex(int codepoint);
int void2dSpriteCodepoint(int id);
int void2dSpriteTableFault(void);
int void2dSpritePadding(int cellSize);
int void2dSpriteCanvasWidth(int cellWidth);
int void2dSpriteCanvasHeight(int cellHeight);
int void2dSpriteDraw(int id, int cellWidth, int cellHeight, int thickness, uint8_t *canvas,
                     int64_t count);
int void2dSpriteInk(int id, int cellWidth, int cellHeight, int thickness, int *box,
                    const uint8_t **rows, int *stride);

#endif
