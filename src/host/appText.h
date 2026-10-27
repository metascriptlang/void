// The event text getter, apart from bridge.h because its msString return needs the
// MetaScript runtime: @include'd by window.ms and defined by appWindowExports.cms.
#ifndef VOID_SOKOL_APP_TEXT_H
#define VOID_SOKOL_APP_TEXT_H

#include "runtime/core/string.h"

msString voidEventText(void);
msString voidClipboard(void);
msString voidDroppedFilePath(int i);

#endif
