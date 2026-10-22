// Void driver — macOS (Metal). Two drivers in one binary, like bridgeWin.c: voidRun is a
// minimal Cocoa window with no sokol_app, and voidViewCreate is the host-view driver behind
// views.c, one CAMetalLayer per view over one shared MTLDevice. The first of the two chooses the
// driver for the process. The GPU door's Metal backend draws on the shared device; the resource
// and pass wrappers are bridge.c's.

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>

#include "bridge.h"
#include "views.h"
#include "../gpu/door.h"
#include "../platform/swapchain.h"
#include "../webgpu/metal/metal.h"

typedef enum { DRIVER_NONE, DRIVER_WINDOW, DRIVER_VIEWS } VoidDriver;
static VoidDriver s_driver = DRIVER_NONE;

// --- Host-provided GPU context ---
static id<MTLDevice>       g_device;
static CAMetalLayer*       g_layer;
static id<CAMetalDrawable> g_drawable;
static int g_w = 800, g_h = 600;
static float g_dpiScale = 1.0f;

// --- Lifecycle closures (driven by voidRun's loop) ---
static msClosure s_init;
static msClosure s_frame;
static int s_frames = 0;

static void call0(msClosure c) {
	if (!c.fn) return;
	if (c.env) ((void (*)(void *))c.fn)(c.env);
	else ((void (*)(void))c.fn)();
}

// Read the rendered drawable back to a PPM — deterministic Stage-2 proof.
static void captureDrawable(id<CAMetalDrawable> drawable, const char* path) {
	id<MTLTexture> tex = drawable.texture;
	NSUInteger w = tex.width, h = tex.height;
	MTLTextureDescriptor* desc = [MTLTextureDescriptor
		texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
		width:w height:h mipmapped:NO];
	desc.storageMode = MTLStorageModeManaged;
	desc.usage = MTLTextureUsageShaderRead;
	id<MTLTexture> staging = [g_device newTextureWithDescriptor:desc];
	id<MTLCommandQueue> q = [g_device newCommandQueue];
	id<MTLCommandBuffer> cb = [q commandBuffer];
	id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
	[blit copyFromTexture:tex sourceSlice:0 sourceLevel:0
		sourceOrigin:MTLOriginMake(0,0,0) sourceSize:MTLSizeMake(w,h,1)
		toTexture:staging destinationSlice:0 destinationLevel:0
		destinationOrigin:MTLOriginMake(0,0,0)];
	[blit synchronizeResource:staging];
	[blit endEncoding];
	[cb commit];
	[cb waitUntilCompleted];
	NSUInteger rowBytes = w * 4;
	uint8_t* buf = (uint8_t*)malloc(rowBytes * h);
	[staging getBytes:buf bytesPerRow:rowBytes
		fromRegion:MTLRegionMake2D(0,0,w,h) mipmapLevel:0];
	FILE* f = fopen(path, "wb");
	fprintf(f, "P6\n%lu %lu\n255\n", (unsigned long)w, (unsigned long)h);
	for (NSUInteger i = 0; i < w*h; i++) {
		uint8_t b = buf[i*4+0], g = buf[i*4+1], r = buf[i*4+2];
		fputc(r, f); fputc(g, f); fputc(b, f);
	}
	fclose(f);
	free(buf);
	NSLog(@"voidEmbed capture: wrote %s %lux%lu", path, (unsigned long)w, (unsigned long)h);
}

static void tick(void) {
	g_drawable = [g_layer nextDrawable];
	if (!g_drawable) return;
	mtlSetDrawable((__bridge void *)g_drawable);
	call0(s_frame);
	s_frames++;
	(void)captureDrawable;
	g_drawable = nil;
}

@interface VEAppDelegate : NSObject <NSApplicationDelegate>
@end
@implementation VEAppDelegate
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)s { (void)s; return YES; }
@end
static id g_delegate;

static int s_reqW = 0;
static int s_reqH = 0;
void voidRequestedSize(int *w, int *h) { *w = s_reqW; *h = s_reqH; }
void voidRunConfigured(int w, int h, int sampleCount, int highDpi, msClosure init, msClosure frame) {
	if (s_driver == DRIVER_VIEWS) voidFail("voidRun: this process already drives Void through host views");
	if (sampleCount != 1) {
		voidFail("voidRunConfigured: the macOS window driver renders at 1 sample, not %d", sampleCount);
	}
	s_driver = DRIVER_WINDOW;
	s_init = init;
	s_reqW = w;
	s_reqH = h;
	s_frame = frame;

	@autoreleasepool {
		[NSApplication sharedApplication];
		[NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
		g_delegate = [VEAppDelegate new];
		[NSApp setDelegate:g_delegate];

		NSRect rect = NSMakeRect(0, 0, w, h);
		NSWindow* win = [[NSWindow alloc] initWithContentRect:rect
			styleMask:(NSWindowStyleMaskTitled | NSWindowStyleMaskClosable)
			backing:NSBackingStoreBuffered defer:NO];
		[win setTitle:@"Void — EMBED (no sokol_app)"];

		g_dpiScale = highDpi ? (float)[[NSScreen mainScreen] backingScaleFactor] : 1.0f;
		if (g_dpiScale < 1.0f) g_dpiScale = 1.0f;

		NSView* view = [win contentView];
		view.wantsLayer = YES;

		g_device = MTLCreateSystemDefaultDevice();
		g_layer = [CAMetalLayer layer];
		g_layer.device = g_device;
		g_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
		g_layer.framebufferOnly = NO;
		g_layer.frame = view.bounds;
		g_layer.contentsScale = (CGFloat)g_dpiScale;
		g_w = (int)(w * g_dpiScale);
		g_h = (int)(h * g_dpiScale);
		g_layer.drawableSize = CGSizeMake(g_w, g_h);
		[view setLayer:g_layer];

		[win center];
		[win makeKeyAndOrderFront:nil];
		[NSApp activateIgnoringOtherApps:YES];

		call0(s_init);

		[NSTimer scheduledTimerWithTimeInterval:1.0/60.0 repeats:YES
			block:^(NSTimer* t){ (void)t; tick(); }];
		[NSApp run];
	}
}

void voidRun(int w, int h, msClosure init, msClosure frame) {
	voidRunConfigured(w, h, 1, 1, init, frame);
}

static void setupMetal(int samples) {
	doorSetup((__bridge void *)g_device, NULL, DOOR_PIXEL_FORMAT_BGRA8, DOOR_PIXEL_FORMAT_NONE, samples);
	if (!doorValid()) voidFail("doorSetup on the Metal device failed");
}

__attribute__((noreturn)) static void noDriver(const char *op) {
	voidFail("%s before voidRun or voidViewCreate chose a driver", op);
}

void voidGfxSetup(void) {
	switch (s_driver) {
		case DRIVER_WINDOW: setupMetal(1); break;
		case DRIVER_VIEWS: break;
		case DRIVER_NONE: noDriver("gfxSetup");
	}
}

int voidFbWidth(void) {
	if (s_driver == DRIVER_WINDOW) return g_w;
	if (s_driver == DRIVER_NONE) noDriver("fbWidth");
	return voidViewsFbWidth();
}

int voidFbHeight(void) {
	if (s_driver == DRIVER_WINDOW) return g_h;
	if (s_driver == DRIVER_NONE) noDriver("fbHeight");
	return voidViewsFbHeight();
}

float voidDpiScale(void) {
	if (s_driver == DRIVER_WINDOW) return g_dpiScale;
	if (s_driver == DRIVER_NONE) noDriver("dpiScale");
	return voidViewsDpiScale();
}

// Keyboard polling — Stage-2 stub (the 2D render proof needs no input). In Stage 3
// this maps to the host (RCTView) key state; here no keys are ever down.
int voidKeyDown(int keycode) { (void)keycode; return 0; }

void voidDriverPresent(void) {
	if (s_driver == DRIVER_VIEWS) voidViewsPresent();
}

typedef struct {
	void *layer;
	void *view;
	void *drawable;
	void *msaa;
	int w, h;
} MacSurface;

static void releaseMsaa(MacSurface *s) {
	if (s->msaa) CFRelease(s->msaa);
	s->msaa = NULL;
}

static void makeMsaa(MacSurface *s) {
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
	desc.storageMode = MTLStorageModePrivate;
	id<MTLTexture> texture = [g_device newTextureWithDescriptor:desc];
	if (!texture) voidFail("the Metal device could not make a %dx%d target at %d samples", s->w, s->h, samples);
	s->msaa = (void *)CFBridgingRetain(texture);
}

void voidPlatformDeviceEnsure(void) {
	if (s_driver == DRIVER_WINDOW) voidFail("voidViewCreate: this process already runs a Cocoa window through voidRun");
	if (s_driver == DRIVER_VIEWS) return;
	g_device = MTLCreateSystemDefaultDevice();
	if (!g_device) voidFail("MTLCreateSystemDefaultDevice returned nil");
	setupMetal(voidViewsSampleCount());
	s_driver = DRIVER_VIEWS;
}

void voidPlatformRunInit(msClosure init) { call0(init); }

static void fitLayer(MacSurface *s, int w, int h) {
	CAMetalLayer *layer = (__bridge CAMetalLayer *)s->layer;
	layer.drawableSize = CGSizeMake(w, h);
	s->w = w;
	s->h = h;
	releaseMsaa(s);
	makeMsaa(s);
	if (!s->view) return;
	NSView *view = (__bridge NSView *)s->view;
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	layer.frame = view.bounds;
	if (view.bounds.size.width > 0) layer.contentsScale = w / view.bounds.size.width;
	[CATransaction commit];
}

void *voidPlatformSurfaceCreate(const void *native, int w, int h) {
	CAMetalLayer *layer = [CAMetalLayer layer];
	layer.device = g_device;
	layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
	MacSurface *s = (MacSurface *)calloc(1, sizeof(MacSurface));
	s->layer = (void *)CFBridgingRetain(layer);
	if (native != NULL) {
		NSView *view = (__bridge NSView *)native;
		view.wantsLayer = YES;
		[view.layer addSublayer:layer];
		s->view = (void *)CFBridgingRetain(view);
	}
	fitLayer(s, w, h);
	return s;
}

void voidPlatformSurfaceResize(void *surface, int w, int h) { fitLayer((MacSurface *)surface, w, h); }

int voidPlatformSurfaceAcquire(void *surface) {
	MacSurface *s = (MacSurface *)surface;
	id<CAMetalDrawable> drawable = [(__bridge CAMetalLayer *)s->layer nextDrawable];
	if (!drawable) return 0;
	s->drawable = (void *)CFBridgingRetain(drawable);
	mtlSetDrawable(s->drawable);
	return 1;
}


void voidPlatformSurfacePresent(void *surface) {
	MacSurface *s = (MacSurface *)surface;
	if (s->drawable) CFRelease(s->drawable);
	s->drawable = NULL;
}

void voidPlatformSurfaceDestroy(void *surface) {
	MacSurface *s = (MacSurface *)surface;
	if (s->drawable) CFRelease(s->drawable);
	releaseMsaa(s);
	[(__bridge CAMetalLayer *)s->layer removeFromSuperlayer];
	CFRelease(s->layer);
	if (s->view) CFRelease(s->view);
	free(s);
}

long long voidPlatformSurfaceNative(void *surface) { return (long long)(intptr_t)((MacSurface *)surface)->layer; }

static MacSurface *screenSurface(void) {
	if (s_driver == DRIVER_NONE) noDriver("beginPass");
	return s_driver == DRIVER_VIEWS ? (MacSurface *)voidViewsCurrentSurface() : NULL;
}

static void *drawableTexture(void *drawable) { return (__bridge void *)((__bridge id<CAMetalDrawable>)drawable).texture; }

int32_t voidSwapchainWidth(void) {
	const MacSurface *s = screenSurface();
	return s ? s->w : g_w;
}

int32_t voidSwapchainHeight(void) {
	const MacSurface *s = screenSurface();
	return s ? s->h : g_h;
}

int32_t voidSwapchainSampleCount(void) { return screenSurface() ? voidViewsSampleCount() : 1; }

void *voidSwapchainRenderView(void) {
	const MacSurface *s = screenSurface();
	if (s == NULL) return drawableTexture((__bridge void *)g_drawable);
	return s->msaa ? s->msaa : drawableTexture(s->drawable);
}

void *voidSwapchainResolveView(void) {
	const MacSurface *s = screenSurface();
	return s && s->msaa ? drawableTexture(s->drawable) : NULL;
}

void *voidSwapchainDepthStencilView(void) { return NULL; }
