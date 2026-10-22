#include <emscripten.h>
#include <emscripten/html5.h>
#include <stdio.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#if defined(VOID_WGPU)
#include <webgpu/webgpu.h>
#else
#include <emscripten/html5_webgl.h>
#endif

#include "backend.h"
#include "bridge.h"
#include "views.h"
#include "appWindow.h"
#include "../gpu/door.h"
#include "../platform/swapchain.h"
#include "../platform/web/window.h"
#ifdef VOID_PROFILER
#include "../void2d/frameClock.h"
#endif

typedef enum { DRIVER_NONE, DRIVER_WINDOW, DRIVER_VIEWS } VoidDriver;
static VoidDriver s_driver = DRIVER_NONE;
static int s_generation = 1;
static int s_contextLost = 0;

static void setupWindowDoor(void);
static void setupViewsGfx(void);

int voidGpuGeneration(void) { return s_generation; }
void voidLoseContext(void) { s_contextLost = 1; }

static void restoreContext(void) {
	doorShutdown();
	if (s_driver == DRIVER_WINDOW) setupWindowDoor();
	else setupViewsGfx();
	s_generation++;
	s_contextLost = 0;
}

static void call0(msClosure c) {
	if (!c.fn) return;
	if (c.env) ((void (*)(void *))c.fn)(c.env);
	else ((void (*)(void))c.fn)();
}

static msClosure s_init;
static msClosure s_frame;
static bool s_keys[VOID_KEY_COUNT];

static int s_textInput = -1;

static int s_imeX, s_imeY, s_imeW, s_imeH;
static bool s_imeReady;

EM_JS_DEPS(voidWebIme, "$withStackSave,$stringToUTF8OnStack");

EMSCRIPTEN_KEEPALIVE void voidWebImeText(int type, const char *utf8, int cursor) {
	voidAppTextDeliver(type, utf8, cursor);
}

// The browser composes only into a focused editable element, so a hidden textarea beside the
// canvas takes the composition. Typing outside a composition still arrives as Char (its input
// event only empties the textarea); a composition arrives once, at compositionend.
EM_JS(void, voidJsImeSetup, (int preedit, int textInput), {
	const canvas = Module.voidWebTarget;
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
	const r = Module.voidWebTarget.getBoundingClientRect();
	input.style.left = (r.left + x) + 'px';
	input.style.top = (r.top + y) + 'px';
	input.style.width = Math.max(1, w) + 'px';
	input.style.height = Math.max(1, h) + 'px';
	input.style.fontSize = Math.max(1, h) + 'px';
	input.style.lineHeight = Math.max(1, h) + 'px';
});

static void applyImeRect(void) {
	const double scale = voidWebDpiScale();
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

// The window bubbles every key so the browser can compose; until text input is on, the keys
// a window that keeps them would have kept from the browser are kept here.
// A key the IME takes while composing reaches the app as neither a key nor a Char.
static bool imeTookKey(const VoidAppEvent *e) {
	return s_imeReady && voidJsComposing()
		&& (e->type == VOID_EVENT_KEY_DOWN || e->type == VOID_EVENT_KEY_UP || e->type == VOID_EVENT_CHAR);
}

static void keepKeysFromBrowser(const VoidAppEvent *e) {
	if (s_textInput == 1) return;
	if (e->type == VOID_EVENT_CHAR
		|| ((e->type == VOID_EVENT_KEY_DOWN || e->type == VOID_EVENT_KEY_UP) && e->keyCode >= VOID_KEY_WORLD_1)) {
		voidWebConsumeEvent();
	}
}

static void _init(void) {
	imeSetup();
	call0(s_init);
}

static void _frame(void) {
	if (s_contextLost) restoreContext();
	call0(s_frame);
}

static int s_reqW = 0;
static int s_reqH = 0;
static void _event(const VoidAppEvent *e) {
#ifdef VOID_PROFILER
	if (e->type == VOID_EVENT_KEY_DOWN || e->type == VOID_EVENT_KEY_UP
		|| e->type == VOID_EVENT_CHAR || e->type == VOID_EVENT_MOUSE_DOWN
		|| e->type == VOID_EVENT_MOUSE_UP || e->type == VOID_EVENT_MOUSE_SCROLL) {
		voidProfileInput();
	}
#endif
	if (e->type == VOID_EVENT_RESUMED) s_contextLost = 1;
	if (imeTookKey(e)) return;
	keepKeysFromBrowser(e);
	if (e->type == VOID_EVENT_KEY_DOWN) {
		s_keys[e->keyCode] = true;
	} else if (e->type == VOID_EVENT_KEY_UP) {
		s_keys[e->keyCode] = false;
	}
	if (voidAppDeliver(e)) return;
	if (e->type == VOID_EVENT_KEY_DOWN && e->keyCode == VOID_KEY_ESCAPE) voidWebRequestQuit();
}

static void _cleanup(void) { doorShutdown(); }

static void leaveCallerSuspendedWhileFramesRun(void) { emscripten_exit_with_live_runtime(); }

void voidRunConfigured(int w, int h, int sampleCount, int highDpi, msClosure init, msClosure frame) {
	if (s_driver == DRIVER_VIEWS) voidFail("voidRun: this document already drives Void through host views");
	s_driver = DRIVER_WINDOW;
	s_init = init;
	s_reqW = w;
	s_reqH = h;
	s_frame = frame;
	VoidWebDesc d = {0};
	d.init = _init;
	d.frame = _frame;
	d.event = _event;
	d.cleanup = _cleanup;
	d.sampleCount = sampleCount;
	d.highDpi = highDpi != 0;
	d.title = voidWindowTitleSet() ? voidWindowTitle() : NULL;
	voidWebRun(&d);
	leaveCallerSuspendedWhileFramesRun();
}

void voidRequestedSize(int *w, int *h) { *w = s_reqW; *h = s_reqH; }

void voidRun(int w, int h, msClosure init, msClosure frame) {
	voidRunConfigured(w, h, 4, 1, init, frame);
}

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
	Module.voidStart = function(canvas) {
		var id = nextId++;
		var stopped = false;
		if (needsDevice && !Module.preinitializedWebGPUDevice) {
			navigator.gpu.requestAdapter()
				.then(function(adapter) { return adapter.requestDevice(); })
				.then(function(device) {
					Module.preinitializedWebGPUDevice = Module.preinitializedWebGPUDevice || device;
					if (!stopped) begin(id, canvas);
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
#if defined(VOID_WGPU)
	voidWebInstallStart(1);
#else
	voidWebInstallStart(0);
#endif
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
#if defined(VOID_WGPU)
	WGPUSurface surface;
	WGPUTexture texture;
	WGPUTextureView view;
#else
	EMSCRIPTEN_WEBGL_CONTEXT_HANDLE context;
#endif
} WebSurface;

static void refuseMultisample(void) {
	if (voidViewsSampleCount() != 1) {
		voidFail("voidViewCreate: web views render at 1 sample, not %d", voidViewsSampleCount());
	}
}

#if defined(VOID_WGPU)

static WGPUInstance s_instance;
static WGPUDevice s_device;
static WGPUTextureFormat s_format;

static int32_t doorColorFormat(WGPUTextureFormat format) {
	switch (format) {
		case WGPUTextureFormat_RGBA8Unorm: return DOOR_PIXEL_FORMAT_RGBA8;
		case WGPUTextureFormat_BGRA8Unorm: return DOOR_PIXEL_FORMAT_BGRA8;
		default: voidFail("the canvas format 0x%x has no door pixel format", (unsigned)format);
	}
}

static void setupWindowDoor(void) {
	doorSetup(voidWebDevice(), NULL, doorColorFormat(voidWebColorFormat()), DOOR_PIXEL_FORMAT_DEPTH, voidWebSampleCount());
	if (!doorValid()) voidFail("doorSetup on the browser window's WebGPU device failed");
}

EM_JS(int, voidWebPrefersBgra, (void), {
	return navigator.gpu.getPreferredCanvasFormat() == 'bgra8unorm' ? 1 : 0;
});

void voidPlatformDeviceEnsure(void) {
	if (s_driver == DRIVER_WINDOW) voidFail("voidViewCreate: this document already runs a Void canvas window");
	if (s_driver == DRIVER_VIEWS) return;
	refuseMultisample();
	s_instance = wgpuCreateInstance(NULL);
	if (!s_instance) voidFail("voidViewCreate: wgpuCreateInstance failed");
	s_device = emscripten_webgpu_get_device();
	if (!s_device) voidFail("voidViewCreate: no WebGPU device; Module.voidStart requests one");
	s_format = voidWebPrefersBgra() ? WGPUTextureFormat_BGRA8Unorm : WGPUTextureFormat_RGBA8Unorm;
	setupViewsGfx();
	s_driver = DRIVER_VIEWS;
}

static void setupViewsGfx(void) {
	doorSetup(s_device, NULL, doorColorFormat(s_format), DOOR_PIXEL_FORMAT_NONE, 1);
	if (!doorValid()) voidFail("doorSetup on the WebGPU device failed");
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

static bool makeSurface(WebSurface *s) {
	WGPUEmscriptenSurfaceSourceCanvasHTMLSelector canvas = {0};
	canvas.chain.sType = WGPUSType_EmscriptenSurfaceSourceCanvasHTMLSelector;
	canvas.selector = (WGPUStringView){ .data = s->selector, .length = WGPU_STRLEN };
	WGPUSurfaceDescriptor desc = {0};
	desc.nextInChain = &canvas.chain;
	s->surface = wgpuInstanceCreateSurface(s_instance, &desc);
	if (!s->surface) return false;
	configure(s);
	return true;
}

static void resizeSurface(WebSurface *s) { configure(s); }

int voidPlatformSurfaceAcquire(void *surface) {
	WebSurface *s = (WebSurface *)surface;
	if (s_contextLost) restoreContext();
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

static void *viewRenderView(const WebSurface *s) { return s->view; }

void voidPlatformSurfacePresent(void *surface) {
	WebSurface *s = (WebSurface *)surface;
	if (s->view) wgpuTextureViewRelease(s->view);
	if (s->texture) wgpuTextureRelease(s->texture);
	s->view = NULL;
	s->texture = NULL;
}

static void dropSurface(WebSurface *s) {
	wgpuSurfaceUnconfigure(s->surface);
	wgpuSurfaceRelease(s->surface);
}

#else // VOID_GLES3

static WebSurface *s_glView = NULL;
static bool s_glEverSetUp = false;

static void setupWindowDoor(void) {
	doorSetup(NULL, NULL, DOOR_PIXEL_FORMAT_RGBA8, DOOR_PIXEL_FORMAT_DEPTH, voidWebSampleCount());
	if (!doorValid()) voidFail("doorSetup on the browser window's WebGL2 context failed");
}

void voidPlatformDeviceEnsure(void) {
	if (s_driver == DRIVER_WINDOW) voidFail("voidViewCreate: this document already runs a Void canvas window");
	if (s_driver == DRIVER_VIEWS) return;
	refuseMultisample();
	s_driver = DRIVER_VIEWS;
}

static void setupViewsGfx(void) {
	doorSetup(NULL, NULL, DOOR_PIXEL_FORMAT_RGBA8, DOOR_PIXEL_FORMAT_NONE, 1);
	if (!doorValid()) voidFail("doorSetup on the WebGL2 context failed");
}

// A WebGL2 context belongs to its canvas, so the device of this driver is the one live view's
// context: a second live view is refused, and a view made after a stop sets the door up again
// on its own context and bumps the GPU generation, whose owners drop the old ids
// (bridgeAndroid.c restore_context, doorContextGeneration).
static bool makeSurface(WebSurface *s) {
	if (s_glView) {
		voidFail("voidViewCreate: WebGL2 runs one view at a time; stop view %d first", s_glView->id);
	}
	EmscriptenWebGLContextAttributes attrs;
	emscripten_webgl_init_context_attributes(&attrs);
	attrs.majorVersion = 2;
	attrs.alpha = true;
	attrs.premultipliedAlpha = true;
	attrs.antialias = false;
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
	if (s_contextLost) restoreContext();
	return 1;
}

static void *viewRenderView(const WebSurface *s) {
	(void)s;
	return NULL;
}

void voidPlatformSurfacePresent(void *surface) { (void)surface; }

EM_JS(void, voidWebLoseContext, (EMSCRIPTEN_WEBGL_CONTEXT_HANDLE handle), {
	var gl = GL.getContext(handle).GLctx;
	var lose = gl.getExtension('WEBGL_lose_context');
	if (lose) lose.loseContext();
});

static void dropSurface(WebSurface *s) {
	emscripten_webgl_make_context_current(s->context);
	doorShutdown();
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

__attribute__((noreturn)) static void noDriver(const char *op) {
	voidFail("%s before voidRun or voidViewCreate chose a driver", op);
}

void voidGfxSetup(void) {
	switch (s_driver) {
		case DRIVER_WINDOW: setupWindowDoor(); break;
		case DRIVER_VIEWS: break;
		case DRIVER_NONE: noDriver("gfxSetup");
	}
}

int voidFbWidth(void) {
	if (s_driver == DRIVER_NONE) noDriver("fbWidth");
	return s_driver == DRIVER_VIEWS ? voidViewsFbWidth() : voidWebWidth();
}

int voidFbHeight(void) {
	if (s_driver == DRIVER_NONE) noDriver("fbHeight");
	return s_driver == DRIVER_VIEWS ? voidViewsFbHeight() : voidWebHeight();
}

float voidDpiScale(void) {
	if (s_driver == DRIVER_NONE) noDriver("dpiScale");
	return s_driver == DRIVER_VIEWS ? voidViewsDpiScale() : voidWebDpiScale();
}

int voidKeyDown(int keycode) {
	if (s_driver != DRIVER_WINDOW || keycode < 0 || keycode >= VOID_KEY_COUNT) return 0;
	return s_keys[keycode] ? 1 : 0;
}

static VoidDriver screenDriver(void) {
	if (s_driver == DRIVER_NONE) noDriver("beginPass");
	return s_driver;
}

int32_t voidSwapchainWidth(void) {
	return screenDriver() == DRIVER_VIEWS ? voidViewsFbWidth() : voidWebWidth();
}

int32_t voidSwapchainHeight(void) {
	return screenDriver() == DRIVER_VIEWS ? voidViewsFbHeight() : voidWebHeight();
}

int32_t voidSwapchainSampleCount(void) {
	return screenDriver() == DRIVER_VIEWS ? voidViewsSampleCount() : voidWebSampleCount();
}

void *voidSwapchainRenderView(void) {
	if (screenDriver() == DRIVER_VIEWS) return viewRenderView((const WebSurface *)voidViewsCurrentSurface());
#if defined(VOID_WGPU)
	return voidWebRenderView();
#else
	return NULL;
#endif
}

void *voidSwapchainResolveView(void) {
	if (screenDriver() == DRIVER_VIEWS) return NULL;
#if defined(VOID_WGPU)
	return voidWebResolveView();
#else
	return NULL;
#endif
}

void *voidSwapchainDepthStencilView(void) {
	if (screenDriver() == DRIVER_VIEWS) return NULL;
#if defined(VOID_WGPU)
	return voidWebDepthStencilView();
#else
	return NULL;
#endif
}

void voidDriverPresent(void) {
	if (s_driver == DRIVER_VIEWS) voidViewsPresent();
}
