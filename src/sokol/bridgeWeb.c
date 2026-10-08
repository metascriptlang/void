// The window-only driver: the browser canvas under emscripten and the desktop GL window
// (-d:voidGlCore) through sokol_app. bridgeWin.c carries the same window path beside its
// host views.

#include <stdbool.h>

#include "backend.h"
#include "bridge.h"
#include "views.h"

#if defined(_WIN32) && !defined(SOKOL_GLCORE)
#error "void: bridgeWeb.c on Windows is the GL core driver; define SOKOL_GLCORE (golden.sh)"
#endif
#include "sokol_app.h"
#include "sokol_glue.h"
#include "sokol_log.h"
#ifdef VOID_PROFILER
#include "../void2d/frameClock.h"
#endif

static void call0(msClosure c) {
	if (!c.fn) return;
	if (c.env) ((void (*)(void *))c.fn)(c.env);
	else ((void (*)(void))c.fn)();
}

static msClosure s_init;
static msClosure s_frame;
static bool s_keys[SAPP_MAX_KEYCODES];

static void _init(void) { call0(s_init); }
static void _frame(void) { call0(s_frame); }

static int s_reqW = 0;
static int s_reqH = 0;
static void _event(const sapp_event *e) {
#ifdef VOID_PROFILER
	if (e->type == SAPP_EVENTTYPE_KEY_DOWN || e->type == SAPP_EVENTTYPE_KEY_UP
		|| e->type == SAPP_EVENTTYPE_CHAR || e->type == SAPP_EVENTTYPE_MOUSE_DOWN
		|| e->type == SAPP_EVENTTYPE_MOUSE_UP || e->type == SAPP_EVENTTYPE_MOUSE_SCROLL) {
		voidProfileInput();
	}
#endif
	if (e->type == SAPP_EVENTTYPE_KEY_DOWN) {
		if (e->key_code == SAPP_KEYCODE_ESCAPE) sapp_request_quit();
		s_keys[e->key_code] = true;
	} else if (e->type == SAPP_EVENTTYPE_KEY_UP) {
		s_keys[e->key_code] = false;
	}
}

static void _cleanup(void) { sg_shutdown(); }

void voidRunConfigured(int w, int h, int sampleCount, int highDpi, msClosure init, msClosure frame) {
	s_init = init;
	s_reqW = w;
	s_reqH = h;
	s_frame = frame;
	sapp_desc d = {0};
	d.init_cb = _init;
	d.frame_cb = _frame;
	d.event_cb = _event;
	d.cleanup_cb = _cleanup;
	d.width = w;
	d.height = h;
	d.sample_count = sampleCount;
	d.high_dpi = highDpi != 0;
	d.window_title = "Void — sokol";
	d.logger.func = slog_func;
	sapp_run(&d);
}

void voidRequestedSize(int *w, int *h) { *w = s_reqW; *h = s_reqH; }

void voidRun(int w, int h, msClosure init, msClosure frame) {
	voidRunConfigured(w, h, 4, 1, init, frame);
}

void voidGfxSetup(void) {
	sg_desc d = {0};
	d.environment = sglue_environment();
	d.logger.func = slog_func;
	sg_setup(&d);
}

int voidFbWidth(void) { return sapp_width(); }
int voidFbHeight(void) { return sapp_height(); }
float voidDpiScale(void) { return sapp_dpi_scale(); }

int voidKeyDown(int keycode) {
	if (keycode < 0 || keycode >= SAPP_MAX_KEYCODES) return 0;
	return s_keys[keycode] ? 1 : 0;
}

sg_swapchain voidDriverSwapchain(void) { return sglue_swapchain(); }

void voidDriverPresent(void) {}
