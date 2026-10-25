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

#endif
