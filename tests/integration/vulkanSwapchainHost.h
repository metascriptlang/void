#ifndef VOID_TEST_VULKAN_SWAPCHAIN_HOST_H
#define VOID_TEST_VULKAN_SWAPCHAIN_HOST_H

#include <stdint.h>

#define VULKAN_HOST_WINDOWS 2

int32_t vulkanHostWindowOpen(uint32_t index, uint32_t width, uint32_t height, uint64_t *surface);
int32_t vulkanHostWindowResize(uint32_t index, uint32_t width, uint32_t height);
void vulkanHostWindowClose(void);
void *vulkanHostView(uint64_t view);

#endif
