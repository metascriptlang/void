#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <commctrl.h>
#include <imm.h>
#include <d3d11.h>
#include <dxgi1_3.h>
#include <dwmapi.h>
#include <stdint.h>
#include <stdlib.h>

#include "backend.h"
#include "bridge.h"
#include "views.h"
#include "windowSurface.h"
#include "../gpu/door.h"
#include "../platform/swapchain.h"

#include "appWindow.h"
#include "../platform/win32/window.h"

static msClosure s_init;
static msClosure s_frame;
static int s_reqW = 0;
static int s_reqH = 0;

static int s_deviceRemoved = 0;

enum { REMOVAL_NONE, REMOVAL_RECOVER, REMOVAL_FATAL };
int32_t voidD3d11RemovalAction(int32_t hr);

static void setupViewsGfx(void);

#if defined(VOID_D3D11)
static void recreateWindowDevice(void);
#endif

static void restoreDoor(void) {
#if defined(VOID_D3D11)
	if (s_deviceRemoved) recreateWindowDevice();
#endif
	s_deviceRemoved = 0;
	if (voidDriver == VOID_DRIVER_WINDOW) voidWindowDoorSetup();
	else setupViewsGfx();
}

static int s_textInput = -1;
static RECT s_imeRect;
static bool s_preeditActive;

static HWND windowHwnd(void) {
	return voidDriver == VOID_DRIVER_WINDOW && voidWindowValid() ? voidWin32Hwnd() : NULL;
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
	voidCallClosure(s_init);
}
static bool s_committed;

static void _frame(void) {
	voidRestoreContextIfLost(restoreDoor);
	if (!s_sizeMove && !voidWindowAwaitFrame()) return;
	s_committed = false;
	voidCallClosure(s_frame);
	if (s_committed) voidWindowPresent(s_sizeMove);
	else if (!s_sizeMove) DwmFlush();
}

static void _cleanup(void) {
	doorShutdown();
	voidWindowSurfaceDestroy();
}

void voidRunConfigured(int w, int h, int sampleCount, int highDpi, msClosure init, msClosure frame) {
	if (voidDriver != VOID_DRIVER_NONE) voidFail("voidRun: this process already drives Void through host views");
	voidDriver = VOID_DRIVER_WINDOW;
	s_reqW = w;
	s_reqH = h;
	s_init = init;
	s_frame = frame;
	s_sampleCount = sampleCount;
	VoidWin32Desc d = {0};
	d.init = _init;
	d.frame = _frame;
	d.event = voidAppWindowEvent;
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

// What the last doorSetup made screen pipelines for; every swapchain handed to the door must match.
static int s_doorSamples;
static bool s_doorDepth;

static void deviceRemoved(const char *what, HRESULT hr) {
#if defined(VOID_GLCORE)
	voidFail("%s failed: 0x%08lx in a GL core build, whose host views are refused", what, (unsigned long)hr);
#else
	if (voidD3d11RemovalAction((int32_t)hr) == REMOVAL_NONE) voidFail("%s failed: 0x%08lx", what, (unsigned long)hr);
	HRESULT reason = ID3D11Device_GetDeviceRemovedReason(s_device);
	if (voidD3d11RemovalAction((int32_t)reason) != REMOVAL_RECOVER) {
		voidFail("%s failed: 0x%08lx, the device was removed for 0x%08lx, which Void does not recover from",
			what, (unsigned long)hr, (unsigned long)reason);
	}
	if (voidDriver != VOID_DRIVER_WINDOW) {
		voidFail("%s failed: 0x%08lx, the device was removed for 0x%08lx and host views cannot rebuild their swap chains",
			what, (unsigned long)hr, (unsigned long)reason);
	}
	s_deviceRemoved = 1;
	voidLoseContext();
#endif
}

void *voidD3d11Device(void) { return s_device; }
void *voidD3d11Context(void) { return s_context; }

static void setupDoor(int32_t depthFormat, int samples) {
	doorSetup(s_device, s_context, DOOR_PIXEL_FORMAT_BGRA8, depthFormat, samples);
	if (!doorValid()) voidFail("doorSetup on the D3D11 device failed");
	s_doorSamples = samples;
	s_doorDepth = depthFormat != DOOR_PIXEL_FORMAT_NONE;
}

typedef struct {
	IDXGISwapChain1 *swapChain;
	ID3D11RenderTargetView *target;
	ID3D11Texture2D *msaa;
	ID3D11RenderTargetView *msaaTarget;
	ID3D11Texture2D *depth;
	ID3D11DepthStencilView *depthTarget;
	HANDLE frameLatency;
	int w, h, samples;
	bool hasDepth;
	bool admitted;
} WinSurface;

static const UINT VOID_SWAP_FLAGS = DXGI_SWAP_CHAIN_FLAG_FRAME_LATENCY_WAITABLE_OBJECT;
static const UINT VOID_FRAME_LATENCY = 2;

static void watchFrameLatency(WinSurface *s) {
	IDXGISwapChain2 *chain2 = NULL;
	HRESULT hr = IDXGISwapChain1_QueryInterface(s->swapChain, &IID_IDXGISwapChain2, (void **)&chain2);
	if (FAILED(hr)) voidFail("the swap chain has no IDXGISwapChain2: 0x%08lx", (unsigned long)hr);
	hr = IDXGISwapChain2_SetMaximumFrameLatency(chain2, VOID_FRAME_LATENCY);
	if (FAILED(hr)) voidFail("SetMaximumFrameLatency(%u) failed: 0x%08lx", VOID_FRAME_LATENCY, (unsigned long)hr);
	s->frameLatency = IDXGISwapChain2_GetFrameLatencyWaitableObject(chain2);
	IDXGISwapChain2_Release(chain2);
	if (s->frameLatency == NULL) voidFail("the swap chain gave no frame latency waitable object");
}

static int surfaceReady(WinSurface *s) {
	if (!s->admitted) s->admitted = WaitForSingleObjectEx(s->frameLatency, 0, FALSE) == WAIT_OBJECT_0;
	return s->admitted;
}

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
	if (voidDriver == VOID_DRIVER_WINDOW) voidFail("voidViewCreate: this process already runs a Void window");
	if (voidDriver == VOID_DRIVER_VIEWS) return;
#if defined(VOID_GLCORE)
	voidFail("voidViewCreate: host views on Windows render through D3D11; this is a GL core build");
#endif
	createDevice(0);
	setupViewsGfx();
	voidDriver = VOID_DRIVER_VIEWS;
}

static void setupViewsGfx(void) {
	setupDoor(DOOR_PIXEL_FORMAT_NONE, voidViewsSampleCount());
}

void voidPlatformRunInit(msClosure init) { voidCallClosure(init); }

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
	desc.Flags = VOID_SWAP_FLAGS;
	WinSurface *s = (WinSurface *)calloc(1, sizeof(WinSurface));
	s->w = w;
	s->h = h;
	s->samples = voidViewsSampleCount();
	HRESULT hr = IDXGIFactory2_CreateSwapChainForComposition(s_factory, (IUnknown *)s_device, &desc, NULL, &s->swapChain);
	if (FAILED(hr)) voidFail("CreateSwapChainForComposition %dx%d failed: 0x%08lx", w, h, (unsigned long)hr);
	watchFrameLatency(s);
	makeTarget(s);
	return s;
}

void voidPlatformSurfaceResize(void *surface, int w, int h) {
	WinSurface *s = (WinSurface *)surface;
	releaseTargets(s);
	s->w = w;
	s->h = h;
	HRESULT hr = IDXGISwapChain1_ResizeBuffers(s->swapChain, 0, (UINT)w, (UINT)h, DXGI_FORMAT_UNKNOWN, VOID_SWAP_FLAGS);
	if (FAILED(hr)) deviceRemoved("IDXGISwapChain1::ResizeBuffers", hr);
	makeTarget(s);
}

int voidPlatformSurfaceReady(void *surface) { return surfaceReady((WinSurface *)surface); }

int voidPlatformSurfaceAcquire(void *surface) {
	(void)surface;
	voidRestoreContextIfLost(restoreDoor);
	return 1;
}

void voidPlatformSurfacePresent(void *surface) {
	((WinSurface *)surface)->admitted = false;
	HRESULT hr = IDXGISwapChain1_Present(((WinSurface *)surface)->swapChain, 1, 0);
	if (FAILED(hr)) deviceRemoved("IDXGISwapChain1::Present", hr);
}

void voidPlatformSurfaceDestroy(void *surface) {
	WinSurface *s = (WinSurface *)surface;
	releaseTargets(s);
	CloseHandle(s->frameLatency);
	IDXGISwapChain1_Release(s->swapChain);
	free(s);
}

long long voidPlatformSurfaceNative(void *surface) {
	return (long long)(intptr_t)((WinSurface *)surface)->swapChain;
}

#if defined(VOID_D3D11)
static WinSurface s_window;

void voidWindowSurfaceCreate(HWND hwnd, int samples) {
	createDevice(D3D11_CREATE_DEVICE_SINGLETHREADED);
	IDXGIDevice1 *dxgiDevice = NULL;
	HRESULT hr = ID3D11Device_QueryInterface(s_device, &IID_IDXGIDevice1, (void **)&dxgiDevice);
	if (FAILED(hr)) voidFail("the D3D11 device has no IDXGIDevice1: 0x%08lx", (unsigned long)hr);
	IDXGIDevice1_SetMaximumFrameLatency(dxgiDevice, 1);
	IDXGIDevice1_Release(dxgiDevice);
	IDXGIFactory2_MakeWindowAssociation(s_factory, hwnd, DXGI_MWA_NO_ALT_ENTER | DXGI_MWA_NO_PRINT_SCREEN);
	s_window.w = voidWindowWidth();
	s_window.h = voidWindowHeight();
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
	desc.Flags = VOID_SWAP_FLAGS;
	hr = IDXGIFactory2_CreateSwapChainForHwnd(s_factory, (IUnknown *)s_device, hwnd, &desc, NULL, NULL, &s_window.swapChain);
	if (FAILED(hr)) voidFail("CreateSwapChainForHwnd %dx%d failed: 0x%08lx", s_window.w, s_window.h, (unsigned long)hr);
	watchFrameLatency(&s_window);
	makeTarget(&s_window);
}

void voidWindowDoorSetup(void) {
	setupDoor(DOOR_PIXEL_FORMAT_DEPTH, s_window.samples);
}

bool voidWindowAwaitFrame(void) {
	if (surfaceReady(&s_window)) return true;
	DWORD woke = MsgWaitForMultipleObjectsEx(1, &s_window.frameLatency, INFINITE, QS_ALLINPUT, MWMO_INPUTAVAILABLE);
	s_window.admitted = woke == WAIT_OBJECT_0;
	return s_window.admitted;
}

void voidWindowPresent(bool modal) {
	s_window.admitted = false;
	HRESULT hr = modal ? IDXGISwapChain1_Present(s_window.swapChain, 0, DXGI_PRESENT_DO_NOT_WAIT)
		: IDXGISwapChain1_Present(s_window.swapChain, 1, 0);
	if (FAILED(hr) && hr != DXGI_ERROR_WAS_STILL_DRAWING) deviceRemoved("IDXGISwapChain1::Present", hr);
}

void voidWindowSurfaceDestroy(void) {
	releaseTargets(&s_window);
	CloseHandle(s_window.frameLatency);
	IDXGISwapChain1_Release(s_window.swapChain);
	IDXGIFactory2_Release(s_factory);
	ID3D11DeviceContext_Release(s_context);
	ID3D11Device_Release(s_device);
}

static void recreateWindowDevice(void) {
	int samples = s_window.samples;
	voidWindowSurfaceDestroy();
	voidWindowSurfaceCreate(voidWin32Hwnd(), samples);
}

void *voidWindowSwapChain(void) { return s_window.swapChain; }
#endif

// The surface the door's screen pass draws into, or NULL for the GL window, whose default
// framebuffer has no view objects.
static WinSurface *screenSurface(void) {
	WinSurface *s = NULL;
	if (voidDriverFor("beginPass") == VOID_DRIVER_VIEWS) {
		s = (WinSurface *)voidViewsCurrentSurface();
	} else {
#if defined(VOID_D3D11)
		if (voidWindowWidth() != s_window.w || voidWindowHeight() != s_window.h) {
			voidPlatformSurfaceResize(&s_window, voidWindowWidth(), voidWindowHeight());
		}
		s = &s_window;
#endif
	}
	if (s != NULL && (s->samples != s_doorSamples || (s->depthTarget != NULL) != s_doorDepth)) {
		voidFail("the swapchain has %d samples %s depth, but screen pipelines are made for the "
			"door's %d samples %s depth", s->samples, s->depthTarget ? "with" : "without",
			s_doorSamples, s_doorDepth ? "with" : "without");
	}
	return s;
}

int32_t voidSwapchainWidth(void) {
	const WinSurface *s = screenSurface();
	return s ? s->w : voidWindowWidth();
}

int32_t voidSwapchainHeight(void) {
	const WinSurface *s = screenSurface();
	return s ? s->h : voidWindowHeight();
}

int32_t voidSwapchainSampleCount(void) {
	const WinSurface *s = screenSurface();
	return s ? s->samples : s_sampleCount;
}

void *voidSwapchainRenderView(void) {
	const WinSurface *s = screenSurface();
	if (s == NULL) return NULL;
	return s->msaaTarget ? (void *)s->msaaTarget : (void *)s->target;
}

void *voidSwapchainResolveView(void) {
	const WinSurface *s = screenSurface();
	return s && s->msaaTarget ? (void *)s->target : NULL;
}

void *voidSwapchainDepthStencilView(void) {
	const WinSurface *s = screenSurface();
	return s ? (void *)s->depthTarget : NULL;
}

void voidDriverPresent(void) {
	if (voidDriver == VOID_DRIVER_WINDOW) s_committed = true;
	if (voidDriver == VOID_DRIVER_VIEWS) voidViewsPresent();
}
