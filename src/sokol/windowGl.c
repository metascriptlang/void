#include "backend.h"
#include "windowSurface.h"
#include "views.h"
#include "../platform/win32/window.h"

#define WGL_DRAW_TO_WINDOW_ARB 0x2001
#define WGL_ACCELERATION_ARB 0x2003
#define WGL_SUPPORT_OPENGL_ARB 0x2010
#define WGL_DOUBLE_BUFFER_ARB 0x2011
#define WGL_PIXEL_TYPE_ARB 0x2013
#define WGL_COLOR_BITS_ARB 0x2014
#define WGL_ALPHA_BITS_ARB 0x201b
#define WGL_DEPTH_BITS_ARB 0x2022
#define WGL_STENCIL_BITS_ARB 0x2023
#define WGL_FULL_ACCELERATION_ARB 0x2027
#define WGL_TYPE_RGBA_ARB 0x202b
#define WGL_SAMPLE_BUFFERS_ARB 0x2041
#define WGL_SAMPLES_ARB 0x2042
#define WGL_CONTEXT_MAJOR_VERSION_ARB 0x2091
#define WGL_CONTEXT_MINOR_VERSION_ARB 0x2092
#define WGL_CONTEXT_FLAGS_ARB 0x2094
#define WGL_CONTEXT_PROFILE_MASK_ARB 0x9126
#define WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB 0x0002
#define WGL_CONTEXT_CORE_PROFILE_BIT_ARB 0x0001

typedef BOOL (WINAPI *ChoosePixelFormatFn)(HDC, const int *, const FLOAT *, UINT, int *, UINT *);
typedef HGLRC (WINAPI *CreateContextAttribsFn)(HDC, HGLRC, const int *);
typedef BOOL (WINAPI *SwapIntervalFn)(int);

static ChoosePixelFormatFn s_choosePixelFormat;
static CreateContextAttribsFn s_createContextAttribs;
static SwapIntervalFn s_swapInterval;
static HDC s_dc;
static HGLRC s_context;
static int s_samples;

static void loadExtensions(void) {
	HWND probe = CreateWindowExW(0, L"STATIC", L"", WS_POPUP, 0, 0, 1, 1, NULL, NULL, GetModuleHandleW(NULL), NULL);
	if (probe == NULL) voidFail("CreateWindowExW for the WGL extension probe failed: %lu", GetLastError());
	HDC dc = GetDC(probe);
	PIXELFORMATDESCRIPTOR pfd;
	ZeroMemory(&pfd, sizeof pfd);
	pfd.nSize = sizeof pfd;
	pfd.nVersion = 1;
	pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
	pfd.iPixelType = PFD_TYPE_RGBA;
	pfd.cColorBits = 24;
	if (!SetPixelFormat(dc, ChoosePixelFormat(dc, &pfd), &pfd)) voidFail("SetPixelFormat on the WGL extension probe failed: %lu", GetLastError());
	HGLRC rc = wglCreateContext(dc);
	if (rc == NULL || !wglMakeCurrent(dc, rc)) voidFail("the WGL extension probe context failed: %lu", GetLastError());
	s_choosePixelFormat = (ChoosePixelFormatFn)(void *)wglGetProcAddress("wglChoosePixelFormatARB");
	s_createContextAttribs = (CreateContextAttribsFn)(void *)wglGetProcAddress("wglCreateContextAttribsARB");
	s_swapInterval = (SwapIntervalFn)(void *)wglGetProcAddress("wglSwapIntervalEXT");
	wglMakeCurrent(NULL, NULL);
	wglDeleteContext(rc);
	ReleaseDC(probe, dc);
	DestroyWindow(probe);
	if (!s_choosePixelFormat) voidFail("the GL driver lacks WGL_ARB_pixel_format");
	if (!s_createContextAttribs) voidFail("the GL driver lacks WGL_ARB_create_context");
	if (!s_swapInterval) voidFail("the GL driver lacks WGL_EXT_swap_control");
}

void voidWindowSurfaceCreate(HWND hwnd, int samples) {
	loadExtensions();
	s_samples = samples;
	s_dc = GetDC(hwnd);
	const int wanted[] = {
		WGL_DRAW_TO_WINDOW_ARB, 1,
		WGL_SUPPORT_OPENGL_ARB, 1,
		WGL_DOUBLE_BUFFER_ARB, 1,
		WGL_ACCELERATION_ARB, WGL_FULL_ACCELERATION_ARB,
		WGL_PIXEL_TYPE_ARB, WGL_TYPE_RGBA_ARB,
		WGL_COLOR_BITS_ARB, 24,
		WGL_ALPHA_BITS_ARB, 8,
		WGL_DEPTH_BITS_ARB, 24,
		WGL_STENCIL_BITS_ARB, 0,
		WGL_SAMPLE_BUFFERS_ARB, samples > 1,
		WGL_SAMPLES_ARB, samples > 1 ? samples : 0,
		0,
	};
	int format = 0;
	UINT count = 0;
	if (!s_choosePixelFormat(s_dc, wanted, NULL, 1, &format, &count) || count == 0) {
		voidFail("no WGL pixel format with RGBA8, depth 24 and %d samples", samples);
	}
	PIXELFORMATDESCRIPTOR pfd;
	DescribePixelFormat(s_dc, format, sizeof pfd, &pfd);
	if (!SetPixelFormat(s_dc, format, &pfd)) voidFail("SetPixelFormat on the Void window failed: %lu", GetLastError());
	const int attrs[] = {
		WGL_CONTEXT_MAJOR_VERSION_ARB, 4,
		WGL_CONTEXT_MINOR_VERSION_ARB, 3,
		WGL_CONTEXT_FLAGS_ARB, WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB,
		WGL_CONTEXT_PROFILE_MASK_ARB, WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
		0,
	};
	s_context = s_createContextAttribs(s_dc, NULL, attrs);
	if (s_context == NULL) voidFail("wglCreateContextAttribsARB for GL core 4.3 failed: 0x%08lx", GetLastError());
	if (!wglMakeCurrent(s_dc, s_context)) voidFail("wglMakeCurrent on the Void window failed: %lu", GetLastError());
	s_swapInterval(1);
}

sg_environment voidWindowEnvironment(void) {
	sg_environment e = {0};
	e.defaults.color_format = SG_PIXELFORMAT_RGBA8;
	e.defaults.depth_format = SG_PIXELFORMAT_DEPTH;
	e.defaults.sample_count = s_samples;
	return e;
}

sg_swapchain voidWindowSwapchain(void) {
	sg_swapchain swapchain = {0};
	swapchain.width = voidWin32Width();
	swapchain.height = voidWin32Height();
	swapchain.sample_count = s_samples;
	swapchain.color_format = SG_PIXELFORMAT_RGBA8;
	swapchain.depth_format = SG_PIXELFORMAT_DEPTH;
	return swapchain;
}

void voidWindowPresent(bool modal) {
	(void)modal;
	SwapBuffers(s_dc);
}

void voidWindowSurfaceDestroy(void) {
	wglMakeCurrent(NULL, NULL);
	wglDeleteContext(s_context);
}
