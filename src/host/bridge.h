// Void bridge — the window, the frame sequence and two resource helpers over the GPU door
// (src/gpu/door.h). Render sequencing lives in MetaScript (src/void2d, src/void3d).
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

static inline void voidCallClosure(msClosure c) {
	if (!c.fn) return;
	if (c.env) ((void (*)(void *))c.fn)(c.env);
	else ((void (*)(void))c.fn)();
}

__attribute__((noreturn, format(printf, 1, 2))) void voidFail(const char *fmt, ...);

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

// The window (bridgeWin.c, bridgeWeb.c, bridgeIosApp.m). Once a handler is set, every window event
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
// bevy_window's PresentMode, before voidRun: 0 AutoVsync, the default, or 1 AutoNoVsync, which
// presents without waiting for the display where the driver can (tearing, else a flip that
// replaces the queued frame) and with vsync where it cannot (the browser, Metal, Android).
void voidSetPresentMode(int mode);
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
// How far a docked software keyboard covers the view from its bottom edge, in framebuffer
// pixels; 0 when it is hidden or floating, and on drivers that have none. Resized follows a change.
float voidKeyboardHeight(void);

// What sokol_app offers beyond events (src/host/appWindow.ms over the window drivers: Windows,
// the browser and Linux). A feature a driver has not ported aborts naming the feature and the
// platform. Every call needs the window to exist, so make it from the handler or after init.
// voidRequestQuit sends QuitRequested to the handler on the next frame, and voidCancelQuit
// from that handler (or before it arrives) keeps the app running; without a handler the app
// quits. A browser tab has no close request, so QuitRequested there follows voidRequestQuit only.
void voidRequestQuit(void);
void voidCancelQuit(void);
double voidFrameDuration(void);

// The clipboard is UTF-8 text. voidClipboard is what the last ClipboardPasted event carried in
// the browser; native it is the clipboard now. The browser can write only from an event handler.
void voidSetClipboard(const char *utf8);

// Cursor ordinals are VoidMouseCursor (src/platform/appEvent.h).
void voidSetMouseCursor(int cursor);
int voidMouseCursor(void);
void voidShowMouse(int shown);
int voidMouseShown(void);

// Locked, the pointer is hidden and confined and the mouse events carry only dx and dy. The
// browser grants a lock from a mouse button or wheel event only.
void voidLockMouse(int locked);
int voidMouseLocked(void);

void voidToggleFullscreen(void);
int voidIsFullscreen(void);

// The files of the last FilesDropped event. The browser gives file names, not paths.
int voidDroppedFileCount(void);

// IME composition (Windows window, browser and iOS). While text input is on and a handler is set,
// a composition arrives as Preedit events and its result as one TextInput event, never also
// as Char. Off disables the IME on Windows and blurs the browser's input element. Before the
// first call the window keeps the OS default: the OS composes in its own window and the
// result arrives as Char. The rect is the caret in framebuffer pixels; the candidate window
// opens below it.
void voidSetTextInput(int on);
void voidSetImeRect(int x, int y, int w, int h);

void voidEmbedRegister(msClosure init, msClosure frame);
void voidEmbedSetMessagePump(msClosure pump);
void voidEmbedPumpMessages(void);

// A lost context (or voidLoseContext) shuts the door down at the driver's next frame, which
// then calls `setup` to set the door up again.
void voidLoseContext(void);
void voidRestoreContextIfLost(void (*setup)(void));
void voidEmbedLoseContext(void);
void voidEmbedDetach(void);
void voidEmbedSetAssetRoot(const char *path);

// Browser only: defines Module.voidStart(canvas), which returns a stop (bridgeWeb.c).
void voidWebInstall(void);

typedef enum { VOID_DRIVER_NONE, VOID_DRIVER_WINDOW, VOID_DRIVER_VIEWS } VoidDriver;
// The desktop bridges' driver (bridge.c): voidRun chooses the window, voidViewCreate the host
// views. voidDriverFor stops naming `op` before either, or while the window does not exist.
extern VoidDriver voidDriver;
VoidDriver voidDriverFor(const char *op);
void voidWindowDoorSetup(void);

void voidGfxSetup(void);
int voidFbWidth(void);
int voidFbHeight(void);
float voidDpiScale(void);
int voidKeyDown(int keycode);

// Resource creation — door ids (0 = invalid).
uint32_t voidMakeImage(const void *rgba, int w, int h);
uint32_t voidMakeView(uint32_t image);

#endif
