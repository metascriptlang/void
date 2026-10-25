// Void driver — dummy: no window and no GPU. voidRun calls init once and then frame
// VOID_DUMMY_FRAMES times (1 when unset) or until voidRequestQuit, over the GPU door's dummy
// backend (src/webgpu/dummy) at the size voidRunConfigured asked for.

#include <stdarg.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "backend.h"
#include "bridge.h"
#include "views.h"
#include "../gpu/door.h"
#include "../platform/swapchain.h"
#include "../platform/windowCore.h"

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

VoidWindow voidWindow;

static int s_reqW = 0;
static int s_reqH = 0;
static int s_sampleCount = 1;
static int s_generation = 1;
static int s_contextLost = 0;
static msClosure s_pump;

static void needWindow(const char *what) {
	if (!voidWindow.valid) voidFail("%s: the window does not exist yet; call it from the event handler or after init", what);
}

static int frameCount(void) {
	const char *text = getenv("VOID_DUMMY_FRAMES");
	if (text == NULL || text[0] == '\0') return 1;
	char *end = NULL;
	long count = strtol(text, &end, 10);
	if (*end != '\0' || count < 1 || count > 1000000) {
		voidFail("VOID_DUMMY_FRAMES '%s' is not a frame count from 1 to 1000000", text);
	}
	return (int)count;
}

static void setupDoor(void) {
	doorSetup(NULL, NULL, DOOR_PIXEL_FORMAT_RGBA8, DOOR_PIXEL_FORMAT_DEPTH, s_sampleCount);
	if (!doorValid()) voidFail("doorSetup on the dummy backend failed");
}

int voidGpuGeneration(void) { return s_generation; }
void voidLoseContext(void) { s_contextLost = 1; }

static void restoreContext(void) {
	doorShutdown();
	setupDoor();
	s_generation++;
	s_contextLost = 0;
}

void voidRunConfigured(int w, int h, int sampleCount, int highDpi, msClosure init, msClosure frame) {
	(void)highDpi;
	if (voidWindow.valid) voidFail("voidRun: this process already runs a Void window");
	if (w <= 0 || h <= 0) voidFail("voidRun: the dummy swapchain needs a positive size, not %dx%d", w, h);
	if (sampleCount != 1 && sampleCount != 4) voidFail("voidRunConfigured: sampleCount %d is not 1 or 4", sampleCount);
	int frames = frameCount();
	voidWindowStart(NULL, NULL, NULL, NULL, w, h);
	voidWindow.valid = true;
	s_reqW = w;
	s_reqH = h;
	s_sampleCount = sampleCount;
	voidCallClosure(init);
	for (int i = 0; i < frames && !voidWindow.quitRequested; i++) {
		if (s_contextLost) restoreContext();
		voidCallClosure(frame);
	}
	if (doorValid()) doorShutdown();
	voidWindowEnd();
}

void voidRequestedSize(int *w, int *h) {
	*w = s_reqW;
	*h = s_reqH;
}

void voidRun(int w, int h, msClosure init, msClosure frame) {
	voidRunConfigured(w, h, 4, 1, init, frame);
}

void voidGfxSetup(void) {
	needWindow("gfxSetup");
	setupDoor();
}

int voidFbWidth(void) {
	needWindow("fbWidth");
	return s_reqW;
}

int voidFbHeight(void) {
	needWindow("fbHeight");
	return s_reqH;
}

float voidDpiScale(void) {
	needWindow("dpiScale");
	return 1.0f;
}

int voidKeyDown(int keycode) {
	(void)keycode;
	return 0;
}

int32_t voidSwapchainWidth(void) {
	needWindow("beginPass");
	return s_reqW;
}

int32_t voidSwapchainHeight(void) {
	needWindow("beginPass");
	return s_reqH;
}

int32_t voidSwapchainSampleCount(void) { return s_sampleCount; }
void *voidSwapchainRenderView(void) { return NULL; }
void *voidSwapchainResolveView(void) { return NULL; }
void *voidSwapchainDepthStencilView(void) { return NULL; }

void voidDriverPresent(void) {}

void voidWindowSetTitle(const char *title) { (void)title; }

void voidWindowSetClipboard(const char *utf8) {
	char *copy = strdup(utf8);
	if (copy == NULL) voidFail("strdup for the clipboard");
	free(voidWindow.clipboard);
	voidWindow.clipboard = copy;
}

const char *voidWindowClipboard(void) { return voidWindow.clipboard ? voidWindow.clipboard : ""; }
void voidWindowSetCursor(int cursor) { voidWindow.mouse.cursor = cursor; }
void voidWindowShowMouse(bool shown) { voidWindow.mouse.shown = shown; }
void voidWindowLockMouse(bool locked) { voidWindow.mouse.locked = locked; }
void voidWindowToggleFullscreen(void) { voidWindow.fullscreen = !voidWindow.fullscreen; }

void voidSetTextInput(int on) { (void)on; }
void voidSetImeRect(int x, int y, int w, int h) {
	(void)x;
	(void)y;
	(void)w;
	(void)h;
}

void voidEmbedSetMessagePump(msClosure pump) { s_pump = pump; }
