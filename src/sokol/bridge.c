// Void bridge — the frame sequence and the two resource helpers every driver shares, over the
// GPU door (src/gpu/door.h). The driver (bridgeWin.c, bridgeIos.m, bridgeAndroid.c) owns the
// device and the swapchain.

#include "bridge.h"
#include "views.h"
#include "../gpu/door.h"

#include <stdbool.h>
#include <stdio.h>
#include <stdlib.h>

// The door's GPU submit, which only voidCommit calls, so no consumer can end a frame around the
// commit hook (door.h offers doorCommit).
void doorSubmitFrame(void);

// --- Resource creation (door ids, 0 = invalid) ---

uint32_t voidMakeImage(const void *rgba, int w, int h) {
	static const uint8_t white[4] = {255, 255, 255, 255};
	if (rgba == NULL || w <= 0 || h <= 0) { rgba = white; w = 1; h = 1; }
	return doorMakeTexture(w, h, DOOR_PIXEL_FORMAT_RGBA8, (const uint8_t *)rgba, (int64_t)w * h * 4);
}

uint32_t voidMakeView(uint32_t image) {
	return doorMakeTextureView(image);
}

// --- Context loss ---

static bool s_contextLost;

void voidLoseContext(void) { s_contextLost = true; }

void voidRestoreContextIfLost(void (*setup)(void)) {
	if (!s_contextLost) return;
	doorShutdown();
	setup();
	s_contextLost = false;
}

// --- Frame sequence ---

void voidBeginPass(float r, float g, float b, float a) {
	doorBeginScreenPass(r, g, b, a);
}

static void (*s_commitHook)(void);
static void (*s_presentHook)(int begin);
void voidSetCommitHook(void (*fn)(void)) { s_commitHook = fn; }
void voidSetPresentHook(void (*fn)(int begin)) { s_presentHook = fn; }
void voidCommit(void) {
	doorSubmitFrame();
	if (s_commitHook) { s_commitHook(); }
	if (s_presentHook) { s_presentHook(1); }
	voidDriverPresent();
	if (s_presentHook) { s_presentHook(0); }
}
