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
#include "appText.h"
#include "views.h"
#include "../gpu/door.h"
#include "../platform/appEvent.h"
#include "../platform/swapchain.h"

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
static bool s_quit;
static int s_reqW = 0;
static int s_reqH = 0;
static int s_sampleCount = 1;
static int s_generation = 1;
static int s_contextLost = 0;
static char s_title[256] = "Void — dummy";
static char s_clipboard[4096] = "";
static int s_cursor = VOID_CURSOR_DEFAULT;
static bool s_mouseShown = true;
static bool s_mouseLocked = false;
static bool s_fullscreen = false;
static msClosure s_handler;
static msClosure s_pump;

static void needWindow(const char *what) {
	if (!s_running) voidFail("%s: the window does not exist yet; call it from the event handler or after init", what);
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
	if (s_running) voidFail("voidRun: this process already runs a Void window");
	if (w <= 0 || h <= 0) voidFail("voidRun: the dummy swapchain needs a positive size, not %dx%d", w, h);
	if (sampleCount != 1 && sampleCount != 4) voidFail("voidRunConfigured: sampleCount %d is not 1 or 4", sampleCount);
	int frames = frameCount();
	s_running = true;
	s_reqW = w;
	s_reqH = h;
	s_sampleCount = sampleCount;
	voidCallClosure(init);
	for (int i = 0; i < frames && !s_quit; i++) {
		if (s_contextLost) restoreContext();
		voidCallClosure(frame);
	}
	if (doorValid()) doorShutdown();
	s_running = false;
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

void voidSetEventHandler(msClosure handler) { s_handler = handler; }

static void noEvent(const char *field) {
	voidFail("voidEvent%s: read outside the event handler voidSetEventHandler registered", field);
}

int voidEventType(void) { noEvent("Type"); return 0; }
int voidEventKeyCode(void) { noEvent("KeyCode"); return 0; }
uint32_t voidEventCharCode(void) { noEvent("CharCode"); return 0; }
int voidEventKeyRepeat(void) { noEvent("KeyRepeat"); return 0; }
uint32_t voidEventModifiers(void) { noEvent("Modifiers"); return 0; }
int voidEventMouseButton(void) { noEvent("MouseButton"); return 0; }
float voidEventMouseX(void) { noEvent("MouseX"); return 0; }
float voidEventMouseY(void) { noEvent("MouseY"); return 0; }
float voidEventMouseDx(void) { noEvent("MouseDx"); return 0; }
float voidEventMouseDy(void) { noEvent("MouseDy"); return 0; }
float voidEventScrollX(void) { noEvent("ScrollX"); return 0; }
float voidEventScrollY(void) { noEvent("ScrollY"); return 0; }
int voidEventFramebufferWidth(void) { noEvent("FramebufferWidth"); return 0; }
int voidEventFramebufferHeight(void) { noEvent("FramebufferHeight"); return 0; }
int voidEventCursor(void) { noEvent("Cursor"); return 0; }
int voidEventTouchCount(void) { noEvent("TouchCount"); return 0; }
int64_t voidEventTouchId(int index) { (void)index; noEvent("TouchId"); return 0; }
float voidEventTouchX(int index) { (void)index; noEvent("TouchX"); return 0; }
float voidEventTouchY(int index) { (void)index; noEvent("TouchY"); return 0; }
int voidEventTouchChanged(int index) { (void)index; noEvent("TouchChanged"); return 0; }
msString voidEventText(void) { noEvent("Text"); return MS_EMPTY_STRING; }

float voidSafeAreaTop(void) { return 0; }
float voidSafeAreaLeft(void) { return 0; }
float voidSafeAreaBottom(void) { return 0; }
float voidSafeAreaRight(void) { return 0; }
float voidKeyboardHeight(void) { return 0; }

void voidSetWindowTitle(const char *title) {
	if (strlen(title) >= sizeof s_title) {
		voidFail("voidSetWindowTitle: the title is %d bytes; at most %d fit", (int)strlen(title), (int)sizeof s_title - 1);
	}
	strcpy(s_title, title);
}

void voidRequestQuit(void) {
	needWindow("voidRequestQuit");
	s_quit = true;
}

void voidCancelQuit(void) {
	needWindow("voidCancelQuit");
	s_quit = false;
}

double voidFrameDuration(void) {
	needWindow("voidFrameDuration");
	return 1.0 / 60.0;
}

void voidSetClipboard(const char *utf8) {
	needWindow("voidSetClipboard");
	if (strlen(utf8) >= sizeof s_clipboard) {
		voidFail("voidSetClipboard: the text is %d bytes; the dummy clipboard holds %d", (int)strlen(utf8), (int)sizeof s_clipboard - 1);
	}
	strcpy(s_clipboard, utf8);
}

msString voidClipboard(void) {
	needWindow("voidClipboard");
	if (s_clipboard[0] == '\0') return MS_EMPTY_STRING;
	return msStringFromCStr(s_clipboard);
}

void voidSetMouseCursor(int cursor) {
	needWindow("voidSetMouseCursor");
	if (cursor < 0 || cursor >= VOID_CURSOR_COUNT) {
		voidFail("voidSetMouseCursor: cursor %d is not a VoidMouseCursor (0..%d)", cursor, VOID_CURSOR_COUNT - 1);
	}
	s_cursor = cursor;
}

int voidMouseCursor(void) {
	needWindow("voidMouseCursor");
	return s_cursor;
}

void voidShowMouse(int shown) {
	needWindow("voidShowMouse");
	s_mouseShown = shown != 0;
}

int voidMouseShown(void) {
	needWindow("voidMouseShown");
	return s_mouseShown ? 1 : 0;
}

void voidLockMouse(int locked) {
	needWindow("voidLockMouse");
	s_mouseLocked = locked != 0;
}

int voidMouseLocked(void) {
	needWindow("voidMouseLocked");
	return s_mouseLocked ? 1 : 0;
}

void voidToggleFullscreen(void) {
	needWindow("voidToggleFullscreen");
	s_fullscreen = !s_fullscreen;
}

int voidIsFullscreen(void) {
	needWindow("voidIsFullscreen");
	return s_fullscreen ? 1 : 0;
}

int voidDroppedFileCount(void) {
	needWindow("voidDroppedFileCount");
	return 0;
}

msString voidDroppedFilePath(int i) {
	needWindow("voidDroppedFilePath");
	voidFail("voidDroppedFilePath: index %d of 0 dropped files", i);
}

void voidSetTextInput(int on) { (void)on; }
void voidSetImeRect(int x, int y, int w, int h) {
	(void)x;
	(void)y;
	(void)w;
	(void)h;
}

void voidEmbedSetMessagePump(msClosure pump) { s_pump = pump; }
