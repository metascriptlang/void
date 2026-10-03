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

typedef int VoidViewId;
void voidEmbedRegister(msClosure init, msClosure frame);
VoidViewId voidViewCreate(long long native, int w, int h, float scale);
void voidViewResize(VoidViewId v, int w, int h, float scale);
int voidViewFrame(VoidViewId v);
void voidViewDestroy(VoidViewId v);
long long voidViewSwapChain(VoidViewId v);
VoidViewId voidCurrentView(void);
void voidEmbedSetMessagePump(msClosure pump);
void voidEmbedPumpMessages(void);

// Android only: the GPU context generation (bumped when a lost EGL context is rebuilt) and a
// switch that forces that rebuild on the next frame.
int voidGpuGeneration(void);
void voidEmbedLoseContext(void);
void voidEmbedDetach(void);
void voidEmbedSetAssetRoot(const char *path);

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

#endif
