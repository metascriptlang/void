#ifndef VOID_GPU_DOOR_H
#define VOID_GPU_DOOR_H

#include <stdint.h>

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

// Pass: four color attachments (view, load action), then depth (view, load and store
// action); the float side holds four rgba clear colors, then the depth clear value.
static const int32_t DOOR_MAX_COLOR_ATTACHMENTS = 4;
static const int32_t DOOR_PASS_COLOR_VIEW = 0;
static const int32_t DOOR_PASS_COLOR_LOAD = 4;
static const int32_t DOOR_PASS_DEPTH_VIEW = 8;
static const int32_t DOOR_PASS_DEPTH_LOAD = 9;
static const int32_t DOOR_PASS_DEPTH_STORE = 10;
static const int32_t DOOR_PASS_LENGTH = 11;
static const int32_t DOOR_PASS_CLEAR_DEPTH = 16;
static const int32_t DOOR_PASS_CLEAR_LENGTH = 17;

// Which pass the door has open, read by MetaScript to stop misuse naming the call.
enum {
	DOOR_PASS_NONE = 0,
	DOOR_PASS_TARGET = 1,
	DOOR_PASS_SCREEN = 2,
};

// What C layers call; MetaScript defines each (src/gpu/doorGpu.ms, `@exportName`). A pointer
// and int64 pair is one MetaScript Span: the length counts elements.
static const int32_t DOOR_BUFFER_VERTEX = 1;
static const int32_t DOOR_BUFFER_INDEX = 2;
static const int32_t DOOR_BUFFER_STREAM = 4;
static const int32_t DOOR_PIXEL_FORMAT_NONE = 0;
static const int32_t DOOR_PIXEL_FORMAT_RGBA8 = 2;
static const int32_t DOOR_PIXEL_FORMAT_DEPTH = 3;
static const int32_t DOOR_PIXEL_FORMAT_BGRA8 = 4;
static const int32_t DOOR_PIXEL_FORMAT_DEPTH_STENCIL = 5;
static const int32_t DOOR_PIXEL_FORMAT_R8 = 7;

// doorFrameStat: the previous frame's counts, as sokol's sg_frame_stats prev_frame.
static const int32_t DOOR_STAT_DRAWS = 0;
static const int32_t DOOR_STAT_PIPELINES = 1;
static const int32_t DOOR_STAT_PASSES = 2;
static const int32_t DOOR_STAT_BUFFER_BYTES = 3;
static const int32_t DOOR_STAT_IMAGE_BYTES = 4;

void doorSetup(void *device, void *context, int32_t colorFormat, int32_t depthFormat, int32_t sampleCount);
void doorShutdown(void);
int32_t doorValid(void);
int32_t doorContextGeneration(void);
int32_t doorFrameStat(int32_t which);
int32_t doorOriginTopLeft(void);

uint32_t doorMakeBuffer(int32_t usage, const uint8_t *data, int64_t length, int64_t size);
int32_t doorUpdateBuffer(uint32_t buffer, const uint8_t *data, int64_t length);
int64_t doorAppendBuffer(uint32_t buffer, const uint8_t *data, int64_t length);
void doorDestroyBuffer(uint32_t buffer);
int32_t doorBufferAlive(uint32_t buffer);

uint32_t doorMakeTexture(int32_t width, int32_t height, int32_t format, const uint8_t *data, int64_t length);
void doorUpdateTexture(uint32_t image, const uint8_t *data, int64_t length);
uint32_t doorMakeTextureView(uint32_t image);
uint32_t doorViewImage(uint32_t view);
int32_t doorViewIsColorAttachment(uint32_t view);
uint32_t doorMakeSampler(int32_t filter, int32_t wrap);
int32_t doorImageAlive(uint32_t image);
int32_t doorViewAlive(uint32_t view);
void doorDestroyImage(uint32_t image);
void doorDestroyView(uint32_t view);
void doorDestroySampler(uint32_t sampler);

void doorApplyPipeline(uint32_t pipeline);
void doorApplyBindings(const uint32_t *bindings, int64_t length, const int32_t *vertexOffsets, int64_t offsetCount);
void doorApplyUniforms(int32_t slot, const uint8_t *data, int64_t length);
void doorApplyScissor(int32_t x, int32_t y, int32_t width, int32_t height);
void doorDraw(int32_t base, int32_t count, int32_t instances);

void doorBeginScreenPass(float red, float green, float blue, float alpha);
void doorBeginColorPass(uint32_t view, float red, float green, float blue, float alpha);
void doorEndPass(void);
void doorCommit(void);
int32_t doorPassState(void);

#endif
