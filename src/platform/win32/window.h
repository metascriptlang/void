// The Win32 window, ported from sokol_app.h's Win32 backend (pin 2e75443d) without a graphics
// API: the caller owns the device and swapchain and presents itself.
#ifndef VOID_PLATFORM_WIN32_WINDOW_H
#define VOID_PLATFORM_WIN32_WINDOW_H

#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
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
	bool highDpi;
	const char *title;
} VoidWin32Desc;

void voidWin32Run(const VoidWin32Desc *desc);
bool voidWin32Valid(void);
HWND voidWin32Hwnd(void);
int voidWin32Width(void);
int voidWin32Height(void);
float voidWin32DpiScale(void);
uint64_t voidWin32FrameCount(void);
void voidWin32RequestQuit(void);
void voidWin32SetTitle(const char *title);

void voidWin32CancelQuit(void);
double voidWin32FrameDuration(void);
void voidWin32SetClipboard(const char *utf8);
const char *voidWin32Clipboard(void);
void voidWin32SetCursor(int cursor);
int voidWin32Cursor(void);
void voidWin32ShowMouse(bool shown);
bool voidWin32MouseShown(void);
void voidWin32LockMouse(bool locked);
bool voidWin32MouseLocked(void);
void voidWin32ToggleFullscreen(void);
bool voidWin32IsFullscreen(void);
int voidWin32DroppedCount(void);
const char *voidWin32DroppedPath(int i);

#endif
