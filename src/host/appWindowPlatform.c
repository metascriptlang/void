// The native half of the window's app-facing code, which src/host/appWindow.ms drives through
// appWindowExports.cms: the platform window's own calls (voidWindow* on the desktop and the
// browser, voidAndroid* and voidIos* on the app shells) under one set of names, the mobile
// shells' stand-ins for the state sokol_app has there, and the shells' working directory.

#include "appWindow.h"
#include "appWindowPlatform.h"

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

#include "bridge.h"
#ifdef VOID_PROFILER
#include "../void2d/frameClock.h"
#endif

#if defined(VOID_ANDROID_APP) || defined(VOID_IOS_APP)
#include <unistd.h>

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

uint32_t voidAppPlatformModifiers(void) { return PLATFORM(Modifiers)(); }
float voidAppPlatformScale(void) { return PLATFORM(Scale)(); }

void voidPlatformRunInit(msClosure init) {
	const char *dir = PLATFORM(AssetDir)();
	char prev[4096];
	const char *got = getcwd(prev, sizeof prev);
	if (dir && dir[0]) chdir(dir);
	voidCallClosure(init);
	if (got) chdir(prev);
}

void voidAppPlatformSetTitle(const char *title) { (void)title; }
#else
void voidAppPlatformSetTitle(const char *title) { voidWindowSetTitle(title); }
#endif

int voidAppPlatformValid(void) { return PLATFORM(Valid)() ? 1 : 0; }
uint64_t voidAppPlatformFrameCount(void) { return PLATFORM(FrameCount)(); }
int voidAppPlatformWidth(void) { return PLATFORM(Width)(); }
int voidAppPlatformHeight(void) { return PLATFORM(Height)(); }
void voidAppPlatformRequestQuit(void) { PLATFORM(RequestQuit)(); }
void voidAppPlatformCancelQuit(void) { PLATFORM(CancelQuit)(); }
double voidAppPlatformFrameDuration(void) { return PLATFORM(FrameDuration)(); }
void voidAppPlatformSetClipboard(const char *utf8) { PLATFORM(SetClipboard)(utf8); }
const char *voidAppPlatformClipboard(void) { return PLATFORM(Clipboard)(); }
void voidAppPlatformSetCursor(int cursor) { PLATFORM(SetCursor)(cursor); }
int voidAppPlatformCursor(void) { return PLATFORM(Cursor)(); }
void voidAppPlatformShowMouse(int shown) { PLATFORM(ShowMouse)(shown != 0); }
int voidAppPlatformMouseShown(void) { return PLATFORM(MouseShown)() ? 1 : 0; }
void voidAppPlatformLockMouse(int locked) { PLATFORM(LockMouse)(locked != 0); }
int voidAppPlatformMouseLocked(void) { return PLATFORM(MouseLocked)() ? 1 : 0; }
void voidAppPlatformToggleFullscreen(void) { PLATFORM(ToggleFullscreen)(); }
int voidAppPlatformIsFullscreen(void) { return PLATFORM(IsFullscreen)() ? 1 : 0; }
int voidAppPlatformDroppedCount(void) { return PLATFORM(DroppedCount)(); }
const char *voidAppPlatformDroppedPath(int i) { return PLATFORM(DroppedPath)(i); }

void voidAppPlatformProfileInput(void) {
#ifdef VOID_PROFILER
	voidProfileInput();
#endif
}
