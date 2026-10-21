#ifndef VOID_SOKOL_APP_WINDOW_H
#define VOID_SOKOL_APP_WINDOW_H

#include "sokol_app.h"

// Void's own event types, after sokol_app's: AppEventType in window.ms keeps the same order.
#define VOID_EVENT_PREEDIT 24
#define VOID_EVENT_TEXT_INPUT 25

// 1 when the closure voidSetEventHandler registered took the event; 0 when none is set.
int voidAppEventDeliver(const sapp_event *e);
int voidAppEventHandlerSet(void);
// An IME event: the composing text with its caret in UTF-16 units, or the committed text.
void voidAppTextDeliver(int type, const char *utf8, int cursor);
void voidAppSetSafeArea(float top, float left, float bottom, float right);
void voidAppSetKeyboard(float height);
const char *voidWindowTitle(void);
int voidWindowTitleSet(void);

#endif
