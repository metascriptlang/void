#define FT2_BUILD_LIBRARY
#define FT_CONFIG_MODULES_H "freetypeModules.h"

#include "freetypeRaster.h"
#include "../../src/void2d/glyph.h"

#include "../../deps/freetype/src/base/ftsystem.c"
#include "../../deps/freetype/src/base/ftinit.c"
#include "../../deps/freetype/src/base/ftdebug.c"
#include "../../deps/freetype/src/base/ftbase.c"
#include "../../deps/freetype/src/base/ftbitmap.c"
#include "../../deps/freetype/src/base/ftmm.c"
#include "../../deps/freetype/src/gzip/ftgzip.c"
#include "../../deps/freetype/src/sfnt/sfnt.c"
#include "../../deps/freetype/src/truetype/truetype.c"
#include "../../deps/freetype/src/smooth/smooth.c"
#include "../../deps/freetype/src/autofit/autofit.c"
#include "../../deps/freetype/src/psnames/psnames.c"

#define FREETYPE_MAX_FACES 16

typedef struct {
	const unsigned char *font;
	FT_Face face;
} CachedFace;

static FT_Library s_library;
static CachedFace s_faces[FREETYPE_MAX_FACES];
static int s_faceCount;
static FT_Int32 s_loadFlags;

static FT_Face faceFor(const unsigned char *font, int length) {
	for (int i = 0; i < s_faceCount; i++) {
		if (s_faces[i].font == font) { return s_faces[i].face; }
	}
	FT_Face face = NULL;
	if (s_faceCount == FREETYPE_MAX_FACES || FT_New_Memory_Face(s_library, font, length, 0, &face)) {
		fprintf(stderr, "void2d experiment: FreeType cannot open face %d\n", s_faceCount);
		return NULL;
	}
	s_faces[s_faceCount].font = font;
	s_faces[s_faceCount].face = face;
	s_faceCount++;
	return face;
}

static FT_GlyphSlot render(const unsigned char *font, int length, int glyph, float sizePx, float shiftX) {
	FT_Face face = faceFor(font, length);
	if (!face) { return NULL; }
	if (FT_Set_Char_Size(face, 0, (FT_F26Dot6)(sizePx * 64.0f + 0.5f), 72, 72)) { return NULL; }
	if (FT_Load_Glyph(face, (FT_UInt)glyph, s_loadFlags)) { return NULL; }
	if (face->glyph->format != FT_GLYPH_FORMAT_OUTLINE) { return NULL; }
	FT_Outline_Translate(&face->glyph->outline, (FT_Pos)(shiftX * 64.0f + 0.5f), 0);
	if (FT_Render_Glyph(face->glyph, FT_RENDER_MODE_NORMAL)) { return NULL; }
	return face->glyph;
}

static void box(const unsigned char *font, int length, int glyph, float sizePx, float shiftX, int *out) {
	out[0] = out[1] = out[2] = out[3] = 0;
	FT_GlyphSlot slot = render(font, length, glyph, sizePx, shiftX);
	if (!slot || slot->bitmap.width == 0 || slot->bitmap.rows == 0) { return; }
	out[0] = slot->bitmap_left;
	out[1] = -slot->bitmap_top;
	out[2] = out[0] + (int)slot->bitmap.width;
	out[3] = out[1] + (int)slot->bitmap.rows;
}

static void fill(const unsigned char *font, int length, int glyph, float sizePx, float shiftX,
                 unsigned char *out, int w, int h, int stride) {
	FT_GlyphSlot slot = render(font, length, glyph, sizePx, shiftX);
	if (!slot) { return; }
	int rows = (int)slot->bitmap.rows < h ? (int)slot->bitmap.rows : h;
	int columns = (int)slot->bitmap.width < w ? (int)slot->bitmap.width : w;
	for (int y = 0; y < rows; y++) {
		memcpy(out + (size_t)y * (size_t)stride, slot->bitmap.buffer + (size_t)y * (size_t)slot->bitmap.pitch,
			(size_t)columns);
	}
}

int void2dFreetypeInstall(int hinted) {
	if (!s_library && FT_Init_FreeType(&s_library)) {
		fprintf(stderr, "void2d experiment: FreeType did not initialise\n");
		return 0;
	}
	s_loadFlags = hinted ? FT_LOAD_TARGET_LIGHT : FT_LOAD_NO_HINTING;
	void2dGlyphSetRasterizer(box, fill);
	return 1;
}
