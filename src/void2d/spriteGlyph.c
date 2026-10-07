#include "spriteGlyph.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

enum { FAMILY_BOX, FAMILY_BLOCK, FAMILY_BRAILLE };

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
	{ 0x2500, 0x256C, FAMILY_BOX, 0 },
	{ 0x2574, 0x257F, FAMILY_BOX, 0x6D },
	{ 0x2580, 0x259F, FAMILY_BLOCK, 0x79 },
	{ 0x2800, 0x28FF, FAMILY_BRAILLE, 0x99 },
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

static void drawBox(int codepoint, const Metrics *m, Canvas *c) {
	if (drawDash(codepoint, m, c)) { return; }
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
	switch (family) {
	case FAMILY_BOX: drawBox(codepoint, &m, &c); return VOID2D_SPRITE_OK;
	case FAMILY_BLOCK: drawBlock(codepoint, &m, &c); return VOID2D_SPRITE_OK;
	case FAMILY_BRAILLE: return drawBraille(codepoint, &m, &c);
	default:
		fprintf(stderr, "void2d sprite: U+%04X belongs to the unknown family %d\n", codepoint,
			family);
		abort();
	}
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
