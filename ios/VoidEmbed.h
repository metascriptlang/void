// Void iOS embed — C surface exported by the Void static lib (libVoidIos.a).
// The host (VoidView / React-Native) calls these; implementations live in
// src/sokol/bridgeIos.m (voidEmbed*) and the emitted dispatcher (MsMain).
#ifndef VOID_EMBED_H
#define VOID_EMBED_H

#ifdef __cplusplus
extern "C" {
#endif

// Runs the MetaScript module-init graph once + the auto-called main_ (which
// registers the Void lifecycle closures). Call once before any voidEmbedInit.
void MsMain(void);

// Host hands over its CAMetalLayer (id<MTLDevice> read from layer.device, or
// created if nil) and the drawable size in pixels. Runs the scene's init.
void voidEmbedInit(const void *metalLayer, int widthPx, int heightPx);

// Host notifies a new drawable size in pixels (on layout / rotation).
void voidEmbedResize(int widthPx, int heightPx);

// Host drives one frame (acquires the next drawable + renders the scene).
void voidEmbedFrame(void);

#ifdef __cplusplus
}
#endif

#endif
