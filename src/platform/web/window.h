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

#include "../windowCore.h"

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
int voidWebSampleCount(void);
// Inside the event callback: the browser's default action for this event does not run.
void voidWebConsumeEvent(void);

#if defined(VOID_WGPU)
WGPUDevice voidWebDevice(void);
WGPUTextureFormat voidWebColorFormat(void);
// The frame's screen views. The surface texture is acquired on the first call in a frame and
// released after the frame callback; with one sample the resolve view is NULL.
WGPUTextureView voidWebRenderView(void);
WGPUTextureView voidWebResolveView(void);
WGPUTextureView voidWebDepthStencilView(void);
#endif

#endif
