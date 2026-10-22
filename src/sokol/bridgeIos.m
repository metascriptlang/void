// Void driver — iOS (Metal). Host-driven: no run-loop, no UIKit window. Each
// React-Native VoidView owns a CAMetalLayer and a CADisplayLink and drives its view in
// views.c. One MTLDevice is shared by every view; the GPU door's Metal backend draws on it.

#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#include <TargetConditionals.h>
#include <stdlib.h>
#include <unistd.h>

#include "bridge.h"
#include "views.h"
#include "iosApp.h"
#include "../gpu/door.h"
#include "../platform/swapchain.h"
#include "../webgpu/metal/metal.h"

static id<MTLDevice> g_device;

typedef struct {
	void *layer;
	void *drawable;
	void *msaa;
	int w, h;
} IosSurface;

static void call0(msClosure c) {
	if (!c.fn) return;
	if (c.env) ((void (*)(void *))c.fn)(c.env);
	else ((void (*)(void))c.fn)();
}

static void setupMetal(void) {
	doorSetup((__bridge void *)g_device, NULL, DOOR_PIXEL_FORMAT_BGRA8, DOOR_PIXEL_FORMAT_NONE, voidViewsSampleCount());
	if (!doorValid()) voidFail("doorSetup on the Metal device failed");
}

void voidPlatformDeviceEnsure(void) {
	if (g_device) return;
	g_device = MTLCreateSystemDefaultDevice();
	if (!g_device) voidFail("MTLCreateSystemDefaultDevice returned nil");
	setupMetal();
}

static int s_contextLost = 0;
void voidLoseContext(void) { s_contextLost = 1; }

static void restoreContextIfLost(void) {
	if (!s_contextLost) return;
	doorShutdown();
	setupMetal();
	s_contextLost = 0;
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

static void releaseMsaa(IosSurface *s) {
	if (s->msaa) CFRelease(s->msaa);
	s->msaa = NULL;
}

static void makeMsaa(IosSurface *s) {
	const int samples = voidViewsSampleCount();
	if (samples == 1) return;
	if (![g_device supportsTextureSampleCount:(NSUInteger)samples]) {
		voidFail("the Metal device cannot render at %d samples", samples);
	}
	MTLTextureDescriptor *desc = [MTLTextureDescriptor
		texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
		width:(NSUInteger)s->w height:(NSUInteger)s->h mipmapped:NO];
	desc.textureType = MTLTextureType2DMultisample;
	desc.sampleCount = (NSUInteger)samples;
	desc.usage = MTLTextureUsageRenderTarget;
#if TARGET_OS_SIMULATOR
	desc.storageMode = MTLStorageModePrivate;
#else
	desc.storageMode = MTLStorageModeMemoryless;
#endif
	id<MTLTexture> texture = [g_device newTextureWithDescriptor:desc];
	if (!texture) voidFail("the Metal device could not make a %dx%d target at %d samples", s->w, s->h, samples);
	s->msaa = (void *)CFBridgingRetain(texture);
}

void *voidPlatformSurfaceCreate(const void *native, int w, int h) {
	if (native == NULL) voidFail("voidViewCreate on iOS needs a CAMetalLayer");
	CAMetalLayer *layer = (__bridge CAMetalLayer *)native;
	layer.device = g_device;
	layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
	layer.drawableSize = CGSizeMake(w, h);
	IosSurface *s = (IosSurface *)calloc(1, sizeof(IosSurface));
	s->layer = (void *)CFBridgingRetain(layer);
	s->w = w;
	s->h = h;
	makeMsaa(s);
	return s;
}

void voidPlatformSurfaceResize(void *surface, int w, int h) {
	IosSurface *s = (IosSurface *)surface;
	((__bridge CAMetalLayer *)s->layer).drawableSize = CGSizeMake(w, h);
	s->w = w;
	s->h = h;
	releaseMsaa(s);
	makeMsaa(s);
}

int voidPlatformSurfaceAcquire(void *surface) {
	restoreContextIfLost();
	IosSurface *s = (IosSurface *)surface;
	id<CAMetalDrawable> drawable = [(__bridge CAMetalLayer *)s->layer nextDrawable];
	if (!drawable) return 0;
	s->drawable = (void *)CFBridgingRetain(drawable);
	mtlSetDrawable(s->drawable);
	return 1;
}

void voidPlatformSurfacePresent(void *surface) {
	IosSurface *s = (IosSurface *)surface;
	if (s->drawable) CFRelease(s->drawable);
	s->drawable = NULL;
}

void voidPlatformSurfaceDestroy(void *surface) {
	IosSurface *s = (IosSurface *)surface;
	if (s->drawable) CFRelease(s->drawable);
	releaseMsaa(s);
	CFRelease(s->layer);
	free(s);
}

long long voidPlatformSurfaceNative(void *surface) { (void)surface; return 0; }

void voidGfxSetup(void) {
	if (!doorValid()) voidFail("gfxSetup before voidViewCreate made the Metal device");
}

int voidFbWidth(void) { return voidIosAppFbWidth(); }
int voidFbHeight(void) { return voidIosAppFbHeight(); }
float voidDpiScale(void) { return voidIosAppDpiScale(); }
int voidKeyDown(int keycode) { (void)keycode; return 0; }
void voidDriverPresent(void) { voidViewsPresent(); }

static IosSurface *screenSurface(void) { return (IosSurface *)voidViewsCurrentSurface(); }
static void *drawableTexture(void *drawable) { return (__bridge void *)((__bridge id<CAMetalDrawable>)drawable).texture; }

int32_t voidSwapchainWidth(void) { return screenSurface()->w; }
int32_t voidSwapchainHeight(void) { return screenSurface()->h; }
int32_t voidSwapchainSampleCount(void) { return voidViewsSampleCount(); }

void *voidSwapchainRenderView(void) {
	const IosSurface *s = screenSurface();
	return s->msaa ? s->msaa : drawableTexture(s->drawable);
}

void *voidSwapchainResolveView(void) {
	const IosSurface *s = screenSurface();
	return s->msaa ? drawableTexture(s->drawable) : NULL;
}

void *voidSwapchainDepthStencilView(void) { return NULL; }
