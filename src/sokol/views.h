#ifndef VOID_SOKOL_VIEWS_H
#define VOID_SOKOL_VIEWS_H

#include "bridge.h"
#include "sokol_gfx.h"

void voidPlatformDeviceEnsure(void);
void voidPlatformRunInit(msClosure init);
void *voidPlatformSurfaceCreate(const void *native, int w, int h);
void voidPlatformSurfaceResize(void *surface, int w, int h);
int voidPlatformSurfaceAcquire(void *surface);
void voidPlatformSurfaceSwapchain(void *surface, sg_swapchain *swapchain);
void voidPlatformSurfacePresent(void *surface);
void voidPlatformSurfaceDestroy(void *surface);
long long voidPlatformSurfaceNative(void *surface);

int voidViewsFbWidth(void);
int voidViewsFbHeight(void);
float voidViewsDpiScale(void);
sg_swapchain voidViewsSwapchain(void);
void voidViewsPresent(void);
void voidViewsEachSurface(void (*fn)(void *surface));

sg_swapchain voidDriverSwapchain(void);
void voidDriverPresent(void);

__attribute__((noreturn)) void voidFail(const char *fmt, ...);

#endif
