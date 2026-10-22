// The browser window, ported from sokol_app.h's emscripten backend (pin 2e75443d): the canvas
// '#canvas' (or Module.canvas), its size and DPI, the requestAnimationFrame loop and the input
// events, over a WebGPU device and surface (VOID_WGPU) or a WebGL2 context (VOID_GLES3).
#ifndef VOID_PLATFORM_WEB_WINDOW_H
#define VOID_PLATFORM_WEB_WINDOW_H

#include <stdbool.h>
#include <stdint.h>
#if defined(VOID_WGPU)
#include <webgpu/webgpu.h>
#endif

#include "../appEvent.h"

typedef struct {
	void (*init)(void);
	void (*frame)(void);
	void (*event)(const VoidAppEvent *e);
	void (*cleanup)(void);
	int sampleCount;
	bool highDpi;
	const char *title;
} VoidWebDesc;

// Returns once the first animation frame is requested; init and every frame run from it, and
// on WebGPU only after the device and surface exist.
void voidWebRun(const VoidWebDesc *desc);
bool voidWebValid(void);
int voidWebWidth(void);
int voidWebHeight(void);
int voidWebSampleCount(void);
float voidWebDpiScale(void);
uint64_t voidWebFrameCount(void);
void voidWebRequestQuit(void);
// Inside the event callback: the browser's default action for this event does not run.
void voidWebConsumeEvent(void);
void voidWebSetTitle(const char *title);

#if defined(VOID_WGPU)
WGPUDevice voidWebDevice(void);
WGPUTextureFormat voidWebColorFormat(void);
// The frame's screen views. The surface texture is acquired on the first call in a frame and
// released after the frame callback; with one sample the resolve view is NULL.
WGPUTextureView voidWebRenderView(void);
WGPUTextureView voidWebResolveView(void);
WGPUTextureView voidWebDepthStencilView(void);
#endif

void voidWebCancelQuit(void);
double voidWebFrameDuration(void);
void voidWebSetClipboard(const char *utf8);
const char *voidWebClipboard(void);
void voidWebSetCursor(int cursor);
int voidWebCursor(void);
void voidWebShowMouse(bool shown);
bool voidWebMouseShown(void);
void voidWebLockMouse(bool locked);
bool voidWebMouseLocked(void);
void voidWebToggleFullscreen(void);
bool voidWebIsFullscreen(void);
int voidWebDroppedCount(void);
const char *voidWebDroppedPath(int i);

#endif
