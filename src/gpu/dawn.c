// Void Dawn/WebGPU — GPU instance, device, pipeline, buffer, render

#include "dawn.h"

#include <dawn/webgpu.h>
#include <SDL3/SDL.h>
#include <sdl3webgpu.h>
#include <stdio.h>
#include <string.h>

// --- Callback state ---

static WGPUAdapter s_adapter = NULL;
static WGPUDevice  s_device  = NULL;

static void on_adapter_ready(
	WGPURequestAdapterStatus status, WGPUAdapter adapter,
	WGPUStringView message, void *u1, void *u2
) {
	(void)message; (void)u1; (void)u2;
	if (status == WGPURequestAdapterStatus_Success) {
		s_adapter = adapter;
	} else {
		fprintf(stderr, "void_gpu: adapter request failed (%d)\n", status);
	}
}

static void on_device_ready(
	WGPURequestDeviceStatus status, WGPUDevice device,
	WGPUStringView message, void *u1, void *u2
) {
	(void)message; (void)u1; (void)u2;
	if (status == WGPURequestDeviceStatus_Success) {
		s_device = device;
	} else {
		fprintf(stderr, "void_gpu: device request failed (%d)\n", status);
	}
}

static void on_device_error(
	WGPUDevice const *device, WGPUErrorType type,
	WGPUStringView message, void *u1, void *u2
) {
	(void)device; (void)u1; (void)u2;
	fprintf(stderr, "void_gpu: device error (type %d): %.*s\n",
		type, (int)message.length, message.data);
}

// --- GPU init ---

void *void_gpu_create_instance(void) {
	WGPUInstanceDescriptor desc = {0};
	return (void *)wgpuCreateInstance(&desc);
}

void *void_gpu_create_surface(void *instance, void *window) {
	return (void *)SDL_GetWGPUSurface((WGPUInstance)instance, (SDL_Window *)window);
}

void *void_gpu_request_adapter(void *instance, void *surface) {
	s_adapter = NULL;
	WGPURequestAdapterOptions opts = {0};
	opts.compatibleSurface = (WGPUSurface)surface;
	WGPURequestAdapterCallbackInfo cb = {0};
	cb.mode = WGPUCallbackMode_AllowSpontaneous;
	cb.callback = on_adapter_ready;
	wgpuInstanceRequestAdapter((WGPUInstance)instance, &opts, cb);
	return (void *)s_adapter;
}

void *void_gpu_request_device(void *adapter) {
	s_device = NULL;
	WGPUDeviceDescriptor dev_desc = {0};
	dev_desc.uncapturedErrorCallbackInfo.callback = on_device_error;
	WGPURequestDeviceCallbackInfo cb = {0};
	cb.mode = WGPUCallbackMode_AllowSpontaneous;
	cb.callback = on_device_ready;
	wgpuAdapterRequestDevice((WGPUAdapter)adapter, &dev_desc, cb);
	return (void *)s_device;
}

void *void_gpu_get_queue(void *device) {
	return (void *)wgpuDeviceGetQueue((WGPUDevice)device);
}

void void_gpu_configure_surface(
	void *surface, void *device,
	uint32_t width, uint32_t height
) {
	WGPUSurfaceConfiguration config = {0};
	config.device = (WGPUDevice)device;
	config.format = WGPUTextureFormat_BGRA8Unorm;
	config.usage = WGPUTextureUsage_RenderAttachment;
	config.width = width;
	config.height = height;
	config.presentMode = WGPUPresentMode_Fifo;
	config.alphaMode = WGPUCompositeAlphaMode_Auto;
	wgpuSurfaceConfigure((WGPUSurface)surface, &config);
}

// --- Buffer ---

void *void_gpu_create_buffer(void *device, uint64_t size, uint32_t usage, int mapped_at_creation) {
	WGPUBufferDescriptor desc = {0};
	desc.size = size;
	desc.usage = (WGPUBufferUsage)usage;
	desc.mappedAtCreation = mapped_at_creation ? 1 : 0;
	return (void *)wgpuDeviceCreateBuffer((WGPUDevice)device, &desc);
}

void *void_gpu_buffer_get_mapped_range(void *buffer, uint64_t offset, uint64_t size) {
	return wgpuBufferGetMappedRange((WGPUBuffer)buffer, (size_t)offset, (size_t)size);
}

void void_gpu_buffer_unmap(void *buffer) {
	wgpuBufferUnmap((WGPUBuffer)buffer);
}

void void_gpu_queue_write_buffer(void *queue, void *buffer, uint64_t offset, const void *data, uint64_t size) {
	wgpuQueueWriteBuffer((WGPUQueue)queue, (WGPUBuffer)buffer, offset, data, (size_t)size);
}

void void_gpu_buffer_write_floats(void *buffer, const float *data, uint32_t count) {
	void *mapped = wgpuBufferGetMappedRange((WGPUBuffer)buffer, 0, count * sizeof(float));
	if (mapped) {
		memcpy(mapped, data, count * sizeof(float));
	}
	wgpuBufferUnmap((WGPUBuffer)buffer);
}

void void_gpu_mapped_write_float(void *mapped, uint32_t index, float value) {
	((float *)mapped)[index] = value;
}

// --- Shader & Pipeline ---

void *void_gpu_create_shader(void *device, const char *wgsl_source) {
	WGPUShaderSourceWGSL wgsl = {0};
	wgsl.chain.sType = WGPUSType_ShaderSourceWGSL;
	wgsl.code = (WGPUStringView){ wgsl_source, WGPU_STRLEN };

	WGPUShaderModuleDescriptor desc = {0};
	desc.nextInChain = (WGPUChainedStruct *)&wgsl;
	return (void *)wgpuDeviceCreateShaderModule((WGPUDevice)device, &desc);
}

void *void_gpu_create_render_pipeline(
	void *device, void *shader,
	const char *vs_entry, const char *fs_entry
) {
	WGPUShaderModule sm = (WGPUShaderModule)shader;

	WGPUColorTargetState color_target = {0};
	color_target.format = WGPUTextureFormat_BGRA8Unorm;
	color_target.writeMask = WGPUColorWriteMask_All;

	WGPUFragmentState frag = {0};
	frag.module = sm;
	frag.entryPoint = (WGPUStringView){ fs_entry, WGPU_STRLEN };
	frag.targetCount = 1;
	frag.targets = &color_target;

	WGPURenderPipelineDescriptor desc = {0};
	desc.label = (WGPUStringView){ "pipeline", WGPU_STRLEN };
	desc.vertex.module = sm;
	desc.vertex.entryPoint = (WGPUStringView){ vs_entry, WGPU_STRLEN };
	desc.primitive.topology = WGPUPrimitiveTopology_TriangleList;
	desc.primitive.frontFace = WGPUFrontFace_CCW;
	desc.primitive.cullMode = WGPUCullMode_None;
	desc.multisample.count = 1;
	desc.multisample.mask = 0xFFFFFFFF;
	desc.fragment = &frag;

	return (void *)wgpuDeviceCreateRenderPipeline((WGPUDevice)device, &desc);
}

void *void_gpu_create_render_pipeline_vb(
	void *device, void *shader,
	const char *vs_entry, const char *fs_entry,
	uint32_t buffer_count,
	uint64_t *strides, uint32_t *attr_counts,
	uint32_t *formats, uint64_t *attr_offsets, uint32_t *locations
) {
	WGPUShaderModule sm = (WGPUShaderModule)shader;

	WGPUVertexBufferLayout vb_layouts[8] = {0};
	WGPUVertexAttribute all_attrs[32] = {0};
	uint32_t attr_idx = 0;

	for (uint32_t b = 0; b < buffer_count && b < 8; b++) {
		vb_layouts[b].arrayStride = strides[b];
		vb_layouts[b].stepMode = WGPUVertexStepMode_Vertex;
		vb_layouts[b].attributeCount = attr_counts[b];
		vb_layouts[b].attributes = &all_attrs[attr_idx];
		for (uint32_t a = 0; a < attr_counts[b] && attr_idx < 32; a++) {
			all_attrs[attr_idx].format = (WGPUVertexFormat)formats[attr_idx];
			all_attrs[attr_idx].offset = attr_offsets[attr_idx];
			all_attrs[attr_idx].shaderLocation = locations[attr_idx];
			attr_idx++;
		}
	}

	WGPUColorTargetState color_target = {0};
	color_target.format = WGPUTextureFormat_BGRA8Unorm;
	color_target.writeMask = WGPUColorWriteMask_All;

	WGPUFragmentState frag = {0};
	frag.module = sm;
	frag.entryPoint = (WGPUStringView){ fs_entry, WGPU_STRLEN };
	frag.targetCount = 1;
	frag.targets = &color_target;

	WGPURenderPipelineDescriptor desc = {0};
	desc.label = (WGPUStringView){ "pipeline_vb", WGPU_STRLEN };
	desc.vertex.module = sm;
	desc.vertex.entryPoint = (WGPUStringView){ vs_entry, WGPU_STRLEN };
	desc.vertex.bufferCount = buffer_count;
	desc.vertex.buffers = vb_layouts;
	desc.primitive.topology = WGPUPrimitiveTopology_TriangleList;
	desc.primitive.frontFace = WGPUFrontFace_CCW;
	desc.primitive.cullMode = WGPUCullMode_None;
	desc.multisample.count = 1;
	desc.multisample.mask = 0xFFFFFFFF;
	desc.fragment = &frag;

	return (void *)wgpuDeviceCreateRenderPipeline((WGPUDevice)device, &desc);
}

void *void_gpu_create_render_pipeline_1vb(
	void *device, void *shader,
	const char *vs_entry, const char *fs_entry,
	uint64_t stride, uint32_t attr_count,
	uint32_t fmt0, uint64_t off0, uint32_t loc0,
	uint32_t fmt1, uint64_t off1, uint32_t loc1
) {
	WGPUShaderModule sm = (WGPUShaderModule)shader;

	WGPUVertexAttribute attrs[2] = {0};
	attrs[0].format = (WGPUVertexFormat)fmt0;
	attrs[0].offset = off0;
	attrs[0].shaderLocation = loc0;
	if (attr_count > 1) {
		attrs[1].format = (WGPUVertexFormat)fmt1;
		attrs[1].offset = off1;
		attrs[1].shaderLocation = loc1;
	}

	WGPUVertexBufferLayout vb = {0};
	vb.arrayStride = stride;
	vb.stepMode = WGPUVertexStepMode_Vertex;
	vb.attributeCount = attr_count;
	vb.attributes = attrs;

	WGPUColorTargetState color_target = {0};
	color_target.format = WGPUTextureFormat_BGRA8Unorm;
	color_target.writeMask = WGPUColorWriteMask_All;

	WGPUFragmentState frag = {0};
	frag.module = sm;
	frag.entryPoint = (WGPUStringView){ fs_entry, WGPU_STRLEN };
	frag.targetCount = 1;
	frag.targets = &color_target;

	WGPURenderPipelineDescriptor desc = {0};
	desc.label = (WGPUStringView){ "pipeline_1vb", WGPU_STRLEN };
	desc.vertex.module = sm;
	desc.vertex.entryPoint = (WGPUStringView){ vs_entry, WGPU_STRLEN };
	desc.vertex.bufferCount = 1;
	desc.vertex.buffers = &vb;
	desc.primitive.topology = WGPUPrimitiveTopology_TriangleList;
	desc.primitive.frontFace = WGPUFrontFace_CCW;
	desc.primitive.cullMode = WGPUCullMode_None;
	desc.multisample.count = 1;
	desc.multisample.mask = 0xFFFFFFFF;
	desc.fragment = &frag;

	return (void *)wgpuDeviceCreateRenderPipeline((WGPUDevice)device, &desc);
}

// --- Frame ---

void *void_gpu_get_current_texture_view(void *surface) {
	WGPUSurfaceTexture st = {0};
	wgpuSurfaceGetCurrentTexture((WGPUSurface)surface, &st);
	if (st.status != WGPUSurfaceGetCurrentTextureStatus_SuccessOptimal) {
		return NULL;
	}
	WGPUTextureView view = wgpuTextureCreateView(st.texture, NULL);
	wgpuTextureRelease(st.texture);
	return (void *)view;
}

void *void_gpu_create_command_encoder(void *device) {
	return (void *)wgpuDeviceCreateCommandEncoder((WGPUDevice)device, NULL);
}

void *void_gpu_begin_render_pass(
	void *encoder, void *view,
	double r, double g, double b, double a
) {
	WGPURenderPassColorAttachment color = {0};
	color.view = (WGPUTextureView)view;
	color.loadOp = WGPULoadOp_Clear;
	color.storeOp = WGPUStoreOp_Store;
	color.clearValue = (WGPUColor){ r, g, b, a };
	color.depthSlice = WGPU_DEPTH_SLICE_UNDEFINED;

	WGPURenderPassDescriptor rp = {0};
	rp.label = (WGPUStringView){ NULL, WGPU_STRLEN };
	rp.colorAttachmentCount = 1;
	rp.colorAttachments = &color;

	return (void *)wgpuCommandEncoderBeginRenderPass(
		(WGPUCommandEncoder)encoder, &rp);
}

void void_gpu_render_pass_set_pipeline(void *pass, void *pipeline) {
	wgpuRenderPassEncoderSetPipeline(
		(WGPURenderPassEncoder)pass, (WGPURenderPipeline)pipeline);
}

void void_gpu_render_pass_set_vertex_buffer(void *pass, uint32_t slot, void *buffer, uint64_t offset, uint64_t size) {
	uint64_t actual_size = (size == 0) ? WGPU_WHOLE_SIZE : size;
	wgpuRenderPassEncoderSetVertexBuffer(
		(WGPURenderPassEncoder)pass, slot, (WGPUBuffer)buffer, offset, actual_size);
}

void void_gpu_render_pass_draw(void *pass, uint32_t vertex_count) {
	wgpuRenderPassEncoderDraw(
		(WGPURenderPassEncoder)pass, vertex_count, 1, 0, 0);
}

void void_gpu_end_render_pass(void *pass) {
	wgpuRenderPassEncoderEnd((WGPURenderPassEncoder)pass);
	wgpuRenderPassEncoderRelease((WGPURenderPassEncoder)pass);
}

void *void_gpu_finish_encoder(void *encoder) {
	return (void *)wgpuCommandEncoderFinish((WGPUCommandEncoder)encoder, NULL);
}

void void_gpu_submit(void *queue, void *command) {
	WGPUCommandBuffer cmd = (WGPUCommandBuffer)command;
	wgpuQueueSubmit((WGPUQueue)queue, 1, &cmd);
}

void void_gpu_present(void *surface) {
	wgpuSurfacePresent((WGPUSurface)surface);
}

// --- Bind Group & Pipeline Layout ---

void *void_gpu_create_bind_group_layout_1buf(
	void *device, uint32_t binding, uint32_t visibility, uint64_t minBindingSize
) {
	WGPUBufferBindingLayout buf_layout = {0};
	buf_layout.type = WGPUBufferBindingType_Uniform;
	buf_layout.minBindingSize = minBindingSize;

	WGPUBindGroupLayoutEntry entry = {0};
	entry.binding = binding;
	entry.visibility = (WGPUShaderStage)visibility;
	entry.buffer = buf_layout;

	WGPUBindGroupLayoutDescriptor desc = {0};
	desc.entryCount = 1;
	desc.entries = &entry;

	return (void *)wgpuDeviceCreateBindGroupLayout((WGPUDevice)device, &desc);
}

void *void_gpu_create_bind_group_1buf(
	void *device, void *layout, uint32_t binding, void *buffer,
	uint64_t offset, uint64_t size
) {
	WGPUBindGroupEntry entry = {0};
	entry.binding = binding;
	entry.buffer = (WGPUBuffer)buffer;
	entry.offset = offset;
	entry.size = size;

	WGPUBindGroupDescriptor desc = {0};
	desc.layout = (WGPUBindGroupLayout)layout;
	desc.entryCount = 1;
	desc.entries = &entry;

	return (void *)wgpuDeviceCreateBindGroup((WGPUDevice)device, &desc);
}

void *void_gpu_create_pipeline_layout_1bg(void *device, void *bindGroupLayout) {
	WGPUBindGroupLayout bgl = (WGPUBindGroupLayout)bindGroupLayout;

	WGPUPipelineLayoutDescriptor desc = {0};
	desc.bindGroupLayoutCount = 1;
	desc.bindGroupLayouts = &bgl;

	return (void *)wgpuDeviceCreatePipelineLayout((WGPUDevice)device, &desc);
}

void void_gpu_render_pass_set_bind_group(void *pass, uint32_t index, void *bindGroup) {
	wgpuRenderPassEncoderSetBindGroup(
		(WGPURenderPassEncoder)pass, index, (WGPUBindGroup)bindGroup, 0, NULL);
}

// --- Index Buffer ---

void void_gpu_render_pass_set_index_buffer(
	void *pass, void *buffer, uint32_t format, uint64_t offset, uint64_t size
) {
	uint64_t actual_size = (size == 0) ? WGPU_WHOLE_SIZE : size;
	wgpuRenderPassEncoderSetIndexBuffer(
		(WGPURenderPassEncoder)pass, (WGPUBuffer)buffer,
		(WGPUIndexFormat)format, offset, actual_size);
}

void void_gpu_render_pass_draw_indexed(
	void *pass, uint32_t indexCount, uint32_t instanceCount,
	uint32_t firstIndex, int32_t baseVertex, uint32_t firstInstance
) {
	wgpuRenderPassEncoderDrawIndexed(
		(WGPURenderPassEncoder)pass, indexCount, instanceCount,
		firstIndex, baseVertex, firstInstance);
}

void void_gpu_mapped_write_u16(void *mapped, uint32_t index, uint16_t value) {
	((uint16_t *)mapped)[index] = value;
}

void void_gpu_mapped_write_u32(void *mapped, uint32_t index, uint32_t value) {
	((uint32_t *)mapped)[index] = value;
}

// --- Depth Texture ---

void *void_gpu_create_depth_texture(void *device, uint32_t width, uint32_t height) {
	WGPUTextureDescriptor desc = {0};
	desc.size.width = width;
	desc.size.height = height;
	desc.size.depthOrArrayLayers = 1;
	desc.mipLevelCount = 1;
	desc.sampleCount = 1;
	desc.dimension = WGPUTextureDimension_2D;
	desc.format = WGPUTextureFormat_Depth24Plus;
	desc.usage = WGPUTextureUsage_RenderAttachment;
	return (void *)wgpuDeviceCreateTexture((WGPUDevice)device, &desc);
}

void *void_gpu_create_texture_view(void *texture) {
	return (void *)wgpuTextureCreateView((WGPUTexture)texture, NULL);
}

void *void_gpu_begin_render_pass_depth(
	void *encoder, void *colorView,
	double r, double g, double b, double a,
	void *depthView
) {
	WGPURenderPassColorAttachment color = {0};
	color.view = (WGPUTextureView)colorView;
	color.loadOp = WGPULoadOp_Clear;
	color.storeOp = WGPUStoreOp_Store;
	color.clearValue = (WGPUColor){ r, g, b, a };
	color.depthSlice = WGPU_DEPTH_SLICE_UNDEFINED;

	WGPURenderPassDepthStencilAttachment depth = {0};
	depth.view = (WGPUTextureView)depthView;
	depth.depthLoadOp = WGPULoadOp_Clear;
	depth.depthStoreOp = WGPUStoreOp_Store;
	depth.depthClearValue = 1.0f;

	WGPURenderPassDescriptor rp = {0};
	rp.label = (WGPUStringView){ NULL, WGPU_STRLEN };
	rp.colorAttachmentCount = 1;
	rp.colorAttachments = &color;
	rp.depthStencilAttachment = &depth;

	return (void *)wgpuCommandEncoderBeginRenderPass(
		(WGPUCommandEncoder)encoder, &rp);
}

// --- Extended Pipeline ---

void *void_gpu_create_render_pipeline_ext(
	void *device, void *shader,
	const char *vs_entry, const char *fs_entry,
	void *pipelineLayout,
	uint64_t stride, uint32_t attr_count,
	uint32_t fmt0, uint64_t off0, uint32_t loc0,
	uint32_t fmt1, uint64_t off1, uint32_t loc1,
	int has_depth, uint32_t cullMode
) {
	WGPUShaderModule sm = (WGPUShaderModule)shader;

	// Vertex buffer layout
	WGPUVertexAttribute attrs[2] = {0};
	attrs[0].format = (WGPUVertexFormat)fmt0;
	attrs[0].offset = off0;
	attrs[0].shaderLocation = loc0;
	if (attr_count > 1) {
		attrs[1].format = (WGPUVertexFormat)fmt1;
		attrs[1].offset = off1;
		attrs[1].shaderLocation = loc1;
	}

	WGPUVertexBufferLayout vb = {0};
	vb.arrayStride = stride;
	vb.stepMode = WGPUVertexStepMode_Vertex;
	vb.attributeCount = attr_count;
	vb.attributes = attrs;

	// Fragment
	WGPUColorTargetState color_target = {0};
	color_target.format = WGPUTextureFormat_BGRA8Unorm;
	color_target.writeMask = WGPUColorWriteMask_All;

	WGPUFragmentState frag = {0};
	frag.module = sm;
	frag.entryPoint = (WGPUStringView){ fs_entry, WGPU_STRLEN };
	frag.targetCount = 1;
	frag.targets = &color_target;

	// Depth stencil
	WGPUDepthStencilState depth_state = {0};
	if (has_depth) {
		depth_state.format = WGPUTextureFormat_Depth24Plus;
		depth_state.depthWriteEnabled = 1;
		depth_state.depthCompare = WGPUCompareFunction_Less;
	}

	// Pipeline descriptor
	WGPURenderPipelineDescriptor desc = {0};
	desc.label = (WGPUStringView){ "pipeline_ext", WGPU_STRLEN };
	if (pipelineLayout) {
		desc.layout = (WGPUPipelineLayout)pipelineLayout;
	}
	desc.vertex.module = sm;
	desc.vertex.entryPoint = (WGPUStringView){ vs_entry, WGPU_STRLEN };
	desc.vertex.bufferCount = 1;
	desc.vertex.buffers = &vb;
	desc.primitive.topology = WGPUPrimitiveTopology_TriangleList;
	desc.primitive.frontFace = WGPUFrontFace_CCW;
	desc.primitive.cullMode = cullMode ? (WGPUCullMode)cullMode : WGPUCullMode_None;
	desc.multisample.count = 1;
	desc.multisample.mask = 0xFFFFFFFF;
	desc.fragment = &frag;
	if (has_depth) {
		desc.depthStencil = &depth_state;
	}

	return (void *)wgpuDeviceCreateRenderPipeline((WGPUDevice)device, &desc);
}

// --- Viewport & Scissor ---

void void_gpu_render_pass_set_viewport(void *pass, float x, float y,
	float width, float height, float minDepth, float maxDepth
) {
	wgpuRenderPassEncoderSetViewport(
		(WGPURenderPassEncoder)pass, x, y, width, height, minDepth, maxDepth);
}

void void_gpu_render_pass_set_scissor_rect(void *pass,
	uint32_t x, uint32_t y, uint32_t width, uint32_t height
) {
	wgpuRenderPassEncoderSetScissorRect(
		(WGPURenderPassEncoder)pass, x, y, width, height);
}

// --- General Texture ---

void *void_gpu_create_texture(void *device, uint32_t width, uint32_t height,
	uint32_t format, uint32_t usage, uint32_t mipLevelCount
) {
	WGPUTextureDescriptor desc = {0};
	desc.size.width = width;
	desc.size.height = height;
	desc.size.depthOrArrayLayers = 1;
	desc.mipLevelCount = mipLevelCount;
	desc.sampleCount = 1;
	desc.dimension = WGPUTextureDimension_2D;
	desc.format = (WGPUTextureFormat)format;
	desc.usage = (WGPUTextureUsage)usage;
	return (void *)wgpuDeviceCreateTexture((WGPUDevice)device, &desc);
}

void void_gpu_queue_write_texture(void *queue, void *texture,
	const void *data, uint64_t dataSize,
	uint32_t bytesPerRow, uint32_t width, uint32_t height
) {
	WGPUTexelCopyTextureInfo dest = {0};
	dest.texture = (WGPUTexture)texture;
	dest.mipLevel = 0;

	WGPUTexelCopyBufferLayout layout = {0};
	layout.bytesPerRow = bytesPerRow;
	layout.rowsPerImage = height;

	WGPUExtent3D size = { width, height, 1 };

	wgpuQueueWriteTexture(
		(WGPUQueue)queue, &dest, data, (size_t)dataSize, &layout, &size);
}

// --- Sampler ---

void *void_gpu_create_sampler(void *device,
	uint32_t addressMode, uint32_t magFilter, uint32_t minFilter
) {
	WGPUSamplerDescriptor desc = {0};
	desc.addressModeU = (WGPUAddressMode)addressMode;
	desc.addressModeV = (WGPUAddressMode)addressMode;
	desc.addressModeW = (WGPUAddressMode)addressMode;
	desc.magFilter = (WGPUFilterMode)magFilter;
	desc.minFilter = (WGPUFilterMode)minFilter;
	desc.mipmapFilter = WGPUMipmapFilterMode_Nearest;
	desc.maxAnisotropy = 1;
	return (void *)wgpuDeviceCreateSampler((WGPUDevice)device, &desc);
}

// --- Texture/Sampler Bind Groups ---

void *void_gpu_create_bind_group_layout_1tex_1samp(void *device,
	uint32_t texBinding, uint32_t texVisibility,
	uint32_t sampBinding, uint32_t sampVisibility
) {
	WGPUBindGroupLayoutEntry entries[2] = {0};

	// Texture entry
	entries[0].binding = texBinding;
	entries[0].visibility = (WGPUShaderStage)texVisibility;
	entries[0].texture.sampleType = WGPUTextureSampleType_Float;
	entries[0].texture.viewDimension = WGPUTextureViewDimension_2D;

	// Sampler entry
	entries[1].binding = sampBinding;
	entries[1].visibility = (WGPUShaderStage)sampVisibility;
	entries[1].sampler.type = WGPUSamplerBindingType_Filtering;

	WGPUBindGroupLayoutDescriptor desc = {0};
	desc.entryCount = 2;
	desc.entries = entries;

	return (void *)wgpuDeviceCreateBindGroupLayout((WGPUDevice)device, &desc);
}

void *void_gpu_create_bind_group_1tex_1samp(void *device, void *layout,
	uint32_t texBinding, void *textureView,
	uint32_t sampBinding, void *sampler
) {
	WGPUBindGroupEntry entries[2] = {0};

	entries[0].binding = texBinding;
	entries[0].textureView = (WGPUTextureView)textureView;

	entries[1].binding = sampBinding;
	entries[1].sampler = (WGPUSampler)sampler;

	WGPUBindGroupDescriptor desc = {0};
	desc.layout = (WGPUBindGroupLayout)layout;
	desc.entryCount = 2;
	desc.entries = entries;

	return (void *)wgpuDeviceCreateBindGroup((WGPUDevice)device, &desc);
}

void *void_gpu_create_pipeline_layout_2bg(void *device, void *bg0, void *bg1) {
	WGPUBindGroupLayout bgls[2];
	bgls[0] = (WGPUBindGroupLayout)bg0;
	bgls[1] = (WGPUBindGroupLayout)bg1;

	WGPUPipelineLayoutDescriptor desc = {0};
	desc.bindGroupLayoutCount = 2;
	desc.bindGroupLayouts = bgls;

	return (void *)wgpuDeviceCreatePipelineLayout((WGPUDevice)device, &desc);
}

// --- Extended Pipeline 2 (3 attrs + blend) ---

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
	uint32_t blendAlphaSrc, uint32_t blendAlphaDst, uint32_t blendAlphaOp
) {
	WGPUShaderModule sm = (WGPUShaderModule)shader;

	// Vertex attributes (up to 3)
	WGPUVertexAttribute attrs[3] = {0};
	attrs[0].format = (WGPUVertexFormat)fmt0;
	attrs[0].offset = off0;
	attrs[0].shaderLocation = loc0;
	if (attr_count > 1) {
		attrs[1].format = (WGPUVertexFormat)fmt1;
		attrs[1].offset = off1;
		attrs[1].shaderLocation = loc1;
	}
	if (attr_count > 2) {
		attrs[2].format = (WGPUVertexFormat)fmt2;
		attrs[2].offset = off2;
		attrs[2].shaderLocation = loc2;
	}

	WGPUVertexBufferLayout vb = {0};
	vb.arrayStride = stride;
	vb.stepMode = WGPUVertexStepMode_Vertex;
	vb.attributeCount = attr_count;
	vb.attributes = attrs;

	// Blend state
	WGPUBlendState blend = {0};
	if (has_blend) {
		blend.color.srcFactor = (WGPUBlendFactor)blendColorSrc;
		blend.color.dstFactor = (WGPUBlendFactor)blendColorDst;
		blend.color.operation = (WGPUBlendOperation)blendColorOp;
		blend.alpha.srcFactor = (WGPUBlendFactor)blendAlphaSrc;
		blend.alpha.dstFactor = (WGPUBlendFactor)blendAlphaDst;
		blend.alpha.operation = (WGPUBlendOperation)blendAlphaOp;
	}

	// Fragment
	WGPUColorTargetState color_target = {0};
	color_target.format = WGPUTextureFormat_BGRA8Unorm;
	color_target.writeMask = WGPUColorWriteMask_All;
	if (has_blend) {
		color_target.blend = &blend;
	}

	WGPUFragmentState frag = {0};
	frag.module = sm;
	frag.entryPoint = (WGPUStringView){ fs_entry, WGPU_STRLEN };
	frag.targetCount = 1;
	frag.targets = &color_target;

	// Depth stencil
	WGPUDepthStencilState depth_state = {0};
	if (has_depth) {
		depth_state.format = WGPUTextureFormat_Depth24Plus;
		depth_state.depthWriteEnabled = 1;
		depth_state.depthCompare = WGPUCompareFunction_Less;
	}

	// Pipeline
	WGPURenderPipelineDescriptor desc = {0};
	desc.label = (WGPUStringView){ "pipeline_ext2", WGPU_STRLEN };
	if (pipelineLayout) {
		desc.layout = (WGPUPipelineLayout)pipelineLayout;
	}
	desc.vertex.module = sm;
	desc.vertex.entryPoint = (WGPUStringView){ vs_entry, WGPU_STRLEN };
	desc.vertex.bufferCount = 1;
	desc.vertex.buffers = &vb;
	desc.primitive.topology = WGPUPrimitiveTopology_TriangleList;
	desc.primitive.frontFace = WGPUFrontFace_CCW;
	desc.primitive.cullMode = cullMode ? (WGPUCullMode)cullMode : WGPUCullMode_None;
	desc.multisample.count = 1;
	desc.multisample.mask = 0xFFFFFFFF;
	desc.fragment = &frag;
	if (has_depth) {
		desc.depthStencil = &depth_state;
	}

	return (void *)wgpuDeviceCreateRenderPipeline((WGPUDevice)device, &desc);
}

// --- Checkerboard Texture Generator ---

void void_gen_checkerboard(void *dest, uint32_t size,
	uint32_t r1, uint32_t g1, uint32_t b1,
	uint32_t r2, uint32_t g2, uint32_t b2
) {
	uint8_t *pixels = (uint8_t *)dest;
	uint32_t cell = size / 8;  // 8x8 checkerboard
	if (cell < 1) cell = 1;
	for (uint32_t y = 0; y < size; y++) {
		for (uint32_t x = 0; x < size; x++) {
			int checker = ((x / cell) + (y / cell)) % 2;
			uint32_t idx = (y * size + x) * 4;
			pixels[idx + 0] = checker ? (uint8_t)r2 : (uint8_t)r1;
			pixels[idx + 1] = checker ? (uint8_t)g2 : (uint8_t)g1;
			pixels[idx + 2] = checker ? (uint8_t)b2 : (uint8_t)b1;
			pixels[idx + 3] = 255;  // alpha
		}
	}
}

// --- Release ---

void void_gpu_release_instance(void *p)        { if (p) wgpuInstanceRelease((WGPUInstance)p); }
void void_gpu_release_surface(void *p)         { if (p) wgpuSurfaceRelease((WGPUSurface)p); }
void void_gpu_release_adapter(void *p)         { if (p) wgpuAdapterRelease((WGPUAdapter)p); }
void void_gpu_release_device(void *p)          { if (p) wgpuDeviceRelease((WGPUDevice)p); }
void void_gpu_release_queue(void *p)           { if (p) wgpuQueueRelease((WGPUQueue)p); }
void void_gpu_release_shader(void *p)          { if (p) wgpuShaderModuleRelease((WGPUShaderModule)p); }
void void_gpu_release_pipeline(void *p)        { if (p) wgpuRenderPipelineRelease((WGPURenderPipeline)p); }
void void_gpu_release_command_encoder(void *p) { if (p) wgpuCommandEncoderRelease((WGPUCommandEncoder)p); }
void void_gpu_release_command_buffer(void *p)  { if (p) wgpuCommandBufferRelease((WGPUCommandBuffer)p); }
void void_gpu_release_texture_view(void *p)    { if (p) wgpuTextureViewRelease((WGPUTextureView)p); }
void void_gpu_release_buffer(void *p)          { if (p) wgpuBufferRelease((WGPUBuffer)p); }
void void_gpu_release_texture(void *p)         { if (p) wgpuTextureRelease((WGPUTexture)p); }
void void_gpu_release_bind_group_layout(void *p) { if (p) wgpuBindGroupLayoutRelease((WGPUBindGroupLayout)p); }
void void_gpu_release_bind_group(void *p)      { if (p) wgpuBindGroupRelease((WGPUBindGroup)p); }
void void_gpu_release_pipeline_layout(void *p) { if (p) wgpuPipelineLayoutRelease((WGPUPipelineLayout)p); }
void void_gpu_release_sampler(void *p)          { if (p) wgpuSamplerRelease((WGPUSampler)p); }
