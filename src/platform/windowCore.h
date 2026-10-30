// The state, event plumbing and getters every platform window shares, ported from sokol_app.h's
// _sapp and its helpers (pin 2e75443d, :3463-3700, getters :14431-14819). One window runs per
// process: the platform window the build compiles defines voidWindow and the functions below
// that need its native API.
#ifndef VOID_PLATFORM_WINDOW_CORE_H
#define VOID_PLATFORM_WINDOW_CORE_H

#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "appEvent.h"
#include "frameTiming.h"

typedef struct {
	void (*initCb)(void);
	void (*frameCb)(void);
	void (*eventCb)(const VoidAppEvent *e);
	void (*cleanupCb)(void);
	bool valid;
	bool initCalled;
	bool cleanupCalled;
	bool quitRequested;
	bool quitOrdered;
	bool eventConsumed;
	bool fullscreen;
	uint64_t frameCount;
	float dpiScale;
	int windowWidth;
	int windowHeight;
	int framebufferWidth;
	int framebufferHeight;
	struct {
		float x, y, dx, dy;
		bool posValid;
		bool shown;
		bool locked;
		bool requestedLock;
		int cursor;
	} mouse;
	VoidFrameTiming timing;
	int droppedCount;
	char **droppedPaths;
	char *clipboard;
	VoidKeysHeld keysHeld;
	VoidAppEvent event;
} VoidWindow;

extern VoidWindow voidWindow;

static inline void voidWindowStart(void (*init)(void), void (*frame)(void), void (*event)(const VoidAppEvent *e),
	void (*cleanup)(void), int width, int height) {
	memset(&voidWindow, 0, sizeof voidWindow);
	voidWindow.initCb = init;
	voidWindow.frameCb = frame;
	voidWindow.eventCb = event;
	voidWindow.cleanupCb = cleanup;
	voidWindow.windowWidth = voidWindow.framebufferWidth = width;
	voidWindow.windowHeight = voidWindow.framebufferHeight = height;
	voidWindow.dpiScale = 1.0f;
	voidWindow.mouse.shown = true;
	voidFrameTimingInit(&voidWindow.timing);
}

static inline bool voidWindowEventsEnabled(void) { return voidWindow.eventCb != NULL && voidWindow.initCalled; }

static inline void voidWindowInitEvent(VoidAppEventType type) {
	memset(&voidWindow.event, 0, sizeof voidWindow.event);
	voidWindow.event.type = type;
	voidWindow.event.frameCount = voidWindow.frameCount;
	voidWindow.event.mouseButton = VOID_MOUSE_INVALID;
	voidWindow.event.windowWidth = voidWindow.windowWidth;
	voidWindow.event.windowHeight = voidWindow.windowHeight;
	voidWindow.event.framebufferWidth = voidWindow.framebufferWidth;
	voidWindow.event.framebufferHeight = voidWindow.framebufferHeight;
	voidWindow.event.mouseX = voidWindow.mouse.x;
	voidWindow.event.mouseY = voidWindow.mouse.y;
	voidWindow.event.mouseDx = voidWindow.mouse.dx;
	voidWindow.event.mouseDy = voidWindow.mouse.dy;
}

static inline bool voidWindowCallEvent(void) {
	if (!voidWindow.cleanupCalled) voidWindow.eventCb(&voidWindow.event);
	const bool consumed = voidWindow.eventConsumed;
	voidWindow.eventConsumed = false;
	return consumed;
}

static inline void voidWindowAppEvent(VoidAppEventType type) {
	if (!voidWindowEventsEnabled()) return;
	voidWindowInitEvent(type);
	voidWindowCallEvent();
}

static inline void voidWindowFrame(void) {
	if (!voidWindow.initCalled) {
		if (voidWindow.initCb) voidWindow.initCb();
		voidWindow.initCalled = true;
	}
	if (!voidWindow.cleanupCalled && voidWindow.frameCb) voidWindow.frameCb();
	voidWindow.frameCount++;
}

static inline void voidWindowCleanup(void) {
	if (voidWindow.cleanupCalled) return;
	if (voidWindow.cleanupCb) voidWindow.cleanupCb();
	voidWindow.cleanupCalled = true;
}

static inline void voidWindowAskQuit(void) {
	if (voidWindow.quitOrdered) return;
	voidWindow.quitRequested = true;
	voidWindowAppEvent(VOID_EVENT_QUIT_REQUESTED);
	if (voidWindow.quitRequested) voidWindow.quitOrdered = true;
}

static inline void voidWindowClearDropped(void) {
	for (int i = 0; i < voidWindow.droppedCount; i++) free(voidWindow.droppedPaths[i]);
	free(voidWindow.droppedPaths);
	voidWindow.droppedPaths = NULL;
	voidWindow.droppedCount = 0;
}

static inline void voidWindowBeginDrop(size_t capacity) {
	voidWindowClearDropped();
	voidWindow.droppedPaths = (char **)calloc(capacity > 0 ? capacity : 1, sizeof(char *));
	if (voidWindow.droppedPaths == NULL) {
		fputs("void: calloc for the dropped file paths\n", stderr);
		abort();
	}
}

static inline void voidWindowEnd(void) {
	voidWindowClearDropped();
	free(voidWindow.clipboard);
	memset(&voidWindow, 0, sizeof voidWindow);
}

static inline bool voidWindowValid(void) { return voidWindow.valid; }
static inline int voidWindowWidth(void) { return voidWindow.framebufferWidth > 0 ? voidWindow.framebufferWidth : 1; }
static inline int voidWindowHeight(void) { return voidWindow.framebufferHeight > 0 ? voidWindow.framebufferHeight : 1; }
static inline float voidWindowDpiScale(void) { return voidWindow.dpiScale; }
static inline uint64_t voidWindowFrameCount(void) { return voidWindow.frameCount; }
static inline void voidWindowRequestQuit(void) { voidWindow.quitRequested = true; }
static inline void voidWindowCancelQuit(void) { voidWindow.quitRequested = false; }
static inline double voidWindowFrameDuration(void) { return voidWindow.timing.smoothDt; }
static inline int voidWindowCursor(void) { return voidWindow.mouse.cursor; }
static inline bool voidWindowMouseShown(void) { return voidWindow.mouse.shown; }
static inline bool voidWindowMouseLocked(void) { return voidWindow.mouse.locked; }
static inline bool voidWindowIsFullscreen(void) { return voidWindow.fullscreen; }
static inline int voidWindowDroppedCount(void) { return voidWindow.droppedCount; }
static inline const char *voidWindowDroppedPath(int i) { return voidWindow.droppedPaths[i]; }

void voidWindowSetTitle(const char *title);
void voidWindowSetClipboard(const char *utf8);
const char *voidWindowClipboard(void);
void voidWindowSetCursor(int cursor);
void voidWindowShowMouse(bool shown);
void voidWindowLockMouse(bool locked);
void voidWindowToggleFullscreen(void);

#endif
