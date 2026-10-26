// Void driver — Android (GLES3 via EGL). Host-driven: no sokol_app. The host (RN Fabric
// SurfaceView, or a headless pbuffer view) owns the surface and the render loop and drives the
// views in views.c. One EGL context is shared by every view; each view has its own EGL window
// surface. The GPU door's GL backend (src/webgpu/gl, OGL_GLES) draws on that context.

#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <stdint.h>
#include <stdlib.h>

#include "bridge.h"
#include "views.h"
#include "../gpu/door.h"
#include "../platform/swapchain.h"

static EGLDisplay g_dpy = EGL_NO_DISPLAY;
static EGLContext g_ctx = EGL_NO_CONTEXT;
static EGLConfig g_cfg;

typedef struct {
	const void *window;
	EGLSurface surf;
	int w, h;
} AndroidSurface;

static int egl_boot(void) {
	g_dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
	if (g_dpy == EGL_NO_DISPLAY) return 0;
	if (!eglInitialize(g_dpy, NULL, NULL)) return 0;
	const int samples = voidViewsSampleCount();
	EGLint cfgAttr[] = {
		EGL_SURFACE_TYPE, EGL_WINDOW_BIT | EGL_PBUFFER_BIT,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
		EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
		EGL_DEPTH_SIZE, 0,
		EGL_SAMPLE_BUFFERS, samples > 1 ? 1 : 0,
		EGL_SAMPLES, samples > 1 ? samples : 0,
		EGL_NONE
	};
	EGLint n = 0;
	if (!eglChooseConfig(g_dpy, cfgAttr, &g_cfg, 1, &n)) return 0;
	if (n < 1) voidFail("EGL has no RGBA8 window and pbuffer config with %d samples", samples);
	eglBindAPI(EGL_OPENGL_ES_API);
	EGLint ctxAttr[] = { EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE };
	g_ctx = eglCreateContext(g_dpy, g_cfg, EGL_NO_CONTEXT, ctxAttr);
	return g_ctx != EGL_NO_CONTEXT;
}

// The EGL config has no depth buffer, so the screen pipelines are made without depth.
static void setupDoor(void) {
	doorSetup(NULL, NULL, DOOR_PIXEL_FORMAT_RGBA8, DOOR_PIXEL_FORMAT_NONE, voidViewsSampleCount());
	if (!doorValid()) voidFail("doorSetup on the EGL context failed");
}

static EGLSurface makeSurface(const AndroidSurface *s) {
	if (s->window != NULL) {
		return eglCreateWindowSurface(g_dpy, g_cfg, (EGLNativeWindowType)(uintptr_t)s->window, NULL);
	}
	EGLint pb[] = { EGL_WIDTH, s->w, EGL_HEIGHT, s->h, EGL_NONE };
	return eglCreatePbufferSurface(g_dpy, g_cfg, pb);
}

static void makeCurrent(const AndroidSurface *s) {
	if (!eglMakeCurrent(g_dpy, s->surf, s->surf, g_ctx)) voidFail("eglMakeCurrent failed: 0x%04x", eglGetError());
}

void voidPlatformDeviceEnsure(void) {
	if (g_ctx != EGL_NO_CONTEXT) return;
	if (!egl_boot()) voidFail("EGL could not make a GLES3 context: 0x%04x", eglGetError());
}

void *voidPlatformSurfaceCreate(const void *native, int w, int h) {
	AndroidSurface *s = (AndroidSurface *)calloc(1, sizeof(AndroidSurface));
	if (!s) voidFail("voidViewCreate: out of memory for an EGL surface");
	s->window = native;
	s->w = w;
	s->h = h;
	s->surf = makeSurface(s);
	if (s->surf == EGL_NO_SURFACE) voidFail("EGL could not make a %dx%d surface: 0x%04x", w, h, eglGetError());
	if (!doorValid()) {
		makeCurrent(s);
		setupDoor();
	}
	return s;
}

void voidPlatformSurfaceResize(void *surface, int w, int h) {
	AndroidSurface *s = (AndroidSurface *)surface;
	s->w = w;
	s->h = h;
	if (s->window != NULL) return;
	eglMakeCurrent(g_dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, g_ctx);
	eglDestroySurface(g_dpy, s->surf);
	s->surf = makeSurface(s);
	if (s->surf == EGL_NO_SURFACE) voidFail("EGL could not resize a pbuffer to %dx%d: 0x%04x", w, h, eglGetError());
}

// ---- context loss (docs/VOID3D.md, Android lifecycle) ----
//
// eglSwapBuffers fails with EGL_CONTEXT_LOST after a power-management event; every GL object
// is gone. The next frame shuts the door down (its GL deletes go to the lost context, which
// ignores them), makes a new context, remakes every view's surface and sets the door up again,
// which bumps doorContextGeneration: the owners of the old ids drop them without destroying.

// Forces the rebuild on the next frame, to exercise it on a device without a real loss.
void voidEmbedLoseContext(void) { voidLoseContext(); }

static void dropSurface(void *surface) {
	AndroidSurface *s = (AndroidSurface *)surface;
	if (s->surf != EGL_NO_SURFACE) eglDestroySurface(g_dpy, s->surf);
	s->surf = EGL_NO_SURFACE;
}

static void remakeSurface(void *surface) {
	AndroidSurface *s = (AndroidSurface *)surface;
	s->surf = makeSurface(s);
	if (s->surf == EGL_NO_SURFACE) voidFail("EGL could not remake a surface after a context loss: 0x%04x", eglGetError());
}

static AndroidSurface *s_acquired;

static void rebuildContext(void) {
	eglMakeCurrent(g_dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
	voidViewsEachSurface(dropSurface);
	if (g_ctx != EGL_NO_CONTEXT) eglDestroyContext(g_dpy, g_ctx);
	g_ctx = EGL_NO_CONTEXT;
	if (!egl_boot()) voidFail("EGL could not rebuild the context after a loss: 0x%04x", eglGetError());
	voidViewsEachSurface(remakeSurface);
	makeCurrent(s_acquired);
	setupDoor();
}

int voidPlatformSurfaceReady(void *surface) { (void)surface; return 1; }

int voidPlatformSurfaceAcquire(void *surface) {
	s_acquired = (AndroidSurface *)surface;
	voidRestoreContextIfLost(rebuildContext);
	makeCurrent(s_acquired);
	return 1;
}

void voidPlatformSurfacePresent(void *surface) {
	AndroidSurface *s = (AndroidSurface *)surface;
	if (!eglSwapBuffers(g_dpy, s->surf) && eglGetError() == EGL_CONTEXT_LOST) voidLoseContext();
}

void voidPlatformSurfaceDestroy(void *surface) {
	AndroidSurface *s = (AndroidSurface *)surface;
	if (eglGetCurrentSurface(EGL_DRAW) == s->surf) eglMakeCurrent(g_dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, g_ctx);
	dropSurface(s);
	free(s);
}

long long voidPlatformSurfaceNative(void *surface) { (void)surface; return 0; }

// Release the context from the calling thread (render thread teardown) so a future render
// thread can make it current again.
void voidEmbedDetach(void) {
	if (g_dpy != EGL_NO_DISPLAY) {
		eglMakeCurrent(g_dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
	}
}

void voidGfxSetup(void) {
	if (!doorValid()) voidFail("gfxSetup before voidViewCreate made the EGL context");
}

// The screen pass draws into the current view's EGL surface, which is framebuffer 0 on GL and
// has no view objects.
int32_t voidSwapchainWidth(void) { return voidViewsFbWidth(); }
int32_t voidSwapchainHeight(void) { return voidViewsFbHeight(); }
int32_t voidSwapchainSampleCount(void) { return voidViewsSampleCount(); }
void *voidSwapchainRenderView(void) { return NULL; }
void *voidSwapchainResolveView(void) { return NULL; }
void *voidSwapchainDepthStencilView(void) { return NULL; }

void voidDriverPresent(void) { voidViewsPresent(); }

// M2 readback — the surface drawn last (a pbuffer keeps it after present), RGBA8, bottom-up GL order.
void voidAndroidReadPixels(int w, int h, unsigned char *out) {
	glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, out);
}
