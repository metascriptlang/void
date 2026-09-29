#include "gpu3d.h"
#include "../gpu/door.h"
#include "../../deps/sokol/sokol_gfx.h"
#include "shader3d.glsl.h"
#include "pixelArt3d.glsl.h"

// ---- void3d's programs and layouts, registered with the GPU door ----

typedef const sg_shader_desc *(*ShaderDescription)(sg_backend backend);

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

// ---- vertex layouts, one per VertexLayout member ----

enum { LAYOUT_LIT, LAYOUT_PARTICLE, LAYOUT_BILLBOARD, LAYOUT_FULLSCREEN };

// The layout each program reads, in PROGRAMS order. gpu3d.ms vertexLayoutOf is the MetaScript
// twin of this table; tests hold the two together through the door's own answer
// (doorProgramLayout against both bases), so a program moved to another layout here without
// its MetaScript map moving is a red test, not a wrong pipeline.
static const int32_t PROGRAM_LAYOUTS[GPU3D_PROGRAM_TABLE_LENGTH] = {
	LAYOUT_LIT,
	LAYOUT_PARTICLE,
	LAYOUT_BILLBOARD,
	LAYOUT_FULLSCREEN,
	LAYOUT_LIT,
	LAYOUT_PARTICLE,
	LAYOUT_BILLBOARD,
	LAYOUT_FULLSCREEN,
	LAYOUT_FULLSCREEN,
};

static void describeLayout(uint32_t layout, sg_vertex_layout_state *out) {
	switch (layout) {
	case LAYOUT_LIT:
		// position, normal, rgba; one interleaved buffer (meshData.ms LIT_VERTEX_STRIDE)
		out->attrs[ATTR_lit_position].format = SG_VERTEXFORMAT_FLOAT3;
		out->attrs[ATTR_lit_normal].format = SG_VERTEXFORMAT_FLOAT3;
		out->attrs[ATTR_lit_color].format = SG_VERTEXFORMAT_FLOAT4;
		break;
	case LAYOUT_PARTICLE:
		// buffer 0: root + rgba per instance; the vertex index makes the corners (quadCorner).
		// WGPU and Vulkan end the buffer list at the first empty slot: never leave slot 0 empty.
		out->buffers[0].step_func = SG_VERTEXSTEP_PER_INSTANCE;
		out->attrs[ATTR_particle_root].format = SG_VERTEXFORMAT_FLOAT4;
		out->attrs[ATTR_particle_color].format = SG_VERTEXFORMAT_FLOAT4;
		break;
	case LAYOUT_BILLBOARD:
		// buffer 0: position, size, anchor, tile uv rect, rgba per instance (billboard.ms
		// BILLBOARD_INSTANCE_STRIDE); the vertex index makes the corners (quadCorner)
		out->buffers[0].step_func = SG_VERTEXSTEP_PER_INSTANCE;
		out->attrs[ATTR_billboard_position].format = SG_VERTEXFORMAT_FLOAT3;
		out->attrs[ATTR_billboard_size].format = SG_VERTEXFORMAT_FLOAT2;
		out->attrs[ATTR_billboard_anchor].format = SG_VERTEXFORMAT_FLOAT2;
		out->attrs[ATTR_billboard_tile].format = SG_VERTEXFORMAT_FLOAT4;
		out->attrs[ATTR_billboard_color].format = SG_VERTEXFORMAT_FLOAT4;
		break;
	default:
		// clip-space position of a fullscreen triangle (copy, post, blit)
		out->attrs[ATTR_copy_position].format = SG_VERTEXFORMAT_FLOAT2;
		break;
	}
}

// One entry per MetaScript enum member. These catch a member added on one side only; the
// order still has to be kept by hand (and is covered by the scene image check).
_Static_assert(sizeof(PROGRAMS) / sizeof(PROGRAMS[0]) == GPU3D_PROGRAM_TABLE_LENGTH,
	"PROGRAMS must match Program in gpu3d.ms");
_Static_assert(ATTR_pixelArt_lit_position == ATTR_lit_position && ATTR_pixelArt_lit_normal == ATTR_lit_normal
	&& ATTR_pixelArt_lit_color == ATTR_lit_color, "every Lit-layout program must declare the core lit attributes");
_Static_assert(ATTR_pixelArt_particle_root == ATTR_particle_root && ATTR_pixelArt_particle_color == ATTR_particle_color,
	"every Particle-layout program must declare the core particle attributes");
_Static_assert(ATTR_pixelArt_billboard_position == ATTR_billboard_position
	&& ATTR_pixelArt_billboard_size == ATTR_billboard_size && ATTR_pixelArt_billboard_anchor == ATTR_billboard_anchor
	&& ATTR_pixelArt_billboard_tile == ATTR_billboard_tile && ATTR_pixelArt_billboard_color == ATTR_billboard_color,
	"every Billboard-layout program must declare the core billboard attributes");
_Static_assert(ATTR_lit_position == 0 && ATTR_lit_normal == 1 && ATTR_lit_color == 2
	&& ATTR_particle_root == 0 && ATTR_particle_color == 1
	&& ATTR_billboard_position == 0 && ATTR_billboard_size == 1 && ATTR_billboard_anchor == 2
	&& ATTR_billboard_tile == 3 && ATTR_billboard_color == 4,
	"sokol lays a buffer out in attribute slot order, which must be the order its writer writes:"
	" meshData.ms, particles.ms writeInstances, billboard.ms pushTo");
_Static_assert(ATTR_pixelArt_post_position == ATTR_copy_position && ATTR_pixelArt_blit_position == ATTR_copy_position,
	"every Fullscreen-layout program must declare the copy position");
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

static int32_t g_programBase = -1;
static int32_t g_layoutBase = -1;

static void registerOnce(void) {
	if (g_programBase >= 0) { return; }
	sg_vertex_layout_state layouts[4] = {0};
	for (uint32_t i = 0; i < 4; i++) {
		describeLayout(i, &layouts[i]);
	}
	g_layoutBase = doorRegisterLayouts(layouts, 4);
	int32_t programLayouts[GPU3D_PROGRAM_TABLE_LENGTH];
	for (int32_t i = 0; i < GPU3D_PROGRAM_TABLE_LENGTH; i++) {
		programLayouts[i] = g_layoutBase + PROGRAM_LAYOUTS[i];
	}
	g_programBase = doorRegisterPrograms(PROGRAMS, programLayouts, GPU3D_PROGRAM_TABLE_LENGTH);
}

int32_t gpu3dProgramBase(void) {
	registerOnce();
	return g_programBase;
}

int32_t gpu3dLayoutBase(void) {
	registerOnce();
	return g_layoutBase;
}

// ---- buffers, images and the draw path (the door owns what both layers share) ----

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

void gpu3dDestroyBuffer(uint32_t buffer) { sg_destroy_buffer((sg_buffer){.id = buffer}); }
void gpu3dDestroyImage(uint32_t image) { sg_destroy_image((sg_image){.id = image}); }

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
	for (int i = 0; i < DOOR_MAX_COLOR_ATTACHMENTS; i++) {
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
