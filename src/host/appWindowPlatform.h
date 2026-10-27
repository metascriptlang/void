#ifndef VOID_SOKOL_APP_WINDOW_PLATFORM_H
#define VOID_SOKOL_APP_WINDOW_PLATFORM_H

#include <stdint.h>

// The platform window under one set of names (appWindowPlatform.c), for appWindowExports.cms.
int voidAppPlatformValid(void);
uint64_t voidAppPlatformFrameCount(void);
int voidAppPlatformWidth(void);
int voidAppPlatformHeight(void);
void voidAppPlatformSetTitle(const char *title);
void voidAppPlatformProfileInput(void);
void voidAppPlatformRequestQuit(void);
void voidAppPlatformCancelQuit(void);
double voidAppPlatformFrameDuration(void);
void voidAppPlatformSetClipboard(const char *utf8);
const char *voidAppPlatformClipboard(void);
void voidAppPlatformSetCursor(int cursor);
int voidAppPlatformCursor(void);
void voidAppPlatformShowMouse(int shown);
int voidAppPlatformMouseShown(void);
void voidAppPlatformLockMouse(int locked);
int voidAppPlatformMouseLocked(void);
void voidAppPlatformToggleFullscreen(void);
int voidAppPlatformIsFullscreen(void);
int voidAppPlatformDroppedCount(void);
const char *voidAppPlatformDroppedPath(int i);
// The app shells only.
uint32_t voidAppPlatformModifiers(void);
float voidAppPlatformScale(void);

#endif
