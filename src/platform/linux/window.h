// The X11 window with its GL context, ported from sokol_app.h's Linux backend (pin 2e75443d):
// GL core 4.3 over GLX, or over EGL with VOID_FORCE_EGL; GLES 3.1 over EGL with VOID_GLES3.
// RGBA8 (GLX) or RGB8 (EGL) with depth 24, swap interval 1.
// The caller draws into framebuffer 0 and presents with voidLinuxSwapBuffers.
#ifndef VOID_PLATFORM_LINUX_WINDOW_H
#define VOID_PLATFORM_LINUX_WINDOW_H

#include <stdbool.h>
#include <stdint.h>

#include "../appEvent.h"

typedef struct {
	void (*init)(void);
	void (*frame)(void);
	void (*event)(const VoidAppEvent *e);
	void (*cleanup)(void);
	int width;
	int height;
	int sampleCount;
	const char *title;
} VoidLinuxDesc;

void voidLinuxRun(const VoidLinuxDesc *desc);
bool voidLinuxValid(void);
int voidLinuxWidth(void);
int voidLinuxHeight(void);
float voidLinuxDpiScale(void);
uint64_t voidLinuxFrameCount(void);
void voidLinuxRequestQuit(void);
void voidLinuxSetTitle(const char *title);
void voidLinuxSwapBuffers(void);

void voidLinuxCancelQuit(void);
double voidLinuxFrameDuration(void);
void voidLinuxSetClipboard(const char *utf8);
const char *voidLinuxClipboard(void);
void voidLinuxSetCursor(int cursor);
int voidLinuxCursor(void);
void voidLinuxShowMouse(bool shown);
bool voidLinuxMouseShown(void);
void voidLinuxLockMouse(bool locked);
bool voidLinuxMouseLocked(void);
void voidLinuxToggleFullscreen(void);
bool voidLinuxIsFullscreen(void);
int voidLinuxDroppedCount(void);
const char *voidLinuxDroppedPath(int i);

#endif
