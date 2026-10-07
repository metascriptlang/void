#include "spriteGlyph.h"
#include "glyph.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum {
	FAMILY_BOX,
	FAMILY_BLOCK,
	FAMILY_BRAILLE,
	FAMILY_GEOMETRIC,
	FAMILY_POWERLINE,
	FAMILY_OCTANT,
	FAMILY_SEXTANT,
	FAMILY_LEGACY_BLOCK,
};

enum { LINE_NONE, LINE_LIGHT, LINE_HEAVY, LINE_DOUBLE };

typedef struct {
	int min;
	int max;
	int family;
	int first;
} SpriteRange;

typedef struct {
	uint8_t *px;
	int width;
	int height;
	int padX;
	int padY;
} Canvas;

typedef struct {
	unsigned int cellWidth;
	unsigned int cellHeight;
	unsigned int boxThickness;
} Metrics;

typedef struct {
	unsigned char up, right, down, left;
} Lines;

static const SpriteRange s_ranges[] = {
	{ 0x2500, 0x257F, FAMILY_BOX, 0 },
	{ 0x2580, 0x259F, FAMILY_BLOCK, 128 },
	{ 0x25E2, 0x25E5, FAMILY_GEOMETRIC, 160 },
	{ 0x25F8, 0x25FA, FAMILY_GEOMETRIC, 164 },
	{ 0x25FF, 0x25FF, FAMILY_GEOMETRIC, 167 },
	{ 0x2800, 0x28FF, FAMILY_BRAILLE, 168 },
	{ 0xE0B0, 0xE0BF, FAMILY_POWERLINE, 424 },
	{ 0xE0D2, 0xE0D2, FAMILY_POWERLINE, 440 },
	{ 0xE0D4, 0xE0D4, FAMILY_POWERLINE, 441 },
	{ 0x1CD00, 0x1CDE5, FAMILY_OCTANT, 442 },
	{ 0x1FB00, 0x1FB3B, FAMILY_SEXTANT, 672 },
	{ 0x1FB70, 0x1FB92, FAMILY_LEGACY_BLOCK, 732 },
	{ 0x1FB94, 0x1FB97, FAMILY_LEGACY_BLOCK, 767 },
};

#define RANGE_COUNT ((int)(sizeof(s_ranges) / sizeof(s_ranges[0])))

static const Lines s_boxLines[0x80] = {
	{ 0, 1, 0, 1 },
	{ 0, 2, 0, 2 },
	{ 1, 0, 1, 0 },
	{ 2, 0, 2, 0 },
	{ 0, 0, 0, 0 },
	{ 0, 0, 0, 0 },
	{ 0, 0, 0, 0 },
	{ 0, 0, 0, 0 },
	{ 0, 0, 0, 0 },
	{ 0, 0, 0, 0 },
	{ 0, 0, 0, 0 },
	{ 0, 0, 0, 0 },
	{ 0, 1, 1, 0 },
	{ 0, 2, 1, 0 },
	{ 0, 1, 2, 0 },
	{ 0, 2, 2, 0 },
	{ 0, 0, 1, 1 },
	{ 0, 0, 1, 2 },
	{ 0, 0, 2, 1 },
	{ 0, 0, 2, 2 },
	{ 1, 1, 0, 0 },
	{ 1, 2, 0, 0 },
	{ 2, 1, 0, 0 },
	{ 2, 2, 0, 0 },
	{ 1, 0, 0, 1 },
	{ 1, 0, 0, 2 },
	{ 2, 0, 0, 1 },
	{ 2, 0, 0, 2 },
	{ 1, 1, 1, 0 },
	{ 1, 2, 1, 0 },
	{ 2, 1, 1, 0 },
	{ 1, 1, 2, 0 },
	{ 2, 1, 2, 0 },
	{ 2, 2, 1, 0 },
	{ 1, 2, 2, 0 },
	{ 2, 2, 2, 0 },
	{ 1, 0, 1, 1 },
	{ 1, 0, 1, 2 },
	{ 2, 0, 1, 1 },
	{ 1, 0, 2, 1 },
	{ 2, 0, 2, 1 },
	{ 2, 0, 1, 2 },
	{ 1, 0, 2, 2 },
	{ 2, 0, 2, 2 },
	{ 0, 1, 1, 1 },
	{ 0, 1, 1, 2 },
	{ 0, 2, 1, 1 },
	{ 0, 2, 1, 2 },
	{ 0, 1, 2, 1 },
	{ 0, 1, 2, 2 },
	{ 0, 2, 2, 1 },
	{ 0, 2, 2, 2 },
	{ 1, 1, 0, 1 },
	{ 1, 1, 0, 2 },
	{ 1, 2, 0, 1 },
	{ 1, 2, 0, 2 },
	{ 2, 1, 0, 1 },
	{ 2, 1, 0, 2 },
	{ 2, 2, 0, 1 },
	{ 2, 2, 0, 2 },
	{ 1, 1, 1, 1 },
	{ 1, 1, 1, 2 },
	{ 1, 2, 1, 1 },
	{ 1, 2, 1, 2 },
	{ 2, 1, 1, 1 },
	{ 1, 1, 2, 1 },
	{ 2, 1, 2, 1 },
	{ 2, 1, 1, 2 },
	{ 2, 2, 1, 1 },
	{ 1, 1, 2, 2 },
	{ 1, 2, 2, 1 },
	{ 2, 2, 1, 2 },
	{ 1, 2, 2, 2 },
	{ 2, 1, 2, 2 },
	{ 2, 2, 2, 1 },
	{ 2, 2, 2, 2 },
	{ 0, 0, 0, 0 },
	{ 0, 0, 0, 0 },
	{ 0, 0, 0, 0 },
	{ 0, 0, 0, 0 },
	{ 0, 3, 0, 3 },
	{ 3, 0, 3, 0 },
	{ 0, 3, 1, 0 },
	{ 0, 1, 3, 0 },
	{ 0, 3, 3, 0 },
	{ 0, 0, 1, 3 },
	{ 0, 0, 3, 1 },
	{ 0, 0, 3, 3 },
	{ 1, 3, 0, 0 },
	{ 3, 1, 0, 0 },
	{ 3, 3, 0, 0 },
	{ 1, 0, 0, 3 },
	{ 3, 0, 0, 1 },
	{ 3, 0, 0, 3 },
	{ 1, 3, 1, 0 },
	{ 3, 1, 3, 0 },
	{ 3, 3, 3, 0 },
	{ 1, 0, 1, 3 },
	{ 3, 0, 3, 1 },
	{ 3, 0, 3, 3 },
	{ 0, 3, 1, 3 },
	{ 0, 1, 3, 1 },
	{ 0, 3, 3, 3 },
	{ 1, 3, 0, 3 },
	{ 3, 1, 0, 1 },
	{ 3, 3, 0, 3 },
	{ 1, 3, 1, 3 },
	{ 3, 1, 3, 1 },
	{ 3, 3, 3, 3 },
	{ 0, 0, 0, 0 },
	{ 0, 0, 0, 0 },
	{ 0, 0, 0, 0 },
	{ 0, 0, 0, 0 },
	{ 0, 0, 0, 0 },
	{ 0, 0, 0, 0 },
	{ 0, 0, 0, 0 },
	{ 0, 0, 0, 1 },
	{ 1, 0, 0, 0 },
	{ 0, 1, 0, 0 },
	{ 0, 0, 1, 0 },
	{ 0, 0, 0, 2 },
	{ 2, 0, 0, 0 },
	{ 0, 2, 0, 0 },
	{ 0, 0, 2, 0 },
	{ 0, 2, 0, 1 },
	{ 1, 0, 2, 0 },
	{ 0, 1, 0, 2 },
	{ 2, 0, 1, 0 },
};

static const unsigned char s_octants[230] = {
	0x04, 0x06, 0x07, 0x08, 0x09, 0x0B, 0x0C, 0x0D, 0x0E, 0x10, 0x11, 0x12,
	0x13, 0x15, 0x16, 0x17, 0x18, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F,
	0x20, 0x21, 0x22, 0x23, 0x24, 0x25, 0x26, 0x27, 0x29, 0x2A, 0x2B, 0x2C,
	0x2D, 0x2E, 0x2F, 0x30, 0x31, 0x32, 0x33, 0x34, 0x35, 0x36, 0x37, 0x38,
	0x39, 0x3A, 0x3B, 0x3C, 0x3D, 0x3E, 0x41, 0x42, 0x43, 0x44, 0x45, 0x46,
	0x47, 0x48, 0x49, 0x4A, 0x4B, 0x4C, 0x4D, 0x4E, 0x4F, 0x51, 0x52, 0x53,
	0x54, 0x56, 0x57, 0x58, 0x59, 0x5B, 0x5C, 0x5D, 0x5E, 0x60, 0x61, 0x62,
	0x63, 0x64, 0x65, 0x66, 0x67, 0x68, 0x69, 0x6A, 0x6B, 0x6C, 0x6D, 0x6E,
	0x6F, 0x70, 0x71, 0x72, 0x73, 0x74, 0x75, 0x76, 0x77, 0x78, 0x79, 0x7A,
	0x7B, 0x7C, 0x7D, 0x7E, 0x7F, 0x81, 0x82, 0x83, 0x84, 0x85, 0x86, 0x87,
	0x88, 0x89, 0x8A, 0x8B, 0x8C, 0x8D, 0x8E, 0x8F, 0x90, 0x91, 0x92, 0x93,
	0x94, 0x95, 0x96, 0x97, 0x98, 0x99, 0x9A, 0x9B, 0x9C, 0x9D, 0x9E, 0x9F,
	0xA1, 0xA2, 0xA3, 0xA4, 0xA6, 0xA7, 0xA8, 0xA9, 0xAB, 0xAC, 0xAD, 0xAE,
	0xB0, 0xB1, 0xB2, 0xB3, 0xB4, 0xB5, 0xB6, 0xB7, 0xB8, 0xB9, 0xBA, 0xBB,
	0xBC, 0xBD, 0xBE, 0xBF, 0xC1, 0xC2, 0xC3, 0xC4, 0xC5, 0xC6, 0xC7, 0xC8,
	0xC9, 0xCA, 0xCB, 0xCC, 0xCD, 0xCE, 0xCF, 0xD0, 0xD1, 0xD2, 0xD3, 0xD4,
	0xD5, 0xD6, 0xD7, 0xD8, 0xD9, 0xDA, 0xDB, 0xDC, 0xDD, 0xDE, 0xDF, 0xE0,
	0xE1, 0xE2, 0xE3, 0xE4, 0xE5, 0xE6, 0xE7, 0xE8, 0xE9, 0xEA, 0xEB, 0xEC,
	0xED, 0xEE, 0xEF, 0xF1, 0xF2, 0xF3, 0xF4, 0xF6, 0xF7, 0xF8, 0xF9, 0xFB,
	0xFD, 0xFE,
};

static int rangeOf(int codepoint) {
	for (int i = 0; i < RANGE_COUNT; i++) {
		if (codepoint >= s_ranges[i].min && codepoint <= s_ranges[i].max) { return i; }
	}
	return -1;
}

int void2dSpriteCount(void) {
	const SpriteRange *last = &s_ranges[RANGE_COUNT - 1];
	return last->first + (last->max - last->min + 1);
}

int void2dSpriteIndex(int codepoint) {
	int r = rangeOf(codepoint);
	if (r < 0) { return 0; }
	return 1 + s_ranges[r].first + (codepoint - s_ranges[r].min);
}

int void2dSpriteCodepoint(int id) {
	if (id < 1 || id > void2dSpriteCount()) { return 0; }
	int at = id - 1;
	for (int i = RANGE_COUNT - 1; i >= 0; i--) {
		if (at >= s_ranges[i].first) { return s_ranges[i].min + (at - s_ranges[i].first); }
	}
	return 0;
}

int void2dSpriteTableFault(void) {
	int expectedFirst = 0;
	for (int i = 0; i < RANGE_COUNT; i++) {
		if (s_ranges[i].max < s_ranges[i].min) { return i + 1; }
		if (i > 0 && s_ranges[i].min <= s_ranges[i - 1].max) { return i + 1; }
		if (s_ranges[i].first != expectedFirst) { return i + 1; }
		expectedFirst += s_ranges[i].max - s_ranges[i].min + 1;
	}
	return 0;
}

int void2dSpritePadding(int cellSize) { return cellSize > 0 ? cellSize / 4 : 0; }

int void2dSpriteCanvasWidth(int cellWidth) {
	return cellWidth + 2 * void2dSpritePadding(cellWidth);
}

int void2dSpriteCanvasHeight(int cellHeight) {
	return cellHeight + 2 * void2dSpritePadding(cellHeight);
}

static void putPixel(Canvas *c, int x, int y, uint8_t value) {
	x += c->padX;
	y += c->padY;
	if (x < 0 || y < 0 || x >= c->width || y >= c->height) { return; }
	c->px[(size_t)y * (size_t)c->width + (size_t)x] = value;
}

static void fillBox(Canvas *c, int x0, int y0, int x1, int y1, uint8_t value) {
	int left = x0 < x1 ? x0 : x1;
	int right = x0 < x1 ? x1 : x0;
	int top = y0 < y1 ? y0 : y1;
	int bottom = y0 < y1 ? y1 : y0;
	for (int y = top; y < bottom; y++) {
		for (int x = left; x < right; x++) { putPixel(c, x, y, value); }
	}
}

static unsigned int subSat(unsigned int a, unsigned int b) { return a > b ? a - b : 0; }

static int fracMin(double fraction, unsigned int size) {
	double s = (double)size;
	return (int)(s - round((1.0 - fraction) * s));
}

static int fracMax(double fraction, unsigned int size) {
	return (int)round(fraction * (double)size);
}

static void fillFractions(const Metrics *m, Canvas *c, double x0, double x1, double y0, double y1) {
	fillBox(c, fracMin(x0, m->cellWidth), fracMin(y0, m->cellHeight),
		fracMax(x1, m->cellWidth), fracMax(y1, m->cellHeight), 255);
}

enum { ALIGN_LEFT, ALIGN_RIGHT, ALIGN_UPPER, ALIGN_LOWER };

static void blockShade(const Metrics *m, Canvas *c, int horizontal, int vertical,
                       double widthFraction, double heightFraction, uint8_t shade) {
	unsigned int w = (unsigned int)round((double)m->cellWidth * widthFraction);
	unsigned int h = (unsigned int)round((double)m->cellHeight * heightFraction);
	unsigned int x = horizontal == ALIGN_RIGHT ? m->cellWidth - w : 0;
	unsigned int y = vertical == ALIGN_LOWER ? m->cellHeight - h : 0;
	fillBox(c, (int)x, (int)y, (int)(x + w), (int)(y + h), shade);
}

static void quadrants(const Metrics *m, Canvas *c, int topLeft, int topRight, int bottomLeft,
                      int bottomRight) {
	if (topLeft) { fillFractions(m, c, 0.0, 0.5, 0.0, 0.5); }
	if (topRight) { fillFractions(m, c, 0.5, 1.0, 0.0, 0.5); }
	if (bottomLeft) { fillFractions(m, c, 0.0, 0.5, 0.5, 1.0); }
	if (bottomRight) { fillFractions(m, c, 0.5, 1.0, 0.5, 1.0); }
}

static void drawBlock(int codepoint, const Metrics *m, Canvas *c) {
	const double eighth = 0.125, quarter = 0.25, threeEighths = 0.375, half = 0.5;
	const double fiveEighths = 0.625, threeQuarters = 0.75, sevenEighths = 0.875;
	int cw = (int)m->cellWidth, ch = (int)m->cellHeight;
	switch (codepoint) {
	case 0x2580: blockShade(m, c, ALIGN_LEFT, ALIGN_UPPER, 1.0, half, 255); break;
	case 0x2581: blockShade(m, c, ALIGN_LEFT, ALIGN_LOWER, 1.0, eighth, 255); break;
	case 0x2582: blockShade(m, c, ALIGN_LEFT, ALIGN_LOWER, 1.0, quarter, 255); break;
	case 0x2583: blockShade(m, c, ALIGN_LEFT, ALIGN_LOWER, 1.0, threeEighths, 255); break;
	case 0x2584: blockShade(m, c, ALIGN_LEFT, ALIGN_LOWER, 1.0, half, 255); break;
	case 0x2585: blockShade(m, c, ALIGN_LEFT, ALIGN_LOWER, 1.0, fiveEighths, 255); break;
	case 0x2586: blockShade(m, c, ALIGN_LEFT, ALIGN_LOWER, 1.0, threeQuarters, 255); break;
	case 0x2587: blockShade(m, c, ALIGN_LEFT, ALIGN_LOWER, 1.0, sevenEighths, 255); break;
	case 0x2588: fillBox(c, 0, 0, cw, ch, 255); break;
	case 0x2589: blockShade(m, c, ALIGN_LEFT, ALIGN_UPPER, sevenEighths, 1.0, 255); break;
	case 0x258A: blockShade(m, c, ALIGN_LEFT, ALIGN_UPPER, threeQuarters, 1.0, 255); break;
	case 0x258B: blockShade(m, c, ALIGN_LEFT, ALIGN_UPPER, fiveEighths, 1.0, 255); break;
	case 0x258C: blockShade(m, c, ALIGN_LEFT, ALIGN_UPPER, half, 1.0, 255); break;
	case 0x258D: blockShade(m, c, ALIGN_LEFT, ALIGN_UPPER, threeEighths, 1.0, 255); break;
	case 0x258E: blockShade(m, c, ALIGN_LEFT, ALIGN_UPPER, quarter, 1.0, 255); break;
	case 0x258F: blockShade(m, c, ALIGN_LEFT, ALIGN_UPPER, eighth, 1.0, 255); break;
	case 0x2590: blockShade(m, c, ALIGN_RIGHT, ALIGN_UPPER, half, 1.0, 255); break;
	case 0x2591: fillBox(c, 0, 0, cw, ch, 0x40); break;
	case 0x2592: fillBox(c, 0, 0, cw, ch, 0x80); break;
	case 0x2593: fillBox(c, 0, 0, cw, ch, 0xC0); break;
	case 0x2594: blockShade(m, c, ALIGN_LEFT, ALIGN_UPPER, 1.0, eighth, 255); break;
	case 0x2595: blockShade(m, c, ALIGN_RIGHT, ALIGN_UPPER, eighth, 1.0, 255); break;
	case 0x2596: quadrants(m, c, 0, 0, 1, 0); break;
	case 0x2597: quadrants(m, c, 0, 0, 0, 1); break;
	case 0x2598: quadrants(m, c, 1, 0, 0, 0); break;
	case 0x2599: quadrants(m, c, 1, 0, 1, 1); break;
	case 0x259A: quadrants(m, c, 1, 0, 0, 1); break;
	case 0x259B: quadrants(m, c, 1, 1, 1, 0); break;
	case 0x259C: quadrants(m, c, 1, 1, 0, 1); break;
	case 0x259D: quadrants(m, c, 0, 1, 0, 0); break;
	case 0x259E: quadrants(m, c, 0, 1, 1, 0); break;
	case 0x259F: quadrants(m, c, 0, 1, 1, 1); break;
	default:
		fprintf(stderr, "void2d sprite: U+%04X is in the block range but has no drawing\n",
			codepoint);
		abort();
	}
}

typedef struct {
	double x, y;
} Pt;

typedef struct {
	Pt *p;
	int n, cap;
} Path;

typedef struct {
	uint8_t *px;
	size_t capacity;
} Scratch;

static Path s_flat, s_left, s_right, s_inset, s_poly, s_shifted;
static Scratch s_scratch;
static int s_failed;

static int pathPush(Path *path, double x, double y) {
	if (path->n > 0 && fabs(path->p[path->n - 1].x - x) < 1e-9 &&
		fabs(path->p[path->n - 1].y - y) < 1e-9) {
		return 1;
	}
	if (path->n == path->cap) {
		int grown = path->cap ? path->cap * 2 : 64;
		Pt *p = (Pt *)realloc(path->p, sizeof(Pt) * (size_t)grown);
		if (!p) {
			s_failed = VOID2D_SPRITE_NO_MEMORY;
			return 0;
		}
		path->p = p;
		path->cap = grown;
	}
	path->p[path->n].x = x;
	path->p[path->n].y = y;
	path->n++;
	return 1;
}

static double distance(Pt a, Pt b) {
	return sqrt((b.x - a.x) * (b.x - a.x) + (b.y - a.y) * (b.y - a.y));
}

static void pathCubic(Path *path, Pt p0, Pt p1, Pt p2, Pt p3) {
	double length = distance(p0, p1) + distance(p1, p2) + distance(p2, p3);
	int steps = (int)ceil(length * 1.5);
	if (steps < 8) { steps = 8; }
	if (steps > 256) { steps = 256; }
	for (int i = 1; i <= steps; i++) {
		double t = (double)i / (double)steps, u = 1.0 - t;
		double a = u * u * u, b = 3.0 * u * u * t, c = 3.0 * u * t * t, d = t * t * t;
		pathPush(path, a * p0.x + b * p1.x + c * p2.x + d * p3.x,
			a * p0.y + b * p1.y + c * p2.y + d * p3.y);
	}
}

static void fillContours(Canvas *canvas, const Pt *pts, const int *counts, int contours,
                         uint8_t color) {
	int total = 0;
	for (int i = 0; i < contours; i++) { total += counts[i]; }
	if (total > s_shifted.cap) {
		Pt *grown = (Pt *)realloc(s_shifted.p, sizeof(Pt) * (size_t)total);
		if (!grown) {
			s_failed = VOID2D_SPRITE_NO_MEMORY;
			return;
		}
		s_shifted.p = grown;
		s_shifted.cap = total;
	}
	for (int i = 0; i < total; i++) {
		s_shifted.p[i].x = pts[i].x + canvas->padX;
		s_shifted.p[i].y = pts[i].y + canvas->padY;
	}
	size_t need = (size_t)canvas->width * (size_t)canvas->height;
	if (need > s_scratch.capacity) {
		uint8_t *grown = (uint8_t *)realloc(s_scratch.px, need);
		if (!grown) {
			s_failed = VOID2D_SPRITE_NO_MEMORY;
			return;
		}
		s_scratch.px = grown;
		s_scratch.capacity = need;
	}
	memset(s_scratch.px, 0, need);
	int status = void2dGlyphPolygonCoverage(s_scratch.px, canvas->width, canvas->height,
		(const double *)s_shifted.p, counts, contours);
	if (status != 0) {
		s_failed = status == VOID2D_POLYGON_NO_MEMORY ? VOID2D_SPRITE_NO_MEMORY
		                                              : VOID2D_SPRITE_GEOMETRY;
		return;
	}
	for (size_t i = 0; i < need; i++) {
		if (s_scratch.px[i] == 0) { continue; }
		double coverage = (double)s_scratch.px[i] / 255.0;
		double base = (double)canvas->px[i];
		canvas->px[i] = (uint8_t)floor(base + ((double)color - base) * coverage + 0.5);
	}
}

static void fillPolygon(Canvas *canvas, const Pt *pts, int n, uint8_t color) {
	fillContours(canvas, pts, &n, 1, color);
}

static void fillTriangle(Canvas *canvas, Pt a, Pt b, Pt c) {
	Pt pts[3] = { a, b, c };
	fillPolygon(canvas, pts, 3, 255);
}

static void offsetSide(const Path *path, double offset, Path *out) {
	out->n = 0;
	Pt *p = path->p;
	int n = path->n;
	if (n < 2) { return; }
	Pt unit[2];
	for (int i = 0; i < n; i++) {
		int hasBefore = i > 0, hasAfter = i + 1 < n;
		Pt before = { 0.0, 0.0 }, after = { 0.0, 0.0 };
		if (hasBefore) {
			double len = distance(p[i - 1], p[i]);
			before.x = (p[i].x - p[i - 1].x) / len;
			before.y = (p[i].y - p[i - 1].y) / len;
		}
		if (hasAfter) {
			double len = distance(p[i], p[i + 1]);
			after.x = (p[i + 1].x - p[i].x) / len;
			after.y = (p[i + 1].y - p[i].y) / len;
		}
		unit[0] = hasBefore ? before : after;
		unit[1] = hasAfter ? after : before;
		Pt n0 = { -unit[0].y, unit[0].x }, n1 = { -unit[1].y, unit[1].x };
		if (!hasBefore || !hasAfter) {
			Pt edge = hasBefore ? n0 : n1;
			pathPush(out, p[i].x + edge.x * offset, p[i].y + edge.y * offset);
			continue;
		}
		double dot = before.x * after.x + before.y * after.y;
		double cross = before.x * after.y - before.y * after.x;
		double along = 1.0 + dot;
		int outer = cross * offset < 0.0;
		if (outer && (along < 0.02 || sqrt(2.0 / along) > 10.0)) {
			pathPush(out, p[i].x + n0.x * offset, p[i].y + n0.y * offset);
			pathPush(out, p[i].x + n1.x * offset, p[i].y + n1.y * offset);
		} else if (along < 1e-9) {
			pathPush(out, p[i].x + n0.x * offset, p[i].y + n0.y * offset);
		} else {
			pathPush(out, p[i].x + (n0.x + n1.x) * offset / along,
				p[i].y + (n0.y + n1.y) * offset / along);
		}
	}
}

static void strokePath(Canvas *canvas, const Path *path, double width, uint8_t color) {
	offsetSide(path, width / 2.0, &s_left);
	offsetSide(path, -width / 2.0, &s_right);
	s_poly.n = 0;
	for (int i = 0; i < s_left.n; i++) { pathPush(&s_poly, s_left.p[i].x, s_left.p[i].y); }
	for (int i = s_right.n - 1; i >= 0; i--) { pathPush(&s_poly, s_right.p[i].x, s_right.p[i].y); }
	if (s_poly.n >= 3) { fillPolygon(canvas, s_poly.p, s_poly.n, color); }
}

static void strokeLine(Canvas *canvas, Pt a, Pt b, double width) {
	s_flat.n = 0;
	pathPush(&s_flat, a.x, a.y);
	pathPush(&s_flat, b.x, b.y);
	strokePath(canvas, &s_flat, width, 255);
}

static void insetTriangleRing(Canvas *canvas, Pt a, Pt b, Pt c, double thickness) {
	double la = distance(b, c), lb = distance(a, c), lc = distance(a, b);
	double perimeter = la + lb + lc;
	double area = fabs((b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)) / 2.0;
	double inradius = 2.0 * area / perimeter;
	Pt incenter = { (la * a.x + lb * b.x + lc * c.x) / perimeter,
		(la * a.y + lb * b.y + lc * c.y) / perimeter };
	double k = inradius > thickness ? (inradius - thickness) / inradius : 0.0;
	Pt outer[3] = { a, b, c };
	Pt inner[3];
	Pt corners[3] = { a, b, c };
	for (int i = 0; i < 3; i++) {
		inner[i].x = incenter.x + k * (corners[i].x - incenter.x);
		inner[i].y = incenter.y + k * (corners[i].y - incenter.y);
	}
	Pt ring[6] = { outer[0], outer[1], outer[2], inner[2], inner[1], inner[0] };
	int counts[2] = { 3, 3 };
	fillContours(canvas, ring, counts, 2, 255);
}

static void flipHorizontal(Canvas *canvas) {
	for (int y = 0; y < canvas->height; y++) {
		uint8_t *row = canvas->px + (size_t)y * (size_t)canvas->width;
		for (int x = 0; x < canvas->width / 2; x++) {
			uint8_t t = row[x];
			row[x] = row[canvas->width - 1 - x];
			row[canvas->width - 1 - x] = t;
		}
	}
}

static double minDouble(double a, double b) { return a < b ? a : b; }

static void diagonalUpperRightToLowerLeft(const Metrics *m, Canvas *c) {
	double w = (double)m->cellWidth, h = (double)m->cellHeight;
	double slopeX = minDouble(1.0, w / h), slopeY = minDouble(1.0, h / w);
	Pt a = { w + 0.5 * slopeX, -0.5 * slopeY }, b = { -0.5 * slopeX, h + 0.5 * slopeY };
	strokeLine(c, a, b, (double)m->boxThickness);
}

static void diagonalUpperLeftToLowerRight(const Metrics *m, Canvas *c) {
	double w = (double)m->cellWidth, h = (double)m->cellHeight;
	double slopeX = minDouble(1.0, w / h), slopeY = minDouble(1.0, h / w);
	Pt a = { -0.5 * slopeX, -0.5 * slopeY }, b = { w + 0.5 * slopeX, h + 0.5 * slopeY };
	strokeLine(c, a, b, (double)m->boxThickness);
}

enum { CORNER_TL, CORNER_TR, CORNER_BL, CORNER_BR };

static void cornerPoints(const Metrics *m, int corner, Pt *out) {
	double w = (double)m->cellWidth, h = (double)m->cellHeight;
	Pt tl[3] = { { 0, 0 }, { 0, h }, { w, 0 } };
	Pt tr[3] = { { 0, 0 }, { w, h }, { w, 0 } };
	Pt bl[3] = { { 0, 0 }, { 0, h }, { w, h } };
	Pt br[3] = { { 0, h }, { w, h }, { w, 0 } };
	const Pt *from = corner == CORNER_TL ? tl : corner == CORNER_TR ? tr
		: corner == CORNER_BL ? bl : br;
	for (int i = 0; i < 3; i++) { out[i] = from[i]; }
}

static void cornerTriangle(const Metrics *m, Canvas *c, int corner) {
	Pt t[3];
	cornerPoints(m, corner, t);
	fillTriangle(c, t[0], t[1], t[2]);
}

static void cornerTriangleOutline(const Metrics *m, Canvas *c, int corner) {
	Pt t[3];
	cornerPoints(m, corner, t);
	insetTriangleRing(c, t[0], t[1], t[2], (double)m->boxThickness);
}

enum { ARC_TL, ARC_TR, ARC_BL, ARC_BR };

static void drawArc(const Metrics *m, Canvas *c, int corner) {
	double w = (double)m->cellWidth, h = (double)m->cellHeight, t = (double)m->boxThickness;
	double centerX = (double)(subSat(m->cellWidth, m->boxThickness) / 2) + t / 2.0;
	double centerY = (double)(subSat(m->cellHeight, m->boxThickness) / 2) + t / 2.0;
	double r = minDouble(w, h) / 2.0, s = 0.25;
	double signX = (corner == ARC_TL || corner == ARC_BL) ? -1.0 : 1.0;
	double signY = (corner == ARC_TL || corner == ARC_TR) ? -1.0 : 1.0;
	double startY = signY < 0.0 ? 0.0 : h;
	double endX = signX < 0.0 ? 0.0 : w;
	s_flat.n = 0;
	pathPush(&s_flat, centerX, startY);
	Pt p0 = { centerX, centerY + signY * r };
	pathPush(&s_flat, p0.x, p0.y);
	Pt p1 = { centerX, centerY + signY * s * r };
	Pt p2 = { centerX + signX * s * r, centerY };
	Pt p3 = { centerX + signX * r, centerY };
	pathCubic(&s_flat, p0, p1, p2, p3);
	if ((endX - p3.x) * signX > 0.0) { pathPush(&s_flat, endX, centerY); }
	strokePath(c, &s_flat, t, 255);
}

static void powerlineRound(const Metrics *m, Canvas *c, int stroked) {
	double w = (double)m->cellWidth, h = (double)m->cellHeight;
	double k = (1.4142135623730951 - 1.0) * 4.0 / 3.0;
	double r = minDouble(w, h / 2.0);
	s_flat.n = 0;
	pathPush(&s_flat, 0.0, 0.0);
	if (stroked) { pathPush(&s_flat, 1.0, 0.0); }
	Pt a0 = { stroked ? 1.0 : 0.0, 0.0 };
	pathCubic(&s_flat, a0, (Pt){ r * k, 0.0 }, (Pt){ r, r - r * k }, (Pt){ r, r });
	pathPush(&s_flat, r, h - r);
	Pt b0 = { r, h - r };
	Pt b3 = { stroked ? 1.0 : 0.0, h };
	pathCubic(&s_flat, b0, (Pt){ r, h - r + r * k }, (Pt){ r * k, h }, b3);
	if (stroked) { pathPush(&s_flat, 0.0, h); }
	if (!stroked) {
		fillPolygon(c, s_flat.p, s_flat.n, 255);
		return;
	}
	double t = (double)m->boxThickness;
	offsetSide(&s_flat, t / 2.0, &s_inset);
	strokePath(c, &s_inset, t, 255);
}

static void powerlineChevron(const Metrics *m, Canvas *c) {
	double w = (double)m->cellWidth, h = (double)m->cellHeight;
	s_flat.n = 0;
	pathPush(&s_flat, 0.0, 0.0);
	pathPush(&s_flat, w, h / 2.0);
	pathPush(&s_flat, 0.0, h);
	strokePath(c, &s_flat, (double)m->boxThickness, 255);
}

static void powerlineDouble(const Metrics *m, Canvas *c) {
	double w = (double)m->cellWidth, h = (double)m->cellHeight, t = (double)m->boxThickness;
	Pt top[4] = { { 0, 0 }, { w, 0 }, { w / 2.0, h / 2.0 - t / 2.0 }, { 0, h / 2.0 - t / 2.0 } };
	Pt bottom[4] = { { 0, h }, { w, h }, { w / 2.0, h / 2.0 + t / 2.0 }, { 0, h / 2.0 + t / 2.0 } };
	fillPolygon(c, top, 4, 255);
	fillPolygon(c, bottom, 4, 255);
}

static void drawPowerline(int codepoint, const Metrics *m, Canvas *c) {
	double w = (double)m->cellWidth, h = (double)m->cellHeight;
	switch (codepoint) {
	case 0xE0B0: fillTriangle(c, (Pt){ 0, 0 }, (Pt){ w, h / 2.0 }, (Pt){ 0, h }); break;
	case 0xE0B1: powerlineChevron(m, c); break;
	case 0xE0B2: fillTriangle(c, (Pt){ w, 0 }, (Pt){ 0, h / 2.0 }, (Pt){ w, h }); break;
	case 0xE0B3: powerlineChevron(m, c); flipHorizontal(c); break;
	case 0xE0B4: powerlineRound(m, c, 0); break;
	case 0xE0B5: powerlineRound(m, c, 1); break;
	case 0xE0B6: powerlineRound(m, c, 0); flipHorizontal(c); break;
	case 0xE0B7: powerlineRound(m, c, 1); flipHorizontal(c); break;
	case 0xE0B8: fillTriangle(c, (Pt){ 0, 0 }, (Pt){ w, h }, (Pt){ 0, h }); break;
	case 0xE0B9: diagonalUpperLeftToLowerRight(m, c); break;
	case 0xE0BA: fillTriangle(c, (Pt){ w, 0 }, (Pt){ w, h }, (Pt){ 0, h }); break;
	case 0xE0BB: diagonalUpperRightToLowerLeft(m, c); break;
	case 0xE0BC: fillTriangle(c, (Pt){ 0, 0 }, (Pt){ w, 0 }, (Pt){ 0, h }); break;
	case 0xE0BD: diagonalUpperRightToLowerLeft(m, c); break;
	case 0xE0BE: fillTriangle(c, (Pt){ 0, 0 }, (Pt){ w, 0 }, (Pt){ w, h }); break;
	case 0xE0BF: diagonalUpperLeftToLowerRight(m, c); break;
	case 0xE0D2: powerlineDouble(m, c); break;
	case 0xE0D4: powerlineDouble(m, c); flipHorizontal(c); break;
	default:
		fprintf(stderr, "void2d sprite: U+%04X is in the powerline range but has no drawing\n",
			codepoint);
		abort();
	}
}

static void drawGeometric(int codepoint, const Metrics *m, Canvas *c) {
	switch (codepoint) {
	case 0x25E2: cornerTriangle(m, c, CORNER_BR); break;
	case 0x25E3: cornerTriangle(m, c, CORNER_BL); break;
	case 0x25E4: cornerTriangle(m, c, CORNER_TL); break;
	case 0x25E5: cornerTriangle(m, c, CORNER_TR); break;
	case 0x25F8: cornerTriangleOutline(m, c, CORNER_TL); break;
	case 0x25F9: cornerTriangleOutline(m, c, CORNER_TR); break;
	case 0x25FA: cornerTriangleOutline(m, c, CORNER_BL); break;
	case 0x25FF: cornerTriangleOutline(m, c, CORNER_BR); break;
	default:
		fprintf(stderr, "void2d sprite: U+%04X is in the geometric range but has no drawing\n",
			codepoint);
		abort();
	}
}

static void drawLines(const Metrics *m, Canvas *c, Lines lines) {
	unsigned int lightPx = m->boxThickness;
	unsigned int heavyPx = m->boxThickness * 2;
	unsigned int hLightTop = subSat(m->cellHeight, lightPx) / 2;
	unsigned int hLightBottom = hLightTop + lightPx;
	unsigned int hHeavyTop = subSat(m->cellHeight, heavyPx) / 2;
	unsigned int hHeavyBottom = hHeavyTop + heavyPx;
	unsigned int hDoubleTop = subSat(hLightTop, lightPx);
	unsigned int hDoubleBottom = hLightBottom + lightPx;
	unsigned int vLightLeft = subSat(m->cellWidth, lightPx) / 2;
	unsigned int vLightRight = vLightLeft + lightPx;
	unsigned int vHeavyLeft = subSat(m->cellWidth, heavyPx) / 2;
	unsigned int vHeavyRight = vHeavyLeft + heavyPx;
	unsigned int vDoubleLeft = subSat(vLightLeft, lightPx);
	unsigned int vDoubleRight = vLightRight + lightPx;
	int cw = (int)m->cellWidth, ch = (int)m->cellHeight;

	unsigned int upBottom;
	if (lines.left == LINE_HEAVY || lines.right == LINE_HEAVY) {
		upBottom = hHeavyBottom;
	} else if (lines.left != lines.right || lines.down == lines.up) {
		upBottom = (lines.left == LINE_DOUBLE || lines.right == LINE_DOUBLE) ? hDoubleBottom
			: hLightBottom;
	} else if (lines.left == LINE_NONE && lines.right == LINE_NONE) {
		upBottom = hLightBottom;
	} else {
		upBottom = hLightTop;
	}

	unsigned int downTop;
	if (lines.left == LINE_HEAVY || lines.right == LINE_HEAVY) {
		downTop = hHeavyTop;
	} else if (lines.left != lines.right || lines.up == lines.down) {
		downTop = (lines.left == LINE_DOUBLE || lines.right == LINE_DOUBLE) ? hDoubleTop
			: hLightTop;
	} else if (lines.left == LINE_NONE && lines.right == LINE_NONE) {
		downTop = hLightTop;
	} else {
		downTop = hLightBottom;
	}

	unsigned int leftRight;
	if (lines.up == LINE_HEAVY || lines.down == LINE_HEAVY) {
		leftRight = vHeavyRight;
	} else if (lines.up != lines.down || lines.left == lines.right) {
		leftRight = (lines.up == LINE_DOUBLE || lines.down == LINE_DOUBLE) ? vDoubleRight
			: vLightRight;
	} else if (lines.up == LINE_NONE && lines.down == LINE_NONE) {
		leftRight = vLightRight;
	} else {
		leftRight = vLightLeft;
	}

	unsigned int rightLeft;
	if (lines.up == LINE_HEAVY || lines.down == LINE_HEAVY) {
		rightLeft = vHeavyLeft;
	} else if (lines.up != lines.down || lines.right == lines.left) {
		rightLeft = (lines.up == LINE_DOUBLE || lines.down == LINE_DOUBLE) ? vDoubleLeft
			: vLightLeft;
	} else if (lines.up == LINE_NONE && lines.down == LINE_NONE) {
		rightLeft = vLightLeft;
	} else {
		rightLeft = vLightRight;
	}

	if (lines.up == LINE_LIGHT) {
		fillBox(c, (int)vLightLeft, 0, (int)vLightRight, (int)upBottom, 255);
	} else if (lines.up == LINE_HEAVY) {
		fillBox(c, (int)vHeavyLeft, 0, (int)vHeavyRight, (int)upBottom, 255);
	} else if (lines.up == LINE_DOUBLE) {
		unsigned int leftBottom = lines.left == LINE_DOUBLE ? hLightTop : upBottom;
		unsigned int rightBottom = lines.right == LINE_DOUBLE ? hLightTop : upBottom;
		fillBox(c, (int)vDoubleLeft, 0, (int)vLightLeft, (int)leftBottom, 255);
		fillBox(c, (int)vLightRight, 0, (int)vDoubleRight, (int)rightBottom, 255);
	}

	if (lines.right == LINE_LIGHT) {
		fillBox(c, (int)rightLeft, (int)hLightTop, cw, (int)hLightBottom, 255);
	} else if (lines.right == LINE_HEAVY) {
		fillBox(c, (int)rightLeft, (int)hHeavyTop, cw, (int)hHeavyBottom, 255);
	} else if (lines.right == LINE_DOUBLE) {
		unsigned int topLeft = lines.up == LINE_DOUBLE ? vLightRight : rightLeft;
		unsigned int bottomLeft = lines.down == LINE_DOUBLE ? vLightRight : rightLeft;
		fillBox(c, (int)topLeft, (int)hDoubleTop, cw, (int)hLightTop, 255);
		fillBox(c, (int)bottomLeft, (int)hLightBottom, cw, (int)hDoubleBottom, 255);
	}

	if (lines.down == LINE_LIGHT) {
		fillBox(c, (int)vLightLeft, (int)downTop, (int)vLightRight, ch, 255);
	} else if (lines.down == LINE_HEAVY) {
		fillBox(c, (int)vHeavyLeft, (int)downTop, (int)vHeavyRight, ch, 255);
	} else if (lines.down == LINE_DOUBLE) {
		unsigned int leftTop = lines.left == LINE_DOUBLE ? hLightBottom : downTop;
		unsigned int rightTop = lines.right == LINE_DOUBLE ? hLightBottom : downTop;
		fillBox(c, (int)vDoubleLeft, (int)leftTop, (int)vLightLeft, ch, 255);
		fillBox(c, (int)vLightRight, (int)rightTop, (int)vDoubleRight, ch, 255);
	}

	if (lines.left == LINE_LIGHT) {
		fillBox(c, 0, (int)hLightTop, (int)leftRight, (int)hLightBottom, 255);
	} else if (lines.left == LINE_HEAVY) {
		fillBox(c, 0, (int)hHeavyTop, (int)leftRight, (int)hHeavyBottom, 255);
	} else if (lines.left == LINE_DOUBLE) {
		unsigned int topRight = lines.up == LINE_DOUBLE ? vLightLeft : leftRight;
		unsigned int bottomRight = lines.down == LINE_DOUBLE ? vLightLeft : leftRight;
		fillBox(c, 0, (int)hDoubleTop, (int)topRight, (int)hLightTop, 255);
		fillBox(c, 0, (int)hLightBottom, (int)bottomRight, (int)hDoubleBottom, 255);
	}
}

static void drawDashHorizontal(const Metrics *m, Canvas *c, int count, unsigned int thickPx,
                               unsigned int desiredGap) {
	int gapCount = count;
	if (m->cellWidth < (unsigned int)(count + gapCount)) {
		unsigned int y = subSat(m->cellHeight, m->boxThickness) / 2;
		fillBox(c, 0, (int)y, (int)m->cellWidth, (int)(y + m->boxThickness), 255);
		return;
	}
	unsigned int cap = m->cellWidth / (unsigned int)(2 * count);
	int gapWidth = (int)(desiredGap < cap ? desiredGap : cap);
	int totalDash = (int)m->cellWidth - gapCount * gapWidth;
	int dashWidth = totalDash / count;
	int extra = totalDash % count;
	int y = (int)(subSat(m->cellHeight, thickPx) / 2);
	int x = gapWidth / 2;
	for (int i = 0; i < count; i++) {
		int x1 = x + dashWidth;
		if (extra > 0) {
			extra--;
			x1++;
		}
		fillBox(c, x, y, x1, y + (int)thickPx, 255);
		x = x1 + gapWidth;
	}
}

static void drawDashVertical(const Metrics *m, Canvas *c, int count, unsigned int thickPx,
                             unsigned int desiredGap) {
	int gapCount = count;
	if (m->cellHeight < (unsigned int)(count + gapCount)) {
		unsigned int x = subSat(m->cellWidth, m->boxThickness) / 2;
		fillBox(c, (int)x, 0, (int)(x + m->boxThickness), (int)m->cellHeight, 255);
		return;
	}
	unsigned int cap = m->cellHeight / (unsigned int)(2 * count);
	int gapHeight = (int)(desiredGap < cap ? desiredGap : cap);
	int totalDash = (int)m->cellHeight - gapCount * gapHeight;
	int dashHeight = totalDash / count;
	int extra = totalDash % count;
	int x = (int)(subSat(m->cellWidth, thickPx) / 2);
	int y = 0;
	for (int i = 0; i < count; i++) {
		int y1 = y + dashHeight;
		if (extra > 0) {
			extra--;
			y1++;
		}
		fillBox(c, x, y, x + (int)thickPx, y1, 255);
		y = y1 + gapHeight;
	}
}

static int drawDash(int codepoint, const Metrics *m, Canvas *c) {
	unsigned int light = m->boxThickness;
	unsigned int heavy = m->boxThickness * 2;
	unsigned int wide = light > 4 ? light : 4;
	switch (codepoint) {
	case 0x2504: drawDashHorizontal(m, c, 3, light, wide); return 1;
	case 0x2505: drawDashHorizontal(m, c, 3, heavy, wide); return 1;
	case 0x2506: drawDashVertical(m, c, 3, light, wide); return 1;
	case 0x2507: drawDashVertical(m, c, 3, heavy, wide); return 1;
	case 0x2508: drawDashHorizontal(m, c, 4, light, wide); return 1;
	case 0x2509: drawDashHorizontal(m, c, 4, heavy, wide); return 1;
	case 0x250A: drawDashVertical(m, c, 4, light, wide); return 1;
	case 0x250B: drawDashVertical(m, c, 4, heavy, wide); return 1;
	case 0x254C: drawDashHorizontal(m, c, 2, light, light); return 1;
	case 0x254D: drawDashHorizontal(m, c, 2, heavy, heavy); return 1;
	case 0x254E: drawDashVertical(m, c, 2, light, heavy); return 1;
	case 0x254F: drawDashVertical(m, c, 2, heavy, heavy); return 1;
	default: return 0;
	}
}

static int drawCurved(int codepoint, const Metrics *m, Canvas *c) {
	switch (codepoint) {
	case 0x256D: drawArc(m, c, ARC_BR); return 1;
	case 0x256E: drawArc(m, c, ARC_BL); return 1;
	case 0x256F: drawArc(m, c, ARC_TL); return 1;
	case 0x2570: drawArc(m, c, ARC_TR); return 1;
	case 0x2571: diagonalUpperRightToLowerLeft(m, c); return 1;
	case 0x2572: diagonalUpperLeftToLowerRight(m, c); return 1;
	case 0x2573:
		diagonalUpperRightToLowerLeft(m, c);
		diagonalUpperLeftToLowerRight(m, c);
		return 1;
	default: return 0;
	}
}

static void drawBox(int codepoint, const Metrics *m, Canvas *c) {
	if (drawDash(codepoint, m, c) || drawCurved(codepoint, m, c)) { return; }
	Lines lines = s_boxLines[codepoint - 0x2500];
	if (lines.up == 0 && lines.right == 0 && lines.down == 0 && lines.left == 0) {
		fprintf(stderr, "void2d sprite: U+%04X is in the box range but has no drawing\n",
			codepoint);
		abort();
	}
	drawLines(m, c, lines);
}

static int drawBraille(int codepoint, const Metrics *m, Canvas *c) {
	int width = (int)m->cellWidth, height = (int)m->cellHeight;
	int quarterWidth = width / 4, eighthHeight = height / 8;
	int w = quarterWidth < eighthHeight ? quarterWidth : eighthHeight;
	int xSpacing = quarterWidth;
	int ySpacing = eighthHeight;
	int xMargin = xSpacing / 2;
	int yMargin = ySpacing / 2;
	int xLeft = width - 2 * xMargin - xSpacing - 2 * w;
	int yLeft = height - 2 * yMargin - 3 * ySpacing - 4 * w;
	if (xLeft >= 2 && yLeft >= 4 && w == 0) {
		w += 1;
		xLeft -= 2;
		yLeft -= 4;
	}
	if (xLeft >= 2 && xMargin == 0) {
		xMargin = 1;
		xLeft -= 2;
	}
	if (yLeft >= 2 && yMargin == 0) {
		yMargin = 1;
		yLeft -= 2;
	}
	if (xLeft >= 1) {
		xSpacing += 1;
		xLeft -= 1;
	}
	if (yLeft >= 3) {
		ySpacing += 1;
		yLeft -= 3;
	}
	if (xLeft >= 2) {
		xMargin += 1;
		xLeft -= 2;
	}
	if (yLeft >= 2) {
		yMargin += 1;
		yLeft -= 2;
	}
	if (xLeft >= 2 && yLeft >= 4) {
		w += 1;
		xLeft -= 2;
		yLeft -= 4;
	}
	if (!(xLeft <= 1 || yLeft <= 1) || 2 * xMargin + 2 * w + xSpacing > width ||
		2 * yMargin + 4 * w + 3 * ySpacing > height) {
		return VOID2D_SPRITE_GEOMETRY;
	}
	int x[2] = { xMargin, xMargin + w + xSpacing };
	int y[4];
	y[0] = yMargin;
	y[1] = y[0] + w + ySpacing;
	y[2] = y[1] + w + ySpacing;
	y[3] = y[2] + w + ySpacing;
	int pattern = codepoint & 0xFF;
	int column[8] = { 0, 0, 0, 1, 1, 1, 0, 1 };
	int row[8] = { 0, 1, 2, 0, 1, 2, 3, 3 };
	for (int bit = 0; bit < 8; bit++) {
		if ((pattern >> bit) & 1) {
			int cx = x[column[bit]], cy = y[row[bit]];
			fillBox(c, cx, cy, cx + w, cy + w, 255);
		}
	}
	return VOID2D_SPRITE_OK;
}


static void drawSextant(int codepoint, const Metrics *m, Canvas *c) {
	int index = codepoint - 0x1FB00;
	int bits = index + index / 0x14 + 1;
	const double third = 1.0 / 3.0, twoThirds = 2.0 / 3.0;
	if (bits & 1) { fillFractions(m, c, 0.0, 0.5, 0.0, third); }
	if (bits & 2) { fillFractions(m, c, 0.5, 1.0, 0.0, third); }
	if (bits & 4) { fillFractions(m, c, 0.0, 0.5, third, twoThirds); }
	if (bits & 8) { fillFractions(m, c, 0.5, 1.0, third, twoThirds); }
	if (bits & 16) { fillFractions(m, c, 0.0, 0.5, twoThirds, 1.0); }
	if (bits & 32) { fillFractions(m, c, 0.5, 1.0, twoThirds, 1.0); }
}

static void drawOctant(int codepoint, const Metrics *m, Canvas *c) {
	int bits = s_octants[codepoint - 0x1CD00];
	for (int bit = 0; bit < 8; bit++) {
		if (!((bits >> bit) & 1)) { continue; }
		double left = (bit & 1) ? 0.5 : 0.0, right = (bit & 1) ? 1.0 : 0.5;
		double top = (double)(bit >> 1) * 0.25;
		fillFractions(m, c, left, right, top, top + 0.25);
	}
}

static void checkerboard(const Metrics *m, Canvas *c, unsigned int parity) {
	unsigned int xSize = 4;
	unsigned int ySize = (unsigned int)round(4.0 * ((double)m->cellHeight / (double)m->cellWidth));
	for (unsigned int x = 0; x < xSize; x++) {
		unsigned int x0 = (m->cellWidth * x) / xSize, x1 = (m->cellWidth * (x + 1)) / xSize;
		for (unsigned int y = 0; y < ySize; y++) {
			unsigned int y0 = (m->cellHeight * y) / ySize;
			unsigned int y1 = (m->cellHeight * (y + 1)) / ySize;
			if ((x + y) % 2 == parity) { fillBox(c, (int)x0, (int)y0, (int)x1, (int)y1, 255); }
		}
	}
}

static void drawLegacyBlock(int codepoint, const Metrics *m, Canvas *c) {
	const double eighth = 0.125, quarter = 0.25, threeEighths = 0.375, half = 0.5;
	const double fiveEighths = 0.625, threeQuarters = 0.75, sevenEighths = 0.875;
	int cw = (int)m->cellWidth, ch = (int)m->cellHeight;
	if (codepoint >= 0x1FB70 && codepoint <= 0x1FB75) {
		double n = (double)(codepoint + 1 - 0x1FB70);
		fillFractions(m, c, n / 8.0, (n + 1.0) / 8.0, 0.0, 1.0);
		return;
	}
	if (codepoint >= 0x1FB76 && codepoint <= 0x1FB7B) {
		double n = (double)(codepoint + 1 - 0x1FB76);
		fillFractions(m, c, 0.0, 1.0, n / 8.0, (n + 1.0) / 8.0);
		return;
	}
	switch (codepoint) {
	case 0x1FB7C:
		blockShade(m, c, ALIGN_LEFT, ALIGN_UPPER, eighth, 1.0, 255);
		blockShade(m, c, ALIGN_LEFT, ALIGN_LOWER, 1.0, eighth, 255);
		break;
	case 0x1FB7D:
		blockShade(m, c, ALIGN_LEFT, ALIGN_UPPER, eighth, 1.0, 255);
		blockShade(m, c, ALIGN_LEFT, ALIGN_UPPER, 1.0, eighth, 255);
		break;
	case 0x1FB7E:
		blockShade(m, c, ALIGN_RIGHT, ALIGN_UPPER, eighth, 1.0, 255);
		blockShade(m, c, ALIGN_LEFT, ALIGN_UPPER, 1.0, eighth, 255);
		break;
	case 0x1FB7F:
		blockShade(m, c, ALIGN_RIGHT, ALIGN_UPPER, eighth, 1.0, 255);
		blockShade(m, c, ALIGN_LEFT, ALIGN_LOWER, 1.0, eighth, 255);
		break;
	case 0x1FB80:
		blockShade(m, c, ALIGN_LEFT, ALIGN_UPPER, 1.0, eighth, 255);
		blockShade(m, c, ALIGN_LEFT, ALIGN_LOWER, 1.0, eighth, 255);
		break;
	case 0x1FB81:
		fillFractions(m, c, 0.0, 1.0, 0.0, eighth);
		fillFractions(m, c, 0.0, 1.0, 2.0 / 8.0, 3.0 / 8.0);
		fillFractions(m, c, 0.0, 1.0, 4.0 / 8.0, 5.0 / 8.0);
		fillFractions(m, c, 0.0, 1.0, 7.0 / 8.0, 1.0);
		break;
	case 0x1FB82: blockShade(m, c, ALIGN_LEFT, ALIGN_UPPER, 1.0, quarter, 255); break;
	case 0x1FB83: blockShade(m, c, ALIGN_LEFT, ALIGN_UPPER, 1.0, threeEighths, 255); break;
	case 0x1FB84: blockShade(m, c, ALIGN_LEFT, ALIGN_UPPER, 1.0, fiveEighths, 255); break;
	case 0x1FB85: blockShade(m, c, ALIGN_LEFT, ALIGN_UPPER, 1.0, threeQuarters, 255); break;
	case 0x1FB86: blockShade(m, c, ALIGN_LEFT, ALIGN_UPPER, 1.0, sevenEighths, 255); break;
	case 0x1FB87: blockShade(m, c, ALIGN_RIGHT, ALIGN_UPPER, quarter, 1.0, 255); break;
	case 0x1FB88: blockShade(m, c, ALIGN_RIGHT, ALIGN_UPPER, threeEighths, 1.0, 255); break;
	case 0x1FB89: blockShade(m, c, ALIGN_RIGHT, ALIGN_UPPER, fiveEighths, 1.0, 255); break;
	case 0x1FB8A: blockShade(m, c, ALIGN_RIGHT, ALIGN_UPPER, threeQuarters, 1.0, 255); break;
	case 0x1FB8B: blockShade(m, c, ALIGN_RIGHT, ALIGN_UPPER, sevenEighths, 1.0, 255); break;
	case 0x1FB8C: blockShade(m, c, ALIGN_LEFT, ALIGN_UPPER, half, 1.0, 0x80); break;
	case 0x1FB8D: blockShade(m, c, ALIGN_RIGHT, ALIGN_UPPER, half, 1.0, 0x80); break;
	case 0x1FB8E: blockShade(m, c, ALIGN_LEFT, ALIGN_UPPER, 1.0, half, 0x80); break;
	case 0x1FB8F: blockShade(m, c, ALIGN_LEFT, ALIGN_LOWER, 1.0, half, 0x80); break;
	case 0x1FB90: fillBox(c, 0, 0, cw, ch, 0x80); break;
	case 0x1FB91:
		fillBox(c, 0, 0, cw, ch, 0x80);
		blockShade(m, c, ALIGN_LEFT, ALIGN_UPPER, 1.0, half, 255);
		break;
	case 0x1FB92:
		fillBox(c, 0, 0, cw, ch, 0x80);
		blockShade(m, c, ALIGN_LEFT, ALIGN_LOWER, 1.0, half, 255);
		break;
	case 0x1FB94:
		fillBox(c, 0, 0, cw, ch, 0x80);
		blockShade(m, c, ALIGN_RIGHT, ALIGN_UPPER, half, 1.0, 255);
		break;
	case 0x1FB95: checkerboard(m, c, 0); break;
	case 0x1FB96: checkerboard(m, c, 1); break;
	case 0x1FB97:
		fillBox(c, 0, ch / 4, cw, 2 * ch / 4, 255);
		fillBox(c, 0, 3 * ch / 4, cw, ch, 255);
		break;
	default:
		fprintf(stderr, "void2d sprite: U+%04X is in the legacy block range but has no drawing\n",
			codepoint);
		abort();
	}
}

int void2dSpriteDraw(int id, int cellWidth, int cellHeight, int thickness, uint8_t *canvas,
                     int64_t count) {
	int codepoint = void2dSpriteCodepoint(id);
	if (codepoint == 0) { return VOID2D_SPRITE_NO_SUCH_ID; }
	if (cellWidth < 1 || cellHeight < 1 || thickness < 1) { return VOID2D_SPRITE_BAD_CELL; }
	Canvas c;
	c.padX = void2dSpritePadding(cellWidth);
	c.padY = void2dSpritePadding(cellHeight);
	c.width = void2dSpriteCanvasWidth(cellWidth);
	c.height = void2dSpriteCanvasHeight(cellHeight);
	c.px = canvas;
	if (!canvas || count != (int64_t)c.width * (int64_t)c.height) {
		return VOID2D_SPRITE_BAD_BUFFER;
	}
	memset(canvas, 0, (size_t)count);
	Metrics m;
	m.cellWidth = (unsigned int)cellWidth;
	m.cellHeight = (unsigned int)cellHeight;
	m.boxThickness = (unsigned int)thickness;
	int family = s_ranges[rangeOf(codepoint)].family;
	s_failed = VOID2D_SPRITE_OK;
	int status = VOID2D_SPRITE_OK;
	switch (family) {
	case FAMILY_BOX: drawBox(codepoint, &m, &c); break;
	case FAMILY_BLOCK: drawBlock(codepoint, &m, &c); break;
	case FAMILY_BRAILLE: status = drawBraille(codepoint, &m, &c); break;
	case FAMILY_GEOMETRIC: drawGeometric(codepoint, &m, &c); break;
	case FAMILY_POWERLINE: drawPowerline(codepoint, &m, &c); break;
	case FAMILY_OCTANT: drawOctant(codepoint, &m, &c); break;
	case FAMILY_SEXTANT: drawSextant(codepoint, &m, &c); break;
	case FAMILY_LEGACY_BLOCK: drawLegacyBlock(codepoint, &m, &c); break;
	default:
		fprintf(stderr, "void2d sprite: U+%04X belongs to the unknown family %d\n", codepoint,
			family);
		abort();
	}
	return status != VOID2D_SPRITE_OK ? status : s_failed;
}

typedef struct {
	int id;
	int cellWidth;
	int cellHeight;
	int thickness;
	int valid;
	int box[4];
	uint8_t *canvas;
	size_t capacity;
} InkCache;

static InkCache s_ink;

static void measureInk(int canvasWidth, int canvasHeight) {
	int left = canvasWidth, top = canvasHeight, right = 0, bottom = 0;
	for (int y = 0; y < canvasHeight; y++) {
		for (int x = 0; x < canvasWidth; x++) {
			if (s_ink.canvas[(size_t)y * (size_t)canvasWidth + (size_t)x] == 0) { continue; }
			if (x < left) { left = x; }
			if (x + 1 > right) { right = x + 1; }
			if (y < top) { top = y; }
			if (y + 1 > bottom) { bottom = y + 1; }
		}
	}
	if (right <= left || bottom <= top) { left = top = right = bottom = 0; }
	s_ink.box[0] = left;
	s_ink.box[1] = top;
	s_ink.box[2] = right;
	s_ink.box[3] = bottom;
}

int void2dSpriteInk(int id, int cellWidth, int cellHeight, int thickness, int *box,
                    const uint8_t **rows, int *stride) {
	box[0] = box[1] = box[2] = box[3] = 0;
	*rows = NULL;
	*stride = 0;
	if (cellWidth < 1 || cellHeight < 1 || thickness < 1) { return VOID2D_SPRITE_BAD_CELL; }
	int canvasWidth = void2dSpriteCanvasWidth(cellWidth);
	int canvasHeight = void2dSpriteCanvasHeight(cellHeight);
	int64_t count = (int64_t)canvasWidth * (int64_t)canvasHeight;
	if (!(s_ink.valid && s_ink.id == id && s_ink.cellWidth == cellWidth &&
		s_ink.cellHeight == cellHeight && s_ink.thickness == thickness)) {
		s_ink.valid = 0;
		if ((size_t)count > s_ink.capacity) {
			uint8_t *grown = (uint8_t *)realloc(s_ink.canvas, (size_t)count);
			if (!grown) {
				fprintf(stderr, "void2d sprite: no memory for a %dx%d canvas\n", canvasWidth,
					canvasHeight);
				return VOID2D_SPRITE_NO_MEMORY;
			}
			s_ink.canvas = grown;
			s_ink.capacity = (size_t)count;
		}
		int status = void2dSpriteDraw(id, cellWidth, cellHeight, thickness, s_ink.canvas, count);
		if (status != VOID2D_SPRITE_OK) { return status; }
		measureInk(canvasWidth, canvasHeight);
		s_ink.id = id;
		s_ink.cellWidth = cellWidth;
		s_ink.cellHeight = cellHeight;
		s_ink.thickness = thickness;
		s_ink.valid = 1;
	}
	int padX = void2dSpritePadding(cellWidth), padY = void2dSpritePadding(cellHeight);
	if (s_ink.box[2] > s_ink.box[0]) {
		box[0] = s_ink.box[0] - padX;
		box[1] = s_ink.box[1] - padY;
		box[2] = s_ink.box[2] - padX;
		box[3] = s_ink.box[3] - padY;
		*rows = s_ink.canvas + (size_t)s_ink.box[1] * (size_t)canvasWidth + (size_t)s_ink.box[0];
		*stride = canvasWidth;
	}
	return VOID2D_SPRITE_OK;
}
