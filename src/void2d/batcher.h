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
void void2dReplay(const float *commands, int commandCount,
                  const float *effects, int effectCount,
                  const float *vertices, int vertexCount,
                  float fbW, float fbH);

// 1 when C's idea of the record layout matches MetaScript's. The emitter and the replay are
// two hand-written readers of one byte layout; this is the renderer's form of rexa's "the
// command table agrees with the parser" (docs/TESTING.md).
int void2dLayoutCheck(int commandFloats, int effectFloats, int vertexFloats,
                      int kindField, int breakField, int vertexOffsetField, int vertexCountField,
                      int viewField, int blendField, int smoothField, int effectField,
                      int clipXField, int arg0Field, int rtModeField,
                      int kindDraw, int kindScissor, int kindBlur);

void void2dSetDpiScale(float scale);

// Per-frame reset (call once before building the frame) — re-arms the font-atlas upload.
void void2dFrameBegin(void);

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
int void2dInstanceBufferBytes(void);
// Frames dropped because one frame's geometry exceeded VOID2D_MAX_BUFFER_BYTES. Never
// silent: the drop is logged once per frame and counted here.
int void2dDroppedFrames(void);

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

#endif
