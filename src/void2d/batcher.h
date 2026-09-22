// Void 2D — thin sokol/fontstash primitives. The batcher LOGIC (vertex buffer,
// quad/glyph geometry, flush orchestration) lives in MetaScript (src/void2d/draw.ms);
// this file only exposes what FFI can't do: sokol resource calls + the fontstash
// glyph-layout iterator. See docs/VOID2D.md.
#ifndef VOID2D_BATCHER_H
#define VOID2D_BATCHER_H

#include <stdint.h>

void void2dSetup(void);
uint32_t void2dWhiteView(void);
uint32_t void2dFontView(void);

// Replay one frame's display list (src/void2d/displayList.ms) into the pass that is already
// open. This is the ONLY function in this file that issues a draw, and it is called once per
// bracket, after the tree walk has finished — which is what makes "no sg_* call happens
// while the tree is walked" a property of the code rather than a promise.
//
// The whole vertex stream is uploaded once, in a single sg_append_buffer, and each Draw
// command is a range inside it. `commands` is commandCount records of COMMAND_FLOATS floats
// and `effects` is effectCount records of EFFECT_FLOATS, both laid out by displayList.ms;
// the layout constants are asserted to agree in void2dLayoutCheck below.
// Uploads the frame's geometry and runs every render-target pass. Call with no pass open,
// before the swapchain pass; 0 means the frame was dropped and void2dReplay will do nothing.
int void2dReplayTargets(const float *targetCommands, int targetCommandCount,
                        const float *effects, int effectCount,
                        const float *vertices, int vertexCount,
                        const float *spriteInstances, int spriteInstanceCount,
                        const float *uiInstances, int uiInstanceCount);

// Replays the swapchain list inside the pass the caller has already opened.
void void2dReplay(const float *commands, int commandCount,
                  const float *effects, int effectCount,
                  float fbW, float fbH);

// 1 when C's idea of the record layout matches MetaScript's. The emitter and the replay are
// two hand-written readers of one byte layout; this is the renderer's form of rexa's "the
// command table agrees with the parser" (docs/TESTING.md).
int void2dLayoutCheck(int commandFloats, int effectFloats, int vertexFloats,
                      int kindField, int breakField, int vertexOffsetField, int vertexCountField,
                      int viewField, int blendField, int samplerField, int effectField,
                      int samplerCount, int maxTargetDepth, int clearRField,
                      int clipXField, int clipUField, int arg0Field, int rtModeField,
                      int kindDraw, int kindScissor, int kindBlur,
                      int kindTargetBegin, int kindTargetEnd);

void void2dSetDpiScale(float scale);
int void2dScissorMin(float edge, float scale);
int void2dScissorMax(float edge, float scale);

// Per-frame reset (call once before building the frame) — re-arms the font-atlas upload.
void void2dFrameBegin(void);

// Runs once per sokol frame, immediately after sg_commit — void2dSetup registers it as the
// bridge's commit hook, so no caller has to remember it. void2dFrameBegin opens a bracket and
// a frame may hold several; only this closes the frame.
void void2dFrameEnd(void);

// One separable-blur tap pass (fullscreen) into the active offscreen RT pass — sample srcView
// with a 9-tap Gaussian offset by (dirX,dirY) in UV. Run twice (H then V) ping-ponging two RTs.
void void2dBlur(uint32_t srcView, float dirX, float dirY);

// Frame counters, read by T1 and gated by T4 (docs/TESTING.md). GPUI counts none of them
// (GPUI.md:62). `buffersAlive` is every sg_buffer this layer holds — one, now that the
// per-node static buffers are gone, which is what makes it constant in the node count.
int void2dDrawCallCount(void);
int void2dUploadCount(void);
int void2dUploadBytes(void);
int void2dBuffersAlive(void);

// Glyph-atlas images made minus freed; 1 in a steady frame.
int void2dAtlasImagesAlive(void);

// The vertex buffer growth policy as pure arithmetic: max(2x, pow2), no shrink, 0 past the
// cap. Exposed so T1 can assert its boundaries without a GPU.
int void2dGrowthTarget(int have, int need);
int void2dVertexBufferBytes(void);
// Frames dropped because one frame's geometry exceeded VOID2D_MAX_BUFFER_BYTES. Never
// silent: the drop is logged once per frame and counted here.
int void2dDroppedFrames(void);
// A pending target list at end2d is a pass-order violation, not a recoverable dropped draw.
void void2dFailPendingTargets(void);

// fontstash glyph-layout iterator (MetaScript builds the glyph quads).
void void2dTextBegin(float x, float y, float size, const char *text);
float *void2dTextNext(void);      // returns 8 floats [x0,y0,s0,t0,x1,y1,s1,t1], or NULL when done
void void2dTextSyncAtlas(void);   // upload atlas if the iterator rasterized new glyphs
float void2dTextWidth(float size, const char *text);   // advance width of one line
float void2dLineHeight(float size);                    // vertical line spacing
void void2dTextSpacing(float spacing);                 // per-glyph advance (letter spacing)
int void2dAtlasGen(void);                              // atlas generation (changes on resize → re-layout)
int void2dAddFont(const char *path);                   // load a TTF, returns font index (0-based)
void void2dSelectFont(int id);                         // select current font for subsequent text ops

// The opaque texel fontstash reserves at the glyph atlas origin, as a UV. A solid card drawn
// against the glyph view instead of the 1x1 white image shares a batch with the labels around
// it. The UV moves when the atlas grows, so read it per frame.
float void2dWhiteTexelU(void);
float void2dWhiteTexelV(void);
// 1 only when that texel is measurably opaque; 0 with no fontstash context.
int void2dWhiteTexelOk(void);

// The instance strides sokol is handed, from sizeof rather than a literal, and the offsets
// the emitter in src/void2d/instance.ms claims it writes. void2dInstanceLayoutCheck fails at
// setup if the two ever disagree.
int void2dUiInstanceStride(void);

// One colour channel packed as the GPU stores it. Exported so a test can hold it against
// instance.ms's packChannel instead of guardrail 9 resting on two copies that look alike.
int void2dPackChannel(float value);
int void2dSpriteInstanceStride(void);
int void2dInstanceLayoutCheck(int uiStride, int uiAffine, int uiOriginSize, int uiUvRadii,
                              int uiBorders, int uiParams0, int uiParams1, int uiColorFill,
                              int uiColorBorder, int uiColorExtra,
                              int spriteStride, int spriteAffine, int spriteOriginSize,
                              int spriteUv, int spriteColor);

#endif
