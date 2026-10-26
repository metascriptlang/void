// The X11 window with its GL context, ported from sokol_app.h's Linux backend (pin 2e75443d):
// GL core 4.3 over GLX, or over EGL with VOID_FORCE_EGL; GLES 3.1 over EGL with VOID_GLES3.
// RGBA8 (GLX) or RGB8 (EGL) with depth 24, swap interval 1.
// The caller draws into framebuffer 0 and presents with voidLinuxSwapBuffers.
#ifndef VOID_PLATFORM_LINUX_WINDOW_H
#define VOID_PLATFORM_LINUX_WINDOW_H

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
	int sampleCount;
	const char *title;
} VoidLinuxDesc;

void voidLinuxRun(const VoidLinuxDesc *desc);
void voidLinuxSwapBuffers(void);

#endif
