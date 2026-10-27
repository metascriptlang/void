#include "window.h"
#include "keyNames.h"

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

static struct {
	VoidWebDesc desc;
	uint16_t mouseButtons;
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
		bool lostPending;
		bool recovering;
	} wgpu;
#endif
} s;

VoidWindow voidWindow;

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
	desc.size.width = (uint32_t)voidWindow.framebufferWidth;
	desc.size.height = (uint32_t)voidWindow.framebufferHeight;
	desc.size.depthOrArrayLayers = 1;
	desc.format = format;
	desc.mipLevelCount = 1;
	desc.sampleCount = samples;
	*texture = wgpuDeviceCreateTexture(s.wgpu.device, &desc);
	if (*texture == NULL) fail("wgpuDeviceCreateTexture for the %s %dx%d failed", what, voidWindow.framebufferWidth, voidWindow.framebufferHeight);
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
	conf.usage = WGPUTextureUsage_RenderAttachment | WGPUTextureUsage_CopySrc;
	conf.width = (uint32_t)voidWindow.framebufferWidth;
	conf.height = (uint32_t)voidWindow.framebufferHeight;
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

enum { LOST_IGNORE, LOST_RECOVER, LOST_FATAL };
int32_t voidWebDeviceLostAction(int32_t reason);

static void deviceLost(const WGPUDevice *device, WGPUDeviceLostReason reason, WGPUStringView message, void *userdata1, void *userdata2) {
	(void)userdata1;
	(void)userdata2;
	switch (voidWebDeviceLostAction((int32_t)reason)) {
		case LOST_IGNORE:
			return;
		case LOST_RECOVER:
			if (*device != s.wgpu.device) return;
			printMessage("the WebGPU device was lost", message);
			s.wgpu.initDone = false;
			s.wgpu.lostPending = true;
			voidWindowAppEvent(VOID_EVENT_SUSPENDED);
			return;
		default:
			printMessage("the WebGPU device was lost", message);
			fail("the WebGPU device was lost with reason %d, which Void does not recover from", (int)reason);
	}
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
	if (s.wgpu.recovering) {
		s.wgpu.recovering = false;
		voidWindowAppEvent(VOID_EVENT_RESUMED);
	}
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
		WGPUFeatureName_TimestampQuery,
		WGPUFeatureName_RG11B10UfloatRenderable,
		WGPUFeatureName_BGRA8UnormStorage,
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
	if (type == EMSCRIPTEN_EVENT_WEBGLCONTEXTLOST) voidWindowAppEvent(VOID_EVENT_SUSPENDED);
	else if (type == EMSCRIPTEN_EVENT_WEBGLCONTEXTRESTORED) voidWindowAppEvent(VOID_EVENT_RESUMED);
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

EM_JS_DEPS(voidWebWindow, "$findCanvasEventTarget,$specialHTMLTargets,$withStackSave,$stringToUTF8OnStack");

EMSCRIPTEN_KEEPALIVE void voidWebOnPaste(const char *utf8) {
	free(voidWindow.clipboard);
	voidWindow.clipboard = strdup(utf8);
	if (voidWindow.clipboard == NULL) fail("strdup for the pasted text");
	voidWindowAppEvent(VOID_EVENT_CLIPBOARD_PASTED);
}

EMSCRIPTEN_KEEPALIVE void voidWebBeginDrop(int count) {
	if (count < 0) count = 0;
	voidWindowBeginDrop((size_t)count);
	voidWindow.droppedCount = count;
}

EMSCRIPTEN_KEEPALIVE void voidWebDrop(int i, const char *name) {
	if (i < 0 || i >= voidWindow.droppedCount) fail("a dropped file %d arrived of %d announced", i, voidWindow.droppedCount);
	voidWindow.droppedPaths[i] = strdup(name);
	if (voidWindow.droppedPaths[i] == NULL) fail("strdup for a dropped file name");
}

EMSCRIPTEN_KEEPALIVE void voidWebEndDrop(int x, int y, int dropMods) {
	if (voidWindow.droppedCount == 0 || !voidWindowEventsEnabled()) return;
	voidWindow.mouse.x = (float)x * voidWindow.dpiScale;
	voidWindow.mouse.y = (float)y * voidWindow.dpiScale;
	voidWindow.mouse.dx = 0.0f;
	voidWindow.mouse.dy = 0.0f;
	voidWindowInitEvent(VOID_EVENT_FILES_DROPPED);
	if (dropMods & 1) voidWindow.event.modifiers |= VOID_MODIFIER_SHIFT;
	if (dropMods & 2) voidWindow.event.modifiers |= VOID_MODIFIER_CTRL;
	if (dropMods & 4) voidWindow.event.modifiers |= VOID_MODIFIER_ALT;
	if (dropMods & 8) voidWindow.event.modifiers |= VOID_MODIFIER_SUPER;
	voidWindowCallEvent();
}

EMSCRIPTEN_KEEPALIVE void voidWebSetFullscreenFlag(int fullscreen) { voidWindow.fullscreen = fullscreen != 0; }

EM_JS(void, voidJsAddClipboardListener, (void), {
	Module.voidPaste = (event) => {
		const text = event.clipboardData.getData('text');
		withStackSave(() => _voidWebOnPaste(stringToUTF8OnStack(text)));
	};
	window.addEventListener('paste', Module.voidPaste);
});

EM_JS(void, voidJsRemoveClipboardListener, (void), {
	window.removeEventListener('paste', Module.voidPaste);
});

EM_JS(void, voidJsWriteClipboard, (const char *utf8), {
	const ta = document.createElement('textarea');
	for (const [name, value] of [['autocomplete', 'off'], ['autocorrect', 'off'], ['autocapitalize', 'off'], ['spellcheck', 'false']]) {
		ta.setAttribute(name, value);
	}
	ta.style.left = '-100px';
	ta.style.top = '-100px';
	ta.style.height = '1px';
	ta.style.width = '1px';
	ta.value = UTF8ToString(Number(utf8));
	document.body.appendChild(ta);
	ta.select();
	document.execCommand('copy');
	document.body.removeChild(ta);
});

EM_JS(void, voidJsSetCursor, (int cursor, int shown), {
	const names = ['auto', 'default', 'text', 'crosshair', 'pointer', 'ew-resize', 'ns-resize', 'nwse-resize', 'nesw-resize', 'all-scroll', 'not-allowed'];
	Module.voidWebTarget.style.cursor = shown === 0 ? 'none' : names[cursor];
});

EM_JS(void, voidJsRequestPointerLock, (void), {
	const canvas = Module.voidWebTarget;
	if (canvas.requestPointerLock) canvas.requestPointerLock();
});

EM_JS(void, voidJsExitPointerLock, (void), {
	if (document.exitPointerLock) document.exitPointerLock();
});

EM_JS(void, voidJsToggleFullscreen, (void), {
	const canvas = Module.voidWebTarget;
	const current = document.fullscreenElement || document.webkitFullscreenElement || document.mozFullScreenElement;
	let p;
	if (!current) {
		if (canvas.requestFullscreen) p = canvas.requestFullscreen();
		else if (canvas.webkitRequestFullscreen) p = canvas.webkitRequestFullscreen();
		else if (canvas.mozRequestFullScreen) p = canvas.mozRequestFullScreen();
		if (p) {
			p.catch((err) => {
				console.warn('void: failed to enter fullscreen', err);
				_voidWebSetFullscreenFlag(0);
			});
		} else {
			console.warn('void: this browser has no requestFullscreen');
			_voidWebSetFullscreenFlag(0);
		}
	} else {
		if (document.exitFullscreen) p = document.exitFullscreen();
		else if (document.webkitExitFullscreen) p = document.webkitExitFullscreen();
		else if (document.mozCancelFullScreen) p = document.mozCancelFullScreen();
		if (p) {
			p.catch((err) => {
				console.warn('void: failed to leave fullscreen', err);
				_voidWebSetFullscreenFlag(1);
			});
		} else {
			console.warn('void: this browser has no exitFullscreen');
		}
	}
});

EM_JS(void, voidJsAddDropListeners, (void), {
	const stop = (event) => {
		event.stopPropagation();
		event.preventDefault();
	};
	Module.voidDragenter = stop;
	Module.voidDragleave = stop;
	Module.voidDragover = stop;
	Module.voidDrop = (event) => {
		stop(event);
		const files = event.dataTransfer.files;
		_voidWebBeginDrop(files.length);
		for (let i = 0; i < files.length; i++) {
			withStackSave(() => _voidWebDrop(i, stringToUTF8OnStack(files[i].name)));
		}
		let dropMods = 0;
		if (event.shiftKey) dropMods |= 1;
		if (event.ctrlKey) dropMods |= 2;
		if (event.altKey) dropMods |= 4;
		if (event.metaKey) dropMods |= 8;
		_voidWebEndDrop(event.clientX, event.clientY, dropMods);
	};
	const canvas = Module.voidWebTarget;
	canvas.addEventListener('dragenter', Module.voidDragenter, false);
	canvas.addEventListener('dragleave', Module.voidDragleave, false);
	canvas.addEventListener('dragover', Module.voidDragover, false);
	canvas.addEventListener('drop', Module.voidDrop, false);
});

EM_JS(void, voidJsRemoveDropListeners, (void), {
	const canvas = Module.voidWebTarget;
	canvas.removeEventListener('dragenter', Module.voidDragenter);
	canvas.removeEventListener('dragleave', Module.voidDragleave);
	canvas.removeEventListener('dragover', Module.voidDragover);
	canvas.removeEventListener('drop', Module.voidDrop);
});

static void updateMouseLockState(void) {
	if (!voidWindow.mouse.requestedLock) return;
	voidWindow.mouse.requestedLock = false;
	voidJsRequestPointerLock();
}

static bool pointerLockChange(int type, const EmscriptenPointerlockChangeEvent *e, void *userData) {
	(void)type;
	(void)userData;
	voidWindow.mouse.locked = e->isActive;
	return true;
}

static bool pointerLockError(int type, const void *reserved, void *userData) {
	(void)type;
	(void)reserved;
	(void)userData;
	voidWindow.mouse.locked = false;
	voidWindow.mouse.requestedLock = false;
	return true;
}

static bool fullscreenChange(int type, const EmscriptenFullscreenChangeEvent *e, void *userData) {
	(void)type;
	(void)userData;
	voidWindow.fullscreen = e->isFullscreen;
	return true;
}

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
	else voidWindow.windowWidth = roundAtLeastOne((float)w);
	if (h < 1.0) h = ui->windowInnerHeight;
	else voidWindow.windowHeight = roundAtLeastOne((float)h);
	if (s.desc.highDpi) voidWindow.dpiScale = (float)emscripten_get_device_pixel_ratio();
	voidWindow.framebufferWidth = roundAtLeastOne((float)w * voidWindow.dpiScale);
	voidWindow.framebufferHeight = roundAtLeastOne((float)h * voidWindow.dpiScale);
	emscripten_set_canvas_element_size(CANVAS, voidWindow.framebufferWidth, voidWindow.framebufferHeight);
#if defined(VOID_WGPU)
	sizeChanged();
#endif
	voidWindowAppEvent(VOID_EVENT_RESIZED);
	return true;
}

static bool mouseCallback(int type, const EmscriptenMouseEvent *e, void *userData) {
	(void)userData;
	s.mouseButtons = e->buttons;
	if (voidWindow.mouse.locked) {
		voidWindow.mouse.dx = (float)e->movementX;
		voidWindow.mouse.dy = (float)e->movementY;
	} else {
		const float x = (float)e->targetX * voidWindow.dpiScale;
		const float y = (float)e->targetY * voidWindow.dpiScale;
		if (voidWindow.mouse.posValid) {
			voidWindow.mouse.dx = x - voidWindow.mouse.x;
			voidWindow.mouse.dy = y - voidWindow.mouse.y;
		}
		voidWindow.mouse.x = x;
		voidWindow.mouse.y = y;
		voidWindow.mouse.posValid = true;
	}
	if (!voidWindowEventsEnabled() || e->button < 0 || e->button >= MOUSE_BUTTONS) return true;
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
		voidWindow.mouse.dx = 0.0f;
		voidWindow.mouse.dy = 0.0f;
	}
	voidWindowInitEvent(eventType);
	voidWindow.event.modifiers = mods(e->ctrlKey, e->shiftKey, e->altKey, e->metaKey);
	if (buttonEvent) {
		voidWindow.event.mouseButton = e->button == 0 ? VOID_MOUSE_LEFT : e->button == 1 ? VOID_MOUSE_MIDDLE : VOID_MOUSE_RIGHT;
	}
	voidWindowCallEvent();
	if (buttonEvent) updateMouseLockState();
	return true;
}

static bool wheelCallback(int type, const EmscriptenWheelEvent *e, void *userData) {
	(void)type;
	(void)userData;
	s.mouseButtons = e->mouse.buttons;
	if (!voidWindowEventsEnabled()) {
		updateMouseLockState();
		return true;
	}
	voidWindowInitEvent(VOID_EVENT_MOUSE_SCROLL);
	voidWindow.event.modifiers = mods(e->mouse.ctrlKey, e->mouse.shiftKey, e->mouse.altKey, e->mouse.metaKey);
	float scale;
	switch (e->deltaMode) {
		case DOM_DELTA_PIXEL: scale = -0.01f; break;
		case DOM_DELTA_LINE: scale = -1.33f; break;
		case DOM_DELTA_PAGE: scale = -10.0f; break;
		default: fail("wheel event with delta mode %lu", (unsigned long)e->deltaMode);
	}
	voidWindow.event.scrollX = scale * (float)e->deltaX;
	voidWindow.event.scrollY = scale * (float)e->deltaY;
	voidWindowCallEvent();
	updateMouseLockState();
	return true;
}

	return VOID_KEY_INVALID;
}

static bool keyCallback(int type, const EmscriptenKeyboardEvent *e, void *userData) {
	(void)userData;
	if (!voidWindowEventsEnabled()) return false;
	VoidAppEventType eventType;
	switch (type) {
		case EMSCRIPTEN_EVENT_KEYDOWN: eventType = VOID_EVENT_KEY_DOWN; break;
		case EMSCRIPTEN_EVENT_KEYUP: eventType = VOID_EVENT_KEY_UP; break;
		case EMSCRIPTEN_EVENT_KEYPRESS: eventType = VOID_EVENT_CHAR; break;
		default: fail("key callback for emscripten event %d", type);
	}
	voidWindowInitEvent(eventType);
	voidWindow.event.keyRepeat = e->repeat;
	voidWindow.event.modifiers = mods(e->ctrlKey, e->shiftKey, e->altKey, e->metaKey);
	bool keyUpFollows = false;
	if (eventType == VOID_EVENT_CHAR) {
		voidWindow.event.charCode = e->charCode;
	} else {
		voidWindow.event.keyCode = voidWebTranslateKey(e->code[0] != 0 ? e->code : e->key);
		keyUpFollows = eventType == VOID_EVENT_KEY_DOWN && voidWindow.event.keyCode != VOID_KEY_LEFT_SUPER
			&& voidWindow.event.keyCode != VOID_KEY_RIGHT_SUPER && (voidWindow.event.modifiers & VOID_MODIFIER_SUPER);
	}
	voidKeysHeldTrack(&voidWindow.keysHeld, eventType, voidWindow.event.keyCode);
	bool consumed = voidWindowCallEvent();
	if (keyUpFollows) {
		voidWindow.event.type = VOID_EVENT_KEY_UP;
		voidKeysHeldTrack(&voidWindow.keysHeld, VOID_EVENT_KEY_UP, voidWindow.event.keyCode);
		consumed |= voidWindowCallEvent();
	}
	return consumed;
}

static bool touchCallback(int type, const EmscriptenTouchEvent *e, void *userData) {
	(void)userData;
	if (!voidWindowEventsEnabled()) return true;
	VoidAppEventType eventType;
	switch (type) {
		case EMSCRIPTEN_EVENT_TOUCHSTART: eventType = VOID_EVENT_TOUCHES_BEGAN; break;
		case EMSCRIPTEN_EVENT_TOUCHMOVE: eventType = VOID_EVENT_TOUCHES_MOVED; break;
		case EMSCRIPTEN_EVENT_TOUCHEND: eventType = VOID_EVENT_TOUCHES_ENDED; break;
		case EMSCRIPTEN_EVENT_TOUCHCANCEL: eventType = VOID_EVENT_TOUCHES_CANCELLED; break;
		default: fail("touch callback for emscripten event %d", type);
	}
	voidWindowInitEvent(eventType);
	voidWindow.event.modifiers = mods(e->ctrlKey, e->shiftKey, e->altKey, e->metaKey);
	voidWindow.event.touchCount = e->numTouches < VOID_MAX_TOUCHPOINTS ? e->numTouches : VOID_MAX_TOUCHPOINTS;
	for (int i = 0; i < voidWindow.event.touchCount; i++) {
		const EmscriptenTouchPoint *src = &e->touches[i];
		voidWindow.event.touches[i].identifier = (uintptr_t)src->identifier;
		voidWindow.event.touches[i].x = (float)src->targetX * voidWindow.dpiScale;
		voidWindow.event.touches[i].y = (float)src->targetY * voidWindow.dpiScale;
		voidWindow.event.touches[i].changed = src->isChanged;
	}
	voidWindowCallEvent();
	return true;
}

static void releaseKey(VoidKeyCode key) {
	if (!voidWindowEventsEnabled()) return;
	voidWindowInitEvent(VOID_EVENT_KEY_UP);
	voidWindow.event.keyCode = key;
	voidWindowCallEvent();
}

static bool focusCallback(int type, const EmscriptenFocusEvent *e, void *userData) {
	(void)e;
	(void)userData;
	if (type != EMSCRIPTEN_EVENT_FOCUS) voidKeysHeldRelease(&voidWindow.keysHeld, releaseKey);
	voidWindowAppEvent(type == EMSCRIPTEN_EVENT_FOCUS ? VOID_EVENT_FOCUSED : VOID_EVENT_UNFOCUSED);
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
	emscripten_set_pointerlockchange_callback(EMSCRIPTEN_EVENT_TARGET_DOCUMENT, 0, true, on ? pointerLockChange : NULL);
	emscripten_set_pointerlockerror_callback(EMSCRIPTEN_EVENT_TARGET_DOCUMENT, 0, true, on ? pointerLockError : NULL);
	emscripten_set_fullscreenchange_callback(CANVAS, 0, true, on ? fullscreenChange : NULL);
	if (on) {
		voidJsAddClipboardListener();
		voidJsAddDropListeners();
	} else {
		voidJsRemoveClipboardListener();
		voidJsRemoveDropListeners();
	}
	emscripten_set_focus_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, 0, true, on ? focusCallback : NULL);
	emscripten_set_blur_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, 0, true, on ? focusCallback : NULL);
	emscripten_set_resize_callback(EMSCRIPTEN_EVENT_TARGET_WINDOW, 0, false, on ? sizeChangedCallback : NULL);
#if defined(VOID_GLES3)
	emscripten_set_webglcontextlost_callback(CANVAS, 0, true, on ? webglContextChanged : NULL);
	emscripten_set_webglcontextrestored_callback(CANVAS, 0, true, on ? webglContextChanged : NULL);
#endif
}

static bool animationFrame(double time, void *userData) {
	(void)userData;
	voidFrameTimingUpdate(&voidWindow.timing, time / 1000.0);
#if defined(VOID_WGPU)
	wgpuInstanceProcessEvents(s.wgpu.instance);
	if (s.wgpu.lostPending) {
		s.wgpu.lostPending = false;
		s.wgpu.recovering = true;
		discardGpu();
		initGpu();
	}
	if (s.wgpu.initDone) {
		voidWindowFrame();
		if (s.wgpu.swapchainView) {
			wgpuTextureViewRelease(s.wgpu.swapchainView);
			s.wgpu.swapchainView = NULL;
		}
	}
#else
	voidWindowFrame();
#endif
	if (voidWindow.quitRequested) voidWindowAskQuit();
	if (!voidWindow.quitOrdered) return true;
	setEventHandlers(false);
	voidWindowCleanup();
#if defined(VOID_WGPU)
	discardGpu();
#endif
	voidWindowEnd();
	memset(&s, 0, sizeof s);
	return false;
}

void voidWebRun(const VoidWebDesc *desc) {
	if (voidWindow.valid) fail("voidWebRun: the browser window already runs");
	memset(&s, 0, sizeof s);
	s.desc = *desc;
	voidWindowStart(desc->init, desc->frame, desc->event, desc->cleanup, 0, 0);
	if (s.desc.sampleCount <= 0) s.desc.sampleCount = 1;
	if (!voidJsWebInit(CANVAS, desc->title)) fail("no canvas %s: Module.canvas is not an element and the page has no #canvas", CANVAS);
	voidWindow.dpiScale = desc->highDpi ? (float)emscripten_get_device_pixel_ratio() : 1.0f;
	double w, h;
	emscripten_get_element_css_size(CANVAS, &w, &h);
	voidWindow.windowWidth = roundAtLeastOne((float)w);
	voidWindow.windowHeight = roundAtLeastOne((float)h);
	voidWindow.framebufferWidth = roundAtLeastOne((float)w * voidWindow.dpiScale);
	voidWindow.framebufferHeight = roundAtLeastOne((float)h * voidWindow.dpiScale);
	emscripten_set_canvas_element_size(CANVAS, voidWindow.framebufferWidth, voidWindow.framebufferHeight);
	initGpu();
	voidWindow.valid = true;
	setEventHandlers(true);
	emscripten_request_animation_frame_loop(animationFrame, NULL);
}

int voidWebSampleCount(void) { return s.desc.sampleCount; }
void voidWebConsumeEvent(void) { voidWindow.eventConsumed = true; }
void voidWindowSetTitle(const char *title) { voidJsSetDocumentTitle(title); }
void voidWindowSetClipboard(const char *utf8) { voidJsWriteClipboard(utf8); }
const char *voidWindowClipboard(void) { return voidWindow.clipboard ? voidWindow.clipboard : ""; }

void voidWindowSetCursor(int cursor) {
	voidWindow.mouse.cursor = cursor;
	voidJsSetCursor(cursor, voidWindow.mouse.shown ? 1 : 0);
}

void voidWindowShowMouse(bool shown) {
	voidWindow.mouse.shown = shown;
	voidJsSetCursor(voidWindow.mouse.cursor, shown ? 1 : 0);
}

void voidWindowLockMouse(bool locked) {
	voidWindow.mouse.requestedLock = locked;
	if (!locked) voidJsExitPointerLock();
}

void voidWindowToggleFullscreen(void) {
	voidWindow.fullscreen = !voidWindow.fullscreen;
	voidJsToggleFullscreen();
}
