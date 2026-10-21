#ifndef VOID_SOKOL_APP_WINDOW_H
#define VOID_SOKOL_APP_WINDOW_H

#include "../platform/appEvent.h"

// 1 when the closure voidSetEventHandler registered took the event; 0 when none is set.
int voidAppDeliver(const VoidAppEvent *e);
int voidAppEventHandlerSet(void);
// An IME event: the composing text with its caret in UTF-16 units, or the committed text.
void voidAppTextDeliver(int type, const char *utf8, int cursor);
void voidAppSetSafeArea(float top, float left, float bottom, float right);
const char *voidWindowTitle(void);
int voidWindowTitleSet(void);

#endif
