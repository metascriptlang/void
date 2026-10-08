#include "shaper.h"
#include "glyph.h"
#include <stdio.h>
#include <stdlib.h>

#define KB_TEXT_SHAPE_IMPLEMENTATION
#define KB_TEXT_SHAPE_STATIC
#if defined(__clang__)
#pragma clang attribute push(__attribute__((no_sanitize("alignment"))), apply_to = function)
#endif
#include "../../deps/kb/kb_text_shape.h"
#if defined(__clang__)
#pragma clang attribute pop
#endif

#define SHAPE_MAX_FEATURES 32

typedef struct {
	const unsigned char *bytes;
	kbts_font *font;
	kbts_shape_context *context;
} ShapeFont;

static ShapeFont *s_current;
static ShapeFont *s_fonts;
static int s_fontCount;
static int s_fontCapacity;
static int s_open;
static int s_nextIndex;
static kbts_u32 s_features[SHAPE_MAX_FEATURES];
static int s_featureCount;
static int *s_glyphs;
static int s_glyphCount;
static int s_glyphCapacity;
static int s_forced;
static int *s_input;
static unsigned char *s_inputBreak;
static int s_inputCount;
static int s_inputCapacity;
static int s_breakNext;

static int growInput(void) {
	if (s_inputCount < s_inputCapacity) { return 1; }
	int grown = s_inputCapacity ? s_inputCapacity * 2 : 128;
	int *input = (int *)realloc(s_input, (size_t)grown * sizeof(int));
	if (!input) { return 0; }
	s_input = input;
	unsigned char *marks = (unsigned char *)realloc(s_inputBreak, (size_t)grown);
	if (!marks) { return 0; }
	s_inputBreak = marks;
	s_inputCapacity = grown;
	return 1;
}

static int growGlyphs(void) {
	if (s_glyphCount < s_glyphCapacity) { return 1; }
	int grown = s_glyphCapacity ? s_glyphCapacity * 2 : 256;
	int *glyphs = (int *)realloc(s_glyphs, (size_t)grown * VOID2D_SHAPE_GLYPH_FIELDS * sizeof(int));
	if (!glyphs) { return 0; }
	s_glyphs = glyphs;
	s_glyphCapacity = grown;
	return 1;
}

static int growFonts(void) {
	if (s_fontCount < s_fontCapacity) { return 1; }
	int grown = s_fontCapacity ? s_fontCapacity * 2 : 8;
	ShapeFont *fonts = (ShapeFont *)realloc(s_fonts, (size_t)grown * sizeof(ShapeFont));
	if (!fonts) { return 0; }
	s_fonts = fonts;
	s_fontCapacity = grown;
	return 1;
}

static int fontFor(const unsigned char *bytes, int length, ShapeFont **out) {
	for (int i = 0; i < s_fontCount; i++) {
		if (s_fonts[i].bytes == bytes) {
			if (!s_fonts[i].font) { return VOID2D_SHAPE_BAD_FONT; }
			*out = &s_fonts[i];
			return 0;
		}
	}
	if (!growFonts()) { return VOID2D_SHAPE_NO_MEMORY; }
	kbts_font *font = (kbts_font *)malloc(sizeof(kbts_font));
	if (!font) { return VOID2D_SHAPE_NO_MEMORY; }
	*font = kbts_FontFromMemory((void *)bytes, length, 0, 0, 0);
	if (!kbts_FontIsValid(font)) {
		kbts_FreeFont(font);
		free(font);
		s_fonts[s_fontCount].bytes = bytes;
		s_fonts[s_fontCount].font = 0;
		s_fonts[s_fontCount].context = 0;
		s_fontCount++;
		return VOID2D_SHAPE_BAD_FONT;
	}
	kbts_shape_context *context = kbts_CreateShapeContext(0, 0);
	if (!context) {
		kbts_FreeFont(font);
		free(font);
		return VOID2D_SHAPE_NO_MEMORY;
	}
	kbts_ShapePushFont(context, font);
	s_fonts[s_fontCount].bytes = bytes;
	s_fonts[s_fontCount].font = font;
	s_fonts[s_fontCount].context = context;
	*out = &s_fonts[s_fontCount++];
	return 0;
}

static void closeShape(void) {
	for (int i = s_featureCount - 1; i >= 0; i--) {
		kbts_ShapePopFeature(s_current->context, s_features[i]);
	}
	s_featureCount = 0;
	s_open = 0;
	s_forced = 0;
}

static void discardContext(void) {
	kbts_DestroyShapeContext(s_current->context);
	s_current->context = kbts_CreateShapeContext(0, 0);
	if (s_current->context) { kbts_ShapePushFont(s_current->context, s_current->font); }
	s_featureCount = 0;
	s_open = 0;
	s_forced = 0;
}

static int openShape(int face, int direction, int forced) {
	if (s_open) { return VOID2D_SHAPE_ALREADY_OPEN; }
	int length = 0;
	const unsigned char *bytes = void2dGlyphFaceData(face, &length);
	if (!bytes) { return VOID2D_SHAPE_NO_FACE; }
	ShapeFont *font;
	int status = fontFor(bytes, length, &font);
	if (status != 0) { return status; }
	if (!font->context) { return VOID2D_SHAPE_NO_MEMORY; }
	s_current = font;
	kbts_ShapeBegin(s_current->context, (kbts_direction)direction, KBTS_LANGUAGE_DONT_KNOW);
	s_glyphCount = 0;
	s_nextIndex = 0;
	s_inputCount = 0;
	s_breakNext = 0;
	s_forced = forced ? direction : 0;
	s_open = 1;
	return 0;
}

int void2dShapeBegin(int face, int direction) {
	return openShape(face, direction, 0);
}

int void2dShapeBeginForced(int face, int direction) {
	if (direction != VOID2D_SHAPE_DIRECTION_LTR && direction != VOID2D_SHAPE_DIRECTION_RTL) {
		return VOID2D_SHAPE_ENGINE_ERROR;
	}
	return openShape(face, direction, 1);
}

int void2dShapeFeature(const char *tag, int value) {
	if (!s_open) { return VOID2D_SHAPE_NOT_OPEN; }
	if (!tag || !tag[0] || !tag[1] || !tag[2] || !tag[3] || tag[4]) { return VOID2D_SHAPE_BAD_TAG; }
	if (s_featureCount == SHAPE_MAX_FEATURES) { return VOID2D_SHAPE_TOO_MANY_FEATURES; }
	const unsigned char *bytes = (const unsigned char *)tag;
	if (bytes[0] > 0x7e || bytes[1] > 0x7e || bytes[2] > 0x7e || bytes[3] > 0x7e) {
		return VOID2D_SHAPE_BAD_TAG;
	}
	kbts_u32 id = KBTS_FOURCC(bytes[0], bytes[1], bytes[2], bytes[3]);
	kbts_ShapePushFeature(s_current->context, id, value);
	s_features[s_featureCount++] = id;
	return 0;
}

int void2dShapeCodepoint(int codepoint) {
	if (!s_open) { return VOID2D_SHAPE_NOT_OPEN; }
	if (s_forced) {
		if (!growInput()) { return VOID2D_SHAPE_NO_MEMORY; }
		s_input[s_inputCount] = codepoint;
		s_inputBreak[s_inputCount] = (unsigned char)s_breakNext;
		s_inputCount++;
		s_breakNext = 0;
		return 0;
	}
	kbts_ShapeCodepointWithUserId(s_current->context, codepoint, s_nextIndex++);
	return 0;
}

int void2dShapeBreak(void) {
	if (!s_open) { return VOID2D_SHAPE_NOT_OPEN; }
	if (s_forced) {
		s_breakNext = 1;
		return 0;
	}
	kbts_ShapeManualBreak(s_current->context);
	return 0;
}

static int feedForced(void) {
	int count = s_inputCount;
	kbts_script *scripts = 0;
	unsigned char *starts = 0;
	if (count > 0) {
		scripts = (kbts_script *)calloc((size_t)count, sizeof(kbts_script));
		starts = (unsigned char *)calloc((size_t)count, 1);
		if (!scripts || !starts) {
			free(scripts);
			free(starts);
			return VOID2D_SHAPE_NO_MEMORY;
		}
		kbts_break_state state;
		kbts_BreakBegin(&state, (kbts_direction)s_forced, KBTS_JAPANESE_LINE_BREAK_STYLE_NORMAL, 0);
		for (int i = 0; i < count; i++) {
			kbts_BreakAddCodepoint(&state, s_input[i], 1, i == count - 1);
			kbts_break found;
			while (kbts_Break(&state, &found)) {
				if ((found.Flags & KBTS_BREAK_FLAG_SCRIPT) && found.Position >= 0 &&
					found.Position < count) {
					starts[found.Position] = 1;
					scripts[found.Position] = found.Script;
				}
			}
		}
	}
	kbts_ShapeBeginManualRuns(s_current->context);
	kbts_script current = KBTS_SCRIPT_DONT_KNOW;
	for (int i = 0; i < count; i++) {
		if (starts[i]) { current = scripts[i]; }
		if (i == 0 || starts[i] || s_inputBreak[i]) {
			kbts_ShapeNextManualRun(s_current->context, (kbts_direction)s_forced, current);
		}
		kbts_ShapeCodepointWithUserId(s_current->context, s_input[i], i);
	}
	kbts_ShapeEndManualRuns(s_current->context);
	free(scripts);
	free(starts);
	return 0;
}

int void2dShapeEnd(void) {
	if (!s_open) { return VOID2D_SHAPE_NOT_OPEN; }
	if (s_forced) {
		int fed = feedForced();
		if (fed != 0) {
			discardContext();
			s_glyphCount = 0;
			return fed;
		}
	}
	kbts_ShapeEnd(s_current->context);
	int run = 0;
	int status = 0;
	kbts_run r;
	while (status == 0 && kbts_ShapeRun(s_current->context, &r)) {
		kbts_glyph *glyph;
		while (kbts_GlyphIteratorNext(&r.Glyphs, &glyph)) {
			if (!growGlyphs()) {
				status = VOID2D_SHAPE_NO_MEMORY;
				break;
			}
			kbts_shape_codepoint source;
			int *out = s_glyphs + (size_t)s_glyphCount * VOID2D_SHAPE_GLYPH_FIELDS;
			int found = kbts_ShapeGetShapeCodepoint(
				s_current->context, glyph->UserIdOrCodepointIndex, &source);
			if (!found) {
				status = VOID2D_SHAPE_ENGINE_ERROR;
				break;
			}
			out[VOID2D_SHAPE_GLYPH_ID] = glyph->Id;
			out[VOID2D_SHAPE_GLYPH_ADVANCE_X] = glyph->AdvanceX;
			out[VOID2D_SHAPE_GLYPH_ADVANCE_Y] = glyph->AdvanceY;
			out[VOID2D_SHAPE_GLYPH_OFFSET_X] = glyph->OffsetX;
			out[VOID2D_SHAPE_GLYPH_OFFSET_Y] = glyph->OffsetY;
			out[VOID2D_SHAPE_GLYPH_INDEX] = source.UserId;
			out[VOID2D_SHAPE_GLYPH_CODEPOINT] = (int)glyph->Codepoint;
			out[VOID2D_SHAPE_GLYPH_DIRECTION] = (int)r.Direction;
			out[VOID2D_SHAPE_GLYPH_RUN] = run;
			s_glyphCount++;
		}
		run++;
	}
	if (status == 0 && kbts_ShapeError(s_current->context) != KBTS_SHAPE_ERROR_NONE) {
		status = VOID2D_SHAPE_ENGINE_ERROR;
	}
	if (status != 0) {
		discardContext();
		s_glyphCount = 0;
		return status;
	}
	closeShape();
	return s_glyphCount;
}

int void2dShapeCount(void) {
	return s_glyphCount;
}

int *void2dShapeGlyph(int index) {
	if (index < 0 || index >= s_glyphCount) { return 0; }
	return s_glyphs + (size_t)index * VOID2D_SHAPE_GLYPH_FIELDS;
}
