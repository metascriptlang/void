// Void driver — Linux: the X11 window and its GLX context (src/platform/linux/window.c) drive
// voidRun; the GPU door's GL backend (src/webgpu/gl, GL core) draws into framebuffer 0.
// Host views are not offered on Linux, so views.c is not part of this build.

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "backend.h"
#include "bridge.h"
#include "appWindow.h"
#include "../gpu/door.h"
#include "../platform/swapchain.h"
#include "../platform/linux/window.h"
#ifdef VOID_PROFILER
#include "../void2d/frameClock.h"
#endif

void voidDriverPresent(void);
__attribute__((noreturn)) void voidFail(const char *fmt, ...);

void voidFail(const char *fmt, ...) {
	va_list args;
	va_start(args, fmt);
	fprintf(stderr, "void: ");
	vfprintf(stderr, fmt, args);
	fprintf(stderr, "\n");
	va_end(args);
	fflush(stderr);
	abort();
}

static bool s_running;
static msClosure s_init;
static msClosure s_frame;
static bool s_keys[VOID_KEY_COUNT];
static int s_reqW = 0;
static int s_reqH = 0;
static int s_sampleCount;
static bool s_committed;

static int s_generation = 1;
static int s_contextLost = 0;

static void setupDoor(void) {
	doorSetup(NULL, NULL, DOOR_PIXEL_FORMAT_RGBA8, DOOR_PIXEL_FORMAT_DEPTH, s_sampleCount);
	if (!doorValid()) voidFail("doorSetup on the GLX context failed");
}

int voidGpuGeneration(void) { return s_generation; }
void voidLoseContext(void) { s_contextLost = 1; }

static void restoreContext(void) {
	doorShutdown();
	setupDoor();
	s_generation++;
	s_contextLost = 0;
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
	if (s_contextLost) restoreContext();
	s_committed = false;
	voidCallClosure(s_frame);
	if (s_committed) voidLinuxSwapBuffers();
}

static void _event(const VoidAppEvent *e) {
#ifdef VOID_PROFILER
	if (e->type == VOID_EVENT_KEY_DOWN || e->type == VOID_EVENT_KEY_UP
		|| e->type == VOID_EVENT_CHAR || e->type == VOID_EVENT_MOUSE_DOWN
		|| e->type == VOID_EVENT_MOUSE_UP || e->type == VOID_EVENT_MOUSE_SCROLL) {
		voidProfileInput();
	}
#endif
	if (e->type == VOID_EVENT_KEY_DOWN) s_keys[e->keyCode] = true;
	else if (e->type == VOID_EVENT_KEY_UP) s_keys[e->keyCode] = false;
	if (voidAppDeliver(e)) return;
	if (e->type == VOID_EVENT_KEY_DOWN && e->keyCode == VOID_KEY_ESCAPE) voidLinuxRequestQuit();
}

static void _cleanup(void) { doorShutdown(); }

// highDpi is not read: sokol_app on X11 always maps window pixels 1:1 to the framebuffer and
// scales by Xft.dpi (sokol_app.h :14299).
void voidRunConfigured(int w, int h, int sampleCount, int highDpi, msClosure init, msClosure frame) {
	(void)highDpi;
	if (s_running) voidFail("voidRun: this process already runs a Void window");
	s_running = true;
	s_reqW = w;
	s_reqH = h;
	s_init = init;
	s_frame = frame;
	s_sampleCount = sampleCount;
	VoidLinuxDesc d = {0};
	d.init = _init;
	d.frame = _frame;
	d.event = _event;
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

static void requireWindow(const char *op) {
	if (!voidLinuxValid()) voidFail("%s before voidRun made the window", op);
}

void voidGfxSetup(void) {
	requireWindow("gfxSetup");
	setupDoor();
}

int voidFbWidth(void) {
	requireWindow("fbWidth");
	return voidLinuxWidth();
}

int voidFbHeight(void) {
	requireWindow("fbHeight");
	return voidLinuxHeight();
}

float voidDpiScale(void) {
	requireWindow("dpiScale");
	return voidLinuxDpiScale();
}

int voidKeyDown(int keycode) {
	if (keycode < 0 || keycode >= VOID_KEY_COUNT) return 0;
	return s_keys[keycode] ? 1 : 0;
}

// The screen pass draws into the window's framebuffer 0, which has no view objects.
int32_t voidSwapchainWidth(void) {
	requireWindow("beginPass");
	return voidLinuxWidth();
}

int32_t voidSwapchainHeight(void) {
	requireWindow("beginPass");
	return voidLinuxHeight();
}

int32_t voidSwapchainSampleCount(void) { return s_sampleCount; }
void *voidSwapchainRenderView(void) { return NULL; }
void *voidSwapchainResolveView(void) { return NULL; }
void *voidSwapchainDepthStencilView(void) { return NULL; }

void voidDriverPresent(void) { s_committed = true; }
