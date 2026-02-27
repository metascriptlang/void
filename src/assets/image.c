// Void Asset — Image loading via stb_image

#include "image.h"

#define STB_IMAGE_IMPLEMENTATION
#include "../../deps/stb/stb_image.h"

static int s_width = 0, s_height = 0;

void *void_load_image(const char *path, int desired_channels) {
	int channels;
	unsigned char *data = stbi_load(path, &s_width, &s_height, &channels, desired_channels);
	return (void *)data;
}

int void_image_width(void) { return s_width; }
int void_image_height(void) { return s_height; }

void void_free_image(void *data) {
	if (data) stbi_image_free(data);
}
