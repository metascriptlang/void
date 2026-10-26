#ifndef VOID_TEST_VULKAN_SWAPCHAIN_HOST_H
#define VOID_TEST_VULKAN_SWAPCHAIN_HOST_H

#include <stdint.h>

int32_t vulkanHostWindowOpen(uint32_t width, uint32_t height);
int32_t vulkanHostWindowResize(uint32_t width, uint32_t height);
void vulkanHostWindowClose(void);
void *vulkanHostView(uint64_t view);

#endif
