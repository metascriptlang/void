// Void driver — Linux: the X11 window and its GLX or EGL context (src/platform/linux/window.c)
// drive voidRun; the GPU door's GL backend (src/webgpu/gl, GL core or GLES3) draws into
// framebuffer 0.
// Host views are not offered on Linux, so views.ms is not part of this build.

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

void voidDriverPresent(void);

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

// The screen pass draws into the window's framebuffer 0, which has no view objects.
int32_t voidSwapchainWidth(void) {
	voidDriverFor("beginPass");
	return voidWindowWidth();
}

int32_t voidSwapchainHeight(void) {
	voidDriverFor("beginPass");
	return voidWindowHeight();
}

int32_t voidSwapchainSampleCount(void) { return s_sampleCount; }
void *voidSwapchainRenderView(void) { return NULL; }
void *voidSwapchainResolveView(void) { return NULL; }
void *voidSwapchainDepthStencilView(void) { return NULL; }

void voidDriverPresent(void) { s_committed = true; }
