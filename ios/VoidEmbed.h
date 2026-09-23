// Void iOS embed — C surface exported by the Void static lib (libVoidIos.a).
// The host (VoidView / React-Native) calls these; implementations live in
// src/sokol/bridgeIos.m (voidEmbed*) and the emitted dispatcher (MsMain).
#ifndef VOID_EMBED_H
#define VOID_EMBED_H

#ifdef __cplusplus
extern "C" {
#endif

// Runs the MetaScript module-init graph once + the auto-called main_ (which
// registers the Void lifecycle closures). Call once before any voidViewCreate.
void MsMain(void);

typedef int VoidViewId;

// A view on the host's CAMetalLayer, sized in pixels at `scale` pixels per point. The first
// view makes the shared MTLDevice and runs the scene's init. A failure aborts with a message.
VoidViewId voidViewCreate(long long metalLayer, int widthPx, int heightPx, float scale);

// Host notifies a new drawable size in pixels (on layout / rotation).
void voidViewResize(VoidViewId view, int widthPx, int heightPx, float scale);

// Host drives one frame of one view (acquires its next drawable and renders its scene).
int voidViewFrame(VoidViewId view);

void voidViewDestroy(VoidViewId view);

#ifdef __cplusplus
}
#endif

#endif
