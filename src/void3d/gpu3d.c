#include "gpu3d.h"
#include "../sokol/bridge.h"
#include "../../deps/sokol/sokol_gfx.h"
#include "shader3d.glsl.h"

// ---- enum tables, indexed by MetaScript ordinal (same order as gpu3d.ms / pass.ms) ----

typedef const sg_shader_desc *(*ShaderDescription)(sg_backend backend);

// Program
static const ShaderDescription PROGRAMS[] = {
	lit_shader_desc,
	billboard_shader_desc,
	post_shader_desc,
	blit_shader_desc,
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
// order still has to be kept by hand (and is covered by the campfire image check).
_Static_assert(COUNT(PROGRAMS) == 4, "PROGRAMS must match Program in gpu3d.ms");
_Static_assert(COUNT(CULL_MODES) == 3, "CULL_MODES must match Face in pass.ms");
_Static_assert(COUNT(COMPARE_FUNCTIONS) == 8, "COMPARE_FUNCTIONS must match Compare in pass.ms");
_Static_assert(COUNT(BLEND_FACTORS) == 10, "BLEND_FACTORS must match Blend in pass.ms");
_Static_assert(COUNT(BLEND_OPERATIONS) == 5, "BLEND_OPERATIONS must match Operation in pass.ms");
_Static_assert(COUNT(PIXEL_FORMATS) == 4, "PIXEL_FORMATS must match PixelFormat in gpu3d.ms");
_Static_assert(COUNT(LOAD_ACTIONS) == 3, "LOAD_ACTIONS must match LoadAction in gpu3d.ms");
_Static_assert(COUNT(FILTERS) == 2, "FILTERS must match Filter in gpu3d.ms");
_Static_assert(COUNT(WRAPS) == 3, "WRAPS must match Wrap in gpu3d.ms");
_Static_assert(COUNT(INDEX_TYPES) == 2, "INDEX_TYPES must match IndexType in gpu3d.ms");

// ---- vertex layouts, one per VertexLayout member ----

enum { LAYOUT_LIT, LAYOUT_BILLBOARD, LAYOUT_FULLSCREEN };

static void describeLayout(uint32_t layout, sg_vertex_layout_state *out) {
	switch (layout) {
	case LAYOUT_LIT:
		// position, normal, rgba; one interleaved buffer (mesh.ms LIT_VERTEX_STRIDE)
		out->attrs[ATTR_lit_position].format = SG_VERTEXFORMAT_FLOAT3;
		out->attrs[ATTR_lit_normal].format = SG_VERTEXFORMAT_FLOAT3;
		out->attrs[ATTR_lit_color].format = SG_VERTEXFORMAT_FLOAT4;
		break;
	case LAYOUT_BILLBOARD:
		// buffer 0: quad corner per vertex; buffer 1: root + shape per instance
		out->buffers[1].step_func = SG_VERTEXSTEP_PER_INSTANCE;
		out->attrs[ATTR_billboard_corner].format = SG_VERTEXFORMAT_FLOAT2;
		out->attrs[ATTR_billboard_root].format = SG_VERTEXFORMAT_FLOAT4;
		out->attrs[ATTR_billboard_root].buffer_index = 1;
		out->attrs[ATTR_billboard_shape].format = SG_VERTEXFORMAT_FLOAT4;
		out->attrs[ATTR_billboard_shape].buffer_index = 1;
		break;
	default:
		// clip-space position of a fullscreen triangle (post, blit)
		out->attrs[ATTR_post_position].format = SG_VERTEXFORMAT_FLOAT2;
		break;
	}
}

// ---- resources ----

uint32_t gpu3dMakeShader(int32_t program) {
	return sg_make_shader(LOOKUP(PROGRAMS, program)(sg_query_backend())).id;
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
	sg_buffer_desc desc = {0};
	desc.usage.vertex_buffer = true;
	desc.data.ptr = data;
	desc.data.size = (size_t)length * sizeof(float);
	return sg_make_buffer(&desc).id;
}

uint32_t gpu3dMakeIndexBuffer(const uint16_t *data, int64_t length) {
	sg_buffer_desc desc = {0};
	desc.usage.index_buffer = true;
	desc.data.ptr = data;
	desc.data.size = (size_t)length * sizeof(uint16_t);
	return sg_make_buffer(&desc).id;
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
void gpu3dCommit(void) { sg_commit(); }

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
