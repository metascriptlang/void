#include "backend.h"
#include "bridge.h"
#include "windowSurface.h"
#include "../gpu/door.h"
#include "../platform/win32/window.h"
#include "../webgpu/vulkan/vulkan.h"

void voidVulkanSurfaceOpen(uint64_t surface);
int32_t voidVulkanSurfaceAwait(uint64_t surface, int32_t width, int32_t height);
void voidVulkanSurfacePresent(uint64_t surface);
uint64_t voidVulkanSurfaceView(uint64_t surface);
int32_t voidVulkanSurfaceWidth(uint64_t surface);
int32_t voidVulkanSurfaceHeight(uint64_t surface);
void voidVulkanSurfaceClose(uint64_t surface);

static int s_samples;
static uint64_t s_surface;

static void opened(const char *call, int32_t code) {
	if (code != VULKAN_OK) voidFail("%s failed with %d: %s", call, code, vulkanError());
}

void voidWindowSurfaceCreate(HWND hwnd, int samples) {
	s_samples = samples;
	opened("vulkanLoaderOpen", vulkanLoaderOpen());
	opened("vulkanInstanceCreate", vulkanInstanceCreate());
	opened("vulkanSurfaceCreateWin32", vulkanSurfaceCreateWin32(GetModuleHandleW(NULL), hwnd, &s_surface));
	opened("vulkanAdapterSelect", vulkanAdapterSelect(VULKAN_POWER_HIGH, s_surface));
	opened("vulkanDeviceCreate", vulkanDeviceCreate());
	voidVulkanSurfaceOpen(s_surface);
}

void voidWindowDoorSetup(void) {
	doorSetup(NULL, NULL, DOOR_PIXEL_FORMAT_BGRA8, DOOR_PIXEL_FORMAT_DEPTH, s_samples);
	if (!doorValid()) voidFail("doorSetup on the Vulkan device failed");
}

bool voidWindowAwaitFrame(void) {
	return voidVulkanSurfaceAwait(s_surface, voidWindowWidth(), voidWindowHeight()) != 0;
}

void voidWindowPresent(bool modal) {
	(void)modal;
	voidVulkanSurfacePresent(s_surface);
}

void voidWindowSurfaceDestroy(void) {
	voidVulkanSurfaceClose(s_surface);
	s_surface = 0;
	vulkanShutdown();
}

int32_t voidSwapchainWidth(void) { return voidVulkanSurfaceWidth(s_surface); }
int32_t voidSwapchainHeight(void) { return voidVulkanSurfaceHeight(s_surface); }
int32_t voidSwapchainSampleCount(void) { return s_samples; }
void *voidSwapchainRenderView(void) { return (void *)(uintptr_t)voidVulkanSurfaceView(s_surface); }
void *voidSwapchainResolveView(void) { return NULL; }
void *voidSwapchainDepthStencilView(void) { return NULL; }
