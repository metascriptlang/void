#include "window.h"

#include <X11/Xlib.h>
#include <X11/Xutil.h>
#include <X11/XKBlib.h>
#include <X11/keysym.h>
#include <X11/Xresource.h>
#include <X11/Xmd.h>
#include <X11/Xatom.h>
#include <X11/cursorfont.h>
#include <X11/Xcursor/Xcursor.h>
#include <X11/extensions/XInput2.h>
#include <dlfcn.h>
#include <limits.h>
#include <math.h>
#include <poll.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "../clock.h"
#include "../frameTiming.h"

#define X11_KEYCODES 256
#define XDND_VERSION 5

#define GLX_VENDOR 1
#define GLX_RGBA_BIT 0x00000001
#define GLX_WINDOW_BIT 0x00000001
#define GLX_DRAWABLE_TYPE 0x8010
#define GLX_RENDER_TYPE 0x8011
#define GLX_DOUBLEBUFFER 5
#define GLX_RED_SIZE 8
#define GLX_GREEN_SIZE 9
#define GLX_BLUE_SIZE 10
#define GLX_ALPHA_SIZE 11
#define GLX_DEPTH_SIZE 12
#define GLX_STENCIL_SIZE 13
#define GLX_SAMPLES 0x186a1
#define GLX_FRAMEBUFFER_SRGB_CAPABLE_ARB 0x20B2
#define GLX_CONTEXT_CORE_PROFILE_BIT_ARB 0x00000001
#define GLX_CONTEXT_PROFILE_MASK_ARB 0x9126
#define GLX_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB 0x00000002
#define GLX_CONTEXT_MAJOR_VERSION_ARB 0x2091
#define GLX_CONTEXT_MINOR_VERSION_ARB 0x2092
#define GLX_CONTEXT_FLAGS_ARB 0x2094

typedef XID GLXWindow;
typedef XID GLXDrawable;
typedef struct __GLXFBConfig *GLXFBConfig;
typedef struct __GLXcontext *GLXContext;
typedef void (*GlxExtProc)(void);

typedef int (*GlxGetFBConfigAttribFn)(Display *, GLXFBConfig, int, int *);
typedef const char *(*GlxGetClientStringFn)(Display *, int);
typedef Bool (*GlxQueryExtensionFn)(Display *, int *, int *);
typedef Bool (*GlxQueryVersionFn)(Display *, int *, int *);
typedef void (*GlxDestroyContextFn)(Display *, GLXContext);
typedef Bool (*GlxMakeCurrentFn)(Display *, GLXDrawable, GLXContext);
typedef void (*GlxSwapBuffersFn)(Display *, GLXDrawable);
typedef const char *(*GlxQueryExtensionsStringFn)(Display *, int);
typedef GLXFBConfig *(*GlxGetFBConfigsFn)(Display *, int, int *);
typedef GlxExtProc (*GlxGetProcAddressFn)(const char *);
typedef void (*GlxSwapIntervalExtFn)(Display *, GLXDrawable, int);
typedef int (*GlxSwapIntervalMesaFn)(int);
typedef XVisualInfo *(*GlxGetVisualFromFBConfigFn)(Display *, GLXFBConfig);
typedef GLXWindow (*GlxCreateWindowFn)(Display *, GLXFBConfig, Window, const int *);
typedef void (*GlxDestroyWindowFn)(Display *, GLXWindow);
typedef GLXContext (*GlxCreateContextAttribsFn)(Display *, GLXFBConfig, GLXContext, Bool, const int *);

typedef char *(*XcursorGetThemeFn)(Display *);
typedef int (*XcursorGetDefaultSizeFn)(Display *);
typedef XcursorImage *(*XcursorLibraryLoadImageFn)(const char *, const char *, int);
typedef Cursor (*XcursorImageLoadCursorFn)(Display *, const XcursorImage *);
typedef void (*XcursorImageDestroyFn)(XcursorImage *);
typedef Status (*XiQueryVersionFn)(Display *, int *, int *);
typedef int (*XiSelectEventsFn)(Display *, Window, XIEventMask *, int);

static const struct {
	uint16_t keysym;
	uint16_t ucs;
} keysymTable[] = {
	{ 0x01a1, 0x0104 },
	{ 0x01a2, 0x02d8 },
	{ 0x01a3, 0x0141 },
	{ 0x01a5, 0x013d },
	{ 0x01a6, 0x015a },
	{ 0x01a9, 0x0160 },
	{ 0x01aa, 0x015e },
	{ 0x01ab, 0x0164 },
	{ 0x01ac, 0x0179 },
	{ 0x01ae, 0x017d },
	{ 0x01af, 0x017b },
	{ 0x01b1, 0x0105 },
	{ 0x01b2, 0x02db },
	{ 0x01b3, 0x0142 },
	{ 0x01b5, 0x013e },
	{ 0x01b6, 0x015b },
	{ 0x01b7, 0x02c7 },
	{ 0x01b9, 0x0161 },
	{ 0x01ba, 0x015f },
	{ 0x01bb, 0x0165 },
	{ 0x01bc, 0x017a },
	{ 0x01bd, 0x02dd },
	{ 0x01be, 0x017e },
	{ 0x01bf, 0x017c },
	{ 0x01c0, 0x0154 },
	{ 0x01c3, 0x0102 },
	{ 0x01c5, 0x0139 },
	{ 0x01c6, 0x0106 },
	{ 0x01c8, 0x010c },
	{ 0x01ca, 0x0118 },
	{ 0x01cc, 0x011a },
	{ 0x01cf, 0x010e },
	{ 0x01d0, 0x0110 },
	{ 0x01d1, 0x0143 },
	{ 0x01d2, 0x0147 },
	{ 0x01d5, 0x0150 },
	{ 0x01d8, 0x0158 },
	{ 0x01d9, 0x016e },
	{ 0x01db, 0x0170 },
	{ 0x01de, 0x0162 },
	{ 0x01e0, 0x0155 },
	{ 0x01e3, 0x0103 },
	{ 0x01e5, 0x013a },
	{ 0x01e6, 0x0107 },
	{ 0x01e8, 0x010d },
	{ 0x01ea, 0x0119 },
	{ 0x01ec, 0x011b },
	{ 0x01ef, 0x010f },
	{ 0x01f0, 0x0111 },
	{ 0x01f1, 0x0144 },
	{ 0x01f2, 0x0148 },
	{ 0x01f5, 0x0151 },
	{ 0x01f8, 0x0159 },
	{ 0x01f9, 0x016f },
	{ 0x01fb, 0x0171 },
	{ 0x01fe, 0x0163 },
	{ 0x01ff, 0x02d9 },
	{ 0x02a1, 0x0126 },
	{ 0x02a6, 0x0124 },
	{ 0x02a9, 0x0130 },
	{ 0x02ab, 0x011e },
	{ 0x02ac, 0x0134 },
	{ 0x02b1, 0x0127 },
	{ 0x02b6, 0x0125 },
	{ 0x02b9, 0x0131 },
	{ 0x02bb, 0x011f },
	{ 0x02bc, 0x0135 },
	{ 0x02c5, 0x010a },
	{ 0x02c6, 0x0108 },
	{ 0x02d5, 0x0120 },
	{ 0x02d8, 0x011c },
	{ 0x02dd, 0x016c },
	{ 0x02de, 0x015c },
	{ 0x02e5, 0x010b },
	{ 0x02e6, 0x0109 },
	{ 0x02f5, 0x0121 },
	{ 0x02f8, 0x011d },
	{ 0x02fd, 0x016d },
	{ 0x02fe, 0x015d },
	{ 0x03a2, 0x0138 },
	{ 0x03a3, 0x0156 },
	{ 0x03a5, 0x0128 },
	{ 0x03a6, 0x013b },
	{ 0x03aa, 0x0112 },
	{ 0x03ab, 0x0122 },
	{ 0x03ac, 0x0166 },
	{ 0x03b3, 0x0157 },
	{ 0x03b5, 0x0129 },
	{ 0x03b6, 0x013c },
	{ 0x03ba, 0x0113 },
	{ 0x03bb, 0x0123 },
	{ 0x03bc, 0x0167 },
	{ 0x03bd, 0x014a },
	{ 0x03bf, 0x014b },
	{ 0x03c0, 0x0100 },
	{ 0x03c7, 0x012e },
	{ 0x03cc, 0x0116 },
	{ 0x03cf, 0x012a },
	{ 0x03d1, 0x0145 },
	{ 0x03d2, 0x014c },
	{ 0x03d3, 0x0136 },
	{ 0x03d9, 0x0172 },
	{ 0x03dd, 0x0168 },
	{ 0x03de, 0x016a },
	{ 0x03e0, 0x0101 },
	{ 0x03e7, 0x012f },
	{ 0x03ec, 0x0117 },
	{ 0x03ef, 0x012b },
	{ 0x03f1, 0x0146 },
	{ 0x03f2, 0x014d },
	{ 0x03f3, 0x0137 },
	{ 0x03f9, 0x0173 },
	{ 0x03fd, 0x0169 },
	{ 0x03fe, 0x016b },
	{ 0x047e, 0x203e },
	{ 0x04a1, 0x3002 },
	{ 0x04a2, 0x300c },
	{ 0x04a3, 0x300d },
	{ 0x04a4, 0x3001 },
	{ 0x04a5, 0x30fb },
	{ 0x04a6, 0x30f2 },
	{ 0x04a7, 0x30a1 },
	{ 0x04a8, 0x30a3 },
	{ 0x04a9, 0x30a5 },
	{ 0x04aa, 0x30a7 },
	{ 0x04ab, 0x30a9 },
	{ 0x04ac, 0x30e3 },
	{ 0x04ad, 0x30e5 },
	{ 0x04ae, 0x30e7 },
	{ 0x04af, 0x30c3 },
	{ 0x04b0, 0x30fc },
	{ 0x04b1, 0x30a2 },
	{ 0x04b2, 0x30a4 },
	{ 0x04b3, 0x30a6 },
	{ 0x04b4, 0x30a8 },
	{ 0x04b5, 0x30aa },
	{ 0x04b6, 0x30ab },
	{ 0x04b7, 0x30ad },
	{ 0x04b8, 0x30af },
	{ 0x04b9, 0x30b1 },
	{ 0x04ba, 0x30b3 },
	{ 0x04bb, 0x30b5 },
	{ 0x04bc, 0x30b7 },
	{ 0x04bd, 0x30b9 },
	{ 0x04be, 0x30bb },
	{ 0x04bf, 0x30bd },
	{ 0x04c0, 0x30bf },
	{ 0x04c1, 0x30c1 },
	{ 0x04c2, 0x30c4 },
	{ 0x04c3, 0x30c6 },
	{ 0x04c4, 0x30c8 },
	{ 0x04c5, 0x30ca },
	{ 0x04c6, 0x30cb },
	{ 0x04c7, 0x30cc },
	{ 0x04c8, 0x30cd },
	{ 0x04c9, 0x30ce },
	{ 0x04ca, 0x30cf },
	{ 0x04cb, 0x30d2 },
	{ 0x04cc, 0x30d5 },
	{ 0x04cd, 0x30d8 },
	{ 0x04ce, 0x30db },
	{ 0x04cf, 0x30de },
	{ 0x04d0, 0x30df },
	{ 0x04d1, 0x30e0 },
	{ 0x04d2, 0x30e1 },
	{ 0x04d3, 0x30e2 },
	{ 0x04d4, 0x30e4 },
	{ 0x04d5, 0x30e6 },
	{ 0x04d6, 0x30e8 },
	{ 0x04d7, 0x30e9 },
	{ 0x04d8, 0x30ea },
	{ 0x04d9, 0x30eb },
	{ 0x04da, 0x30ec },
	{ 0x04db, 0x30ed },
	{ 0x04dc, 0x30ef },
	{ 0x04dd, 0x30f3 },
	{ 0x04de, 0x309b },
	{ 0x04df, 0x309c },
	{ 0x05ac, 0x060c },
	{ 0x05bb, 0x061b },
	{ 0x05bf, 0x061f },
	{ 0x05c1, 0x0621 },
	{ 0x05c2, 0x0622 },
	{ 0x05c3, 0x0623 },
	{ 0x05c4, 0x0624 },
	{ 0x05c5, 0x0625 },
	{ 0x05c6, 0x0626 },
	{ 0x05c7, 0x0627 },
	{ 0x05c8, 0x0628 },
	{ 0x05c9, 0x0629 },
	{ 0x05ca, 0x062a },
	{ 0x05cb, 0x062b },
	{ 0x05cc, 0x062c },
	{ 0x05cd, 0x062d },
	{ 0x05ce, 0x062e },
	{ 0x05cf, 0x062f },
	{ 0x05d0, 0x0630 },
	{ 0x05d1, 0x0631 },
	{ 0x05d2, 0x0632 },
	{ 0x05d3, 0x0633 },
	{ 0x05d4, 0x0634 },
	{ 0x05d5, 0x0635 },
	{ 0x05d6, 0x0636 },
	{ 0x05d7, 0x0637 },
	{ 0x05d8, 0x0638 },
	{ 0x05d9, 0x0639 },
	{ 0x05da, 0x063a },
	{ 0x05e0, 0x0640 },
	{ 0x05e1, 0x0641 },
	{ 0x05e2, 0x0642 },
	{ 0x05e3, 0x0643 },
	{ 0x05e4, 0x0644 },
	{ 0x05e5, 0x0645 },
	{ 0x05e6, 0x0646 },
	{ 0x05e7, 0x0647 },
	{ 0x05e8, 0x0648 },
	{ 0x05e9, 0x0649 },
	{ 0x05ea, 0x064a },
	{ 0x05eb, 0x064b },
	{ 0x05ec, 0x064c },
	{ 0x05ed, 0x064d },
	{ 0x05ee, 0x064e },
	{ 0x05ef, 0x064f },
	{ 0x05f0, 0x0650 },
	{ 0x05f1, 0x0651 },
	{ 0x05f2, 0x0652 },
	{ 0x06a1, 0x0452 },
	{ 0x06a2, 0x0453 },
	{ 0x06a3, 0x0451 },
	{ 0x06a4, 0x0454 },
	{ 0x06a5, 0x0455 },
	{ 0x06a6, 0x0456 },
	{ 0x06a7, 0x0457 },
	{ 0x06a8, 0x0458 },
	{ 0x06a9, 0x0459 },
	{ 0x06aa, 0x045a },
	{ 0x06ab, 0x045b },
	{ 0x06ac, 0x045c },
	{ 0x06ae, 0x045e },
	{ 0x06af, 0x045f },
	{ 0x06b0, 0x2116 },
	{ 0x06b1, 0x0402 },
	{ 0x06b2, 0x0403 },
	{ 0x06b3, 0x0401 },
	{ 0x06b4, 0x0404 },
	{ 0x06b5, 0x0405 },
	{ 0x06b6, 0x0406 },
	{ 0x06b7, 0x0407 },
	{ 0x06b8, 0x0408 },
	{ 0x06b9, 0x0409 },
	{ 0x06ba, 0x040a },
	{ 0x06bb, 0x040b },
	{ 0x06bc, 0x040c },
	{ 0x06be, 0x040e },
	{ 0x06bf, 0x040f },
	{ 0x06c0, 0x044e },
	{ 0x06c1, 0x0430 },
	{ 0x06c2, 0x0431 },
	{ 0x06c3, 0x0446 },
	{ 0x06c4, 0x0434 },
	{ 0x06c5, 0x0435 },
	{ 0x06c6, 0x0444 },
	{ 0x06c7, 0x0433 },
	{ 0x06c8, 0x0445 },
	{ 0x06c9, 0x0438 },
	{ 0x06ca, 0x0439 },
	{ 0x06cb, 0x043a },
	{ 0x06cc, 0x043b },
	{ 0x06cd, 0x043c },
	{ 0x06ce, 0x043d },
	{ 0x06cf, 0x043e },
	{ 0x06d0, 0x043f },
	{ 0x06d1, 0x044f },
	{ 0x06d2, 0x0440 },
	{ 0x06d3, 0x0441 },
	{ 0x06d4, 0x0442 },
	{ 0x06d5, 0x0443 },
	{ 0x06d6, 0x0436 },
	{ 0x06d7, 0x0432 },
	{ 0x06d8, 0x044c },
	{ 0x06d9, 0x044b },
	{ 0x06da, 0x0437 },
	{ 0x06db, 0x0448 },
	{ 0x06dc, 0x044d },
	{ 0x06dd, 0x0449 },
	{ 0x06de, 0x0447 },
	{ 0x06df, 0x044a },
	{ 0x06e0, 0x042e },
	{ 0x06e1, 0x0410 },
	{ 0x06e2, 0x0411 },
	{ 0x06e3, 0x0426 },
	{ 0x06e4, 0x0414 },
	{ 0x06e5, 0x0415 },
	{ 0x06e6, 0x0424 },
	{ 0x06e7, 0x0413 },
	{ 0x06e8, 0x0425 },
	{ 0x06e9, 0x0418 },
	{ 0x06ea, 0x0419 },
	{ 0x06eb, 0x041a },
	{ 0x06ec, 0x041b },
	{ 0x06ed, 0x041c },
	{ 0x06ee, 0x041d },
	{ 0x06ef, 0x041e },
	{ 0x06f0, 0x041f },
	{ 0x06f1, 0x042f },
	{ 0x06f2, 0x0420 },
	{ 0x06f3, 0x0421 },
	{ 0x06f4, 0x0422 },
	{ 0x06f5, 0x0423 },
	{ 0x06f6, 0x0416 },
	{ 0x06f7, 0x0412 },
	{ 0x06f8, 0x042c },
	{ 0x06f9, 0x042b },
	{ 0x06fa, 0x0417 },
	{ 0x06fb, 0x0428 },
	{ 0x06fc, 0x042d },
	{ 0x06fd, 0x0429 },
	{ 0x06fe, 0x0427 },
	{ 0x06ff, 0x042a },
	{ 0x07a1, 0x0386 },
	{ 0x07a2, 0x0388 },
	{ 0x07a3, 0x0389 },
	{ 0x07a4, 0x038a },
	{ 0x07a5, 0x03aa },
	{ 0x07a7, 0x038c },
	{ 0x07a8, 0x038e },
	{ 0x07a9, 0x03ab },
	{ 0x07ab, 0x038f },
	{ 0x07ae, 0x0385 },
	{ 0x07af, 0x2015 },
	{ 0x07b1, 0x03ac },
	{ 0x07b2, 0x03ad },
	{ 0x07b3, 0x03ae },
	{ 0x07b4, 0x03af },
	{ 0x07b5, 0x03ca },
	{ 0x07b6, 0x0390 },
	{ 0x07b7, 0x03cc },
	{ 0x07b8, 0x03cd },
	{ 0x07b9, 0x03cb },
	{ 0x07ba, 0x03b0 },
	{ 0x07bb, 0x03ce },
	{ 0x07c1, 0x0391 },
	{ 0x07c2, 0x0392 },
	{ 0x07c3, 0x0393 },
	{ 0x07c4, 0x0394 },
	{ 0x07c5, 0x0395 },
	{ 0x07c6, 0x0396 },
	{ 0x07c7, 0x0397 },
	{ 0x07c8, 0x0398 },
	{ 0x07c9, 0x0399 },
	{ 0x07ca, 0x039a },
	{ 0x07cb, 0x039b },
	{ 0x07cc, 0x039c },
	{ 0x07cd, 0x039d },
	{ 0x07ce, 0x039e },
	{ 0x07cf, 0x039f },
	{ 0x07d0, 0x03a0 },
	{ 0x07d1, 0x03a1 },
	{ 0x07d2, 0x03a3 },
	{ 0x07d4, 0x03a4 },
	{ 0x07d5, 0x03a5 },
	{ 0x07d6, 0x03a6 },
	{ 0x07d7, 0x03a7 },
	{ 0x07d8, 0x03a8 },
	{ 0x07d9, 0x03a9 },
	{ 0x07e1, 0x03b1 },
	{ 0x07e2, 0x03b2 },
	{ 0x07e3, 0x03b3 },
	{ 0x07e4, 0x03b4 },
	{ 0x07e5, 0x03b5 },
	{ 0x07e6, 0x03b6 },
	{ 0x07e7, 0x03b7 },
	{ 0x07e8, 0x03b8 },
	{ 0x07e9, 0x03b9 },
	{ 0x07ea, 0x03ba },
	{ 0x07eb, 0x03bb },
	{ 0x07ec, 0x03bc },
	{ 0x07ed, 0x03bd },
	{ 0x07ee, 0x03be },
	{ 0x07ef, 0x03bf },
	{ 0x07f0, 0x03c0 },
	{ 0x07f1, 0x03c1 },
	{ 0x07f2, 0x03c3 },
	{ 0x07f3, 0x03c2 },
	{ 0x07f4, 0x03c4 },
	{ 0x07f5, 0x03c5 },
	{ 0x07f6, 0x03c6 },
	{ 0x07f7, 0x03c7 },
	{ 0x07f8, 0x03c8 },
	{ 0x07f9, 0x03c9 },
	{ 0x08a1, 0x23b7 },
	{ 0x08a2, 0x250c },
	{ 0x08a3, 0x2500 },
	{ 0x08a4, 0x2320 },
	{ 0x08a5, 0x2321 },
	{ 0x08a6, 0x2502 },
	{ 0x08a7, 0x23a1 },
	{ 0x08a8, 0x23a3 },
	{ 0x08a9, 0x23a4 },
	{ 0x08aa, 0x23a6 },
	{ 0x08ab, 0x239b },
	{ 0x08ac, 0x239d },
	{ 0x08ad, 0x239e },
	{ 0x08ae, 0x23a0 },
	{ 0x08af, 0x23a8 },
	{ 0x08b0, 0x23ac },
	{ 0x08bc, 0x2264 },
	{ 0x08bd, 0x2260 },
	{ 0x08be, 0x2265 },
	{ 0x08bf, 0x222b },
	{ 0x08c0, 0x2234 },
	{ 0x08c1, 0x221d },
	{ 0x08c2, 0x221e },
	{ 0x08c5, 0x2207 },
	{ 0x08c8, 0x223c },
	{ 0x08c9, 0x2243 },
	{ 0x08cd, 0x21d4 },
	{ 0x08ce, 0x21d2 },
	{ 0x08cf, 0x2261 },
	{ 0x08d6, 0x221a },
	{ 0x08da, 0x2282 },
	{ 0x08db, 0x2283 },
	{ 0x08dc, 0x2229 },
	{ 0x08dd, 0x222a },
	{ 0x08de, 0x2227 },
	{ 0x08df, 0x2228 },
	{ 0x08ef, 0x2202 },
	{ 0x08f6, 0x0192 },
	{ 0x08fb, 0x2190 },
	{ 0x08fc, 0x2191 },
	{ 0x08fd, 0x2192 },
	{ 0x08fe, 0x2193 },
	{ 0x09e0, 0x25c6 },
	{ 0x09e1, 0x2592 },
	{ 0x09e2, 0x2409 },
	{ 0x09e3, 0x240c },
	{ 0x09e4, 0x240d },
	{ 0x09e5, 0x240a },
	{ 0x09e8, 0x2424 },
	{ 0x09e9, 0x240b },
	{ 0x09ea, 0x2518 },
	{ 0x09eb, 0x2510 },
	{ 0x09ec, 0x250c },
	{ 0x09ed, 0x2514 },
	{ 0x09ee, 0x253c },
	{ 0x09ef, 0x23ba },
	{ 0x09f0, 0x23bb },
	{ 0x09f1, 0x2500 },
	{ 0x09f2, 0x23bc },
	{ 0x09f3, 0x23bd },
	{ 0x09f4, 0x251c },
	{ 0x09f5, 0x2524 },
	{ 0x09f6, 0x2534 },
	{ 0x09f7, 0x252c },
	{ 0x09f8, 0x2502 },
	{ 0x0aa1, 0x2003 },
	{ 0x0aa2, 0x2002 },
	{ 0x0aa3, 0x2004 },
	{ 0x0aa4, 0x2005 },
	{ 0x0aa5, 0x2007 },
	{ 0x0aa6, 0x2008 },
	{ 0x0aa7, 0x2009 },
	{ 0x0aa8, 0x200a },
	{ 0x0aa9, 0x2014 },
	{ 0x0aaa, 0x2013 },
	{ 0x0aae, 0x2026 },
	{ 0x0aaf, 0x2025 },
	{ 0x0ab0, 0x2153 },
	{ 0x0ab1, 0x2154 },
	{ 0x0ab2, 0x2155 },
	{ 0x0ab3, 0x2156 },
	{ 0x0ab4, 0x2157 },
	{ 0x0ab5, 0x2158 },
	{ 0x0ab6, 0x2159 },
	{ 0x0ab7, 0x215a },
	{ 0x0ab8, 0x2105 },
	{ 0x0abb, 0x2012 },
	{ 0x0abc, 0x2329 },
	{ 0x0abe, 0x232a },
	{ 0x0ac3, 0x215b },
	{ 0x0ac4, 0x215c },
	{ 0x0ac5, 0x215d },
	{ 0x0ac6, 0x215e },
	{ 0x0ac9, 0x2122 },
	{ 0x0aca, 0x2613 },
	{ 0x0acc, 0x25c1 },
	{ 0x0acd, 0x25b7 },
	{ 0x0ace, 0x25cb },
	{ 0x0acf, 0x25af },
	{ 0x0ad0, 0x2018 },
	{ 0x0ad1, 0x2019 },
	{ 0x0ad2, 0x201c },
	{ 0x0ad3, 0x201d },
	{ 0x0ad4, 0x211e },
	{ 0x0ad6, 0x2032 },
	{ 0x0ad7, 0x2033 },
	{ 0x0ad9, 0x271d },
	{ 0x0adb, 0x25ac },
	{ 0x0adc, 0x25c0 },
	{ 0x0add, 0x25b6 },
	{ 0x0ade, 0x25cf },
	{ 0x0adf, 0x25ae },
	{ 0x0ae0, 0x25e6 },
	{ 0x0ae1, 0x25ab },
	{ 0x0ae2, 0x25ad },
	{ 0x0ae3, 0x25b3 },
	{ 0x0ae4, 0x25bd },
	{ 0x0ae5, 0x2606 },
	{ 0x0ae6, 0x2022 },
	{ 0x0ae7, 0x25aa },
	{ 0x0ae8, 0x25b2 },
	{ 0x0ae9, 0x25bc },
	{ 0x0aea, 0x261c },
	{ 0x0aeb, 0x261e },
	{ 0x0aec, 0x2663 },
	{ 0x0aed, 0x2666 },
	{ 0x0aee, 0x2665 },
	{ 0x0af0, 0x2720 },
	{ 0x0af1, 0x2020 },
	{ 0x0af2, 0x2021 },
	{ 0x0af3, 0x2713 },
	{ 0x0af4, 0x2717 },
	{ 0x0af5, 0x266f },
	{ 0x0af6, 0x266d },
	{ 0x0af7, 0x2642 },
	{ 0x0af8, 0x2640 },
	{ 0x0af9, 0x260e },
	{ 0x0afa, 0x2315 },
	{ 0x0afb, 0x2117 },
	{ 0x0afc, 0x2038 },
	{ 0x0afd, 0x201a },
	{ 0x0afe, 0x201e },
	{ 0x0ba3, 0x003c },
	{ 0x0ba6, 0x003e },
	{ 0x0ba8, 0x2228 },
	{ 0x0ba9, 0x2227 },
	{ 0x0bc0, 0x00af },
	{ 0x0bc2, 0x22a5 },
	{ 0x0bc3, 0x2229 },
	{ 0x0bc4, 0x230a },
	{ 0x0bc6, 0x005f },
	{ 0x0bca, 0x2218 },
	{ 0x0bcc, 0x2395 },
	{ 0x0bce, 0x22a4 },
	{ 0x0bcf, 0x25cb },
	{ 0x0bd3, 0x2308 },
	{ 0x0bd6, 0x222a },
	{ 0x0bd8, 0x2283 },
	{ 0x0bda, 0x2282 },
	{ 0x0bdc, 0x22a2 },
	{ 0x0bfc, 0x22a3 },
	{ 0x0cdf, 0x2017 },
	{ 0x0ce0, 0x05d0 },
	{ 0x0ce1, 0x05d1 },
	{ 0x0ce2, 0x05d2 },
	{ 0x0ce3, 0x05d3 },
	{ 0x0ce4, 0x05d4 },
	{ 0x0ce5, 0x05d5 },
	{ 0x0ce6, 0x05d6 },
	{ 0x0ce7, 0x05d7 },
	{ 0x0ce8, 0x05d8 },
	{ 0x0ce9, 0x05d9 },
	{ 0x0cea, 0x05da },
	{ 0x0ceb, 0x05db },
	{ 0x0cec, 0x05dc },
	{ 0x0ced, 0x05dd },
	{ 0x0cee, 0x05de },
	{ 0x0cef, 0x05df },
	{ 0x0cf0, 0x05e0 },
	{ 0x0cf1, 0x05e1 },
	{ 0x0cf2, 0x05e2 },
	{ 0x0cf3, 0x05e3 },
	{ 0x0cf4, 0x05e4 },
	{ 0x0cf5, 0x05e5 },
	{ 0x0cf6, 0x05e6 },
	{ 0x0cf7, 0x05e7 },
	{ 0x0cf8, 0x05e8 },
	{ 0x0cf9, 0x05e9 },
	{ 0x0cfa, 0x05ea },
	{ 0x0da1, 0x0e01 },
	{ 0x0da2, 0x0e02 },
	{ 0x0da3, 0x0e03 },
	{ 0x0da4, 0x0e04 },
	{ 0x0da5, 0x0e05 },
	{ 0x0da6, 0x0e06 },
	{ 0x0da7, 0x0e07 },
	{ 0x0da8, 0x0e08 },
	{ 0x0da9, 0x0e09 },
	{ 0x0daa, 0x0e0a },
	{ 0x0dab, 0x0e0b },
	{ 0x0dac, 0x0e0c },
	{ 0x0dad, 0x0e0d },
	{ 0x0dae, 0x0e0e },
	{ 0x0daf, 0x0e0f },
	{ 0x0db0, 0x0e10 },
	{ 0x0db1, 0x0e11 },
	{ 0x0db2, 0x0e12 },
	{ 0x0db3, 0x0e13 },
	{ 0x0db4, 0x0e14 },
	{ 0x0db5, 0x0e15 },
	{ 0x0db6, 0x0e16 },
	{ 0x0db7, 0x0e17 },
	{ 0x0db8, 0x0e18 },
	{ 0x0db9, 0x0e19 },
	{ 0x0dba, 0x0e1a },
	{ 0x0dbb, 0x0e1b },
	{ 0x0dbc, 0x0e1c },
	{ 0x0dbd, 0x0e1d },
	{ 0x0dbe, 0x0e1e },
	{ 0x0dbf, 0x0e1f },
	{ 0x0dc0, 0x0e20 },
	{ 0x0dc1, 0x0e21 },
	{ 0x0dc2, 0x0e22 },
	{ 0x0dc3, 0x0e23 },
	{ 0x0dc4, 0x0e24 },
	{ 0x0dc5, 0x0e25 },
	{ 0x0dc6, 0x0e26 },
	{ 0x0dc7, 0x0e27 },
	{ 0x0dc8, 0x0e28 },
	{ 0x0dc9, 0x0e29 },
	{ 0x0dca, 0x0e2a },
	{ 0x0dcb, 0x0e2b },
	{ 0x0dcc, 0x0e2c },
	{ 0x0dcd, 0x0e2d },
	{ 0x0dce, 0x0e2e },
	{ 0x0dcf, 0x0e2f },
	{ 0x0dd0, 0x0e30 },
	{ 0x0dd1, 0x0e31 },
	{ 0x0dd2, 0x0e32 },
	{ 0x0dd3, 0x0e33 },
	{ 0x0dd4, 0x0e34 },
	{ 0x0dd5, 0x0e35 },
	{ 0x0dd6, 0x0e36 },
	{ 0x0dd7, 0x0e37 },
	{ 0x0dd8, 0x0e38 },
	{ 0x0dd9, 0x0e39 },
	{ 0x0dda, 0x0e3a },
	{ 0x0ddf, 0x0e3f },
	{ 0x0de0, 0x0e40 },
	{ 0x0de1, 0x0e41 },
	{ 0x0de2, 0x0e42 },
	{ 0x0de3, 0x0e43 },
	{ 0x0de4, 0x0e44 },
	{ 0x0de5, 0x0e45 },
	{ 0x0de6, 0x0e46 },
	{ 0x0de7, 0x0e47 },
	{ 0x0de8, 0x0e48 },
	{ 0x0de9, 0x0e49 },
	{ 0x0dea, 0x0e4a },
	{ 0x0deb, 0x0e4b },
	{ 0x0dec, 0x0e4c },
	{ 0x0ded, 0x0e4d },
	{ 0x0df0, 0x0e50 },
	{ 0x0df1, 0x0e51 },
	{ 0x0df2, 0x0e52 },
	{ 0x0df3, 0x0e53 },
	{ 0x0df4, 0x0e54 },
	{ 0x0df5, 0x0e55 },
	{ 0x0df6, 0x0e56 },
	{ 0x0df7, 0x0e57 },
	{ 0x0df8, 0x0e58 },
	{ 0x0df9, 0x0e59 },
	{ 0x0ea1, 0x3131 },
	{ 0x0ea2, 0x3132 },
	{ 0x0ea3, 0x3133 },
	{ 0x0ea4, 0x3134 },
	{ 0x0ea5, 0x3135 },
	{ 0x0ea6, 0x3136 },
	{ 0x0ea7, 0x3137 },
	{ 0x0ea8, 0x3138 },
	{ 0x0ea9, 0x3139 },
	{ 0x0eaa, 0x313a },
	{ 0x0eab, 0x313b },
	{ 0x0eac, 0x313c },
	{ 0x0ead, 0x313d },
	{ 0x0eae, 0x313e },
	{ 0x0eaf, 0x313f },
	{ 0x0eb0, 0x3140 },
	{ 0x0eb1, 0x3141 },
	{ 0x0eb2, 0x3142 },
	{ 0x0eb3, 0x3143 },
	{ 0x0eb4, 0x3144 },
	{ 0x0eb5, 0x3145 },
	{ 0x0eb6, 0x3146 },
	{ 0x0eb7, 0x3147 },
	{ 0x0eb8, 0x3148 },
	{ 0x0eb9, 0x3149 },
	{ 0x0eba, 0x314a },
	{ 0x0ebb, 0x314b },
	{ 0x0ebc, 0x314c },
	{ 0x0ebd, 0x314d },
	{ 0x0ebe, 0x314e },
	{ 0x0ebf, 0x314f },
	{ 0x0ec0, 0x3150 },
	{ 0x0ec1, 0x3151 },
	{ 0x0ec2, 0x3152 },
	{ 0x0ec3, 0x3153 },
	{ 0x0ec4, 0x3154 },
	{ 0x0ec5, 0x3155 },
	{ 0x0ec6, 0x3156 },
	{ 0x0ec7, 0x3157 },
	{ 0x0ec8, 0x3158 },
	{ 0x0ec9, 0x3159 },
	{ 0x0eca, 0x315a },
	{ 0x0ecb, 0x315b },
	{ 0x0ecc, 0x315c },
	{ 0x0ecd, 0x315d },
	{ 0x0ece, 0x315e },
	{ 0x0ecf, 0x315f },
	{ 0x0ed0, 0x3160 },
	{ 0x0ed1, 0x3161 },
	{ 0x0ed2, 0x3162 },
	{ 0x0ed3, 0x3163 },
	{ 0x0ed4, 0x11a8 },
	{ 0x0ed5, 0x11a9 },
	{ 0x0ed6, 0x11aa },
	{ 0x0ed7, 0x11ab },
	{ 0x0ed8, 0x11ac },
	{ 0x0ed9, 0x11ad },
	{ 0x0eda, 0x11ae },
	{ 0x0edb, 0x11af },
	{ 0x0edc, 0x11b0 },
	{ 0x0edd, 0x11b1 },
	{ 0x0ede, 0x11b2 },
	{ 0x0edf, 0x11b3 },
	{ 0x0ee0, 0x11b4 },
	{ 0x0ee1, 0x11b5 },
	{ 0x0ee2, 0x11b6 },
	{ 0x0ee3, 0x11b7 },
	{ 0x0ee4, 0x11b8 },
	{ 0x0ee5, 0x11b9 },
	{ 0x0ee6, 0x11ba },
	{ 0x0ee7, 0x11bb },
	{ 0x0ee8, 0x11bc },
	{ 0x0ee9, 0x11bd },
	{ 0x0eea, 0x11be },
	{ 0x0eeb, 0x11bf },
	{ 0x0eec, 0x11c0 },
	{ 0x0eed, 0x11c1 },
	{ 0x0eee, 0x11c2 },
	{ 0x0eef, 0x316d },
	{ 0x0ef0, 0x3171 },
	{ 0x0ef1, 0x3178 },
	{ 0x0ef2, 0x317f },
	{ 0x0ef3, 0x3181 },
	{ 0x0ef4, 0x3184 },
	{ 0x0ef5, 0x3186 },
	{ 0x0ef6, 0x318d },
	{ 0x0ef7, 0x318e },
	{ 0x0ef8, 0x11eb },
	{ 0x0ef9, 0x11f0 },
	{ 0x0efa, 0x11f9 },
	{ 0x0eff, 0x20a9 },
	{ 0x13a4, 0x20ac },
	{ 0x13bc, 0x0152 },
	{ 0x13bd, 0x0153 },
	{ 0x13be, 0x0178 },
	{ 0x20ac, 0x20ac },
	{ 0xfe50, 0x0060 },
	{ 0xfe51, 0x00b4 },
	{ 0xfe52, 0x005e },
	{ 0xfe53, 0x007e },
	{ 0xfe54, 0x00af },
	{ 0xfe55, 0x02d8 },
	{ 0xfe56, 0x02d9 },
	{ 0xfe57, 0x00a8 },
	{ 0xfe58, 0x02da },
	{ 0xfe59, 0x02dd },
	{ 0xfe5a, 0x02c7 },
	{ 0xfe5b, 0x00b8 },
	{ 0xfe5c, 0x02db },
	{ 0xfe5d, 0x037a },
	{ 0xfe5e, 0x309b },
	{ 0xfe5f, 0x309c },
	{ 0xfe63, 0x002f },
	{ 0xfe64, 0x02bc },
	{ 0xfe65, 0x02bd },
	{ 0xfe66, 0x02f5 },
	{ 0xfe67, 0x02f3 },
	{ 0xfe68, 0x02cd },
	{ 0xfe69, 0xa788 },
	{ 0xfe6a, 0x02f7 },
	{ 0xfe6e, 0x002c },
	{ 0xfe6f, 0x00a4 },
	{ 0xfe80, 0x0061 },
	{ 0xfe81, 0x0041 },
	{ 0xfe82, 0x0065 },
	{ 0xfe83, 0x0045 },
	{ 0xfe84, 0x0069 },
	{ 0xfe85, 0x0049 },
	{ 0xfe86, 0x006f },
	{ 0xfe87, 0x004f },
	{ 0xfe88, 0x0075 },
	{ 0xfe89, 0x0055 },
	{ 0xfe8a, 0x0259 },
	{ 0xfe8b, 0x018f },
	{ 0xfe8c, 0x00b5 },
	{ 0xfe90, 0x005f },
	{ 0xfe91, 0x02c8 },
	{ 0xfe92, 0x02cc },
	{ 0xff80, 0x0020 },
	{ 0xff95, 0x0037 },
	{ 0xff96, 0x0034 },
	{ 0xff97, 0x0038 },
	{ 0xff98, 0x0036 },
	{ 0xff99, 0x0032 },
	{ 0xff9a, 0x0039 },
	{ 0xff9b, 0x0033 },
	{ 0xff9c, 0x0031 },
	{ 0xff9d, 0x0035 },
	{ 0xff9e, 0x0030 },
	{ 0xffaa, 0x002a },
	{ 0xffab, 0x002b },
	{ 0xffac, 0x002c },
	{ 0xffad, 0x002d },
	{ 0xffae, 0x002e },
	{ 0xffaf, 0x002f },
	{ 0xffb0, 0x0030 },
	{ 0xffb1, 0x0031 },
	{ 0xffb2, 0x0032 },
	{ 0xffb3, 0x0033 },
	{ 0xffb4, 0x0034 },
	{ 0xffb5, 0x0035 },
	{ 0xffb6, 0x0036 },
	{ 0xffb7, 0x0037 },
	{ 0xffb8, 0x0038 },
	{ 0xffb9, 0x0039 },
	{ 0xffbd, 0x003d },
};

typedef struct {
	int redBits, greenBits, blueBits, alphaBits, depthBits, stencilBits, samples;
	bool doublebuffer;
	bool srgbCapable;
	GLXFBConfig handle;
} FbConfig;

static struct {
	VoidLinuxDesc desc;
	bool valid;
	bool firstFrame;
	bool initCalled;
	bool cleanupCalled;
	bool quitRequested;
	bool quitOrdered;
	VoidFrameTiming timing;
	uint64_t frameCount;
	int windowWidth;
	int windowHeight;
	int framebufferWidth;
	int framebufferHeight;
	float dpiScale;
	struct {
		float x, y, dx, dy;
		bool posValid;
		bool shown;
		bool locked;
		bool requestedLock;
		int cursor;
	} mouse;
	bool fullscreen;
	char *clipboard;
	int droppedCount;
	char **droppedPaths;
	VoidAppEvent event;
	int16_t keycodes[X11_KEYCODES];
	struct {
		uint8_t mouseButtons;
		Display *display;
		int screen;
		Window root;
		Colormap colormap;
		Window window;
		int windowState;
		float dpi;
		unsigned char errorCode;
		Atom UTF8_STRING;
		Atom WM_PROTOCOLS;
		Atom WM_DELETE_WINDOW;
		Atom WM_STATE;
		Atom NET_WM_NAME;
		Atom NET_WM_ICON_NAME;
		Atom NET_WM_STATE;
		Atom NET_WM_STATE_FULLSCREEN;
		Atom CLIPBOARD;
		Atom TARGETS;
		bool windowFocused;
		Cursor standardCursors[VOID_CURSOR_COUNT];
		Cursor hiddenCursor;
		bool keyRepeat[X11_KEYCODES];
		struct {
			Atom XdndAware, XdndEnter, XdndPosition, XdndStatus, XdndActionCopy, XdndDrop, XdndFinished,
				XdndSelection, XdndTypeList, textUriList;
			Window source;
			long version;
			Atom format;
		} xdnd;
		struct {
			bool available;
			int majorOpcode, eventBase, errorBase;
			XiSelectEventsFn SelectEvents;
		} xi;
	} x11;
	struct {
		void *libgl;
		int major, minor, eventBase, errorBase;
		GLXContext ctx;
		GLXWindow window;
		GlxGetFBConfigsFn GetFBConfigs;
		GlxGetFBConfigAttribFn GetFBConfigAttrib;
		GlxGetClientStringFn GetClientString;
		GlxQueryExtensionFn QueryExtension;
		GlxQueryVersionFn QueryVersion;
		GlxDestroyContextFn DestroyContext;
		GlxMakeCurrentFn MakeCurrent;
		GlxSwapBuffersFn SwapBuffers;
		GlxQueryExtensionsStringFn QueryExtensionsString;
		GlxGetVisualFromFBConfigFn GetVisualFromFBConfig;
		GlxCreateWindowFn CreateWindow;
		GlxDestroyWindowFn DestroyWindow;
		GlxGetProcAddressFn GetProcAddress;
		GlxGetProcAddressFn GetProcAddressARB;
		GlxSwapIntervalExtFn SwapIntervalEXT;
		GlxSwapIntervalMesaFn SwapIntervalMESA;
		GlxCreateContextAttribsFn CreateContextAttribsARB;
		bool EXT_swap_control;
		bool MESA_swap_control;
		bool ARB_multisample;
		bool ARB_create_context;
		bool ARB_create_context_profile;
	} glx;
	VoidKeysHeld keysHeld;
} s;

__attribute__((noreturn)) static void fail(const char *what) {
	fprintf(stderr, "void: %s\n", what);
	abort();
}

static int roundAtLeastOne(float f) {
	int v = (int)roundf(f);
	return v <= 0 ? 1 : v;
}

static bool eventsEnabled(void) { return s.desc.event != NULL && s.initCalled; }

static void initEvent(VoidAppEventType type) {
	memset(&s.event, 0, sizeof s.event);
	s.event.type = type;
	s.event.frameCount = s.frameCount;
	s.event.mouseButton = VOID_MOUSE_INVALID;
	s.event.windowWidth = s.windowWidth;
	s.event.windowHeight = s.windowHeight;
	s.event.framebufferWidth = s.framebufferWidth;
	s.event.framebufferHeight = s.framebufferHeight;
	s.event.mouseX = s.mouse.x;
	s.event.mouseY = s.mouse.y;
	s.event.mouseDx = s.mouse.dx;
	s.event.mouseDy = s.mouse.dy;
}

static void callEvent(void) {
	if (!s.cleanupCalled) s.desc.event(&s.event);
}

static void appEvent(VoidAppEventType type) {
	if (!eventsEnabled()) return;
	initEvent(type);
	callEvent();
}

static int errorHandler(Display *display, XErrorEvent *event) {
	(void)display;
	s.x11.errorCode = event->error_code;
	return 0;
}

static void grabErrorHandler(void) {
	s.x11.errorCode = Success;
	XSetErrorHandler(errorHandler);
}

static void releaseErrorHandler(void) {
	XSync(s.x11.display, False);
	XSetErrorHandler(NULL);
}

static void initAtoms(void) {
	s.x11.UTF8_STRING = XInternAtom(s.x11.display, "UTF8_STRING", False);
	s.x11.WM_PROTOCOLS = XInternAtom(s.x11.display, "WM_PROTOCOLS", False);
	s.x11.WM_DELETE_WINDOW = XInternAtom(s.x11.display, "WM_DELETE_WINDOW", False);
	s.x11.WM_STATE = XInternAtom(s.x11.display, "WM_STATE", False);
	s.x11.NET_WM_NAME = XInternAtom(s.x11.display, "_NET_WM_NAME", False);
	s.x11.NET_WM_ICON_NAME = XInternAtom(s.x11.display, "_NET_WM_ICON_NAME", False);
	s.x11.NET_WM_STATE = XInternAtom(s.x11.display, "_NET_WM_STATE", False);
	s.x11.NET_WM_STATE_FULLSCREEN = XInternAtom(s.x11.display, "_NET_WM_STATE_FULLSCREEN", False);
	s.x11.CLIPBOARD = XInternAtom(s.x11.display, "CLIPBOARD", False);
	s.x11.TARGETS = XInternAtom(s.x11.display, "TARGETS", False);
	s.x11.xdnd.XdndAware = XInternAtom(s.x11.display, "XdndAware", False);
	s.x11.xdnd.XdndEnter = XInternAtom(s.x11.display, "XdndEnter", False);
	s.x11.xdnd.XdndPosition = XInternAtom(s.x11.display, "XdndPosition", False);
	s.x11.xdnd.XdndStatus = XInternAtom(s.x11.display, "XdndStatus", False);
	s.x11.xdnd.XdndActionCopy = XInternAtom(s.x11.display, "XdndActionCopy", False);
	s.x11.xdnd.XdndDrop = XInternAtom(s.x11.display, "XdndDrop", False);
	s.x11.xdnd.XdndFinished = XInternAtom(s.x11.display, "XdndFinished", False);
	s.x11.xdnd.XdndSelection = XInternAtom(s.x11.display, "XdndSelection", False);
	s.x11.xdnd.XdndTypeList = XInternAtom(s.x11.display, "XdndTypeList", False);
	s.x11.xdnd.textUriList = XInternAtom(s.x11.display, "text/uri-list", False);
}

static void initXinput(void) {
	void *lib = dlopen("libXi.so.6", RTLD_LAZY | RTLD_LOCAL);
	if (lib == NULL) return;
	XiQueryVersionFn queryVersion = (XiQueryVersionFn)dlsym(lib, "XIQueryVersion");
	s.x11.xi.SelectEvents = (XiSelectEventsFn)dlsym(lib, "XISelectEvents");
	if (queryVersion == NULL || s.x11.xi.SelectEvents == NULL) return;
	if (!XQueryExtension(s.x11.display, "XInputExtension", &s.x11.xi.majorOpcode, &s.x11.xi.eventBase, &s.x11.xi.errorBase)) return;
	int major = 2, minor = 0;
	s.x11.xi.available = queryVersion(s.x11.display, &major, &minor) == Success;
}

// The layout-dependent fallback for a key XKB could not name (sokol_app.h :12303).
static VoidKeyCode translateKeysyms(const KeySym *keysyms, int width) {
	if (width > 1) {
		switch (keysyms[1]) {
			case XK_KP_0: return VOID_KEY_KP_0;
			case XK_KP_1: return VOID_KEY_KP_1;
			case XK_KP_2: return VOID_KEY_KP_2;
			case XK_KP_3: return VOID_KEY_KP_3;
			case XK_KP_4: return VOID_KEY_KP_4;
			case XK_KP_5: return VOID_KEY_KP_5;
			case XK_KP_6: return VOID_KEY_KP_6;
			case XK_KP_7: return VOID_KEY_KP_7;
			case XK_KP_8: return VOID_KEY_KP_8;
			case XK_KP_9: return VOID_KEY_KP_9;
			case XK_KP_Separator:
			case XK_KP_Decimal: return VOID_KEY_KP_DECIMAL;
			case XK_KP_Equal: return VOID_KEY_KP_EQUAL;
			case XK_KP_Enter: return VOID_KEY_KP_ENTER;
			default: break;
		}
	}
	switch (keysyms[0]) {
		case XK_Escape: return VOID_KEY_ESCAPE;
		case XK_Tab: return VOID_KEY_TAB;
		case XK_Shift_L: return VOID_KEY_LEFT_SHIFT;
		case XK_Shift_R: return VOID_KEY_RIGHT_SHIFT;
		case XK_Control_L: return VOID_KEY_LEFT_CONTROL;
		case XK_Control_R: return VOID_KEY_RIGHT_CONTROL;
		case XK_Meta_L:
		case XK_Alt_L: return VOID_KEY_LEFT_ALT;
		case XK_Mode_switch:
		case XK_ISO_Level3_Shift:
		case XK_Meta_R:
		case XK_Alt_R: return VOID_KEY_RIGHT_ALT;
		case XK_Super_L: return VOID_KEY_LEFT_SUPER;
		case XK_Super_R: return VOID_KEY_RIGHT_SUPER;
		case XK_Menu: return VOID_KEY_MENU;
		case XK_Num_Lock: return VOID_KEY_NUM_LOCK;
		case XK_Caps_Lock: return VOID_KEY_CAPS_LOCK;
		case XK_Print: return VOID_KEY_PRINT_SCREEN;
		case XK_Scroll_Lock: return VOID_KEY_SCROLL_LOCK;
		case XK_Pause: return VOID_KEY_PAUSE;
		case XK_Delete: return VOID_KEY_DELETE;
		case XK_BackSpace: return VOID_KEY_BACKSPACE;
		case XK_Return: return VOID_KEY_ENTER;
		case XK_Home: return VOID_KEY_HOME;
		case XK_End: return VOID_KEY_END;
		case XK_Page_Up: return VOID_KEY_PAGE_UP;
		case XK_Page_Down: return VOID_KEY_PAGE_DOWN;
		case XK_Insert: return VOID_KEY_INSERT;
		case XK_Left: return VOID_KEY_LEFT;
		case XK_Right: return VOID_KEY_RIGHT;
		case XK_Down: return VOID_KEY_DOWN;
		case XK_Up: return VOID_KEY_UP;
		case XK_F1: return VOID_KEY_F1;
		case XK_F2: return VOID_KEY_F2;
		case XK_F3: return VOID_KEY_F3;
		case XK_F4: return VOID_KEY_F4;
		case XK_F5: return VOID_KEY_F5;
		case XK_F6: return VOID_KEY_F6;
		case XK_F7: return VOID_KEY_F7;
		case XK_F8: return VOID_KEY_F8;
		case XK_F9: return VOID_KEY_F9;
		case XK_F10: return VOID_KEY_F10;
		case XK_F11: return VOID_KEY_F11;
		case XK_F12: return VOID_KEY_F12;
		case XK_F13: return VOID_KEY_F13;
		case XK_F14: return VOID_KEY_F14;
		case XK_F15: return VOID_KEY_F15;
		case XK_F16: return VOID_KEY_F16;
		case XK_F17: return VOID_KEY_F17;
		case XK_F18: return VOID_KEY_F18;
		case XK_F19: return VOID_KEY_F19;
		case XK_F20: return VOID_KEY_F20;
		case XK_F21: return VOID_KEY_F21;
		case XK_F22: return VOID_KEY_F22;
		case XK_F23: return VOID_KEY_F23;
		case XK_F24: return VOID_KEY_F24;
		case XK_F25: return VOID_KEY_F25;
		case XK_KP_Divide: return VOID_KEY_KP_DIVIDE;
		case XK_KP_Multiply: return VOID_KEY_KP_MULTIPLY;
		case XK_KP_Subtract: return VOID_KEY_KP_SUBTRACT;
		case XK_KP_Add: return VOID_KEY_KP_ADD;
		case XK_KP_Insert: return VOID_KEY_KP_0;
		case XK_KP_End: return VOID_KEY_KP_1;
		case XK_KP_Down: return VOID_KEY_KP_2;
		case XK_KP_Page_Down: return VOID_KEY_KP_3;
		case XK_KP_Left: return VOID_KEY_KP_4;
		case XK_KP_Right: return VOID_KEY_KP_6;
		case XK_KP_Home: return VOID_KEY_KP_7;
		case XK_KP_Up: return VOID_KEY_KP_8;
		case XK_KP_Page_Up: return VOID_KEY_KP_9;
		case XK_KP_Delete: return VOID_KEY_KP_DECIMAL;
		case XK_KP_Equal: return VOID_KEY_KP_EQUAL;
		case XK_KP_Enter: return VOID_KEY_KP_ENTER;
		case XK_a: return VOID_KEY_A;
		case XK_b: return VOID_KEY_B;
		case XK_c: return VOID_KEY_C;
		case XK_d: return VOID_KEY_D;
		case XK_e: return VOID_KEY_E;
		case XK_f: return VOID_KEY_F;
		case XK_g: return VOID_KEY_G;
		case XK_h: return VOID_KEY_H;
		case XK_i: return VOID_KEY_I;
		case XK_j: return VOID_KEY_J;
		case XK_k: return VOID_KEY_K;
		case XK_l: return VOID_KEY_L;
		case XK_m: return VOID_KEY_M;
		case XK_n: return VOID_KEY_N;
		case XK_o: return VOID_KEY_O;
		case XK_p: return VOID_KEY_P;
		case XK_q: return VOID_KEY_Q;
		case XK_r: return VOID_KEY_R;
		case XK_s: return VOID_KEY_S;
		case XK_t: return VOID_KEY_T;
		case XK_u: return VOID_KEY_U;
		case XK_v: return VOID_KEY_V;
		case XK_w: return VOID_KEY_W;
		case XK_x: return VOID_KEY_X;
		case XK_y: return VOID_KEY_Y;
		case XK_z: return VOID_KEY_Z;
		case XK_1: return VOID_KEY_1;
		case XK_2: return VOID_KEY_2;
		case XK_3: return VOID_KEY_3;
		case XK_4: return VOID_KEY_4;
		case XK_5: return VOID_KEY_5;
		case XK_6: return VOID_KEY_6;
		case XK_7: return VOID_KEY_7;
		case XK_8: return VOID_KEY_8;
		case XK_9: return VOID_KEY_9;
		case XK_0: return VOID_KEY_0;
		case XK_space: return VOID_KEY_SPACE;
		case XK_minus: return VOID_KEY_MINUS;
		case XK_equal: return VOID_KEY_EQUAL;
		case XK_bracketleft: return VOID_KEY_LEFT_BRACKET;
		case XK_bracketright: return VOID_KEY_RIGHT_BRACKET;
		case XK_backslash: return VOID_KEY_BACKSLASH;
		case XK_semicolon: return VOID_KEY_SEMICOLON;
		case XK_apostrophe: return VOID_KEY_APOSTROPHE;
		case XK_grave: return VOID_KEY_GRAVE_ACCENT;
		case XK_comma: return VOID_KEY_COMMA;
		case XK_period: return VOID_KEY_PERIOD;
		case XK_slash: return VOID_KEY_SLASH;
		case XK_less: return VOID_KEY_WORLD_1;
		default: return VOID_KEY_INVALID;
	}
}

// Physical key positions by XKB key name, so keycodes do not follow the layout (sokol_app.h :12468).
static void initKeytable(void) {
	static const struct {
		VoidKeyCode key;
		const char *name;
	} keymap[] = {
		{ VOID_KEY_GRAVE_ACCENT, "TLDE" }, { VOID_KEY_1, "AE01" }, { VOID_KEY_2, "AE02" },
		{ VOID_KEY_3, "AE03" }, { VOID_KEY_4, "AE04" }, { VOID_KEY_5, "AE05" },
		{ VOID_KEY_6, "AE06" }, { VOID_KEY_7, "AE07" }, { VOID_KEY_8, "AE08" },
		{ VOID_KEY_9, "AE09" }, { VOID_KEY_0, "AE10" }, { VOID_KEY_MINUS, "AE11" },
		{ VOID_KEY_EQUAL, "AE12" }, { VOID_KEY_Q, "AD01" }, { VOID_KEY_W, "AD02" },
		{ VOID_KEY_E, "AD03" }, { VOID_KEY_R, "AD04" }, { VOID_KEY_T, "AD05" },
		{ VOID_KEY_Y, "AD06" }, { VOID_KEY_U, "AD07" }, { VOID_KEY_I, "AD08" },
		{ VOID_KEY_O, "AD09" }, { VOID_KEY_P, "AD10" }, { VOID_KEY_LEFT_BRACKET, "AD11" },
		{ VOID_KEY_RIGHT_BRACKET, "AD12" }, { VOID_KEY_A, "AC01" }, { VOID_KEY_S, "AC02" },
		{ VOID_KEY_D, "AC03" }, { VOID_KEY_F, "AC04" }, { VOID_KEY_G, "AC05" },
		{ VOID_KEY_H, "AC06" }, { VOID_KEY_J, "AC07" }, { VOID_KEY_K, "AC08" },
		{ VOID_KEY_L, "AC09" }, { VOID_KEY_SEMICOLON, "AC10" }, { VOID_KEY_APOSTROPHE, "AC11" },
		{ VOID_KEY_Z, "AB01" }, { VOID_KEY_X, "AB02" }, { VOID_KEY_C, "AB03" },
		{ VOID_KEY_V, "AB04" }, { VOID_KEY_B, "AB05" }, { VOID_KEY_N, "AB06" },
		{ VOID_KEY_M, "AB07" }, { VOID_KEY_COMMA, "AB08" }, { VOID_KEY_PERIOD, "AB09" },
		{ VOID_KEY_SLASH, "AB10" }, { VOID_KEY_BACKSLASH, "BKSL" }, { VOID_KEY_WORLD_1, "LSGT" },
		{ VOID_KEY_SPACE, "SPCE" }, { VOID_KEY_ESCAPE, "ESC" }, { VOID_KEY_ENTER, "RTRN" },
		{ VOID_KEY_TAB, "TAB" }, { VOID_KEY_BACKSPACE, "BKSP" }, { VOID_KEY_INSERT, "INS" },
		{ VOID_KEY_DELETE, "DELE" }, { VOID_KEY_RIGHT, "RGHT" }, { VOID_KEY_LEFT, "LEFT" },
		{ VOID_KEY_DOWN, "DOWN" }, { VOID_KEY_UP, "UP" }, { VOID_KEY_PAGE_UP, "PGUP" },
		{ VOID_KEY_PAGE_DOWN, "PGDN" }, { VOID_KEY_HOME, "HOME" }, { VOID_KEY_END, "END" },
		{ VOID_KEY_CAPS_LOCK, "CAPS" }, { VOID_KEY_SCROLL_LOCK, "SCLK" }, { VOID_KEY_NUM_LOCK, "NMLK" },
		{ VOID_KEY_PRINT_SCREEN, "PRSC" }, { VOID_KEY_PAUSE, "PAUS" }, { VOID_KEY_F1, "FK01" },
		{ VOID_KEY_F2, "FK02" }, { VOID_KEY_F3, "FK03" }, { VOID_KEY_F4, "FK04" },
		{ VOID_KEY_F5, "FK05" }, { VOID_KEY_F6, "FK06" }, { VOID_KEY_F7, "FK07" },
		{ VOID_KEY_F8, "FK08" }, { VOID_KEY_F9, "FK09" }, { VOID_KEY_F10, "FK10" },
		{ VOID_KEY_F11, "FK11" }, { VOID_KEY_F12, "FK12" }, { VOID_KEY_F13, "FK13" },
		{ VOID_KEY_F14, "FK14" }, { VOID_KEY_F15, "FK15" }, { VOID_KEY_F16, "FK16" },
		{ VOID_KEY_F17, "FK17" }, { VOID_KEY_F18, "FK18" }, { VOID_KEY_F19, "FK19" },
		{ VOID_KEY_F20, "FK20" }, { VOID_KEY_F21, "FK21" }, { VOID_KEY_F22, "FK22" },
		{ VOID_KEY_F23, "FK23" }, { VOID_KEY_F24, "FK24" }, { VOID_KEY_F25, "FK25" },
		{ VOID_KEY_KP_0, "KP0" }, { VOID_KEY_KP_1, "KP1" }, { VOID_KEY_KP_2, "KP2" },
		{ VOID_KEY_KP_3, "KP3" }, { VOID_KEY_KP_4, "KP4" }, { VOID_KEY_KP_5, "KP5" },
		{ VOID_KEY_KP_6, "KP6" }, { VOID_KEY_KP_7, "KP7" }, { VOID_KEY_KP_8, "KP8" },
		{ VOID_KEY_KP_9, "KP9" }, { VOID_KEY_KP_DECIMAL, "KPDL" }, { VOID_KEY_KP_DIVIDE, "KPDV" },
		{ VOID_KEY_KP_MULTIPLY, "KPMU" }, { VOID_KEY_KP_SUBTRACT, "KPSU" }, { VOID_KEY_KP_ADD, "KPAD" },
		{ VOID_KEY_KP_ENTER, "KPEN" }, { VOID_KEY_KP_EQUAL, "KPEQ" }, { VOID_KEY_LEFT_SHIFT, "LFSH" },
		{ VOID_KEY_LEFT_CONTROL, "LCTL" }, { VOID_KEY_LEFT_ALT, "LALT" }, { VOID_KEY_LEFT_SUPER, "LWIN" },
		{ VOID_KEY_RIGHT_SHIFT, "RTSH" }, { VOID_KEY_RIGHT_CONTROL, "RCTL" }, { VOID_KEY_RIGHT_ALT, "RALT" },
		{ VOID_KEY_RIGHT_ALT, "LVL3" }, { VOID_KEY_RIGHT_ALT, "MDSW" }, { VOID_KEY_RIGHT_SUPER, "RWIN" },
		{ VOID_KEY_MENU, "MENU" },
	};
	const int keymapCount = (int)(sizeof keymap / sizeof keymap[0]);
	for (int i = 0; i < X11_KEYCODES; i++) s.keycodes[i] = VOID_KEY_INVALID;
	XkbDescPtr desc = XkbGetMap(s.x11.display, 0, XkbUseCoreKbd);
	if (desc == NULL) fail("XkbGetMap failed");
	XkbGetNames(s.x11.display, XkbKeyNamesMask | XkbKeyAliasesMask, desc);
	const int scancodeMin = desc->min_key_code;
	const int scancodeMax = desc->max_key_code;
	for (int scancode = scancodeMin; scancode <= scancodeMax; scancode++) {
		VoidKeyCode key = VOID_KEY_INVALID;
		for (int i = 0; i < keymapCount; i++) {
			if (strncmp(desc->names->keys[scancode].name, keymap[i].name, XkbKeyNameLength) == 0) {
				key = keymap[i].key;
				break;
			}
		}
		for (int i = 0; i < desc->names->num_key_aliases && key == VOID_KEY_INVALID; i++) {
			if (strncmp(desc->names->key_aliases[i].real, desc->names->keys[scancode].name, XkbKeyNameLength) != 0) continue;
			for (int j = 0; j < keymapCount; j++) {
				if (strncmp(desc->names->key_aliases[i].alias, keymap[j].name, XkbKeyNameLength) == 0) {
					key = keymap[j].key;
					break;
				}
			}
		}
		s.keycodes[scancode] = (int16_t)key;
	}
	XkbFreeNames(desc, XkbKeyNamesMask, True);
	XkbFreeKeyboard(desc, 0, True);
	int width = 0;
	KeySym *keysyms = XGetKeyboardMapping(s.x11.display, (KeyCode)scancodeMin, scancodeMax - scancodeMin + 1, &width);
	for (int scancode = scancodeMin; scancode <= scancodeMax; scancode++) {
		if (s.keycodes[scancode] == VOID_KEY_INVALID) {
			const size_t base = (size_t)((scancode - scancodeMin) * width);
			s.keycodes[scancode] = (int16_t)translateKeysyms(&keysyms[base], width);
		}
	}
	XFree(keysyms);
}

// Xft.dpi as Qt and Gtk read it, else 96 (sokol_app.h :12647).
static void querySystemDpi(void) {
	s.x11.dpi = 96.0f;
	char *rms = XResourceManagerString(s.x11.display);
	if (rms == NULL) return;
	XrmDatabase db = XrmGetStringDatabase(rms);
	if (db == NULL) return;
	XrmValue value;
	char *valueType = NULL;
	if (XrmGetResource(db, "Xft.dpi", "Xft.Dpi", &valueType, &value) && valueType && strcmp(valueType, "String") == 0) {
		s.x11.dpi = (float)atof(value.addr);
	}
	XrmDestroyDatabase(db);
}

static bool hasExtension(const char *ext, const char *extensions) {
	if (extensions == NULL) return false;
	const char *start = extensions;
	for (;;) {
		const char *where = strstr(start, ext);
		if (where == NULL) return false;
		const char *terminator = where + strlen(ext);
		if ((where == start || where[-1] == ' ') && (*terminator == ' ' || *terminator == '\0')) return true;
		start = terminator;
	}
}

static void *glxProcAddress(const char *name) {
	if (s.glx.GetProcAddress) return (void *)s.glx.GetProcAddress(name);
	if (s.glx.GetProcAddressARB) return (void *)s.glx.GetProcAddressARB(name);
	return dlsym(s.glx.libgl, name);
}

static void initGlx(void) {
	const char *sonames[] = { "libGL.so.1", "libGL.so", NULL };
	for (int i = 0; sonames[i] && s.glx.libgl == NULL; i++) s.glx.libgl = dlopen(sonames[i], RTLD_LAZY | RTLD_GLOBAL);
	if (s.glx.libgl == NULL) fail("failed to load libGL");
	s.glx.GetFBConfigs = (GlxGetFBConfigsFn)dlsym(s.glx.libgl, "glXGetFBConfigs");
	s.glx.GetFBConfigAttrib = (GlxGetFBConfigAttribFn)dlsym(s.glx.libgl, "glXGetFBConfigAttrib");
	s.glx.GetClientString = (GlxGetClientStringFn)dlsym(s.glx.libgl, "glXGetClientString");
	s.glx.QueryExtension = (GlxQueryExtensionFn)dlsym(s.glx.libgl, "glXQueryExtension");
	s.glx.QueryVersion = (GlxQueryVersionFn)dlsym(s.glx.libgl, "glXQueryVersion");
	s.glx.DestroyContext = (GlxDestroyContextFn)dlsym(s.glx.libgl, "glXDestroyContext");
	s.glx.MakeCurrent = (GlxMakeCurrentFn)dlsym(s.glx.libgl, "glXMakeCurrent");
	s.glx.SwapBuffers = (GlxSwapBuffersFn)dlsym(s.glx.libgl, "glXSwapBuffers");
	s.glx.QueryExtensionsString = (GlxQueryExtensionsStringFn)dlsym(s.glx.libgl, "glXQueryExtensionsString");
	s.glx.CreateWindow = (GlxCreateWindowFn)dlsym(s.glx.libgl, "glXCreateWindow");
	s.glx.DestroyWindow = (GlxDestroyWindowFn)dlsym(s.glx.libgl, "glXDestroyWindow");
	s.glx.GetProcAddress = (GlxGetProcAddressFn)dlsym(s.glx.libgl, "glXGetProcAddress");
	s.glx.GetProcAddressARB = (GlxGetProcAddressFn)dlsym(s.glx.libgl, "glXGetProcAddressARB");
	s.glx.GetVisualFromFBConfig = (GlxGetVisualFromFBConfigFn)dlsym(s.glx.libgl, "glXGetVisualFromFBConfig");
	if (!s.glx.GetFBConfigs || !s.glx.GetFBConfigAttrib || !s.glx.GetClientString || !s.glx.QueryExtension
		|| !s.glx.QueryVersion || !s.glx.DestroyContext || !s.glx.MakeCurrent || !s.glx.SwapBuffers
		|| !s.glx.QueryExtensionsString || !s.glx.CreateWindow || !s.glx.DestroyWindow
		|| !s.glx.GetProcAddress || !s.glx.GetProcAddressARB || !s.glx.GetVisualFromFBConfig) {
		fail("failed to load GLX entry points");
	}
	if (!s.glx.QueryExtension(s.x11.display, &s.glx.errorBase, &s.glx.eventBase)) fail("GLX extension not found");
	if (!s.glx.QueryVersion(s.x11.display, &s.glx.major, &s.glx.minor)) fail("failed to query GLX version");
	if (s.glx.major == 1 && s.glx.minor < 3) fail("GLX version too low (need at least 1.3)");
	const char *exts = s.glx.QueryExtensionsString(s.x11.display, s.x11.screen);
	if (hasExtension("GLX_EXT_swap_control", exts)) {
		s.glx.SwapIntervalEXT = (GlxSwapIntervalExtFn)glxProcAddress("glXSwapIntervalEXT");
		s.glx.EXT_swap_control = s.glx.SwapIntervalEXT != NULL;
	}
	if (hasExtension("GLX_MESA_swap_control", exts)) {
		s.glx.SwapIntervalMESA = (GlxSwapIntervalMesaFn)glxProcAddress("glXSwapIntervalMESA");
		s.glx.MESA_swap_control = s.glx.SwapIntervalMESA != NULL;
	}
	s.glx.ARB_multisample = hasExtension("GLX_ARB_multisample", exts);
	if (hasExtension("GLX_ARB_create_context", exts)) {
		s.glx.CreateContextAttribsARB = (GlxCreateContextAttribsFn)glxProcAddress("glXCreateContextAttribsARB");
		s.glx.ARB_create_context = s.glx.CreateContextAttribsARB != NULL;
	}
	s.glx.ARB_create_context_profile = hasExtension("GLX_ARB_create_context_profile", exts);
}

static int glxAttrib(GLXFBConfig config, int attrib) {
	int value = 0;
	s.glx.GetFBConfigAttrib(s.x11.display, config, attrib, &value);
	return value;
}

static int squared(int desired, int current) {
	return desired == -1 ? 0 : (desired - current) * (desired - current);
}

// The closest config by missing buffers, then color size, then the other sizes; -1 is "don't
// care" (sokol_app.h _sapp_gl_choose_fbconfig :8528).
static const FbConfig *closestConfig(const FbConfig *desired, const FbConfig *alternatives, int count) {
	int leastMissing = 1000000;
	int leastColorDiff = 10000000;
	int leastExtraDiff = 10000000;
	const FbConfig *closest = NULL;
	for (int i = 0; i < count; i++) {
		const FbConfig *current = alternatives + i;
		if (desired->doublebuffer != current->doublebuffer || desired->srgbCapable != current->srgbCapable) continue;
		int missing = 0;
		if (desired->alphaBits > 0 && current->alphaBits == 0) missing++;
		if (desired->depthBits > 0 && current->depthBits == 0) missing++;
		if (desired->stencilBits > 0 && current->stencilBits == 0) missing++;
		if (desired->samples > 0 && current->samples == 0) missing++;
		const int colorDiff = squared(desired->redBits, current->redBits) + squared(desired->greenBits, current->greenBits)
			+ squared(desired->blueBits, current->blueBits);
		const int extraDiff = squared(desired->alphaBits, current->alphaBits) + squared(desired->depthBits, current->depthBits)
			+ squared(desired->stencilBits, current->stencilBits) + squared(desired->samples, current->samples);
		if (missing < leastMissing) {
			closest = current;
		} else if (missing == leastMissing) {
			if (colorDiff < leastColorDiff || (colorDiff == leastColorDiff && extraDiff < leastExtraDiff)) closest = current;
		}
		if (current == closest) {
			leastMissing = missing;
			leastColorDiff = colorDiff;
			leastExtraDiff = extraDiff;
		}
	}
	return closest;
}

// RGBA8, depth 24, no stencil, double-buffered, not sRGB: sokol's defaults (depth_format DEPTH,
// srgb false) in _sapp_glx_choosefbconfig (sokol_app.h :12799).
static GLXFBConfig chooseFbConfig(void) {
	// VirtualBox's GL ("Chromium") sets the window bit on no config.
	const char *vendor = s.glx.GetClientString(s.x11.display, GLX_VENDOR);
	const bool trustWindowBit = !(vendor && strcmp(vendor, "Chromium") == 0);
	int nativeCount = 0;
	GLXFBConfig *native = s.glx.GetFBConfigs(s.x11.display, s.x11.screen, &nativeCount);
	if (native == NULL || nativeCount == 0) fail("glXGetFBConfigs() returned no configs");
	FbConfig *usable = (FbConfig *)calloc((size_t)nativeCount, sizeof(FbConfig));
	if (usable == NULL) fail("out of memory for the GLX configs");
	int usableCount = 0;
	for (int i = 0; i < nativeCount; i++) {
		const GLXFBConfig n = native[i];
		if ((glxAttrib(n, GLX_RENDER_TYPE) & GLX_RGBA_BIT) == 0) continue;
		if ((glxAttrib(n, GLX_DRAWABLE_TYPE) & GLX_WINDOW_BIT) == 0 && trustWindowBit) continue;
		FbConfig *u = &usable[usableCount++];
		u->redBits = glxAttrib(n, GLX_RED_SIZE);
		u->greenBits = glxAttrib(n, GLX_GREEN_SIZE);
		u->blueBits = glxAttrib(n, GLX_BLUE_SIZE);
		u->alphaBits = glxAttrib(n, GLX_ALPHA_SIZE);
		u->depthBits = glxAttrib(n, GLX_DEPTH_SIZE);
		u->stencilBits = glxAttrib(n, GLX_STENCIL_SIZE);
		u->samples = s.glx.ARB_multisample ? glxAttrib(n, GLX_SAMPLES) : 0;
		u->doublebuffer = glxAttrib(n, GLX_DOUBLEBUFFER) != 0;
		u->srgbCapable = false;
		u->handle = n;
	}
	const bool wantsMsaa = s.desc.sampleCount > 1 && s.glx.ARB_multisample;
	const FbConfig desired = {
		.redBits = 8, .greenBits = 8, .blueBits = 8, .alphaBits = 8,
		.depthBits = 24, .stencilBits = 0,
		.samples = wantsMsaa ? s.desc.sampleCount : 0,
		.doublebuffer = true, .srgbCapable = false,
	};
	const FbConfig *closest = closestConfig(&desired, usable, usableCount);
	GLXFBConfig result = closest ? closest->handle : NULL;
	const int samples = closest ? closest->samples : 0;
	XFree(native);
	free(usable);
	if (result == NULL) fail("failed to find a suitable GLXFBConfig");
	if (s.desc.sampleCount > 1 && samples != s.desc.sampleCount) {
		fprintf(stderr, "void: no GLXFBConfig with %d samples (the closest has %d)\n", s.desc.sampleCount, samples);
		abort();
	}
	return result;
}

static void chooseVisual(Visual **visual, int *depth) {
	XVisualInfo *info = s.glx.GetVisualFromFBConfig(s.x11.display, chooseFbConfig());
	if (info == NULL) fail("glXGetVisualFromFBConfig failed");
	*visual = info->visual;
	*depth = info->depth;
	XFree(info);
}

static void createContext(void) {
	GLXFBConfig native = chooseFbConfig();
	if (!(s.glx.ARB_create_context && s.glx.ARB_create_context_profile)) {
		fail("GLX extensions ARB_create_context and ARB_create_context_profile missing");
	}
	grabErrorHandler();
	const int attribs[] = {
		GLX_CONTEXT_MAJOR_VERSION_ARB, 4,
		GLX_CONTEXT_MINOR_VERSION_ARB, 3,
		GLX_CONTEXT_PROFILE_MASK_ARB, GLX_CONTEXT_CORE_PROFILE_BIT_ARB,
		GLX_CONTEXT_FLAGS_ARB, GLX_CONTEXT_FORWARD_COMPATIBLE_BIT_ARB,
		0, 0,
	};
	s.glx.ctx = s.glx.CreateContextAttribsARB(s.x11.display, native, NULL, True, attribs);
	if (s.glx.ctx == NULL) fail("failed to create GL context via glXCreateContextAttribsARB");
	releaseErrorHandler();
	s.glx.window = s.glx.CreateWindow(s.x11.display, native, s.x11.window, NULL);
	if (!s.glx.window) fail("glXCreateWindow() failed");
	s.glx.MakeCurrent(s.x11.display, s.glx.window, s.glx.ctx);
}

static void destroyContext(void) {
	if (s.glx.window) {
		s.glx.DestroyWindow(s.x11.display, s.glx.window);
		s.glx.window = 0;
	}
	if (s.glx.ctx) {
		s.glx.DestroyContext(s.x11.display, s.glx.ctx);
		s.glx.ctx = NULL;
	}
}

static void swapInterval(int interval) {
	if (s.glx.EXT_swap_control) s.glx.SwapIntervalEXT(s.x11.display, s.glx.window, interval);
	else if (s.glx.MESA_swap_control) s.glx.SwapIntervalMESA(interval);
}

static bool waitForEvent(int eventType, int64_t timeoutNs, XEvent *out) {
	const int64_t start = voidPlatformClockNow();
	while (!XCheckTypedWindowEvent(s.x11.display, s.x11.window, eventType, out)) {
		struct pollfd fd = { ConnectionNumber(s.x11.display), POLLIN, 0 };
		poll(&fd, 1, (int)(timeoutNs / 1000000));
		if (voidPlatformClockNow() - start > timeoutNs) return false;
	}
	return true;
}

// Window size is X11 pixels over Xft.dpi/96; the framebuffer is X11 pixels (sokol_app.h :13003).
static void updateDimensions(int x11Width, int x11Height) {
	const float windowScale = s.x11.dpi / 96.0f;
	s.windowWidth = roundAtLeastOne((float)x11Width / windowScale);
	s.windowHeight = roundAtLeastOne((float)x11Height / windowScale);
	const int fbWidth = roundAtLeastOne((float)s.windowWidth * s.dpiScale);
	const int fbHeight = roundAtLeastOne((float)s.windowHeight * s.dpiScale);
	if (fbWidth == s.framebufferWidth && fbHeight == s.framebufferHeight) return;
	s.framebufferWidth = fbWidth;
	s.framebufferHeight = fbHeight;
	if (!s.firstFrame) appEvent(VOID_EVENT_RESIZED);
}

static void updateDimensionsFromWindowSize(void) {
	XWindowAttributes attribs;
	XGetWindowAttributes(s.x11.display, s.x11.window, &attribs);
	updateDimensions(attribs.width, attribs.height);
}

static void updateWindowTitle(const char *title) {
	Xutf8SetWMProperties(s.x11.display, s.x11.window, title, title, NULL, 0, NULL, NULL, NULL);
	XChangeProperty(s.x11.display, s.x11.window, s.x11.NET_WM_NAME, s.x11.UTF8_STRING, 8, PropModeReplace,
		(const unsigned char *)title, (int)strlen(title));
	XChangeProperty(s.x11.display, s.x11.window, s.x11.NET_WM_ICON_NAME, s.x11.UTF8_STRING, 8, PropModeReplace,
		(const unsigned char *)title, (int)strlen(title));
	XFlush(s.x11.display);
}

static void createWindow(Visual *visual, int depth) {
	s.x11.colormap = XCreateColormap(s.x11.display, s.x11.root, visual, AllocNone);
	XSetWindowAttributes wa;
	memset(&wa, 0, sizeof wa);
	const unsigned long wamask = CWBorderPixel | CWColormap | CWEventMask;
	wa.colormap = s.x11.colormap;
	wa.border_pixel = 0;
	wa.event_mask = StructureNotifyMask | KeyPressMask | KeyReleaseMask | PointerMotionMask | ButtonPressMask
		| ButtonReleaseMask | ExposureMask | FocusChangeMask | VisibilityChangeMask | EnterWindowMask
		| LeaveWindowMask | PropertyChangeMask;
	const int displayWidth = DisplayWidth(s.x11.display, s.x11.screen);
	const int displayHeight = DisplayHeight(s.x11.display, s.x11.screen);
	const float windowScale = s.x11.dpi / 96.0f;
	int x11Width = roundAtLeastOne((float)s.windowWidth * windowScale);
	int x11Height = roundAtLeastOne((float)s.windowHeight * windowScale);
	if (s.windowWidth == 0) x11Width = displayWidth * 4 / 5;
	if (s.windowHeight == 0) x11Height = displayHeight * 4 / 5;
	grabErrorHandler();
	s.x11.window = XCreateWindow(s.x11.display, s.x11.root, 0, 0, (unsigned)x11Width, (unsigned)x11Height, 0, depth,
		InputOutput, visual, wamask, &wa);
	releaseErrorHandler();
	if (!s.x11.window) fail("XCreateWindow() failed");
	Atom protocols[] = { s.x11.WM_DELETE_WINDOW };
	XSetWMProtocols(s.x11.display, s.x11.window, protocols, 1);
	XSizeHints *hints = XAllocSizeHints();
	hints->flags = PWinGravity;
	hints->win_gravity = CenterGravity;
	XSetWMNormalHints(s.x11.display, s.x11.window, hints);
	XFree(hints);
	const Atom xdndVersion = XDND_VERSION;
	XChangeProperty(s.x11.display, s.x11.window, s.x11.xdnd.XdndAware, XA_ATOM, 32, PropModeReplace,
		(const unsigned char *)&xdndVersion, 1);
	updateWindowTitle(s.desc.title);
	updateDimensionsFromWindowSize();
}

static void destroyWindow(void) {
	if (s.x11.window) {
		XUnmapWindow(s.x11.display, s.x11.window);
		XDestroyWindow(s.x11.display, s.x11.window);
		s.x11.window = 0;
	}
	if (s.x11.colormap) {
		XFreeColormap(s.x11.display, s.x11.colormap);
		s.x11.colormap = 0;
	}
	XFlush(s.x11.display);
}

static void showWindow(void) {
	XWindowAttributes wa;
	XGetWindowAttributes(s.x11.display, s.x11.window, &wa);
	if (wa.map_state == IsViewable) return;
	XMapWindow(s.x11.display, s.x11.window);
	XEvent dummy;
	waitForEvent(VisibilityNotify, 100000000, &dummy);
	XRaiseWindow(s.x11.display, s.x11.window);
	XFlush(s.x11.display);
}

static int windowState(void) {
	int result = WithdrawnState;
	struct {
		CARD32 state;
		Window icon;
	} *state = NULL;
	Atom actualType;
	int actualFormat;
	unsigned long itemCount = 0, bytesAfter;
	XGetWindowProperty(s.x11.display, s.x11.window, s.x11.WM_STATE, 0, LONG_MAX, False, s.x11.WM_STATE, &actualType,
		&actualFormat, &itemCount, &bytesAfter, (unsigned char **)&state);
	if (itemCount >= 2) result = (int)state->state;
	if (state) XFree(state);
	return result;
}

static uint32_t keyModifierBit(VoidKeyCode key) {
	switch (key) {
		case VOID_KEY_LEFT_SHIFT:
		case VOID_KEY_RIGHT_SHIFT: return VOID_MODIFIER_SHIFT;
		case VOID_KEY_LEFT_CONTROL:
		case VOID_KEY_RIGHT_CONTROL: return VOID_MODIFIER_CTRL;
		case VOID_KEY_LEFT_ALT:
		case VOID_KEY_RIGHT_ALT: return VOID_MODIFIER_ALT;
		case VOID_KEY_LEFT_SUPER:
		case VOID_KEY_RIGHT_SUPER: return VOID_MODIFIER_SUPER;
		default: return 0;
	}
}

static uint32_t buttonModifierBit(VoidMouseButton button) {
	switch (button) {
		case VOID_MOUSE_LEFT: return VOID_MODIFIER_LMB;
		case VOID_MOUSE_RIGHT: return VOID_MODIFIER_RMB;
		case VOID_MOUSE_MIDDLE: return VOID_MODIFIER_MMB;
		default: return 0;
	}
}

static uint32_t mods(unsigned int state) {
	uint32_t m = 0;
	if (state & ShiftMask) m |= VOID_MODIFIER_SHIFT;
	if (state & ControlMask) m |= VOID_MODIFIER_CTRL;
	if (state & Mod1Mask) m |= VOID_MODIFIER_ALT;
	if (state & Mod4Mask) m |= VOID_MODIFIER_SUPER;
	if (state & Button1Mask) m |= VOID_MODIFIER_LMB;
	if (state & Button2Mask) m |= VOID_MODIFIER_MMB;
	if (state & Button3Mask) m |= VOID_MODIFIER_RMB;
	return m;
}

static VoidMouseButton translateButton(unsigned int button) {
	switch (button) {
		case Button1: return VOID_MOUSE_LEFT;
		case Button2: return VOID_MOUSE_MIDDLE;
		case Button3: return VOID_MOUSE_RIGHT;
		default: return VOID_MOUSE_INVALID;
	}
}

static void mouseUpdate(int x, int y, bool clearDelta) {
	const float newX = (float)x;
	const float newY = (float)y;
	if (clearDelta) {
		s.mouse.dx = 0.0f;
		s.mouse.dy = 0.0f;
	} else if (s.mouse.posValid) {
		s.mouse.dx = newX - s.mouse.x;
		s.mouse.dy = newY - s.mouse.y;
	}
	s.mouse.x = newX;
	s.mouse.y = newY;
	s.mouse.posValid = true;
}

static void mouseEvent(VoidAppEventType type, VoidMouseButton button, uint32_t modifiers) {
	if (!eventsEnabled()) return;
	initEvent(type);
	s.event.mouseButton = button;
	s.event.modifiers = modifiers;
	callEvent();
}

static void scrollEvent(float x, float y, uint32_t modifiers) {
	if (!eventsEnabled()) return;
	initEvent(VOID_EVENT_MOUSE_SCROLL);
	s.event.modifiers = modifiers;
	s.event.scrollX = x;
	s.event.scrollY = y;
	callEvent();
}

static void keyEvent(VoidAppEventType type, VoidKeyCode key, bool repeat, uint32_t modifiers) {
	if (!eventsEnabled()) return;
	voidKeysHeldTrack(&s.keysHeld, type, key);
	initEvent(type);
	s.event.keyCode = key;
	s.event.keyRepeat = repeat;
	s.event.modifiers = modifiers;
	callEvent();
}

static void charEvent(uint32_t c, bool repeat, uint32_t modifiers) {
	if (!eventsEnabled()) return;
	initEvent(VOID_EVENT_CHAR);
	s.event.charCode = c;
	s.event.keyRepeat = repeat;
	s.event.modifiers = modifiers;
	callEvent();
}

static VoidKeyCode translateKey(int scancode) {
	return scancode >= 0 && scancode < X11_KEYCODES ? (VoidKeyCode)s.keycodes[scancode] : VOID_KEY_INVALID;
}

// Latin-1 and directly encoded UCS keysyms map 1:1, the rest through GLFW's table (sokol_app.h :13631).
static int32_t keysymToUnicode(KeySym keysym) {
	if ((keysym >= 0x0020 && keysym <= 0x007e) || (keysym >= 0x00a0 && keysym <= 0x00ff)) return (int32_t)keysym;
	if ((keysym & 0xff000000) == 0x01000000) return (int32_t)(keysym & 0x00ffffff);
	int min = 0;
	int max = (int)(sizeof keysymTable / sizeof keysymTable[0]) - 1;
	while (max >= min) {
		const int mid = (min + max) / 2;
		if (keysymTable[mid].keysym < keysym) min = mid + 1;
		else if (keysymTable[mid].keysym > keysym) max = mid - 1;
		else return keysymTable[mid].ucs;
	}
	return -1;
}

static bool keypressRepeat(int keycode) {
	if (keycode < 0 || keycode >= X11_KEYCODES) return false;
	const bool repeat = s.x11.keyRepeat[keycode];
	s.x11.keyRepeat[keycode] = true;
	return repeat;
}

static void keyreleaseRepeat(int keycode) {
	if (keycode >= 0 && keycode < X11_KEYCODES) s.x11.keyRepeat[keycode] = false;
}

static void releaseKey(VoidKeyCode key) { keyEvent(VOID_EVENT_KEY_UP, key, false, 0); }

static void onFocus(const XEvent *event, bool focused) {
	if (event->xfocus.mode == NotifyGrab || event->xfocus.mode == NotifyUngrab) return;
	s.x11.windowFocused = focused;
	if (!focused) voidKeysHeldRelease(&s.keysHeld, releaseKey);
	appEvent(focused ? VOID_EVENT_FOCUSED : VOID_EVENT_UNFOCUSED);
}

// X11 reports the modifier state from before the event, so a modifier key's own bit is added on
// press and removed on release (sokol_app.h :13791-13820).
static void onKeyPress(XEvent *event) {
	const int keycode = (int)event->xkey.keycode;
	const VoidKeyCode key = translateKey(keycode);
	const bool repeat = keypressRepeat(keycode);
	const uint32_t modifiers = mods(event->xkey.state) | keyModifierBit(key);
	if (key != VOID_KEY_INVALID) keyEvent(VOID_EVENT_KEY_DOWN, key, repeat, modifiers);
	if (key == VOID_KEY_V && modifiers == VOID_MODIFIER_CTRL) appEvent(VOID_EVENT_CLIPBOARD_PASTED);
	KeySym keysym;
	XLookupString(&event->xkey, NULL, 0, &keysym, NULL);
	const int32_t c = keysymToUnicode(keysym);
	if (c > 0) charEvent((uint32_t)c, repeat, modifiers);
}

static void onKeyRelease(const XEvent *event) {
	const int keycode = (int)event->xkey.keycode;
	const VoidKeyCode key = translateKey(keycode);
	keyreleaseRepeat(keycode);
	if (key != VOID_KEY_INVALID) keyEvent(VOID_EVENT_KEY_UP, key, false, mods(event->xkey.state) & ~keyModifierBit(key));
}

static void onButtonPress(const XEvent *event) {
	mouseUpdate(event->xbutton.x, event->xbutton.y, false);
	const VoidMouseButton button = translateButton(event->xbutton.button);
	const uint32_t modifiers = mods(event->xbutton.state) | buttonModifierBit(button);
	if (button != VOID_MOUSE_INVALID) {
		mouseEvent(VOID_EVENT_MOUSE_DOWN, button, modifiers);
		s.x11.mouseButtons |= (uint8_t)(1 << button);
		return;
	}
	switch (event->xbutton.button) {
		case 4: scrollEvent(0.0f, 1.0f, modifiers); break;
		case 5: scrollEvent(0.0f, -1.0f, modifiers); break;
		case 6: scrollEvent(1.0f, 0.0f, modifiers); break;
		case 7: scrollEvent(-1.0f, 0.0f, modifiers); break;
		default: break;
	}
}

static void onButtonRelease(const XEvent *event) {
	mouseUpdate(event->xbutton.x, event->xbutton.y, false);
	const VoidMouseButton button = translateButton(event->xbutton.button);
	if (button == VOID_MOUSE_INVALID) return;
	mouseEvent(VOID_EVENT_MOUSE_UP, button, mods(event->xbutton.state) & ~buttonModifierBit(button));
	s.x11.mouseButtons &= (uint8_t)~(1 << button);
}

// No enter or leave while a button is held (sokol_app.h :13854).
static void onCrossing(const XEvent *event, VoidAppEventType type) {
	if (s.x11.mouseButtons != 0) return;
	mouseUpdate(event->xcrossing.x, event->xcrossing.y, true);
	mouseEvent(type, VOID_MOUSE_INVALID, mods(event->xcrossing.state));
}

static void onPropertyNotify(const XEvent *event) {
	if (event->xproperty.state != PropertyNewValue || event->xproperty.atom != s.x11.WM_STATE) return;
	const int state = windowState();
	if (state == s.x11.windowState) return;
	s.x11.windowState = state;
	if (state == IconicState) appEvent(VOID_EVENT_ICONIFIED);
	else if (state == NormalState) appEvent(VOID_EVENT_RESTORED);
}

static void sendRootClientMessage(Atom type, long a, long b) {
	XEvent event;
	memset(&event, 0, sizeof event);
	event.type = ClientMessage;
	event.xclient.window = s.x11.window;
	event.xclient.format = 32;
	event.xclient.message_type = type;
	event.xclient.data.l[0] = a;
	event.xclient.data.l[1] = b;
	event.xclient.data.l[3] = 1;
	XSendEvent(s.x11.display, s.x11.root, False, SubstructureNotifyMask | SubstructureRedirectMask, &event);
}

static void setFullscreen(bool enable) {
	if (s.x11.NET_WM_STATE && s.x11.NET_WM_STATE_FULLSCREEN) {
		sendRootClientMessage(s.x11.NET_WM_STATE, enable ? 1 : 0, (long)s.x11.NET_WM_STATE_FULLSCREEN);
	}
	XFlush(s.x11.display);
}

static void createStandardCursor(int cursor, const char *name, const char *theme, int size, unsigned int fallback,
	XcursorLibraryLoadImageFn loadImage, XcursorImageLoadCursorFn loadCursor, XcursorImageDestroyFn destroyImage) {
	if (theme != NULL) {
		XcursorImage *img = loadImage(name, theme, size);
		if (img != NULL) {
			s.x11.standardCursors[cursor] = loadCursor(s.x11.display, img);
			destroyImage(img);
		}
	}
	if (s.x11.standardCursors[cursor] == 0) s.x11.standardCursors[cursor] = XCreateFontCursor(s.x11.display, fallback);
}

static void createCursors(void) {
	const char *theme = NULL;
	int size = 0;
	XcursorLibraryLoadImageFn loadImage = NULL;
	XcursorImageLoadCursorFn loadCursor = NULL;
	XcursorImageDestroyFn destroyImage = NULL;
	void *lib = dlopen("libXcursor.so.1", RTLD_LAZY | RTLD_LOCAL);
	if (lib != NULL) {
		XcursorGetThemeFn getTheme = (XcursorGetThemeFn)dlsym(lib, "XcursorGetTheme");
		XcursorGetDefaultSizeFn getSize = (XcursorGetDefaultSizeFn)dlsym(lib, "XcursorGetDefaultSize");
		loadImage = (XcursorLibraryLoadImageFn)dlsym(lib, "XcursorLibraryLoadImage");
		loadCursor = (XcursorImageLoadCursorFn)dlsym(lib, "XcursorImageLoadCursor");
		destroyImage = (XcursorImageDestroyFn)dlsym(lib, "XcursorImageDestroy");
		if (getTheme && getSize && loadImage && loadCursor && destroyImage) {
			theme = getTheme(s.x11.display);
			size = getSize(s.x11.display);
		}
	}
	createStandardCursor(VOID_CURSOR_ARROW, "default", theme, size, XC_left_ptr, loadImage, loadCursor, destroyImage);
	createStandardCursor(VOID_CURSOR_IBEAM, "text", theme, size, XC_xterm, loadImage, loadCursor, destroyImage);
	createStandardCursor(VOID_CURSOR_CROSSHAIR, "crosshair", theme, size, XC_crosshair, loadImage, loadCursor, destroyImage);
	createStandardCursor(VOID_CURSOR_POINTING_HAND, "pointer", theme, size, XC_hand2, loadImage, loadCursor, destroyImage);
	createStandardCursor(VOID_CURSOR_RESIZE_EW, "ew-resize", theme, size, XC_sb_h_double_arrow, loadImage, loadCursor, destroyImage);
	createStandardCursor(VOID_CURSOR_RESIZE_NS, "ns-resize", theme, size, XC_sb_v_double_arrow, loadImage, loadCursor, destroyImage);
	createStandardCursor(VOID_CURSOR_RESIZE_NWSE, "nwse-resize", theme, size, XC_top_left_corner, loadImage, loadCursor, destroyImage);
	createStandardCursor(VOID_CURSOR_RESIZE_NESW, "nesw-resize", theme, size, XC_top_right_corner, loadImage, loadCursor, destroyImage);
	createStandardCursor(VOID_CURSOR_RESIZE_ALL, "all-scroll", theme, size, XC_fleur, loadImage, loadCursor, destroyImage);
	createStandardCursor(VOID_CURSOR_NOT_ALLOWED, "not-allowed", theme, size, XC_pirate, loadImage, loadCursor, destroyImage);
	static const char blank[1] = { 0 };
	Pixmap bitmap = XCreateBitmapFromData(s.x11.display, s.x11.root, blank, 1, 1);
	XColor black;
	memset(&black, 0, sizeof black);
	s.x11.hiddenCursor = XCreatePixmapCursor(s.x11.display, bitmap, bitmap, &black, &black, 0, 0);
	XFreePixmap(s.x11.display, bitmap);
}

static void destroyCursors(void) {
	if (s.x11.hiddenCursor) XFreeCursor(s.x11.display, s.x11.hiddenCursor);
	for (int i = 0; i < VOID_CURSOR_COUNT; i++) {
		if (s.x11.standardCursors[i]) XFreeCursor(s.x11.display, s.x11.standardCursors[i]);
	}
}

static void updateCursor(void) {
	if (!s.x11.window) return;
	if (!s.mouse.shown) XDefineCursor(s.x11.display, s.x11.window, s.x11.hiddenCursor);
	else if (s.x11.standardCursors[s.mouse.cursor]) XDefineCursor(s.x11.display, s.x11.window, s.x11.standardCursors[s.mouse.cursor]);
	else XUndefineCursor(s.x11.display, s.x11.window);
	XFlush(s.x11.display);
}

static void selectRawMotion(bool enable) {
	if (!s.x11.xi.available) return;
	unsigned char mask[XIMaskLen(XI_RawMotion)] = { 0 };
	if (enable) XISetMask(mask, XI_RawMotion);
	XIEventMask em;
	em.deviceid = XIAllMasterDevices;
	em.mask_len = sizeof mask;
	em.mask = mask;
	s.x11.xi.SelectEvents(s.x11.display, s.x11.root, &em, 1);
}

static void doLockMouse(void) {
	const int result = XGrabPointer(s.x11.display, s.x11.window, True,
		ButtonPressMask | ButtonReleaseMask | PointerMotionMask, GrabModeAsync, GrabModeAsync, s.x11.window,
		s.x11.hiddenCursor, CurrentTime);
	if (result != GrabSuccess) return;
	s.mouse.locked = true;
	s.mouse.dx = 0.0f;
	s.mouse.dy = 0.0f;
	selectRawMotion(true);
}

static void doUnlockMouse(void) {
	selectRawMotion(false);
	s.mouse.dx = 0.0f;
	s.mouse.dy = 0.0f;
	s.mouse.locked = false;
	XWarpPointer(s.x11.display, None, s.x11.window, 0, 0, 0, 0, (int)s.mouse.x, (int)s.mouse.y);
	XUngrabPointer(s.x11.display, CurrentTime);
}

static void updateMouseLock(void) {
	if (!s.x11.windowFocused) {
		if (s.mouse.locked) doUnlockMouse();
		return;
	}
	if (s.mouse.requestedLock == s.mouse.locked) return;
	if (s.mouse.requestedLock) doLockMouse();
	else doUnlockMouse();
}

static void onGenericEvent(XEvent *event) {
	if (!s.mouse.locked || !s.x11.xi.available || event->xcookie.extension != s.x11.xi.majorOpcode) return;
	if (!XGetEventData(s.x11.display, &event->xcookie)) return;
	if (event->xcookie.evtype == XI_RawMotion) {
		const XIRawEvent *raw = (const XIRawEvent *)event->xcookie.data;
		if (raw->valuators.mask_len) {
			const double *values = raw->raw_values;
			if (XIMaskIsSet(raw->valuators.mask, 0)) s.mouse.dx = (float)*values++;
			if (XIMaskIsSet(raw->valuators.mask, 1)) s.mouse.dy = (float)*values;
			Window rootReturn, childReturn;
			int rootX, rootY, winX, winY;
			unsigned int state = 0;
			XQueryPointer(s.x11.display, s.x11.window, &rootReturn, &childReturn, &rootX, &rootY, &winX, &winY, &state);
			mouseEvent(VOID_EVENT_MOUSE_MOVE, VOID_MOUSE_INVALID, mods(state));
		}
	}
	XFreeEventData(s.x11.display, &event->xcookie);
}

static unsigned long windowProperty(Window window, Atom property, Atom type, unsigned char **value) {
	Atom actualType;
	int actualFormat;
	unsigned long itemCount, bytesAfter;
	XGetWindowProperty(s.x11.display, window, property, 0, LONG_MAX, False, type, &actualType, &actualFormat,
		&itemCount, &bytesAfter, value);
	return itemCount;
}

static void clearDropped(void) {
	for (int i = 0; i < s.droppedCount; i++) free(s.droppedPaths[i]);
	free(s.droppedPaths);
	s.droppedPaths = NULL;
	s.droppedCount = 0;
}

static bool parseDroppedFilesList(const char *src) {
	clearDropped();
	size_t lines = 1;
	for (const char *p = src; *p; p++) if (*p == '\n') lines++;
	s.droppedPaths = (char **)calloc(lines, sizeof(char *));
	if (s.droppedPaths == NULL) fail("calloc for the dropped file paths");
	const char *p = src;
	while (*p) {
		const char *end = p;
		while (*end && *end != '\r' && *end != '\n') end++;
		if (end > p) {
			if (strncmp(p, "file://", 7) != 0 || end - p < 7) {
				fprintf(stderr, "void: a dropped file uri has the wrong scheme\n");
				clearDropped();
				return false;
			}
			char *path = (char *)malloc((size_t)(end - p) + 1);
			if (path == NULL) fail("malloc for a dropped file path");
			char *dst = path;
			for (const char *c = p + 7; c < end; c++) {
				if (*c == '%' && c + 2 < end) {
					const char digits[3] = { c[1], c[2], 0 };
					*dst++ = (char)strtol(digits, NULL, 16);
					c += 2;
				} else {
					*dst++ = *c;
				}
			}
			*dst = 0;
			s.droppedPaths[s.droppedCount++] = path;
		}
		p = end;
		while (*p == '\r' || *p == '\n') p++;
	}
	return true;
}

static void sendXdndReply(Atom type, long accepted, long action) {
	XEvent reply;
	memset(&reply, 0, sizeof reply);
	reply.type = ClientMessage;
	reply.xclient.window = s.x11.xdnd.source;
	reply.xclient.message_type = type;
	reply.xclient.format = 32;
	reply.xclient.data.l[0] = (long)s.x11.window;
	reply.xclient.data.l[1] = accepted;
	if (type == s.x11.xdnd.XdndStatus) {
		if (accepted && s.x11.xdnd.version >= 2) reply.xclient.data.l[4] = action;
	} else {
		reply.xclient.data.l[2] = action;
	}
	XSendEvent(s.x11.display, s.x11.xdnd.source, False, NoEventMask, &reply);
	XFlush(s.x11.display);
}

static void onSelectionNotify(const XEvent *event) {
	if (event->xselection.property != s.x11.xdnd.XdndSelection) return;
	char *data = NULL;
	const unsigned long result = windowProperty(event->xselection.requestor, event->xselection.property,
		event->xselection.target, (unsigned char **)&data);
	if (result && data != NULL && parseDroppedFilesList(data)) {
		s.mouse.dx = 0.0f;
		s.mouse.dy = 0.0f;
		appEvent(VOID_EVENT_FILES_DROPPED);
	}
	if (s.x11.xdnd.version >= 2) sendXdndReply(s.x11.xdnd.XdndFinished, (long)result, (long)s.x11.xdnd.XdndActionCopy);
	if (data) XFree(data);
}

static void onXdndEnter(const XEvent *event) {
	const bool isList = (event->xclient.data.l[1] & 1) != 0;
	s.x11.xdnd.source = (Window)event->xclient.data.l[0];
	s.x11.xdnd.version = event->xclient.data.l[1] >> 24;
	s.x11.xdnd.format = None;
	if (s.x11.xdnd.version > XDND_VERSION) return;
	unsigned long count;
	Atom *formats = NULL;
	if (isList) {
		count = windowProperty(s.x11.xdnd.source, s.x11.xdnd.XdndTypeList, XA_ATOM, (unsigned char **)&formats);
	} else {
		count = 3;
		formats = (Atom *)event->xclient.data.l + 2;
	}
	for (unsigned long i = 0; i < count; i++) {
		if (formats[i] == s.x11.xdnd.textUriList) {
			s.x11.xdnd.format = s.x11.xdnd.textUriList;
			break;
		}
	}
	if (isList && formats) XFree(formats);
}

static void onXdndDrop(const XEvent *event) {
	if (s.x11.xdnd.version > XDND_VERSION) return;
	if (s.x11.xdnd.format) {
		const Time time = s.x11.xdnd.version >= 1 ? (Time)event->xclient.data.l[2] : CurrentTime;
		XConvertSelection(s.x11.display, s.x11.xdnd.XdndSelection, s.x11.xdnd.format, s.x11.xdnd.XdndSelection,
			s.x11.window, time);
	} else if (s.x11.xdnd.version >= 2) {
		sendXdndReply(s.x11.xdnd.XdndFinished, 0, None);
	}
}

static void onXdndPosition(void) {
	if (s.x11.xdnd.version > XDND_VERSION) return;
	sendXdndReply(s.x11.xdnd.XdndStatus, s.x11.xdnd.format ? 1 : 0, (long)s.x11.xdnd.XdndActionCopy);
}

static void onSelectionRequest(const XEvent *event) {
	const XSelectionRequestEvent *req = &event->xselectionrequest;
	if (req->selection != s.x11.CLIPBOARD || s.clipboard == NULL) return;
	XSelectionEvent reply;
	memset(&reply, 0, sizeof reply);
	reply.type = SelectionNotify;
	reply.display = req->display;
	reply.requestor = req->requestor;
	reply.selection = req->selection;
	reply.target = req->target;
	reply.property = req->property;
	reply.time = req->time;
	if (req->target == s.x11.UTF8_STRING) {
		XChangeProperty(s.x11.display, req->requestor, req->property, s.x11.UTF8_STRING, 8, PropModeReplace,
			(const unsigned char *)s.clipboard, (int)strlen(s.clipboard));
	} else if (req->target == s.x11.TARGETS) {
		XChangeProperty(s.x11.display, req->requestor, req->property, XA_ATOM, 32, PropModeReplace,
			(const unsigned char *)&s.x11.UTF8_STRING, 1);
	} else {
		reply.property = None;
	}
	XSendEvent(s.x11.display, req->requestor, False, 0, (XEvent *)&reply);
}

static void onClientMessage(XEvent *event) {
	if (XFilterEvent(event, None)) return;
	const Atom type = event->xclient.message_type;
	if (type == s.x11.WM_PROTOCOLS) {
		if ((Atom)event->xclient.data.l[0] == s.x11.WM_DELETE_WINDOW) s.quitRequested = true;
	} else if (type == s.x11.xdnd.XdndEnter) {
		onXdndEnter(event);
	} else if (type == s.x11.xdnd.XdndDrop) {
		onXdndDrop(event);
	} else if (type == s.x11.xdnd.XdndPosition) {
		onXdndPosition();
	}
}

static void processEvent(XEvent *event) {
	switch (event->type) {
		case FocusIn: onFocus(event, true); break;
		case FocusOut: onFocus(event, false); break;
		case KeyPress: onKeyPress(event); break;
		case KeyRelease: onKeyRelease(event); break;
		case ButtonPress: onButtonPress(event); break;
		case ButtonRelease: onButtonRelease(event); break;
		case EnterNotify: onCrossing(event, VOID_EVENT_MOUSE_ENTER); break;
		case LeaveNotify: onCrossing(event, VOID_EVENT_MOUSE_LEAVE); break;
		case MotionNotify:
			if (s.mouse.locked) break;
			mouseUpdate(event->xmotion.x, event->xmotion.y, false);
			mouseEvent(VOID_EVENT_MOUSE_MOVE, VOID_MOUSE_INVALID, mods(event->xmotion.state));
			break;
		case GenericEvent: onGenericEvent(event); break;
		case SelectionNotify: onSelectionNotify(event); break;
		case SelectionRequest: onSelectionRequest(event); break;
		case PropertyNotify: onPropertyNotify(event); break;
		case ClientMessage: onClientMessage(event); break;
		default: break;
	}
}

static void frame(void) {
	updateDimensionsFromWindowSize();
	if (s.firstFrame) {
		s.firstFrame = false;
		if (s.desc.init) s.desc.init();
		s.initCalled = true;
	}
	if (!s.cleanupCalled && s.desc.frame) s.desc.frame();
	s.frameCount++;
}

void voidLinuxRun(const VoidLinuxDesc *desc) {
	memset(&s, 0, sizeof s);
	s.desc = *desc;
	s.firstFrame = true;
	voidFrameTimingInit(&s.timing);
	s.windowWidth = s.framebufferWidth = desc->width;
	s.windowHeight = s.framebufferHeight = desc->height;
	s.x11.windowState = NormalState;
	XInitThreads();
	XrmInitialize();
	s.x11.display = XOpenDisplay(NULL);
	if (s.x11.display == NULL) fail("XOpenDisplay() failed");
	s.x11.screen = DefaultScreen(s.x11.display);
	s.x11.root = DefaultRootWindow(s.x11.display);
	querySystemDpi();
	s.dpiScale = s.x11.dpi / 96.0f;
	s.mouse.shown = true;
	initAtoms();
	initXinput();
	createCursors();
	XkbSetDetectableAutoRepeat(s.x11.display, True, NULL);
	initKeytable();
	initGlx();
	Visual *visual = NULL;
	int depth = 0;
	chooseVisual(&visual, &depth);
	createWindow(visual, depth);
	createContext();
	swapInterval(1);
	s.valid = true;
	showWindow();
	XFlush(s.x11.display);
	while (!s.quitOrdered) {
		voidFrameTimingUpdate(&s.timing, 0.0);
		int count = XPending(s.x11.display);
		while (count--) {
			XEvent event;
			XNextEvent(s.x11.display, &event);
			processEvent(&event);
		}
		frame();
		updateMouseLock();
		XFlush(s.x11.display);
		if (s.quitRequested && !s.quitOrdered) {
			appEvent(VOID_EVENT_QUIT_REQUESTED);
			if (s.quitRequested) s.quitOrdered = true;
		}
	}
	if (!s.cleanupCalled) {
		if (s.desc.cleanup) s.desc.cleanup();
		s.cleanupCalled = true;
	}
	destroyContext();
	destroyWindow();
	destroyCursors();
	clearDropped();
	free(s.clipboard);
	XCloseDisplay(s.x11.display);
	memset(&s, 0, sizeof s);
}

bool voidLinuxValid(void) { return s.valid; }
int voidLinuxWidth(void) { return s.framebufferWidth > 0 ? s.framebufferWidth : 1; }
int voidLinuxHeight(void) { return s.framebufferHeight > 0 ? s.framebufferHeight : 1; }
float voidLinuxDpiScale(void) { return s.dpiScale; }
uint64_t voidLinuxFrameCount(void) { return s.frameCount; }
void voidLinuxRequestQuit(void) { s.quitRequested = true; }
void voidLinuxSetTitle(const char *title) { updateWindowTitle(title); }
void voidLinuxSwapBuffers(void) { s.glx.SwapBuffers(s.x11.display, s.glx.window); }


void voidLinuxCancelQuit(void) { s.quitRequested = false; }
double voidLinuxFrameDuration(void) { return s.timing.smoothDt; }
void voidLinuxSetClipboard(const char *utf8) {
	char *copy = strdup(utf8);
	if (copy == NULL) fail("strdup for the clipboard");
	free(s.clipboard);
	s.clipboard = copy;
	XSetSelectionOwner(s.x11.display, s.x11.CLIPBOARD, s.x11.window, CurrentTime);
	if (XGetSelectionOwner(s.x11.display, s.x11.CLIPBOARD) != s.x11.window) fail("becoming the owner of the clipboard");
}

const char *voidLinuxClipboard(void) {
	if (s.clipboard == NULL) s.clipboard = strdup("");
	if (s.clipboard == NULL) fail("strdup for the clipboard");
	if (XGetSelectionOwner(s.x11.display, s.x11.CLIPBOARD) == s.x11.window) return s.clipboard;
	Atom property = XInternAtom(s.x11.display, "VOID_SELECTION", False);
	Atom incremental = XInternAtom(s.x11.display, "INCR", False);
	XConvertSelection(s.x11.display, s.x11.CLIPBOARD, s.x11.UTF8_STRING, property, s.x11.window, CurrentTime);
	XEvent event;
	if (!waitForEvent(SelectionNotify, 100000000, &event) || event.xselection.property == None) return s.clipboard;
	char *data = NULL;
	Atom actualType;
	int actualFormat;
	unsigned long itemCount, bytesAfter;
	const int status = XGetWindowProperty(s.x11.display, event.xselection.requestor, event.xselection.property, 0,
		LONG_MAX, True, s.x11.UTF8_STRING, &actualType, &actualFormat, &itemCount, &bytesAfter, (unsigned char **)&data);
	if (status != Success || data == NULL) {
		if (data) XFree(data);
		return s.clipboard;
	}
	if (actualType == incremental) {
		fprintf(stderr, "void: the clipboard owner sends its string in increments, which is not supported\n");
	} else {
		char *copy = strdup(data);
		if (copy == NULL) fail("strdup for the clipboard");
		free(s.clipboard);
		s.clipboard = copy;
	}
	XFree(data);
	return s.clipboard;
}

void voidLinuxSetCursor(int cursor) {
	s.mouse.cursor = cursor;
	updateCursor();
}

int voidLinuxCursor(void) { return s.mouse.cursor; }

void voidLinuxShowMouse(bool shown) {
	s.mouse.shown = shown;
	updateCursor();
}

bool voidLinuxMouseShown(void) { return s.mouse.shown; }
void voidLinuxLockMouse(bool locked) { s.mouse.requestedLock = locked; }
bool voidLinuxMouseLocked(void) { return s.mouse.locked; }

void voidLinuxToggleFullscreen(void) {
	s.fullscreen = !s.fullscreen;
	setFullscreen(s.fullscreen);
	updateDimensionsFromWindowSize();
}

bool voidLinuxIsFullscreen(void) { return s.fullscreen; }
int voidLinuxDroppedCount(void) { return s.droppedCount; }

const char *voidLinuxDroppedPath(int i) {
	if (i < 0 || i >= s.droppedCount) fail("the dropped file index is out of range");
	return s.droppedPaths[i];
}
