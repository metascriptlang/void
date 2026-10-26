// The Windows window's device and swapchain, which Void owns because its window
// (src/platform/win32/window.c) has no graphics API: D3D11 in bridgeWin.c, GL core in
// windowGl.c, Vulkan in windowVulkan.c. The surface follows voidWindowWidth/voidWindowHeight; a frame presents only once drawn.
#ifndef VOID_SOKOL_WINDOW_SURFACE_H
#define VOID_SOKOL_WINDOW_SURFACE_H

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdbool.h>

void voidWindowSurfaceCreate(HWND hwnd, int samples);
bool voidWindowAwaitFrame(void);
void voidWindowPresent(bool modal);
void voidWindowSurfaceDestroy(void);

#endif
