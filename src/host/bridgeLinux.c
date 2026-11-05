// Void driver — Linux: the X11 window and its GLX or EGL context (src/platform/linux/window.c)
// drive voidRun; the GPU door's GL backend (src/webgpu/gl, GL core or GLES3) draws into
// framebuffer 0. Host views (views.ms) draw through one GLX context made current on each view's
// drawable (voidLinuxView* in window.c).

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "backend.h"
#include "bridge.h"
#include "appWindow.h"
#include "viewsExports.h"
#include "../gpu/door.h"
#include "../platform/swapchain.h"
#include "../platform/linux/window.h"

static msClosure s_init;
static msClosure s_frame;
static int s_reqW = 0;
static int s_reqH = 0;
static int s_sampleCount;
static bool s_committed;

void voidWindowDoorSetup(void) {
	doorSetup(NULL, NULL, DOOR_PIXEL_FORMAT_RGBA8, DOOR_PIXEL_FORMAT_DEPTH, s_sampleCount);
	if (!doorValid()) voidFail("doorSetup on the window's GL context failed");
}

// sokol_app's X11 backend has no input method: keys arrive through XLookupString as Char
// (sokol_app.h :13803), so text input is always the OS default and there is no IME to place.
void voidSetTextInput(int on) { (void)on; }
void voidSetImeRect(int x, int y, int w, int h) {
	(void)x;
	(void)y;
	(void)w;
	(void)h;
}

static void _init(void) { voidCallClosure(s_init); }

static void _frame(void) {
	voidRestoreContextIfLost(voidWindowDoorSetup);
	s_committed = false;
	voidCallClosure(s_frame);
	if (s_committed) voidLinuxSwapBuffers();
}

static void _cleanup(void) { doorShutdown(); }

// highDpi is not read: sokol_app on X11 always maps window pixels 1:1 to the framebuffer and
// scales by Xft.dpi (sokol_app.h :14299).
void voidRunConfigured(int w, int h, int sampleCount, int highDpi, msClosure init, msClosure frame) {
	(void)highDpi;
	if (voidDriver == VOID_DRIVER_VIEWS) voidFail("voidRun: this process already drives Void through host views");
	if (voidDriver != VOID_DRIVER_NONE) voidFail("voidRun: this process already runs a Void window");
	voidDriver = VOID_DRIVER_WINDOW;
	s_reqW = w;
	s_reqH = h;
	s_init = init;
	s_frame = frame;
	s_sampleCount = sampleCount;
	VoidLinuxDesc d = {0};
	d.init = _init;
	d.frame = _frame;
	d.event = voidAppWindowEvent;
	d.cleanup = _cleanup;
	d.width = w;
	d.height = h;
	d.sampleCount = sampleCount;
	d.title = voidWindowTitle();
	voidLinuxRun(&d);
}

void voidRequestedSize(int *w, int *h) {
	*w = s_reqW;
	*h = s_reqH;
}

void voidRun(int w, int h, msClosure init, msClosure frame) {
	voidRunConfigured(w, h, 4, 1, init, frame);
}

static VoidLinuxView *s_presented;

static const VoidLinuxView *viewsScreen(void) {
	if (voidCurrentView() == 0 && s_presented) return s_presented;
	return (const VoidLinuxView *)voidViewsCurrentSurface();
}

// The screen pass draws into framebuffer 0 of the window or of the current view's drawable, which
// has no view objects. Outside a view frame it is the view presented last, so a readback sees it.
int32_t voidSwapchainWidth(void) {
	if (voidDriverFor("beginPass") == VOID_DRIVER_VIEWS) return viewsScreen()->w;
	return voidWindowWidth();
}

int32_t voidSwapchainHeight(void) {
	if (voidDriverFor("beginPass") == VOID_DRIVER_VIEWS) return viewsScreen()->h;
	return voidWindowHeight();
}

int32_t voidSwapchainSampleCount(void) { return voidDriver == VOID_DRIVER_VIEWS ? voidViewsSampleCount() : s_sampleCount; }
void *voidSwapchainRenderView(void) { return NULL; }
void *voidSwapchainResolveView(void) { return NULL; }
void *voidSwapchainDepthStencilView(void) { return NULL; }

void voidDriverPresent(void) {
	if (voidDriver == VOID_DRIVER_VIEWS) voidViewsPresent();
	else s_committed = true;
}

void voidPlatformDeviceEnsure(void) {
	if (voidDriver == VOID_DRIVER_WINDOW) voidFail("voidViewCreate: this process already runs an X11 window through voidRun");
	if (voidDriver == VOID_DRIVER_VIEWS) return;
	voidLinuxViewsStart(voidViewsSampleCount());
	voidDriver = VOID_DRIVER_VIEWS;
}

void voidPlatformRunInit(msClosure init) { voidCallClosure(init); }

// The views' GLX config has no depth buffer the door relies on, so the screen pipelines are made
// without depth, as on Android and the D3D11 views.
void *voidPlatformSurfaceCreate(const void *native, int w, int h) {
	VoidLinuxView *v = (VoidLinuxView *)calloc(1, sizeof(VoidLinuxView));
	if (!v) voidFail("voidViewCreate: out of memory for a GLX surface");
	voidLinuxViewInit(v, (unsigned long)(uintptr_t)native, w, h);
	if (!doorValid()) {
		voidLinuxViewMakeCurrent(v);
		doorSetup(NULL, NULL, DOOR_PIXEL_FORMAT_RGBA8, DOOR_PIXEL_FORMAT_NONE, voidViewsSampleCount());
		if (!doorValid()) voidFail("doorSetup on the views' GLX context failed");
	}
	return v;
}

void voidPlatformSurfaceResize(void *surface, int w, int h) {
	voidLinuxViewResize((VoidLinuxView *)surface, w, h);
	if (s_presented == surface) s_presented = NULL;
}

int voidPlatformSurfaceReady(void *surface) { (void)surface; return 1; }

static void lostViews(void) { voidFail("the GL context of the host views was lost; Linux views do not rebuild it"); }

int voidPlatformSurfaceAcquire(void *surface) {
	voidRestoreContextIfLost(lostViews);
	voidLinuxViewMakeCurrent((const VoidLinuxView *)surface);
	return 1;
}

void voidPlatformSurfacePresent(void *surface) {
	voidLinuxViewSwap((const VoidLinuxView *)surface);
	s_presented = (VoidLinuxView *)surface;
}

void voidPlatformSurfaceDestroy(void *surface) {
	if (s_presented == surface) s_presented = NULL;
	voidLinuxViewRelease((VoidLinuxView *)surface);
	free(surface);
}

// The X11 window Void draws into inside the host's, or the pbuffer of a windowless view.
long long voidPlatformSurfaceNative(void *surface) {
	const VoidLinuxView *v = (const VoidLinuxView *)surface;
	return (long long)(v->child ? v->child : v->drawable);
}
