// Void Dawn/WebGPU — GPU instance, device, pipeline, buffer, render
// All handles are opaque pointers.

#ifndef VOID_DAWN_H
#define VOID_DAWN_H

#include <stdint.h>

// GPU init
void *void_gpu_create_instance(void);
void *void_gpu_create_surface(void *instance, void *window);
void *void_gpu_request_adapter(void *instance, void *surface);
void *void_gpu_request_device(void *adapter);
void *void_gpu_get_queue(void *device);
void void_gpu_configure_surface(void *surface, void *device, uint32_t width, uint32_t height);

// Shader & Pipeline
void *void_gpu_create_shader(void *device, const char *wgsl_source);
void *void_gpu_create_render_pipeline(void *device, void *shader,
    const char *vs_entry, const char *fs_entry);
void *void_gpu_create_render_pipeline_vb(void *device, void *shader,
    const char *vs_entry, const char *fs_entry,
    uint32_t buffer_count, uint64_t *strides, uint32_t *attr_counts,
    uint32_t *formats, uint64_t *attr_offsets, uint32_t *locations);
void *void_gpu_create_render_pipeline_1vb(void *device, void *shader,
    const char *vs_entry, const char *fs_entry,
    uint64_t stride, uint32_t attr_count,
    uint32_t fmt0, uint64_t off0, uint32_t loc0,
    uint32_t fmt1, uint64_t off1, uint32_t loc1);

// Buffer
void *void_gpu_create_buffer(void *device, uint64_t size, uint32_t usage, int mapped_at_creation);
void *void_gpu_buffer_get_mapped_range(void *buffer, uint64_t offset, uint64_t size);
void  void_gpu_buffer_unmap(void *buffer);
void  void_gpu_queue_write_buffer(void *queue, void *buffer, uint64_t offset, const void *data, uint64_t size);
void  void_gpu_buffer_write_floats(void *buffer, const float *data, uint32_t count);
void  void_gpu_mapped_write_float(void *mapped, uint32_t index, float value);

// Frame
void *void_gpu_get_current_texture_view(void *surface);
void *void_gpu_create_command_encoder(void *device);
void *void_gpu_begin_render_pass(void *encoder, void *view,
    double r, double g, double b, double a);
void void_gpu_render_pass_set_pipeline(void *pass, void *pipeline);
void void_gpu_render_pass_set_vertex_buffer(void *pass, uint32_t slot, void *buffer, uint64_t offset, uint64_t size);
void void_gpu_render_pass_draw(void *pass, uint32_t vertex_count);
void void_gpu_end_render_pass(void *pass);
void *void_gpu_finish_encoder(void *encoder);
void void_gpu_submit(void *queue, void *command);
void void_gpu_present(void *surface);

// Bind Group & Pipeline Layout
void *void_gpu_create_bind_group_layout_1buf(
    void *device, uint32_t binding, uint32_t visibility, uint64_t minBindingSize);
void *void_gpu_create_bind_group_1buf(
    void *device, void *layout, uint32_t binding, void *buffer,
    uint64_t offset, uint64_t size);
void *void_gpu_create_pipeline_layout_1bg(void *device, void *bindGroupLayout);
void void_gpu_render_pass_set_bind_group(void *pass, uint32_t index, void *bindGroup);

// Index Buffer
void void_gpu_render_pass_set_index_buffer(
    void *pass, void *buffer, uint32_t format, uint64_t offset, uint64_t size);
void void_gpu_render_pass_draw_indexed(
    void *pass, uint32_t indexCount, uint32_t instanceCount,
    uint32_t firstIndex, int32_t baseVertex, uint32_t firstInstance);
void void_gpu_mapped_write_u16(void *mapped, uint32_t index, uint16_t value);
void void_gpu_mapped_write_u32(void *mapped, uint32_t index, uint32_t value);

// Depth Texture
void *void_gpu_create_depth_texture(void *device, uint32_t width, uint32_t height);
void *void_gpu_create_texture_view(void *texture);
void void_gpu_release_texture(void *p);
void *void_gpu_begin_render_pass_depth(
    void *encoder, void *colorView,
    double r, double g, double b, double a,
    void *depthView);

// Extended Pipeline (with layout, depth, cull)
void *void_gpu_create_render_pipeline_ext(
    void *device, void *shader,
    const char *vs_entry, const char *fs_entry,
    void *pipelineLayout,
    uint64_t stride, uint32_t attr_count,
    uint32_t fmt0, uint64_t off0, uint32_t loc0,
    uint32_t fmt1, uint64_t off1, uint32_t loc1,
    int has_depth, uint32_t cullMode);

// Extended Pipeline 2 (3 attrs + blend)
void *void_gpu_create_render_pipeline_ext2(
    void *device, void *shader,
    const char *vs_entry, const char *fs_entry,
    void *pipelineLayout,
    uint64_t stride, uint32_t attr_count,
    uint32_t fmt0, uint64_t off0, uint32_t loc0,
    uint32_t fmt1, uint64_t off1, uint32_t loc1,
    uint32_t fmt2, uint64_t off2, uint32_t loc2,
    int has_depth, uint32_t cullMode,
    int has_blend,
    uint32_t blendColorSrc, uint32_t blendColorDst, uint32_t blendColorOp,
    uint32_t blendAlphaSrc, uint32_t blendAlphaDst, uint32_t blendAlphaOp);

// Viewport & Scissor
void void_gpu_render_pass_set_viewport(void *pass, float x, float y,
    float width, float height, float minDepth, float maxDepth);
void void_gpu_render_pass_set_scissor_rect(void *pass,
    uint32_t x, uint32_t y, uint32_t width, uint32_t height);

// General Texture
void *void_gpu_create_texture(void *device, uint32_t width, uint32_t height,
    uint32_t format, uint32_t usage, uint32_t mipLevelCount);
void void_gpu_queue_write_texture(void *queue, void *texture,
    const void *data, uint64_t dataSize,
    uint32_t bytesPerRow, uint32_t width, uint32_t height);

// Sampler
void *void_gpu_create_sampler(void *device,
    uint32_t addressMode, uint32_t magFilter, uint32_t minFilter);

// Texture/Sampler Bind Groups
void *void_gpu_create_bind_group_layout_1tex_1samp(void *device,
    uint32_t texBinding, uint32_t texVisibility,
    uint32_t sampBinding, uint32_t sampVisibility);
void *void_gpu_create_bind_group_1tex_1samp(void *device, void *layout,
    uint32_t texBinding, void *textureView,
    uint32_t sampBinding, void *sampler);
void *void_gpu_create_pipeline_layout_2bg(void *device, void *bg0, void *bg1);

// Checkerboard texture generator
void void_gen_checkerboard(void *dest, uint32_t size,
    uint32_t r1, uint32_t g1, uint32_t b1,
    uint32_t r2, uint32_t g2, uint32_t b2);

// Release
void void_gpu_release_instance(void *p);
void void_gpu_release_surface(void *p);
void void_gpu_release_adapter(void *p);
void void_gpu_release_device(void *p);
void void_gpu_release_queue(void *p);
void void_gpu_release_shader(void *p);
void void_gpu_release_pipeline(void *p);
void void_gpu_release_command_encoder(void *p);
void void_gpu_release_command_buffer(void *p);
void void_gpu_release_texture_view(void *p);
void void_gpu_release_buffer(void *p);
void void_gpu_release_bind_group_layout(void *p);
void void_gpu_release_bind_group(void *p);
void void_gpu_release_pipeline_layout(void *p);
void void_gpu_release_sampler(void *p);

#endif
