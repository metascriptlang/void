#ifndef VOID_GPU_DRAW_H
#define VOID_GPU_DRAW_H

#include <stdint.h>

static const int32_t DRAW_BINDING_VERTEX_BUFFER = 0;
static const int32_t DRAW_BINDING_VERTEX_BUFFERS = 2;
static const int32_t DRAW_BINDING_INDEX_BUFFER = 2;
static const int32_t DRAW_BINDING_VIEW = 3;
static const int32_t DRAW_BINDING_VIEWS = 6;
static const int32_t DRAW_BINDING_SAMPLER = 9;
static const int32_t DRAW_BINDING_SAMPLERS = 3;
static const int32_t DRAW_BINDING_LENGTH = 12;

// A refused length returns 0: sokol _SG_PANICs on an empty buffer instead of returning an
// invalid id (sokol_gfx.h _sg_validate_buffer_desc).
uint32_t drawMakeVertexBuffer(const float *data, int64_t length);
uint32_t drawMakeIndexBuffer(const uint16_t *data, int64_t length);
uint32_t drawMakeIndexBuffer32(const uint32_t *data, int64_t length);
uint32_t drawMakeStreamBuffer(int64_t length);
int32_t drawUpdateBuffer(uint32_t buffer, const float *data, int64_t length);
void drawDestroyBuffer(uint32_t buffer);

void drawApplyPipeline(uint32_t pipeline);
void drawApplyBindings(const uint32_t *bindings, int64_t length);
void drawApplyUniforms(int32_t slot, const float *data, int64_t length);
void drawElements(int32_t base, int32_t count, int32_t instances);

#endif
