// The window's app-facing half, shared by the window drivers (bridgeWin.c, bridgeLinux.c,
// bridgeWeb.c and bridgeIosApp.m): the event closure with its getters, the IME events, and the title.

#if defined(__EMSCRIPTEN__)
#include "../platform/web/window.h"
#elif defined(__APPLE__)
#include "iosApp.h"
#elif defined(__linux__)
#include "../platform/linux/window.h"
#else
#include "../platform/win32/window.h"
#endif
#include <stdarg.h>
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "backend.h"
#include "bridge.h"
#include "appWindow.h"
#include "appText.h"

__attribute__((noreturn)) static void fail(const char *fmt, ...) {
	va_list args;
	va_start(args, fmt);
	fputs("void: ", stderr);
	vfprintf(stderr, fmt, args);
	fputc('\n', stderr);
	va_end(args);
	abort();
}

static msClosure s_handler;
static const VoidAppEvent *s_event;

static const char *s_text = "";
static int s_cursor = 0;

void voidSetEventHandler(msClosure handler) { s_handler = handler; }
int voidAppEventHandlerSet(void) { return s_handler.fn != NULL; }

int voidAppDeliver(const VoidAppEvent *e) {
	if (!s_handler.fn) return 0;
	s_event = e;
	if (s_handler.env) ((void (*)(void *))s_handler.fn)(s_handler.env);
	else ((void (*)(void))s_handler.fn)();
	s_event = NULL;
	return 1;
}

static const VoidAppEvent *current(const char *field) {
	if (!s_event) fail("voidEvent%s: read outside the event handler voidSetEventHandler registered", field);
	return s_event;
}

int voidEventType(void) { return (int)current("Type")->type; }
int voidEventKeyCode(void) { return (int)current("KeyCode")->keyCode; }
uint32_t voidEventCharCode(void) { return current("CharCode")->charCode; }
int voidEventKeyRepeat(void) { return current("KeyRepeat")->keyRepeat ? 1 : 0; }
uint32_t voidEventModifiers(void) { return current("Modifiers")->modifiers; }
int voidEventMouseButton(void) { return (int)current("MouseButton")->mouseButton; }
float voidEventMouseX(void) { return current("MouseX")->mouseX; }
float voidEventMouseY(void) { return current("MouseY")->mouseY; }
float voidEventMouseDx(void) { return current("MouseDx")->mouseDx; }
float voidEventMouseDy(void) { return current("MouseDy")->mouseDy; }
float voidEventScrollX(void) { return current("ScrollX")->scrollX; }
float voidEventScrollY(void) { return current("ScrollY")->scrollY; }
int voidEventFramebufferWidth(void) { return current("FramebufferWidth")->framebufferWidth; }
int voidEventFramebufferHeight(void) { return current("FramebufferHeight")->framebufferHeight; }
static const VoidTouchPoint *touchAt(const char *field, int index) {
	const VoidAppEvent *e = current(field);
	if (index < 0 || index >= e->touchCount) fail("voidEvent%s(%d): the event has %d touch points", field, index, e->touchCount);
	return &e->touches[index];
}

int voidEventTouchCount(void) { return current("TouchCount")->touchCount; }
int64_t voidEventTouchId(int index) { return (int64_t)touchAt("TouchId", index)->identifier; }
float voidEventTouchX(int index) { return touchAt("TouchX", index)->x; }
float voidEventTouchY(int index) { return touchAt("TouchY", index)->y; }
int voidEventTouchChanged(int index) { return touchAt("TouchChanged", index)->changed ? 1 : 0; }

static float s_safeTop, s_safeLeft, s_safeBottom, s_safeRight;

void voidAppSetSafeArea(float top, float left, float bottom, float right) {
	s_safeTop = top;
	s_safeLeft = left;
	s_safeBottom = bottom;
	s_safeRight = right;
}

float voidSafeAreaTop(void) { return s_safeTop; }
float voidSafeAreaLeft(void) { return s_safeLeft; }
float voidSafeAreaBottom(void) { return s_safeBottom; }
float voidSafeAreaRight(void) { return s_safeRight; }

static float s_keyboard;

void voidAppSetKeyboard(float height) { s_keyboard = height; }
float voidKeyboardHeight(void) { return s_keyboard; }

int voidEventCursor(void) {
	current("Cursor");
	return s_cursor;
}

msString voidEventText(void) {
	current("Text");
	if (s_text[0] == '\0') {
		msString empty;
		empty.len = 0;
		empty.p = NULL;
		return empty;
	}
	return msStringFromCStr(s_text);
}

void voidAppTextDeliver(int type, const char *utf8, int cursor) {
	VoidAppEvent e;
	memset(&e, 0, sizeof e);
	e.type = (VoidAppEventType)type;
#if defined(__EMSCRIPTEN__)
	e.frameCount = voidWebFrameCount();
	e.framebufferWidth = voidWebWidth();
	e.framebufferHeight = voidWebHeight();
#elif defined(__APPLE__)
	e.frameCount = voidIosFrameCount();
	e.framebufferWidth = voidIosWidth();
	e.framebufferHeight = voidIosHeight();
#elif defined(__linux__)
	e.frameCount = voidLinuxFrameCount();
	e.framebufferWidth = voidLinuxWidth();
	e.framebufferHeight = voidLinuxHeight();
#else
	e.frameCount = voidWin32FrameCount();
	e.framebufferWidth = voidWin32Width();
	e.framebufferHeight = voidWin32Height();
#endif
	s_text = utf8;
	s_cursor = cursor;
	voidAppDeliver(&e);
	s_text = "";
	s_cursor = 0;
}

static char s_title[256] = "Void — sokol";
static bool s_titleSet = false;

void voidSetWindowTitle(const char *title) {
	if (strlen(title) >= sizeof s_title) fail("voidSetWindowTitle: the title is %d bytes; at most %d fit", (int)strlen(title), (int)sizeof s_title - 1);
	strcpy(s_title, title);
	s_titleSet = true;
#if defined(__EMSCRIPTEN__)
	if (voidWebValid()) voidWebSetTitle(s_title);
#elif defined(__APPLE__)
#elif defined(__linux__)
	if (voidLinuxValid()) voidLinuxSetTitle(s_title);
#else
	if (voidWin32Valid()) voidWin32SetTitle(s_title);
#endif
}

const char *voidWindowTitle(void) { return s_title; }
int voidWindowTitleSet(void) { return s_titleSet ? 1 : 0; }

#if defined(__EMSCRIPTEN__)
#define PLATFORM(name) voidWeb##name
#elif defined(__linux__)
#define PLATFORM(name) voidLinux##name
#elif defined(__APPLE__)
#define PLATFORM(name) voidIos##name
__attribute__((noreturn)) static void notPortedIos(const char *feature) { fail("%s is not ported to iOS yet (src/sokol/appWindow.c)", feature); }
static void voidIosRequestQuit(void) { notPortedIos("voidRequestQuit"); }
static void voidIosCancelQuit(void) { notPortedIos("voidCancelQuit"); }
static double voidIosFrameDuration(void) { notPortedIos("voidFrameDuration"); }
static void voidIosSetClipboard(const char *utf8) { (void)utf8; notPortedIos("the clipboard"); }
static const char *voidIosClipboard(void) { notPortedIos("the clipboard"); }
static void voidIosSetCursor(int cursor) { (void)cursor; notPortedIos("the mouse cursor"); }
static int voidIosCursor(void) { notPortedIos("the mouse cursor"); }
static void voidIosShowMouse(bool shown) { (void)shown; notPortedIos("showing and hiding the mouse"); }
static bool voidIosMouseShown(void) { notPortedIos("showing and hiding the mouse"); }
static void voidIosLockMouse(bool locked) { (void)locked; notPortedIos("the mouse lock"); }
static bool voidIosMouseLocked(void) { notPortedIos("the mouse lock"); }
static void voidIosToggleFullscreen(void) { notPortedIos("fullscreen"); }
static bool voidIosIsFullscreen(void) { notPortedIos("fullscreen"); }
static int voidIosDroppedCount(void) { notPortedIos("dropped files"); }
static const char *voidIosDroppedPath(int i) { (void)i; notPortedIos("dropped files"); }
#else
#define PLATFORM(name) voidWin32##name
#endif

static void needWindow(const char *what) {
	if (!PLATFORM(Valid)()) fail("%s: the window does not exist yet; call it from the event handler or after init", what);
}

void voidRequestQuit(void) {
	needWindow("voidRequestQuit");
	PLATFORM(RequestQuit)();
}

void voidCancelQuit(void) {
	needWindow("voidCancelQuit");
	PLATFORM(CancelQuit)();
}

double voidFrameDuration(void) {
	needWindow("voidFrameDuration");
	return PLATFORM(FrameDuration)();
}

void voidSetClipboard(const char *utf8) {
	needWindow("voidSetClipboard");
	PLATFORM(SetClipboard)(utf8);
}

msString voidClipboard(void) {
	needWindow("voidClipboard");
	const char *text = PLATFORM(Clipboard)();
	if (text[0] == '\0') {
		msString empty;
		empty.len = 0;
		empty.p = NULL;
		return empty;
	}
	return msStringFromCStr(text);
}

void voidSetMouseCursor(int cursor) {
	needWindow("voidSetMouseCursor");
	if (cursor < 0 || cursor >= VOID_CURSOR_COUNT) fail("voidSetMouseCursor: cursor %d is not a VoidMouseCursor (0..%d)", cursor, VOID_CURSOR_COUNT - 1);
	PLATFORM(SetCursor)(cursor);
}

int voidMouseCursor(void) {
	needWindow("voidMouseCursor");
	return PLATFORM(Cursor)();
}

void voidShowMouse(int shown) {
	needWindow("voidShowMouse");
	PLATFORM(ShowMouse)(shown != 0);
}

int voidMouseShown(void) {
	needWindow("voidMouseShown");
	return PLATFORM(MouseShown)() ? 1 : 0;
}

void voidLockMouse(int locked) {
	needWindow("voidLockMouse");
	PLATFORM(LockMouse)(locked != 0);
}

int voidMouseLocked(void) {
	needWindow("voidMouseLocked");
	return PLATFORM(MouseLocked)() ? 1 : 0;
}

void voidToggleFullscreen(void) {
	needWindow("voidToggleFullscreen");
	PLATFORM(ToggleFullscreen)();
}

int voidIsFullscreen(void) {
	needWindow("voidIsFullscreen");
	return PLATFORM(IsFullscreen)() ? 1 : 0;
}

int voidDroppedFileCount(void) {
	needWindow("voidDroppedFileCount");
	return PLATFORM(DroppedCount)();
}

msString voidDroppedFilePath(int i) {
	needWindow("voidDroppedFilePath");
	if (i < 0 || i >= PLATFORM(DroppedCount)()) fail("voidDroppedFilePath: index %d of %d dropped files", i, PLATFORM(DroppedCount)());
	return msStringFromCStr(PLATFORM(DroppedPath)(i));
}

