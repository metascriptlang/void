// The window's app-facing half, shared by the window drivers (bridgeWin.c and bridgeWeb.c):
// the event closure with its getters, the IME events, and the title.

#if defined(__EMSCRIPTEN__)
#include "../platform/web/window.h"
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
#else
	if (voidWin32Valid()) voidWin32SetTitle(s_title);
#endif
}

const char *voidWindowTitle(void) { return s_title; }
int voidWindowTitleSet(void) { return s_titleSet ? 1 : 0; }
