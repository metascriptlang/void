#ifndef VOID2D_SHAPER_H
#define VOID2D_SHAPER_H

#define VOID2D_SHAPE_NO_FACE -1
#define VOID2D_SHAPE_BAD_FONT -2
#define VOID2D_SHAPE_NO_MEMORY -3
#define VOID2D_SHAPE_ENGINE_ERROR -4
#define VOID2D_SHAPE_NOT_OPEN -5
#define VOID2D_SHAPE_ALREADY_OPEN -6
#define VOID2D_SHAPE_BAD_TAG -7

#define VOID2D_SHAPE_DIRECTION_UNKNOWN 0
#define VOID2D_SHAPE_DIRECTION_LTR 1
#define VOID2D_SHAPE_DIRECTION_RTL 2

#define VOID2D_SHAPE_GLYPH_ID 0
#define VOID2D_SHAPE_GLYPH_ADVANCE_X 1
#define VOID2D_SHAPE_GLYPH_ADVANCE_Y 2
#define VOID2D_SHAPE_GLYPH_OFFSET_X 3
#define VOID2D_SHAPE_GLYPH_OFFSET_Y 4
#define VOID2D_SHAPE_GLYPH_INDEX 5
#define VOID2D_SHAPE_GLYPH_CODEPOINT 6
#define VOID2D_SHAPE_GLYPH_DIRECTION 7
#define VOID2D_SHAPE_GLYPH_RUN 8
#define VOID2D_SHAPE_GLYPH_FIELDS 9

int void2dShapeBegin(int face, int direction);
int void2dShapeFeature(const char *tag, int value);
int void2dShapeCodepoint(int codepoint);
int void2dShapeBreak(void);
int void2dShapeEnd(void);
int *void2dShapeGlyph(int index);

#endif
