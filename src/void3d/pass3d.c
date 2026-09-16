#include "pass3d.h"
#include "../sokol/bridge.h"
#include "../../deps/sokol/sokol_gfx.h"
#include "shader3d.glsl.h"

typedef struct {
	int width;
	int height;
	sg_image colorImage;
	sg_image normalImage;
	sg_image depthImage;
	sg_image postImage;
	sg_view colorAttachment;
	sg_view normalAttachment;
	sg_view depthAttachment;
	sg_view postAttachment;
	sg_view colorTexture;
	sg_view normalTexture;
	sg_view postTexture;
} Void3dTargets;

static Void3dTargets s_targets;
static sg_pipeline s_litPipeline;
static sg_pipeline s_billboardPipeline;
static sg_pipeline s_postPipeline;
static sg_pipeline s_blitPipeline;
static sg_buffer s_cornerBuffer;
static sg_buffer s_fullscreenBuffer;
static sg_sampler s_pointSampler;

static const float CORNERS[12] = {
	-0.5f, 0.0f, 0.5f, 0.0f, 0.5f, 1.0f,
	-0.5f, 0.0f, 0.5f, 1.0f, -0.5f, 1.0f,
};

static const float FULLSCREEN_TRIANGLE[6] = {
	-1.0f, -1.0f, 3.0f, -1.0f, -1.0f, 3.0f,
};

static sg_buffer makeStaticBuffer(const void *data, size_t byteCount) {
	sg_buffer_desc desc = {0};
	desc.usage.vertex_buffer = true;
	desc.data.ptr = data;
	desc.data.size = byteCount;
	return sg_make_buffer(&desc);
}

static void useSceneTargets(sg_pipeline_desc *desc) {
	desc->depth.pixel_format = SG_PIXELFORMAT_DEPTH;
	desc->depth.compare = SG_COMPAREFUNC_LESS_EQUAL;
	desc->depth.write_enabled = true;
	desc->color_count = 2;
	desc->colors[0].pixel_format = SG_PIXELFORMAT_RGBA8;
	desc->colors[1].pixel_format = SG_PIXELFORMAT_RGBA8;
	desc->sample_count = 1;
}

void void3dSetup(void) {
	s_cornerBuffer = makeStaticBuffer(CORNERS, sizeof(CORNERS));
	s_fullscreenBuffer = makeStaticBuffer(FULLSCREEN_TRIANGLE, sizeof(FULLSCREEN_TRIANGLE));

	sg_sampler_desc samplerDesc = {0};
	samplerDesc.min_filter = SG_FILTER_NEAREST;
	samplerDesc.mag_filter = SG_FILTER_NEAREST;
	samplerDesc.wrap_u = SG_WRAP_CLAMP_TO_EDGE;
	samplerDesc.wrap_v = SG_WRAP_CLAMP_TO_EDGE;
	s_pointSampler = sg_make_sampler(&samplerDesc);

	sg_pipeline_desc lit = {0};
	lit.shader = sg_make_shader(lit_shader_desc(sg_query_backend()));
	lit.layout.attrs[ATTR_lit_position].format = SG_VERTEXFORMAT_FLOAT3;
	lit.layout.attrs[ATTR_lit_normal].format = SG_VERTEXFORMAT_FLOAT3;
	lit.layout.attrs[ATTR_lit_color].format = SG_VERTEXFORMAT_FLOAT4;
	useSceneTargets(&lit);
	s_litPipeline = sg_make_pipeline(&lit);

	sg_pipeline_desc billboard = {0};
	billboard.shader = sg_make_shader(billboard_shader_desc(sg_query_backend()));
	billboard.layout.buffers[1].step_func = SG_VERTEXSTEP_PER_INSTANCE;
	billboard.layout.attrs[ATTR_billboard_corner].format = SG_VERTEXFORMAT_FLOAT2;
	billboard.layout.attrs[ATTR_billboard_root].format = SG_VERTEXFORMAT_FLOAT4;
	billboard.layout.attrs[ATTR_billboard_root].buffer_index = 1;
	billboard.layout.attrs[ATTR_billboard_shape].format = SG_VERTEXFORMAT_FLOAT4;
	billboard.layout.attrs[ATTR_billboard_shape].buffer_index = 1;
	useSceneTargets(&billboard);
	s_billboardPipeline = sg_make_pipeline(&billboard);

	sg_pipeline_desc post = {0};
	post.shader = sg_make_shader(post_shader_desc(sg_query_backend()));
	post.layout.attrs[ATTR_post_position].format = SG_VERTEXFORMAT_FLOAT2;
	post.depth.pixel_format = SG_PIXELFORMAT_NONE;
	post.colors[0].pixel_format = SG_PIXELFORMAT_RGBA8;
	post.sample_count = 1;
	s_postPipeline = sg_make_pipeline(&post);

	sg_pipeline_desc blit = {0};
	blit.shader = sg_make_shader(blit_shader_desc(sg_query_backend()));
	blit.layout.attrs[ATTR_blit_position].format = SG_VERTEXFORMAT_FLOAT2;
	s_blitPipeline = sg_make_pipeline(&blit);
}

static sg_image makeTargetImage(int width, int height, sg_pixel_format format) {
	sg_image_desc desc = {0};
	if (format == SG_PIXELFORMAT_DEPTH) {
		desc.usage.depth_stencil_attachment = true;
	} else {
		desc.usage.color_attachment = true;
	}
	desc.width = width;
	desc.height = height;
	desc.pixel_format = format;
	desc.sample_count = 1;
	return sg_make_image(&desc);
}

static sg_view makeColorAttachment(sg_image image) {
	sg_view_desc desc = {0};
	desc.color_attachment.image = image;
	return sg_make_view(&desc);
}

static sg_view makeDepthAttachment(sg_image image) {
	sg_view_desc desc = {0};
	desc.depth_stencil_attachment.image = image;
	return sg_make_view(&desc);
}

static sg_view makeTextureView(sg_image image) {
	sg_view_desc desc = {0};
	desc.texture.image = image;
	return sg_make_view(&desc);
}

static void destroyTargets(void) {
	if (s_targets.width == 0) return;
	sg_destroy_view(s_targets.colorAttachment);
	sg_destroy_view(s_targets.normalAttachment);
	sg_destroy_view(s_targets.depthAttachment);
	sg_destroy_view(s_targets.postAttachment);
	sg_destroy_view(s_targets.colorTexture);
	sg_destroy_view(s_targets.normalTexture);
	sg_destroy_view(s_targets.postTexture);
	sg_destroy_image(s_targets.colorImage);
	sg_destroy_image(s_targets.normalImage);
	sg_destroy_image(s_targets.depthImage);
	sg_destroy_image(s_targets.postImage);
	s_targets = (Void3dTargets){0};
}

void void3dResize(int lowWidth, int lowHeight) {
	if (lowWidth <= 0 || lowHeight <= 0) return;
	if (lowWidth == s_targets.width && lowHeight == s_targets.height) return;
	destroyTargets();
	s_targets.width = lowWidth;
	s_targets.height = lowHeight;
	s_targets.colorImage = makeTargetImage(lowWidth, lowHeight, SG_PIXELFORMAT_RGBA8);
	s_targets.normalImage = makeTargetImage(lowWidth, lowHeight, SG_PIXELFORMAT_RGBA8);
	s_targets.depthImage = makeTargetImage(lowWidth, lowHeight, SG_PIXELFORMAT_DEPTH);
	s_targets.postImage = makeTargetImage(lowWidth, lowHeight, SG_PIXELFORMAT_RGBA8);
	s_targets.colorAttachment = makeColorAttachment(s_targets.colorImage);
	s_targets.normalAttachment = makeColorAttachment(s_targets.normalImage);
	s_targets.depthAttachment = makeDepthAttachment(s_targets.depthImage);
	s_targets.postAttachment = makeColorAttachment(s_targets.postImage);
	s_targets.colorTexture = makeTextureView(s_targets.colorImage);
	s_targets.normalTexture = makeTextureView(s_targets.normalImage);
	s_targets.postTexture = makeTextureView(s_targets.postImage);
}

uint32_t void3dMakeBuffer(const float *data, int byteCount) {
	return makeStaticBuffer(data, (size_t)byteCount).id;
}

uint32_t void3dMakeTexture(const uint32_t *rgba, int width, int height) {
	sg_image_desc desc = {0};
	desc.width = width;
	desc.height = height;
	desc.pixel_format = SG_PIXELFORMAT_RGBA8;
	desc.data.mip_levels[0].ptr = rgba;
	desc.data.mip_levels[0].size = (size_t)(width * height * 4);
	return makeTextureView(sg_make_image(&desc)).id;
}

void void3dBeginScene(float red, float green, float blue) {
	sg_pass pass = {0};
	pass.action.colors[0].load_action = SG_LOADACTION_CLEAR;
	pass.action.colors[0].clear_value = (sg_color){red, green, blue, 0.0f};
	pass.action.colors[1].load_action = SG_LOADACTION_CLEAR;
	pass.action.colors[1].clear_value = (sg_color){0.5f, 1.0f, 0.5f, 1.0f};
	pass.action.depth.load_action = SG_LOADACTION_CLEAR;
	pass.action.depth.clear_value = 1.0f;
	pass.attachments.colors[0] = s_targets.colorAttachment;
	pass.attachments.colors[1] = s_targets.normalAttachment;
	pass.attachments.depth_stencil = s_targets.depthAttachment;
	sg_begin_pass(&pass);
}

static void applySceneParams(const float *vertexParams, const float *lightParams) {
	sg_range vertexRange = {.ptr = vertexParams, .size = sizeof(vertexParams_t)};
	sg_range lightRange = {.ptr = lightParams, .size = sizeof(lightParams_t)};
	sg_apply_uniforms(UB_vertexParams, &vertexRange);
	sg_apply_uniforms(UB_lightParams, &lightRange);
}

void void3dDrawLit(uint32_t buffer, int vertexCount, const float *vertexParams, const float *lightParams) {
	sg_apply_pipeline(s_litPipeline);
	sg_bindings bindings = {0};
	bindings.vertex_buffers[0] = (sg_buffer){.id = buffer};
	sg_apply_bindings(&bindings);
	applySceneParams(vertexParams, lightParams);
	sg_draw(0, vertexCount, 1);
}

void void3dDrawBillboards(uint32_t instances, int instanceCount, uint32_t texture, const float *vertexParams, const float *lightParams) {
	sg_apply_pipeline(s_billboardPipeline);
	sg_bindings bindings = {0};
	bindings.vertex_buffers[0] = s_cornerBuffer;
	bindings.vertex_buffers[1] = (sg_buffer){.id = instances};
	bindings.views[VIEW_spriteTexture] = (sg_view){.id = texture};
	bindings.samplers[SMP_spriteSampler] = s_pointSampler;
	sg_apply_bindings(&bindings);
	applySceneParams(vertexParams, lightParams);
	sg_draw(0, 6, instanceCount);
}

void void3dEndScene(void) {
	sg_end_pass();
}

void void3dPost(const float *postParams) {
	sg_pass pass = {0};
	pass.action.colors[0].load_action = SG_LOADACTION_DONTCARE;
	pass.attachments.colors[0] = s_targets.postAttachment;
	sg_begin_pass(&pass);
	sg_apply_pipeline(s_postPipeline);
	sg_bindings bindings = {0};
	bindings.vertex_buffers[0] = s_fullscreenBuffer;
	bindings.views[VIEW_colorTexture] = s_targets.colorTexture;
	bindings.views[VIEW_normalTexture] = s_targets.normalTexture;
	bindings.samplers[SMP_pointSampler] = s_pointSampler;
	sg_apply_bindings(&bindings);
	sg_range range = {.ptr = postParams, .size = sizeof(postParams_t)};
	sg_apply_uniforms(UB_postParams, &range);
	sg_draw(0, 3, 1);
	sg_end_pass();
}

void void3dPresent(float pixelScale, float offsetX, float offsetY) {
	voidBeginPass(0.0f, 0.0f, 0.0f, 1.0f);
	sg_apply_pipeline(s_blitPipeline);
	sg_bindings bindings = {0};
	bindings.vertex_buffers[0] = s_fullscreenBuffer;
	bindings.views[VIEW_sceneTexture] = s_targets.postTexture;
	bindings.samplers[SMP_pointSampler] = s_pointSampler;
	sg_apply_bindings(&bindings);
	blitParams_t params = {.pixel = {pixelScale, pixelScale, offsetX, offsetY}};
	sg_range range = SG_RANGE(params);
	sg_apply_uniforms(UB_blitParams, &range);
	sg_draw(0, 3, 1);
	sg_end_pass();
	sg_commit();
}
