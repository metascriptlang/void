#ifndef VOID_GPU_DOOR_H
#define VOID_GPU_DOOR_H

#include <stdint.h>

#include "../../deps/sokol/sokol_gfx.h"

#define DOOR_UNIFORM_SLOT_TABLE_LENGTH 8
static const int32_t DOOR_UNIFORM_SLOTS = DOOR_UNIFORM_SLOT_TABLE_LENGTH;

// Flat descriptor layouts. `static const` rather than enum or #define so that MetaScript
// can import them from this header (door.ms, pipeline.ms); msc sees neither of the others.

// Pipeline: one uint32 per field; enum fields hold MetaScript ordinals, LAYOUT a registered
// layout id.
static const int32_t DOOR_PIPELINE_SHADER = 0;
static const int32_t DOOR_PIPELINE_LAYOUT = 1;
static const int32_t DOOR_PIPELINE_CULLING = 2;
static const int32_t DOOR_PIPELINE_DEPTH_TEST = 3;
static const int32_t DOOR_PIPELINE_DEPTH_WRITE = 4;
static const int32_t DOOR_PIPELINE_BLEND_SOURCE = 5;
static const int32_t DOOR_PIPELINE_BLEND_DESTINATION = 6;
static const int32_t DOOR_PIPELINE_BLEND_ALPHA_SOURCE = 7;
static const int32_t DOOR_PIPELINE_BLEND_ALPHA_DESTINATION = 8;
static const int32_t DOOR_PIPELINE_BLEND_OPERATION = 9;
static const int32_t DOOR_PIPELINE_BLEND_ALPHA_OPERATION = 10;
static const int32_t DOOR_PIPELINE_COLOR_MASK = 11;
static const int32_t DOOR_PIPELINE_COLOR_FORMAT = 12; // four, one per color attachment
static const int32_t DOOR_PIPELINE_DEPTH_FORMAT = 16;
static const int32_t DOOR_PIPELINE_SAMPLE_COUNT = 17;
// IndexType ordinal: None for a mesh drawn straight from its vertex buffer, Uint16 when an
// index buffer is bound. sokol bakes it into the pipeline, so it selects one (PipelineKey).
static const int32_t DOOR_PIPELINE_INDEX_TYPE = 18;
static const int32_t DOOR_PIPELINE_LENGTH = 19;

// Pass: four color attachments (view, load action), then depth; the float side holds four
// rgba clear colors, then the depth clear value.
static const int32_t DOOR_MAX_COLOR_ATTACHMENTS = 4;
static const int32_t DOOR_PASS_COLOR_VIEW = 0;
static const int32_t DOOR_PASS_COLOR_LOAD = 4;
static const int32_t DOOR_PASS_DEPTH_VIEW = 8;
static const int32_t DOOR_PASS_DEPTH_LOAD = 9;
static const int32_t DOOR_PASS_LENGTH = 10;
static const int32_t DOOR_PASS_CLEAR_DEPTH = 16;
static const int32_t DOOR_PASS_CLEAR_LENGTH = 17;

// Which pass the door has open, read by MetaScript to stop misuse naming the call.
enum {
	DOOR_PASS_NONE = 0,
	DOOR_PASS_TARGET = 1,
	DOOR_PASS_SCREEN = 2,
};

typedef const sg_shader_desc *(*door_shader_fn)(sg_backend backend);

// Registers `count` vertex layouts and returns the first id. Refuses (prints, aborts) when
// the registry cannot hold them.
int32_t doorRegisterLayouts(const sg_vertex_layout_state *layouts, int32_t count);

// Registers `count` programs — each a sokol-shdc table entry and the layout id it reads —
// and returns the first program id. A program id is what a PipelineKey holds and what
// shader making and introspection take.
int32_t doorRegisterPrograms(const door_shader_fn *shaders, const int32_t *layouts, int32_t count);

// The layout a registered program reads; the registration's own answer, so a layer's
// MetaScript map of its programs can be held against it.
int32_t doorProgramLayout(int32_t program);
int32_t doorProgramCount(void);

uint32_t doorMakeShader(int32_t program);
// Bit n set when the program declares a uniform block at slot n, read off its shader desc.
uint32_t doorUniformSlotMask(int32_t program);
// Bytes of the block the program declares at `slot`, 0 for none; needs no GPU.
int32_t doorUniformBlockBytes(int32_t program, int32_t slot);
// Bit n set when the program samples a texture at view slot n, or declares sampler slot n;
// read off the D3D11 desc like doorUniformBlockBytes, so it needs no GPU.
uint32_t doorTextureSlotMask(int32_t program);
uint32_t doorSamplerSlotMask(int32_t program);
// Floats per vertex (or per instance) of vertex buffer `buffer` in the registered layout
// `layout`, or -1 for a format that is not float.
int32_t doorLayoutFloats(int32_t layout, int32_t buffer);
// 1 when the registered layout's vertex buffer 0 steps per instance (particle, billboard).
int32_t doorLayoutPerInstance(int32_t layout);
uint32_t doorMakePipeline(const uint32_t *descriptor, int64_t length);
uint32_t doorMakeTargetImage(int32_t width, int32_t height, int32_t format);
uint32_t doorMakeAttachmentView(uint32_t image, int32_t format);
uint32_t doorMakeTextureView(uint32_t image);
uint32_t doorMakeSampler(int32_t filter, int32_t wrap);
// Destruction of what the door makes. Buffers, plain and dynamic images and the draw-path
// calls (apply, uniforms, draw) belong to the layer that made them (void3d: gpu3d.c).
void doorDestroyShader(uint32_t shader);
void doorDestroyPipeline(uint32_t pipeline);
void doorDestroyImage(uint32_t image);
void doorDestroyView(uint32_t view);
void doorDestroySampler(uint32_t sampler);

void doorBeginPass(const uint32_t *descriptor, int64_t length, const float *clear, int64_t clearLength);
// The swapchain is the platform bridge's (bridge.h voidBeginPass), which clears color to
// the given value and depth to 1.
void doorBeginScreenPass(float red, float green, float blue, float alpha);
void doorBeginColorPass(uint32_t view, float red, float green, float blue, float alpha);
void doorEndPass(void);
void doorCommit(void);
int32_t doorPassState(void);

// Backend conventions the renderer adapts to: 1 when framebuffer and texture rows start at
// the top (D3D11, Metal), 0 when at the bottom (GL); 1 when the depth buffer stores clip z
// as is (0..1), 0 when GL maps clip z from -1..1 into it.
int32_t doorOriginTopLeft(void);
int32_t doorDepthZeroToOne(void);
int32_t doorEnvironmentColorFormat(void);
int32_t doorEnvironmentDepthFormat(void);
int32_t doorEnvironmentSampleCount(void);
// Changes when the host rebuilt a lost GPU context (only the Android bridge does); every
// handle made before is stale then.
int32_t doorContextGeneration(void);
// sokol's index of the frame being recorded, the one its update-once-per-frame rule counts in.
uint32_t doorFrameIndex(void);
// How many buffers, images, views and samplers sokol's pools hold alive, whoever made them.
int32_t doorLiveBuffers(void);
int32_t doorLiveImages(void);
int32_t doorLiveViews(void);
int32_t doorLiveSamplers(void);

#endif
