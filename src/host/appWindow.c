// The window's app-facing half, shared by the window drivers (bridgeWin.c, bridgeLinux.c,
// bridgeWeb.c, bridgeEmbed.m, bridgeIosApp.m, bridgeAndroidApp.c and bridgeDummy.c): the event
// closure with its getters, the IME events, and the title.

#include "appWindow.h"

#if defined(VOID_ANDROID_APP)
#include "androidApp.h"
#define PLATFORM(name) voidAndroid##name
#elif defined(VOID_IOS_APP)
#include "iosApp.h"
#define PLATFORM(name) voidIos##name
#else
#include "../platform/windowCore.h"
#define PLATFORM(name) voidWindow##name
#endif
#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "backend.h"
#include "bridge.h"
#include "appText.h"
#ifdef VOID_PROFILER
#include "../void2d/frameClock.h"
#endif

static msClosure s_handler;
static const VoidAppEvent *s_event;

static const char *s_text = "";
static int s_cursor = 0;

void voidSetEventHandler(msClosure handler) { s_handler = handler; }
int voidAppEventHandlerSet(void) { return s_handler.fn != NULL; }

int voidAppDeliver(const VoidAppEvent *e) {
	if (!s_handler.fn) return 0;
	s_event = e;
	voidCallClosure(s_handler);
	s_event = NULL;
	return 1;
}

#if !defined(VOID_ANDROID_APP) && !defined(VOID_IOS_APP)
void voidAppWindowEvent(const VoidAppEvent *e) {
#ifdef VOID_PROFILER
	if (e->type == VOID_EVENT_KEY_DOWN || e->type == VOID_EVENT_KEY_UP
		|| e->type == VOID_EVENT_CHAR || e->type == VOID_EVENT_MOUSE_DOWN
		|| e->type == VOID_EVENT_MOUSE_UP || e->type == VOID_EVENT_MOUSE_SCROLL) {
		voidProfileInput();
	}
#endif
	if (voidAppDeliver(e)) return;
	if (e->type == VOID_EVENT_KEY_DOWN && e->keyCode == VOID_KEY_ESCAPE) voidWindowRequestQuit();
}
#endif

static const VoidAppEvent *current(const char *field) {
	if (!s_event) voidFail("voidEvent%s: read outside the event handler voidSetEventHandler registered", field);
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
	if (index < 0 || index >= e->touchCount) voidFail("voidEvent%s(%d): the event has %d touch points", field, index, e->touchCount);
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

static msString stringOrEmpty(const char *text) {
	if (text[0] != '\0') return msStringFromCStr(text);
	msString empty;
	empty.len = 0;
	empty.p = NULL;
	return empty;
}

msString voidEventText(void) {
	current("Text");
	return stringOrEmpty(s_text);
}

void voidAppTextDeliver(int type, const char *utf8, int cursor) {
	VoidAppEvent e;
	memset(&e, 0, sizeof e);
	e.type = (VoidAppEventType)type;
	e.frameCount = PLATFORM(FrameCount)();
	e.framebufferWidth = PLATFORM(Width)();
	e.framebufferHeight = PLATFORM(Height)();
	s_text = utf8;
	s_cursor = cursor;
	voidAppDeliver(&e);
	s_text = "";
	s_cursor = 0;
}

static char s_title[256] = "Void";
static bool s_titleSet = false;

void voidSetWindowTitle(const char *title) {
	if (strlen(title) >= sizeof s_title) voidFail("voidSetWindowTitle: the title is %d bytes; at most %d fit", (int)strlen(title), (int)sizeof s_title - 1);
	strcpy(s_title, title);
	s_titleSet = true;
#if !defined(VOID_ANDROID_APP) && !defined(VOID_IOS_APP)
	if (voidWindowValid()) voidWindowSetTitle(s_title);
#endif
}

const char *voidWindowTitle(void) { return s_title; }
int voidWindowTitleSet(void) { return s_titleSet ? 1 : 0; }

static int s_presentMode = 0;

void voidSetPresentMode(int mode) {
	if (mode != 0 && mode != 1) voidFail("voidSetPresentMode: %d is neither 0 (AutoVsync) nor 1 (AutoNoVsync)", mode);
	if (PLATFORM(Valid)()) voidFail("voidSetPresentMode: the window already presents; set the mode before voidRun");
	s_presentMode = mode;
}

int voidPresentMode(void) { return s_presentMode; }

#if defined(VOID_ANDROID_APP) || defined(VOID_IOS_APP)
#include <unistd.h>
#include "views.h"

#define CLIPBOARD_SIZE 8192
static char s_clipboard[CLIPBOARD_SIZE];
static int s_mouseCursor = 0;
static bool s_mouseShown = true;
static bool s_mouseLocked = false;
#if defined(VOID_IOS_APP)
static void PLATFORM(RequestQuit)(void) {}
#endif
static void PLATFORM(CancelQuit)(void) {}
static void PLATFORM(SetClipboard)(const char *utf8) {
	if (strlen(utf8) >= sizeof s_clipboard) voidFail("voidSetClipboard: the clipboard holds at most %d bytes; got %d", (int)sizeof s_clipboard - 1, (int)strlen(utf8));
	strcpy(s_clipboard, utf8);
}
static const char *PLATFORM(Clipboard)(void) { return s_clipboard; }
static void PLATFORM(SetCursor)(int cursor) { s_mouseCursor = cursor; }
static int PLATFORM(Cursor)(void) { return s_mouseCursor; }
static void PLATFORM(ShowMouse)(bool shown) { s_mouseShown = shown; }
static bool PLATFORM(MouseShown)(void) { return s_mouseShown; }
static void PLATFORM(LockMouse)(bool locked) { s_mouseLocked = locked; }
static bool PLATFORM(MouseLocked)(void) { return s_mouseLocked; }
static void PLATFORM(ToggleFullscreen)(void) {}
static bool PLATFORM(IsFullscreen)(void) { return false; }
static int PLATFORM(DroppedCount)(void) { return 0; }
static const char *PLATFORM(DroppedPath)(int i) { (void)i; return ""; }

static VoidKeysHeld s_keysHeld;

int voidKeyDown(int keycode) { return voidKeysHeldDown(&s_keysHeld, keycode); }

int voidFbWidth(void) { return PLATFORM(Valid)() && voidCurrentView() == 0 ? PLATFORM(Width)() : voidViewsFbWidth(); }
int voidFbHeight(void) { return PLATFORM(Valid)() && voidCurrentView() == 0 ? PLATFORM(Height)() : voidViewsFbHeight(); }
float voidDpiScale(void) { return PLATFORM(Valid)() && voidCurrentView() == 0 ? PLATFORM(Scale)() : voidViewsDpiScale(); }

void voidPlatformRunInit(msClosure init) {
	const char *dir = PLATFORM(AssetDir)();
	char prev[4096];
	const char *got = getcwd(prev, sizeof prev);
	if (dir && dir[0]) chdir(dir);
	voidCallClosure(init);
	if (got) chdir(prev);
}

VoidAppEvent voidMobileEvent(VoidAppEventType type) {
	VoidAppEvent e;
	memset(&e, 0, sizeof e);
	e.type = type;
	e.frameCount = PLATFORM(FrameCount)();
	e.modifiers = PLATFORM(Modifiers)();
	e.framebufferWidth = PLATFORM(Width)();
	e.framebufferHeight = PLATFORM(Height)();
	e.windowWidth = (int)(e.framebufferWidth / PLATFORM(Scale)());
	e.windowHeight = (int)(e.framebufferHeight / PLATFORM(Scale)());
	return e;
}

void voidMobileSend(VoidAppEventType type) {
	VoidAppEvent e = voidMobileEvent(type);
	voidAppDeliver(&e);
}

void voidMobileKey(VoidAppEventType type, VoidKeyCode code, bool repeat) {
	voidKeysHeldTrack(&s_keysHeld, type, code);
	VoidAppEvent e = voidMobileEvent(type);
	e.keyCode = code;
	e.keyRepeat = repeat;
	voidAppDeliver(&e);
}

static void releaseKey(VoidKeyCode key) { voidMobileKey(VOID_EVENT_KEY_UP, key, false); }

void voidMobileReleaseKeys(void) { voidKeysHeldRelease(&s_keysHeld, releaseKey); }

static void tapUnlessHeld(VoidKeyCode key) {
	if (voidKeysHeldDown(&s_keysHeld, key)) return;
	voidMobileKey(VOID_EVENT_KEY_DOWN, key, false);
	voidMobileKey(VOID_EVENT_KEY_UP, key, false);
}

void voidMobileCommit(int textInput, const char *utf8, const uint32_t *codepoints, size_t count) {
	if (count == 1 && (codepoints[0] == '\n' || codepoints[0] == '\r')) {
		tapUnlessHeld(VOID_KEY_ENTER);
		return;
	}
	if (count == 1 && codepoints[0] == '\t') {
		tapUnlessHeld(VOID_KEY_TAB);
		return;
	}
	for (size_t i = 0; i < count; i++) {
		if (codepoints[i] < 0x20 || codepoints[i] == 0x7F) continue;
		if (textInput) {
			voidAppTextDeliver(VOID_EVENT_TEXT_INPUT, utf8, 0);
			return;
		}
		VoidAppEvent e = voidMobileEvent(VOID_EVENT_CHAR);
		e.charCode = codepoints[i];
		voidAppDeliver(&e);
	}
}
#endif

static void needWindow(const char *what) {
	if (!PLATFORM(Valid)()) voidFail("%s: the window does not exist yet; call it from the event handler or after init", what);
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
	return stringOrEmpty(PLATFORM(Clipboard)());
}

void voidSetMouseCursor(int cursor) {
	needWindow("voidSetMouseCursor");
	if (cursor < 0 || cursor >= VOID_CURSOR_COUNT) voidFail("voidSetMouseCursor: cursor %d is not a VoidMouseCursor (0..%d)", cursor, VOID_CURSOR_COUNT - 1);
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
	if (i < 0 || i >= PLATFORM(DroppedCount)()) voidFail("voidDroppedFilePath: index %d of %d dropped files", i, PLATFORM(DroppedCount)());
	return msStringFromCStr(PLATFORM(DroppedPath)(i));
}

