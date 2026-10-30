// Void driver — Android on the Vulkan backend. Host-driven like bridgeAndroid.c: the host owns
// each view's ANativeWindow and the render loop and drives the views in views.ms. Every view is a
// Vulkan surface with its own swapchain (src/webgpu/vulkan/window.ms). The device is made against
// the first view's surface, and the door draws in the colour format that surface lists first.

#include <stdint.h>
#include <stdlib.h>

#include "bridge.h"
#include "viewsExports.h"
#include "../gpu/door.h"
#include "../platform/swapchain.h"
#include "../webgpu/vulkan/vulkan.h"

void voidVulkanSurfaceOpen(uint64_t surface);
int32_t voidVulkanSurfaceAwait(uint64_t surface, int32_t width, int32_t height);
void voidVulkanSurfacePresent(uint64_t surface);
uint64_t voidVulkanSurfaceView(uint64_t surface);
int32_t voidVulkanSurfaceWidth(uint64_t surface);
int32_t voidVulkanSurfaceHeight(uint64_t surface);
void voidVulkanSurfaceClose(uint64_t surface);

static const int32_t FORMAT_RGBA8_UNORM = 37;
static const int32_t FORMAT_BGRA8_UNORM = 44;
static const uint32_t COLOR_SPACE_SRGB_NONLINEAR = 0;

typedef struct {
	uint64_t surface;
	int w, h;
} AndroidVulkanSurface;

static int s_instanceMade;

static void opened(const char *call, int32_t code) {
	if (code != VULKAN_OK) voidFail("%s failed with %d: %s", call, code, vulkanError());
}

void voidPlatformDeviceEnsure(void) {
	if (s_instanceMade) return;
	opened("vulkanLoaderOpen", vulkanLoaderOpen());
	opened("vulkanInstanceCreate", vulkanInstanceCreate());
	s_instanceMade = 1;
}

static int32_t doorFormatOf(uint64_t surface) {
	opened("vulkanSurfaceQuery", vulkanSurfaceQuery(surface));
	for (int32_t i = 0; i < vulkanSurfaceFormatCount(surface); i++) {
		int32_t format = 0;
		uint32_t colorSpace = 0;
		opened("vulkanSurfaceFormat", vulkanSurfaceFormat(surface, i, &format, &colorSpace));
		if (colorSpace != COLOR_SPACE_SRGB_NONLINEAR) continue;
		if (format == FORMAT_RGBA8_UNORM) return DOOR_PIXEL_FORMAT_RGBA8;
		if (format == FORMAT_BGRA8_UNORM) return DOOR_PIXEL_FORMAT_BGRA8;
	}
	voidFail("the first view's Vulkan surface lists neither RGBA8 nor BGRA8 unorm in the sRGB-nonlinear colour space");
}

static void deviceMake(uint64_t surface) {
	opened("vulkanAdapterSelect", vulkanAdapterSelect(VULKAN_POWER_HIGH, surface));
	opened("vulkanDeviceCreate", vulkanDeviceCreate());
	doorSetup(NULL, NULL, doorFormatOf(surface), DOOR_PIXEL_FORMAT_DEPTH, voidViewsSampleCount());
	if (!doorValid()) voidFail("doorSetup on the Vulkan device failed");
}

void *voidPlatformSurfaceCreate(const void *native, int w, int h) {
	if (native == NULL) {
		voidFail("voidViewCreate: a view without an ANativeWindow is an EGL pbuffer, which the Vulkan build has no counterpart for");
	}
	AndroidVulkanSurface *s = (AndroidVulkanSurface *)calloc(1, sizeof(AndroidVulkanSurface));
	if (!s) voidFail("voidViewCreate: out of memory for a Vulkan surface");
	s->w = w;
	s->h = h;
	opened("vulkanSurfaceCreateAndroid", vulkanSurfaceCreateAndroid((void *)native, &s->surface));
	if (!doorValid()) deviceMake(s->surface);
	voidVulkanSurfaceOpen(s->surface);
	return s;
}

void voidPlatformSurfaceResize(void *surface, int w, int h) {
	AndroidVulkanSurface *s = (AndroidVulkanSurface *)surface;
	s->w = w;
	s->h = h;
}

int voidPlatformSurfaceReady(void *surface) { (void)surface; return 1; }

int voidPlatformSurfaceAcquire(void *surface) {
	AndroidVulkanSurface *s = (AndroidVulkanSurface *)surface;
	return voidVulkanSurfaceAwait(s->surface, s->w, s->h) != 0;
}

void voidPlatformSurfacePresent(void *surface) { voidVulkanSurfacePresent(((AndroidVulkanSurface *)surface)->surface); }

void voidPlatformSurfaceDestroy(void *surface) {
	AndroidVulkanSurface *s = (AndroidVulkanSurface *)surface;
	voidVulkanSurfaceClose(s->surface);
	free(s);
}

long long voidPlatformSurfaceNative(void *surface) { (void)surface; return 0; }

void voidEmbedLoseContext(void) {
	voidFail("voidEmbedLoseContext: a Vulkan device has no context to lose, and recovering a lost device is not built");
}

void voidEmbedDetach(void) {}

void voidGfxSetup(void) {
	if (!doorValid()) voidFail("gfxSetup before voidViewCreate made the Vulkan device");
}

static uint64_t currentSurface(void) { return ((AndroidVulkanSurface *)voidViewsCurrentSurface())->surface; }

int32_t voidSwapchainWidth(void) { return voidVulkanSurfaceWidth(currentSurface()); }
int32_t voidSwapchainHeight(void) { return voidVulkanSurfaceHeight(currentSurface()); }
int32_t voidSwapchainSampleCount(void) { return voidViewsSampleCount(); }
void *voidSwapchainRenderView(void) { return (void *)(uintptr_t)voidVulkanSurfaceView(currentSurface()); }
void *voidSwapchainResolveView(void) { return NULL; }
void *voidSwapchainDepthStencilView(void) { return NULL; }

void voidDriverPresent(void) { voidViewsPresent(); }
