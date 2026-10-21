// sokol_app implementation unit — Windows. sokol_app owns the window, its events and DPI;
// the device and swapchain are Void's (bridgeWin.c, windowGl.c), so this unit builds on
// sokol_app's no-API backend whichever backend sokol_gfx uses.
#undef SOKOL_D3D11
#undef SOKOL_GLCORE
#define SOKOL_NOAPI
#define SOKOL_IMPL
#define SOKOL_NO_ENTRY
#include "sokol_app.h"
