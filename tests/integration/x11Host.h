// A stand-in for Ion's Linux host in tests/integration/linuxViews.ms: a top-level X11 window with
// one child area per view, read back from the X server as the screen shows it.
#ifndef VOID_TEST_X11_HOST_H
#define VOID_TEST_X11_HOST_H

#include <stdint.h>

int64_t x11HostOpen(int32_t width, int32_t height);
int64_t x11HostArea(int32_t x, int32_t y, int32_t width, int32_t height);
void x11HostResizeArea(int64_t area, int32_t width, int32_t height);
// 0xRRGGBB of the pixel at (x, y) of `window` as the X server holds it; -1 when it cannot be read.
int64_t x11HostPixel(int64_t window, int32_t x, int32_t y);

#endif
