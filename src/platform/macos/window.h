// The macOS window, ported from sokol_app.h's macOS backend (pin 2e75443d) without a graphics
// API: the caller owns the device and the layer on voidMacosView() and presents itself.
#ifndef VOID_PLATFORM_MACOS_WINDOW_H
#define VOID_PLATFORM_MACOS_WINDOW_H

#include <stdbool.h>
#include <stdint.h>

#include "../appEvent.h"

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
bool voidMacosValid(void);
void *voidMacosView(void);
int voidMacosWidth(void);
int voidMacosHeight(void);
float voidMacosDpiScale(void);
uint64_t voidMacosFrameCount(void);
void voidMacosRequestQuit(void);
void voidMacosSetTitle(const char *title);

void voidMacosCancelQuit(void);
double voidMacosFrameDuration(void);
void voidMacosSetClipboard(const char *utf8);
const char *voidMacosClipboard(void);
void voidMacosSetCursor(int cursor);
int voidMacosCursor(void);
void voidMacosShowMouse(bool shown);
bool voidMacosMouseShown(void);
void voidMacosLockMouse(bool locked);
bool voidMacosMouseLocked(void);
void voidMacosToggleFullscreen(void);
bool voidMacosIsFullscreen(void);
int voidMacosDroppedCount(void);
const char *voidMacosDroppedPath(int i);
void voidMacosSetTextInput(bool on);
void voidMacosSetImeRect(int x, int y, int w, int h);

#endif
