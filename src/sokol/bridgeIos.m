// Void driver — iOS (Metal). Host-driven: no run-loop, no UIKit window. Each
// React-Native VoidView owns a CAMetalLayer and a CADisplayLink and drives its view in
// views.c. One MTLDevice is shared by every view; the GPU door's Metal backend draws on it.

#import <Foundation/Foundation.h>
#import <QuartzCore/CAMetalLayer.h>
#import <Metal/Metal.h>
#include <stdlib.h>
#include <unistd.h>

#include "bridge.h"
#include "presentGate.h"
#include "views.h"
#include "iosApp.h"
#include "metalSurface.h"
#include "../gpu/door.h"

void voidPlatformDeviceEnsure(void) {
	if (voidMetalDevice()) return;
	voidMetalDeviceMake();
	voidMetalDoorSetup(voidViewsSampleCount());
}

// Void's asset loaders use relative paths ("assets/test.png", "assets/font.ttf").
// Point the CWD at the app bundle for the init window (where images + fonts load),
// then restore — so the host app's CWD is untouched outside this call.
void voidPlatformRunInit(msClosure init) {
	char prev[4096];
	const char *got = getcwd(prev, sizeof prev);
	const char *res = [[[NSBundle mainBundle] resourcePath] fileSystemRepresentation];
	if (res) chdir(res);
	voidCallClosure(init);
	if (got) chdir(prev);
}

void *voidPlatformSurfaceCreate(const void *native, int w, int h) {
	if (native == NULL) voidFail("voidViewCreate on iOS needs a CAMetalLayer");
	return voidMetalSurfaceMake((void *)native, w, h);
}

void voidPlatformSurfaceResize(void *surface, int w, int h) { voidMetalSurfaceSize((VoidMetalSurface *)surface, w, h); }

int voidPlatformSurfaceReady(void *surface) { return voidPresentGateAdmits(((VoidMetalSurface *)surface)->gate); }

long long voidPlatformSurfaceNative(void *surface) { (void)surface; return 0; }

void voidGfxSetup(void) {
	if (!doorValid()) voidFail("gfxSetup before voidViewCreate made the Metal device");
}

int voidFbWidth(void) { return voidIosAppFbWidth(); }
int voidFbHeight(void) { return voidIosAppFbHeight(); }
float voidDpiScale(void) { return voidIosAppDpiScale(); }
void voidDriverPresent(void) { voidViewsPresent(); }

const VoidMetalSurface *voidMetalScreen(void) { return voidMetalViewsScreen(); }
