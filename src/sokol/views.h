#ifndef VOID_SOKOL_VIEWS_H
#define VOID_SOKOL_VIEWS_H

#include "bridge.h"

void voidPlatformDeviceEnsure(void);
int voidViewsSampleCount(void);
void voidPlatformRunInit(msClosure init);
void *voidPlatformSurfaceCreate(const void *native, int w, int h);
void voidPlatformSurfaceResize(void *surface, int w, int h);
int voidPlatformSurfaceReady(void *surface);
int voidPlatformSurfaceAcquire(void *surface);
void voidPlatformSurfacePresent(void *surface);
void voidPlatformSurfaceDestroy(void *surface);
long long voidPlatformSurfaceNative(void *surface);

int voidViewsFbWidth(void);
int voidViewsFbHeight(void);
float voidViewsDpiScale(void);
// The surface of the view whose frame is running; stops outside a view frame.
void *voidViewsCurrentSurface(void);
void voidViewsPresent(void);
void voidViewsEachSurface(void (*fn)(void *surface));

void voidDriverPresent(void);

#endif
