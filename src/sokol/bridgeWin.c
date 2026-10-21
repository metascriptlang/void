#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <commctrl.h>
#include <imm.h>
#include <d3d11.h>
#include <dxgi1_2.h>
#include <dwmapi.h>
#include <stdint.h>
#include <stdlib.h>

#include "backend.h"
#include "bridge.h"
#include "views.h"
#include "windowSurface.h"

#include "sokol_log.h"
#include "appWindow.h"
#include "../platform/win32/window.h"
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
static bool s_keys[VOID_KEY_COUNT];
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

static int s_textInput = -1;
static RECT s_imeRect;
static bool s_preeditActive;

static HWND windowHwnd(void) {
	return s_driver == DRIVER_WINDOW && voidWin32Valid() ? voidWin32Hwnd() : NULL;
}

static bool imeTaken(void) { return s_textInput == 1 && voidAppEventHandlerSet(); }

static void imePlace(HWND hwnd) {
	HIMC himc = ImmGetContext(hwnd);
	if (himc == NULL) return;
	COMPOSITIONFORM cf;
	ZeroMemory(&cf, sizeof cf);
	cf.dwStyle = CFS_POINT;
	cf.ptCurrentPos.x = s_imeRect.left;
	cf.ptCurrentPos.y = s_imeRect.top;
	ImmSetCompositionWindow(himc, &cf);
	CANDIDATEFORM cand;
	ZeroMemory(&cand, sizeof cand);
	cand.dwIndex = 0;
	cand.dwStyle = CFS_EXCLUDE;
	cand.ptCurrentPos.x = s_imeRect.left;
	cand.ptCurrentPos.y = s_imeRect.bottom;
	cand.rcArea = s_imeRect;
	ImmSetCandidateWindow(himc, &cand);
	ImmReleaseContext(hwnd, himc);
}

static int imeString(HIMC himc, DWORD kind, char *utf8, int cap) {
	static WCHAR wide[512];
	LONG bytes = ImmGetCompositionStringW(himc, kind, NULL, 0);
	int n = bytes > 0 ? (int)(bytes / (LONG)sizeof(WCHAR)) : 0;
	if (n > 512) voidFail("IME %s is %d UTF-16 units; at most 512 fit", kind == GCS_RESULTSTR ? "result" : "composition", n);
	if (n > 0) ImmGetCompositionStringW(himc, kind, wide, (DWORD)(n * (int)sizeof(WCHAR)));
	int len = n > 0 ? WideCharToMultiByte(CP_UTF8, 0, wide, n, utf8, cap - 1, NULL, NULL) : 0;
	utf8[len] = '\0';
	return n;
}

static void imePreedit(const char *utf8, int cursor) {
	voidAppTextDeliver(VOID_EVENT_PREEDIT, utf8, cursor);
	s_preeditActive = utf8[0] != '\0';
}

static void imeComposition(HWND hwnd, LPARAM lParam) {
	static char utf8[2048];
	HIMC himc = ImmGetContext(hwnd);
	if (himc == NULL) return;
	if (lParam & GCS_RESULTSTR) {
		imeString(himc, GCS_RESULTSTR, utf8, sizeof utf8);
		if (s_preeditActive) imePreedit("", 0);
		if (utf8[0] != '\0') voidAppTextDeliver(VOID_EVENT_TEXT_INPUT, utf8, 0);
	}
	if (lParam & GCS_COMPSTR) {
		int n = imeString(himc, GCS_COMPSTR, utf8, sizeof utf8);
		LONG cursor = (lParam & GCS_CURSORPOS) ? ImmGetCompositionStringW(himc, GCS_CURSORPOS, NULL, 0) : n;
		imePreedit(utf8, cursor < 0 || cursor > n ? n : (int)cursor);
	}
	if (lParam == 0 && s_preeditActive) imePreedit("", 0);
	ImmReleaseContext(hwnd, himc);
}

static bool s_sizeMove;

// Handled here, WM_IME_COMPOSITION never reaches DefWindowProc, so Windows posts no
// WM_IME_CHAR/WM_CHAR for the result and the window sends no Char for committed text.
static LRESULT CALLBACK windowProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam, UINT_PTR id, DWORD_PTR data) {
	(void)id;
	(void)data;
	if (msg == WM_ENTERSIZEMOVE) s_sizeMove = true;
	if (msg == WM_EXITSIZEMOVE) s_sizeMove = false;
	if (imeTaken()) {
		switch (msg) {
			case WM_IME_STARTCOMPOSITION: imePlace(hwnd); return 0;
			case WM_IME_COMPOSITION: imeComposition(hwnd, lParam); return 0;
			case WM_IME_ENDCOMPOSITION:
				if (s_preeditActive) imePreedit("", 0);
				return 0;
			case WM_KEYDOWN:
				if (wParam == VK_PROCESSKEY) return DefWindowProcW(hwnd, msg, wParam, lParam);
				break;
			default: break;
		}
	}
	return DefSubclassProc(hwnd, msg, wParam, lParam);
}

static void applyTextInput(HWND hwnd) {
	if (s_textInput == -1) return;
	ImmAssociateContextEx(hwnd, NULL, s_textInput == 1 ? IACE_DEFAULT : 0);
	if (s_textInput == 1 && GetFocus() == hwnd) imePlace(hwnd);
}

void voidSetTextInput(int on) {
	s_textInput = on != 0;
	HWND hwnd = windowHwnd();
	if (hwnd != NULL) applyTextInput(hwnd);
}

void voidSetImeRect(int x, int y, int w, int h) {
	s_imeRect.left = x;
	s_imeRect.top = y;
	s_imeRect.right = x + w;
	s_imeRect.bottom = y + h;
	HWND hwnd = windowHwnd();
	if (hwnd != NULL && imeTaken() && GetFocus() == hwnd) imePlace(hwnd);
}

static int s_sampleCount;

static void _init(void) {
	HWND hwnd = voidWin32Hwnd();
	voidWindowSurfaceCreate(hwnd, s_sampleCount);
	if (!SetWindowSubclass(hwnd, windowProc, 1, 0)) voidFail("SetWindowSubclass on the Void window failed");
	applyTextInput(hwnd);
	call0(s_init);
}
static bool s_committed;

static void _frame(void) {
	if (s_contextLost) restoreContext();
	s_committed = false;
	call0(s_frame);
	if (s_committed) voidWindowPresent(s_sizeMove);
	else if (!s_sizeMove) DwmFlush();
}

static void _event(const VoidAppEvent *e) {
#ifdef VOID_PROFILER
	if (e->type == VOID_EVENT_KEY_DOWN || e->type == VOID_EVENT_KEY_UP
		|| e->type == VOID_EVENT_CHAR || e->type == VOID_EVENT_MOUSE_DOWN
		|| e->type == VOID_EVENT_MOUSE_UP || e->type == VOID_EVENT_MOUSE_SCROLL) {
		voidProfileInput();
	}
#endif
	if (e->type == VOID_EVENT_KEY_DOWN) {
		s_keys[e->keyCode] = true;
	} else if (e->type == VOID_EVENT_KEY_UP) {
		s_keys[e->keyCode] = false;
	}
	if (voidAppDeliver(e)) return;
	if (e->type == VOID_EVENT_KEY_DOWN && e->keyCode == VOID_KEY_ESCAPE) voidWin32RequestQuit();
}

static void _cleanup(void) {
	sg_shutdown();
	voidWindowSurfaceDestroy();
}

void voidRunConfigured(int w, int h, int sampleCount, int highDpi, msClosure init, msClosure frame) {
	if (s_driver != DRIVER_NONE) voidFail("voidRun: this process already drives Void through host views");
	s_driver = DRIVER_WINDOW;
	s_reqW = w;
	s_reqH = h;
	s_init = init;
	s_frame = frame;
	s_sampleCount = sampleCount;
	VoidWin32Desc d = {0};
	d.init = _init;
	d.frame = _frame;
	d.event = _event;
	d.cleanup = _cleanup;
	d.width = w;
	d.height = h;
	d.highDpi = highDpi != 0;
	d.title = voidWindowTitle();
	voidWin32Run(&d);
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
	ID3D11Texture2D *depth;
	ID3D11DepthStencilView *depthTarget;
	int w, h, samples;
	bool hasDepth;
} WinSurface;

static void createDevice(UINT flags) {
	const D3D_FEATURE_LEVEL wanted[] = { D3D_FEATURE_LEVEL_11_1, D3D_FEATURE_LEVEL_11_0 };
	D3D_FEATURE_LEVEL level;
	HRESULT hr = D3D11CreateDevice(NULL, D3D_DRIVER_TYPE_HARDWARE, NULL, flags | D3D11_CREATE_DEVICE_BGRA_SUPPORT,
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
}

void voidPlatformDeviceEnsure(void) {
	if (s_driver == DRIVER_WINDOW) voidFail("voidViewCreate: this process already runs a Void window");
	if (s_driver == DRIVER_VIEWS) return;
#if defined(SOKOL_GLCORE)
	voidFail("voidViewCreate: host views on Windows render through D3D11; this is a GL core build");
#endif
	createDevice(0);
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
	const int samples = s->samples;
	D3D11_TEXTURE2D_DESC desc;
	ZeroMemory(&desc, sizeof desc);
	desc.Width = (UINT)s->w;
	desc.Height = (UINT)s->h;
	desc.MipLevels = 1;
	desc.ArraySize = 1;
	desc.SampleDesc.Count = (UINT)samples;
	desc.SampleDesc.Quality = samples > 1 ? (UINT)D3D11_STANDARD_MULTISAMPLE_PATTERN : 0;
	desc.Usage = D3D11_USAGE_DEFAULT;
	if (samples > 1) {
		UINT quality = 0;
		hr = ID3D11Device_CheckMultisampleQualityLevels(s_device, DXGI_FORMAT_B8G8R8A8_UNORM, (UINT)samples, &quality);
		if (FAILED(hr) || quality == 0) voidFail("the D3D11 device cannot render BGRA8 at %d samples", samples);
		desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
		desc.BindFlags = D3D11_BIND_RENDER_TARGET;
		hr = ID3D11Device_CreateTexture2D(s_device, &desc, NULL, &s->msaa);
		if (FAILED(hr)) voidFail("CreateTexture2D %dx%d at %d samples failed: 0x%08lx", s->w, s->h, samples, (unsigned long)hr);
		hr = ID3D11Device_CreateRenderTargetView(s_device, (ID3D11Resource *)s->msaa, NULL, &s->msaaTarget);
		if (FAILED(hr)) voidFail("CreateRenderTargetView on the %d-sample target failed: 0x%08lx", samples, (unsigned long)hr);
	}
	if (s->hasDepth) {
		desc.Format = DXGI_FORMAT_D32_FLOAT;
		desc.BindFlags = D3D11_BIND_DEPTH_STENCIL;
		hr = ID3D11Device_CreateTexture2D(s_device, &desc, NULL, &s->depth);
		if (FAILED(hr)) voidFail("CreateTexture2D depth %dx%d at %d samples failed: 0x%08lx", s->w, s->h, samples, (unsigned long)hr);
		hr = ID3D11Device_CreateDepthStencilView(s_device, (ID3D11Resource *)s->depth, NULL, &s->depthTarget);
		if (FAILED(hr)) voidFail("CreateDepthStencilView failed: 0x%08lx", (unsigned long)hr);
	}
}

static void releaseTargets(WinSurface *s) {
	ID3D11DeviceContext_OMSetRenderTargets(s_context, 0, NULL, NULL);
	ID3D11RenderTargetView_Release(s->target);
	s->target = NULL;
	if (s->msaaTarget) ID3D11RenderTargetView_Release(s->msaaTarget);
	if (s->msaa) ID3D11Texture2D_Release(s->msaa);
	if (s->depthTarget) ID3D11DepthStencilView_Release(s->depthTarget);
	if (s->depth) ID3D11Texture2D_Release(s->depth);
	s->msaaTarget = NULL;
	s->msaa = NULL;
	s->depthTarget = NULL;
	s->depth = NULL;
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
	s->samples = voidViewsSampleCount();
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
	swapchain->d3d11.depth_stencil_view = s->depthTarget;
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

#if defined(SOKOL_D3D11)
static WinSurface s_window;

void voidWindowSurfaceCreate(HWND hwnd, int samples) {
	createDevice(D3D11_CREATE_DEVICE_SINGLETHREADED);
	IDXGIDevice1 *dxgiDevice = NULL;
	HRESULT hr = ID3D11Device_QueryInterface(s_device, &IID_IDXGIDevice1, (void **)&dxgiDevice);
	if (FAILED(hr)) voidFail("the D3D11 device has no IDXGIDevice1: 0x%08lx", (unsigned long)hr);
	IDXGIDevice1_SetMaximumFrameLatency(dxgiDevice, 1);
	IDXGIDevice1_Release(dxgiDevice);
	IDXGIFactory2_MakeWindowAssociation(s_factory, hwnd, DXGI_MWA_NO_ALT_ENTER | DXGI_MWA_NO_PRINT_SCREEN);
	s_window.w = voidWin32Width();
	s_window.h = voidWin32Height();
	s_window.samples = samples;
	s_window.hasDepth = true;
	DXGI_SWAP_CHAIN_DESC1 desc;
	ZeroMemory(&desc, sizeof desc);
	desc.Width = (UINT)s_window.w;
	desc.Height = (UINT)s_window.h;
	desc.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
	desc.SampleDesc.Count = 1;
	desc.BufferUsage = DXGI_USAGE_RENDER_TARGET_OUTPUT;
	desc.BufferCount = 2;
	desc.Scaling = DXGI_SCALING_STRETCH;
	desc.SwapEffect = DXGI_SWAP_EFFECT_FLIP_DISCARD;
	hr = IDXGIFactory2_CreateSwapChainForHwnd(s_factory, (IUnknown *)s_device, hwnd, &desc, NULL, NULL, &s_window.swapChain);
	if (FAILED(hr)) voidFail("CreateSwapChainForHwnd %dx%d failed: 0x%08lx", s_window.w, s_window.h, (unsigned long)hr);
	makeTarget(&s_window);
}

sg_environment voidWindowEnvironment(void) {
	sg_environment e = {0};
	e.defaults.color_format = SG_PIXELFORMAT_BGRA8;
	e.defaults.depth_format = SG_PIXELFORMAT_DEPTH;
	e.defaults.sample_count = s_window.samples;
	e.d3d11.device = s_device;
	e.d3d11.device_context = s_context;
	return e;
}

sg_swapchain voidWindowSwapchain(void) {
	if (voidWin32Width() != s_window.w || voidWin32Height() != s_window.h) {
		voidPlatformSurfaceResize(&s_window, voidWin32Width(), voidWin32Height());
	}
	sg_swapchain swapchain = {0};
	swapchain.width = s_window.w;
	swapchain.height = s_window.h;
	swapchain.sample_count = s_window.samples;
	swapchain.depth_format = SG_PIXELFORMAT_DEPTH;
	voidPlatformSurfaceSwapchain(&s_window, &swapchain);
	return swapchain;
}

void voidWindowPresent(bool modal) {
	HRESULT hr = modal ? IDXGISwapChain1_Present(s_window.swapChain, 0, DXGI_PRESENT_DO_NOT_WAIT)
		: IDXGISwapChain1_Present(s_window.swapChain, 1, 0);
	if (FAILED(hr) && hr != DXGI_ERROR_WAS_STILL_DRAWING) {
		voidFail("IDXGISwapChain1::Present failed: 0x%08lx", (unsigned long)hr);
	}
}

void voidWindowSurfaceDestroy(void) {
	releaseTargets(&s_window);
	IDXGISwapChain1_Release(s_window.swapChain);
	IDXGIFactory2_Release(s_factory);
	ID3D11DeviceContext_Release(s_context);
	ID3D11Device_Release(s_device);
}

void *voidWindowSwapChain(void) { return s_window.swapChain; }
#endif

static void setupWindowGfx(void) {
	sg_desc d = {0};
	d.environment = voidWindowEnvironment();
	d.logger.func = slog_func;
	sg_setup(&d);
	if (!sg_isvalid()) voidFail("sg_setup on the Void window failed");
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
	if (s_driver == DRIVER_WINDOW) return voidWin32Width();
	if (s_driver == DRIVER_NONE) noDriver("fbWidth");
	return voidViewsFbWidth();
}

int voidFbHeight(void) {
	if (s_driver == DRIVER_WINDOW) return voidWin32Height();
	if (s_driver == DRIVER_NONE) noDriver("fbHeight");
	return voidViewsFbHeight();
}

float voidDpiScale(void) {
	if (s_driver == DRIVER_WINDOW) return voidWin32DpiScale();
	if (s_driver == DRIVER_NONE) noDriver("dpiScale");
	return voidViewsDpiScale();
}

int voidKeyDown(int keycode) {
	if (s_driver != DRIVER_WINDOW || keycode < 0 || keycode >= VOID_KEY_COUNT) return 0;
	return s_keys[keycode] ? 1 : 0;
}

sg_swapchain voidDriverSwapchain(void) {
	if (s_driver == DRIVER_WINDOW) return voidWindowSwapchain();
	if (s_driver == DRIVER_NONE) noDriver("beginPass");
	return voidViewsSwapchain();
}

void voidDriverPresent(void) {
	if (s_driver == DRIVER_WINDOW) s_committed = true;
	if (s_driver == DRIVER_VIEWS) voidViewsPresent();
}
