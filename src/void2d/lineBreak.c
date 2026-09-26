#include "lineBreak.h"
#include "lineBreakTable.h"

#define HANGUL_FIRST 0xAC00
#define HANGUL_LAST 0xD7A3
#define HANGUL_T_COUNT 28
#define CLASS_H2 36
#define CLASS_H3 37
#define EAST_ASIAN (1 << 6)

int void2dLineBreakClass(int codepoint) {
	if (codepoint < 0 || codepoint > 0x10FFFF) { return 0; }
	if (codepoint >= HANGUL_FIRST && codepoint <= HANGUL_LAST) {
		int syllable = (codepoint - HANGUL_FIRST) % HANGUL_T_COUNT == 0 ? CLASS_H2 : CLASS_H3;
		return syllable | EAST_ASIAN;
	}
	int lo = 0;
	int hi = VOID2D_LINE_BREAK_RANGES - 1;
	while (lo < hi) {
		int mid = (lo + hi + 1) / 2;
		if ((int)(kVoid2dLineBreakRanges[mid] >> 11) <= codepoint) {
			lo = mid;
		} else {
			hi = mid - 1;
		}
	}
	return (int)(kVoid2dLineBreakRanges[lo] & 0x7FFu);
}
