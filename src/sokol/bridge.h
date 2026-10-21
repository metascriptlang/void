// Void sokol bridge — thin 1:1 wrappers over sokol_gfx/sokol_app.
// Render sequencing lives in MetaScript (src/void2d, src/void3d); this file only
// builds sokol descriptor structs (which FFI can't) and maps handles ↔ uint32.
#ifndef VOID_SOKOL_BRIDGE_H
#define VOID_SOKOL_BRIDGE_H

#include <stdint.h>

#ifndef MS_CLOSURE_DEFINED
#define MS_CLOSURE_DEFINED
typedef struct {
	void *fn;
	void *env;
} msClosure;
#endif

// Lifecycle — MetaScript main() drives via init/frame closures.
void voidRun(int w, int h, msClosure init, msClosure frame);

// Same, with the two window knobs a capture harness has to pin (tests/golden/runner.ms):
// `sampleCount` is the swapchain sample count — 1 is what iOS, Android and the embed
// bridges already use, so a golden taken at 1 is the one every backend can be compared
// against (guardrail 9); `highDpi` 0 makes the framebuffer exactly w x h and
// voidDpiScale() 1.0 whatever the host display reports.
void voidRunConfigured(int w, int h, int sampleCount, int highDpi, msClosure init, msClosure frame);

// The window size voidRunConfigured asked the host for; 0 when no windowed run started.
// Read-only: the OS may lawfully clamp a window (a minimum client width); the framebuffer
// is the truth a frame must follow, and this getter only lets a test compare the two.
void voidRequestedSize(int *w, int *h);

// The sokol_app window (bridgeWin.c, bridgeWeb.c, bridgeIosApp.m). Once a handler is set, every sapp_event
// calls it and Escape no longer quits; the voidEvent* getters read the event it was called
// for. The title may be set before or after voidRun.
void voidSetEventHandler(msClosure handler);
int voidEventType(void);
int voidEventKeyCode(void);
uint32_t voidEventCharCode(void);
int voidEventKeyRepeat(void);
uint32_t voidEventModifiers(void);
int voidEventMouseButton(void);
float voidEventMouseX(void);
float voidEventMouseY(void);
float voidEventMouseDx(void);
float voidEventMouseDy(void);
float voidEventScrollX(void);
float voidEventScrollY(void);
int voidEventFramebufferWidth(void);
int voidEventFramebufferHeight(void);
int voidEventCursor(void);
void voidSetWindowTitle(const char *title);
// The touch points of a Touches* event, in framebuffer pixels; `changed` is 1 for the points
// this event began, moved, ended or cancelled.
int voidEventTouchCount(void);
int64_t voidEventTouchId(int index);
float voidEventTouchX(int index);
float voidEventTouchY(int index);
int voidEventTouchChanged(int index);
// The area a host keeps content off (the iOS home indicator and notch), in framebuffer pixels
// from each edge; 0 on drivers that have none. Resized follows a change.
float voidSafeAreaTop(void);
float voidSafeAreaLeft(void);
float voidSafeAreaBottom(void);
float voidSafeAreaRight(void);

// IME composition (Windows window, browser and iOS). While text input is on and a handler is set,
// a composition arrives as Preedit events and its result as one TextInput event, never also
// as Char. Off disables the IME on Windows and blurs the browser's input element. Before the
// first call the window keeps sokol_app's default: the OS composes in its own window and the
// result arrives as Char. The rect is the caret in framebuffer pixels; the candidate window
// opens below it.
void voidSetTextInput(int on);
void voidSetImeRect(int x, int y, int w, int h);

typedef int VoidViewId;
void voidEmbedRegister(msClosure init, msClosure frame);
void voidViewsSetSampleCount(int count);
VoidViewId voidViewCreate(long long native, int w, int h, float scale);
void voidViewResize(VoidViewId v, int w, int h, float scale);
int voidViewFrame(VoidViewId v);
void voidViewDestroy(VoidViewId v);
long long voidViewSwapChain(VoidViewId v);
VoidViewId voidCurrentView(void);
void voidEmbedSetMessagePump(msClosure pump);
void voidEmbedPumpMessages(void);

int voidGpuGeneration(void);
void voidLoseContext(void);
void voidEmbedLoseContext(void);
void voidEmbedDetach(void);
void voidEmbedSetAssetRoot(const char *path);

// Browser only: defines Module.voidStart(canvas), which returns a stop (bridgeWeb.c).
void voidWebInstall(void);

void voidGfxSetup(void);
int voidFbWidth(void);
int voidFbHeight(void);
float voidDpiScale(void);
int voidKeyDown(int keycode);

// Resource creation — sokol handles returned as uint32 ids (0 = invalid).
uint32_t voidMakeImage(const void *rgba, int w, int h);
uint32_t voidMakeView(uint32_t image);

// Frame sequence.
void voidSetCommitHook(void (*fn)(void));
void voidSetPresentHook(void (*fn)(int begin));

#endif
