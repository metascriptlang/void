// The macOS window, ported from sokol_app.h's macOS backend (pin 2e75443d) without a graphics
// API: the caller owns the device and the layer on voidMacosView() and presents itself.
#ifndef VOID_PLATFORM_MACOS_WINDOW_H
#define VOID_PLATFORM_MACOS_WINDOW_H

#include <stdbool.h>
#include <stdint.h>

#include "../windowCore.h"

typedef struct {
	void (*init)(void);
	void (*frame)(void);
	void (*event)(const VoidAppEvent *e);
	void (*text)(int type, const char *utf8, int cursor);
	void (*cleanup)(void);
	int width;
	int height;
	bool highDpi;
	const char *title;
} VoidMacosDesc;

void voidMacosRun(const VoidMacosDesc *desc);
void *voidMacosView(void);

void voidMacosSetTextInput(bool on);
void voidMacosSetImeRect(int x, int y, int w, int h);

#endif
