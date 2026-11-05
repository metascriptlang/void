#include "x11Host.h"

#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <stdio.h>
#include <stdlib.h>

static Display *s_display;
static Window s_top;

static void waitMapped(Window w) {
	XEvent e;
	do { XWindowEvent(s_display, w, StructureNotifyMask, &e); } while (e.type != MapNotify);
}

int64_t x11HostOpen(int32_t width, int32_t height) {
	s_display = XOpenDisplay(NULL);
	if (s_display == NULL) {
		fprintf(stderr, "x11Host: XOpenDisplay failed; DISPLAY must name an X server\n");
		exit(1);
	}
	const int screen = DefaultScreen(s_display);
	s_top = XCreateSimpleWindow(s_display, RootWindow(s_display, screen), 0, 0, (unsigned)width, (unsigned)height, 0, 0,
		BlackPixel(s_display, screen));
	XSelectInput(s_display, s_top, StructureNotifyMask);
	XMapWindow(s_display, s_top);
	waitMapped(s_top);
	return (int64_t)s_top;
}

int64_t x11HostArea(int32_t x, int32_t y, int32_t width, int32_t height) {
	const int screen = DefaultScreen(s_display);
	Window area = XCreateSimpleWindow(s_display, s_top, x, y, (unsigned)width, (unsigned)height, 0, 0, WhitePixel(s_display, screen));
	XSelectInput(s_display, area, StructureNotifyMask);
	XMapWindow(s_display, area);
	waitMapped(area);
	return (int64_t)area;
}

void x11HostResizeArea(int64_t area, int32_t width, int32_t height) {
	XResizeWindow(s_display, (Window)area, (unsigned)width, (unsigned)height);
	XSync(s_display, False);
}

static int shiftOf(unsigned long mask) {
	int shift = 0;
	while (mask && !(mask & 1)) {
		mask >>= 1;
		shift++;
	}
	return shift;
}

int64_t x11HostPixel(int64_t window, int32_t x, int32_t y) {
	XSync(s_display, False);
	XImage *image = XGetImage(s_display, (Window)window, x, y, 1, 1, AllPlanes, ZPixmap);
	if (image == NULL) return -1;
	const unsigned long p = XGetPixel(image, 0, 0);
	const int64_t r = (int64_t)((p & image->red_mask) >> shiftOf(image->red_mask)) & 0xFF;
	const int64_t g = (int64_t)((p & image->green_mask) >> shiftOf(image->green_mask)) & 0xFF;
	const int64_t b = (int64_t)((p & image->blue_mask) >> shiftOf(image->blue_mask)) & 0xFF;
	XDestroyImage(image);
	return (r << 16) | (g << 8) | b;
}
