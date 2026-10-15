#ifndef VOID_SOKOL_APP_WINDOW_H
#define VOID_SOKOL_APP_WINDOW_H

#include "sokol_app.h"

// 1 when the closure voidSetEventHandler registered took the event; 0 when none is set.
int voidAppEventDeliver(const sapp_event *e);
const char *voidWindowTitle(void);
int voidWindowTitleSet(void);

#endif
