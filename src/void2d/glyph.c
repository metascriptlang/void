#include "glyph.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

// fontstash compiles its own stb_truetype v1.16 into batcher.c: keep this v1.26 file-local,
// or the two implementations collide at link.
#define STBTT_STATIC
#define STB_TRUETYPE_IMPLEMENTATION
#include "../../deps/stb/stb_truetype.h"

#define GLYPH_MAX_KERN_LOOKUPS 32

typedef struct {
	unsigned char *bytes;
	stbtt_fontinfo info;
	int kernLookups[GLYPH_MAX_KERN_LOOKUPS];
	int kernLookupCount;
} GlyphFace;

typedef struct {
	unsigned char *texels;
	int size;
	int dirty;
} GlyphPage;

static GlyphFace *s_faces;
static int s_faceCount;
static int s_faceCapacity;
static GlyphPage *s_pages;
static int s_pageCount;
static int s_pageCapacity;
static float s_metrics[3];
static int s_box[4];

static int validFace(int face) { return face >= 0 && face < s_faceCount; }
static int validPage(int page) { return page >= 0 && page < s_pageCount; }

static unsigned char *readWholeFile(const char *path, long *outSize) {
	FILE *f = fopen(path, "rb");
	if (!f) { return NULL; }
	fseek(f, 0, SEEK_END);
	long n = ftell(f);
	fseek(f, 0, SEEK_SET);
	unsigned char *buf = n > 0 ? (unsigned char *)malloc((size_t)n) : NULL;
	if (!buf || fread(buf, 1, (size_t)n, f) != (size_t)n) {
		fclose(f);
		free(buf);
		return NULL;
	}
	fclose(f);
	*outSize = n;
	return buf;
}

static int bitCount(int v) {
	int n = 0;
	for (; v; v >>= 1) { n += v & 1; }
	return n;
}

static stbtt_uint8 *pickScript(stbtt_uint8 *scriptList) {
	int count = ttUSHORT(scriptList);
	stbtt_uint8 *latn = NULL;
	for (int i = 0; i < count; i++) {
		stbtt_uint8 *record = scriptList + 2 + 6 * i;
		if (memcmp(record, "DFLT", 4) == 0) { return scriptList + ttUSHORT(record + 4); }
		if (memcmp(record, "latn", 4) == 0) { latn = scriptList + ttUSHORT(record + 4); }
	}
	if (latn) { return latn; }
	return count > 0 ? scriptList + ttUSHORT(scriptList + 6) : NULL;
}

static void addKernLookup(GlyphFace *face, int lookup) {
	for (int i = 0; i < face->kernLookupCount; i++) {
		if (face->kernLookups[i] == lookup) { return; }
	}
	if (face->kernLookupCount == GLYPH_MAX_KERN_LOOKUPS) {
		fprintf(stderr, "void2d: more than %d GPOS kern lookups; the rest are ignored\n",
			GLYPH_MAX_KERN_LOOKUPS);
		return;
	}
	int at = face->kernLookupCount++;
	while (at > 0 && face->kernLookups[at - 1] > lookup) {
		face->kernLookups[at] = face->kernLookups[at - 1];
		at--;
	}
	face->kernLookups[at] = lookup;
}

static void addKernFeature(GlyphFace *face, stbtt_uint8 *featureList, int featureIndex) {
	if (featureIndex < 0 || featureIndex >= ttUSHORT(featureList)) { return; }
	stbtt_uint8 *record = featureList + 2 + 6 * featureIndex;
	if (memcmp(record, "kern", 4) != 0) { return; }
	stbtt_uint8 *feature = featureList + ttUSHORT(record + 4);
	int lookups = ttUSHORT(feature + 2);
	for (int i = 0; i < lookups; i++) { addKernLookup(face, ttUSHORT(feature + 4 + 2 * i)); }
}

static void findKernLookups(GlyphFace *face) {
	face->kernLookupCount = 0;
	if (!face->info.gpos) { return; }
	stbtt_uint8 *gpos = face->bytes + face->info.gpos;
	if (ttUSHORT(gpos) != 1) { return; }
	stbtt_uint8 *script = pickScript(gpos + ttUSHORT(gpos + 4));
	if (!script || ttUSHORT(script) == 0) { return; }
	stbtt_uint8 *langSys = script + ttUSHORT(script);
	stbtt_uint8 *featureList = gpos + ttUSHORT(gpos + 6);
	int required = ttUSHORT(langSys + 2);
	if (required != 0xFFFF) { addKernFeature(face, featureList, required); }
	int features = ttUSHORT(langSys + 4);
	for (int i = 0; i < features; i++) {
		addKernFeature(face, featureList, ttUSHORT(langSys + 6 + 2 * i));
	}
}

static int pairAdvance(stbtt_uint8 *table, int left, int right, int *applied) {
	*applied = 0;
	if (stbtt__GetCoverageIndex(table + ttUSHORT(table + 2), left) < 0) { return 0; }
	int format = ttUSHORT(table);
	int valueFormat1 = ttUSHORT(table + 4);
	int valueFormat2 = ttUSHORT(table + 6);
	int size1 = bitCount(valueFormat1 & 0xFF) * 2;
	int size2 = bitCount(valueFormat2 & 0xFF) * 2;
	int xAdvanceAt = bitCount(valueFormat1 & 0x3) * 2;
	int hasXAdvance = (valueFormat1 & 0x4) != 0;
	if (format == 1) {
		int coverage = stbtt__GetCoverageIndex(table + ttUSHORT(table + 2), left);
		if (coverage >= ttUSHORT(table + 8)) { return 0; }
		stbtt_uint8 *pairSet = table + ttUSHORT(table + 10 + 2 * coverage);
		int count = ttUSHORT(pairSet);
		int stride = 2 + size1 + size2;
		int lo = 0, hi = count - 1;
		while (lo <= hi) {
			int mid = (lo + hi) >> 1;
			stbtt_uint8 *record = pairSet + 2 + stride * mid;
			int second = ttUSHORT(record);
			if (right < second) { hi = mid - 1; }
			else if (right > second) { lo = mid + 1; }
			else {
				*applied = 1;
				return hasXAdvance ? ttSHORT(record + 2 + xAdvanceAt) : 0;
			}
		}
		return 0;
	}
	if (format == 2) {
		int class1 = stbtt__GetGlyphClass(table + ttUSHORT(table + 8), left);
		int class2 = stbtt__GetGlyphClass(table + ttUSHORT(table + 10), right);
		int class1Count = ttUSHORT(table + 12);
		int class2Count = ttUSHORT(table + 14);
		if (class1 < 0 || class2 < 0 || class1 >= class1Count || class2 >= class2Count) { return 0; }
		*applied = 1;
		stbtt_uint8 *record = table + 16 + (class1 * class2Count + class2) * (size1 + size2);
		return hasXAdvance ? ttSHORT(record + xAdvanceAt) : 0;
	}
	return 0;
}

static int gposKern(GlyphFace *face, int left, int right) {
	stbtt_uint8 *gpos = face->bytes + face->info.gpos;
	stbtt_uint8 *lookupList = gpos + ttUSHORT(gpos + 8);
	int total = 0;
	for (int i = 0; i < face->kernLookupCount; i++) {
		stbtt_uint8 *lookup = lookupList + ttUSHORT(lookupList + 2 + 2 * face->kernLookups[i]);
		int type = ttUSHORT(lookup);
		int subtables = ttUSHORT(lookup + 4);
		for (int s = 0; s < subtables; s++) {
			stbtt_uint8 *table = lookup + ttUSHORT(lookup + 6 + 2 * s);
			if (type == 9) {
				if (ttUSHORT(table + 2) != 2) { continue; }
				table = table + ttULONG(table + 4);
			} else if (type != 2) {
				continue;
			}
			int applied = 0;
			total += pairAdvance(table, left, right, &applied);
			if (applied) { break; }
		}
	}
	return total;
}

int void2dGlyphFaceLoad(const char *path) {
	long size = 0;
	unsigned char *bytes = readWholeFile(path, &size);
	if (!bytes) {
		fprintf(stderr, "void2d: cannot read font file %s\n", path);
		return -1;
	}
	int offset = stbtt_GetFontOffsetForIndex(bytes, 0);
	stbtt_fontinfo info;
	if (offset < 0 || !stbtt_InitFont(&info, bytes, offset)) {
		fprintf(stderr, "void2d: %s is not a font stb_truetype can read\n", path);
		free(bytes);
		return -1;
	}
	if (s_faceCount == s_faceCapacity) {
		int grown = s_faceCapacity ? s_faceCapacity * 2 : 4;
		GlyphFace *faces = (GlyphFace *)realloc(s_faces, sizeof(GlyphFace) * (size_t)grown);
		if (!faces) {
			fprintf(stderr, "void2d: no memory for %d font faces\n", grown);
			free(bytes);
			return -1;
		}
		s_faces = faces;
		s_faceCapacity = grown;
	}
	s_faces[s_faceCount].bytes = bytes;
	s_faces[s_faceCount].info = info;
	findKernLookups(&s_faces[s_faceCount]);
	return s_faceCount++;
}

int void2dGlyphFaceCount(void) { return s_faceCount; }

float void2dGlyphScale(int face, float sizePx) {
	if (!validFace(face)) { return 0.0f; }
	return stbtt_ScaleForMappingEmToPixels(&s_faces[face].info, sizePx);
}

float *void2dGlyphFaceMetrics(int face, float sizePx) {
	s_metrics[0] = 0.0f; s_metrics[1] = 0.0f; s_metrics[2] = 0.0f;
	if (!validFace(face)) { return s_metrics; }
	int ascent = 0, descent = 0, lineGap = 0;
	stbtt_GetFontVMetrics(&s_faces[face].info, &ascent, &descent, &lineGap);
	float scale = void2dGlyphScale(face, sizePx);
	s_metrics[0] = (float)ascent * scale;
	s_metrics[1] = (float)-descent * scale;
	s_metrics[2] = (float)lineGap * scale;
	return s_metrics;
}

int void2dGlyphIndex(int face, int codepoint) {
	if (!validFace(face)) { return 0; }
	return stbtt_FindGlyphIndex(&s_faces[face].info, codepoint);
}

float void2dGlyphAdvance(int face, int glyph, float sizePx) {
	if (!validFace(face)) { return 0.0f; }
	int advance = 0, bearing = 0;
	stbtt_GetGlyphHMetrics(&s_faces[face].info, glyph, &advance, &bearing);
	return (float)advance * void2dGlyphScale(face, sizePx);
}

float void2dGlyphKern(int face, int left, int right, float sizePx) {
	if (!validFace(face)) { return 0.0f; }
	GlyphFace *f = &s_faces[face];
	int units = f->kernLookupCount > 0
		? gposKern(f, left, right)
		: stbtt__GetGlyphKernInfoAdvance(&f->info, left, right);
	return (float)units * void2dGlyphScale(face, sizePx);
}

int *void2dGlyphBox(int face, int glyph, float sizePx, float shiftX) {
	s_box[0] = 0; s_box[1] = 0; s_box[2] = 0; s_box[3] = 0;
	if (!validFace(face)) { return s_box; }
	float scale = void2dGlyphScale(face, sizePx);
	stbtt_GetGlyphBitmapBoxSubpixel(&s_faces[face].info, glyph, scale, scale, shiftX, 0.0f,
		&s_box[0], &s_box[1], &s_box[2], &s_box[3]);
	return s_box;
}

int void2dGlyphPageCreate(int size) {
	if (size <= 0) { return -1; }
	if (s_pageCount == s_pageCapacity) {
		int grown = s_pageCapacity ? s_pageCapacity * 2 : 4;
		GlyphPage *pages = (GlyphPage *)realloc(s_pages, sizeof(GlyphPage) * (size_t)grown);
		if (!pages) {
			fprintf(stderr, "void2d: no memory for %d glyph pages\n", grown);
			return -1;
		}
		s_pages = pages;
		s_pageCapacity = grown;
	}
	unsigned char *texels = (unsigned char *)calloc((size_t)size * (size_t)size, 1);
	if (!texels) {
		fprintf(stderr, "void2d: no memory for a %dx%d glyph page\n", size, size);
		return -1;
	}
	s_pages[s_pageCount].texels = texels;
	s_pages[s_pageCount].size = size;
	s_pages[s_pageCount].dirty = 1;
	return s_pageCount++;
}

int void2dGlyphPageCount(void) { return s_pageCount; }

int void2dGlyphPageSize(int page) { return validPage(page) ? s_pages[page].size : 0; }

void void2dGlyphPageClear(int page) {
	if (!validPage(page)) { return; }
	size_t size = (size_t)s_pages[page].size;
	memset(s_pages[page].texels, 0, size * size);
	s_pages[page].dirty = 1;
}

void void2dGlyphRasterize(int face, int glyph, float sizePx, float shiftX,
                          int page, int x, int y, int w, int h) {
	if (!validFace(face) || !validPage(page) || w <= 0 || h <= 0) { return; }
	GlyphPage *p = &s_pages[page];
	if (x < 0 || y < 0 || x + w > p->size || y + h > p->size) {
		fprintf(stderr, "void2d: glyph tile %dx%d at (%d,%d) falls outside its %d page\n",
			w, h, x, y, p->size);
		return;
	}
	float scale = void2dGlyphScale(face, sizePx);
	stbtt_MakeGlyphBitmapSubpixel(&s_faces[face].info, p->texels + (size_t)y * (size_t)p->size + (size_t)x,
		w, h, p->size, scale, scale, shiftX, 0.0f, glyph);
	p->dirty = 1;
}

int void2dGlyphPageTexel(int page, int x, int y) {
	if (!validPage(page)) { return -1; }
	GlyphPage *p = &s_pages[page];
	if (x < 0 || y < 0 || x >= p->size || y >= p->size) { return -1; }
	return p->texels[(size_t)y * (size_t)p->size + (size_t)x];
}

const unsigned char *void2dGlyphPageData(int page) {
	return validPage(page) ? s_pages[page].texels : NULL;
}

int void2dGlyphPageDirty(int page) { return validPage(page) ? s_pages[page].dirty : 0; }

void void2dGlyphPageClean(int page) {
	if (validPage(page)) { s_pages[page].dirty = 0; }
}
