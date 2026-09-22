// void3d GPU bridge: builds sokol descriptor structs from flat data, nothing more.
// Which pipelines, targets and passes exist, and in what order they run, is decided in
// MetaScript (src/void3d/gpu3d.ms and above). Every enum argument is a MetaScript enum
// ordinal; the tables in gpu3d.c map them to sokol values, so both sides must list the
// members in the same order. See docs/VOID3D.md, M2.
#ifndef VOID3D_GPU3D_H
#define VOID3D_GPU3D_H

#include <stdint.h>

// Flat descriptor layouts. `static const` rather than enum or #define so that MetaScript
// can import them from this header (gpu3d.ms); msc sees neither of the other two.

// Pipeline: one uint32 per field; enum fields hold MetaScript ordinals.
static const int32_t GPU3D_PIPELINE_SHADER = 0;
static const int32_t GPU3D_PIPELINE_LAYOUT = 1;
static const int32_t GPU3D_PIPELINE_CULLING = 2;
static const int32_t GPU3D_PIPELINE_DEPTH_TEST = 3;
static const int32_t GPU3D_PIPELINE_DEPTH_WRITE = 4;
static const int32_t GPU3D_PIPELINE_BLEND_SOURCE = 5;
static const int32_t GPU3D_PIPELINE_BLEND_DESTINATION = 6;
static const int32_t GPU3D_PIPELINE_BLEND_ALPHA_SOURCE = 7;
static const int32_t GPU3D_PIPELINE_BLEND_ALPHA_DESTINATION = 8;
static const int32_t GPU3D_PIPELINE_BLEND_OPERATION = 9;
static const int32_t GPU3D_PIPELINE_BLEND_ALPHA_OPERATION = 10;
static const int32_t GPU3D_PIPELINE_COLOR_MASK = 11;
static const int32_t GPU3D_PIPELINE_COLOR_FORMAT = 12; // four, one per color attachment
static const int32_t GPU3D_PIPELINE_DEPTH_FORMAT = 16;
static const int32_t GPU3D_PIPELINE_SAMPLE_COUNT = 17;
// IndexType ordinal: None for a mesh drawn straight from its vertex buffer, Uint16 when an
// index buffer is bound. sokol bakes it into the pipeline, so it selects one (PipelineKey).
static const int32_t GPU3D_PIPELINE_INDEX_TYPE = 18;
static const int32_t GPU3D_PIPELINE_LENGTH = 19;

// Pass: four color attachments (view, load action), then depth; the float side holds
// four rgba clear colors, then the depth clear value.
static const int32_t GPU3D_MAX_COLOR_ATTACHMENTS = 4;
static const int32_t GPU3D_PASS_COLOR_VIEW = 0;
static const int32_t GPU3D_PASS_COLOR_LOAD = 4;
static const int32_t GPU3D_PASS_DEPTH_VIEW = 8;
static const int32_t GPU3D_PASS_DEPTH_LOAD = 9;
static const int32_t GPU3D_PASS_LENGTH = 10;
static const int32_t GPU3D_PASS_CLEAR_DEPTH = 16;
static const int32_t GPU3D_PASS_CLEAR_LENGTH = 17;

// Bindings: 0 leaves a slot empty. View and sampler slots are the `binding=` numbers in
// shader3d.glsl.
static const int32_t GPU3D_BINDING_VERTEX_BUFFER = 0; // two
static const int32_t GPU3D_BINDING_INDEX_BUFFER = 2;
static const int32_t GPU3D_BINDING_VIEW = 3; // four
static const int32_t GPU3D_BINDING_SAMPLER = 7; // two
static const int32_t GPU3D_BINDING_LENGTH = 9;

uint32_t gpu3dMakeShader(int32_t program);
uint32_t gpu3dMakePipeline(const uint32_t *descriptor, int64_t length);
uint32_t gpu3dMakeVertexBuffer(const float *data, int64_t length);
uint32_t gpu3dMakeIndexBuffer(const uint16_t *data, int64_t length);
uint32_t gpu3dMakeImage(const uint32_t *rgba, int64_t length, int32_t width, int32_t height);
uint32_t gpu3dMakeTargetImage(int32_t width, int32_t height, int32_t format);
uint32_t gpu3dMakeAttachmentView(uint32_t image, int32_t format);
uint32_t gpu3dMakeTextureView(uint32_t image);
uint32_t gpu3dMakeSampler(int32_t filter, int32_t wrap);
// An RGBA8 image whose pixels are replaced from the CPU (the palette LUT); starts undefined.
uint32_t gpu3dMakeDynamicImage(int32_t width, int32_t height);
// At most once per frame per image, before the pass that samples it.
void gpu3dUpdateImage(uint32_t image, const uint32_t *rgba, int64_t length);
void gpu3dDestroyShader(uint32_t shader);
void gpu3dDestroyPipeline(uint32_t pipeline);
void gpu3dDestroyBuffer(uint32_t buffer);
void gpu3dDestroyImage(uint32_t image);
void gpu3dDestroyView(uint32_t view);
// The glTF reader's one byte-level need: a little-endian float32 at `at`, exact through a
// union pun because an arithmetic decode is wrong on denormals and NaN.
float gpu3dFloat32At(const uint8_t *bytes, int64_t length, int32_t at);
void gpu3dDestroySampler(uint32_t sampler);

void gpu3dBeginPass(const uint32_t *descriptor, int64_t length, const float *clear, int64_t clearLength);
void gpu3dBeginSwapchainPass(float red, float green, float blue, float alpha);
void gpu3dApplyPipeline(uint32_t pipeline);
void gpu3dApplyBindings(const uint32_t *bindings, int64_t length);
void gpu3dApplyUniforms(int32_t slot, const float *data, int64_t length);
void gpu3dDraw(int32_t base, int32_t count, int32_t instances);
void gpu3dEndPass(void);
void gpu3dCommit(void);

// Backend conventions the renderer adapts to: 1 when framebuffer and texture rows start at the
// top (D3D11, Metal), 0 when at the bottom (GL); 1 when the depth buffer stores clip z as is
// (0..1), 0 when GL maps clip z from -1..1 into it.
int32_t gpu3dOriginTopLeft(void);
int32_t gpu3dDepthZeroToOne(void);
// Changes when the host rebuilt a lost GPU context (only the Android bridge does); every
// handle made before is stale then.
int32_t gpu3dContextGeneration(void);

#endif
