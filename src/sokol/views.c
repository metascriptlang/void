#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>

#include "views.h"

#define VOID_MAX_VIEWS 16

typedef struct {
	int used;
	int w, h;
	float scale;
	void *surface;
} VoidViewSlot;

static VoidViewSlot s_views[VOID_MAX_VIEWS];
static VoidViewId s_current = 0;
static int s_inited = 0;
static msClosure s_init;
static msClosure s_frame;
static msClosure s_pump;

void voidFail(const char *fmt, ...) {
	va_list args;
	va_start(args, fmt);
	fprintf(stderr, "void: ");
	vfprintf(stderr, fmt, args);
	fprintf(stderr, "\n");
	va_end(args);
	fflush(stderr);
	abort();
}

static void call0(msClosure c) {
	if (!c.fn) return;
	if (c.env) ((void (*)(void *))c.fn)(c.env);
	else ((void (*)(void))c.fn)();
}

static VoidViewSlot *slotOf(VoidViewId v, const char *op) {
	if (v <= 0 || v > VOID_MAX_VIEWS || !s_views[v - 1].used) voidFail("%s: view %d does not exist", op, v);
	return &s_views[v - 1];
}

static VoidViewSlot *currentSlot(const char *op) {
	if (s_current == 0) voidFail("%s outside a view frame: call it between voidViewFrame's begin and commit", op);
	return &s_views[s_current - 1];
}

void voidEmbedRegister(msClosure init, msClosure frame) {
	s_init = init;
	s_frame = frame;
}

void voidEmbedSetMessagePump(msClosure pump) { s_pump = pump; }
void voidEmbedPumpMessages(void) { call0(s_pump); }

VoidViewId voidViewCreate(long long native, int w, int h, float scale) {
	if (w <= 0 || h <= 0 || scale <= 0.0f) voidFail("voidViewCreate: %dx%d at scale %g is not a drawable size", w, h, scale);
	int slot = -1;
	for (int i = 0; i < VOID_MAX_VIEWS; i++) {
		if (!s_views[i].used) { slot = i; break; }
	}
	if (slot < 0) voidFail("voidViewCreate: all %d views are in use", VOID_MAX_VIEWS);
	voidPlatformDeviceEnsure();
	void *surface = voidPlatformSurfaceCreate((const void *)(intptr_t)native, w, h);
	if (surface == NULL) voidFail("voidViewCreate: the platform could not make a %dx%d surface", w, h);
	s_views[slot] = (VoidViewSlot){.used = 1, .w = w, .h = h, .scale = scale, .surface = surface};
	if (!s_inited) {
		s_inited = 1;
		voidPlatformRunInit(s_init);
	}
	return slot + 1;
}

void voidViewResize(VoidViewId v, int w, int h, float scale) {
	VoidViewSlot *s = slotOf(v, "voidViewResize");
	if (s_current != 0) voidFail("voidViewResize(%d) inside the frame of view %d", v, s_current);
	if (w <= 0 || h <= 0 || scale <= 0.0f) voidFail("voidViewResize(%d): %dx%d at scale %g is not a drawable size", v, w, h, scale);
	if (w != s->w || h != s->h) voidPlatformSurfaceResize(s->surface, w, h);
	s->w = w;
	s->h = h;
	s->scale = scale;
}

int voidViewFrame(VoidViewId v) {
	VoidViewSlot *s = slotOf(v, "voidViewFrame");
	if (s_current != 0) voidFail("voidViewFrame(%d) inside the frame of view %d", v, s_current);
	voidEmbedPumpMessages();
	if (!voidPlatformSurfaceAcquire(s->surface)) return 0;
	s_current = v;
	call0(s_frame);
	if (s_current != 0) voidFail("the frame closure for view %d returned without commit()", v);
	return 1;
}

void voidViewDestroy(VoidViewId v) {
	VoidViewSlot *s = slotOf(v, "voidViewDestroy");
	if (s_current != 0) voidFail("voidViewDestroy(%d) inside the frame of view %d", v, s_current);
	voidPlatformSurfaceDestroy(s->surface);
	*s = (VoidViewSlot){0};
}

long long voidViewSwapChain(VoidViewId v) {
	return voidPlatformSurfaceNative(slotOf(v, "voidViewSwapChain")->surface);
}

VoidViewId voidCurrentView(void) { return s_current; }

int voidViewsFbWidth(void) { return currentSlot("fbWidth")->w; }
int voidViewsFbHeight(void) { return currentSlot("fbHeight")->h; }
float voidViewsDpiScale(void) { return currentSlot("dpiScale")->scale; }

sg_swapchain voidViewsSwapchain(void) {
	VoidViewSlot *s = currentSlot("beginPass");
	sg_swapchain swapchain = {0};
	swapchain.width = s->w;
	swapchain.height = s->h;
	swapchain.sample_count = 1;
	swapchain.depth_format = SG_PIXELFORMAT_NONE;
	voidPlatformSurfaceSwapchain(s->surface, &swapchain);
	return swapchain;
}

void voidViewsPresent(void) {
	VoidViewSlot *s = currentSlot("commit");
	s_current = 0;
	voidPlatformSurfacePresent(s->surface);
}

void voidViewsEachSurface(void (*fn)(void *surface)) {
	for (int i = 0; i < VOID_MAX_VIEWS; i++) {
		if (s_views[i].used) fn(s_views[i].surface);
	}
}
