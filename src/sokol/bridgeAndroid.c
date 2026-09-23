// Void sokol driver — Android (GLES3 via EGL). Host-driven: no sokol_app. The host (RN
// Fabric SurfaceView, or a headless pbuffer view) owns the surface and the render loop and
// drives the views in views.c. One EGL context is shared by every view; each view has its own
// EGL window surface. Single sokol_gfx implementation unit on Android.

#define SOKOL_IMPL
#define SOKOL_GLES3

#include <EGL/egl.h>
#include <GLES3/gl3.h>
#include <stdlib.h>
#include <unistd.h>

#include "bridge.h"
#include "views.h"
#include "sokol_log.h"

static EGLDisplay g_dpy = EGL_NO_DISPLAY;
static EGLContext g_ctx = EGL_NO_CONTEXT;
static EGLConfig g_cfg;
static int g_generation = 1;
static int g_contextLost = 0;

typedef struct {
	const void *window;
	EGLSurface surf;
	int w, h;
} AndroidSurface;

static void call0(msClosure c) {
	if (!c.fn) return;
	if (c.env) ((void (*)(void *))c.fn)(c.env);
	else ((void (*)(void))c.fn)();
}

static int egl_boot(void) {
	g_dpy = eglGetDisplay(EGL_DEFAULT_DISPLAY);
	if (g_dpy == EGL_NO_DISPLAY) return 0;
	if (!eglInitialize(g_dpy, NULL, NULL)) return 0;
	EGLint cfgAttr[] = {
		EGL_SURFACE_TYPE, EGL_WINDOW_BIT | EGL_PBUFFER_BIT,
		EGL_RENDERABLE_TYPE, EGL_OPENGL_ES2_BIT,
		EGL_RED_SIZE, 8, EGL_GREEN_SIZE, 8, EGL_BLUE_SIZE, 8, EGL_ALPHA_SIZE, 8,
		EGL_DEPTH_SIZE, 0, EGL_NONE
	};
	EGLint n = 0;
	if (!eglChooseConfig(g_dpy, cfgAttr, &g_cfg, 1, &n) || n < 1) return 0;
	eglBindAPI(EGL_OPENGL_ES_API);
	EGLint ctxAttr[] = { EGL_CONTEXT_CLIENT_VERSION, 3, EGL_NONE };
	g_ctx = eglCreateContext(g_dpy, g_cfg, EGL_NO_CONTEXT, ctxAttr);
	return g_ctx != EGL_NO_CONTEXT;
}

static void sokolSetup(void) {
	sg_desc d = {0};
	d.environment.defaults.color_format = SG_PIXELFORMAT_RGBA8;
	d.environment.defaults.depth_format = SG_PIXELFORMAT_NONE;
	d.environment.defaults.sample_count = 1;
	d.logger.func = slog_func;
	sg_setup(&d);
	if (!sg_isvalid()) voidFail("sg_setup on the EGL context failed");
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

// Asset loaders use relative paths ("assets/test.png"); the host extracts APK assets to a
// real dir and tells us its root, so init2d's loads resolve (scoped chdir, like iOS bundles).
static char g_assetRoot[1024] = {0};

void voidEmbedSetAssetRoot(const char *p) {
	size_t n = 0;
	while (p[n] && n < sizeof(g_assetRoot) - 1) { g_assetRoot[n] = p[n]; n++; }
	g_assetRoot[n] = 0;
}

void voidPlatformRunInit(msClosure init) {
	char prev[1024];
	const char *got = getcwd(prev, sizeof prev);
	if (g_assetRoot[0]) chdir(g_assetRoot);
	call0(init);
	if (got) chdir(prev);
}

void *voidPlatformSurfaceCreate(const void *native, int w, int h) {
	AndroidSurface *s = (AndroidSurface *)calloc(1, sizeof(AndroidSurface));
	s->window = native;
	s->w = w;
	s->h = h;
	s->surf = makeSurface(s);
	if (s->surf == EGL_NO_SURFACE) voidFail("EGL could not make a %dx%d surface: 0x%04x", w, h, eglGetError());
	if (!sg_isvalid()) {
		makeCurrent(s);
		sokolSetup();
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
// is gone. The next frame makes a new context, remakes every view's surface and sets sokol up
// again, then counts a new generation: void3d's renderer sees it (gpu3d contextGeneration),
// drops its stale handles and rebuilds targets, samplers, pipelines and the palette LUT from
// CPU data. The app's meshes and textures are not rebuilt yet (void3d M5), nor is void2d.

int voidGpuGeneration(void) { return g_generation; }

// Forces the rebuild on the next frame, to exercise it on a device without a real loss.
void voidEmbedLoseContext(void) { g_contextLost = 1; }

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

static void restore_context(AndroidSurface *current) {
	// sokol frees its pools here; the GL deletes it issues go to the lost context, which
	// ignores them. Stale sokol ids may be handed out again after sg_setup, so the owners of
	// the old ones must drop them without destroying (the generation tells them).
	sg_shutdown();
	eglMakeCurrent(g_dpy, EGL_NO_SURFACE, EGL_NO_SURFACE, EGL_NO_CONTEXT);
	voidViewsEachSurface(dropSurface);
	if (g_ctx != EGL_NO_CONTEXT) eglDestroyContext(g_dpy, g_ctx);
	g_ctx = EGL_NO_CONTEXT;
	if (!egl_boot()) voidFail("EGL could not rebuild the context after a loss: 0x%04x", eglGetError());
	voidViewsEachSurface(remakeSurface);
	makeCurrent(current);
	sokolSetup();
	g_generation++;
	g_contextLost = 0;
}

int voidPlatformSurfaceAcquire(void *surface) {
	AndroidSurface *s = (AndroidSurface *)surface;
	if (g_contextLost) restore_context(s);
	makeCurrent(s);
	return 1;
}

void voidPlatformSurfaceSwapchain(void *surface, sg_swapchain *swapchain) {
	(void)surface;
	swapchain->color_format = SG_PIXELFORMAT_RGBA8;
	swapchain->gl.framebuffer = 0;
}

void voidPlatformSurfacePresent(void *surface) {
	AndroidSurface *s = (AndroidSurface *)surface;
	if (!eglSwapBuffers(g_dpy, s->surf) && eglGetError() == EGL_CONTEXT_LOST) g_contextLost = 1;
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
	if (!sg_isvalid()) voidFail("gfxSetup before voidViewCreate made the EGL context");
}

int voidFbWidth(void) { return voidViewsFbWidth(); }
int voidFbHeight(void) { return voidViewsFbHeight(); }
float voidDpiScale(void) { return voidViewsDpiScale(); }
int voidKeyDown(int keycode) { (void)keycode; return 0; }
sg_swapchain voidDriverSwapchain(void) { return voidViewsSwapchain(); }
void voidDriverPresent(void) { voidViewsPresent(); }

// M2 readback — the surface drawn last (a pbuffer keeps it after present), RGBA8, bottom-up GL order.
void voidAndroidReadPixels(int w, int h, unsigned char *out) {
	glReadPixels(0, 0, w, h, GL_RGBA, GL_UNSIGNED_BYTE, out);
}
