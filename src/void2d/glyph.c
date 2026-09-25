#include "glyph.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define STBTT_STATIC
#define STB_TRUETYPE_IMPLEMENTATION
#include "../../deps/stb/stb_truetype.h"

#define GLYPH_MAX_KERN_LOOKUPS 32
#define GLYPH_ITALIC_SKEW 0.21255656f

typedef struct {
	float cap, ex, ic;
	float capEstimate, exEstimate, icEstimate;
	float lineHeight;
} FaceHeights;

typedef struct {
	unsigned char *bytes;
	int length;
	stbtt_fontinfo info;
	int kernLookups[GLYPH_MAX_KERN_LOOKUPS];
	int kernLookupCount;
	float emboldenUnits;
	float skew;
	int measured;
	FaceHeights heights;
	float underlineTop, underlineThickness, strikeTop, strikeThickness;
} GlyphFace;

typedef struct {
	float x, y;
	stbtt_vertex_type *px, *py;
} GlyphPoint;

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
static float s_decoration[4];
static float s_heights[7];
static int s_box[4];
static int s_glyphLookups;
static GlyphRasterBox s_rasterBox;
static GlyphRasterFill s_rasterFill;

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

static void pushPoint(GlyphPoint *points, int *count, stbtt_vertex_type *x, stbtt_vertex_type *y) {
	points[*count].x = (float)*x;
	points[*count].y = (float)*y;
	points[*count].px = x;
	points[*count].py = y;
	(*count)++;
}

static int outlinePoints(stbtt_vertex *v, int count, GlyphPoint *points, int *contourEnds) {
	int n = 0, contours = 0;
	for (int i = 0; i < count; i++) {
		if (v[i].type == STBTT_vmove) {
			if (n > 0) { contourEnds[contours++] = n - 1; }
		} else if (v[i].type == STBTT_vcurve) {
			pushPoint(points, &n, &v[i].cx, &v[i].cy);
		} else if (v[i].type == STBTT_vcubic) {
			pushPoint(points, &n, &v[i].cx, &v[i].cy);
			pushPoint(points, &n, &v[i].cx1, &v[i].cy1);
		}
		pushPoint(points, &n, &v[i].x, &v[i].y);
	}
	if (n > 0) { contourEnds[contours++] = n - 1; }
	return contours;
}

static float normLen(float *x, float *y) {
	float len = sqrtf(*x * *x + *y * *y);
	if (len > 0.0f) { *x /= len; *y /= len; }
	return len;
}

static void emboldenContour(GlyphPoint *p, int first, int last, float strength, int trueType) {
	float xs = strength * 0.5f, ys = strength * 0.5f;
	float inX = 0.0f, inY = 0.0f, anchorX = 0.0f, anchorY = 0.0f;
	float lIn = 0.0f, lAnchor = 0.0f;
	int i = last, j = first, k = -1;
	for (; j != i && i != k; j = j < last ? j + 1 : first) {
		float outX, outY, lOut;
		if (j != k) {
			outX = p[j].x - p[i].x;
			outY = p[j].y - p[i].y;
			lOut = normLen(&outX, &outY);
			if (lOut == 0.0f) { continue; }
		} else {
			outX = anchorX; outY = anchorY; lOut = lAnchor;
		}
		if (lIn != 0.0f) {
			if (k < 0) { k = i; anchorX = inX; anchorY = inY; lAnchor = lIn; }
			float d = inX * outX + inY * outY;
			float shiftX = 0.0f, shiftY = 0.0f;
			if (d > -0.9375f) {
				d += 1.0f;
				shiftX = inY + outY;
				shiftY = inX + outX;
				if (trueType) { shiftX = -shiftX; } else { shiftY = -shiftY; }
				float q = outX * inY - outY * inX;
				if (trueType) { q = -q; }
				float l = lIn < lOut ? lIn : lOut;
				shiftX = xs * q <= l * d ? shiftX * xs / d : shiftX * l / q;
				shiftY = ys * q <= l * d ? shiftY * ys / d : shiftY * l / q;
			}
			for (; i != j; i = i < last ? i + 1 : first) {
				p[i].x += xs + shiftX;
				p[i].y += ys + shiftY;
			}
		} else {
			i = j;
		}
		inX = outX; inY = outY; lIn = lOut;
	}
}

static void embolden(stbtt_vertex *v, int count, float strength) {
	GlyphPoint *points = (GlyphPoint *)malloc(sizeof(GlyphPoint) * (size_t)count * 3);
	int *ends = (int *)malloc(sizeof(int) * (size_t)count);
	if (!points || !ends) {
		fprintf(stderr, "void2d: no memory to embolden a %d-vertex glyph; it is drawn regular\n", count);
		free(points);
		free(ends);
		return;
	}
	int contours = outlinePoints(v, count, points, ends);
	float area = 0.0f;
	for (int c = 0, first = 0; c < contours; first = ends[c] + 1, c++) {
		for (int i = first, prev = ends[c]; i <= ends[c]; prev = i, i++) {
			area += (points[i].y - points[prev].y) * (points[i].x + points[prev].x);
		}
	}
	if (area != 0.0f) {
		for (int c = 0, first = 0; c < contours; first = ends[c] + 1, c++) {
			int last = ends[c];
			int closed = last > first && points[last].x == points[first].x && points[last].y == points[first].y;
			emboldenContour(points, first, closed ? last - 1 : last, strength, area < 0.0f);
			if (closed) { points[last].x = points[first].x; points[last].y = points[first].y; }
		}
	}
	int total = contours ? ends[contours - 1] + 1 : 0;
	for (int i = 0; i < total; i++) {
		*points[i].px = (stbtt_vertex_type)floorf(points[i].x + 0.5f);
		*points[i].py = (stbtt_vertex_type)floorf(points[i].y + 0.5f);
	}
	free(points);
	free(ends);
}

static int isSynthetic(GlyphFace *face) { return face->emboldenUnits > 0.0f || face->skew != 0.0f; }

static int glyphShape(GlyphFace *face, int glyph, stbtt_vertex **vertices) {
	int count = stbtt_GetGlyphShape(&face->info, glyph, vertices);
	if (count <= 0) { return count; }
	if (face->emboldenUnits > 0.0f) { embolden(*vertices, count, face->emboldenUnits); }
	if (face->skew != 0.0f) {
		for (int i = 0; i < count; i++) {
			stbtt_vertex *v = &(*vertices)[i];
			v->x = (stbtt_vertex_type)floorf(v->x + v->y * face->skew + 0.5f);
			if (v->type == STBTT_vcurve || v->type == STBTT_vcubic) {
				v->cx = (stbtt_vertex_type)floorf(v->cx + v->cy * face->skew + 0.5f);
			}
			if (v->type == STBTT_vcubic) {
				v->cx1 = (stbtt_vertex_type)floorf(v->cx1 + v->cy1 * face->skew + 0.5f);
			}
		}
	}
	return count;
}

static void shapeBox(stbtt_vertex *v, int count, float scale, float shiftX, int *box) {
	box[0] = box[1] = box[2] = box[3] = 0;
	if (count <= 0) { return; }
	float x0 = v[0].x, x1 = v[0].x, y0 = v[0].y, y1 = v[0].y;
	for (int i = 0; i < count; i++) {
		float xs[3] = { v[i].x, v[i].cx, v[i].cx1 };
		float ys[3] = { v[i].y, v[i].cy, v[i].cy1 };
		int used = v[i].type == STBTT_vcubic ? 3 : v[i].type == STBTT_vcurve ? 2 : 1;
		for (int k = 0; k < used; k++) {
			if (xs[k] < x0) { x0 = xs[k]; }
			if (xs[k] > x1) { x1 = xs[k]; }
			if (ys[k] < y0) { y0 = ys[k]; }
			if (ys[k] > y1) { y1 = ys[k]; }
		}
	}
	box[0] = (int)floorf(x0 * scale + shiftX);
	box[1] = (int)floorf(-y1 * scale);
	box[2] = (int)ceilf(x1 * scale + shiftX);
	box[3] = (int)ceilf(-y0 * scale);
}

static stbtt_uint8 *findTable(GlyphFace *face, const char *tag, int *length) {
	stbtt_uint8 *font = face->bytes + face->info.fontstart;
	int tables = ttUSHORT(font + 4);
	*length = 0;
	for (int i = 0; i < tables; i++) {
		stbtt_uint8 *record = font + 12 + 16 * i;
		if (memcmp(record, tag, 4) != 0) { continue; }
		*length = (int)ttULONG(record + 12);
		return face->bytes + ttULONG(record + 8);
	}
	return NULL;
}

static int findGlyph(GlyphFace *face, int codepoint) {
	s_glyphLookups++;
	return stbtt_FindGlyphIndex(&face->info, codepoint);
}

int void2dGlyphLookups(void) { return s_glyphLookups; }

static float glyphHeight(GlyphFace *face, int codepoint) {
	int glyph = findGlyph(face, codepoint);
	int x0 = 0, y0 = 0, x1 = 0, y1 = 0;
	if (glyph == 0 || !stbtt_GetGlyphBox(&face->info, glyph, &x0, &y0, &x1, &y1)) { return 0.0f; }
	return (float)(y1 - y0);
}

static void asciiExtent(GlyphFace *face, float *height, float *cellWidth) {
	int top = 0, bottom = 0, widest = 0;
	for (int c = ' '; c < 127; c++) {
		int glyph = findGlyph(face, c);
		if (glyph == 0) { continue; }
		int advance = 0, bearing = 0, x0 = 0, y0 = 0, x1 = 0, y1 = 0;
		stbtt_GetGlyphHMetrics(&face->info, glyph, &advance, &bearing);
		if (advance > widest) { widest = advance; }
		if (stbtt_GetGlyphBox(&face->info, glyph, &x0, &y0, &x1, &y1)) {
			if (y1 > top) { top = y1; }
			if (y0 < bottom) { bottom = y0; }
		}
	}
	*height = (float)(top - bottom);
	*cellWidth = (float)widest;
}

static float ideographWidth(GlyphFace *face) {
	int glyph = findGlyph(face, 0x6C34);
	if (glyph == 0) { return 0.0f; }
	int advance = 0, bearing = 0, x0 = 0, y0 = 0, x1 = 0, y1 = 0;
	stbtt_GetGlyphHMetrics(&face->info, glyph, &advance, &bearing);
	if (stbtt_GetGlyphBox(&face->info, glyph, &x0, &y0, &x1, &y1) && x1 - x0 > advance) { return 0.0f; }
	return (float)advance;
}

static void measureHeights(GlyphFace *f, FaceHeights *h) {
	int ascent = 0, descent = 0, lineGap = 0;
	stbtt_GetFontVMetrics(&f->info, &ascent, &descent, &lineGap);
	int os2Length = 0;
	stbtt_uint8 *os2 = findTable(f, "OS/2", &os2Length);
	if (os2 && ttUSHORT(os2) >= 2 && os2Length >= 90) {
		h->ex = (float)ttSHORT(os2 + 86);
		h->cap = (float)ttSHORT(os2 + 88);
	} else {
		h->ex = glyphHeight(f, 'x');
		h->cap = glyphHeight(f, 'H');
	}
	h->ic = ideographWidth(f);
	h->capEstimate = h->cap > 0.0f ? h->cap : 0.75f * (float)ascent;
	h->exEstimate = h->ex > 0.0f ? h->ex : 0.75f * h->capEstimate;
	float asciiHeight = 0.0f, cellWidth = 0.0f;
	asciiExtent(f, &asciiHeight, &cellWidth);
	if (asciiHeight <= 0.0f) { asciiHeight = 1.5f * h->capEstimate; }
	float twoCells = 2.0f * cellWidth;
	h->icEstimate = h->ic > 0.0f ? h->ic : (asciiHeight < twoCells ? asciiHeight : twoCells);
	h->lineHeight = (float)(ascent - descent + lineGap);
}

static void measureFace(GlyphFace *f) {
	if (f->measured) { return; }
	measureHeights(f, &f->heights);
	int postLength = 0, os2Length = 0;
	stbtt_uint8 *post = findTable(f, "post", &postLength);
	stbtt_uint8 *os2 = findTable(f, "OS/2", &os2Length);
	if (postLength < 12) { post = NULL; }
	if (os2Length < 30) { os2 = NULL; }
	float exHeight = f->heights.exEstimate;
	int underlinePosition = post ? ttSHORT(post + 8) : 0;
	int underlineSize = post ? ttSHORT(post + 10) : 0;
	f->underlineThickness = underlineSize > 0 ? (float)underlineSize : 0.15f * exHeight;
	f->underlineTop = post && (underlineSize != 0 || underlinePosition != 0)
		? (float)underlinePosition : -f->underlineThickness;
	int strikeSize = os2 ? ttSHORT(os2 + 26) : 0;
	int strikePosition = os2 ? ttSHORT(os2 + 28) : 0;
	f->strikeThickness = strikeSize > 0 ? (float)strikeSize : f->underlineThickness;
	f->strikeTop = os2 && (strikeSize != 0 || strikePosition != 0)
		? (float)strikePosition : (exHeight + f->strikeThickness) * 0.5f;
	f->measured = 1;
}

float *void2dGlyphFaceHeights(int face) {
	for (int i = 0; i < 7; i++) { s_heights[i] = 0.0f; }
	if (!validFace(face)) { return s_heights; }
	measureFace(&s_faces[face]);
	const FaceHeights *h = &s_faces[face].heights;
	float perEm = void2dGlyphScale(face, 1.0f);
	s_heights[0] = (h->ic > 0.0f ? h->ic : 0.0f) * perEm;
	s_heights[1] = (h->ex > 0.0f ? h->ex : 0.0f) * perEm;
	s_heights[2] = (h->cap > 0.0f ? h->cap : 0.0f) * perEm;
	s_heights[3] = h->icEstimate * perEm;
	s_heights[4] = h->exEstimate * perEm;
	s_heights[5] = h->capEstimate * perEm;
	s_heights[6] = h->lineHeight * perEm;
	return s_heights;
}

float *void2dGlyphDecoration(int face, float sizePx) {
	s_decoration[0] = 0.0f; s_decoration[1] = 0.0f; s_decoration[2] = 0.0f; s_decoration[3] = 0.0f;
	if (!validFace(face)) { return s_decoration; }
	GlyphFace *f = &s_faces[face];
	measureFace(f);
	float scale = void2dGlyphScale(face, sizePx);
	s_decoration[0] = -f->underlineTop * scale;
	s_decoration[1] = f->underlineThickness * scale;
	s_decoration[2] = -f->strikeTop * scale;
	s_decoration[3] = f->strikeThickness * scale;
	return s_decoration;
}

static int growFaces(void) {
	if (s_faceCount < s_faceCapacity) { return 1; }
	int grown = s_faceCapacity ? s_faceCapacity * 2 : 4;
	GlyphFace *faces = (GlyphFace *)realloc(s_faces, sizeof(GlyphFace) * (size_t)grown);
	if (!faces) {
		fprintf(stderr, "void2d: no memory for %d font faces\n", grown);
		return 0;
	}
	s_faces = faces;
	s_faceCapacity = grown;
	return 1;
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
	if (!growFaces()) {
		free(bytes);
		return -1;
	}
	s_faces[s_faceCount].bytes = bytes;
	s_faces[s_faceCount].length = (int)size;
	s_faces[s_faceCount].info = info;
	s_faces[s_faceCount].emboldenUnits = 0.0f;
	s_faces[s_faceCount].skew = 0.0f;
	s_faces[s_faceCount].measured = 0;
	findKernLookups(&s_faces[s_faceCount]);
	return s_faceCount++;
}

int void2dGlyphFaceSynthetic(int face, int bold, int italic) {
	if (!validFace(face) || !growFaces()) { return -1; }
	GlyphFace synthetic = s_faces[face];
	if (bold) {
		int ascent = 0, descent = 0, lineGap = 0;
		stbtt_GetFontVMetrics(&synthetic.info, &ascent, &descent, &lineGap);
		synthetic.emboldenUnits = (float)(ascent - descent + lineGap) / 32.0f;
	}
	if (italic) { synthetic.skew = GLYPH_ITALIC_SKEW; }
	s_faces[s_faceCount] = synthetic;
	return s_faceCount++;
}

int void2dGlyphFaceCount(void) { return s_faceCount; }

void void2dGlyphSetRasterizer(GlyphRasterBox box, GlyphRasterFill fill) {
	s_rasterBox = box;
	s_rasterFill = fill;
}

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
	return findGlyph(&s_faces[face], codepoint);
}

float void2dGlyphAdvance(int face, int glyph, float sizePx) {
	if (!validFace(face)) { return 0.0f; }
	int advance = 0, bearing = 0;
	stbtt_GetGlyphHMetrics(&s_faces[face].info, glyph, &advance, &bearing);
	return ((float)advance + s_faces[face].emboldenUnits) * void2dGlyphScale(face, sizePx);
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
	GlyphFace *f = &s_faces[face];
	if (s_rasterBox && !isSynthetic(f)) {
		s_rasterBox(f->bytes, f->length, glyph, sizePx, shiftX, s_box);
		return s_box;
	}
	if (isSynthetic(f)) {
		stbtt_vertex *vertices = NULL;
		int count = glyphShape(f, glyph, &vertices);
		shapeBox(vertices, count, scale, shiftX, s_box);
		STBTT_free(vertices, f->info.userdata);
		return s_box;
	}
	stbtt_GetGlyphBitmapBoxSubpixel(&f->info, glyph, scale, scale, shiftX, 0.0f,
		&s_box[0], &s_box[1], &s_box[2], &s_box[3]);
	return s_box;
}

int void2dGlyphPageCreate(int size) {
	if (size <= 0) { return -1; }
	if (s_pageCount >= VOID2D_MAX_GLYPH_PAGES) {
		fprintf(stderr, "void2d: glyph page %d refused, the renderer binds at most %d\n",
			s_pageCount, VOID2D_MAX_GLYPH_PAGES);
		return -1;
	}
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
	GlyphFace *f = &s_faces[face];
	unsigned char *at = p->texels + (size_t)y * (size_t)p->size + (size_t)x;
	if (s_rasterFill && !isSynthetic(f)) {
		s_rasterFill(f->bytes, f->length, glyph, sizePx, shiftX, at, w, h, p->size);
	} else if (isSynthetic(f)) {
		stbtt_vertex *vertices = NULL;
		int count = glyphShape(f, glyph, &vertices);
		int box[4];
		shapeBox(vertices, count, scale, shiftX, box);
		stbtt__bitmap bitmap = { w, h, p->size, at };
		if (count > 0) {
			stbtt_Rasterize(&bitmap, 0.35f, vertices, count, scale, scale, shiftX, 0.0f,
				box[0], box[1], 1, f->info.userdata);
		}
		STBTT_free(vertices, f->info.userdata);
	} else {
		stbtt_MakeGlyphBitmapSubpixel(&f->info, at, w, h, p->size, scale, scale, shiftX, 0.0f, glyph);
	}
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
