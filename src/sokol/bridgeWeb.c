// The browser canvas under emscripten and the desktop GL window (-d:voidGlCore). Two drivers,
// as in bridgeWin.c: the sokol_app window (voidRun) and, in the browser, host views, one per
// canvas a page hands to Module.voidStart (docs/EMBED.md "Web"). The first of voidRun or
// voidViewCreate chooses the driver for the document.

#if defined(__EMSCRIPTEN__)
#include <emscripten.h>
#include <emscripten/html5.h>
#include <stdio.h>
#endif
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#if defined(__EMSCRIPTEN__) && defined(SOKOL_WGPU)
#include <webgpu/webgpu.h>
#endif

#include "backend.h"
#include "bridge.h"
#include "views.h"

#if defined(_WIN32) && !defined(SOKOL_GLCORE)
#error "void: bridgeWeb.c on Windows is the GL core driver; define SOKOL_GLCORE (golden.sh)"
#endif
#include "sokol_app.h"
#include "sokol_glue.h"
#include "sokol_log.h"
#include "appWindow.h"
#ifdef VOID_PROFILER
#include "../void2d/frameClock.h"
#endif

typedef enum { DRIVER_NONE, DRIVER_WINDOW, DRIVER_VIEWS } VoidDriver;
static VoidDriver s_driver = DRIVER_NONE;
static int s_generation = 1;

int voidGpuGeneration(void) { return s_generation; }

static void call0(msClosure c) {
	if (!c.fn) return;
	if (c.env) ((void (*)(void *))c.fn)(c.env);
	else ((void (*)(void))c.fn)();
}

static msClosure s_init;
static msClosure s_frame;
static bool s_keys[SAPP_MAX_KEYCODES];

static int s_textInput = -1;

#if defined(__EMSCRIPTEN__)
static int s_imeX, s_imeY, s_imeW, s_imeH;
static bool s_imeReady;

EM_JS_DEPS(voidWebIme, "$withStackSave,$stringToUTF8OnStack");

EMSCRIPTEN_KEEPALIVE void voidWebImeText(int type, const char *utf8, int cursor) {
	voidAppTextDeliver(type, utf8, cursor);
}

// The browser composes only into a focused editable element, so a hidden textarea beside the
// canvas takes the composition. Typing outside a composition still arrives as sokol Char
// (its input event only empties the textarea); a composition arrives once, at compositionend.
EM_JS(void, voidJsImeSetup, (int preedit, int textInput), {
	const canvas = Module.sapp_emsc_target;
	const input = document.createElement('textarea');
	for (const [name, value] of [['autocomplete', 'off'], ['autocorrect', 'off'], ['autocapitalize', 'off'],
		['spellcheck', 'false'], ['aria-hidden', 'true'], ['tabindex', '-1']]) {
		input.setAttribute(name, value);
	}
	input.style.cssText = 'position:fixed;left:0;top:0;width:1px;height:1px;margin:0;padding:0;border:0;' +
		'outline:none;resize:none;overflow:hidden;opacity:0;pointer-events:none;';
	canvas.insertAdjacentElement('afterend', input);
	const send = (type, text, cursor) => withStackSave(() => _voidWebImeText(type, stringToUTF8OnStack(text), cursor));
	input.addEventListener('compositionstart', () => { Module.voidComposing = true; });
	input.addEventListener('input', (e) => {
		if (e.isComposing) send(preedit, input.value, input.selectionStart);
		else input.value = '';
	});
	input.addEventListener('compositionend', (e) => {
		Module.voidComposing = false;
		send(preedit, '', 0);
		if (e.data) send(textInput, e.data, 0);
		input.value = '';
	});
	input.addEventListener('keydown', (e) => { if (e.key === 'Tab') e.preventDefault(); });
	canvas.addEventListener('pointerdown', () => {
		if (Module.voidImeOn) setTimeout(() => input.focus({ preventScroll: true }), 0);
	});
	Module.voidImeInput = input;
	Module.voidImeOn = false;
	Module.voidComposing = false;
});

EM_JS(int, voidJsComposing, (void), { return Module.voidComposing ? 1 : 0; });

EM_JS(void, voidJsImeFocus, (int on), {
	const input = Module.voidImeInput;
	Module.voidImeOn = on !== 0;
	if (Module.voidImeOn) input.focus({ preventScroll: true });
	else if (document.activeElement === input) input.blur();
});

EM_JS(void, voidJsImeRect, (double x, double y, double w, double h), {
	const input = Module.voidImeInput;
	const r = Module.sapp_emsc_target.getBoundingClientRect();
	input.style.left = (r.left + x) + 'px';
	input.style.top = (r.top + y) + 'px';
	input.style.width = Math.max(1, w) + 'px';
	input.style.height = Math.max(1, h) + 'px';
	input.style.fontSize = Math.max(1, h) + 'px';
	input.style.lineHeight = Math.max(1, h) + 'px';
});

static void applyImeRect(void) {
	const double scale = sapp_dpi_scale();
	voidJsImeRect(s_imeX / scale, s_imeY / scale, s_imeW / scale, s_imeH / scale);
}

void voidSetTextInput(int on) {
	s_textInput = on != 0;
	if (s_imeReady) voidJsImeFocus(s_textInput);
}

void voidSetImeRect(int x, int y, int w, int h) {
	s_imeX = x;
	s_imeY = y;
	s_imeW = w;
	s_imeH = h;
	if (s_imeReady) applyImeRect();
}

static void imeSetup(void) {
	voidJsImeSetup(VOID_EVENT_PREEDIT, VOID_EVENT_TEXT_INPUT);
	s_imeReady = true;
	applyImeRect();
	if (s_textInput != -1) voidJsImeFocus(s_textInput);
}

// sokol_app is told to bubble every key so the browser can compose; until text input is on,
// the keys sokol_app would have kept from the browser are kept here.
// A key the IME takes while composing reaches the app as neither a key nor a Char.
static bool imeTookKey(const sapp_event *e) {
	return s_imeReady && voidJsComposing()
		&& (e->type == SAPP_EVENTTYPE_KEY_DOWN || e->type == SAPP_EVENTTYPE_KEY_UP || e->type == SAPP_EVENTTYPE_CHAR);
}

static void keepKeysFromBrowser(const sapp_event *e) {
	if (s_textInput == 1) return;
	if (e->type == SAPP_EVENTTYPE_CHAR
		|| ((e->type == SAPP_EVENTTYPE_KEY_DOWN || e->type == SAPP_EVENTTYPE_KEY_UP) && e->key_code >= SAPP_KEYCODE_WORLD_1)) {
		sapp_consume_event();
	}
}
#else
void voidSetTextInput(int on) { s_textInput = on != 0; }
void voidSetImeRect(int x, int y, int w, int h) { (void)x; (void)y; (void)w; (void)h; }
static void imeSetup(void) {}
static bool imeTookKey(const sapp_event *e) { (void)e; return false; }
static void keepKeysFromBrowser(const sapp_event *e) { (void)e; }
#endif

static void _init(void) {
	imeSetup();
	call0(s_init);
}
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
	if (imeTookKey(e)) return;
	keepKeysFromBrowser(e);
	if (e->type == SAPP_EVENTTYPE_KEY_DOWN) {
		s_keys[e->key_code] = true;
	} else if (e->type == SAPP_EVENTTYPE_KEY_UP) {
		s_keys[e->key_code] = false;
	}
	if (voidAppEventDeliver(e)) return;
	if (e->type == SAPP_EVENTTYPE_KEY_DOWN && e->key_code == SAPP_KEYCODE_ESCAPE) sapp_request_quit();
}

static void _cleanup(void) { sg_shutdown(); }

#if defined(__EMSCRIPTEN__)
static void leaveCallerSuspendedWhileFramesRun(void) { emscripten_exit_with_live_runtime(); }
#else
static void leaveCallerSuspendedWhileFramesRun(void) {}
#endif

void voidRunConfigured(int w, int h, int sampleCount, int highDpi, msClosure init, msClosure frame) {
	if (s_driver == DRIVER_VIEWS) voidFail("voidRun: this document already drives Void through host views");
	s_driver = DRIVER_WINDOW;
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
	d.composite_mode = SAPP_COMPOSITEMODE_PREMULTIPLIED;
	d.window_title = voidWindowTitle();
	d.html5.update_document_title = voidWindowTitleSet() != 0;
	d.html5.bubble_key_events = true;
	d.html5.bubble_char_events = true;
	d.logger.func = slog_func;
	sapp_run(&d);
	leaveCallerSuspendedWhileFramesRun();
}

void voidRequestedSize(int *w, int *h) { *w = s_reqW; *h = s_reqH; }

void voidRun(int w, int h, msClosure init, msClosure frame) {
	voidRunConfigured(w, h, 4, 1, init, frame);
}

#if defined(__EMSCRIPTEN__)

// R3F's shape (react-three-fiber d604b18): one runtime per document, a root per canvas, one
// animation-frame loop over the live roots that cancels itself when none is left
// (core/loop.ts:95-130), and a stop that releases the renderer's context
// (core/renderer.ts:22-42). The canvas reaches C as an id whose selector
// '#void-view-<id>' resolves through emscripten's specialHTMLTargets.
EM_JS(void, voidWebInstallStart, (int needsDevice), {
	if (Module.voidStart) return;
	var live = new Map();
	var nextId = 1;
	var pending = 0;
	function measure(canvas) {
		var dpr = window.devicePixelRatio || 1;
		return {
			w: Math.max(1, Math.round(canvas.clientWidth * dpr)),
			h: Math.max(1, Math.round(canvas.clientHeight * dpr)),
			dpr: dpr,
		};
	}
	function tick() {
		pending = 0;
		live.forEach(function(v) {
			var size = measure(v.canvas);
			if (size.w != v.w || size.h != v.h || size.dpr != v.dpr) {
				_voidWebViewResize(v.view, size.w, size.h, size.dpr);
				v.w = size.w; v.h = size.h; v.dpr = size.dpr;
			}
			_voidWebViewFrame(v.view);
		});
		if (live.size) pending = requestAnimationFrame(tick);
	}
	function begin(id, canvas) {
		var key = '#void-view-' + id;
		specialHTMLTargets[key] = canvas;
		var size = measure(canvas);
		var view = _voidWebViewCreate(id, size.w, size.h, size.dpr);
		live.set(id, { canvas: canvas, key: key, view: view, w: size.w, h: size.h, dpr: size.dpr });
		if (!pending) pending = requestAnimationFrame(tick);
	}
	Module.voidStart = function(canvas, onError) {
		var id = nextId++;
		var stopped = false;
		if (needsDevice && !Module.preinitializedWebGPUDevice) {
			Promise.resolve()
				.then(function() { return navigator.gpu.requestAdapter(); })
				.then(function(adapter) {
					if (!adapter) throw new Error('navigator.gpu.requestAdapter() gave no adapter');
					return adapter.requestDevice();
				})
				.then(function(device) {
					Module.preinitializedWebGPUDevice = Module.preinitializedWebGPUDevice || device;
					if (!stopped) begin(id, canvas);
				}, function(error) {
					if (stopped) return;
					var failure = new Error('void: this browser gave no WebGPU device: ' + (error && error.message || error));
					if (onError) onError(failure); else console.error(failure.message);
				});
		} else {
			begin(id, canvas);
		}
		return function stop() {
			if (stopped) return;
			stopped = true;
			var v = live.get(id);
			if (!v) return;
			live.delete(id);
			_voidWebViewDestroy(v.view);
			delete specialHTMLTargets[v.key];
			if (!live.size && pending) {
				cancelAnimationFrame(pending);
				pending = 0;
			}
		};
	};
	if (Module.onVoidReady) Module.onVoidReady();
});

void voidWebInstall(void) {
#if defined(SOKOL_WGPU)
	voidWebInstallStart(1);
#else
	voidWebInstallStart(0);
#endif
	leaveCallerSuspendedWhileFramesRun();
}

EMSCRIPTEN_KEEPALIVE int voidWebViewCreate(int id, int w, int h, float scale) {
	return voidViewCreate(id, w, h, scale);
}
EMSCRIPTEN_KEEPALIVE void voidWebViewResize(int view, int w, int h, float scale) {
	voidViewResize(view, w, h, scale);
}
EMSCRIPTEN_KEEPALIVE int voidWebViewFrame(int view) { return voidViewFrame(view); }
EMSCRIPTEN_KEEPALIVE void voidWebViewDestroy(int view) { voidViewDestroy(view); }

typedef struct {
	int id;
	char selector[32];
	int w, h;
#if defined(SOKOL_WGPU)
	WGPUSurface surface;
	WGPUTexture texture;
	WGPUTextureView view;
	WGPUTexture msaa;
	WGPUTextureView msaaView;
#else
	EMSCRIPTEN_WEBGL_CONTEXT_HANDLE context;
#endif
} WebSurface;

static void setupViewsGfx(void);

#if defined(SOKOL_WGPU)

static WGPUInstance s_instance;
static WGPUDevice s_device;
static WGPUTextureFormat s_format;

EM_JS(int, voidWebPrefersBgra, (void), {
	return navigator.gpu.getPreferredCanvasFormat() == 'bgra8unorm' ? 1 : 0;
});

void voidPlatformDeviceEnsure(void) {
	if (s_driver == DRIVER_WINDOW) voidFail("voidViewCreate: this document already runs a sokol_app canvas");
	if (s_driver == DRIVER_VIEWS) return;
	s_instance = wgpuCreateInstance(NULL);
	if (!s_instance) voidFail("voidViewCreate: wgpuCreateInstance failed");
	s_device = emscripten_webgpu_get_device();
	if (!s_device) voidFail("voidViewCreate: no WebGPU device; Module.voidStart requests one");
	s_format = voidWebPrefersBgra() ? WGPUTextureFormat_BGRA8Unorm : WGPUTextureFormat_RGBA8Unorm;
	setupViewsGfx();
	s_driver = DRIVER_VIEWS;
}

static void setupViewsGfx(void) {
	sg_desc d = {0};
	d.environment.wgpu.device = s_device;
	d.environment.defaults.color_format =
		s_format == WGPUTextureFormat_BGRA8Unorm ? SG_PIXELFORMAT_BGRA8 : SG_PIXELFORMAT_RGBA8;
	d.environment.defaults.depth_format = SG_PIXELFORMAT_NONE;
	d.environment.defaults.sample_count = voidViewsSampleCount();
	d.logger.func = slog_func;
	sg_setup(&d);
	if (!sg_isvalid()) voidFail("sg_setup on the WebGPU device failed");
}

static void configure(WebSurface *s) {
	WGPUSurfaceConfiguration c = {0};
	c.device = s_device;
	c.format = s_format;
	c.usage = WGPUTextureUsage_RenderAttachment;
	c.width = (uint32_t)s->w;
	c.height = (uint32_t)s->h;
	c.alphaMode = WGPUCompositeAlphaMode_Premultiplied;
	c.presentMode = WGPUPresentMode_Fifo;
	wgpuSurfaceConfigure(s->surface, &c);
}

static void dropMsaa(WebSurface *s) {
	if (s->msaaView) wgpuTextureViewRelease(s->msaaView);
	if (s->msaa) wgpuTextureRelease(s->msaa);
	s->msaaView = NULL;
	s->msaa = NULL;
}

// sokol_app's own WebGPU swapchain does the same: the pass renders into a multisampled texture
// and resolves into the canvas texture (sokol_app.h _sapp_wgpu_create_swapchain).
static void makeMsaa(WebSurface *s) {
	dropMsaa(s);
	const int samples = voidViewsSampleCount();
	if (samples == 1) return;
	WGPUTextureDescriptor desc = {0};
	desc.usage = WGPUTextureUsage_RenderAttachment;
	desc.dimension = WGPUTextureDimension_2D;
	desc.size.width = (uint32_t)s->w;
	desc.size.height = (uint32_t)s->h;
	desc.size.depthOrArrayLayers = 1;
	desc.format = s_format;
	desc.mipLevelCount = 1;
	desc.sampleCount = (uint32_t)samples;
	s->msaa = wgpuDeviceCreateTexture(s_device, &desc);
	if (!s->msaa) voidFail("the %dx%d target at %d samples failed", s->w, s->h, samples);
	s->msaaView = wgpuTextureCreateView(s->msaa, NULL);
	if (!s->msaaView) voidFail("the view of the %d-sample target failed", samples);
}

static bool makeSurface(WebSurface *s) {
	WGPUEmscriptenSurfaceSourceCanvasHTMLSelector canvas = {0};
	canvas.chain.sType = WGPUSType_EmscriptenSurfaceSourceCanvasHTMLSelector;
	canvas.selector = (WGPUStringView){ .data = s->selector, .length = WGPU_STRLEN };
	WGPUSurfaceDescriptor desc = {0};
	desc.nextInChain = &canvas.chain;
	s->surface = wgpuInstanceCreateSurface(s_instance, &desc);
	if (!s->surface) return false;
	configure(s);
	makeMsaa(s);
	return true;
}

static void resizeSurface(WebSurface *s) {
	configure(s);
	makeMsaa(s);
}

int voidPlatformSurfaceAcquire(void *surface) {
	WebSurface *s = (WebSurface *)surface;
	WGPUSurfaceTexture current = {0};
	wgpuSurfaceGetCurrentTexture(s->surface, &current);
	if (current.status != WGPUSurfaceGetCurrentTextureStatus_SuccessOptimal
		&& current.status != WGPUSurfaceGetCurrentTextureStatus_SuccessSuboptimal) {
		if (current.texture) wgpuTextureRelease(current.texture);
		return 0;
	}
	s->texture = current.texture;
	s->view = wgpuTextureCreateView(current.texture, NULL);
	return 1;
}

void voidPlatformSurfaceSwapchain(void *surface, sg_swapchain *swapchain) {
	swapchain->color_format =
		s_format == WGPUTextureFormat_BGRA8Unorm ? SG_PIXELFORMAT_BGRA8 : SG_PIXELFORMAT_RGBA8;
	WebSurface *s = (WebSurface *)surface;
	swapchain->wgpu.render_view = s->msaaView ? s->msaaView : s->view;
	swapchain->wgpu.resolve_view = s->msaaView ? s->view : NULL;
}

void voidPlatformSurfacePresent(void *surface) {
	WebSurface *s = (WebSurface *)surface;
	if (s->view) wgpuTextureViewRelease(s->view);
	if (s->texture) wgpuTextureRelease(s->texture);
	s->view = NULL;
	s->texture = NULL;
}

static void dropSurface(WebSurface *s) {
	dropMsaa(s);
	wgpuSurfaceUnconfigure(s->surface);
	wgpuSurfaceRelease(s->surface);
}

#else // SOKOL_GLES3

static WebSurface *s_glView = NULL;
static bool s_glEverSetUp = false;

void voidPlatformDeviceEnsure(void) {
	if (s_driver == DRIVER_WINDOW) voidFail("voidViewCreate: this document already runs a sokol_app canvas");
	if (s_driver == DRIVER_VIEWS) return;
	s_driver = DRIVER_VIEWS;
}

static void setupViewsGfx(void) {
	sg_desc d = {0};
	d.environment.defaults.color_format = SG_PIXELFORMAT_RGBA8;
	d.environment.defaults.depth_format = SG_PIXELFORMAT_NONE;
	d.environment.defaults.sample_count = voidViewsSampleCount();
	d.logger.func = slog_func;
	sg_setup(&d);
	if (!sg_isvalid()) voidFail("sg_setup on the WebGL2 context failed");
}

// A WebGL2 context belongs to its canvas, so the device of this driver is the one live view's
// context: a second live view is refused, and a view made after a stop sets sokol up again on
// its own context and bumps the GPU generation, whose owners drop the old ids (bridgeAndroid.c
// restore_context, src/gpu/door.c doorContextGeneration).
static bool makeSurface(WebSurface *s) {
	if (s_glView) {
		voidFail("voidViewCreate: WebGL2 runs one view at a time; stop view %d first", s_glView->id);
	}
	EmscriptenWebGLContextAttributes attrs;
	emscripten_webgl_init_context_attributes(&attrs);
	attrs.majorVersion = 2;
	attrs.alpha = true;
	attrs.premultipliedAlpha = true;
	attrs.antialias = voidViewsSampleCount() > 1;
	attrs.depth = false;
	attrs.stencil = false;
	s->context = emscripten_webgl_create_context(s->selector, &attrs);
	if (s->context <= 0) return false;
	emscripten_webgl_make_context_current(s->context);
	emscripten_set_canvas_element_size(s->selector, s->w, s->h);
	setupViewsGfx();
	if (s_glEverSetUp) s_generation++;
	s_glEverSetUp = true;
	s_glView = s;
	return true;
}

static void resizeSurface(WebSurface *s) { emscripten_set_canvas_element_size(s->selector, s->w, s->h); }

int voidPlatformSurfaceAcquire(void *surface) {
	WebSurface *s = (WebSurface *)surface;
	if (emscripten_is_webgl_context_lost(s->context)) return 0;
	emscripten_webgl_make_context_current(s->context);
	return 1;
}

void voidPlatformSurfaceSwapchain(void *surface, sg_swapchain *swapchain) {
	(void)surface;
	swapchain->color_format = SG_PIXELFORMAT_RGBA8;
	swapchain->gl.framebuffer = 0;
}

void voidPlatformSurfacePresent(void *surface) { (void)surface; }

EM_JS(void, voidWebLoseContext, (EMSCRIPTEN_WEBGL_CONTEXT_HANDLE handle), {
	var gl = GL.getContext(handle).GLctx;
	var lose = gl.getExtension('WEBGL_lose_context');
	if (lose) lose.loseContext();
});

static void dropSurface(WebSurface *s) {
	emscripten_webgl_make_context_current(s->context);
	sg_shutdown();
	voidWebLoseContext(s->context);
	emscripten_webgl_destroy_context(s->context);
	s_glView = NULL;
}

#endif

void voidPlatformRunInit(msClosure init) { call0(init); }

void *voidPlatformSurfaceCreate(const void *native, int w, int h) {
	WebSurface *s = (WebSurface *)calloc(1, sizeof(WebSurface));
	if (!s) voidFail("voidViewCreate: out of memory for a web surface");
	s->id = (int)(intptr_t)native;
	snprintf(s->selector, sizeof s->selector, "#void-view-%d", s->id);
	s->w = w;
	s->h = h;
	if (!makeSurface(s)) {
		free(s);
		return NULL;
	}
	return s;
}

void voidPlatformSurfaceResize(void *surface, int w, int h) {
	WebSurface *s = (WebSurface *)surface;
	s->w = w;
	s->h = h;
	resizeSurface(s);
}

void voidPlatformSurfaceDestroy(void *surface) {
	WebSurface *s = (WebSurface *)surface;
	dropSurface(s);
	free(s);
}

long long voidPlatformSurfaceNative(void *surface) { return ((WebSurface *)surface)->id; }

#endif // __EMSCRIPTEN__

__attribute__((noreturn)) static void noDriver(const char *op) {
	voidFail("%s before voidRun or voidViewCreate chose a driver", op);
}

void voidGfxSetup(void) {
	switch (s_driver) {
		case DRIVER_WINDOW: {
			sg_desc d = {0};
			d.environment = sglue_environment();
			d.logger.func = slog_func;
			sg_setup(&d);
			break;
		}
		case DRIVER_VIEWS: break;
		case DRIVER_NONE: noDriver("gfxSetup");
	}
}

#if defined(__EMSCRIPTEN__)
#define VIEWS_OR(call, fallback) (s_driver == DRIVER_VIEWS ? (call) : (fallback))
#else
#define VIEWS_OR(call, fallback) (fallback)
#endif

int voidFbWidth(void) {
	if (s_driver == DRIVER_NONE) noDriver("fbWidth");
	return VIEWS_OR(voidViewsFbWidth(), sapp_width());
}

int voidFbHeight(void) {
	if (s_driver == DRIVER_NONE) noDriver("fbHeight");
	return VIEWS_OR(voidViewsFbHeight(), sapp_height());
}

float voidDpiScale(void) {
	if (s_driver == DRIVER_NONE) noDriver("dpiScale");
	return VIEWS_OR(voidViewsDpiScale(), sapp_dpi_scale());
}

int voidKeyDown(int keycode) {
	if (s_driver != DRIVER_WINDOW || keycode < 0 || keycode >= SAPP_MAX_KEYCODES) return 0;
	return s_keys[keycode] ? 1 : 0;
}

sg_swapchain voidDriverSwapchain(void) {
	if (s_driver == DRIVER_NONE) noDriver("beginPass");
	return VIEWS_OR(voidViewsSwapchain(), sglue_swapchain());
}

void voidDriverPresent(void) {
#if defined(__EMSCRIPTEN__)
	if (s_driver == DRIVER_VIEWS) voidViewsPresent();
#endif
}
