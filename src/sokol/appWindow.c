// The sokol_app window's app-facing half, shared by the window drivers (bridgeWin.c,
// bridgeWeb.c and bridgeIosApp.m): the event closure with its getters, the IME events, and the title.

#if defined(__EMSCRIPTEN__)
#include <emscripten.h>
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

_Static_assert(VOID_EVENT_PREEDIT == _SAPP_EVENTTYPE_NUM, "sokol_app added event types: renumber VOID_EVENT_* and AppEventType in window.ms");

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
static const sapp_event *s_event;

static const char *s_text = "";
static int s_cursor = 0;

void voidSetEventHandler(msClosure handler) { s_handler = handler; }
int voidAppEventHandlerSet(void) { return s_handler.fn != NULL; }

int voidAppEventDeliver(const sapp_event *e) {
	if (!s_handler.fn) return 0;
	s_event = e;
	if (s_handler.env) ((void (*)(void *))s_handler.fn)(s_handler.env);
	else ((void (*)(void))s_handler.fn)();
	s_event = NULL;
	return 1;
}

static const sapp_event *current(const char *field) {
	if (!s_event) fail("voidEvent%s: read outside the event handler voidSetEventHandler registered", field);
	return s_event;
}

int voidEventType(void) { return (int)current("Type")->type; }
int voidEventKeyCode(void) { return (int)current("KeyCode")->key_code; }
uint32_t voidEventCharCode(void) { return current("CharCode")->char_code; }
int voidEventKeyRepeat(void) { return current("KeyRepeat")->key_repeat ? 1 : 0; }
uint32_t voidEventModifiers(void) { return current("Modifiers")->modifiers; }
int voidEventMouseButton(void) { return (int)current("MouseButton")->mouse_button; }
float voidEventMouseX(void) { return current("MouseX")->mouse_x; }
float voidEventMouseY(void) { return current("MouseY")->mouse_y; }
float voidEventMouseDx(void) { return current("MouseDx")->mouse_dx; }
float voidEventMouseDy(void) { return current("MouseDy")->mouse_dy; }
float voidEventScrollX(void) { return current("ScrollX")->scroll_x; }
float voidEventScrollY(void) { return current("ScrollY")->scroll_y; }
int voidEventFramebufferWidth(void) { return current("FramebufferWidth")->framebuffer_width; }
int voidEventFramebufferHeight(void) { return current("FramebufferHeight")->framebuffer_height; }
static const sapp_touchpoint *touchAt(const char *field, int index) {
	const sapp_event *e = current(field);
	if (index < 0 || index >= e->num_touches) fail("voidEvent%s(%d): the event has %d touch points", field, index, e->num_touches);
	return &e->touches[index];
}

int voidEventTouchCount(void) { return current("TouchCount")->num_touches; }
int64_t voidEventTouchId(int index) { return (int64_t)touchAt("TouchId", index)->identifier; }
float voidEventTouchX(int index) { return touchAt("TouchX", index)->pos_x; }
float voidEventTouchY(int index) { return touchAt("TouchY", index)->pos_y; }
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
	sapp_event e;
	memset(&e, 0, sizeof e);
	e.type = (sapp_event_type)type;
	e.frame_count = sapp_frame_count();
	e.framebuffer_width = sapp_width();
	e.framebuffer_height = sapp_height();
	s_text = utf8;
	s_cursor = cursor;
	voidAppEventDeliver(&e);
	s_text = "";
	s_cursor = 0;
}

static char s_title[256] = "Void — sokol";
static bool s_titleSet = false;

#if defined(__EMSCRIPTEN__)
EM_JS(void, voidJsSetDocumentTitle, (const char *title), {
	document.title = UTF8ToString(Number(title));
});
#endif

void voidSetWindowTitle(const char *title) {
	if (strlen(title) >= sizeof s_title) fail("voidSetWindowTitle: the title is %d bytes; at most %d fit", (int)strlen(title), (int)sizeof s_title - 1);
	strcpy(s_title, title);
	s_titleSet = true;
	if (!sapp_isvalid()) return;
#if defined(__EMSCRIPTEN__)
	voidJsSetDocumentTitle(s_title);
#else
	sapp_set_window_title(s_title);
#endif
}

const char *voidWindowTitle(void) { return s_title; }
int voidWindowTitleSet(void) { return s_titleSet ? 1 : 0; }

static int s_presentMode = 0;

void voidSetPresentMode(int mode) {
	if (mode != 0 && mode != 1) fail("voidSetPresentMode: %d is neither 0 (AutoVsync) nor 1 (AutoNoVsync)", mode);
	if (sapp_isvalid()) fail("voidSetPresentMode: the window already presents; set the mode before voidRun");
	s_presentMode = mode;
}

int voidPresentMode(void) { return s_presentMode; }
