// Void sokol bridge — thin 1:1 wrappers over sokol_gfx/sokol_app.
// Render sequencing lives in MetaScript (rendererSokol.ms); this file only
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

// Embed lifecycle (iOS / host-driven) — host owns the CAMetalLayer + render loop.
void voidEmbedRegister(msClosure init, msClosure frame);
void voidEmbedInit(const void *layer, int w, int h);
void voidEmbedResize(int w, int h);
void voidEmbedFrame(void);
void voidEmbedSetMessagePump(msClosure pump);
void voidEmbedPumpMessages(void);

void voidGfxSetup(void);
int voidFbWidth(void);
int voidFbHeight(void);
float voidDpiScale(void);
int voidKeyDown(int keycode);

// Resource creation — sokol handles returned as uint32 ids (0 = invalid).
uint32_t voidMakeVertexBuffer(const void *data, int size);
uint32_t voidMakeIndexBuffer(const void *data, int size);
uint32_t voidMakeCubeShader(void);
uint32_t voidMakePipeline(uint32_t shader);
uint32_t voidMakeImage(const void *rgba, int w, int h);
uint32_t voidMakeView(uint32_t image);
uint32_t voidMakeSampler(void);

// Offscreen render targets (for h2d-style Filters). Single-sample RGBA8 color-only.
uint32_t voidMakeRenderTarget(int w, int h);
uint32_t voidRenderTargetView(uint32_t rt);
void voidBeginRenderTargetPass(uint32_t rt, float r, float g, float b, float a);
void voidDestroyRenderTarget(uint32_t rt);
int voidIsRenderTargetView(uint32_t view);

// Frame sequence.
void voidBeginPass(float r, float g, float b, float a);
void voidApplyPipeline(uint32_t pipeline);
void voidApplyBindings(uint32_t vbuf, uint32_t ibuf, uint32_t view, uint32_t sampler);
void voidApplyMvp(const float *mvp);
void voidDraw(int count);
void voidEndPass(void);
void voidCommit(void);

#endif
