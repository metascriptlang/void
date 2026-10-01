// Void sokol bridge — EMBED variant (Stage-2 POC). Same surface as bridge.c, but
// renders into a host-provided CAMetalLayer with NO sokol_app: we own the MTLDevice
// and hand sokol a fresh CAMetalDrawable each frame. voidRun() here is a minimal
// Cocoa driver (the macOS stand-in for the React-Native RCTView that will drive
// frames in Stage 3). Everything else is identical to bridge.c.

#import <Cocoa/Cocoa.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>

#include "bridge.h"
#include "sokol_gfx.h"
#include "sokol_log.h"

// --- Host-provided GPU context (no sokol_app / sglue) ---
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

void voidRun(int w, int h, msClosure init, msClosure frame) {
	s_init = init;
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

		g_dpiScale = (float)[[NSScreen mainScreen] backingScaleFactor];
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

void voidGfxSetup(void) {
	sg_desc d = {0};
	d.environment.metal.device = (__bridge const void*)g_device;
	d.environment.defaults.color_format = SG_PIXELFORMAT_BGRA8;
	d.environment.defaults.depth_format = SG_PIXELFORMAT_NONE;
	d.environment.defaults.sample_count = 1;
	d.logger.func = slog_func;
	sg_setup(&d);
}

int voidFbWidth(void) { return g_w; }
int voidFbHeight(void) { return g_h; }
float voidDpiScale(void) { return g_dpiScale; }

// Keyboard polling — Stage-2 stub (the 2D render proof needs no input). In Stage 3
// this maps to the host (RCTView) key state; here no keys are ever down.
int voidKeyDown(int keycode) { (void)keycode; return 0; }

// --- Resource creation (identical to bridge.c) ---

uint32_t voidMakeImage(const void *rgba, int w, int h) {
	static const uint8_t white[4] = {255, 255, 255, 255};
	if (rgba == NULL || w <= 0 || h <= 0) { rgba = white; w = 1; h = 1; }
	sg_image_desc d = {0};
	d.width = w;
	d.height = h;
	d.pixel_format = SG_PIXELFORMAT_RGBA8;
	d.data.mip_levels[0].ptr = rgba;
	d.data.mip_levels[0].size = (size_t)(w * h * 4);
	return sg_make_image(&d).id;
}

uint32_t voidMakeView(uint32_t image) {
	sg_view_desc d = {0};
	d.texture.image = (sg_image){.id = image};
	return sg_make_view(&d).id;
}

// --- Frame sequence ---

void voidBeginPass(float r, float g, float b, float a) {
	sg_pass pass = {0};
	pass.action.colors[0].load_action = SG_LOADACTION_CLEAR;
	pass.action.colors[0].clear_value = (sg_color){r, g, b, a};
	pass.swapchain.width = g_w;
	pass.swapchain.height = g_h;
	pass.swapchain.sample_count = 1;
	pass.swapchain.color_format = SG_PIXELFORMAT_BGRA8;
	pass.swapchain.depth_format = SG_PIXELFORMAT_NONE;
	pass.swapchain.metal.current_drawable = (__bridge const void*)g_drawable;
	sg_begin_pass(&pass);
}

static void (*s_commitHook)(void);
void voidSetCommitHook(void (*fn)(void)) { s_commitHook = fn; }
void voidCommit(void) { sg_commit(); if (s_commitHook) { s_commitHook(); } }
