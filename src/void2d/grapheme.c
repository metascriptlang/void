#include "grapheme.h"
#include "graphemeTable.h"

#define HANGUL_FIRST 0xAC00
#define HANGUL_LAST 0xD7A3
#define HANGUL_T_COUNT 28
#define CLASS_LV 12
#define CLASS_LVT 13

int void2dGraphemeClass(int codepoint) {
	if (codepoint < 0 || codepoint > 0x10FFFF) { return 0; }
	if (codepoint >= 0x20 && codepoint < 0x7F) { return 0; }
	if (codepoint >= HANGUL_FIRST && codepoint <= HANGUL_LAST) {
		return (codepoint - HANGUL_FIRST) % HANGUL_T_COUNT == 0 ? CLASS_LV : CLASS_LVT;
	}
	int lo = 0;
	int hi = VOID2D_GRAPHEME_RANGES - 1;
	while (lo < hi) {
		int mid = (lo + hi + 1) / 2;
		if ((int)(kVoid2dGraphemeRanges[mid] >> 8) <= codepoint) {
			lo = mid;
		} else {
			hi = mid - 1;
		}
	}
	return (int)(kVoid2dGraphemeRanges[lo] & 0xFFu);
}
