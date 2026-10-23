#pragma once
#include <stdint.h>

void *metalSystemDevice(void);
int32_t metalReadback(
	void *queue,
	void *texture,
	int32_t level,
	int32_t slice,
	int32_t plane,
	void *pixels,
	int32_t width,
	int32_t height,
	int32_t bytesPerPixel);
