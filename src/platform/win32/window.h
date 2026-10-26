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

#include "../windowCore.h"

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
HWND voidWin32Hwnd(void);

#endif
