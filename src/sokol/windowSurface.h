// The sokol_app window's device and swapchain on Windows, which Void owns because sokol_app
// runs without a graphics API there (sokolAppWin.c): D3D11 in bridgeWin.c, GL core in
// windowGl.c. The surface follows sapp_width/sapp_height; a frame presents only once drawn.
#ifndef VOID_SOKOL_WINDOW_SURFACE_H
#define VOID_SOKOL_WINDOW_SURFACE_H

#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <stdbool.h>

#include "sokol_gfx.h"

void voidWindowSurfaceCreate(HWND hwnd, int samples);
sg_environment voidWindowEnvironment(void);
sg_swapchain voidWindowSwapchain(void);
bool voidWindowAwaitFrame(void);
void voidWindowPresent(bool modal);
void voidWindowSurfaceDestroy(void);

#endif
