// Void capture — one readback signature, a backend behind it (docs/TESTING.md "T2").
//
// sokol has no readback API (docs/SOKOL.md:34), so every backend is hand-written here.
// D3D11 and GLES3 exist; Metal, WebGPU and WebGL2 are stubs that report themselves as
// absent, so the gate can print SKIP with a reason and never PASS for a backend it did
// not run.
//
// Two slots, so the caller can grab the same frame twice and prove the capture path is
// deterministic before either grab is compared to a golden ("distrust the harness before
// the engine", docs/TESTING.md).
#ifndef VOID_CAPTURE_H
#define VOID_CAPTURE_H

#include <stdint.h>

#define VOID_CAPTURE_SLOTS 2

// 0 = none (stub), 1 = D3D11, 2 = GLES3. Names the path that voidCaptureGrab would take.
int voidCaptureBackend(void);

// Read the current swapchain contents into `slot` as 8-bit RGBA, top row first.
// Returns 1 on success, 0 when this build has no readback path or the read failed.
int voidCaptureGrab(int slot);

// D3D11 only: read buffer `buffer` of an IDXGISwapChain1 the caller owns (a host view's).
int voidCaptureGrabSwapChain(int slot, long long swapChain, int buffer);

// 0xRRGGBBAA of one pixel of `slot`, or -1 outside the capture.
long long voidCapturePixel(int slot, int x, int y);

int voidCaptureWidth(int slot);
int voidCaptureHeight(int slot);

// Pixels whose RGBA differs between the two slots, or -1 if their sizes differ.
int voidCaptureSlotsDiffer(void);

// 1 when every pixel of `slot` is the same colour — the "captured before the draw" shape.
int voidCaptureUniform(int slot);

// Write `slot` as an 8-bit RGBA PNG. The directory must exist. 1 on success.
int voidCaptureWritePng(int slot, const char *path);

// Environment, because MetaScript has no argv. Missing or unparseable → fallback.
int voidCaptureEnvInt(const char *name, int fallback);

void voidCaptureExit(int code);

#endif
