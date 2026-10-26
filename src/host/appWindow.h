#ifndef VOID_SOKOL_APP_WINDOW_H
#define VOID_SOKOL_APP_WINDOW_H

#if defined(__APPLE__)
#include <TargetConditionals.h>
#endif
#if !defined(VOID_DUMMY) && defined(__ANDROID__)
#define VOID_ANDROID_APP 1
#elif !defined(VOID_DUMMY) && defined(__APPLE__) && !TARGET_OS_OSX
#define VOID_IOS_APP 1
#endif
#if !defined(VOID_DUMMY) && !(defined(__linux__) && !defined(__ANDROID__))
#define VOID_HOST_VIEWS 1
#endif

#include "../platform/appEvent.h"

// 1 when the closure voidSetEventHandler registered took the event; 0 when none is set.
int voidAppDeliver(const VoidAppEvent *e);
int voidAppEventHandlerSet(void);
void voidAppWindowEvent(const VoidAppEvent *e);
// An IME event: the composing text with its caret in UTF-16 units, or the committed text.
void voidAppTextDeliver(int type, const char *utf8, int cursor);
void voidAppSetSafeArea(float top, float left, float bottom, float right);
void voidAppSetKeyboard(float height);
const char *voidWindowTitle(void);
int voidWindowTitleSet(void);
int voidPresentMode(void);

#if defined(VOID_ANDROID_APP) || defined(VOID_IOS_APP)
#include <stddef.h>
// The app shells' events (bridgeIosApp.m, bridgeAndroidApp.c), stamped with the shell's frame,
// framebuffer and modifiers; voidMobileKey keeps voidKeyDown's held keys.
VoidAppEvent voidMobileEvent(VoidAppEventType type);
void voidMobileSend(VoidAppEventType type);
void voidMobileKey(VoidAppEventType type, VoidKeyCode code, bool repeat);
void voidMobileReleaseKeys(void);
// Committed text: a lone newline or tab is a key tap unless that key is held; otherwise one
// TEXT_INPUT while text input is on, else a CHAR per printable codepoint.
void voidMobileCommit(int textInput, const char *utf8, const uint32_t *codepoints, size_t count);
#endif

#endif
