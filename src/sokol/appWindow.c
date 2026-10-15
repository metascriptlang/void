// The sokol_app window's app-facing half, shared by the window drivers (bridgeWin.c and
// bridgeWeb.c): the event closure with its getters.

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>

#include "backend.h"
#include "bridge.h"
#include "appWindow.h"

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

void voidSetEventHandler(msClosure handler) { s_handler = handler; }

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
