// Void sokol driver — macOS (Metal). Two drivers in one binary, like bridgeWin.c: voidRun is a
// minimal Cocoa window with no sokol_app, and voidViewCreate is the host-view driver behind
// views.c, one CAMetalLayer per view over one shared MTLDevice. The first of the two chooses the
// driver for the process. sokol_gfx is the one implementation in sokol.o; the resource and pass
// wrappers are bridge.c's.

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>

#include "bridge.h"
#include "views.h"
#include "presentGate.h"
#include "sokol_gfx.h"
#include "sokol_log.h"

typedef enum { DRIVER_NONE, DRIVER_WINDOW, DRIVER_VIEWS } VoidDriver;
static VoidDriver s_driver = DRIVER_NONE;

// --- Host-provided GPU context (no sokol_app / sglue) ---
static id<MTLDevice>       g_device;
static CAMetalLayer*       g_layer;
static id<CAMetalDrawable> g_drawable;
static void*              g_gate;
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

static void tick(void) {
	if (!voidPresentGateAdmits(g_gate)) return;
	g_drawable = [g_layer nextDrawable];
	if (!g_drawable) return;
	voidPresentGateTrack(g_gate, (__bridge void *)g_drawable);
	call0(s_frame);
	s_frames++;
	g_drawable = nil;
}

int voidWindowReadRgba(uint8_t *out, int width, int height) {
	if (s_driver != DRIVER_WINDOW || !g_drawable) return 0;
	id<MTLTexture> tex = g_drawable.texture;
	if ((int)tex.width != width || (int)tex.height != height) return 0;
	@autoreleasepool {
		NSUInteger rowBytes = (NSUInteger)width * 4u;
		id<MTLBuffer> shared = [g_device newBufferWithLength:rowBytes * (NSUInteger)height
			options:MTLResourceStorageModeShared];
		if (!shared) return 0;
		id<MTLCommandQueue> queue = (__bridge id<MTLCommandQueue>)sg_mtl_command_queue();
		id<MTLCommandBuffer> cb = [queue commandBuffer];
		id<MTLBlitCommandEncoder> blit = [cb blitCommandEncoder];
		[blit copyFromTexture:tex sourceSlice:0 sourceLevel:0
			sourceOrigin:MTLOriginMake(0, 0, 0) sourceSize:MTLSizeMake((NSUInteger)width, (NSUInteger)height, 1)
			toBuffer:shared destinationOffset:0 destinationBytesPerRow:rowBytes
			destinationBytesPerImage:rowBytes * (NSUInteger)height];
		[blit endEncoding];
		[cb commit];
		[cb waitUntilCompleted];
		int ok = cb.status == MTLCommandBufferStatusCompleted;
		const uint8_t *bgra = (const uint8_t *)shared.contents;
		for (size_t i = 0; ok && i < (size_t)width * (size_t)height; i++) {
			out[i * 4 + 0] = bgra[i * 4 + 2];
			out[i * 4 + 1] = bgra[i * 4 + 1];
			out[i * 4 + 2] = bgra[i * 4 + 0];
			out[i * 4 + 3] = bgra[i * 4 + 3];
		}
		[shared release];
		return ok;
	}
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
		g_gate = voidPresentGateCreate((__bridge void *)g_layer);
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
	sg_desc d = {0};
	d.environment.metal.device = (__bridge const void*)g_device;
	d.environment.defaults.color_format = SG_PIXELFORMAT_BGRA8;
	d.environment.defaults.depth_format = SG_PIXELFORMAT_NONE;
	d.environment.defaults.sample_count = samples;
	d.logger.func = slog_func;
	sg_setup(&d);
	if (!sg_isvalid()) voidFail("sg_setup on the Metal device failed");
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

sg_swapchain voidDriverSwapchain(void) {
	if (s_driver == DRIVER_NONE) noDriver("beginPass");
	if (s_driver == DRIVER_VIEWS) return voidViewsSwapchain();
	sg_swapchain swapchain = {0};
	swapchain.width = g_w;
	swapchain.height = g_h;
	swapchain.sample_count = 1;
	swapchain.color_format = SG_PIXELFORMAT_BGRA8;
	swapchain.depth_format = SG_PIXELFORMAT_NONE;
	swapchain.metal.current_drawable = (__bridge const void*)g_drawable;
	return swapchain;
}

void voidDriverPresent(void) {
	if (s_driver == DRIVER_VIEWS) voidViewsPresent();
}

typedef struct {
	void *layer;
	void *gate;
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
	s->gate = voidPresentGateCreate(s->layer);
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

int voidPlatformSurfaceReady(void *surface) { return voidPresentGateAdmits(((MacSurface *)surface)->gate); }

int voidPlatformSurfaceAcquire(void *surface) {
	MacSurface *s = (MacSurface *)surface;
	id<CAMetalDrawable> drawable = [(__bridge CAMetalLayer *)s->layer nextDrawable];
	if (!drawable) return 0;
	voidPresentGateTrack(s->gate, (__bridge void *)drawable);
	s->drawable = (void *)CFBridgingRetain(drawable);
	return 1;
}

void voidPlatformSurfaceSwapchain(void *surface, sg_swapchain *swapchain) {
	swapchain->color_format = SG_PIXELFORMAT_BGRA8;
	swapchain->metal.current_drawable = ((MacSurface *)surface)->drawable;
	swapchain->metal.msaa_color_texture = ((MacSurface *)surface)->msaa;
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
	voidPresentGateRelease(s->gate);
	CFRelease(s->layer);
	if (s->view) CFRelease(s->view);
	free(s);
}

long long voidPlatformSurfaceNative(void *surface) { return (long long)(intptr_t)((MacSurface *)surface)->layer; }
