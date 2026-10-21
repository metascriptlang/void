#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#include <stdio.h>
#include <GL/gl.h>
#include "glWindow.h"

#define WGL_DRAW_TO_WINDOW_ARB 0x2001
#define WGL_ACCELERATION_ARB 0x2003
#define WGL_SUPPORT_OPENGL_ARB 0x2010
#define WGL_DOUBLE_BUFFER_ARB 0x2011
#define WGL_PIXEL_TYPE_ARB 0x2013
#define WGL_COLOR_BITS_ARB 0x2014
#define WGL_ALPHA_BITS_ARB 0x201b
#define WGL_DEPTH_BITS_ARB 0x2022
#define WGL_FULL_ACCELERATION_ARB 0x2027
#define WGL_TYPE_RGBA_ARB 0x202b
#define WGL_CONTEXT_MAJOR_VERSION_ARB 0x2091
#define WGL_CONTEXT_MINOR_VERSION_ARB 0x2092
#define WGL_CONTEXT_FLAGS_ARB 0x2094
#define WGL_CONTEXT_PROFILE_MASK_ARB 0x9126
#define WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB 0x0002
#define WGL_CONTEXT_CORE_PROFILE_BIT_ARB 0x0001
#define GL_READ_FRAMEBUFFER_ID 0x8CA8
#define GL_COLOR_ATTACHMENT0_ID 0x8CE0
#define GL_FRAMEBUFFER_COMPLETE_ID 0x8CD5

typedef BOOL (WINAPI *ChoosePixelFormatFn)(HDC, const int *, const FLOAT *, UINT, int *, UINT *);
typedef HGLRC (WINAPI *CreateContextAttribsFn)(HDC, HGLRC, const int *);
typedef void (APIENTRY *GenFramebuffersFn)(GLsizei, GLuint *);
typedef void (APIENTRY *BindFramebufferFn)(GLenum, GLuint);
typedef void (APIENTRY *FramebufferTexture2DFn)(GLenum, GLenum, GLenum, GLuint, GLint);
typedef GLenum (APIENTRY *CheckFramebufferStatusFn)(GLenum);
typedef void (APIENTRY *DeleteFramebuffersFn)(GLsizei, const GLuint *);

static HWND s_window;
static HDC s_dc;
static HGLRC s_context;
static char s_error[256];
static GenFramebuffersFn s_genFramebuffers;
static BindFramebufferFn s_bindFramebuffer;
static FramebufferTexture2DFn s_framebufferTexture2D;
static CheckFramebufferStatusFn s_checkFramebufferStatus;
static DeleteFramebuffersFn s_deleteFramebuffers;

static int32_t fail(const char *what) {
	snprintf(s_error, sizeof s_error, "%s (GetLastError %lu)", what, GetLastError());
	return 0;
}

static HWND hiddenWindow(void) {
	return CreateWindowExW(0, L"STATIC", L"", WS_POPUP, 0, 0, 64, 64, NULL, NULL, GetModuleHandleW(NULL), NULL);
}

int32_t glWindowOpen(void) {
	if (s_context) return 1;
	HWND probe = hiddenWindow();
	if (probe == NULL) return fail("CreateWindowExW for the WGL probe failed");
	HDC probeDc = GetDC(probe);
	PIXELFORMATDESCRIPTOR pfd;
	ZeroMemory(&pfd, sizeof pfd);
	pfd.nSize = sizeof pfd;
	pfd.nVersion = 1;
	pfd.dwFlags = PFD_DRAW_TO_WINDOW | PFD_SUPPORT_OPENGL | PFD_DOUBLEBUFFER;
	pfd.iPixelType = PFD_TYPE_RGBA;
	pfd.cColorBits = 24;
	if (!SetPixelFormat(probeDc, ChoosePixelFormat(probeDc, &pfd), &pfd)) return fail("SetPixelFormat on the WGL probe failed");
	HGLRC probeContext = wglCreateContext(probeDc);
	if (probeContext == NULL || !wglMakeCurrent(probeDc, probeContext)) return fail("the WGL probe context failed");
	ChoosePixelFormatFn choosePixelFormat = (ChoosePixelFormatFn)(void *)wglGetProcAddress("wglChoosePixelFormatARB");
	CreateContextAttribsFn createContextAttribs = (CreateContextAttribsFn)(void *)wglGetProcAddress("wglCreateContextAttribsARB");
	wglMakeCurrent(NULL, NULL);
	wglDeleteContext(probeContext);
	ReleaseDC(probe, probeDc);
	DestroyWindow(probe);
	if (!choosePixelFormat || !createContextAttribs) return fail("the GL driver lacks WGL_ARB_pixel_format or WGL_ARB_create_context");

	s_window = hiddenWindow();
	if (s_window == NULL) return fail("CreateWindowExW for the GL check window failed");
	s_dc = GetDC(s_window);
	const int wanted[] = {
		WGL_DRAW_TO_WINDOW_ARB, 1,
		WGL_SUPPORT_OPENGL_ARB, 1,
		WGL_DOUBLE_BUFFER_ARB, 1,
		WGL_ACCELERATION_ARB, WGL_FULL_ACCELERATION_ARB,
		WGL_PIXEL_TYPE_ARB, WGL_TYPE_RGBA_ARB,
		WGL_COLOR_BITS_ARB, 24,
		WGL_ALPHA_BITS_ARB, 8,
		WGL_DEPTH_BITS_ARB, 24,
		0,
	};
	int format = 0;
	UINT count = 0;
	if (!choosePixelFormat(s_dc, wanted, NULL, 1, &format, &count) || count == 0) return fail("no WGL pixel format with RGBA8 and depth 24");
	DescribePixelFormat(s_dc, format, sizeof pfd, &pfd);
	if (!SetPixelFormat(s_dc, format, &pfd)) return fail("SetPixelFormat on the GL check window failed");
	const int attrs[] = {
		WGL_CONTEXT_MAJOR_VERSION_ARB, 4,
		WGL_CONTEXT_MINOR_VERSION_ARB, 3,
		WGL_CONTEXT_FLAGS_ARB, WGL_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB,
		WGL_CONTEXT_PROFILE_MASK_ARB, WGL_CONTEXT_CORE_PROFILE_BIT_ARB,
		0,
	};
	s_context = createContextAttribs(s_dc, NULL, attrs);
	if (s_context == NULL) return fail("wglCreateContextAttribsARB for GL core 4.3 failed");
	if (!wglMakeCurrent(s_dc, s_context)) return fail("wglMakeCurrent on the GL check window failed");
	s_genFramebuffers = (GenFramebuffersFn)(void *)wglGetProcAddress("glGenFramebuffers");
	s_bindFramebuffer = (BindFramebufferFn)(void *)wglGetProcAddress("glBindFramebuffer");
	s_framebufferTexture2D = (FramebufferTexture2DFn)(void *)wglGetProcAddress("glFramebufferTexture2D");
	s_checkFramebufferStatus = (CheckFramebufferStatusFn)(void *)wglGetProcAddress("glCheckFramebufferStatus");
	s_deleteFramebuffers = (DeleteFramebuffersFn)(void *)wglGetProcAddress("glDeleteFramebuffers");
	if (!s_genFramebuffers || !s_bindFramebuffer || !s_framebufferTexture2D || !s_checkFramebufferStatus || !s_deleteFramebuffers) {
		return fail("the GL context lacks the framebuffer functions the readback needs");
	}
	return 1;
}

const char *glWindowError(void) { return s_error; }

int32_t glWindowReadback(void *texture, void *pixels, int32_t width, int32_t height) {
	GLuint framebuffer = 0;
	s_genFramebuffers(1, &framebuffer);
	s_bindFramebuffer(GL_READ_FRAMEBUFFER_ID, framebuffer);
	s_framebufferTexture2D(GL_READ_FRAMEBUFFER_ID, GL_COLOR_ATTACHMENT0_ID, GL_TEXTURE_2D, (GLuint)(uintptr_t)texture, 0);
	int32_t complete = s_checkFramebufferStatus(GL_READ_FRAMEBUFFER_ID) == GL_FRAMEBUFFER_COMPLETE_ID;
	if (complete) {
		glPixelStorei(GL_PACK_ALIGNMENT, 1);
		glReadPixels(0, 0, width, height, GL_RGBA, GL_UNSIGNED_BYTE, pixels);
	}
	s_bindFramebuffer(GL_READ_FRAMEBUFFER_ID, 0);
	s_deleteFramebuffers(1, &framebuffer);
	return complete && glGetError() == GL_NO_ERROR;
}

void glWindowClose(void) {
	if (s_context) {
		wglMakeCurrent(NULL, NULL);
		wglDeleteContext(s_context);
	}
	if (s_dc) ReleaseDC(s_window, s_dc);
	if (s_window) DestroyWindow(s_window);
	s_context = NULL;
	s_dc = NULL;
	s_window = NULL;
}
