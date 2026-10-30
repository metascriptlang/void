#include "vulkanSwapchainHost.h"

#include <stdio.h>
#include "../../src/webgpu/vulkan/vulkan.h"

void *vulkanHostView(uint64_t view) { return (void *)(uintptr_t)view; }

#if defined(__linux__) && !defined(__ANDROID__)
#include <dlfcn.h>

#define MAP_NOTIFY 19
#define CONFIGURE_NOTIFY 22
#define STRUCTURE_NOTIFY_MASK (1L << 17)

typedef struct {
	void *library;
	void *display;
	unsigned long windows[VULKAN_HOST_WINDOWS];
	void *(*openDisplay)(const char *);
	int (*defaultScreen)(void *);
	unsigned long (*rootWindow)(void *, int);
	unsigned long (*createSimpleWindow)(void *, unsigned long, int, int, unsigned, unsigned, unsigned, unsigned long, unsigned long);
	int (*selectInput)(void *, unsigned long, long);
	int (*mapWindow)(void *, unsigned long);
	int (*resizeWindow)(void *, unsigned long, unsigned, unsigned);
	int (*nextEvent)(void *, void *);
	int (*sync)(void *, int);
	int (*destroyWindow)(void *, unsigned long);
	int (*closeDisplay)(void *);
} Host;

static Host s_host;

static int32_t waitFor(int type) {
	long event[24];
	for (int i = 0; i < 64; i++) {
		s_host.nextEvent(s_host.display, event);
		if (*(int *)event == type) return 0;
	}
	fprintf(stderr, "vulkan swapchain host: no X event of type %d in 64 events\n", type);
	return 1;
}

static int32_t hostWindowIndex(uint32_t index) {
	if (index < VULKAN_HOST_WINDOWS) return 0;
	fprintf(stderr, "vulkan swapchain host: window %u is not below %d\n", index, VULKAN_HOST_WINDOWS);
	return 1;
}

static int32_t displayOpen(void) {
	if (s_host.display != NULL) return 0;
	s_host.library = dlopen("libX11.so.6", RTLD_NOW);
	if (s_host.library == NULL) {
		fprintf(stderr, "vulkan swapchain host: dlopen libX11.so.6: %s\n", dlerror());
		return 1;
	}
	*(void **)&s_host.openDisplay = dlsym(s_host.library, "XOpenDisplay");
	*(void **)&s_host.defaultScreen = dlsym(s_host.library, "XDefaultScreen");
	*(void **)&s_host.rootWindow = dlsym(s_host.library, "XRootWindow");
	*(void **)&s_host.createSimpleWindow = dlsym(s_host.library, "XCreateSimpleWindow");
	*(void **)&s_host.selectInput = dlsym(s_host.library, "XSelectInput");
	*(void **)&s_host.mapWindow = dlsym(s_host.library, "XMapWindow");
	*(void **)&s_host.resizeWindow = dlsym(s_host.library, "XResizeWindow");
	*(void **)&s_host.nextEvent = dlsym(s_host.library, "XNextEvent");
	*(void **)&s_host.sync = dlsym(s_host.library, "XSync");
	*(void **)&s_host.destroyWindow = dlsym(s_host.library, "XDestroyWindow");
	*(void **)&s_host.closeDisplay = dlsym(s_host.library, "XCloseDisplay");
	if (s_host.openDisplay == NULL || s_host.closeDisplay == NULL || s_host.nextEvent == NULL) {
		fprintf(stderr, "vulkan swapchain host: libX11.so.6 lacks an Xlib entry point\n");
		return 1;
	}
	s_host.display = s_host.openDisplay(NULL);
	if (s_host.display == NULL) {
		fprintf(stderr, "vulkan swapchain host: XOpenDisplay found no display (is DISPLAY set?)\n");
		return 1;
	}
	return 0;
}

int32_t vulkanHostWindowOpen(uint32_t index, uint32_t width, uint32_t height, uint64_t *surface) {
	if (hostWindowIndex(index) != 0 || displayOpen() != 0) return 1;
	unsigned long root = s_host.rootWindow(s_host.display, s_host.defaultScreen(s_host.display));
	s_host.windows[index] = s_host.createSimpleWindow(s_host.display, root, 0, 0, width, height, 0, 0, 0);
	s_host.selectInput(s_host.display, s_host.windows[index], STRUCTURE_NOTIFY_MASK);
	s_host.mapWindow(s_host.display, s_host.windows[index]);
	if (waitFor(MAP_NOTIFY) != 0) return 1;
	return vulkanSurfaceCreateXlib(s_host.display, s_host.windows[index], surface);
}

int32_t vulkanHostWindowResize(uint32_t index, uint32_t width, uint32_t height) {
	if (hostWindowIndex(index) != 0) return 1;
	s_host.resizeWindow(s_host.display, s_host.windows[index], width, height);
	s_host.sync(s_host.display, 0);
	return waitFor(CONFIGURE_NOTIFY);
}

void vulkanHostWindowClose(void) {
	if (s_host.display != NULL) {
		for (int i = 0; i < VULKAN_HOST_WINDOWS; i++) {
			if (s_host.windows[i] != 0) s_host.destroyWindow(s_host.display, s_host.windows[i]);
		}
		s_host.closeDisplay(s_host.display);
	}
	if (s_host.library != NULL) dlclose(s_host.library);
	s_host = (Host){ 0 };
}

#elif defined(_WIN32)
#include <windows.h>

static HWND s_windows[VULKAN_HOST_WINDOWS];

static void pump(void) {
	MSG message;
	while (PeekMessageA(&message, NULL, 0, 0, PM_REMOVE)) {
		TranslateMessage(&message);
		DispatchMessageA(&message);
	}
}

static int32_t sizeClient(HWND window, uint32_t width, uint32_t height) {
	RECT frame = { 0, 0, (LONG)width, (LONG)height };
	AdjustWindowRect(&frame, WS_POPUP, FALSE);
	if (!SetWindowPos(window, NULL, 0, 0, frame.right - frame.left, frame.bottom - frame.top,
			SWP_NOMOVE | SWP_NOZORDER | SWP_NOACTIVATE)) {
		fprintf(stderr, "vulkan swapchain host: SetWindowPos failed: %lu\n", GetLastError());
		return 1;
	}
	pump();
	RECT client;
	GetClientRect(window, &client);
	if ((uint32_t)client.right != width || (uint32_t)client.bottom != height) {
		fprintf(stderr, "vulkan swapchain host: the client area is %ldx%ld, not %ux%u\n",
			client.right, client.bottom, width, height);
		return 1;
	}
	return 0;
}

static int32_t hostWindowIndex(uint32_t index) {
	if (index < VULKAN_HOST_WINDOWS) return 0;
	fprintf(stderr, "vulkan swapchain host: window %u is not below %d\n", index, VULKAN_HOST_WINDOWS);
	return 1;
}

int32_t vulkanHostWindowOpen(uint32_t index, uint32_t width, uint32_t height, uint64_t *surface) {
	if (hostWindowIndex(index) != 0) return 1;
	HINSTANCE instance = GetModuleHandleA(NULL);
	WNDCLASSA windowClass = { 0 };
	windowClass.lpfnWndProc = DefWindowProcA;
	windowClass.hInstance = instance;
	windowClass.lpszClassName = "VoidVulkanSwapchainHost";
	if (RegisterClassA(&windowClass) == 0 && GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
		fprintf(stderr, "vulkan swapchain host: RegisterClassA failed: %lu\n", GetLastError());
		return 1;
	}
	HWND window = CreateWindowA(windowClass.lpszClassName, "void vulkan swapchain", WS_POPUP,
		CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, CW_USEDEFAULT, NULL, NULL, instance, NULL);
	if (window == NULL) {
		fprintf(stderr, "vulkan swapchain host: CreateWindowA failed: %lu\n", GetLastError());
		return 1;
	}
	s_windows[index] = window;
	ShowWindow(window, SW_SHOWNOACTIVATE);
	if (sizeClient(window, width, height) != 0) return 1;
	return vulkanSurfaceCreateWin32(instance, window, surface);
}

int32_t vulkanHostWindowResize(uint32_t index, uint32_t width, uint32_t height) {
	if (hostWindowIndex(index) != 0) return 1;
	return sizeClient(s_windows[index], width, height);
}

void vulkanHostWindowClose(void) {
	for (int i = 0; i < VULKAN_HOST_WINDOWS; i++) {
		if (s_windows[i] != NULL) DestroyWindow(s_windows[i]);
		s_windows[i] = NULL;
	}
	pump();
}

#else

int32_t vulkanHostWindowOpen(uint32_t index, uint32_t width, uint32_t height, uint64_t *surface) {
	(void)index;
	(void)width;
	(void)height;
	*surface = 0;
	fprintf(stderr, "vulkan swapchain host: no test window on this platform\n");
	return 1;
}

int32_t vulkanHostWindowResize(uint32_t index, uint32_t width, uint32_t height) {
	(void)index;
	(void)width;
	(void)height;
	return 1;
}

void vulkanHostWindowClose(void) {}

#endif
