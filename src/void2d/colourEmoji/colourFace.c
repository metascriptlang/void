#include "colourFace.h"

#include <math.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define STBI_ONLY_PNG
#define STBI_NO_STDIO
#define STBI_NO_HDR
#define STBI_NO_LINEAR
#define STBI_MAX_DIMENSIONS 4096
#define STB_IMAGE_STATIC
#define STB_IMAGE_IMPLEMENTATION
#include "../../../deps/stb/stb_image.h"

#define MAX_TABLES 256
#define MAX_STRIKES 64
#define MAX_SIDE 4096
#define REASON_BYTES 256
#define REFUSED_SLOTS 64

typedef struct {
	size_t offset, length;
	int found;
} Table;

typedef struct {
	const unsigned char *p;
	uint64_t n;
	int bad;
} Span;

#define KIND_CBDT 0
#define KIND_SBIX 1
#define MAX_SBIX_DUPE 8
#define MAX_REFUSED_TAGS 8
#define MAX_REPORTED 64
#define MAX_LAYERS 256

typedef struct {
	int kind;
	uint64_t arrayAt;
	unsigned subtables;
	int ppemX, ppemY;
} Strike;

typedef struct {
	const unsigned char *png;
	size_t pngLength;
	int width, height, bearingX, bearingY;
	int ppem;
} Bitmap;

struct ColourFace {
	const unsigned char *bytes;
	size_t length;
	Table cmap, head, hhea, hmtx, maxp, glyf, loca, cff, cblc, cbdt, sbix, colr, cpal;
	int numGlyphs;
	uint64_t index;
	unsigned indexFormat;
	Strike strikes[MAX_STRIKES];
	int strikeCount;
	unsigned long long refused[REFUSED_SLOTS / 64];
	uint32_t refusedTags[MAX_REFUSED_TAGS];
	int refusedTagCount;
	uint64_t colrBases, colrLayers, paletteAt;
	unsigned colrBaseCount, colrLayerCount, paletteEntries;
	int reported[MAX_REPORTED];
	int reportedCount;
};

static char s_reason[REASON_BYTES];

static int fail(const char *format, ...) {
	va_list args;
	va_start(args, format);
	vsnprintf(s_reason, sizeof(s_reason), format, args);
	va_end(args);
	return VOID2D_COLOUR_BAD_TABLE;
}

const char *void2dColourFaceReason(void) { return s_reason; }

static unsigned rd8(Span *s, uint64_t at) {
	if (at >= s->n) { s->bad = 1; return 0; }
	return s->p[at];
}

static unsigned rd16(Span *s, uint64_t at) {
	if (at > s->n || s->n - at < 2) { s->bad = 1; return 0; }
	return ((unsigned)s->p[at] << 8) | s->p[at + 1];
}

static int rdI8(Span *s, uint64_t at) { return (signed char)rd8(s, at); }

static uint32_t rd32(Span *s, uint64_t at) {
	if (at > s->n || s->n - at < 4) { s->bad = 1; return 0; }
	return ((uint32_t)s->p[at] << 24) | ((uint32_t)s->p[at + 1] << 16) |
		((uint32_t)s->p[at + 2] << 8) | s->p[at + 3];
}

static Span tableSpan(const ColourFace *face, Table t) {
	Span s = { face->bytes + t.offset, t.length, 0 };
	return s;
}

static int refusedBefore(ColourFace *face, int slot) {
	unsigned long long bit = 1ull << (slot & 63);
	unsigned long long *word = &face->refused[slot >> 6];
	if (*word & bit) { return 1; }
	*word |= bit;
	return 0;
}

static int tagRefusedBefore(ColourFace *face, uint32_t tag) {
	for (int i = 0; i < face->refusedTagCount; i++) {
		if (face->refusedTags[i] == tag) { return 1; }
	}
	if (face->refusedTagCount < MAX_REFUSED_TAGS) {
		face->refusedTags[face->refusedTagCount++] = tag;
	}
	return 0;
}

static int reportedBefore(ColourFace *face, int glyph) {
	for (int i = 0; i < face->reportedCount; i++) {
		if (face->reported[i] == glyph) { return 1; }
	}
	if (face->reportedCount == MAX_REPORTED) { return 1; }
	face->reported[face->reportedCount++] = glyph;
	if (face->reportedCount == MAX_REPORTED) {
		fprintf(stderr, "void2d: %d colour glyphs refused, the rest are refused silently\n",
			MAX_REPORTED);
	}
	return 0;
}

static Table findTable(const ColourFace *face, size_t directory, int tables, const char *tag) {
	Table none = { 0, 0, 0 };
	for (int i = 0; i < tables; i++) {
		const unsigned char *record = face->bytes + directory + 16 * (size_t)i;
		if (memcmp(record, tag, 4) != 0) { continue; }
		uint32_t offset = ((uint32_t)record[8] << 24) | ((uint32_t)record[9] << 16) |
			((uint32_t)record[10] << 8) | record[11];
		uint32_t length = ((uint32_t)record[12] << 24) | ((uint32_t)record[13] << 16) |
			((uint32_t)record[14] << 8) | record[15];
		if (offset > face->length || length > face->length - offset) { continue; }
		Table t = { offset, length, 1 };
		return t;
	}
	return none;
}

static int openCblc(ColourFace *face) {
	Span s = tableSpan(face, face->cblc);
	unsigned major = rd16(&s, 0);
	uint32_t sizes = rd32(&s, 4);
	if (s.bad || (major != 2 && major != 3)) {
		return fail("CBLC version %u is not 2 or 3", major);
	}
	if (sizes == 0 || sizes > MAX_STRIKES) {
		return fail("CBLC holds %u strikes, expected 1 to %d", (unsigned)sizes, MAX_STRIKES);
	}
	if (face->cbdt.length < 4) { return fail("CBDT is shorter than its header"); }
	Span d = tableSpan(face, face->cbdt);
	unsigned dataMajor = rd16(&d, 0);
	if (dataMajor != 2 && dataMajor != 3) {
		return fail("CBDT version %u is not 2 or 3", dataMajor);
	}
	for (uint32_t i = 0; i < sizes; i++) {
		uint64_t at = 8 + 48 * (uint64_t)i;
		Strike st;
		st.kind = KIND_CBDT;
		st.arrayAt = rd32(&s, at);
		st.subtables = rd32(&s, at + 8);
		st.ppemX = (int)rd8(&s, at + 44);
		st.ppemY = (int)rd8(&s, at + 45);
		int depth = (int)rd8(&s, at + 46);
		if (s.bad) { return fail("CBLC is cut off inside strike record %u", (unsigned)i); }
		if (st.ppemY == 0 || st.ppemX == 0) {
			return fail("CBLC strike %u has ppem 0", (unsigned)i);
		}
		if (depth != 32) {
			fprintf(stderr, "void2d: CBLC strike %u (ppem %d) has bit depth %d, only 32 "
				"(colour) is read; the strike is skipped\n", (unsigned)i, st.ppemY, depth);
			continue;
		}
		if (st.arrayAt > s.n || st.subtables > (s.n - st.arrayAt) / 8) {
			return fail("CBLC strike %u index subtable array lies outside the table", (unsigned)i);
		}
		if (face->strikeCount == MAX_STRIKES) { return fail("more than %d strikes", MAX_STRIKES); }
		face->strikes[face->strikeCount++] = st;
	}
	if (face->strikeCount == 0) {
		return fail("CBLC holds no strike with a 32-bit colour depth");
	}
	return VOID2D_COLOUR_OK;
}

static int openSbix(ColourFace *face) {
	Span s = tableSpan(face, face->sbix);
	unsigned version = rd16(&s, 0);
	uint32_t count = rd32(&s, 4);
	if (s.bad || version != 1) { return fail("sbix version %u is not 1", version); }
	if (count == 0 || count > MAX_STRIKES) {
		return fail("sbix holds %u strikes, expected 1 to %d", (unsigned)count, MAX_STRIKES);
	}
	uint64_t offsets = 4 * ((uint64_t)face->numGlyphs + 1);
	for (uint32_t i = 0; i < count; i++) {
		Strike st;
		st.kind = KIND_SBIX;
		st.arrayAt = rd32(&s, 8 + 4 * (uint64_t)i);
		st.subtables = 0;
		st.ppemX = st.ppemY = (int)rd16(&s, st.arrayAt);
		if (s.bad) { return fail("sbix is cut off inside strike %u", (unsigned)i); }
		if (st.ppemY == 0) { return fail("sbix strike %u has ppem 0", (unsigned)i); }
		if (st.arrayAt + 4 + offsets > s.n) {
			return fail("sbix strike %u glyph offsets run past the table", (unsigned)i);
		}
		if (face->strikeCount == MAX_STRIKES) { return fail("more than %d strikes", MAX_STRIKES); }
		face->strikes[face->strikeCount++] = st;
	}
	return VOID2D_COLOUR_OK;
}

static int chooseIndex(ColourFace *face) {
	Span c = tableSpan(face, face->cmap);
	unsigned records = rd16(&c, 2);
	uint64_t chosen = 0;
	for (unsigned i = 0; i < records; i++) {
		uint64_t record = 4 + 8 * (uint64_t)i;
		unsigned platform = rd16(&c, record);
		unsigned encoding = rd16(&c, record + 2);
		uint64_t offset = rd32(&c, record + 4);
		if (c.bad) { return fail("cmap is cut off inside its encoding records"); }
		if (platform == 3 && (encoding == 1 || encoding == 10)) { chosen = offset; }
		if (platform == 0 && encoding != 5) { chosen = offset; }
	}
	if (chosen == 0) { return fail("cmap has no Unicode subtable"); }
	unsigned format = rd16(&c, chosen);
	if (c.bad) { return fail("the cmap subtable lies outside the table"); }
	if (format == 4) {
		uint64_t segments = rd16(&c, chosen + 6) / 2;
		if (c.bad || chosen + 16 + 8 * segments > c.n) {
			return fail("cmap format 4 segments run past the table");
		}
	} else if (format == 12) {
		uint64_t groups = rd32(&c, chosen + 12);
		if (c.bad || chosen + 16 + 12 * groups > c.n) {
			return fail("cmap format 12 groups run past the table");
		}
	} else {
		return fail("cmap format %u is not read for a colour font (4 and 12 are)", format);
	}
	face->index = chosen;
	face->indexFormat = format;
	return VOID2D_COLOUR_OK;
}

int void2dColourFaceGlyphIndex(const ColourFace *face, int codepoint) {
	if (!face || codepoint < 0 || face->index == 0) { return 0; }
	Span c = tableSpan(face, face->cmap);
	uint64_t at = face->index;
	int glyph = 0;
	if (face->indexFormat == 4) {
		if (codepoint > 0xFFFF) { return 0; }
		unsigned count = rd16(&c, at + 6) / 2;
		uint64_t ends = at + 14, starts = ends + 2 * (uint64_t)count + 2;
		uint64_t deltas = starts + 2 * (uint64_t)count, ranges = deltas + 2 * (uint64_t)count;
		unsigned lo = 0, hi = count;
		while (lo < hi) {
			unsigned mid = (lo + hi) / 2;
			if (rd16(&c, ends + 2 * (uint64_t)mid) < (unsigned)codepoint) { lo = mid + 1; }
			else { hi = mid; }
		}
		if (lo == count) { return 0; }
		unsigned start = rd16(&c, starts + 2 * (uint64_t)lo);
		if ((unsigned)codepoint < start) { return 0; }
		unsigned delta = rd16(&c, deltas + 2 * (uint64_t)lo);
		unsigned range = rd16(&c, ranges + 2 * (uint64_t)lo);
		if (range == 0) {
			glyph = (int)(((unsigned)codepoint + delta) & 0xFFFF);
		} else {
			uint64_t slot = ranges + 2 * (uint64_t)lo + range + 2 * ((unsigned)codepoint - start);
			unsigned raw = rd16(&c, slot);
			glyph = raw ? (int)((raw + delta) & 0xFFFF) : 0;
		}
	} else {
		uint32_t groups = rd32(&c, at + 12);
		uint32_t lo = 0, hi = groups;
		while (lo < hi) {
			uint32_t mid = lo + (hi - lo) / 2;
			uint64_t group = at + 16 + 12 * (uint64_t)mid;
			if (rd32(&c, group + 4) < (uint32_t)codepoint) { lo = mid + 1; }
			else { hi = mid; }
		}
		if (lo == groups) { return 0; }
		uint64_t group = at + 16 + 12 * (uint64_t)lo;
		uint32_t start = rd32(&c, group);
		if ((uint32_t)codepoint < start) { return 0; }
		glyph = (int)(rd32(&c, group + 8) + ((uint32_t)codepoint - start));
	}
	if (c.bad || glyph < 0 || glyph >= face->numGlyphs) { return 0; }
	return glyph;
}

static int openColr(ColourFace *face) {
	if (!face->cpal.found) { return fail("COLR is present without CPAL"); }
	Span c = tableSpan(face, face->colr);
	unsigned version = rd16(&c, 0);
	unsigned bases = rd16(&c, 2);
	uint64_t basesAt = rd32(&c, 4);
	uint64_t layersAt = rd32(&c, 8);
	unsigned layers = rd16(&c, 12);
	if (c.bad) { return fail("COLR is shorter than its header"); }
	if (version > 1) { return fail("COLR version %u is not 0 or 1", version); }
	if (bases == 0) {
		return version == 1
			? fail("COLR v1 holds a paint graph and no v0 layers, which is all that is read")
			: fail("COLR holds no base glyph records");
	}
	if (basesAt + 6 * (uint64_t)bases > c.n || layersAt + 4 * (uint64_t)layers > c.n) {
		return fail("COLR records run past the table");
	}
	Span p = tableSpan(face, face->cpal);
	unsigned cpalVersion = rd16(&p, 0);
	unsigned entries = rd16(&p, 2);
	unsigned palettes = rd16(&p, 4);
	unsigned records = rd16(&p, 6);
	uint64_t recordsAt = rd32(&p, 8);
	unsigned first = rd16(&p, 12);
	if (p.bad) { return fail("CPAL is shorter than its header"); }
	if (cpalVersion > 1) { return fail("CPAL version %u is not 0 or 1", cpalVersion); }
	if (palettes == 0 || entries == 0) { return fail("CPAL holds no palette"); }
	if ((uint64_t)first + entries > records || recordsAt + 4 * (uint64_t)records > p.n) {
		return fail("CPAL palette 0 runs past its colour records");
	}
	face->colrBases = basesAt;
	face->colrBaseCount = bases;
	face->colrLayers = layersAt;
	face->colrLayerCount = layers;
	face->paletteAt = recordsAt + 4 * (uint64_t)first;
	face->paletteEntries = entries;
	return VOID2D_COLOUR_OK;
}

int void2dColourFaceHasLayers(const ColourFace *face) { return face && face->colr.found; }

static int layersOf(ColourFace *face, int glyph, ColourLayer *out, int capacity) {
	s_reason[0] = 0;
	if (!face || !face->colr.found || glyph < 0 || glyph >= 0x10000) { return 0; }
	Span c = tableSpan(face, face->colr);
	unsigned lo = 0, hi = face->colrBaseCount;
	while (lo < hi) {
		unsigned mid = (lo + hi) / 2;
		if (rd16(&c, face->colrBases + 6 * (uint64_t)mid) < (unsigned)glyph) { lo = mid + 1; }
		else { hi = mid; }
	}
	if (lo == face->colrBaseCount) { return 0; }
	uint64_t record = face->colrBases + 6 * (uint64_t)lo;
	if (rd16(&c, record) != (unsigned)glyph) { return 0; }
	unsigned first = rd16(&c, record + 2);
	unsigned count = rd16(&c, record + 4);
	if (c.bad) { return fail("COLR is cut off inside its base glyph records"); }
	if (count == 0) { return 0; }
	if (count > MAX_LAYERS || count > (unsigned)capacity) {
		return fail("COLR glyph %d has %u layers, at most %d are read", glyph, count, MAX_LAYERS);
	}
	if ((uint64_t)first + count > face->colrLayerCount) {
		return fail("COLR glyph %d layers run past the layer records", glyph);
	}
	Span p = tableSpan(face, face->cpal);
	for (unsigned i = 0; i < count; i++) {
		uint64_t layer = face->colrLayers + 4 * ((uint64_t)first + i);
		unsigned layerGlyph = rd16(&c, layer);
		unsigned index = rd16(&c, layer + 2);
		if (c.bad) { return fail("COLR is cut off inside its layer records"); }
		if (layerGlyph >= (unsigned)face->numGlyphs) {
			return fail("COLR glyph %d layer %u names glyph %u of %d", glyph, i, layerGlyph,
				face->numGlyphs);
		}
		if (index == 0xFFFF) {
			return fail("COLR glyph %d layer %u uses the foreground colour (palette index "
				"0xFFFF), which a colour tile cannot hold", glyph, i);
		}
		if (index >= face->paletteEntries) {
			return fail("COLR glyph %d layer %u uses palette index %u of %u", glyph, i, index,
				face->paletteEntries);
		}
		uint64_t at = face->paletteAt + 4 * (uint64_t)index;
		out[i].glyph = (int)layerGlyph;
		out[i].b = (unsigned char)rd8(&p, at);
		out[i].g = (unsigned char)rd8(&p, at + 1);
		out[i].r = (unsigned char)rd8(&p, at + 2);
		out[i].a = (unsigned char)rd8(&p, at + 3);
		if (p.bad) { return fail("CPAL is cut off inside palette 0"); }
	}
	return (int)count;
}

int void2dColourGlyphLayers(ColourFace *face, int glyph, ColourLayer *out, int capacity) {
	int count = layersOf(face, glyph, out, capacity);
	if (count < 0 && !reportedBefore(face, glyph)) {
		fprintf(stderr, "void2d: colour glyph %d refused: %s\n", glyph, s_reason);
	}
	return count;
}

void void2dColourCompose(unsigned int *dst, int stride, int dw, int dh,
                         const unsigned char *coverage, int coverageStride, int ox, int oy,
                         int cw, int ch, const ColourLayer *colour) {
	for (int y = 0; y < ch; y++) {
		for (int x = 0; x < cw; x++) {
			int tx = ox + x, ty = oy + y;
			if (tx < 0 || ty < 0 || tx >= dw || ty >= dh) { continue; }
			unsigned cov = coverage[(size_t)y * (size_t)coverageStride + (size_t)x];
			if (!cov) { continue; }
			unsigned sa = (cov * colour->a + 127u) / 255u;
			unsigned source[4] = {
				(colour->r * sa + 127u) / 255u, (colour->g * sa + 127u) / 255u,
				(colour->b * sa + 127u) / 255u, sa,
			};
			unsigned int *at = dst + (size_t)ty * (size_t)stride + (size_t)tx;
			unsigned int out = 0;
			for (int c = 0; c < 4; c++) {
				unsigned d = (*at >> (8 * c)) & 255u;
				out |= (source[c] + (d * (255u - sa) + 127u) / 255u) << (8 * c);
			}
			*at = out;
		}
	}
}

int void2dColourFaceOpen(const unsigned char *bytes, size_t length, size_t fontStart,
                         ColourFace **out) {
	*out = NULL;
	s_reason[0] = 0;
	if (fontStart > length || length - fontStart < 12) {
		return fail("the file is shorter than an sfnt header");
	}
	int tables = (int)(((unsigned)bytes[fontStart + 4] << 8) | bytes[fontStart + 5]);
	if (tables == 0 || tables > MAX_TABLES) {
		return fail("the table directory counts %d tables", tables);
	}
	if (length - fontStart - 12 < 16 * (size_t)tables) {
		return fail("the table directory runs past the end of the file");
	}
	ColourFace *face = (ColourFace *)calloc(1, sizeof(ColourFace));
	if (!face) { return VOID2D_COLOUR_NO_MEMORY; }
	face->bytes = bytes;
	face->length = length;
	size_t dir = fontStart + 12;
	face->cmap = findTable(face, dir, tables, "cmap");
	face->head = findTable(face, dir, tables, "head");
	face->hhea = findTable(face, dir, tables, "hhea");
	face->hmtx = findTable(face, dir, tables, "hmtx");
	face->maxp = findTable(face, dir, tables, "maxp");
	face->glyf = findTable(face, dir, tables, "glyf");
	face->loca = findTable(face, dir, tables, "loca");
	face->cff = findTable(face, dir, tables, "CFF ");
	face->cblc = findTable(face, dir, tables, "CBLC");
	face->cbdt = findTable(face, dir, tables, "CBDT");
	face->sbix = findTable(face, dir, tables, "sbix");
	face->colr = findTable(face, dir, tables, "COLR");
	face->cpal = findTable(face, dir, tables, "CPAL");
	int status = VOID2D_COLOUR_NONE;
	if (face->cblc.found != face->cbdt.found) {
		status = fail("%s is present without %s", face->cblc.found ? "CBLC" : "CBDT",
			face->cblc.found ? "CBDT" : "CBLC");
	} else if (face->cblc.found || face->sbix.found || face->colr.found) {
		status = VOID2D_COLOUR_OK;
	}
	if (status == VOID2D_COLOUR_OK) {
		Span m = tableSpan(face, face->maxp);
		face->numGlyphs = (int)rd16(&m, 4);
		if (!face->maxp.found || m.bad) {
			status = fail("a colour font needs a maxp with a glyph count");
		} else if (!face->cmap.found) {
			status = fail("a colour font without cmap");
		}
	}
	if (status == VOID2D_COLOUR_OK && face->cblc.found) { status = openCblc(face); }
	if (status == VOID2D_COLOUR_OK && face->sbix.found) { status = openSbix(face); }
	if (status == VOID2D_COLOUR_OK && face->colr.found) { status = openColr(face); }
	if (status != VOID2D_COLOUR_OK) {
		free(face);
		return status;
	}
	status = chooseIndex(face);
	if (status != VOID2D_COLOUR_OK) {
		free(face);
		return status;
	}
	*out = face;
	return VOID2D_COLOUR_OK;
}

int void2dColourFaceSfnt(const ColourFace *face, ColourSfnt *out) {
	memset(out, 0, sizeof(*out));
	if (!face->head.found || !face->hhea.found || !face->hmtx.found) {
		return fail("a colour font needs head, hhea and hmtx");
	}
	if (face->head.length < 54) { return fail("head is shorter than 54 bytes"); }
	if (face->hhea.length < 36) { return fail("hhea is shorter than 36 bytes"); }
	Span h = tableSpan(face, face->hhea);
	unsigned longMetrics = rd16(&h, 34);
	size_t need = 4 * (size_t)longMetrics;
	if ((int)longMetrics < face->numGlyphs) {
		need += 2 * ((size_t)face->numGlyphs - longMetrics);
	}
	if (longMetrics == 0 || face->hmtx.length < need) {
		return fail("hmtx holds fewer metrics than hhea and maxp promise");
	}
	Span head = tableSpan(face, face->head);
	if (rd32(&head, 12) != 0x5F0F3CF5u) { return fail("head has a bad magic number"); }
	if (rd16(&head, 18) == 0) { return fail("head has unitsPerEm 0"); }
	out->head = face->head.offset;
	out->hhea = face->hhea.offset;
	out->hmtx = face->hmtx.offset;
	out->hmtxLength = face->hmtx.length;
	out->numGlyphs = face->numGlyphs;
	out->outlines = face->glyf.found || face->cff.found;
	return VOID2D_COLOUR_OK;
}

static int pngInfo(Span *s, uint64_t at, uint64_t length, int *width, int *height) {
	if (length < 24 || at > s->n || s->n - at < length) { return 0; }
	static const unsigned char signature[8] = { 0x89, 'P', 'N', 'G', '\r', '\n', 0x1a, '\n' };
	if (memcmp(s->p + at, signature, 8) != 0 || memcmp(s->p + at + 12, "IHDR", 4) != 0) {
		return 0;
	}
	*width = (int)rd32(s, at + 16);
	*height = (int)rd32(s, at + 20);
	return 1;
}

static int findCbdt(ColourFace *face, const Strike *strike, int glyph, Bitmap *out) {
	Span index = tableSpan(face, face->cblc);
	Span data = tableSpan(face, face->cbdt);
	for (unsigned i = 0; i < strike->subtables; i++) {
		uint64_t entry = strike->arrayAt + 8 * (uint64_t)i;
		unsigned first = rd16(&index, entry);
		unsigned last = rd16(&index, entry + 2);
		uint32_t additional = rd32(&index, entry + 4);
		if (index.bad) { return fail("CBLC is cut off inside an index subtable array"); }
		if ((unsigned)glyph < first || (unsigned)glyph > last) { continue; }
		uint64_t sub = strike->arrayAt + additional;
		unsigned indexFormat = rd16(&index, sub);
		unsigned imageFormat = rd16(&index, sub + 2);
		uint32_t imageBase = rd32(&index, sub + 4);
		if (index.bad) { return fail("CBLC is cut off inside an index subtable header"); }
		uint64_t slot = (uint64_t)glyph - first;
		uint64_t start = 0, size = 0;
		int hasMetrics = 0;
		int bigWidth = 0, bigHeight = 0, bigBx = 0, bigBy = 0;
		if (indexFormat == 1 || indexFormat == 3) {
			uint64_t width = indexFormat == 1 ? 4 : 2;
			uint64_t cells = (uint64_t)last - first + 2;
			if (sub + 8 > index.n || cells > (index.n - sub - 8) / width) {
				return fail("CBLC index format %u offsets run past the table", indexFormat);
			}
			uint64_t at = sub + 8 + width * slot;
			uint64_t a = indexFormat == 1 ? rd32(&index, at) : rd16(&index, at);
			uint64_t b = indexFormat == 1 ? rd32(&index, at + width) : rd16(&index, at + width);
			if (b < a) { return fail("CBLC glyph %d has a negative image length", glyph); }
			start = (uint64_t)imageBase + a;
			size = b - a;
		} else if (indexFormat == 2) {
			uint64_t each = rd32(&index, sub + 8);
			bigHeight = (int)rd8(&index, sub + 12);
			bigWidth = (int)rd8(&index, sub + 13);
			bigBx = rdI8(&index, sub + 14);
			bigBy = rdI8(&index, sub + 15);
			hasMetrics = 1;
			if (index.bad) { return fail("CBLC index format 2 is cut off"); }
			start = (uint64_t)imageBase + each * slot;
			size = each;
		} else {
			if (!refusedBefore(face, indexFormat & 31)) {
				fprintf(stderr, "void2d: CBLC index format %u is not read (1, 2 and 3 are)\n",
					indexFormat);
			}
			return VOID2D_COLOUR_REFUSED;
		}
		if (size == 0) { return VOID2D_COLOUR_ABSENT; }
		if (imageFormat != 17 && imageFormat != 18 && imageFormat != 19) {
			if (!refusedBefore(face, 32 + (imageFormat & 31))) {
				fprintf(stderr,
					"void2d: CBDT image format %u is not a PNG format (17, 18 and 19 are)\n",
					imageFormat);
			}
			return VOID2D_COLOUR_REFUSED;
		}
		if (start > data.n || size > data.n - start) {
			return fail("CBDT glyph %d image lies outside the table", glyph);
		}
		uint64_t header = imageFormat == 17 ? 5 : imageFormat == 18 ? 8 : 0;
		int width = bigWidth, height = bigHeight, bx = bigBx, by = bigBy;
		if (imageFormat == 17 || imageFormat == 18) {
			height = (int)rd8(&data, start);
			width = (int)rd8(&data, start + 1);
			bx = rdI8(&data, start + 2);
			by = rdI8(&data, start + 3);
		} else if (!hasMetrics) {
			return fail("CBDT image format 19 needs the shared metrics of index format 2");
		}
		uint32_t pngLength = rd32(&data, start + header);
		if (data.bad || size < header + 4 || pngLength > size - header - 4) {
			return fail("CBDT glyph %d image is cut off", glyph);
		}
		int pngW = 0, pngH = 0;
		uint64_t pngAt = start + header + 4;
		if (!pngInfo(&data, pngAt, pngLength, &pngW, &pngH)) {
			return fail("CBDT glyph %d is not a PNG", glyph);
		}
		if (pngW != width || pngH != height || width <= 0 || height <= 0) {
			return fail("CBDT glyph %d metrics say %dx%d but its PNG is %dx%d", glyph, width,
				height, pngW, pngH);
		}
		out->png = data.p + pngAt;
		out->pngLength = pngLength;
		out->width = width;
		out->height = height;
		out->bearingX = bx;
		out->bearingY = by;
		out->ppem = strike->ppemY;
		return VOID2D_COLOUR_PRESENT;
	}
	return VOID2D_COLOUR_ABSENT;
}

static int findSbix(ColourFace *face, const Strike *strike, int glyph, int depth, Bitmap *out) {
	Span s = tableSpan(face, face->sbix);
	if (glyph < 0 || glyph >= face->numGlyphs) { return VOID2D_COLOUR_ABSENT; }
	uint64_t base = strike->arrayAt;
	uint64_t from = rd32(&s, base + 4 + 4 * (uint64_t)glyph);
	uint64_t to = rd32(&s, base + 4 + 4 * ((uint64_t)glyph + 1));
	if (s.bad) { return fail("sbix is cut off inside the glyph offsets"); }
	if (to < from) { return fail("sbix glyph %d has a negative data length", glyph); }
	if (to == from || to - from == 8) { return VOID2D_COLOUR_ABSENT; }
	if (to - from < 8 || base + to > s.n) {
		return fail("sbix glyph %d data lies outside the table", glyph);
	}
	uint64_t at = base + from;
	int originX = (int16_t)rd16(&s, at);
	int originY = (int16_t)rd16(&s, at + 2);
	uint32_t tag = rd32(&s, at + 4);
	if (tag == 0x64757065u) {
		if (to - from < 10) { return fail("sbix glyph %d is a dupe without a target", glyph); }
		if (depth >= MAX_SBIX_DUPE) {
			return fail("sbix glyph %d starts a dupe chain deeper than %d", glyph, MAX_SBIX_DUPE);
		}
		return findSbix(face, strike, (int)rd16(&s, at + 8), depth + 1, out);
	}
	if (tag != 0x706E6720u) {
		if (!tagRefusedBefore(face, tag)) {
			char name[5];
			for (int i = 0; i < 4; i++) {
				unsigned c = (tag >> (24 - 8 * i)) & 255u;
				name[i] = (c >= 32 && c < 127) ? (char)c : '?';
			}
			name[4] = 0;
			fprintf(stderr, "void2d: sbix graphic type '%s' is not read ('png ' and 'dupe' are)\n",
				name);
		}
		return VOID2D_COLOUR_REFUSED;
	}
	int width = 0, height = 0;
	if (!pngInfo(&s, at + 8, to - from - 8, &width, &height)) {
		return fail("sbix glyph %d is not a PNG", glyph);
	}
	if (width <= 0 || height <= 0 || width > MAX_SIDE || height > MAX_SIDE) {
		return fail("sbix glyph %d is %dx%d, expected 1 to %d a side", glyph, width, height,
			MAX_SIDE);
	}
	out->png = s.p + at + 8;
	out->pngLength = to - from - 8;
	out->width = width;
	out->height = height;
	out->bearingX = originX;
	out->bearingY = originY + height;
	out->ppem = strike->ppemY;
	return VOID2D_COLOUR_PRESENT;
}

static int findBitmap(ColourFace *face, const Strike *strike, int glyph, Bitmap *out) {
	s_reason[0] = 0;
	if (strike->kind == KIND_SBIX) { return findSbix(face, strike, glyph, 0, out); }
	return findCbdt(face, strike, glyph, out);
}

static const Strike *chooseStrike(ColourFace *face, int glyph, float sizePx, Bitmap *bitmap,
                                  int *status) {
	const Strike *best = NULL;
	Bitmap bestBitmap;
	int refusal = VOID2D_COLOUR_ABSENT;
	for (int i = 0; i < face->strikeCount; i++) {
		const Strike *st = &face->strikes[i];
		Bitmap found;
		int code = findBitmap(face, st, glyph, &found);
		if (code == VOID2D_COLOUR_PRESENT) {
			int bigger = (float)st->ppemY >= sizePx;
			int bestBigger = best && (float)best->ppemY >= sizePx;
			int better = !best
				|| (bigger && (!bestBigger || st->ppemY < best->ppemY))
				|| (!bigger && !bestBigger && st->ppemY > best->ppemY);
			if (better) {
				best = st;
				bestBitmap = found;
			}
		} else if (code != VOID2D_COLOUR_ABSENT) {
			refusal = code;
		}
	}
	*status = best ? VOID2D_COLOUR_PRESENT : refusal;
	if (best) { *bitmap = bestBitmap; }
	return best;
}

static int scaled(int value, float sizePx, int ppem) {
	return (int)floor((double)value * (double)sizePx / (double)ppem + 0.5);
}

static void boxOf(const Bitmap *b, float sizePx, ColourBox *box) {
	int w = scaled(b->width, sizePx, b->ppem);
	int h = scaled(b->height, sizePx, b->ppem);
	box->width = w < 1 ? 1 : w;
	box->height = h < 1 ? 1 : h;
	box->bearingX = scaled(b->bearingX, sizePx, b->ppem);
	box->bearingY = scaled(b->bearingY, sizePx, b->ppem);
	box->ppem = b->ppem;
}

int void2dColourGlyphBox(ColourFace *face, int glyph, float sizePx, ColourBox *box) {
	memset(box, 0, sizeof(*box));
	if (!face || glyph <= 0 || glyph >= 0x10000 || !(sizePx > 0.0f)) {
		return VOID2D_COLOUR_ABSENT;
	}
	s_reason[0] = 0;
	int status = VOID2D_COLOUR_ABSENT;
	Bitmap bitmap;
	if (!(sizePx <= VOID2D_COLOUR_MAX_SIZE_PX)) {
		fail("a size of %g px is over the %g px limit", (double)sizePx,
			(double)VOID2D_COLOUR_MAX_SIZE_PX);
		status = VOID2D_COLOUR_REFUSED;
	} else {
		chooseStrike(face, glyph, sizePx, &bitmap, &status);
	}
	if (status == VOID2D_COLOUR_PRESENT) {
		boxOf(&bitmap, sizePx, box);
		if ((int64_t)box->width * box->height > VOID2D_COLOUR_MAX_TEXELS) {
			fail("colour glyph %d is %dx%d at %.1f px, over the %d texel limit", glyph,
				box->width, box->height, sizePx, VOID2D_COLOUR_MAX_TEXELS);
			memset(box, 0, sizeof(*box));
			status = VOID2D_COLOUR_REFUSED;
		}
	}
	if (status != VOID2D_COLOUR_PRESENT && status != VOID2D_COLOUR_ABSENT) {
		if (s_reason[0] && !reportedBefore(face, glyph)) {
			fprintf(stderr, "void2d: colour glyph %d refused: %s\n", glyph, s_reason);
		}
		return VOID2D_COLOUR_REFUSED;
	}
	return status;
}

static const char *pngReason(void) {
	static char text[64];
	const char *reason = stbi_failure_reason();
	if (!reason) { return "the decoded size changed"; }
	size_t i = 0;
	for (; reason[i] && i + 1 < sizeof(text); i++) {
		text[i] = (reason[i] >= 32 && reason[i] < 127) ? reason[i] : '?';
	}
	text[i] = 0;
	return text;
}

static unsigned premultiplied(unsigned c, unsigned a) { return (c * a + 127u) / 255u; }

static void areaAverage(const unsigned int *src, int sw, int sh, unsigned int *dst, int stride,
                        int dw, int dh) {
	uint64_t total = (uint64_t)sw * (uint64_t)sh;
	for (int oy = 0; oy < dh; oy++) {
		int64_t y0 = (int64_t)oy * sh, y1 = y0 + sh;
		int iy0 = (int)(y0 / dh), iy1 = (int)((y1 - 1) / dh);
		for (int ox = 0; ox < dw; ox++) {
			int64_t x0 = (int64_t)ox * sw, x1 = x0 + sw;
			int ix0 = (int)(x0 / dw), ix1 = (int)((x1 - 1) / dw);
			uint64_t sum[4] = { 0, 0, 0, 0 };
			for (int iy = iy0; iy <= iy1; iy++) {
				int64_t ya = (int64_t)iy * dh > y0 ? (int64_t)iy * dh : y0;
				int64_t yb = (int64_t)(iy + 1) * dh < y1 ? (int64_t)(iy + 1) * dh : y1;
				for (int ix = ix0; ix <= ix1; ix++) {
					int64_t xa = (int64_t)ix * dw > x0 ? (int64_t)ix * dw : x0;
					int64_t xb = (int64_t)(ix + 1) * dw < x1 ? (int64_t)(ix + 1) * dw : x1;
					uint64_t weight = (uint64_t)(xb - xa) * (uint64_t)(yb - ya);
					unsigned int texel = src[(size_t)iy * (size_t)sw + (size_t)ix];
					for (int c = 0; c < 4; c++) { sum[c] += weight * ((texel >> (8 * c)) & 255u); }
				}
			}
			unsigned int out = 0;
			for (int c = 0; c < 4; c++) {
				out |= (unsigned int)((sum[c] + total / 2) / total) << (8 * c);
			}
			dst[(size_t)oy * (size_t)stride + (size_t)ox] = out;
		}
	}
}

int void2dColourGlyphRender(ColourFace *face, int glyph, float sizePx, unsigned int *dst,
                            int strideTexels, int width, int height) {
	ColourBox box;
	int status = void2dColourGlyphBox(face, glyph, sizePx, &box);
	if (status != VOID2D_COLOUR_PRESENT) { return status; }
	if (box.width != width || box.height != height || strideTexels < width) {
		fprintf(stderr, "void2d: colour tile %dx%d does not match the glyph's %dx%d box\n", width,
			height, box.width, box.height);
		return VOID2D_COLOUR_REFUSED;
	}
	Bitmap bitmap;
	chooseStrike(face, glyph, sizePx, &bitmap, &status);
	if (status != VOID2D_COLOUR_PRESENT) { return VOID2D_COLOUR_REFUSED; }
	int w = 0, h = 0, channels = 0;
	unsigned char *pixels = stbi_load_from_memory(bitmap.png, (int)bitmap.pngLength, &w, &h,
		&channels, 4);
	if (!pixels || w != bitmap.width || h != bitmap.height) {
		fprintf(stderr, "void2d: colour glyph %d: the PNG does not decode: %s\n", glyph,
			pngReason());
		if (pixels) { stbi_image_free(pixels); }
		return VOID2D_COLOUR_REFUSED;
	}
	unsigned int *source = (unsigned int *)malloc(sizeof(unsigned int) * (size_t)w * (size_t)h);
	if (!source) {
		stbi_image_free(pixels);
		return VOID2D_COLOUR_NO_MEMORY;
	}
	for (size_t i = 0; i < (size_t)w * (size_t)h; i++) {
		unsigned a = pixels[4 * i + 3];
		source[i] = premultiplied(pixels[4 * i], a) |
			(premultiplied(pixels[4 * i + 1], a) << 8) |
			(premultiplied(pixels[4 * i + 2], a) << 16) | (a << 24);
	}
	stbi_image_free(pixels);
	areaAverage(source, w, h, dst, strideTexels, width, height);
	free(source);
	return VOID2D_COLOUR_PRESENT;
}

int void2dColourFaceSweep(const unsigned char *bytes, size_t length, size_t fontStart,
                          int glyphCount, int step, int *refused) {
	int runs = 0;
	*refused = 0;
	if (step < 1) { step = 1; }
	unsigned int tile[64 * 64];
	for (size_t cut = 0; cut <= length; cut += (size_t)step) {
		for (int variant = 0; variant < 2; variant++) {
			unsigned char *copy = (unsigned char *)malloc(length ? length : 1);
			if (!copy) { return -1; }
			memcpy(copy, bytes, length);
			size_t usable = length;
			if (variant == 0) {
				usable = cut;
				unsigned char *exact = (unsigned char *)malloc(usable ? usable : 1);
				if (!exact) { free(copy); return -1; }
				memcpy(exact, copy, usable);
				free(copy);
				copy = exact;
			} else if (cut + 4 <= length) {
				memset(copy + cut, 0xFF, 4);
			}
			ColourFace *face = NULL;
			int status = void2dColourFaceOpen(copy, usable, fontStart, &face);
			if (status == VOID2D_COLOUR_OK) {
				for (int g = 0; g < glyphCount; g++) {
					ColourLayer layers[MAX_LAYERS];
					if (void2dColourGlyphLayers(face, g, layers, MAX_LAYERS) < 0) { (*refused)++; }
					ColourBox box;
					if (void2dColourGlyphBox(face, g, 16.0f, &box) == VOID2D_COLOUR_PRESENT &&
						box.width <= 64 && box.height <= 64) {
						if (void2dColourGlyphRender(face, g, 16.0f, tile, 64, box.width,
							box.height) == VOID2D_COLOUR_REFUSED) { (*refused)++; }
					}
				}
				free(face);
			} else if (status == VOID2D_COLOUR_BAD_TABLE) {
				(*refused)++;
			}
			free(copy);
			runs++;
		}
	}
	return runs;
}
