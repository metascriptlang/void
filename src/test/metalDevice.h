#pragma once
#include <stdint.h>

void *metalSystemDevice(void);
int32_t metalReadback(void *queue, void *texture, void *pixels, int32_t width, int32_t height);
