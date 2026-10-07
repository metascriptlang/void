#include "sfnt.h"
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>

#define SFNT_MAX_TABLES 512
#define SFNT_MAX_CMAP 0x4000000u

typedef uint64_t Off;

typedef struct {
	unsigned char *cmap;
	Off length;
	Off index;
	Off sequences;
	int flags;
} Summary;

static Summary *s_summaries;
static int s_summaryCount;
static int s_summaryCapacity;
static int s_summariesRead;

static int fits(const Summary *s, Off at, Off n) { return at <= s->length && n <= s->length - at; }

static unsigned readU8(const Summary *s, Off at) { return fits(s, at, 1) ? s->cmap[at] : 0; }

static unsigned readU16(const Summary *s, Off at) {
	if (!fits(s, at, 2)) { return 0; }
	return ((unsigned)s->cmap[at] << 8) | s->cmap[at + 1];
}

static int readI16(const Summary *s, Off at) {
	unsigned v = readU16(s, at);
	return v >= 0x8000u ? (int)v - 0x10000 : (int)v;
}

static uint32_t readU24(const Summary *s, Off at) {
	if (!fits(s, at, 3)) { return 0; }
	return ((uint32_t)s->cmap[at] << 16) | ((uint32_t)s->cmap[at + 1] << 8) | s->cmap[at + 2];
}

static uint32_t readU32(const Summary *s, Off at) {
	if (!fits(s, at, 4)) { return 0; }
	return ((uint32_t)s->cmap[at] << 24) | ((uint32_t)s->cmap[at + 1] << 16) |
		((uint32_t)s->cmap[at + 2] << 8) | s->cmap[at + 3];
}

static uint32_t fileU32(const unsigned char *p) {
	return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3];
}

static int validSummary(int summary) { return summary >= 0 && summary < s_summaryCount; }

static int glyphInFormat4(const Summary *s, Off map, int codepoint) {
	unsigned segcount = readU16(s, map + 6) >> 1;
	unsigned searchRange = readU16(s, map + 8) >> 1;
	unsigned entrySelector = readU16(s, map + 10);
	unsigned rangeShift = readU16(s, map + 12) >> 1;
	Off endCount = map + 14;
	Off search = endCount;
	if (codepoint > 0xffff || !fits(s, map, 16 + (Off)segcount * 8)) { return 0; }
	if ((unsigned)codepoint >= readU16(s, search + (Off)rangeShift * 2)) {
		search += (Off)rangeShift * 2;
	}
	search -= 2;
	while (entrySelector) {
		searchRange >>= 1;
		if ((unsigned)codepoint > readU16(s, search + (Off)searchRange * 2)) {
			search += (Off)searchRange * 2;
		}
		--entrySelector;
	}
	search += 2;
	unsigned item = (unsigned)((search - endCount) >> 1) & 0xffffu;
	if (item >= segcount) { return 0; }
	unsigned start = readU16(s, map + 14 + (Off)segcount * 2 + 2 + 2 * (Off)item);
	unsigned last = readU16(s, endCount + 2 * (Off)item);
	if ((unsigned)codepoint < start || (unsigned)codepoint > last) { return 0; }
	unsigned offset = readU16(s, map + 14 + (Off)segcount * 6 + 2 + 2 * (Off)item);
	if (offset == 0) {
		int delta = readI16(s, map + 14 + (Off)segcount * 4 + 2 + 2 * (Off)item);
		return (int)((unsigned)(codepoint + delta) & 0xffffu);
	}
	return (int)readU16(s, (Off)offset + (Off)(codepoint - (int)start) * 2 + map + 14 +
		(Off)segcount * 6 + 2 + 2 * (Off)item);
}

static int glyphInGroups(const Summary *s, Off map, int codepoint, int sharedGlyph) {
	Off low = 0;
	Off high = readU32(s, map + 12);
	if (!fits(s, map, 16 + high * 12)) { return 0; }
	while (low < high) {
		Off mid = low + ((high - low) >> 1);
		uint32_t startChar = readU32(s, map + 16 + mid * 12);
		uint32_t endChar = readU32(s, map + 16 + mid * 12 + 4);
		if ((uint32_t)codepoint < startChar) {
			high = mid;
		} else if ((uint32_t)codepoint > endChar) {
			low = mid + 1;
		} else {
			uint32_t startGlyph = readU32(s, map + 16 + mid * 12 + 8);
			if (sharedGlyph) { return (int)startGlyph; }
			return (int)(startGlyph + ((uint32_t)codepoint - startChar));
		}
	}
	return 0;
}

static int stbCompatibleGlyph(const Summary *s, int codepoint) {
	Off map = s->index;
	if (map == 0 || codepoint < 0) { return 0; }
	unsigned format = readU16(s, map);
	if (format == 0) {
		int bytes = (int)readU16(s, map + 2);
		if (codepoint < bytes - 6) { return (int)readU8(s, map + 6 + (Off)codepoint); }
		return 0;
	}
	if (format == 6) {
		unsigned first = readU16(s, map + 6);
		unsigned count = readU16(s, map + 8);
		if (!fits(s, map, 10 + (Off)count * 2)) { return 0; }
		if ((unsigned)codepoint >= first && (unsigned)codepoint < first + count) {
			return (int)readU16(s, map + 10 + (Off)((unsigned)codepoint - first) * 2);
		}
		return 0;
	}
	if (format == 4) { return glyphInFormat4(s, map, codepoint); }
	if (format == 12) { return glyphInGroups(s, map, codepoint, 0); }
	if (format == 13) { return glyphInGroups(s, map, codepoint, 1); }
	return 0;
}

static Off chooseIndex(const Summary *s) {
	Off chosen = 0;
	unsigned records = readU16(s, 2);
	for (unsigned i = 0; i < records; i++) {
		Off record = 4 + 8 * (Off)i;
		if (!fits(s, record, 8)) { break; }
		unsigned platform = readU16(s, record);
		unsigned encoding = readU16(s, record + 2);
		Off offset = readU32(s, record + 4);
		if (platform == 3 && (encoding == 1 || encoding == 10)) { chosen = offset; }
		if (platform == 0) { chosen = offset; }
	}
	return fits(s, chosen, 2) ? chosen : 0;
}

static Off chooseSequences(const Summary *s) {
	unsigned records = readU16(s, 2);
	for (unsigned i = 0; i < records; i++) {
		Off record = 4 + 8 * (Off)i;
		if (!fits(s, record, 8)) { break; }
		if (readU16(s, record) == 0 && readU16(s, record + 2) == 5) {
			Off offset = readU32(s, record + 4);
			if (fits(s, offset, 10) && readU16(s, offset) == 14) { return offset; }
		}
	}
	return 0;
}

static int sequenceInDefault(const Summary *s, Off table, int codepoint) {
	Off low = 0;
	Off high = readU32(s, table);
	if (!fits(s, table, 4 + high * 4)) { return 0; }
	while (low < high) {
		Off mid = low + ((high - low) >> 1);
		uint32_t start = readU24(s, table + 4 + mid * 4);
		uint32_t last = start + readU8(s, table + 4 + mid * 4 + 3);
		if ((uint32_t)codepoint < start) {
			high = mid;
		} else if ((uint32_t)codepoint > last) {
			low = mid + 1;
		} else {
			return 1;
		}
	}
	return 0;
}

static int sequenceInSpecific(const Summary *s, Off table, int codepoint) {
	Off low = 0;
	Off high = readU32(s, table);
	if (!fits(s, table, 4 + high * 5)) { return 0; }
	while (low < high) {
		Off mid = low + ((high - low) >> 1);
		uint32_t value = readU24(s, table + 4 + mid * 5);
		if ((uint32_t)codepoint < value) {
			high = mid;
		} else if ((uint32_t)codepoint > value) {
			low = mid + 1;
		} else {
			return readU16(s, table + 4 + mid * 5 + 3) != 0;
		}
	}
	return 0;
}

static unsigned char *readRange(FILE *f, Off at, Off length) {
	unsigned char *buf = (unsigned char *)malloc((size_t)(length > 0 ? length : 1));
	if (!buf) { return NULL; }
	if (fseek(f, (long)at, SEEK_SET) != 0 || fread(buf, 1, (size_t)length, f) != (size_t)length) {
		free(buf);
		return NULL;
	}
	return buf;
}

static int growSummaries(void) {
	if (s_summaryCount < s_summaryCapacity) { return 1; }
	int grown = s_summaryCapacity ? s_summaryCapacity * 2 : 4;
	Summary *next = (Summary *)realloc(s_summaries, sizeof(Summary) * (size_t)grown);
	if (!next) {
		fprintf(stderr, "void2d: no memory for %d font summaries\n", grown);
		return 0;
	}
	s_summaries = next;
	s_summaryCapacity = grown;
	return 1;
}

typedef struct {
	Off offset;
	Off length;
	int found;
} TableSpan;

static TableSpan findTable(const unsigned char *directory, int tables, Off fileSize,
		const char *tag) {
	TableSpan span = { 0, 0, 0 };
	for (int i = 0; i < tables; i++) {
		const unsigned char *record = directory + 16 * i;
		if (memcmp(record, tag, 4) != 0) { continue; }
		Off offset = fileU32(record + 8);
		Off length = fileU32(record + 12);
		if (offset > fileSize || length > fileSize - offset) { continue; }
		span.offset = offset;
		span.length = length;
		span.found = 1;
		return span;
	}
	return span;
}

int void2dSfntPeek(const char *path) {
	FILE *f = fopen(path, "rb");
	if (!f) {
		fprintf(stderr, "void2d: cannot read font file %s\n", path);
		return VOID2D_SFNT_UNREADABLE;
	}
	fseek(f, 0, SEEK_END);
	long measured = ftell(f);
	Off fileSize = measured < 0 ? 0 : (Off)measured;
	unsigned char head[16];
	Off fontStart = 0;
	int status = VOID2D_SFNT_NOT_AN_SFNT;
	int tables = 0;
	unsigned char *directory = NULL;
	unsigned char *cmap = NULL;
	TableSpan cmapSpan, headSpan, hheaSpan, hmtxSpan, glyfSpan, locaSpan, cffSpan;
	Summary summary;
	if (fileSize < 12 || fseek(f, 0, SEEK_SET) != 0 || fread(head, 1, 12, f) != 12) {
		goto done;
	}
	if (memcmp(head, "ttcf", 4) == 0) {
		if (fseek(f, 12, SEEK_SET) != 0 || fread(head, 1, 4, f) != 4) { goto done; }
		fontStart = fileU32(head);
		if (fontStart > fileSize || 12 > fileSize - fontStart ||
			fseek(f, (long)fontStart, SEEK_SET) != 0 || fread(head, 1, 12, f) != 12) {
			goto done;
		}
	}
	if (!(fileU32(head) == 0x00010000ul || memcmp(head, "OTTO", 4) == 0 ||
		memcmp(head, "true", 4) == 0)) {
		goto done;
	}
	tables = (int)(((unsigned)head[4] << 8) | head[5]);
	if (tables == 0 || tables > SFNT_MAX_TABLES) { goto done; }
	if (fontStart + 12 > fileSize || 16 * (Off)tables > fileSize - fontStart - 12) { goto done; }
	directory = readRange(f, fontStart + 12, 16 * (Off)tables);
	if (!directory) { goto done; }
	cmapSpan = findTable(directory, tables, fileSize, "cmap");
	headSpan = findTable(directory, tables, fileSize, "head");
	hheaSpan = findTable(directory, tables, fileSize, "hhea");
	hmtxSpan = findTable(directory, tables, fileSize, "hmtx");
	glyfSpan = findTable(directory, tables, fileSize, "glyf");
	locaSpan = findTable(directory, tables, fileSize, "loca");
	cffSpan = findTable(directory, tables, fileSize, "CFF ");
	if (!cmapSpan.found || cmapSpan.length > SFNT_MAX_CMAP) { goto done; }
	cmap = readRange(f, cmapSpan.offset, cmapSpan.length);
	if (!cmap) { goto done; }
	if (!growSummaries()) {
		status = VOID2D_SFNT_NO_MEMORY;
		goto done;
	}
	summary = (Summary){ cmap, cmapSpan.length, 0, 0, 0 };
	summary.index = chooseIndex(&summary);
	summary.sequences = chooseSequences(&summary);
	if (summary.index != 0 && headSpan.found && hheaSpan.found && hmtxSpan.found &&
		(glyfSpan.found ? locaSpan.found : cffSpan.found)) {
		summary.flags |= VOID2D_SFNT_DRAWABLE;
	}
	if ((findTable(directory, tables, fileSize, "CBDT").found &&
			findTable(directory, tables, fileSize, "CBLC").found) ||
		findTable(directory, tables, fileSize, "sbix").found) {
		summary.flags |= VOID2D_SFNT_COLOUR_BITMAP;
	}
	if (findTable(directory, tables, fileSize, "COLR").found &&
		findTable(directory, tables, fileSize, "CPAL").found) {
		summary.flags |= VOID2D_SFNT_COLOUR_LAYERS;
	}
	s_summaries[s_summaryCount] = summary;
	cmap = NULL;
	s_summariesRead++;
	status = s_summaryCount++;
done:
	free(directory);
	free(cmap);
	fclose(f);
	if (status == VOID2D_SFNT_NOT_AN_SFNT) {
		fprintf(stderr, "void2d: %s is not an sfnt with a cmap table\n", path);
	}
	return status;
}

int void2dSfntCovers(int summary, int codepoint) {
	if (!validSummary(summary)) { return 0; }
	return stbCompatibleGlyph(&s_summaries[summary], codepoint) != 0;
}

int void2dSfntSequence(int summary, int codepoint, int selector) {
	if (!validSummary(summary) || codepoint < 0 || selector < 0) { return VOID2D_SFNT_NO_SEQUENCE; }
	const Summary *s = &s_summaries[summary];
	Off table = s->sequences;
	if (table == 0) { return VOID2D_SFNT_NO_SEQUENCE; }
	Off low = 0;
	Off high = readU32(s, table + 6);
	if (!fits(s, table, 10 + high * 11)) { return VOID2D_SFNT_NO_SEQUENCE; }
	while (low < high) {
		Off mid = low + ((high - low) >> 1);
		Off record = table + 10 + mid * 11;
		uint32_t found = readU24(s, record);
		if ((uint32_t)selector < found) {
			high = mid;
		} else if ((uint32_t)selector > found) {
			low = mid + 1;
		} else {
			Off defaults = readU32(s, record + 3);
			Off specifics = readU32(s, record + 7);
			if (specifics && sequenceInSpecific(s, table + specifics, codepoint)) {
				return VOID2D_SFNT_SPECIFIC_SEQUENCE;
			}
			if (defaults && sequenceInDefault(s, table + defaults, codepoint)) {
				return VOID2D_SFNT_DEFAULT_SEQUENCE;
			}
			return VOID2D_SFNT_NO_SEQUENCE;
		}
	}
	return VOID2D_SFNT_NO_SEQUENCE;
}

int void2dSfntFlags(int summary) {
	return validSummary(summary) ? s_summaries[summary].flags : 0;
}

int void2dSfntSummariesRead(void) { return s_summariesRead; }
