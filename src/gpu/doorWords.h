#ifndef VOID_GPU_DOOR_WORDS_H
#define VOID_GPU_DOOR_WORDS_H

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

static const int32_t DOOR_BINDING_VERTEX_BUFFER = 0;
static const int32_t DOOR_BINDING_INDEX_BUFFER = 2;
static const int32_t DOOR_BINDING_VIEW = 3;
static const int32_t DOOR_BINDING_SAMPLER = 9;
static const int32_t DOOR_BINDING_LENGTH = 12;

// Which pass the door has open, read by MetaScript to stop misuse naming the call.
enum {
	DOOR_PASS_NONE = 0,
	DOOR_PASS_TARGET = 1,
	DOOR_PASS_SCREEN = 2,
};

#endif
