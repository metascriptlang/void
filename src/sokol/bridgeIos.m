// Void sokol driver — iOS (Metal). Host-driven: no run-loop, no UIKit window. Each
// React-Native VoidView owns a CAMetalLayer and a CADisplayLink and drives its view in
// views.c. One MTLDevice is shared by every view. Single sokol_gfx implementation unit on iOS
// (Metal backend, no sokol_app).

#define SOKOL_IMPL
#define SOKOL_METAL

#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#include <stdlib.h>
#include <unistd.h>

#include "bridge.h"
#include "views.h"
#include "sokol_log.h"

static id<MTLDevice> g_device;

typedef struct {
	void *layer;
	void *drawable;
} IosSurface;

static void call0(msClosure c) {
	if (!c.fn) return;
	if (c.env) ((void (*)(void *))c.fn)(c.env);
	else ((void (*)(void))c.fn)();
}

void voidPlatformDeviceEnsure(void) {
	if (g_device) return;
	g_device = MTLCreateSystemDefaultDevice();
	if (!g_device) voidFail("MTLCreateSystemDefaultDevice returned nil");
	sg_desc d = {0};
	d.environment.metal.device = (__bridge const void *)g_device;
	d.environment.defaults.color_format = SG_PIXELFORMAT_BGRA8;
	d.environment.defaults.depth_format = SG_PIXELFORMAT_NONE;
	d.environment.defaults.sample_count = 1;
	d.logger.func = slog_func;
	sg_setup(&d);
	if (!sg_isvalid()) voidFail("sg_setup on the Metal device failed");
}

// Void's asset loaders use relative paths ("assets/test.png", "assets/font.ttf").
// Point the CWD at the app bundle for the init window (where images + fonts load),
// then restore — so the host app's CWD is untouched outside this call.
void voidPlatformRunInit(msClosure init) {
	char prev[4096];
	const char *got = getcwd(prev, sizeof prev);
	const char *res = [[[NSBundle mainBundle] resourcePath] fileSystemRepresentation];
	if (res) chdir(res);
	call0(init);
	if (got) chdir(prev);
}

void *voidPlatformSurfaceCreate(const void *native, int w, int h) {
	if (native == NULL) voidFail("voidViewCreate on iOS needs a CAMetalLayer");
	CAMetalLayer *layer = (__bridge CAMetalLayer *)native;
	layer.device = g_device;
	layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
	layer.drawableSize = CGSizeMake(w, h);
	IosSurface *s = (IosSurface *)calloc(1, sizeof(IosSurface));
	s->layer = (void *)CFBridgingRetain(layer);
	return s;
}

void voidPlatformSurfaceResize(void *surface, int w, int h) {
	((__bridge CAMetalLayer *)((IosSurface *)surface)->layer).drawableSize = CGSizeMake(w, h);
}

int voidPlatformSurfaceAcquire(void *surface) {
	IosSurface *s = (IosSurface *)surface;
	id<CAMetalDrawable> drawable = [(__bridge CAMetalLayer *)s->layer nextDrawable];
	if (!drawable) return 0;
	s->drawable = (void *)CFBridgingRetain(drawable);
	return 1;
}

void voidPlatformSurfaceSwapchain(void *surface, sg_swapchain *swapchain) {
	swapchain->color_format = SG_PIXELFORMAT_BGRA8;
	swapchain->metal.current_drawable = ((IosSurface *)surface)->drawable;
}

void voidPlatformSurfacePresent(void *surface) {
	IosSurface *s = (IosSurface *)surface;
	if (s->drawable) CFRelease(s->drawable);
	s->drawable = NULL;
}

void voidPlatformSurfaceDestroy(void *surface) {
	IosSurface *s = (IosSurface *)surface;
	if (s->drawable) CFRelease(s->drawable);
	CFRelease(s->layer);
	free(s);
}

long long voidPlatformSurfaceNative(void *surface) { (void)surface; return 0; }

void voidGfxSetup(void) {
	if (!sg_isvalid()) voidFail("gfxSetup before voidViewCreate made the Metal device");
}

int voidFbWidth(void) { return voidViewsFbWidth(); }
int voidFbHeight(void) { return voidViewsFbHeight(); }
float voidDpiScale(void) { return voidViewsDpiScale(); }
int voidKeyDown(int keycode) { (void)keycode; return 0; }
sg_swapchain voidDriverSwapchain(void) { return voidViewsSwapchain(); }
void voidDriverPresent(void) { voidViewsPresent(); }
