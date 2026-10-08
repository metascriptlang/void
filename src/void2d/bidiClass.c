#include "bidiClass.h"
#include "bidiTable.h"

#define CLASS_BITS 5
#define CLASS_MASK 31
#define CLASS_L 0

int void2dBidiClass(int codepoint) {
	if (codepoint < 0 || codepoint > 0x10FFFF) { return CLASS_L; }
	int lo = 0;
	int hi = VOID2D_BIDI_CLASS_RANGES - 1;
	while (lo < hi) {
		int mid = (lo + hi + 1) / 2;
		if ((int)(kVoid2dBidiClassRanges[mid] >> CLASS_BITS) <= codepoint) {
			lo = mid;
		} else {
			hi = mid - 1;
		}
	}
	return (int)(kVoid2dBidiClassRanges[lo] & CLASS_MASK);
}

static int pairValue(const uint32_t* pairs, int count, int codepoint) {
	int lo = 0;
	int hi = count - 1;
	while (lo <= hi) {
		int mid = (lo + hi) / 2;
		int key = (int)pairs[mid * 2];
		if (key == codepoint) { return (int)pairs[mid * 2 + 1]; }
		if (key < codepoint) { lo = mid + 1; } else { hi = mid - 1; }
	}
	return 0;
}

int void2dBidiBracket(int codepoint) {
	return pairValue(kVoid2dBidiBrackets, VOID2D_BIDI_BRACKETS, codepoint);
}

int void2dBidiMirror(int codepoint) {
	return pairValue(kVoid2dBidiMirrors, VOID2D_BIDI_MIRRORS, codepoint);
}
