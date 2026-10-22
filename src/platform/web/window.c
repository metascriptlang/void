#include "window.h"

#include <emscripten.h>
#include <emscripten/html5.h>
#if defined(VOID_GLES3)
#include <emscripten/html5_webgl.h>
#elif !defined(VOID_WGPU)
#error "void: the browser window needs -DVOID_WGPU or -DVOID_GLES3"
#endif
#include <math.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#define CANVAS "#canvas"
#define MOUSE_BUTTONS 3

static const struct {
	const char *name;
	VoidKeyCode code;
} keyTable[] = {
	{ "Backspace", VOID_KEY_BACKSPACE },
	{ "Tab", VOID_KEY_TAB },
	{ "Enter", VOID_KEY_ENTER },
	{ "ShiftLeft", VOID_KEY_LEFT_SHIFT },
	{ "ShiftRight", VOID_KEY_RIGHT_SHIFT },
	{ "ControlLeft", VOID_KEY_LEFT_CONTROL },
	{ "ControlRight", VOID_KEY_RIGHT_CONTROL },
	{ "AltLeft", VOID_KEY_LEFT_ALT },
	{ "AltRight", VOID_KEY_RIGHT_ALT },
	{ "Pause", VOID_KEY_PAUSE },
	{ "CapsLock", VOID_KEY_CAPS_LOCK },
	{ "Escape", VOID_KEY_ESCAPE },
	{ "Space", VOID_KEY_SPACE },
	{ "PageUp", VOID_KEY_PAGE_UP },
	{ "PageDown", VOID_KEY_PAGE_DOWN },
	{ "End", VOID_KEY_END },
	{ "Home", VOID_KEY_HOME },
	{ "ArrowLeft", VOID_KEY_LEFT },
	{ "ArrowUp", VOID_KEY_UP },
	{ "ArrowRight", VOID_KEY_RIGHT },
	{ "ArrowDown", VOID_KEY_DOWN },
	{ "PrintScreen", VOID_KEY_PRINT_SCREEN },
	{ "Insert", VOID_KEY_INSERT },
	{ "Delete", VOID_KEY_DELETE },
	{ "Digit0", VOID_KEY_0 },
	{ "Digit1", VOID_KEY_1 },
	{ "Digit2", VOID_KEY_2 },
	{ "Digit3", VOID_KEY_3 },
	{ "Digit4", VOID_KEY_4 },
	{ "Digit5", VOID_KEY_5 },
	{ "Digit6", VOID_KEY_6 },
	{ "Digit7", VOID_KEY_7 },
	{ "Digit8", VOID_KEY_8 },
	{ "Digit9", VOID_KEY_9 },
	{ "KeyA", VOID_KEY_A },
	{ "KeyB", VOID_KEY_B },
	{ "KeyC", VOID_KEY_C },
	{ "KeyD", VOID_KEY_D },
	{ "KeyE", VOID_KEY_E },
	{ "KeyF", VOID_KEY_F },
	{ "KeyG", VOID_KEY_G },
	{ "KeyH", VOID_KEY_H },
	{ "KeyI", VOID_KEY_I },
	{ "KeyJ", VOID_KEY_J },
	{ "KeyK", VOID_KEY_K },
	{ "KeyL", VOID_KEY_L },
	{ "KeyM", VOID_KEY_M },
	{ "KeyN", VOID_KEY_N },
	{ "KeyO", VOID_KEY_O },
	{ "KeyP", VOID_KEY_P },
	{ "KeyQ", VOID_KEY_Q },
	{ "KeyR", VOID_KEY_R },
	{ "KeyS", VOID_KEY_S },
	{ "KeyT", VOID_KEY_T },
	{ "KeyU", VOID_KEY_U },
	{ "KeyV", VOID_KEY_V },
	{ "KeyW", VOID_KEY_W },
	{ "KeyX", VOID_KEY_X },
	{ "KeyY", VOID_KEY_Y },
	{ "KeyZ", VOID_KEY_Z },
	{ "MetaLeft", VOID_KEY_LEFT_SUPER },
	{ "MetaRight", VOID_KEY_RIGHT_SUPER },
	{ "Numpad0", VOID_KEY_KP_0 },
	{ "Numpad1", VOID_KEY_KP_1 },
	{ "Numpad2", VOID_KEY_KP_2 },
	{ "Numpad3", VOID_KEY_KP_3 },
	{ "Numpad4", VOID_KEY_KP_4 },
	{ "Numpad5", VOID_KEY_KP_5 },
	{ "Numpad6", VOID_KEY_KP_6 },
	{ "Numpad7", VOID_KEY_KP_7 },
	{ "Numpad8", VOID_KEY_KP_8 },
	{ "Numpad9", VOID_KEY_KP_9 },
	{ "NumpadMultiply", VOID_KEY_KP_MULTIPLY },
	{ "NumpadAdd", VOID_KEY_KP_ADD },
	{ "NumpadSubtract", VOID_KEY_KP_SUBTRACT },
	{ "NumpadDecimal", VOID_KEY_KP_DECIMAL },
	{ "NumpadDivide", VOID_KEY_KP_DIVIDE },
	{ "F1", VOID_KEY_F1 },
	{ "F2", VOID_KEY_F2 },
	{ "F3", VOID_KEY_F3 },
	{ "F4", VOID_KEY_F4 },
	{ "F5", VOID_KEY_F5 },
	{ "F6", VOID_KEY_F6 },
	{ "F7", VOID_KEY_F7 },
	{ "F8", VOID_KEY_F8 },
	{ "F9", VOID_KEY_F9 },
	{ "F10", VOID_KEY_F10 },
	{ "F11", VOID_KEY_F11 },
	{ "F12", VOID_KEY_F12 },
	{ "NumLock", VOID_KEY_NUM_LOCK },
	{ "ScrollLock", VOID_KEY_SCROLL_LOCK },
	{ "Semicolon", VOID_KEY_SEMICOLON },
	{ "Equal", VOID_KEY_EQUAL },
	{ "Comma", VOID_KEY_COMMA },
	{ "Minus", VOID_KEY_MINUS },
	{ "Period", VOID_KEY_PERIOD },
	{ "Slash", VOID_KEY_SLASH },
	{ "Backquote", VOID_KEY_GRAVE_ACCENT },
	{ "BracketLeft", VOID_KEY_LEFT_BRACKET },
	{ "Backslash", VOID_KEY_BACKSLASH },
	{ "BracketRight", VOID_KEY_RIGHT_BRACKET },
	{ "Quote", VOID_KEY_GRAVE_ACCENT },
};

static struct {
	VoidWebDesc desc;
	bool valid;
	bool initCalled;
	bool cleanupCalled;
	bool quitRequested;
	bool quitOrdered;
	bool eventConsumed;
	uint64_t frameCount;
	float dpiScale;
	int windowWidth;
	int windowHeight;
	int framebufferWidth;
	int framebufferHeight;
	uint16_t mouseButtons;
	struct {
		float x, y, dx, dy;
		bool posValid;
	} mouse;
	VoidAppEvent event;
#if defined(VOID_WGPU)
	struct {
		WGPUInstance instance;
		WGPUAdapter adapter;
		WGPUDevice device;
		WGPUSurface surface;
		WGPUTextureFormat format;
		WGPUTexture msaaTexture;
		WGPUTextureView msaaView;
		WGPUTexture depthTexture;
		WGPUTextureView depthView;
		WGPUTextureView swapchainView;
		bool initDone;
	} wgpu;
#endif
} s;

__attribute__((noreturn, format(printf, 1, 2))) static void fail(const char *fmt, ...) {
	va_list args;
	va_start(args, fmt);
	fputs("void: ", stderr);
	vfprintf(stderr, fmt, args);
	fputc('\n', stderr);
	va_end(args);
	abort();
}

static int roundAtLeastOne(float f) {
	int v = (int)roundf(f);
	return v <= 0 ? 1 : v;
}

static bool eventsEnabled(void) { return s.desc.event != NULL && s.initCalled; }

static void initEvent(VoidAppEventType type) {
	memset(&s.event, 0, sizeof s.event);
	s.event.type = type;
	s.event.frameCount = s.frameCount;
	s.event.mouseButton = VOID_MOUSE_INVALID;
	s.event.windowWidth = s.windowWidth;
	s.event.windowHeight = s.windowHeight;
	s.event.framebufferWidth = s.framebufferWidth;
	s.event.framebufferHeight = s.framebufferHeight;
	s.event.mouseX = s.mouse.x;
	s.event.mouseY = s.mouse.y;
	s.event.mouseDx = s.mouse.dx;
	s.event.mouseDy = s.mouse.dy;
}

static bool callEvent(void) {
	if (!s.cleanupCalled) s.desc.event(&s.event);
	const bool consumed = s.eventConsumed;
	s.eventConsumed = false;
	return consumed;
}

static void appEvent(VoidAppEventType type) {
	if (!eventsEnabled()) return;
	initEvent(type);
	callEvent();
}

static uint32_t buttonMods(void) {
	uint32_t m = 0;
	if (s.mouseButtons & (1 << 0)) m |= VOID_MODIFIER_LMB;
	if (s.mouseButtons & (1 << 1)) m |= VOID_MODIFIER_RMB;
	if (s.mouseButtons & (1 << 2)) m |= VOID_MODIFIER_MMB;
	return m;
}

static uint32_t mods(bool ctrl, bool shift, bool alt, bool meta) {
	uint32_t m = buttonMods();
	if (ctrl) m |= VOID_MODIFIER_CTRL;
	if (shift) m |= VOID_MODIFIER_SHIFT;
	if (alt) m |= VOID_MODIFIER_ALT;
	if (meta) m |= VOID_MODIFIER_SUPER;
	return m;
}

#if defined(VOID_WGPU)

static void printMessage(const char *what, WGPUStringView message) {
	const size_t length = message.data == NULL ? 0 : message.length == WGPU_STRLEN ? strlen(message.data) : message.length;
	fprintf(stderr, "void: %s: %.*s\n", what, (int)length, message.data ? message.data : "");
}

static WGPUTextureFormat pickRenderFormat(size_t count, const WGPUTextureFormat *formats) {
	if (count == 0) fail("the WebGPU surface offers no texture format");
	for (size_t i = 0; i < count; i++) {
		if (formats[i] == WGPUTextureFormat_RGBA8Unorm || formats[i] == WGPUTextureFormat_BGRA8Unorm) return formats[i];
	}
	return formats[0];
}

static WGPUTextureView createAttachment(WGPUTexture *texture, WGPUTextureFormat format, uint32_t samples, const char *what) {
	WGPUTextureDescriptor desc = {0};
	desc.usage = WGPUTextureUsage_RenderAttachment;
	desc.dimension = WGPUTextureDimension_2D;
	desc.size.width = (uint32_t)s.framebufferWidth;
	desc.size.height = (uint32_t)s.framebufferHeight;
	desc.size.depthOrArrayLayers = 1;
	desc.format = format;
	desc.mipLevelCount = 1;
	desc.sampleCount = samples;
	*texture = wgpuDeviceCreateTexture(s.wgpu.device, &desc);
	if (*texture == NULL) fail("wgpuDeviceCreateTexture for the %s %dx%d failed", what, s.framebufferWidth, s.framebufferHeight);
	WGPUTextureView view = wgpuTextureCreateView(*texture, NULL);
	if (view == NULL) fail("wgpuTextureCreateView for the %s failed", what);
	return view;
}

static void createSwapchain(bool fromResize) {
	if (!fromResize) {
		WGPUEmscriptenSurfaceSourceCanvasHTMLSelector canvas = {0};
		canvas.chain.sType = WGPUSType_EmscriptenSurfaceSourceCanvasHTMLSelector;
		canvas.selector = (WGPUStringView){ .data = CANVAS, .length = WGPU_STRLEN };
		WGPUSurfaceDescriptor desc = {0};
		desc.nextInChain = &canvas.chain;
		s.wgpu.surface = wgpuInstanceCreateSurface(s.wgpu.instance, &desc);
		if (s.wgpu.surface == NULL) fail("wgpuInstanceCreateSurface on %s failed", CANVAS);
		WGPUSurfaceCapabilities caps = {0};
		if (wgpuSurfaceGetCapabilities(s.wgpu.surface, s.wgpu.adapter, &caps) != WGPUStatus_Success) {
			fail("wgpuSurfaceGetCapabilities on %s failed", CANVAS);
		}
		s.wgpu.format = pickRenderFormat(caps.formatCount, caps.formats);
		wgpuSurfaceCapabilitiesFreeMembers(caps);
	}
	WGPUSurfaceConfiguration conf = {0};
	conf.device = s.wgpu.device;
	conf.format = s.wgpu.format;
	conf.usage = WGPUTextureUsage_RenderAttachment;
	conf.width = (uint32_t)s.framebufferWidth;
	conf.height = (uint32_t)s.framebufferHeight;
	conf.alphaMode = WGPUCompositeAlphaMode_Premultiplied;
	conf.presentMode = WGPUPresentMode_Fifo;
	wgpuSurfaceConfigure(s.wgpu.surface, &conf);
	s.wgpu.depthView = createAttachment(&s.wgpu.depthTexture, WGPUTextureFormat_Depth32Float, (uint32_t)s.desc.sampleCount, "depth buffer");
	if (s.desc.sampleCount > 1) {
		s.wgpu.msaaView = createAttachment(&s.wgpu.msaaTexture, s.wgpu.format, (uint32_t)s.desc.sampleCount, "multisample target");
	}
}

static void discardSwapchain(bool fromResize) {
	if (s.wgpu.msaaView) wgpuTextureViewRelease(s.wgpu.msaaView);
	if (s.wgpu.msaaTexture) wgpuTextureRelease(s.wgpu.msaaTexture);
	if (s.wgpu.depthView) wgpuTextureViewRelease(s.wgpu.depthView);
	if (s.wgpu.depthTexture) wgpuTextureRelease(s.wgpu.depthTexture);
	s.wgpu.msaaView = NULL;
	s.wgpu.msaaTexture = NULL;
	s.wgpu.depthView = NULL;
	s.wgpu.depthTexture = NULL;
	if (!fromResize && s.wgpu.surface) {
		wgpuSurfaceRelease(s.wgpu.surface);
		s.wgpu.surface = NULL;
	}
}

static bool swapchainNext(void) {
	WGPUSurfaceTexture current = {0};
	wgpuSurfaceGetCurrentTexture(s.wgpu.surface, &current);
	switch (current.status) {
		case WGPUSurfaceGetCurrentTextureStatus_SuccessOptimal:
		case WGPUSurfaceGetCurrentTextureStatus_SuccessSuboptimal:
			break;
		case WGPUSurfaceGetCurrentTextureStatus_Timeout:
		case WGPUSurfaceGetCurrentTextureStatus_Outdated:
		case WGPUSurfaceGetCurrentTextureStatus_Lost:
			if (current.texture) wgpuTextureRelease(current.texture);
			discardSwapchain(false);
			createSwapchain(false);
			return false;
		default:
			fail("wgpuSurfaceGetCurrentTexture on %s failed with status %d", CANVAS, (int)current.status);
	}
	s.wgpu.swapchainView = wgpuTextureCreateView(current.texture, NULL);
	wgpuTextureRelease(current.texture);
	if (s.wgpu.swapchainView == NULL) fail("wgpuTextureCreateView on the surface texture failed");
	return true;
}

static void acquireSwapchain(void) {
	if (s.wgpu.swapchainView) return;
	if (!s.wgpu.initDone) fail("the screen view was asked for before the WebGPU device exists");
	if (!swapchainNext() && !swapchainNext()) fail("the WebGPU surface on %s gave no texture after it was made again", CANVAS);
}

static void sizeChanged(void) {
	if (s.wgpu.surface) {
		discardSwapchain(true);
		createSwapchain(true);
	}
}

static void deviceLost(const WGPUDevice *device, WGPUDeviceLostReason reason, WGPUStringView message, void *userdata1, void *userdata2) {
	(void)device;
	(void)userdata1;
	(void)userdata2;
	if (reason != WGPUDeviceLostReason_CallbackCancelled) printMessage("the WebGPU device was lost", message);
}

static void uncapturedError(const WGPUDevice *device, WGPUErrorType type, WGPUStringView message, void *userdata1, void *userdata2) {
	(void)device;
	(void)userdata1;
	(void)userdata2;
	if (type != WGPUErrorType_NoError) printMessage("WebGPU error", message);
}

static void deviceReady(WGPURequestDeviceStatus status, WGPUDevice device, WGPUStringView message, void *userdata1, void *userdata2) {
	(void)userdata1;
	(void)userdata2;
	if (status != WGPURequestDeviceStatus_Success) {
		printMessage("requestDevice", message);
		fail("the WebGPU device request failed with status %d", (int)status);
	}
	s.wgpu.device = device;
	createSwapchain(false);
	s.wgpu.initDone = true;
}

static void requestDevice(void) {
	static const WGPUFeatureName optional[] = {
		WGPUFeatureName_TextureCompressionBC,
		WGPUFeatureName_TextureCompressionETC2,
		WGPUFeatureName_TextureCompressionASTC,
		WGPUFeatureName_DualSourceBlending,
		WGPUFeatureName_ShaderF16,
		WGPUFeatureName_Float32Filterable,
		WGPUFeatureName_Float32Blendable,
		WGPUFeatureName_TextureFormatsTier2,
	};
	WGPUFeatureName features[1 + sizeof optional / sizeof optional[0]] = { WGPUFeatureName_Depth32FloatStencil8 };
	size_t featureCount = 1;
	for (size_t i = 0; i < sizeof optional / sizeof optional[0]; i++) {
		if (wgpuAdapterHasFeature(s.wgpu.adapter, optional[i])) features[featureCount++] = optional[i];
	}
	WGPULimits adapterLimits = WGPU_LIMITS_INIT;
	wgpuAdapterGetLimits(s.wgpu.adapter, &adapterLimits);
	WGPULimits limits = WGPU_LIMITS_INIT;
	limits.maxColorAttachments = adapterLimits.maxColorAttachments;
	limits.maxSampledTexturesPerShaderStage = adapterLimits.maxSampledTexturesPerShaderStage;
	limits.maxStorageBuffersPerShaderStage = adapterLimits.maxStorageBuffersPerShaderStage;
	limits.maxStorageTexturesPerShaderStage = adapterLimits.maxStorageTexturesPerShaderStage;
	WGPUDeviceDescriptor desc = {0};
	desc.requiredFeatureCount = featureCount;
	desc.requiredFeatures = features;
	desc.requiredLimits = &limits;
	desc.deviceLostCallbackInfo.mode = WGPUCallbackMode_AllowProcessEvents;
	desc.deviceLostCallbackInfo.callback = deviceLost;
	desc.uncapturedErrorCallbackInfo.callback = uncapturedError;
	WGPURequestDeviceCallbackInfo callback = {0};
	callback.mode = WGPUCallbackMode_AllowProcessEvents;
	callback.callback = deviceReady;
	wgpuAdapterRequestDevice(s.wgpu.adapter, &desc, callback);
}

static void adapterReady(WGPURequestAdapterStatus status, WGPUAdapter adapter, WGPUStringView message, void *userdata1, void *userdata2) {
	(void)userdata1;
	(void)userdata2;
	if (status != WGPURequestAdapterStatus_Success) {
		printMessage("requestAdapter", message);
		fail("the WebGPU adapter request failed with status %d", (int)status);
	}
	s.wgpu.adapter = adapter;
	requestDevice();
}

static void initGpu(void) {
	WGPUInstanceDescriptor desc = {0};
	s.wgpu.instance = wgpuCreateInstance(&desc);
	if (s.wgpu.instance == NULL) fail("wgpuCreateInstance failed");
	WGPURequestAdapterCallbackInfo callback = {0};
	callback.mode = WGPUCallbackMode_AllowProcessEvents;
	callback.callback = adapterReady;
	wgpuInstanceRequestAdapter(s.wgpu.instance, NULL, callback);
}

static void discardGpu(void) {
	discardSwapchain(false);
	if (s.wgpu.device) wgpuDeviceRelease(s.wgpu.device);
	if (s.wgpu.adapter) wgpuAdapterRelease(s.wgpu.adapter);
	if (s.wgpu.instance) wgpuInstanceRelease(s.wgpu.instance);
	s.wgpu.device = NULL;
	s.wgpu.adapter = NULL;
	s.wgpu.instance = NULL;
}

WGPUDevice voidWebDevice(void) {
	if (!s.wgpu.initDone) fail("voidWebDevice before the WebGPU device exists");
	return s.wgpu.device;
}

WGPUTextureFormat voidWebColorFormat(void) {
	if (!s.wgpu.initDone) fail("voidWebColorFormat before the WebGPU surface exists");
	return s.wgpu.format;
}

WGPUTextureView voidWebRenderView(void) {
	acquireSwapchain();
	return s.desc.sampleCount > 1 ? s.wgpu.msaaView : s.wgpu.swapchainView;
}

WGPUTextureView voidWebResolveView(void) {
	acquireSwapchain();
	return s.desc.sampleCount > 1 ? s.wgpu.swapchainView : NULL;
}

WGPUTextureView voidWebDepthStencilView(void) { return s.wgpu.depthView; }

#else

static bool webglContextChanged(int type, const void *reserved, void *userData) {
	(void)reserved;
	(void)userData;
	if (type == EMSCRIPTEN_EVENT_WEBGLCONTEXTLOST) appEvent(VOID_EVENT_SUSPENDED);
	else if (type == EMSCRIPTEN_EVENT_WEBGLCONTEXTRESTORED) appEvent(VOID_EVENT_RESUMED);
	return true;
}

static void initGpu(void) {
	EmscriptenWebGLContextAttributes attrs;
	emscripten_webgl_init_context_attributes(&attrs);
	attrs.alpha = true;
	attrs.depth = true;
	attrs.stencil = false;
	attrs.antialias = s.desc.sampleCount > 1;
	attrs.premultipliedAlpha = true;
	attrs.preserveDrawingBuffer = false;
	attrs.enableExtensionsByDefault = true;
	attrs.majorVersion = 2;
	EMSCRIPTEN_WEBGL_CONTEXT_HANDLE context = emscripten_webgl_create_context(CANVAS, &attrs);
	if (context <= 0) fail("emscripten_webgl_create_context for WebGL2 on %s failed: %d", CANVAS, (int)context);
	if (emscripten_webgl_make_context_current(context) != EMSCRIPTEN_RESULT_SUCCESS) fail("emscripten_webgl_make_context_current on %s failed", CANVAS);
}

#endif

EM_JS_DEPS(voidWebWindow, "$findCanvasEventTarget,$specialHTMLTargets");

EM_JS(int, voidJsWebInit, (const char *selector, const char *title), {
	if (title !== 0) document.title = UTF8ToString(Number(title));
	const name = UTF8ToString(Number(selector));
	if (Module['canvas'] !== undefined) {
		if (typeof Module['canvas'] !== 'object') return 0;
		specialHTMLTargets[name] = Module['canvas'];
	}
	Module.voidWebTarget = findCanvasEventTarget(name);
	return Module.voidWebTarget ? 1 : 0;
});

EM_JS(void, voidJsSetDocumentTitle, (const char *title), {
	document.title = UTF8ToString(Number(title));
});

static bool sizeChangedCallback(int type, const EmscriptenUiEvent *ui, void *userData) {
	(void)type;
	(void)userData;
	double w, h;
	emscripten_get_element_css_size(CANVAS, &w, &h);
	if (w < 1.0) w = ui->windowInnerWidth;
	else s.windowWidth = roundAtLeastOne((float)w);
	if (h < 1.0) h = ui->windowInnerHeight;
	else s.windowHeight = roundAtLeastOne((float)h);
	if (s.desc.highDpi) s.dpiScale = (float)emscripten_get_device_pixel_ratio();
	s.framebufferWidth = roundAtLeastOne((float)w * s.dpiScale);
	s.framebufferHeight = roundAtLeastOne((float)h * s.dpiScale);
	emscripten_set_canvas_element_size(CANVAS, s.framebufferWidth, s.framebufferHeight);
#if defined(VOID_WGPU)
	sizeChanged();
#endif
	appEvent(VOID_EVENT_RESIZED);
	return true;
}

static bool mouseCallback(int type, const EmscriptenMouseEvent *e, void *userData) {
	(void)userData;
	s.mouseButtons = e->buttons;
	const float x = (float)e->targetX * s.dpiScale;
	const float y = (float)e->targetY * s.dpiScale;
	if (s.mouse.posValid) {
		s.mouse.dx = x - s.mouse.x;
		s.mouse.dy = y - s.mouse.y;
	}
	s.mouse.x = x;
	s.mouse.y = y;
	s.mouse.posValid = true;
	if (!eventsEnabled() || e->button < 0 || e->button >= MOUSE_BUTTONS) return true;
	VoidAppEventType eventType;
	bool buttonEvent = false;
	switch (type) {
		case EMSCRIPTEN_EVENT_MOUSEDOWN: eventType = VOID_EVENT_MOUSE_DOWN; buttonEvent = true; break;
		case EMSCRIPTEN_EVENT_MOUSEUP: eventType = VOID_EVENT_MOUSE_UP; buttonEvent = true; break;
		case EMSCRIPTEN_EVENT_MOUSEMOVE: eventType = VOID_EVENT_MOUSE_MOVE; break;
		case EMSCRIPTEN_EVENT_MOUSEENTER: eventType = VOID_EVENT_MOUSE_ENTER; break;
		case EMSCRIPTEN_EVENT_MOUSELEAVE: eventType = VOID_EVENT_MOUSE_LEAVE; break;
		default: fail("mouse callback for emscripten event %d", type);
	}
	if (eventType == VOID_EVENT_MOUSE_ENTER || eventType == VOID_EVENT_MOUSE_LEAVE) {
		s.mouse.dx = 0.0f;
		s.mouse.dy = 0.0f;
	}
	initEvent(eventType);
	s.event.modifiers = mods(e->ctrlKey, e->shiftKey, e->altKey, e->metaKey);
	if (buttonEvent) {
		s.event.mouseButton = e->button == 0 ? VOID_MOUSE_LEFT : e->button == 1 ? VOID_MOUSE_MIDDLE : VOID_MOUSE_RIGHT;
	}
	callEvent();
	return true;
}

static bool wheelCallback(int type, const EmscriptenWheelEvent *e, void *userData) {
	(void)type;
	(void)userData;
	s.mouseButtons = e->mouse.buttons;
	if (!eventsEnabled()) return true;
	initEvent(VOID_EVENT_MOUSE_SCROLL);
	s.event.modifiers = mods(e->mouse.ctrlKey, e->mouse.shiftKey, e->mouse.altKey, e->mouse.metaKey);
	float scale;
	switch (e->deltaMode) {
		case DOM_DELTA_PIXEL: scale = -0.01f; break;
		case DOM_DELTA_LINE: scale = -1.33f; break;
		case DOM_DELTA_PAGE: scale = -10.0f; break;
		default: fail("wheel event with delta mode %lu", (unsigned long)e->deltaMode);
	}
	s.event.scrollX = scale * (float)e->deltaX;
	s.event.scrollY = scale * (float)e->deltaY;
	callEvent();
	return true;
}

static VoidKeyCode translateKey(const char *name) {
	for (size_t i = 0; i < sizeof keyTable / sizeof keyTable[0]; i++) {
		if (strcmp(name, keyTable[i].name) == 0) return keyTable[i].code;
	}
	return VOID_KEY_INVALID;
}

static bool keyCallback(int type, const EmscriptenKeyboardEvent *e, void *userData) {
	(void)userData;
	if (!eventsEnabled()) return false;
	VoidAppEventType eventType;
	switch (type) {
		case EMSCRIPTEN_EVENT_KEYDOWN: eventType = VOID_EVENT_KEY_DOWN; break;
		case EMSCRIPTEN_EVENT_KEYUP: eventType = VOID_EVENT_KEY_UP; break;
		case EMSCRIPTEN_EVENT_KEYPRESS: eventType = VOID_EVENT_CHAR; break;
		default: fail("key callback for emscripten event %d", type);
	}
	initEvent(eventType);
	s.event.keyRepeat = e->repeat;
	s.event.modifiers = mods(e->ctrlKey, e->shiftKey, e->altKey, e->metaKey);
	bool keyUpFollows = false;
	if (eventType == VOID_EVENT_CHAR) {
		s.event.charCode = e->charCode;
	} else {
		s.event.keyCode = translateKey(e->code[0] != 0 ? e->code : e->key);
		keyUpFollows = eventType == VOID_EVENT_KEY_DOWN && s.event.keyCode != VOID_KEY_LEFT_SUPER
			&& s.event.keyCode != VOID_KEY_RIGHT_SUPER && (s.event.modifiers & VOID_MODIFIER_SUPER);
	}
	bool consumed = callEvent();
	if (keyUpFollows) {
		s.event.type = VOID_EVENT_KEY_UP;
		consumed |= callEvent();
	}
	return consumed;
}

static bool touchCallback(int type, const EmscriptenTouchEvent *e, void *userData) {
	(void)userData;
	if (!eventsEnabled()) return true;
	VoidAppEventType eventType;
	switch (type) {
		case EMSCRIPTEN_EVENT_TOUCHSTART: eventType = VOID_EVENT_TOUCHES_BEGAN; break;
		case EMSCRIPTEN_EVENT_TOUCHMOVE: eventType = VOID_EVENT_TOUCHES_MOVED; break;
		case EMSCRIPTEN_EVENT_TOUCHEND: eventType = VOID_EVENT_TOUCHES_ENDED; break;
		case EMSCRIPTEN_EVENT_TOUCHCANCEL: eventType = VOID_EVENT_TOUCHES_CANCELLED; break;
		default: fail("touch callback for emscripten event %d", type);
	}
	initEvent(eventType);
	s.event.modifiers = mods(e->ctrlKey, e->shiftKey, e->altKey, e->metaKey);
	callEvent();
	return true;
}

static bool focusCallback(int type, const EmscriptenFocusEvent *e, void *userData) {
	(void)e;
	(void)userData;
	appEvent(type == EMSCRIPTEN_EVENT_FOCUS ? VOID_EVENT_FOCUSED : VOID_EVENT_UNFOCUSED);
	return true;
}

static void setEventHandlers(bool on) {
	emscripten_set_mousedown_callback(CANVAS, 0, true, on ? mouseCallback : NULL);
	emscripten_set_mouseup_callback(CANVAS, 0, true, on ? mouseCallback : NULL);
	emscripten_set_mousemove_callback(CANVAS, 0, true, on ? mouseCallback : NULL);
	emscripten_set_mouseenter_callback(CANVAS, 0, true, on ? mouseCallback : NULL);
	emscripten_set_mouseleave_callback(CANVAS, 0, true, on ? mouseCallback : NULL);
	emscripten_set_wheel_callback(CANVAS, 0, true, on ? wheelCallback : NULL);
	emscripten_set_keydown_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, 0, true, on ? keyCallback : NULL);
	emscripten_set_keyup_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, 0, true, on ? keyCallback : NULL);
	emscripten_set_keypress_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, 0, true, on ? keyCallback : NULL);
	emscripten_set_touchstart_callback(CANVAS, 0, true, on ? touchCallback : NULL);
	emscripten_set_touchmove_callback(CANVAS, 0, true, on ? touchCallback : NULL);
	emscripten_set_touchend_callback(CANVAS, 0, true, on ? touchCallback : NULL);
	emscripten_set_touchcancel_callback(CANVAS, 0, true, on ? touchCallback : NULL);
	emscripten_set_focus_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, 0, true, on ? focusCallback : NULL);
	emscripten_set_blur_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, 0, true, on ? focusCallback : NULL);
	emscripten_set_resize_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, 0, false, on ? sizeChangedCallback : NULL);
#if defined(VOID_GLES3)
	emscripten_set_webglcontextlost_callback(CANVAS, 0, true, on ? webglContextChanged : NULL);
	emscripten_set_webglcontextrestored_callback(CANVAS, 0, true, on ? webglContextChanged : NULL);
#endif
}

static void frame(void) {
	if (!s.initCalled) {
		if (s.desc.init) s.desc.init();
		s.initCalled = true;
	}
	if (!s.cleanupCalled && s.desc.frame) s.desc.frame();
	s.frameCount++;
}

static bool animationFrame(double time, void *userData) {
	(void)time;
	(void)userData;
#if defined(VOID_WGPU)
	wgpuInstanceProcessEvents(s.wgpu.instance);
	if (s.wgpu.initDone) {
		frame();
		if (s.wgpu.swapchainView) {
			wgpuTextureViewRelease(s.wgpu.swapchainView);
			s.wgpu.swapchainView = NULL;
		}
	}
#else
	frame();
#endif
	if (s.quitRequested) {
		appEvent(VOID_EVENT_QUIT_REQUESTED);
		if (s.quitRequested) s.quitOrdered = true;
	}
	if (!s.quitOrdered) return true;
	setEventHandlers(false);
	if (!s.cleanupCalled) {
		if (s.desc.cleanup) s.desc.cleanup();
		s.cleanupCalled = true;
	}
#if defined(VOID_WGPU)
	discardGpu();
#endif
	memset(&s, 0, sizeof s);
	return false;
}

void voidWebRun(const VoidWebDesc *desc) {
	if (s.valid) fail("voidWebRun: the browser window already runs");
	memset(&s, 0, sizeof s);
	s.desc = *desc;
	if (s.desc.sampleCount <= 0) s.desc.sampleCount = 1;
	if (!voidJsWebInit(CANVAS, desc->title)) fail("no canvas %s: Module.canvas is not an element and the page has no #canvas", CANVAS);
	s.dpiScale = desc->highDpi ? (float)emscripten_get_device_pixel_ratio() : 1.0f;
	double w, h;
	emscripten_get_element_css_size(CANVAS, &w, &h);
	s.windowWidth = roundAtLeastOne((float)w);
	s.windowHeight = roundAtLeastOne((float)h);
	s.framebufferWidth = roundAtLeastOne((float)w * s.dpiScale);
	s.framebufferHeight = roundAtLeastOne((float)h * s.dpiScale);
	emscripten_set_canvas_element_size(CANVAS, s.framebufferWidth, s.framebufferHeight);
	initGpu();
	s.valid = true;
	setEventHandlers(true);
	emscripten_request_animation_frame_loop(animationFrame, NULL);
}

bool voidWebValid(void) { return s.valid; }
int voidWebWidth(void) { return s.framebufferWidth > 0 ? s.framebufferWidth : 1; }
int voidWebHeight(void) { return s.framebufferHeight > 0 ? s.framebufferHeight : 1; }
int voidWebSampleCount(void) { return s.desc.sampleCount; }
float voidWebDpiScale(void) { return s.dpiScale; }
uint64_t voidWebFrameCount(void) { return s.frameCount; }
void voidWebRequestQuit(void) { s.quitRequested = true; }
void voidWebConsumeEvent(void) { s.eventConsumed = true; }
void voidWebSetTitle(const char *title) { voidJsSetDocumentTitle(title); }
