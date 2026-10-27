// Void driver — macOS (Metal). Two drivers in one binary, like bridgeWin.c: voidRun is the Cocoa
// window of src/platform/macos/window.m with no sokol_app, and voidViewCreate is the host-view
// driver behind views.ms, one CAMetalLayer per view over one shared MTLDevice. The first of the
// two chooses the driver for the process. The GPU door's Metal backend draws on the shared
// device; the resource and pass wrappers are bridge.c's.

#import <Cocoa/Cocoa.h>
#import <QuartzCore/QuartzCore.h>
#import <Metal/Metal.h>

#include "bridge.h"
#include "viewsExports.h"
#include "../gpu/door.h"
#include "../webgpu/metal/metal.h"
#include "metalSurface.h"
#include "presentGate.h"
#include "appWindow.h"
#include "../platform/macos/window.h"

static CAMetalLayer *g_layer;
static void *g_gate;
static VoidMetalSurface s_window;

// --- Lifecycle closures (driven by voidRun's loop) ---
static msClosure s_init;
static msClosure s_frame;
static int s_frames = 0;

static void tick(void) {
	voidRestoreContextIfLost(voidWindowDoorSetup);
	if (!voidPresentGateAdmits(g_gate)) return;
	id<CAMetalDrawable> drawable = [g_layer nextDrawable];
	if (!drawable) return;
	s_window.drawable = (__bridge void *)drawable;
	voidPresentGateTrack(g_gate, s_window.drawable);
	mtlSetDrawable(s_window.drawable);
	voidCallClosure(s_frame);
	s_frames++;
	s_window.drawable = NULL;
}

static int s_reqW = 0;
static int s_reqH = 0;
void voidRequestedSize(int *w, int *h) { *w = s_reqW; *h = s_reqH; }

static void windowInit(void) {
	NSView *view = (__bridge NSView *)voidMacosView();
	view.wantsLayer = YES;
	voidMetalDeviceMake();
	g_layer = [CAMetalLayer layer];
	g_layer.device = voidMetalDevice();
	g_layer.pixelFormat = MTLPixelFormatBGRA8Unorm;
	g_layer.framebufferOnly = NO;
	g_layer.frame = view.bounds;
	g_layer.contentsScale = (CGFloat)voidWindowDpiScale();
	s_window.w = voidWindowWidth();
	s_window.h = voidWindowHeight();
	g_layer.drawableSize = CGSizeMake(s_window.w, s_window.h);
	g_gate = voidPresentGateCreate((__bridge void *)g_layer);
	[view setLayer:g_layer];
	voidCallClosure(s_init);
}

static void fitWindowLayer(void) {
	NSView *view = (__bridge NSView *)voidMacosView();
	s_window.w = voidWindowWidth();
	s_window.h = voidWindowHeight();
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	g_layer.frame = view.bounds;
	g_layer.contentsScale = (CGFloat)voidWindowDpiScale();
	g_layer.drawableSize = CGSizeMake(s_window.w, s_window.h);
	[CATransaction commit];
}

static void windowEvent(const VoidAppEvent *e) {
	if (e->type == VOID_EVENT_RESIZED) fitWindowLayer();
	voidAppWindowEvent(e);
}

static void windowCleanup(void) { doorShutdown(); }

void voidRunConfigured(int w, int h, int sampleCount, int highDpi, msClosure init, msClosure frame) {
	if (voidDriver == VOID_DRIVER_VIEWS) voidFail("voidRun: this process already drives Void through host views");
	if (sampleCount != 1) {
		voidFail("voidRunConfigured: the macOS window driver renders at 1 sample, not %d", sampleCount);
	}
	voidDriver = VOID_DRIVER_WINDOW;
	s_init = init;
	s_reqW = w;
	s_reqH = h;
	s_frame = frame;
	VoidMacosDesc d = {0};
	d.init = windowInit;
	d.frame = tick;
	d.event = windowEvent;
	d.text = voidAppTextDeliver;
	d.cleanup = windowCleanup;
	d.width = w;
	d.height = h;
	d.highDpi = highDpi != 0;
	d.title = voidWindowTitle();
	voidMacosRun(&d);
}

void voidRun(int w, int h, msClosure init, msClosure frame) {
	voidRunConfigured(w, h, 1, 1, init, frame);
}

void voidWindowDoorSetup(void) { voidMetalDoorSetup(1); }

void voidSetTextInput(int on) { voidMacosSetTextInput(on != 0); }
void voidSetImeRect(int x, int y, int w, int h) { voidMacosSetImeRect(x, y, w, h); }

void voidDriverPresent(void) {
	if (voidDriver == VOID_DRIVER_VIEWS) voidViewsPresent();
}

void voidPlatformDeviceEnsure(void) {
	if (voidDriver == VOID_DRIVER_WINDOW) voidFail("voidViewCreate: this process already runs a Cocoa window through voidRun");
	if (voidDriver == VOID_DRIVER_VIEWS) return;
	voidMetalDeviceMake();
	voidMetalDoorSetup(voidViewsSampleCount());
	voidDriver = VOID_DRIVER_VIEWS;
}

void voidPlatformRunInit(msClosure init) { voidCallClosure(init); }

static void fitView(VoidMetalSurface *s) {
	if (!s->view) return;
	CAMetalLayer *layer = (__bridge CAMetalLayer *)s->layer;
	NSView *view = (__bridge NSView *)s->view;
	[CATransaction begin];
	[CATransaction setDisableActions:YES];
	layer.frame = view.bounds;
	if (view.bounds.size.width > 0) layer.contentsScale = s->w / view.bounds.size.width;
	[CATransaction commit];
}

void *voidPlatformSurfaceCreate(const void *native, int w, int h) {
	VoidMetalSurface *s = voidMetalSurfaceMake((__bridge void *)[CAMetalLayer layer], w, h);
	if (native != NULL) {
		NSView *view = (__bridge NSView *)native;
		view.wantsLayer = YES;
		[view.layer addSublayer:(__bridge CAMetalLayer *)s->layer];
		s->view = (void *)CFBridgingRetain(view);
	}
	fitView(s);
	return s;
}

void voidPlatformSurfaceResize(void *surface, int w, int h) {
	voidMetalSurfaceSize((VoidMetalSurface *)surface, w, h);
	fitView((VoidMetalSurface *)surface);
}

static int windowIsVisible(VoidMetalSurface *s) {
	if (!s->view) return 1;
	NSWindow *window = ((__bridge NSView *)s->view).window;
	return window != nil && (window.occlusionState & NSWindowOcclusionStateVisible) != 0;
}

int voidPlatformSurfaceReady(void *surface) {
	VoidMetalSurface *s = (VoidMetalSurface *)surface;
	return windowIsVisible(s) && voidPresentGateAdmits(s->gate);
}

long long voidPlatformSurfaceNative(void *surface) { return (long long)(intptr_t)((VoidMetalSurface *)surface)->layer; }

const VoidMetalSurface *voidMetalScreen(void) {
	if (voidDriverFor("beginPass") == VOID_DRIVER_WINDOW) return &s_window;
	return voidMetalViewsScreen();
}
