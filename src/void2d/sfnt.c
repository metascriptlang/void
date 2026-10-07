#include "sfnt.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define SFNT_MAX_TABLES 512
#define SFNT_MAX_CMAP 0x4000000L

typedef struct {
	unsigned char *cmap;
	long length;
	long index;
	long sequences;
	int flags;
} Summary;

static Summary *s_summaries;
static int s_summaryCount;
static int s_summaryCapacity;
static int s_summariesRead;

static unsigned readU8(const Summary *s, long at) {
	return at < 0 || at >= s->length ? 0 : s->cmap[at];
}

static unsigned readU16(const Summary *s, long at) {
	if (at < 0 || at + 2 > s->length) { return 0; }
	return ((unsigned)s->cmap[at] << 8) | s->cmap[at + 1];
}

static int readI16(const Summary *s, long at) {
	unsigned v = readU16(s, at);
	return v >= 0x8000u ? (int)v - 0x10000 : (int)v;
}

static unsigned long readU24(const Summary *s, long at) {
	if (at < 0 || at + 3 > s->length) { return 0; }
	return ((unsigned long)s->cmap[at] << 16) | ((unsigned long)s->cmap[at + 1] << 8) |
		s->cmap[at + 2];
}

static unsigned long readU32(const Summary *s, long at) {
	if (at < 0 || at + 4 > s->length) { return 0; }
	return ((unsigned long)s->cmap[at] << 24) | ((unsigned long)s->cmap[at + 1] << 16) |
		((unsigned long)s->cmap[at + 2] << 8) | s->cmap[at + 3];
}

static unsigned long fileU32(const unsigned char *p) {
	return ((unsigned long)p[0] << 24) | ((unsigned long)p[1] << 16) |
		((unsigned long)p[2] << 8) | p[3];
}

static int validSummary(int summary) { return summary >= 0 && summary < s_summaryCount; }

static int glyphInFormat4(const Summary *s, long map, int codepoint) {
	unsigned segcount = readU16(s, map + 6) >> 1;
	unsigned searchRange = readU16(s, map + 8) >> 1;
	unsigned entrySelector = readU16(s, map + 10);
	unsigned rangeShift = readU16(s, map + 12) >> 1;
	long endCount = map + 14;
	long search = endCount;
	if (codepoint > 0xffff) { return 0; }
	if ((unsigned)codepoint >= readU16(s, search + (long)rangeShift * 2)) {
		search += (long)rangeShift * 2;
	}
	search -= 2;
	while (entrySelector) {
		searchRange >>= 1;
		if ((unsigned)codepoint > readU16(s, search + (long)searchRange * 2)) {
			search += (long)searchRange * 2;
		}
		--entrySelector;
	}
	search += 2;
	unsigned item = (unsigned)((search - endCount) >> 1) & 0xffffu;
	unsigned start = readU16(s, map + 14 + (long)segcount * 2 + 2 + 2 * (long)item);
	unsigned last = readU16(s, endCount + 2 * (long)item);
	if ((unsigned)codepoint < start || (unsigned)codepoint > last) { return 0; }
	unsigned offset = readU16(s, map + 14 + (long)segcount * 6 + 2 + 2 * (long)item);
	if (offset == 0) {
		int delta = readI16(s, map + 14 + (long)segcount * 4 + 2 + 2 * (long)item);
		return (int)((unsigned)(codepoint + delta) & 0xffffu);
	}
	return (int)readU16(s, offset + (long)(codepoint - (int)start) * 2 + map + 14 +
		(long)segcount * 6 + 2 + 2 * (long)item);
}

static int glyphInGroups(const Summary *s, long map, int codepoint, int sharedGlyph) {
	long low = 0;
	long high = (long)readU32(s, map + 12);
	while (low < high) {
		long mid = low + ((high - low) >> 1);
		unsigned long startChar = readU32(s, map + 16 + mid * 12);
		unsigned long endChar = readU32(s, map + 16 + mid * 12 + 4);
		if ((unsigned long)codepoint < startChar) {
			high = mid;
		} else if ((unsigned long)codepoint > endChar) {
			low = mid + 1;
		} else {
			unsigned long startGlyph = readU32(s, map + 16 + mid * 12 + 8);
			if (sharedGlyph) { return (int)startGlyph; }
			return (int)(startGlyph + ((unsigned long)codepoint - startChar));
		}
	}
	return 0;
}

static int stbCompatibleGlyph(const Summary *s, int codepoint) {
	long map = s->index;
	if (map == 0 || codepoint < 0) { return 0; }
	unsigned format = readU16(s, map);
	if (format == 0) {
		int bytes = (int)readU16(s, map + 2);
		if (codepoint < bytes - 6 && s->index + 6 + codepoint < s->length) {
			return s->cmap[map + 6 + codepoint];
		}
		return 0;
	}
	if (format == 6) {
		unsigned long first = readU16(s, map + 6);
		unsigned long count = readU16(s, map + 8);
		if ((unsigned long)codepoint >= first && (unsigned long)codepoint < first + count) {
			return (int)readU16(s, map + 10 + (long)((unsigned long)codepoint - first) * 2);
		}
		return 0;
	}
	if (format == 4) { return glyphInFormat4(s, map, codepoint); }
	if (format == 12) { return glyphInGroups(s, map, codepoint, 0); }
	if (format == 13) { return glyphInGroups(s, map, codepoint, 1); }
	return 0;
}

static long chooseIndex(const Summary *s) {
	long chosen = 0;
	unsigned records = readU16(s, 2);
	for (unsigned i = 0; i < records; i++) {
		long record = 4 + 8 * (long)i;
		unsigned platform = readU16(s, record);
		unsigned encoding = readU16(s, record + 2);
		long offset = (long)readU32(s, record + 4);
		if (platform == 3 && (encoding == 1 || encoding == 10)) { chosen = offset; }
		if (platform == 0) { chosen = offset; }
	}
	return chosen;
}

static long chooseSequences(const Summary *s) {
	unsigned records = readU16(s, 2);
	for (unsigned i = 0; i < records; i++) {
		long record = 4 + 8 * (long)i;
		if (readU16(s, record) == 0 && readU16(s, record + 2) == 5) {
			long offset = (long)readU32(s, record + 4);
			if (readU16(s, offset) == 14) { return offset; }
		}
	}
	return 0;
}

static int sequenceInDefault(const Summary *s, long table, int codepoint) {
	long low = 0;
	long high = (long)readU32(s, table);
	while (low < high) {
		long mid = low + ((high - low) >> 1);
		unsigned long start = readU24(s, table + 4 + mid * 4);
		unsigned long last = start + readU8(s, table + 4 + mid * 4 + 3);
		if ((unsigned long)codepoint < start) {
			high = mid;
		} else if ((unsigned long)codepoint > last) {
			low = mid + 1;
		} else {
			return 1;
		}
	}
	return 0;
}

static int sequenceInSpecific(const Summary *s, long table, int codepoint) {
	long low = 0;
	long high = (long)readU32(s, table);
	while (low < high) {
		long mid = low + ((high - low) >> 1);
		unsigned long value = readU24(s, table + 4 + mid * 5);
		if ((unsigned long)codepoint < value) {
			high = mid;
		} else if ((unsigned long)codepoint > value) {
			low = mid + 1;
		} else {
			return readU16(s, table + 4 + mid * 5 + 3) != 0;
		}
	}
	return 0;
}

static unsigned char *readRange(FILE *f, long at, long length) {
	unsigned char *buf = (unsigned char *)malloc((size_t)(length > 0 ? length : 1));
	if (!buf) { return NULL; }
	if (fseek(f, at, SEEK_SET) != 0 || fread(buf, 1, (size_t)length, f) != (size_t)length) {
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
	long offset;
	long length;
	int found;
} TableSpan;

static TableSpan findTable(const unsigned char *directory, int tables, long fileSize,
		const char *tag) {
	TableSpan span = { 0, 0, 0 };
	for (int i = 0; i < tables; i++) {
		const unsigned char *record = directory + 16 * i;
		if (memcmp(record, tag, 4) != 0) { continue; }
		unsigned long offset = fileU32(record + 8);
		unsigned long length = fileU32(record + 12);
		if (offset > (unsigned long)fileSize || length > (unsigned long)fileSize - offset) {
			continue;
		}
		span.offset = (long)offset;
		span.length = (long)length;
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
	long fileSize = ftell(f);
	unsigned char head[16];
	long fontStart = 0;
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
		fontStart = (long)fileU32(head);
		if (fontStart < 0 || fontStart + 12 > fileSize || fseek(f, fontStart, SEEK_SET) != 0 ||
			fread(head, 1, 12, f) != 12) {
			goto done;
		}
	}
	if (!(fileU32(head) == 0x00010000ul || memcmp(head, "OTTO", 4) == 0 ||
		memcmp(head, "true", 4) == 0)) {
		goto done;
	}
	tables = (int)(((unsigned)head[4] << 8) | head[5]);
	if (tables == 0 || tables > SFNT_MAX_TABLES) { goto done; }
	directory = readRange(f, fontStart + 12, 16L * tables);
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
	long table = s->sequences;
	if (table == 0) { return VOID2D_SFNT_NO_SEQUENCE; }
	long low = 0;
	long high = (long)readU32(s, table + 6);
	while (low < high) {
		long mid = low + ((high - low) >> 1);
		long record = table + 10 + mid * 11;
		unsigned long found = readU24(s, record);
		if ((unsigned long)selector < found) {
			high = mid;
		} else if ((unsigned long)selector > found) {
			low = mid + 1;
		} else {
			unsigned long defaults = readU32(s, record + 3);
			unsigned long specifics = readU32(s, record + 7);
			if (specifics && sequenceInSpecific(s, table + (long)specifics, codepoint)) {
				return VOID2D_SFNT_SPECIFIC_SEQUENCE;
			}
			if (defaults && sequenceInDefault(s, table + (long)defaults, codepoint)) {
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
