#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>
#include <TargetConditionals.h>
#include <stdlib.h>

#include "metalSurface.h"
#include "bridge.h"
#include "presentGate.h"
#include "viewsExports.h"
#include "../gpu/door.h"
#include "../platform/swapchain.h"
#include "../webgpu/metal/metal.h"

#if !__has_feature(objc_arc)
#error "metalSurface.m is written for ARC"
#endif

static id<MTLDevice> s_device;

id<MTLDevice> voidMetalDevice(void) { return s_device; }

void voidMetalDeviceMake(void) {
	s_device = MTLCreateSystemDefaultDevice();
	if (!s_device) voidFail("MTLCreateSystemDefaultDevice returned nil");
}

void voidMetalDoorSetup(int samples) {
	doorSetup((__bridge void *)s_device, NULL, DOOR_PIXEL_FORMAT_BGRA8, DOOR_PIXEL_FORMAT_NONE, samples);
	if (!doorValid()) voidFail("doorSetup on the Metal device failed");
}

static void viewsDoorSetup(void) { voidMetalDoorSetup(voidViewsSampleCount()); }

static void releaseMsaa(VoidMetalSurface *s) {
	if (s->msaa) CFRelease(s->msaa);
	s->msaa = NULL;
}

static void makeMsaa(VoidMetalSurface *s) {
	const int samples = voidViewsSampleCount();
	if (samples == 1) return;
	if (![s_device supportsTextureSampleCount:(NSUInteger)samples]) {
		voidFail("the Metal device cannot render at %d samples", samples);
	}
	MTLTextureDescriptor *desc = [MTLTextureDescriptor
		texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
		width:(NSUInteger)s->w height:(NSUInteger)s->h mipmapped:NO];
	desc.textureType = MTLTextureType2DMultisample;
	desc.sampleCount = (NSUInteger)samples;
	desc.usage = MTLTextureUsageRenderTarget;
#if TARGET_OS_IOS && !TARGET_OS_SIMULATOR
	desc.storageMode = MTLStorageModeMemoryless;
#else
	desc.storageMode = MTLStorageModePrivate;
#endif
	id<MTLTexture> texture = [s_device newTextureWithDescriptor:desc];
	if (!texture) voidFail("the Metal device could not make a %dx%d target at %d samples", s->w, s->h, samples);
	s->msaa = (void *)CFBridgingRetain(texture);
}

VoidMetalSurface *voidMetalSurfaceMake(void *native, int w, int h) {
	CAMetalLayer *layer = (__bridge CAMetalLayer *)native;
	layer.device = s_device;
	layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
	layer.framebufferOnly = NO;
	VoidMetalSurface *s = (VoidMetalSurface *)calloc(1, sizeof(VoidMetalSurface));
	if (!s) voidFail("voidViewCreate: out of memory for a Metal surface");
	s->layer = (void *)CFBridgingRetain(layer);
	s->gate = voidPresentGateCreate(s->layer);
	voidMetalSurfaceSize(s, w, h);
	return s;
}

void voidMetalSurfaceSize(VoidMetalSurface *s, int w, int h) {
	((__bridge CAMetalLayer *)s->layer).drawableSize = CGSizeMake(w, h);
	s->w = w;
	s->h = h;
	releaseMsaa(s);
	makeMsaa(s);
}

// The drawable a commit presented stays readable until the surface's next frame, as the macOS
// window's does, so a capture after commit() reads the frame it showed.
static VoidMetalSurface *s_presented;

int voidPlatformSurfaceAcquire(void *surface) {
	voidRestoreContextIfLost(viewsDoorSetup);
	VoidMetalSurface *s = (VoidMetalSurface *)surface;
	if (s->drawable) CFRelease(s->drawable);
	s->drawable = NULL;
	id<CAMetalDrawable> drawable = [(__bridge CAMetalLayer *)s->layer nextDrawable];
	if (!drawable) return 0;
	voidPresentGateTrack(s->gate, (__bridge void *)drawable);
	s->drawable = (void *)CFBridgingRetain(drawable);
	mtlSetDrawable(s->drawable);
	return 1;
}

void voidPlatformSurfacePresent(void *surface) { s_presented = (VoidMetalSurface *)surface; }

void voidPlatformSurfaceDestroy(void *surface) {
	VoidMetalSurface *s = (VoidMetalSurface *)surface;
	if (s_presented == s) s_presented = NULL;
	if (s->drawable) CFRelease(s->drawable);
	releaseMsaa(s);
	if (s->view) {
		[(__bridge CAMetalLayer *)s->layer removeFromSuperlayer];
		CFRelease(s->view);
	}
	voidPresentGateRelease(s->gate);
	CFRelease(s->layer);
	free(s);
}

VoidMetalSurface *voidMetalViewsScreen(void) {
	if (voidCurrentView() == 0 && s_presented) return s_presented;
	return (VoidMetalSurface *)voidViewsCurrentSurface();
}

static void *drawableTexture(void *drawable) { return (__bridge void *)((__bridge id<CAMetalDrawable>)drawable).texture; }

int32_t voidSwapchainWidth(void) { return voidMetalScreen()->w; }
int32_t voidSwapchainHeight(void) { return voidMetalScreen()->h; }
int32_t voidSwapchainSampleCount(void) { return voidMetalScreen()->msaa ? voidViewsSampleCount() : 1; }

void *voidSwapchainRenderView(void) {
	const VoidMetalSurface *s = voidMetalScreen();
	return s->msaa ? s->msaa : drawableTexture(s->drawable);
}

void *voidSwapchainResolveView(void) {
	const VoidMetalSurface *s = voidMetalScreen();
	return s->msaa ? drawableTexture(s->drawable) : NULL;
}

void *voidSwapchainDepthStencilView(void) { return NULL; }
