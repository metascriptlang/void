#include "gpu3d.h"
#include "../sokol/bridge.h"
#include "../../deps/sokol/sokol_gfx.h"
#include "shader3d.glsl.h"
#include "pixelArt3d.glsl.h"

// ---- enum tables, indexed by MetaScript ordinal (same order as gpu3d.ms / pass.ms) ----

typedef const sg_shader_desc *(*ShaderDescription)(sg_backend backend);

// Program
static const ShaderDescription PROGRAMS[] = {
	lit_shader_desc,
	particle_shader_desc,
	billboard_shader_desc,
	copy_shader_desc,
	pixelArt_lit_shader_desc,
	pixelArt_particle_shader_desc,
	pixelArt_billboard_shader_desc,
	pixelArt_post_shader_desc,
	pixelArt_blit_shader_desc,
};

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

// Filter, Wrap (h3d.mat.Data)
static const sg_filter FILTERS[] = { SG_FILTER_NEAREST, SG_FILTER_LINEAR };
static const sg_wrap WRAPS[] = { SG_WRAP_CLAMP_TO_EDGE, SG_WRAP_REPEAT, SG_WRAP_MIRRORED_REPEAT };

#define COUNT(table) ((uint32_t)(sizeof(table) / sizeof(table[0])))
#define LOOKUP(table, index) ((uint32_t)(index) < COUNT(table) ? table[(uint32_t)(index)] : table[0])

// One entry per MetaScript enum member. These catch a member added on one side only; the
// order still has to be kept by hand (and is covered by the scene image check).
_Static_assert(COUNT(PROGRAMS) == GPU3D_PROGRAM_TABLE_LENGTH, "PROGRAMS must match Program in gpu3d.ms");
_Static_assert(ATTR_pixelArt_lit_position == ATTR_lit_position && ATTR_pixelArt_lit_normal == ATTR_lit_normal
	&& ATTR_pixelArt_lit_color == ATTR_lit_color, "every Lit-layout program must declare the core lit attributes");
_Static_assert(ATTR_pixelArt_particle_corner == ATTR_particle_corner && ATTR_pixelArt_particle_root == ATTR_particle_root
	&& ATTR_pixelArt_particle_color == ATTR_particle_color,
	"every Particle-layout program must declare the core particle attributes");
_Static_assert(ATTR_pixelArt_billboard_corner == ATTR_billboard_corner
	&& ATTR_pixelArt_billboard_position == ATTR_billboard_position
	&& ATTR_pixelArt_billboard_size == ATTR_billboard_size && ATTR_pixelArt_billboard_tile == ATTR_billboard_tile
	&& ATTR_pixelArt_billboard_color == ATTR_billboard_color,
	"every Billboard-layout program must declare the core billboard attributes");
_Static_assert(ATTR_lit_position == 0 && ATTR_lit_normal == 1 && ATTR_lit_color == 2
	&& ATTR_particle_corner == 0 && ATTR_particle_root == 1 && ATTR_particle_color == 2
	&& ATTR_billboard_corner == 0 && ATTR_billboard_position == 1 && ATTR_billboard_size == 2
	&& ATTR_billboard_tile == 3 && ATTR_billboard_color == 4,
	"sokol lays a buffer out in attribute slot order, which must be the order its writer writes:"
	" meshData.ms, particles.ms writeInstances, billboard.ms pushTo");
_Static_assert(ATTR_pixelArt_post_position == ATTR_copy_position && ATTR_pixelArt_blit_position == ATTR_copy_position,
	"every Fullscreen-layout program must declare the copy position");
_Static_assert(COUNT(CULL_MODES) == 3, "CULL_MODES must match Face in pass.ms");
_Static_assert(COUNT(COMPARE_FUNCTIONS) == 8, "COMPARE_FUNCTIONS must match Compare in pass.ms");
_Static_assert(COUNT(BLEND_FACTORS) == 10, "BLEND_FACTORS must match Blend in pass.ms");
_Static_assert(COUNT(BLEND_OPERATIONS) == 5, "BLEND_OPERATIONS must match Operation in pass.ms");
_Static_assert(COUNT(PIXEL_FORMATS) == 4, "PIXEL_FORMATS must match PixelFormat in gpu3d.ms");
_Static_assert(COUNT(LOAD_ACTIONS) == 3, "LOAD_ACTIONS must match LoadAction in gpu3d.ms");
_Static_assert(COUNT(FILTERS) == 2, "FILTERS must match Filter in gpu3d.ms");
_Static_assert(COUNT(WRAPS) == 3, "WRAPS must match Wrap in gpu3d.ms");
_Static_assert(COUNT(INDEX_TYPES) == 2, "INDEX_TYPES must match IndexType in gpu3d.ms");
_Static_assert(sizeof(lightParams_t) == 44 * 4, "lightParams must match LIGHT_UNIFORM_LENGTH in gpu3d.ms");
_Static_assert(sizeof(modelParams_t) == 32 * 4, "modelParams must match MODEL_LENGTH in draw.ms");
_Static_assert(sizeof(pixelArt_vertexParams_t) == sizeof(vertexParams_t)
	&& sizeof(pixelArt_lightParams_t) == sizeof(lightParams_t)
	&& sizeof(pixelArt_modelParams_t) == sizeof(modelParams_t)
	&& sizeof(pixelArt_materialParams_t) == sizeof(materialParams_t)
	&& sizeof(pixelArt_billboardParams_t) == sizeof(billboardParams_t)
	&& UB_pixelArt_vertexParams == UB_vertexParams && UB_pixelArt_lightParams == UB_lightParams
	&& UB_pixelArt_modelParams == UB_modelParams && UB_pixelArt_materialParams == UB_materialParams
	&& UB_pixelArt_billboardParams == UB_billboardParams,
	"both shader files must take the blocks of shader3dBlocks.glsl");
_Static_assert(GPU3D_UNIFORM_SLOT_TABLE_LENGTH == SG_MAX_UNIFORMBLOCK_BINDSLOTS,
	"GPU3D_UNIFORM_SLOTS must be sokol's uniform block slot count");
_Static_assert(GPU3D_PROGRAM_TABLE_LENGTH <= 16,
	"Program must fit the four bits PipelineKey and ProgramMap give it (pipelineCache.ms, programMap.ms)");

// ---- vertex layouts, one per VertexLayout member ----

enum { LAYOUT_LIT, LAYOUT_PARTICLE, LAYOUT_BILLBOARD, LAYOUT_FULLSCREEN };

static void describeLayout(uint32_t layout, sg_vertex_layout_state *out) {
	switch (layout) {
	case LAYOUT_LIT:
		// position, normal, rgba; one interleaved buffer (meshData.ms LIT_VERTEX_STRIDE)
		out->attrs[ATTR_lit_position].format = SG_VERTEXFORMAT_FLOAT3;
		out->attrs[ATTR_lit_normal].format = SG_VERTEXFORMAT_FLOAT3;
		out->attrs[ATTR_lit_color].format = SG_VERTEXFORMAT_FLOAT4;
		break;
	case LAYOUT_PARTICLE:
		// buffer 0: quad corner per vertex; buffer 1: root + rgba per instance
		out->buffers[1].step_func = SG_VERTEXSTEP_PER_INSTANCE;
		out->attrs[ATTR_particle_corner].format = SG_VERTEXFORMAT_FLOAT2;
		out->attrs[ATTR_particle_root].format = SG_VERTEXFORMAT_FLOAT4;
		out->attrs[ATTR_particle_root].buffer_index = 1;
		out->attrs[ATTR_particle_color].format = SG_VERTEXFORMAT_FLOAT4;
		out->attrs[ATTR_particle_color].buffer_index = 1;
		break;
	case LAYOUT_BILLBOARD:
		// buffer 0: quad corner per vertex; buffer 1: position, size, tile uv rect, rgba per
		// instance (billboard.ms BILLBOARD_INSTANCE_STRIDE)
		out->buffers[1].step_func = SG_VERTEXSTEP_PER_INSTANCE;
		out->attrs[ATTR_billboard_corner].format = SG_VERTEXFORMAT_FLOAT2;
		out->attrs[ATTR_billboard_position].format = SG_VERTEXFORMAT_FLOAT3;
		out->attrs[ATTR_billboard_position].buffer_index = 1;
		out->attrs[ATTR_billboard_size].format = SG_VERTEXFORMAT_FLOAT2;
		out->attrs[ATTR_billboard_size].buffer_index = 1;
		out->attrs[ATTR_billboard_tile].format = SG_VERTEXFORMAT_FLOAT4;
		out->attrs[ATTR_billboard_tile].buffer_index = 1;
		out->attrs[ATTR_billboard_color].format = SG_VERTEXFORMAT_FLOAT4;
		out->attrs[ATTR_billboard_color].buffer_index = 1;
		break;
	default:
		// clip-space position of a fullscreen triangle (copy, post, blit)
		out->attrs[ATTR_copy_position].format = SG_VERTEXFORMAT_FLOAT2;
		break;
	}
}

static int32_t formatFloats(sg_vertex_format format) {
	switch (format) {
	case SG_VERTEXFORMAT_FLOAT2: return 2;
	case SG_VERTEXFORMAT_FLOAT3: return 3;
	case SG_VERTEXFORMAT_FLOAT4: return 4;
	default: return -1;
	}
}

int32_t gpu3dLayoutFloats(int32_t layout, int32_t buffer) {
	sg_vertex_layout_state state = {0};
	describeLayout((uint32_t)layout, &state);
	int32_t floats = 0;
	for (int i = 0; i < SG_MAX_VERTEX_ATTRIBUTES; i++) {
		if (state.attrs[i].format == SG_VERTEXFORMAT_INVALID || state.attrs[i].buffer_index != buffer) {
			continue;
		}
		const int32_t size = formatFloats(state.attrs[i].format);
		if (size < 0) return -1;
		floats += size;
	}
	return floats;
}

// ---- resources ----

uint32_t gpu3dMakeShader(int32_t program) {
	return sg_make_shader(LOOKUP(PROGRAMS, program)(sg_query_backend())).id;
}

uint32_t gpu3dUniformSlotMask(int32_t program) {
	const sg_shader_desc *desc = LOOKUP(PROGRAMS, program)(sg_query_backend());
	uint32_t mask = 0;
	for (int slot = 0; slot < SG_MAX_UNIFORMBLOCK_BINDSLOTS; slot++) {
		if (desc->uniform_blocks[slot].stage != SG_SHADERSTAGE_NONE) mask |= 1u << slot;
	}
	return mask;
}

// Every backend's desc carries the same block sizes; D3D11's is always compiled in (hlsl5).
int32_t gpu3dUniformBlockBytes(int32_t program, int32_t slot) {
	if (slot < 0 || slot >= SG_MAX_UNIFORMBLOCK_BINDSLOTS) return 0;
	const sg_shader_desc *desc = LOOKUP(PROGRAMS, program)(SG_BACKEND_D3D11);
	if (desc == 0 || desc->uniform_blocks[slot].stage == SG_SHADERSTAGE_NONE) return 0;
	return (int32_t)desc->uniform_blocks[slot].size;
}

uint32_t gpu3dTextureSlotMask(int32_t program) {
	const sg_shader_desc *desc = LOOKUP(PROGRAMS, program)(SG_BACKEND_D3D11);
	uint32_t mask = 0;
	for (int slot = 0; slot < SG_MAX_VIEW_BINDSLOTS; slot++) {
		if (desc->views[slot].texture.stage != SG_SHADERSTAGE_NONE) mask |= 1u << slot;
	}
	return mask;
}

uint32_t gpu3dSamplerSlotMask(int32_t program) {
	const sg_shader_desc *desc = LOOKUP(PROGRAMS, program)(SG_BACKEND_D3D11);
	uint32_t mask = 0;
	for (int slot = 0; slot < SG_MAX_SAMPLER_BINDSLOTS; slot++) {
		if (desc->samplers[slot].stage != SG_SHADERSTAGE_NONE) mask |= 1u << slot;
	}
	return mask;
}

uint32_t gpu3dMakePipeline(const uint32_t *descriptor, int64_t length) {
	if (length < GPU3D_PIPELINE_LENGTH) return SG_INVALID_ID;
	const uint32_t *d = descriptor;
	sg_pipeline_desc desc = {0};
	desc.shader = (sg_shader){.id = d[GPU3D_PIPELINE_SHADER]};
	describeLayout(d[GPU3D_PIPELINE_LAYOUT], &desc.layout);
	desc.cull_mode = LOOKUP(CULL_MODES, d[GPU3D_PIPELINE_CULLING]);
	// glTF, the Blender exporter and the spike wind front faces counter-clockwise.
	desc.face_winding = SG_FACEWINDING_CCW;
	desc.depth.pixel_format = LOOKUP(PIXEL_FORMATS, d[GPU3D_PIPELINE_DEPTH_FORMAT]);
	desc.depth.compare = LOOKUP(COMPARE_FUNCTIONS, d[GPU3D_PIPELINE_DEPTH_TEST]);
	desc.depth.write_enabled = d[GPU3D_PIPELINE_DEPTH_WRITE] != 0;
	desc.sample_count = (int)d[GPU3D_PIPELINE_SAMPLE_COUNT];
	desc.index_type = LOOKUP(INDEX_TYPES, d[GPU3D_PIPELINE_INDEX_TYPE]);

	sg_blend_state blend = {0};
	blend.src_factor_rgb = LOOKUP(BLEND_FACTORS, d[GPU3D_PIPELINE_BLEND_SOURCE]);
	blend.dst_factor_rgb = LOOKUP(BLEND_FACTORS, d[GPU3D_PIPELINE_BLEND_DESTINATION]);
	blend.src_factor_alpha = LOOKUP(BLEND_FACTORS, d[GPU3D_PIPELINE_BLEND_ALPHA_SOURCE]);
	blend.dst_factor_alpha = LOOKUP(BLEND_FACTORS, d[GPU3D_PIPELINE_BLEND_ALPHA_DESTINATION]);
	blend.op_rgb = LOOKUP(BLEND_OPERATIONS, d[GPU3D_PIPELINE_BLEND_OPERATION]);
	blend.op_alpha = LOOKUP(BLEND_OPERATIONS, d[GPU3D_PIPELINE_BLEND_ALPHA_OPERATION]);
	// One/Zero/Add on both channels is Heaps' "no blending" (Pass.blend(One, Zero)).
	blend.enabled = !(blend.src_factor_rgb == SG_BLENDFACTOR_ONE && blend.dst_factor_rgb == SG_BLENDFACTOR_ZERO
		&& blend.src_factor_alpha == SG_BLENDFACTOR_ONE && blend.dst_factor_alpha == SG_BLENDFACTOR_ZERO
		&& blend.op_rgb == SG_BLENDOP_ADD && blend.op_alpha == SG_BLENDOP_ADD);
	// Heaps colorMask bits (r=1, g=2, b=4, a=8) are sokol's; an empty mask needs the explicit NONE.
	uint32_t mask = d[GPU3D_PIPELINE_COLOR_MASK] & 15;
	sg_color_mask writeMask = mask == 0 ? SG_COLORMASK_NONE : (sg_color_mask)mask;

	int colorCount = 0;
	for (int i = 0; i < GPU3D_MAX_COLOR_ATTACHMENTS; i++) {
		uint32_t format = d[GPU3D_PIPELINE_COLOR_FORMAT + i];
		if (format == FORMAT_NONE) break;
		desc.colors[i].pixel_format = LOOKUP(PIXEL_FORMATS, format);
		desc.colors[i].write_mask = writeMask;
		desc.colors[i].blend = blend;
		colorCount = i + 1;
	}
	desc.color_count = colorCount;
	return sg_make_pipeline(&desc).id;
}

uint32_t gpu3dMakeVertexBuffer(const float *data, int64_t length) {
	// sokol validates size > 0 and _SG_PANICs on failure, so an empty buffer would abort the
	// process rather than return an invalid id, as gpu3dMakeImage already guards against.
	if (length <= 0) return SG_INVALID_ID;
	sg_buffer_desc desc = {0};
	desc.usage.vertex_buffer = true;
	desc.data.ptr = data;
	desc.data.size = (size_t)length * sizeof(float);
	return sg_make_buffer(&desc).id;
}

uint32_t gpu3dMakeIndexBuffer(const uint16_t *data, int64_t length) {
	if (length <= 0) return SG_INVALID_ID;
	sg_buffer_desc desc = {0};
	desc.usage.index_buffer = true;
	desc.data.ptr = data;
	desc.data.size = (size_t)length * sizeof(uint16_t);
	return sg_make_buffer(&desc).id;
}

uint32_t gpu3dMakeStreamBuffer(int64_t length) {
	if (length <= 0) return SG_INVALID_ID;
	sg_buffer_desc desc = {0};
	desc.usage.vertex_buffer = true;
	desc.usage.dynamic_update = true;
	desc.size = (size_t)length * sizeof(float);
	return sg_make_buffer(&desc).id;
}

int32_t gpu3dUpdateBuffer(uint32_t buffer, const float *data, int64_t length) {
	sg_buffer handle = {.id = buffer};
	if (length <= 0 || sg_query_buffer_state(handle) != SG_RESOURCESTATE_VALID) return 0;
	const size_t size = (size_t)length * sizeof(float);
	if (size > sg_query_buffer_size(handle)) return 0;
	sg_update_buffer(handle, &(sg_range){.ptr = data, .size = size});
	return 1;
}

uint32_t gpu3dMakeImage(const uint32_t *rgba, int64_t length, int32_t width, int32_t height) {
	if (width <= 0 || height <= 0 || length < (int64_t)width * height) return SG_INVALID_ID;
	sg_image_desc desc = {0};
	desc.width = width;
	desc.height = height;
	desc.pixel_format = SG_PIXELFORMAT_RGBA8;
	desc.data.mip_levels[0].ptr = rgba;
	desc.data.mip_levels[0].size = (size_t)width * (size_t)height * 4;
	return sg_make_image(&desc).id;
}

uint32_t gpu3dMakeTargetImage(int32_t width, int32_t height, int32_t format) {
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

uint32_t gpu3dMakeAttachmentView(uint32_t image, int32_t format) {
	sg_view_desc desc = {0};
	if (format == FORMAT_DEPTH) {
		desc.depth_stencil_attachment.image = (sg_image){.id = image};
	} else {
		desc.color_attachment.image = (sg_image){.id = image};
	}
	return sg_make_view(&desc).id;
}

uint32_t gpu3dMakeTextureView(uint32_t image) {
	sg_view_desc desc = {0};
	desc.texture.image = (sg_image){.id = image};
	return sg_make_view(&desc).id;
}

uint32_t gpu3dMakeSampler(int32_t filter, int32_t wrap) {
	sg_sampler_desc desc = {0};
	desc.min_filter = LOOKUP(FILTERS, filter);
	desc.mag_filter = LOOKUP(FILTERS, filter);
	desc.wrap_u = LOOKUP(WRAPS, wrap);
	desc.wrap_v = LOOKUP(WRAPS, wrap);
	return sg_make_sampler(&desc).id;
}

uint32_t gpu3dMakeDynamicImage(int32_t width, int32_t height) {
	if (width <= 0 || height <= 0) return SG_INVALID_ID;
	sg_image_desc desc = {0};
	desc.usage.dynamic_update = true;
	desc.width = width;
	desc.height = height;
	desc.pixel_format = SG_PIXELFORMAT_RGBA8;
	return sg_make_image(&desc).id;
}

void gpu3dUpdateImage(uint32_t image, const uint32_t *rgba, int64_t length) {
	sg_image handle = {.id = image};
	if (sg_query_image_state(handle) != SG_RESOURCESTATE_VALID) return;
	const int width = sg_query_image_width(handle);
	const int height = sg_query_image_height(handle);
	if (length < (int64_t)width * height) return;
	sg_image_data data = {0};
	data.mip_levels[0].ptr = rgba;
	data.mip_levels[0].size = (size_t)width * (size_t)height * 4;
	sg_update_image(handle, &data);
}

void gpu3dDestroyShader(uint32_t shader) { sg_destroy_shader((sg_shader){.id = shader}); }
void gpu3dDestroyPipeline(uint32_t pipeline) { sg_destroy_pipeline((sg_pipeline){.id = pipeline}); }
void gpu3dDestroyBuffer(uint32_t buffer) { sg_destroy_buffer((sg_buffer){.id = buffer}); }
void gpu3dDestroyImage(uint32_t image) { sg_destroy_image((sg_image){.id = image}); }
void gpu3dDestroyView(uint32_t view) { sg_destroy_view((sg_view){.id = view}); }
void gpu3dDestroySampler(uint32_t sampler) { sg_destroy_sampler((sg_sampler){.id = sampler}); }

// ---- frame ----

void gpu3dBeginPass(const uint32_t *descriptor, int64_t length, const float *clear, int64_t clearLength) {
	if (length < GPU3D_PASS_LENGTH || clearLength < GPU3D_PASS_CLEAR_LENGTH) return;
	sg_pass pass = {0};
	for (int i = 0; i < GPU3D_MAX_COLOR_ATTACHMENTS; i++) {
		pass.attachments.colors[i] = (sg_view){.id = descriptor[GPU3D_PASS_COLOR_VIEW + i]};
		pass.action.colors[i].load_action = LOOKUP(LOAD_ACTIONS, descriptor[GPU3D_PASS_COLOR_LOAD + i]);
		pass.action.colors[i].clear_value = (sg_color){clear[i * 4], clear[i * 4 + 1], clear[i * 4 + 2], clear[i * 4 + 3]};
	}
	pass.attachments.depth_stencil = (sg_view){.id = descriptor[GPU3D_PASS_DEPTH_VIEW]};
	pass.action.depth.load_action = LOOKUP(LOAD_ACTIONS, descriptor[GPU3D_PASS_DEPTH_LOAD]);
	pass.action.depth.clear_value = clear[GPU3D_PASS_CLEAR_DEPTH];
	sg_begin_pass(&pass);
}

// The swapchain differs per host (sokol_app, EGL, the iOS/macOS embed), so the platform
// bridge owns it; it clears color to the given value and depth to 1.
void gpu3dBeginSwapchainPass(float red, float green, float blue, float alpha) {
	voidBeginPass(red, green, blue, alpha);
}

void gpu3dApplyPipeline(uint32_t pipeline) {
	sg_apply_pipeline((sg_pipeline){.id = pipeline});
}

void gpu3dApplyBindings(const uint32_t *bindings, int64_t length) {
	if (length < GPU3D_BINDING_LENGTH) return;
	sg_bindings desc = {0};
	for (int i = 0; i < 2; i++) {
		desc.vertex_buffers[i] = (sg_buffer){.id = bindings[GPU3D_BINDING_VERTEX_BUFFER + i]};
		desc.samplers[i] = (sg_sampler){.id = bindings[GPU3D_BINDING_SAMPLER + i]};
	}
	desc.index_buffer = (sg_buffer){.id = bindings[GPU3D_BINDING_INDEX_BUFFER]};
	for (int i = 0; i < GPU3D_MAX_COLOR_ATTACHMENTS; i++) {
		desc.views[i] = (sg_view){.id = bindings[GPU3D_BINDING_VIEW + i]};
	}
	sg_apply_bindings(&desc);
}

void gpu3dApplyUniforms(int32_t slot, const float *data, int64_t length) {
	sg_range range = {.ptr = data, .size = (size_t)length * sizeof(float)};
	sg_apply_uniforms(slot, &range);
}

void gpu3dDraw(int32_t base, int32_t count, int32_t instances) {
	sg_draw(base, count, instances);
}

void gpu3dEndPass(void) { sg_end_pass(); }

// ---- backend conventions ----

int32_t gpu3dOriginTopLeft(void) { return sg_query_features().origin_top_left ? 1 : 0; }

int32_t gpu3dDepthZeroToOne(void) {
	const sg_backend backend = sg_query_backend();
	return backend == SG_BACKEND_GLCORE || backend == SG_BACKEND_GLES3 ? 0 : 1;
}

int32_t gpu3dContextGeneration(void) {
#if defined(__ANDROID__)
	return voidGpuGeneration();
#else
	return 1;
#endif
}
