#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <stdint.h>
#include <stdlib.h>

#include "bridge.h"
#include "views.h"
#include "sokol_app.h"
#include "sokol_glue.h"
#include "sokol_log.h"
#ifdef VOID_PROFILER
#include "../void2d/frameClock.h"
#endif

typedef enum { DRIVER_NONE, DRIVER_WINDOW, DRIVER_VIEWS } VoidDriver;
static VoidDriver s_driver = DRIVER_NONE;

static void call0(msClosure c) {
	if (!c.fn) return;
	if (c.env) ((void (*)(void *))c.fn)(c.env);
	else ((void (*)(void))c.fn)();
}

static msClosure s_init;
static msClosure s_frame;
static bool s_keys[SAPP_MAX_KEYCODES];
static int s_reqW = 0;
static int s_reqH = 0;

static int s_generation = 1;
static int s_contextLost = 0;

static void setupWindowGfx(void);
static void setupViewsGfx(void);

int voidGpuGeneration(void) { return s_generation; }
void voidLoseContext(void) { s_contextLost = 1; }

static void restoreContext(void) {
	sg_shutdown();
	if (s_driver == DRIVER_WINDOW) setupWindowGfx();
	else setupViewsGfx();
	s_generation++;
	s_contextLost = 0;
}

static void _init(void) { call0(s_init); }
static void _frame(void) {
	if (s_contextLost) restoreContext();
	call0(s_frame);
}

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
	if (s_driver != DRIVER_NONE) voidFail("voidRun: this process already drives Void through host views");
	s_driver = DRIVER_WINDOW;
	s_reqW = w;
	s_reqH = h;
	s_init = init;
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

static ID3D11Device *s_device;
static ID3D11DeviceContext *s_context;
static IDXGIFactory2 *s_factory;

typedef struct {
	IDXGISwapChain1 *swapChain;
	ID3D11RenderTargetView *target;
	ID3D11Texture2D *msaa;
	ID3D11RenderTargetView *msaaTarget;
	int w, h;
} WinSurface;

void voidPlatformDeviceEnsure(void) {
	if (s_driver == DRIVER_WINDOW) voidFail("voidViewCreate: this process already runs a sokol_app window");
	if (s_driver == DRIVER_VIEWS) return;
	const D3D_FEATURE_LEVEL wanted[] = { D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0 };
	D3D_FEATURE_LEVEL level;
	HRESULT hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, D3D11_CREATE_DEVICE_BGRA_SUPPORT,
		wanted, 2, D3D11_SDK_VERSION, &s_device, &level, &s_context);
	if (FAILED(hr)) voidFail("D3D11CreateDevice failed: 0x%08lx", (unsigned long)hr);
	IDXGIDevice *dxgiDevice = NULL;
	IDXGIAdapter *adapter = NULL;
	hr = ID3D11Device_QueryInterface(s_device, &IID_IDXGIDevice, (void **)&dxgiDevice);
	if (SUCCEEDED(hr)) hr = IDXGIDevice_GetAdapter(dxgiDevice, &adapter);
	if (SUCCEEDED(hr)) hr = IDXGIAdapter_GetParent(adapter, &IID_IDXGIFactory2, (void **)&s_factory);
	if (adapter) IDXGIAdapter_Release(adapter);
	if (dxgiDevice) IDXGIDevice_Release(dxgiDevice);
	if (FAILED(hr)) voidFail("the D3D11 device has no IDXGIFactory2: 0x%08lx", (unsigned long)hr);
	setupViewsGfx();
	s_driver = DRIVER_VIEWS;
}

static void setupViewsGfx(void) {
	sg_desc d = {0};
	d.environment.d3d11.device = s_device;
	d.environment.d3d11.device_context = s_context;
	d.environment.defaults.color_format = SG_PIXELFORMAT_BGRA8;
	d.environment.defaults.depth_format = SG_PIXELFORMAT_NONE;
	d.environment.defaults.sample_count = voidViewsSampleCount();
	d.logger.func = slog_func;
	sg_setup(&d);
	if (!sg_isvalid()) voidFail("sg_setup on the D3D11 device failed");
}

void voidPlatformRunInit(msClosure init) { call0(init); }

static void makeTarget(WinSurface *s) {
	ID3D11Texture2D *back = NULL;
	HRESULT hr = IDXGISwapChain1_GetBuffer(s->swapChain, 0, &IID_ID3D11Texture2D, (void **)&back);
	if (FAILED(hr)) voidFail("IDXGISwapChain1::GetBuffer failed: 0x%08lx", (unsigned long)hr);
	hr = ID3D11Device_CreateRenderTargetView(s_device, (ID3D11Resource *)back, NULL, &s->target);
	ID3D11Texture2D_Release(back);
	if (FAILED(hr)) voidFail("CreateRenderTargetView on the back buffer failed: 0x%08lx", (unsigned long)hr);
	const int samples = voidViewsSampleCount();
	if (samples == 1) return;
	UINT quality = 0;
	hr = ID3D11Device_CheckMultisampleQualityLevels(s_device, DXGI_FORMAT_B8G8R8A8_UNORM, (UINT)samples, &quality);
	if (FAILED(hr) || quality == 0) voidFail("the D3D11 device cannot render BGRA8 at %d samples", samples);
	D3D11_TEXTURE2D_DESC desc;
	ZeroMemory(&desc, sizeof desc);
	desc.Width = (UINT)s->w;
	desc.Height = (UINT)s->h;
	desc.MipLevels = 1;
	desc.ArraySize = 1;
	desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
	desc.SampleDesc.Count = (UINT)samples;
	desc.SampleDesc.Quality = (UINT)D3D11_STANDARD_MULTISAMPLE_PATTERN;
	desc.Usage = D3D11_USAGE_DEFAULT;
	desc.BindFlags = D3D11_BIND_RENDER_TARGET;
	hr = ID3D11Device_CreateTexture2D(s_device, &desc, NULL, &s->msaa);
	if (FAILED(hr)) voidFail("CreateTexture2D %dx%d at %d samples failed: 0x%08lx", s->w, s->h, samples, (unsigned long)hr);
	hr = ID3D11Device_CreateRenderTargetView(s_device, (ID3D11Resource *)s->msaa, NULL, &s->msaaTarget);
	if (FAILED(hr)) voidFail("CreateRenderTargetView on the %d-sample target failed: 0x%08lx", samples, (unsigned long)hr);
}

static void releaseTargets(WinSurface *s) {
	ID3D11DeviceContext_OMSetRenderTargets(s_context, 0, NULL, NULL);
	ID3D11RenderTargetView_Release(s->target);
	s->target = NULL;
	if (s->msaaTarget) ID3D11RenderTargetView_Release(s->msaaTarget);
	if (s->msaa) ID3D11Texture2D_Release(s->msaa);
	s->msaaTarget = NULL;
	s->msaa = NULL;
}

void *voidPlatformSurfaceCreate(const void *native, int w, int h) {
	(void)native;
	DXGI_SWAP_CHAIN_DESC1 desc;
	ZeroMemory(&desc, sizeof desc);
	desc.Width = (UINT)w;
	desc.Height = (UINT)h;
	desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
	desc.SampleDesc.Count = 1;
	desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
	desc.BufferCount = 2;
	desc.Scaling = DXGI_SCALING_STRETCH;
	desc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
	desc.AlphaMode = DXGI_ALPHA_MODE_PREMULTIPLIED;
	WinSurface *s = (WinSurface *)calloc(1, sizeof(WinSurface));
	s->w = w;
	s->h = h;
	HRESULT hr = IDXGIFactory2_CreateSwapChainForComposition(s_factory, (IUnknown *)s_device, &desc, NULL, &s->swapChain);
	if (FAILED(hr)) voidFail("CreateSwapChainForComposition %dx%d failed: 0x%08lx", w, h, (unsigned long)hr);
	makeTarget(s);
	return s;
}

void voidPlatformSurfaceResize(void *surface, int w, int h) {
	WinSurface *s = (WinSurface *)surface;
	releaseTargets(s);
	s->w = w;
	s->h = h;
	HRESULT hr = IDXGISwapChain1_ResizeBuffers(s->swapChain, 0, (UINT)w, (UINT)h, DXGI_FORMAT_UNKNOWN, 0);
	if (FAILED(hr)) voidFail("ResizeBuffers to %dx%d failed: 0x%08lx", w, h, (unsigned long)hr);
	makeTarget(s);
}

int voidPlatformSurfaceAcquire(void *surface) {
	(void)surface;
	if (s_contextLost) restoreContext();
	return 1;
}

void voidPlatformSurfaceSwapchain(void *surface, sg_swapchain *swapchain) {
	WinSurface *s = (WinSurface *)surface;
	swapchain->color_format = SG_PIXELFORMAT_BGRA8;
	if (s->msaaTarget) {
		swapchain->d3d11.render_view = s->msaaTarget;
		swapchain->d3d11.resolve_view = s->target;
	} else {
		swapchain->d3d11.render_view = s->target;
	}
}

void voidPlatformSurfacePresent(void *surface) {
	HRESULT hr = IDXGISwapChain1_Present(((WinSurface *)surface)->swapChain, 1, 0);
	if (FAILED(hr)) voidFail("IDXGISwapChain1::Present failed: 0x%08lx", (unsigned long)hr);
}

void voidPlatformSurfaceDestroy(void *surface) {
	WinSurface *s = (WinSurface *)surface;
	releaseTargets(s);
	IDXGISwapChain1_Release(s->swapChain);
	free(s);
}

long long voidPlatformSurfaceNative(void *surface) {
	return (long long)(intptr_t)((WinSurface *)surface)->swapChain;
}

static void setupWindowGfx(void) {
	sg_desc d = {0};
	d.environment = sglue_environment();
	d.logger.func = slog_func;
	sg_setup(&d);
}

__attribute__((noreturn)) static void noDriver(const char *op) {
	voidFail("%s before voidRun or voidViewCreate chose a driver", op);
}

void voidGfxSetup(void) {
	switch (s_driver) {
		case DRIVER_WINDOW: setupWindowGfx(); break;
		case DRIVER_VIEWS: break;
		case DRIVER_NONE: noDriver("gfxSetup");
	}
}

int voidFbWidth(void) {
	if (s_driver == DRIVER_WINDOW) return sapp_width();
	if (s_driver == DRIVER_NONE) noDriver("fbWidth");
	return voidViewsFbWidth();
}

int voidFbHeight(void) {
	if (s_driver == DRIVER_WINDOW) return sapp_height();
	if (s_driver == DRIVER_NONE) noDriver("fbHeight");
	return voidViewsFbHeight();
}

float voidDpiScale(void) {
	if (s_driver == DRIVER_WINDOW) return sapp_dpi_scale();
	if (s_driver == DRIVER_NONE) noDriver("dpiScale");
	return voidViewsDpiScale();
}

int voidKeyDown(int keycode) {
	if (s_driver != DRIVER_WINDOW || keycode < 0 || keycode >= SAPP_MAX_KEYCODES) return 0;
	return s_keys[keycode] ? 1 : 0;
}

sg_swapchain voidDriverSwapchain(void) {
	if (s_driver == DRIVER_WINDOW) return sglue_swapchain();
	if (s_driver == DRIVER_NONE) noDriver("beginPass");
	return voidViewsSwapchain();
}

void voidDriverPresent(void) {
	if (s_driver == DRIVER_VIEWS) voidViewsPresent();
}
