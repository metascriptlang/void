#include "door.h"
#include "../sokol/bridge.h"

#include <stdio.h>
#include <stdlib.h>

// ---- enum tables, indexed by MetaScript ordinal (same order as state.ms / target.ms) ----

// Face (h3d.mat.Data.Face without Both)
static const sg_cull_mode CULL_MODES[] = {
	SG_CULLMODE_NONE,
	SG_CULLMODE_BACK,
	SG_CULLMODE_FRONT,
};

// Compare (h3d.mat.Data.Compare)
static const sg_compare_func COMPARE_FUNCTIONS[] = {
	SG_COMPAREFUNC_ALWAYS,
	SG_COMPAREFUNC_NEVER,
	SG_COMPAREFUNC_EQUAL,
	SG_COMPAREFUNC_NOT_EQUAL,
	SG_COMPAREFUNC_GREATER,
	SG_COMPAREFUNC_GREATER_EQUAL,
	SG_COMPAREFUNC_LESS,
	SG_COMPAREFUNC_LESS_EQUAL,
};

// Blend (h3d.mat.Data.Blend without the constant-color factors)
static const sg_blend_factor BLEND_FACTORS[] = {
	SG_BLENDFACTOR_ONE,
	SG_BLENDFACTOR_ZERO,
	SG_BLENDFACTOR_SRC_ALPHA,
	SG_BLENDFACTOR_SRC_COLOR,
	SG_BLENDFACTOR_DST_ALPHA,
	SG_BLENDFACTOR_DST_COLOR,
	SG_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
	SG_BLENDFACTOR_ONE_MINUS_SRC_COLOR,
	SG_BLENDFACTOR_ONE_MINUS_DST_ALPHA,
	SG_BLENDFACTOR_ONE_MINUS_DST_COLOR,
};

static const sg_blend_factor ALPHA_CHANNEL_BLEND_FACTORS[] = {
	SG_BLENDFACTOR_ONE,
	SG_BLENDFACTOR_ZERO,
	SG_BLENDFACTOR_SRC_ALPHA,
	SG_BLENDFACTOR_SRC_ALPHA,
	SG_BLENDFACTOR_DST_ALPHA,
	SG_BLENDFACTOR_DST_ALPHA,
	SG_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
	SG_BLENDFACTOR_ONE_MINUS_SRC_ALPHA,
	SG_BLENDFACTOR_ONE_MINUS_DST_ALPHA,
	SG_BLENDFACTOR_ONE_MINUS_DST_ALPHA,
};

// Operation (h3d.mat.Data.Operation)
static const sg_blend_op BLEND_OPERATIONS[] = {
	SG_BLENDOP_ADD,
	SG_BLENDOP_SUBTRACT,
	SG_BLENDOP_REVERSE_SUBTRACT,
	SG_BLENDOP_MIN,
	SG_BLENDOP_MAX,
};

// PixelFormat: Default (0 in a sokol desc) means "whatever the swapchain uses".
enum { FORMAT_NONE, FORMAT_DEFAULT, FORMAT_RGBA8, FORMAT_DEPTH };
static const sg_pixel_format PIXEL_FORMATS[] = {
	SG_PIXELFORMAT_NONE,
	_SG_PIXELFORMAT_DEFAULT,
	SG_PIXELFORMAT_RGBA8,
	SG_PIXELFORMAT_DEPTH,
};

// LoadAction
static const sg_load_action LOAD_ACTIONS[] = {
	SG_LOADACTION_CLEAR,
	SG_LOADACTION_LOAD,
	SG_LOADACTION_DONTCARE,
};

// IndexType: uint16 only, which caps a mesh at 65536 vertices (meshData.ms).
static const sg_index_type INDEX_TYPES[] = {
	SG_INDEXTYPE_NONE,
	SG_INDEXTYPE_UINT16,
};

// FilterMode, Wrap (h3d.mat.Data)
static const sg_filter FILTERS[] = { SG_FILTER_NEAREST, SG_FILTER_LINEAR };
static const sg_wrap WRAPS[] = { SG_WRAP_CLAMP_TO_EDGE, SG_WRAP_REPEAT, SG_WRAP_MIRRORED_REPEAT };

#define COUNT(table) ((uint32_t)(sizeof(table) / sizeof(table[0])))
#define LOOKUP(table, index) ((uint32_t)(index) < COUNT(table) ? table[(uint32_t)(index)] : table[0])

// One entry per MetaScript enum member; these catch a member added on one side only. The
// order still has to be kept by hand, and is covered by the scene image check.
_Static_assert(COUNT(CULL_MODES) == 3, "CULL_MODES must match Face in state.ms");
_Static_assert(COUNT(COMPARE_FUNCTIONS) == 8, "COMPARE_FUNCTIONS must match Compare in state.ms");
_Static_assert(COUNT(BLEND_FACTORS) == 10, "BLEND_FACTORS must match Blend in state.ms");
_Static_assert(COUNT(ALPHA_CHANNEL_BLEND_FACTORS) == 10,
	"ALPHA_CHANNEL_BLEND_FACTORS must match Blend in state.ms");
_Static_assert(COUNT(BLEND_OPERATIONS) == 5, "BLEND_OPERATIONS must match Operation in state.ms");
_Static_assert(COUNT(PIXEL_FORMATS) == 4, "PIXEL_FORMATS must match PixelFormat in door.ms");
_Static_assert(COUNT(LOAD_ACTIONS) == 3, "LOAD_ACTIONS must match LoadAction in door.ms");
_Static_assert(COUNT(FILTERS) == 2, "FILTERS must match FilterMode in door.ms");
_Static_assert(COUNT(WRAPS) == 3, "WRAPS must match Wrap in door.ms");
_Static_assert(COUNT(INDEX_TYPES) == 2, "INDEX_TYPES must match IndexType in pipeline.ms");
_Static_assert(DOOR_UNIFORM_SLOT_TABLE_LENGTH == SG_MAX_UNIFORMBLOCK_BINDSLOTS,
	"DOOR_UNIFORM_SLOTS must be sokol's uniform block slot count");

// ---- the registries ----

static sg_vertex_layout_state *g_layouts = NULL;
static int32_t g_layoutCount = 0;
static int32_t g_layoutCapacity = 0;

typedef struct {
	door_shader_fn shader;
	int32_t layout;
} DoorProgram;

static DoorProgram *g_programs = NULL;
static int32_t g_programCount = 0;
static int32_t g_programCapacity = 0;

static void *grownRegistry(void *entries, int32_t *capacity, int32_t count, int32_t more,
	size_t entrySize, const char *what) {
	if (more > INT32_MAX - count) {
		fprintf(stderr, "gpu door: %d more %s ids overflow int32 after %d registered\n",
			more, what, count);
		abort();
	}
	const int32_t need = count + more;
	if (need <= *capacity) return entries;
	int64_t grown = *capacity > 0 ? (int64_t)*capacity * 2 : 16;
	if (grown < need) grown = need;
	if (grown > INT32_MAX) grown = INT32_MAX;
	void *moved = (uint64_t)grown > SIZE_MAX / entrySize
		? NULL
		: realloc(entries, (size_t)grown * entrySize);
	if (moved == NULL) {
		fprintf(stderr, "gpu door: out of memory registering %d more %s ids after %d\n",
			more, what, count);
		abort();
	}
	*capacity = (int32_t)grown;
	return moved;
}

int32_t doorRegisterLayouts(const sg_vertex_layout_state *layouts, int32_t count) {
	if (count < 0) {
		fprintf(stderr, "gpu door: registerLayouts count is negative\n");
		abort();
	}
	g_layouts = grownRegistry(g_layouts, &g_layoutCapacity, g_layoutCount, count,
		sizeof(sg_vertex_layout_state), "vertex layout");
	const int32_t base = g_layoutCount;
	for (int32_t i = 0; i < count; i++) {
		g_layouts[base + i] = layouts[i];
	}
	g_layoutCount += count;
	return base;
}

int32_t doorRegisterPrograms(const door_shader_fn *shaders, const int32_t *layouts, int32_t count) {
	if (count < 0) {
		fprintf(stderr, "gpu door: registerPrograms count is negative\n");
		abort();
	}
	g_programs = grownRegistry(g_programs, &g_programCapacity, g_programCount, count,
		sizeof(DoorProgram), "program");
	const int32_t base = g_programCount;
	for (int32_t i = 0; i < count; i++) {
		g_programs[base + i].shader = shaders[i];
		g_programs[base + i].layout = layouts[i];
	}
	g_programCount += count;
	return base;
}


static int32_t programIndex(int32_t program) {
	if ((uint32_t)program >= (uint32_t)g_programCount) {
		fprintf(stderr, "gpu door: unregistered program id\n");
		abort();
	}
	return program;
}

static const sg_vertex_layout_state *layoutOf(int32_t layout) {
	if ((uint32_t)layout >= (uint32_t)g_layoutCount) {
		fprintf(stderr, "gpu door: unregistered layout id\n");
		abort();
	}
	return &g_layouts[layout];
}

int32_t doorProgramLayout(int32_t program) {
	return g_programs[programIndex(program)].layout;
}

static door_shader_fn shaderOf(int32_t program) {
	return g_programs[programIndex(program)].shader;
}

uint32_t doorMakeShader(int32_t program) {
	sg_shader shader = sg_make_shader(shaderOf(program)(sg_query_backend()));
	if (sg_query_shader_state(shader) != SG_RESOURCESTATE_VALID) {
		sg_destroy_shader(shader);
		return SG_INVALID_ID;
	}
	return shader.id;
}

uint32_t doorUniformSlotMask(int32_t program) {
	const sg_shader_desc *desc = shaderOf(program)(sg_query_backend());
	uint32_t mask = 0;
	for (int slot = 0; slot < SG_MAX_UNIFORMBLOCK_BINDSLOTS; slot++) {
		if (desc->uniform_blocks[slot].stage != SG_SHADERSTAGE_NONE) mask |= 1u << slot;
	}
	return mask;
}

// Every backend's desc carries the same block sizes; D3D11's is always compiled in (hlsl5).
int32_t doorUniformBlockBytes(int32_t program, int32_t slot) {
	if (slot < 0 || slot >= SG_MAX_UNIFORMBLOCK_BINDSLOTS) return 0;
	const sg_shader_desc *desc = shaderOf(program)(SG_BACKEND_D3D11);
	if (desc == 0 || desc->uniform_blocks[slot].stage == SG_SHADERSTAGE_NONE) return 0;
	return (int32_t)desc->uniform_blocks[slot].size;
}

uint32_t doorTextureSlotMask(int32_t program) {
	const sg_shader_desc *desc = shaderOf(program)(SG_BACKEND_D3D11);
	uint32_t mask = 0;
	for (int slot = 0; slot < SG_MAX_VIEW_BINDSLOTS; slot++) {
		if (desc->views[slot].texture.stage != SG_SHADERSTAGE_NONE) mask |= 1u << slot;
	}
	return mask;
}

uint32_t doorSamplerSlotMask(int32_t program) {
	const sg_shader_desc *desc = shaderOf(program)(SG_BACKEND_D3D11);
	uint32_t mask = 0;
	for (int slot = 0; slot < SG_MAX_SAMPLER_BINDSLOTS; slot++) {
		if (desc->samplers[slot].stage != SG_SHADERSTAGE_NONE) mask |= 1u << slot;
	}
	return mask;
}

static int32_t formatFloats(sg_vertex_format format) {
	switch (format) {
	case SG_VERTEXFORMAT_FLOAT2: return 2;
	case SG_VERTEXFORMAT_FLOAT3: return 3;
	case SG_VERTEXFORMAT_FLOAT4: return 4;
	default: return -1;
	}
}

int32_t doorLayoutFloats(int32_t layout, int32_t buffer) {
	const sg_vertex_layout_state *state = layoutOf(layout);
	int32_t floats = 0;
	for (int i = 0; i < SG_MAX_VERTEX_ATTRIBUTES; i++) {
		if (state->attrs[i].format == SG_VERTEXFORMAT_INVALID || state->attrs[i].buffer_index != buffer) {
			continue;
		}
		const int32_t size = formatFloats(state->attrs[i].format);
		if (size < 0) return -1;
		floats += size;
	}
	return floats;
}

int32_t doorLayoutPerInstance(int32_t layout) {
	const sg_vertex_layout_state *state = layoutOf(layout);
	return state->buffers[0].step_func == SG_VERTEXSTEP_PER_INSTANCE ? 1 : 0;
}

// ---- resources ----

uint32_t doorMakePipeline(const uint32_t *descriptor, int64_t length) {
	if (length < DOOR_PIPELINE_LENGTH) return SG_INVALID_ID;
	const uint32_t *d = descriptor;
	sg_pipeline_desc desc = {0};
	desc.shader = (sg_shader){.id = d[DOOR_PIPELINE_SHADER]};
	desc.layout = *layoutOf((int32_t)d[DOOR_PIPELINE_LAYOUT]);
	desc.cull_mode = LOOKUP(CULL_MODES, d[DOOR_PIPELINE_CULLING]);
	// glTF, the Blender exporter and the spike wind front faces counter-clockwise.
	desc.face_winding = SG_FACEWINDING_CCW;
	desc.depth.pixel_format = LOOKUP(PIXEL_FORMATS, d[DOOR_PIPELINE_DEPTH_FORMAT]);
	desc.depth.compare = LOOKUP(COMPARE_FUNCTIONS, d[DOOR_PIPELINE_DEPTH_TEST]);
	desc.depth.write_enabled = d[DOOR_PIPELINE_DEPTH_WRITE] != 0;
	desc.sample_count = (int)d[DOOR_PIPELINE_SAMPLE_COUNT];
	desc.index_type = LOOKUP(INDEX_TYPES, d[DOOR_PIPELINE_INDEX_TYPE]);

	sg_blend_state blend = {0};
	blend.src_factor_rgb = LOOKUP(BLEND_FACTORS, d[DOOR_PIPELINE_BLEND_SOURCE]);
	blend.dst_factor_rgb = LOOKUP(BLEND_FACTORS, d[DOOR_PIPELINE_BLEND_DESTINATION]);
	blend.src_factor_alpha = LOOKUP(ALPHA_CHANNEL_BLEND_FACTORS, d[DOOR_PIPELINE_BLEND_ALPHA_SOURCE]);
	blend.dst_factor_alpha =
		LOOKUP(ALPHA_CHANNEL_BLEND_FACTORS, d[DOOR_PIPELINE_BLEND_ALPHA_DESTINATION]);
	blend.op_rgb = LOOKUP(BLEND_OPERATIONS, d[DOOR_PIPELINE_BLEND_OPERATION]);
	blend.op_alpha = LOOKUP(BLEND_OPERATIONS, d[DOOR_PIPELINE_BLEND_ALPHA_OPERATION]);
	// One/Zero/Add on both channels is Heaps' "no blending" (Pass.blend(One, Zero)).
	blend.enabled = !(blend.src_factor_rgb == SG_BLENDFACTOR_ONE && blend.dst_factor_rgb == SG_BLENDFACTOR_ZERO
		&& blend.src_factor_alpha == SG_BLENDFACTOR_ONE && blend.dst_factor_alpha == SG_BLENDFACTOR_ZERO
		&& blend.op_rgb == SG_BLENDOP_ADD && blend.op_alpha == SG_BLENDOP_ADD);
	// Heaps colorMask bits (r=1, g=2, b=4, a=8) are sokol's; an empty mask needs the explicit NONE.
	uint32_t mask = d[DOOR_PIPELINE_COLOR_MASK] & 15;
	sg_color_mask writeMask = mask == 0 ? SG_COLORMASK_NONE : (sg_color_mask)mask;

	int colorCount = 0;
	for (int i = 0; i < DOOR_MAX_COLOR_ATTACHMENTS; i++) {
		uint32_t format = d[DOOR_PIPELINE_COLOR_FORMAT + i];
		if (format == FORMAT_NONE) break;
		desc.colors[i].pixel_format = LOOKUP(PIXEL_FORMATS, format);
		desc.colors[i].write_mask = writeMask;
		desc.colors[i].blend = blend;
		colorCount = i + 1;
	}
	desc.color_count = colorCount;
	sg_pipeline pipeline = sg_make_pipeline(&desc);
	if (sg_query_pipeline_state(pipeline) != SG_RESOURCESTATE_VALID) {
		sg_destroy_pipeline(pipeline);
		return SG_INVALID_ID;
	}
	return pipeline.id;
}

uint32_t doorMakeTargetImage(int32_t width, int32_t height, int32_t format) {
	if (width <= 0 || height <= 0) return SG_INVALID_ID;
	sg_image_desc desc = {0};
	if (format == FORMAT_DEPTH) {
		desc.usage.depth_stencil_attachment = true;
	} else {
		desc.usage.color_attachment = true;
	}
	desc.width = width;
	desc.height = height;
	desc.pixel_format = LOOKUP(PIXEL_FORMATS, format);
	desc.sample_count = 1;
	return sg_make_image(&desc).id;
}

uint32_t doorMakeAttachmentView(uint32_t image, int32_t format) {
	sg_view_desc desc = {0};
	if (format == FORMAT_DEPTH) {
		desc.depth_stencil_attachment.image = (sg_image){.id = image};
	} else {
		desc.color_attachment.image = (sg_image){.id = image};
	}
	return sg_make_view(&desc).id;
}

uint32_t doorMakeTextureView(uint32_t image) {
	sg_view_desc desc = {0};
	desc.texture.image = (sg_image){.id = image};
	return sg_make_view(&desc).id;
}

uint32_t doorMakeSampler(int32_t filter, int32_t wrap) {
	sg_sampler_desc desc = {0};
	desc.min_filter = LOOKUP(FILTERS, filter);
	desc.mag_filter = LOOKUP(FILTERS, filter);
	desc.wrap_u = LOOKUP(WRAPS, wrap);
	desc.wrap_v = LOOKUP(WRAPS, wrap);
	return sg_make_sampler(&desc).id;
}

void doorDestroyShader(uint32_t shader) { sg_destroy_shader((sg_shader){.id = shader}); }
void doorDestroyPipeline(uint32_t pipeline) { sg_destroy_pipeline((sg_pipeline){.id = pipeline}); }
void doorDestroyImage(uint32_t image) { sg_destroy_image((sg_image){.id = image}); }
void doorDestroyView(uint32_t view) { sg_destroy_view((sg_view){.id = view}); }
void doorDestroySampler(uint32_t sampler) { sg_destroy_sampler((sg_sampler){.id = sampler}); }

// ---- passes ----

static int32_t g_openPass = DOOR_PASS_NONE;

// The open-pass state is set in these three functions and read nowhere else in C. The stops
// that name the call live in MetaScript (door.ms), which every layer passes through.
void doorBeginPass(const uint32_t *descriptor, int64_t length, const float *clear, int64_t clearLength) {
	if (length < DOOR_PASS_LENGTH || clearLength < DOOR_PASS_CLEAR_LENGTH) return;
	sg_pass pass = {0};
	for (int i = 0; i < DOOR_MAX_COLOR_ATTACHMENTS; i++) {
		pass.attachments.colors[i] = (sg_view){.id = descriptor[DOOR_PASS_COLOR_VIEW + i]};
		pass.action.colors[i].load_action = LOOKUP(LOAD_ACTIONS, descriptor[DOOR_PASS_COLOR_LOAD + i]);
		pass.action.colors[i].clear_value = (sg_color){clear[i * 4], clear[i * 4 + 1], clear[i * 4 + 2], clear[i * 4 + 3]};
	}
	pass.attachments.depth_stencil = (sg_view){.id = descriptor[DOOR_PASS_DEPTH_VIEW]};
	pass.action.depth.load_action = LOOKUP(LOAD_ACTIONS, descriptor[DOOR_PASS_DEPTH_LOAD]);
	pass.action.depth.clear_value = clear[DOOR_PASS_CLEAR_DEPTH];
	sg_begin_pass(&pass);
	g_openPass = DOOR_PASS_TARGET;
}

void doorBeginScreenPass(float red, float green, float blue, float alpha) {
	voidBeginPass(red, green, blue, alpha);
	g_openPass = DOOR_PASS_SCREEN;
}

void doorEndPass(void) {
	sg_end_pass();
	g_openPass = DOOR_PASS_NONE;
}

int32_t doorPassState(void) {
	return g_openPass;
}

// ---- backend conventions ----

int32_t doorOriginTopLeft(void) { return sg_query_features().origin_top_left ? 1 : 0; }

int32_t doorDepthZeroToOne(void) {
	const sg_backend backend = sg_query_backend();
	return backend == SG_BACKEND_GLCORE || backend == SG_BACKEND_GLES3 ? 0 : 1;
}

int32_t doorContextGeneration(void) {
#if defined(__ANDROID__)
	return voidGpuGeneration();
#else
	return 1;
#endif
}

// sg_commit files the frame it ends as prev_frame and then counts on, and sg_setup starts at 1
// (sokol_gfx.h sg_commit, _sg_update_stats), so this is the index sg_update_buffer checks.
uint32_t doorFrameIndex(void) {
	return sg_query_stats().prev_frame.frame_index + 1;
}

int32_t doorLiveBuffers(void) {
	return (int32_t)sg_query_stats().total.buffers.alive;
}

int32_t doorLiveImages(void) {
	return (int32_t)sg_query_stats().total.images.alive;
}

int32_t doorLiveViews(void) {
	return (int32_t)sg_query_stats().total.views.alive;
}

int32_t doorLiveSamplers(void) {
	return (int32_t)sg_query_stats().total.samplers.alive;
}
