// void3d's GPU unit: registers this layer's programs and vertex layouts with the GPU door
// (src/gpu/door.h) and keeps the draw path the door does not own — buffers, plain and
// dynamic images, bindings, uniforms and the draw call. Which pipelines, targets and passes
// exist, and in what order they run, is decided in MetaScript (src/void3d/gpu3d.ms and
// above); the shared surface both render layers draw through is the door's. Every enum
// argument is a MetaScript ordinal; the door maps them to sokol values, so both sides must
// list the members in the same order. See docs/VOID3D.md, M20.
#ifndef VOID3D_GPU3D_H
#define VOID3D_GPU3D_H

#include <stdint.h>

// void3d's programs, in Program's order (gpu3d.ms): what gpu3d.c registers with the door.
#define GPU3D_PROGRAM_TABLE_LENGTH 13

// Bindings: 0 leaves a slot empty. View and sampler slots are the `binding=` numbers in
// shader3d.glsl and pixelArt3d.glsl.
static const int32_t GPU3D_BINDING_VERTEX_BUFFER = 0; // two
static const int32_t GPU3D_BINDING_INDEX_BUFFER = 2;
static const int32_t GPU3D_BINDING_VIEW = 3; // four
static const int32_t GPU3D_BINDING_SAMPLER = 7; // two
static const int32_t GPU3D_BINDING_LENGTH = 9;

int32_t gpu3dProgramBase(void);
int32_t gpu3dLayoutBase(void);

uint32_t gpu3dMakeVertexBuffer(const float *data, int64_t length);
uint32_t gpu3dMakeIndexBuffer(const uint16_t *data, int64_t length);
uint32_t gpu3dMakeImage(const uint32_t *rgba, int64_t length, int32_t width, int32_t height);
// An RGBA8 image whose pixels are replaced from the CPU (the palette LUT); starts undefined.
uint32_t gpu3dMakeDynamicImage(int32_t width, int32_t height);
// At most once per frame per image, before the pass that samples it.
void gpu3dUpdateImage(uint32_t image, const uint32_t *rgba, int64_t length);
// A vertex buffer of `length` floats the CPU rewrites (particle instances); starts undefined.
uint32_t gpu3dMakeStreamBuffer(int64_t length);
// At most once per frame per buffer, before the pass that draws it. 0 when refused: a buffer that
// is not valid, or more floats than it holds.
int32_t gpu3dUpdateBuffer(uint32_t buffer, const float *data, int64_t length);
void gpu3dDestroyBuffer(uint32_t buffer);
void gpu3dDestroyImage(uint32_t image);

void gpu3dApplyPipeline(uint32_t pipeline);
void gpu3dApplyBindings(const uint32_t *bindings, int64_t length);
void gpu3dApplyUniforms(int32_t slot, const float *data, int64_t length);
void gpu3dDraw(int32_t base, int32_t count, int32_t instances);

#endif
