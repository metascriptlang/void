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

// Upload a MetaScript-owned packed vertex run (pos2+uv2+color4 per vert) and draw it.
// blend selects the pipeline: 0=Alpha 1=Add 2=Multiply 3=Screen 4=None (see BlendMode).
// colorMatrix = 16 floats (column-major, identity = no-op); colorAdd = rgba added after.
void void2dUploadDraw(const float *verts, int vertCount, uint32_t view, int blend, float fbW, float fbH,
                      const float *colorMatrix, float addR, float addG, float addB, float addA,
                      float keyR, float keyG, float keyB, float keyA, int smooth);

// h2d.Mask clip — restrict subsequent draws to a framebuffer-pixel rect (top-left origin).
void void2dScissor(int x, int y, int w, int h);

// Route draws to the offscreen-RT pipeline set (single-sample, no depth) vs the swapchain set.
void void2dSetRTMode(int on);

// Per-frame reset (call once before building the frame) — re-arms the font-atlas upload.
void void2dFrameBegin(void);

// Static (retained) geometry: upload LOCAL-space verts once, draw many frames with the object
// matrix + alpha supplied per draw. Destroy before re-uploading a changed mesh (no auto-free).
uint32_t void2dMakeStaticBuffer(const float *verts, int vertCount);
void void2dDestroyStaticBuffer(uint32_t bufId);
void void2dDrawStatic(uint32_t bufId, int vertCount, uint32_t view, int blend, float fbW, float fbH,
                      float mA, float mB, float mC, float mD, float mTx, float mTy,
                      float gcR, float gcG, float gcB, float gcA,
                      const float *colorMatrix, float addR, float addG, float addB, float addA,
                      float keyR, float keyG, float keyB, float keyA, int smooth);

// fontstash glyph-layout iterator (MetaScript builds the glyph quads).
void void2dTextBegin(float x, float y, float size, const char *text);
float *void2dTextNext(void);      // returns 8 floats [x0,y0,s0,t0,x1,y1,s1,t1], or NULL when done
void void2dTextSyncAtlas(void);   // upload atlas if the iterator rasterized new glyphs
float void2dTextWidth(float size, const char *text);   // advance width of one line
float void2dLineHeight(float size);                    // vertical line spacing
void void2dTextSpacing(float spacing);                 // per-glyph advance (letter spacing)

#endif
