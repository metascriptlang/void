#ifndef VOID_SOKOL_VIEWS_EXPORTS_H
#define VOID_SOKOL_VIEWS_EXPORTS_H

#include "viewsPlatform.h"

#define VOID_MAX_VIEWS 16

typedef int VoidViewId;

void voidViewsSetSampleCount(int count);
int voidViewsSampleCount(void);
VoidViewId voidViewCreate(long long native, int w, int h, float scale);
void voidViewResize(VoidViewId v, int w, int h, float scale);
int voidViewReady(VoidViewId v);
int voidViewFrame(VoidViewId v);
void voidViewDestroy(VoidViewId v);
long long voidViewSwapChain(VoidViewId v);
VoidViewId voidCurrentView(void);

int voidViewsFbWidth(void);
int voidViewsFbHeight(void);
float voidViewsDpiScale(void);
// The surface of the view whose frame is running; stops outside a view frame.
void *voidViewsCurrentSurface(void);
void voidViewsPresent(void);
// The surface of the view in slot `slot`, NULL while the slot holds no view.
void *voidViewsSurfaceAt(int slot);

static inline void voidViewsEachSurface(void (*fn)(void *surface)) {
	for (int i = 0; i < VOID_MAX_VIEWS; i++) {
		void *surface = voidViewsSurfaceAt(i);
		if (surface != NULL) fn(surface);
	}
}

#endif
