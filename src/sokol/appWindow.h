#ifndef VOID_SOKOL_APP_WINDOW_H
#define VOID_SOKOL_APP_WINDOW_H

#include "../platform/appEvent.h"

// 1 when the closure voidSetEventHandler registered took the event; 0 when none is set.
int voidAppDeliver(const VoidAppEvent *e);
#if defined(__EMSCRIPTEN__)
#include "sokol_app.h"
// The browser window still runs on sokol_app: its event, copied into a VoidAppEvent.
int voidAppEventDeliver(const sapp_event *e);
#endif
int voidAppEventHandlerSet(void);
// An IME event: the composing text with its caret in UTF-16 units, or the committed text.
void voidAppTextDeliver(int type, const char *utf8, int cursor);
const char *voidWindowTitle(void);
int voidWindowTitleSet(void);

#endif
