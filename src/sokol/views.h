#ifndef VOID_SOKOL_VIEWS_H
#define VOID_SOKOL_VIEWS_H

#include "bridge.h"
#if !defined(_WIN32)
#include "sokol_gfx.h"
#endif

void voidPlatformDeviceEnsure(void);
int voidViewsSampleCount(void);
void voidPlatformRunInit(msClosure init);
void *voidPlatformSurfaceCreate(const void *native, int w, int h);
void voidPlatformSurfaceResize(void *surface, int w, int h);
int voidPlatformSurfaceAcquire(void *surface);
#if !defined(_WIN32)
void voidPlatformSurfaceSwapchain(void *surface, sg_swapchain *swapchain);
#endif
void voidPlatformSurfacePresent(void *surface);
void voidPlatformSurfaceDestroy(void *surface);
long long voidPlatformSurfaceNative(void *surface);

int voidViewsFbWidth(void);
int voidViewsFbHeight(void);
float voidViewsDpiScale(void);
#if !defined(_WIN32)
sg_swapchain voidViewsSwapchain(void);
#endif
// The surface of the view whose frame is running; stops outside a view frame.
void *voidViewsCurrentSurface(void);
void voidViewsPresent(void);
void voidViewsEachSurface(void (*fn)(void *surface));

#if !defined(_WIN32)
sg_swapchain voidDriverSwapchain(void);
#endif
void voidDriverPresent(void);

__attribute__((noreturn)) void voidFail(const char *fmt, ...);

#endif
