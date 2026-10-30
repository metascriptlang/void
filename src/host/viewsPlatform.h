#ifndef VOID_SOKOL_VIEWS_PLATFORM_H
#define VOID_SOKOL_VIEWS_PLATFORM_H

#include <stddef.h>

#include "bridge.h"

#ifdef __APPLE__
extern void *objc_autoreleasePoolPush(void);
extern void objc_autoreleasePoolPop(void *pool);
#endif

static inline void *voidViewsPoolPush(void) {
#ifdef __APPLE__
	return objc_autoreleasePoolPush();
#else
	return NULL;
#endif
}

static inline void voidViewsPoolPop(void *pool) {
#ifdef __APPLE__
	objc_autoreleasePoolPop(pool);
#else
	(void)pool;
#endif
}

void voidPlatformDeviceEnsure(void);
void voidPlatformRunInit(msClosure init);
void *voidPlatformSurfaceCreate(const void *native, int w, int h);
void voidPlatformSurfaceResize(void *surface, int w, int h);
int voidPlatformSurfaceReady(void *surface);
int voidPlatformSurfaceAcquire(void *surface);
void voidPlatformSurfacePresent(void *surface);
void voidPlatformSurfaceDestroy(void *surface);
long long voidPlatformSurfaceNative(void *surface);

void voidDriverPresent(void);

#endif
