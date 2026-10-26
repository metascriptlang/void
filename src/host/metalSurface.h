// The Metal device and host-view surface shared by the macOS (bridgeEmbed.m) and iOS
// (bridgeIos.m) drivers, and the swapchain the door's screen pass draws into.
#ifndef VOID_SOKOL_METAL_SURFACE_H
#define VOID_SOKOL_METAL_SURFACE_H

#import <Metal/Metal.h>

typedef struct {
	void *layer;
	void *gate;
	void *view;
	void *drawable;
	void *msaa;
	int w, h;
} VoidMetalSurface;

id<MTLDevice> voidMetalDevice(void);
void voidMetalDeviceMake(void);
void voidMetalDoorSetup(int samples);

VoidMetalSurface *voidMetalSurfaceMake(void *layer, int w, int h);
void voidMetalSurfaceSize(VoidMetalSurface *s, int w, int h);

VoidMetalSurface *voidMetalViewsScreen(void);
// Each driver's screen: voidMetalViewsScreen, or on macOS the window while voidRun drives it.
const VoidMetalSurface *voidMetalScreen(void);

#endif
