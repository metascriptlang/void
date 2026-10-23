// Scratch readback: the swapchain through the door (doorReadScreen) to a PPM
// before Present.
#include <stdio.h>
#include <stdlib.h>
#include "capture3d.h"

static FILE *openFrame(int32_t frame, char *path, size_t size, unsigned width, unsigned height) {
	const char *prefix = getenv("CAPTURE_PREFIX");
	snprintf(path, size, "%s_%d.ppm", prefix ? prefix : "out/tmp/capture/frame", frame);
	FILE *file = fopen(path, "wb");
	if (file) fprintf(file, "P6\n%u %u\n255\n", width, height);
	return file;
}

int32_t doorReadScreen(uint8_t *out, int64_t outLength);
int32_t voidSwapchainWidth(void);
int32_t voidSwapchainHeight(void);

void captureSwapchain(int32_t frame) {
	const int width = voidSwapchainWidth(), height = voidSwapchainHeight();
	uint8_t *rgba = (uint8_t *)malloc((size_t)width * (size_t)height * 4u);
	if (!rgba || !doorReadScreen(rgba, (int64_t)width * (int64_t)height * 4)) { fprintf(stderr, "swapchain readback failed\n"); free(rgba); return; }
	char path[512];
	FILE *file = openFrame(frame, path, sizeof path, (unsigned)width, (unsigned)height);
	for (size_t i = 0; i < (size_t)width * (size_t)height; i++) fwrite(rgba + i * 4, 1, 3, file);
	fclose(file);
	free(rgba);
	fprintf(stderr, "captured %s (%dx%d)\n", path, width, height);
}

void captureQuit(void) { exit(0); }
