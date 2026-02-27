// Void Asset — Image loading via stb_image

#ifndef VOID_ASSET_IMAGE_H
#define VOID_ASSET_IMAGE_H

void *void_load_image(const char *path, int desired_channels);
int void_image_width(void);
int void_image_height(void);
void void_free_image(void *data);

#endif
