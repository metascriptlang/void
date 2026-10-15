// The window-only driver: the browser canvas under emscripten and the desktop GL window
// (-d:voidGlCore) through sokol_app. bridgeWin.c carries the same window path beside its
// host views.

#if defined(__EMSCRIPTEN__)
#include <emscripten.h>
#endif
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
#include "appWindow.h"
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
