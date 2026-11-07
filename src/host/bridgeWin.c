#define COBJMACROS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#include <commctrl.h>
#include <imm.h>
#include <dxgi1_5.h>
#include <dwmapi.h>
#include <stdint.h>
#include <stdlib.h>

#include "backend.h"
#include "bridge.h"
#include "viewsExports.h"
#include "windowSurface.h"
#include "../gpu/door.h"
#include "../platform/swapchain.h"

#include "appWindow.h"
#include "../platform/win32/window.h"

static msClosure s_init;
static msClosure s_frame;
static int s_reqW = 0;
static int s_reqH = 0;


enum { REMOVAL_NONE, REMOVAL_RECOVER, REMOVAL_FATAL };
int32_t voidDxgiRemovalAction(int32_t hr);

static void setupViewsGfx(void);


static void restoreDoor(void) {
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
#if defined(VOID_VULKAN)
	if (!voidWindowAwaitFrame()) return;
#else
	if (!s_sizeMove && !voidWindowAwaitFrame()) return;
#endif
	s_committed = false;
	voidCallClosure(s_frame);
	if (s_committed) voidWindowPresent(s_sizeMove);
	else if (!s_sizeMove) DwmFlush();
}

static void _cleanup(void) {
#if defined(VOID_D3D12)
	voidWindowSurfaceDestroy();
	doorShutdown();
#else
	doorShutdown();
	voidWindowSurfaceDestroy();
#endif
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

#if defined(VOID_D3D12)
uint32_t voidD3d12SurfaceOpen(uint64_t window, int32_t composition, int32_t width, int32_t height, int32_t presentMode);
uint64_t voidD3d12SurfaceWaitable(uint32_t surface);
uint64_t voidD3d12SurfaceNative(uint32_t surface);
void voidD3d12SurfaceFit(uint32_t surface, int32_t width, int32_t height);
int32_t voidD3d12SurfaceWidth(uint32_t surface);
int32_t voidD3d12SurfaceHeight(uint32_t surface);
int32_t voidD3d12SurfacePresent(uint32_t surface, int32_t modal);
void voidD3d12SurfaceClose(uint32_t surface);
int32_t voidD3d12RemovedReason(void);

static void closeWindowSurface(void);
#endif

#if defined(VOID_D3D12)
// What the last doorSetup made screen pipelines for; every swapchain handed to the door must match.
static int s_doorSamples;

static void deviceRemoved(const char *what, HRESULT hr) {
	if (voidDxgiRemovalAction((int32_t)hr) == REMOVAL_NONE) voidFail("%s failed: 0x%08lx", what, (unsigned long)hr);
	HRESULT reason = (HRESULT)voidD3d12RemovedReason();
	if (voidDxgiRemovalAction((int32_t)reason) != REMOVAL_RECOVER) {
		voidFail("%s failed: 0x%08lx, the device was removed for 0x%08lx, which Void does not recover from",
			what, (unsigned long)hr, (unsigned long)reason);
	}
	if (voidDriver != VOID_DRIVER_WINDOW) {
		voidFail("%s failed: 0x%08lx, the device was removed for 0x%08lx and host views cannot rebuild their swap chains",
			what, (unsigned long)hr, (unsigned long)reason);
	}
	closeWindowSurface();
	voidLoseContext();
}

static void setupDoor(int32_t depthFormat, int samples) {
	doorSetup(NULL, NULL, DOOR_PIXEL_FORMAT_BGRA8, depthFormat, samples);
	if (!doorValid()) voidFail("doorSetup on the D3D12 device failed");
	s_doorSamples = samples;
}

typedef struct {
	uint32_t surface;
	HANDLE frameLatency;
	int samples;
	bool admitted;
} WinSurface;

static int surfaceReady(WinSurface *s) {
	if (!s->admitted) s->admitted = WaitForSingleObjectEx(s->frameLatency, 0, FALSE) == WAIT_OBJECT_0;
	return s->admitted;
}
#endif

void voidPlatformDeviceEnsure(void) {
	if (voidDriver == VOID_DRIVER_WINDOW) voidFail("voidViewCreate: this process already runs a Void window");
	if (voidDriver == VOID_DRIVER_VIEWS) return;
	setupViewsGfx();
	voidDriver = VOID_DRIVER_VIEWS;
}

void voidPlatformRunInit(msClosure init) { voidCallClosure(init); }

#if defined(VOID_D3D12)
static void setupViewsGfx(void) {
	setupDoor(DOOR_PIXEL_FORMAT_NONE, voidViewsSampleCount());
}

void *voidPlatformSurfaceCreate(const void *native, int w, int h) {
	(void)native;
	WinSurface *s = (WinSurface *)calloc(1, sizeof(WinSurface));
	if (s == NULL) voidFail("voidViewCreate: out of memory for a D3D12 surface");
	s->samples = voidViewsSampleCount();
	s->surface = voidD3d12SurfaceOpen(0, 1, w, h, 0);
	s->frameLatency = (HANDLE)(uintptr_t)voidD3d12SurfaceWaitable(s->surface);
	return s;
}

void voidPlatformSurfaceResize(void *surface, int w, int h) {
	voidD3d12SurfaceFit(((WinSurface *)surface)->surface, w, h);
}

int voidPlatformSurfaceReady(void *surface) { return surfaceReady((WinSurface *)surface); }

int voidPlatformSurfaceAcquire(void *surface) {
	(void)surface;
	voidRestoreContextIfLost(restoreDoor);
	return 1;
}

void voidPlatformSurfacePresent(void *surface) {
	WinSurface *s = (WinSurface *)surface;
	s->admitted = false;
	HRESULT hr = (HRESULT)voidD3d12SurfacePresent(s->surface, 0);
	if (hr != 0) deviceRemoved("IDXGISwapChain3::Present", hr);
}

void voidPlatformSurfaceDestroy(void *surface) {
	WinSurface *s = (WinSurface *)surface;
	voidD3d12SurfaceClose(s->surface);
	free(s);
}

long long voidPlatformSurfaceNative(void *surface) {
	return (long long)voidD3d12SurfaceNative(((WinSurface *)surface)->surface);
}

static WinSurface s_window;
static HWND s_hwnd;

void voidWindowSurfaceCreate(HWND hwnd, int samples) {
	s_hwnd = hwnd;
	s_window.samples = samples;
}

static void closeWindowSurface(void) {
	if (s_window.surface == 0) return;
	voidD3d12SurfaceClose(s_window.surface);
	s_window.surface = 0;
	s_window.frameLatency = NULL;
	s_window.admitted = false;
}

void voidWindowDoorSetup(void) {
	if (s_window.surface != 0) voidFail("voidWindowDoorSetup while the D3D12 window swapchain is open; the door is set up once per device");
	setupDoor(DOOR_PIXEL_FORMAT_DEPTH, s_window.samples);
	s_window.surface = voidD3d12SurfaceOpen((uint64_t)(uintptr_t)s_hwnd, 0, voidWindowWidth(), voidWindowHeight(), voidPresentMode());
	s_window.frameLatency = (HANDLE)(uintptr_t)voidD3d12SurfaceWaitable(s_window.surface);
}

bool voidWindowAwaitFrame(void) {
	if (s_window.surface == 0 || surfaceReady(&s_window)) return true;
	DWORD woke = MsgWaitForMultipleObjectsEx(1, &s_window.frameLatency, INFINITE, QS_ALLINPUT, MWMO_INPUTAVAILABLE);
	s_window.admitted = woke == WAIT_OBJECT_0;
	return s_window.admitted;
}

void voidWindowPresent(bool modal) {
	if (s_window.surface == 0) voidFail("present on the D3D12 window before voidGfxSetup opened its swapchain");
	s_window.admitted = false;
	HRESULT hr = (HRESULT)voidD3d12SurfacePresent(s_window.surface, modal ? 1 : 0);
	if (hr != 0) deviceRemoved("IDXGISwapChain3::Present", hr);
}

void voidWindowSurfaceDestroy(void) { closeWindowSurface(); }

static WinSurface *screenSurface(void) {
	WinSurface *s = &s_window;
	if (voidDriverFor("beginPass") == VOID_DRIVER_VIEWS) {
		s = (WinSurface *)voidViewsCurrentSurface();
	} else {
		if (s_window.surface == 0) voidFail("the screen pass before voidGfxSetup opened the D3D12 window swapchain");
		voidD3d12SurfaceFit(s_window.surface, voidWindowWidth(), voidWindowHeight());
	}
	if (s->samples != s_doorSamples) {
		voidFail("the swapchain has %d samples, but screen pipelines are made for the door's %d samples", s->samples, s_doorSamples);
	}
	return s;
}

int32_t voidSwapchainWidth(void) { return voidD3d12SurfaceWidth(screenSurface()->surface); }
int32_t voidSwapchainHeight(void) { return voidD3d12SurfaceHeight(screenSurface()->surface); }
int32_t voidSwapchainSampleCount(void) { return screenSurface()->samples; }
void *voidSwapchainRenderView(void) { return (void *)(uintptr_t)screenSurface()->surface; }
void *voidSwapchainResolveView(void) { return NULL; }
void *voidSwapchainDepthStencilView(void) { return NULL; }
#else
static void setupViewsGfx(void) {
#if defined(VOID_GLCORE)
	voidFail("voidViewCreate: host views on Windows render through D3D12; this is a GL core build");
#else
	voidFail("voidViewCreate: host views on Windows render through D3D12; this is a Vulkan build");
#endif
}

static void refuseSurface(const char *call) { voidFail("%s: host views on Windows render through D3D12, not this build", call); }
void *voidPlatformSurfaceCreate(const void *native, int w, int h) { (void)native; (void)w; (void)h; refuseSurface("voidPlatformSurfaceCreate"); return NULL; }
void voidPlatformSurfaceResize(void *surface, int w, int h) { (void)surface; (void)w; (void)h; refuseSurface("voidPlatformSurfaceResize"); }
int voidPlatformSurfaceReady(void *surface) { (void)surface; refuseSurface("voidPlatformSurfaceReady"); return 0; }
int voidPlatformSurfaceAcquire(void *surface) { (void)surface; refuseSurface("voidPlatformSurfaceAcquire"); return 0; }
void voidPlatformSurfacePresent(void *surface) { (void)surface; refuseSurface("voidPlatformSurfacePresent"); }
void voidPlatformSurfaceDestroy(void *surface) { (void)surface; refuseSurface("voidPlatformSurfaceDestroy"); }
long long voidPlatformSurfaceNative(void *surface) { (void)surface; refuseSurface("voidPlatformSurfaceNative"); return 0; }
#endif

#if defined(VOID_GLCORE)
// The GL window draws into its default framebuffer, which has no view objects; host views are refused.
int32_t voidSwapchainWidth(void) { return voidWindowWidth(); }
int32_t voidSwapchainHeight(void) { return voidWindowHeight(); }
int32_t voidSwapchainSampleCount(void) { return s_sampleCount; }
void *voidSwapchainRenderView(void) { return NULL; }
void *voidSwapchainResolveView(void) { return NULL; }
void *voidSwapchainDepthStencilView(void) { return NULL; }
#endif

void voidDriverPresent(void) {
	if (voidDriver == VOID_DRIVER_WINDOW) s_committed = true;
	if (voidDriver == VOID_DRIVER_VIEWS) voidViewsPresent();
}
