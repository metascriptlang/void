#include "fontBytes.h"
#include <stdlib.h>
#include <string.h>

typedef struct {
	char *name;
	unsigned char *bytes;
	size_t length;
} MemoryFont;

static MemoryFont *s_memory;
static int s_memoryCount;

const unsigned char *void2dFontBytesFind(const char *name, size_t *length) {
	for (int i = 0; i < s_memoryCount; i++) {
		if (strcmp(s_memory[i].name, name) == 0) {
			*length = s_memory[i].length;
			return s_memory[i].bytes;
		}
	}
	return NULL;
}

int void2dFontBytesAdd(const char *name, const unsigned char *bytes, int length) {
	size_t had = 0;
	const unsigned char *known = void2dFontBytesFind(name, &had);
	if (known) {
		return had == (size_t)length && memcmp(known, bytes, had) == 0 ? VOID2D_FONT_BYTES_OK
			: VOID2D_FONT_BYTES_CONFLICT;
	}
	MemoryFont *grown = (MemoryFont *)realloc(s_memory, sizeof(MemoryFont) * (size_t)(s_memoryCount + 1));
	if (!grown) { return VOID2D_SFNT_NO_MEMORY; }
	s_memory = grown;
	MemoryFont font = { (char *)malloc(strlen(name) + 1), (unsigned char *)malloc((size_t)length), (size_t)length };
	if (!font.name || !font.bytes) {
		free(font.name);
		free(font.bytes);
		return VOID2D_SFNT_NO_MEMORY;
	}
	strcpy(font.name, name);
	memcpy(font.bytes, bytes, (size_t)length);
	s_memory[s_memoryCount++] = font;
	return VOID2D_FONT_BYTES_OK;
}
