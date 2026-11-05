#include "winWindowSize.h"
#include "../../src/platform/win32/window.h"
#include <math.h>
#include <stdio.h>
#include <stdlib.h>

static int requestedWidth;
static int requestedHeight;
static int failures;
static bool highDpi;
static int frames;

static void checkSize(void) {
	RECT client;
	HWND window = voidWin32Hwnd();
	if (!GetClientRect(window, &client)) {
		fprintf(stderr, "FAIL Win32 GetClientRect: %lu\n", GetLastError());
		failures++;
		return;
	}
	const float scale = highDpi ? (float)GetDpiForWindow(window) / 96.0f : 1.0f;
	const int width = client.right - client.left;
	const int height = client.bottom - client.top;
	const int expectedWidth = (int)((float)requestedWidth * scale);
	const int expectedHeight = (int)((float)requestedHeight * scale);
	const bool explicitSize = requestedWidth > 0 && requestedHeight > 0;
	const bool fits = !explicitSize || (width == expectedWidth && height == expectedHeight);
	const bool framebufferFits = voidWindowWidth() == width && voidWindowHeight() == height;
	printf("%s Win32 highDpi=%d frame=%d request=%dx%d client=%dx%d framebuffer=%dx%d dpi=%.0f maxTrack=%dx%d\n",
		fits && framebufferFits ? "PASS" : "FAIL", highDpi, frames, requestedWidth, requestedHeight,
		width, height, voidWindowWidth(), voidWindowHeight(), scale * 96.0f,
		GetSystemMetrics(SM_CXMAXTRACK), GetSystemMetrics(SM_CYMAXTRACK));
	if (!fits || !framebufferFits || width <= 0 || height <= 0) failures++;
}

static void frame(void) {
	checkSize();
	if (++frames == 2) voidWindowRequestQuit();
}

int voidWinWindowSizeCheck(void) {
	const char *mode = getenv("VOID_WINDOW_HIGH_DPI");
	highDpi = mode == NULL || mode[0] != '0';
	const int sizes[][2] = {
		{ 640, 360 },
		{ 1920, 1080 },
		{ GetSystemMetrics(SM_CXSCREEN) + 200, GetSystemMetrics(SM_CYSCREEN) + 200 },
		{ 0, 0 },
	};
	for (int i = 0; i < 4; i++) {
		requestedWidth = sizes[i][0];
		requestedHeight = sizes[i][1];
		frames = 0;
		VoidWin32Desc desc = {
			.frame = frame,
			.width = requestedWidth,
			.height = requestedHeight,
			.highDpi = highDpi,
			.title = "Void Win32 client-size regression",
		};
		voidWin32Run(&desc);
	}
	printf("Win32 client-size: %d failure(s)\n", failures);
	return failures;
}
