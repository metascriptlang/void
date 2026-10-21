#pragma once
#include <stdint.h>

int32_t glWindowOpen(void);
const char *glWindowError(void);
int32_t glWindowReadback(void *texture, void *pixels, int32_t width, int32_t height);
void glWindowClose(void);
