#include "backend.h"
#include "bridge.h"
#include "windowSurface.h"
#include "../gpu/door.h"
#include "../platform/win32/window.h"
#include "../webgpu/vulkan/vulkan.h"

int32_t voidVulkanWindowAwait(int32_t width, int32_t height);
void voidVulkanWindowPresent(void);
uint64_t voidVulkanWindowView(void);
int32_t voidVulkanWindowWidth(void);
int32_t voidVulkanWindowHeight(void);
void voidVulkanWindowClose(void);

static int s_samples;

static void opened(const char *call, int32_t code) {
	if (code != VULKAN_OK) voidFail("%s failed with %d: %s", call, code, vulkanError());
}

void voidWindowSurfaceCreate(HWND hwnd, int samples) {
	s_samples = samples;
	opened("vulkanLoaderOpen", vulkanLoaderOpen());
	opened("vulkanInstanceCreate", vulkanInstanceCreate());
	opened("vulkanSurfaceCreateWin32", vulkanSurfaceCreateWin32(GetModuleHandleW(NULL), hwnd));
	opened("vulkanAdapterSelect", vulkanAdapterSelect(VULKAN_POWER_HIGH));
	opened("vulkanDeviceCreate", vulkanDeviceCreate());
}

void voidWindowDoorSetup(void) {
	doorSetup(NULL, NULL, DOOR_PIXEL_FORMAT_BGRA8, DOOR_PIXEL_FORMAT_DEPTH, s_samples);
	if (!doorValid()) voidFail("doorSetup on the Vulkan device failed");
}

bool voidWindowAwaitFrame(void) {
	return voidVulkanWindowAwait(voidWindowWidth(), voidWindowHeight()) != 0;
}

void voidWindowPresent(bool modal) {
	(void)modal;
	voidVulkanWindowPresent();
}

void voidWindowSurfaceDestroy(void) {
	voidVulkanWindowClose();
	vulkanShutdown();
}

int32_t voidSwapchainWidth(void) { return voidVulkanWindowWidth(); }
int32_t voidSwapchainHeight(void) { return voidVulkanWindowHeight(); }
int32_t voidSwapchainSampleCount(void) { return s_samples; }
void *voidSwapchainRenderView(void) { return (void *)(uintptr_t)voidVulkanWindowView(); }
void *voidSwapchainResolveView(void) { return NULL; }
void *voidSwapchainDepthStencilView(void) { return NULL; }
