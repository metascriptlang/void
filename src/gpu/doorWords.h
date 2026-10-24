#ifndef VOID_GPU_DOOR_WORDS_H
#define VOID_GPU_DOOR_WORDS_H

#include <stdint.h>

#define DOOR_UNIFORM_SLOT_TABLE_LENGTH 8
static const int32_t DOOR_UNIFORM_SLOTS = DOOR_UNIFORM_SLOT_TABLE_LENGTH;

// `static const` rather than enum or #define so that MetaScript can import these from this
// header (doorGpu.ms, draw.ms); msc sees neither of the others.

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

static const int32_t DOOR_BINDING_VERTEX_BUFFER = 0; // two
static const int32_t DOOR_BINDING_INDEX_BUFFER = 2;
static const int32_t DOOR_BINDING_VIEW = 3; // nine
static const int32_t DOOR_BINDING_SAMPLER = 12; // five
static const int32_t DOOR_BINDING_LENGTH = 17;

// Which pass the door has open, read by MetaScript to stop misuse naming the call.
enum {
	DOOR_PASS_NONE = 0,
	DOOR_PASS_TARGET = 1,
	DOOR_PASS_SCREEN = 2,
};

#endif
