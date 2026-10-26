#include <stdio.h>
#include <string.h>
#include <webgpu/webgpu.h>
#include "wgpu.h"

#define MAX_ENTRIES 24
#define MAX_BUFFERS 2
#define MAX_ATTRIBUTES 16
#define MAX_TARGETS 4

static WGPUDevice device;
static WGPUQueue queue;
static WGPULimits limits;
static WGPUCommandEncoder encoder;
static WGPUCommandBuffer commands;
static WGPURenderPassEncoder pass;
static WGPUComputePassEncoder computePass;
static int32_t passWidth;
static int32_t passHeight;

static WGPUStringView text(const char *value) {
	WGPUStringView view = WGPU_STRING_VIEW_INIT;
	if (value && value[0]) {
		view.data = value;
		view.length = strlen(value);
	}
	return view;
}

int32_t wgSetup(void *native) {
	device = (WGPUDevice)native;
	queue = wgpuDeviceGetQueue(device);
	limits = (WGPULimits)WGPU_LIMITS_INIT;
	if (!queue || wgpuDeviceGetLimits(device, &limits) != WGPUStatus_Success) return 0;
	return 1;
}

void wgShutdown(void) {
	if (pass) wgpuRenderPassEncoderRelease(pass);
	if (computePass) wgpuComputePassEncoderRelease(computePass);
	if (commands) wgpuCommandBufferRelease(commands);
	if (encoder) wgpuCommandEncoderRelease(encoder);
	if (queue) wgpuQueueRelease(queue);
	pass = NULL;
	computePass = NULL;
	commands = NULL;
	encoder = NULL;
	queue = NULL;
	device = NULL;
}

enum {
	LIMIT_TEXTURE_DIMENSION_1D,
	LIMIT_TEXTURE_DIMENSION_2D,
	LIMIT_TEXTURE_DIMENSION_3D,
	LIMIT_TEXTURE_ARRAY_LAYERS,
	LIMIT_BIND_GROUPS,
	LIMIT_SAMPLED_TEXTURES,
	LIMIT_SAMPLERS,
	LIMIT_STORAGE_BUFFERS,
	LIMIT_STORAGE_TEXTURES,
	LIMIT_UNIFORM_BUFFERS,
	LIMIT_UNIFORM_BINDING_SIZE,
	LIMIT_STORAGE_BINDING_SIZE,
	LIMIT_VERTEX_BUFFERS,
	LIMIT_VERTEX_ATTRIBUTES,
	LIMIT_COLOR_ATTACHMENTS,
	LIMIT_WORKGROUP_SIZE_X,
	LIMIT_WORKGROUP_SIZE_Y,
	LIMIT_WORKGROUP_SIZE_Z,
	LIMIT_WORKGROUP_INVOCATIONS,
	LIMIT_WORKGROUPS_PER_DIMENSION,
	LIMIT_UNIFORM_ALIGNMENT,
	LIMIT_STORAGE_ALIGNMENT
};

int64_t wgLimit(int32_t which) {
	switch (which) {
	case LIMIT_TEXTURE_DIMENSION_1D: return limits.maxTextureDimension1D;
	case LIMIT_TEXTURE_DIMENSION_2D: return limits.maxTextureDimension2D;
	case LIMIT_TEXTURE_DIMENSION_3D: return limits.maxTextureDimension3D;
	case LIMIT_TEXTURE_ARRAY_LAYERS: return limits.maxTextureArrayLayers;
	case LIMIT_BIND_GROUPS: return limits.maxBindGroups;
	case LIMIT_SAMPLED_TEXTURES: return limits.maxSampledTexturesPerShaderStage;
	case LIMIT_SAMPLERS: return limits.maxSamplersPerShaderStage;
	case LIMIT_STORAGE_BUFFERS: return limits.maxStorageBuffersPerShaderStage;
	case LIMIT_STORAGE_TEXTURES: return limits.maxStorageTexturesPerShaderStage;
	case LIMIT_UNIFORM_BUFFERS: return limits.maxUniformBuffersPerShaderStage;
	case LIMIT_UNIFORM_BINDING_SIZE: return (int64_t)limits.maxUniformBufferBindingSize;
	case LIMIT_STORAGE_BINDING_SIZE: return (int64_t)limits.maxStorageBufferBindingSize;
	case LIMIT_VERTEX_BUFFERS: return limits.maxVertexBuffers;
	case LIMIT_VERTEX_ATTRIBUTES: return limits.maxVertexAttributes;
	case LIMIT_COLOR_ATTACHMENTS: return limits.maxColorAttachments;
	case LIMIT_WORKGROUP_SIZE_X: return limits.maxComputeWorkgroupSizeX;
	case LIMIT_WORKGROUP_SIZE_Y: return limits.maxComputeWorkgroupSizeY;
	case LIMIT_WORKGROUP_SIZE_Z: return limits.maxComputeWorkgroupSizeZ;
	case LIMIT_WORKGROUP_INVOCATIONS: return limits.maxComputeInvocationsPerWorkgroup;
	case LIMIT_WORKGROUPS_PER_DIMENSION: return limits.maxComputeWorkgroupsPerDimension;
	case LIMIT_UNIFORM_ALIGNMENT: return limits.minUniformBufferOffsetAlignment;
	case LIMIT_STORAGE_ALIGNMENT: return limits.minStorageBufferOffsetAlignment;
	default: return -1;
	}
}
int32_t wgHasFeature(int32_t feature) {
	return wgpuDeviceHasFeature(device, (WGPUFeatureName)feature) ? 1 : 0;
}
WgView wgViewFrom(void *native) { return (WgView)native; }
void *wgTextureNative(WgTexture texture) { return texture; }

WgBuffer wgCreateBuffer(int64_t bytes, int32_t usage, const char *label) {
	WGPUBufferDescriptor desc = WGPU_BUFFER_DESCRIPTOR_INIT;
	desc.label = text(label);
	desc.usage = (WGPUBufferUsage)usage;
	desc.size = ((uint64_t)bytes + 3) & ~(uint64_t)3;
	return (WgBuffer)wgpuDeviceCreateBuffer(device, &desc);
}

void wgReleaseBuffer(WgBuffer buffer) {
	if (buffer) wgpuBufferRelease((WGPUBuffer)buffer);
}

void wgWriteBuffer(WgBuffer buffer, int64_t offset, const void *data, int64_t bytes) {
	const uint64_t whole = (uint64_t)bytes & ~(uint64_t)3;
	const uint64_t tail = (uint64_t)bytes & 3;
	if (whole > 0)
		wgpuQueueWriteBuffer(queue, (WGPUBuffer)buffer, (uint64_t)offset, data, (size_t)whole);
	if (tail > 0) {
		uint8_t padded[4] = {0};
		memcpy(padded, (const uint8_t *)data + whole, (size_t)tail);
		wgpuQueueWriteBuffer(queue, (WGPUBuffer)buffer, (uint64_t)offset + whole, padded, 4);
	}
}

WgTexture wgCreateTexture(
	int32_t width,
	int32_t height,
	int32_t depthOrLayers,
	int32_t mipLevels,
	int32_t dimension,
	int32_t format,
	int32_t usage,
	int32_t sampleCount,
	const char *label) {
	WGPUTextureDescriptor desc = WGPU_TEXTURE_DESCRIPTOR_INIT;
	desc.label = text(label);
	desc.usage = (WGPUTextureUsage)usage;
	desc.dimension = (WGPUTextureDimension)dimension;
	desc.size.width = (uint32_t)width;
	desc.size.height = (uint32_t)height;
	desc.size.depthOrArrayLayers = (uint32_t)depthOrLayers;
	desc.mipLevelCount = (uint32_t)mipLevels;
	desc.format = (WGPUTextureFormat)format;
	desc.sampleCount = (uint32_t)sampleCount;
	return (WgTexture)wgpuDeviceCreateTexture(device, &desc);
}

void wgReleaseTexture(WgTexture texture) {
	if (texture) wgpuTextureRelease((WGPUTexture)texture);
}

void wgWriteTexture(
	WgTexture texture,
	const void *data,
	int64_t bytes,
	int64_t offset,
	int32_t bytesPerRow,
	int32_t rowsPerImage,
	int32_t mipLevel,
	int32_t x,
	int32_t y,
	int32_t z,
	int32_t width,
	int32_t height,
	int32_t depth) {
	WGPUTexelCopyTextureInfo destination = WGPU_TEXEL_COPY_TEXTURE_INFO_INIT;
	destination.texture = (WGPUTexture)texture;
	destination.mipLevel = (uint32_t)mipLevel;
	destination.origin.x = (uint32_t)x;
	destination.origin.y = (uint32_t)y;
	destination.origin.z = (uint32_t)z;
	destination.aspect = WGPUTextureAspect_All;
	WGPUTexelCopyBufferLayout layout = WGPU_TEXEL_COPY_BUFFER_LAYOUT_INIT;
	layout.offset = (uint64_t)offset;
	layout.bytesPerRow = (uint32_t)bytesPerRow;
	layout.rowsPerImage = (uint32_t)rowsPerImage;
	WGPUExtent3D extent = WGPU_EXTENT_3D_INIT;
	extent.width = (uint32_t)width;
	extent.height = (uint32_t)height;
	extent.depthOrArrayLayers = (uint32_t)depth;
	wgpuQueueWriteTexture(queue, &destination, data, (size_t)bytes, &layout, &extent);
}

void wgCopyBufferToBuffer(WgBuffer source, int64_t sourceOffset, WgBuffer destination, int64_t destinationOffset, int64_t bytes) {
	wgpuCommandEncoderCopyBufferToBuffer(
		encoder, (WGPUBuffer)source, (uint64_t)sourceOffset, (WGPUBuffer)destination, (uint64_t)destinationOffset, (uint64_t)bytes);
}

static WGPUTexelCopyTextureInfo textureInfo(WgTexture texture, int32_t mipLevel, int32_t x, int32_t y, int32_t z) {
	WGPUTexelCopyTextureInfo info = WGPU_TEXEL_COPY_TEXTURE_INFO_INIT;
	info.texture = (WGPUTexture)texture;
	info.mipLevel = (uint32_t)mipLevel;
	info.origin.x = (uint32_t)x;
	info.origin.y = (uint32_t)y;
	info.origin.z = (uint32_t)z;
	info.aspect = WGPUTextureAspect_All;
	return info;
}

static WGPUTexelCopyBufferInfo bufferInfo(WgBuffer buffer, int64_t offset, int32_t bytesPerRow, int32_t rowsPerImage) {
	WGPUTexelCopyBufferInfo info = WGPU_TEXEL_COPY_BUFFER_INFO_INIT;
	info.buffer = (WGPUBuffer)buffer;
	info.layout.offset = (uint64_t)offset;
	info.layout.bytesPerRow = (uint32_t)bytesPerRow;
	info.layout.rowsPerImage = (uint32_t)rowsPerImage;
	return info;
}

static WGPUExtent3D extentOf(int32_t width, int32_t height, int32_t depth) {
	WGPUExtent3D extent = WGPU_EXTENT_3D_INIT;
	extent.width = (uint32_t)width;
	extent.height = (uint32_t)height;
	extent.depthOrArrayLayers = (uint32_t)depth;
	return extent;
}

void wgCopyBufferToTexture(
	WgBuffer buffer,
	int64_t offset,
	int32_t bytesPerRow,
	int32_t rowsPerImage,
	WgTexture texture,
	int32_t mipLevel,
	int32_t x,
	int32_t y,
	int32_t z,
	int32_t width,
	int32_t height,
	int32_t depth) {
	WGPUTexelCopyBufferInfo source = bufferInfo(buffer, offset, bytesPerRow, rowsPerImage);
	WGPUTexelCopyTextureInfo destination = textureInfo(texture, mipLevel, x, y, z);
	WGPUExtent3D extent = extentOf(width, height, depth);
	wgpuCommandEncoderCopyBufferToTexture(encoder, &source, &destination, &extent);
}

void wgCopyTextureToBuffer(
	WgTexture texture,
	int32_t mipLevel,
	int32_t x,
	int32_t y,
	int32_t z,
	WgBuffer buffer,
	int64_t offset,
	int32_t bytesPerRow,
	int32_t rowsPerImage,
	int32_t width,
	int32_t height,
	int32_t depth) {
	WGPUTexelCopyTextureInfo source = textureInfo(texture, mipLevel, x, y, z);
	WGPUTexelCopyBufferInfo destination = bufferInfo(buffer, offset, bytesPerRow, rowsPerImage);
	WGPUExtent3D extent = extentOf(width, height, depth);
	wgpuCommandEncoderCopyTextureToBuffer(encoder, &source, &destination, &extent);
}

void wgCopyTextureToTexture(
	WgTexture source,
	int32_t sourceMip,
	int32_t sourceX,
	int32_t sourceY,
	int32_t sourceZ,
	WgTexture destination,
	int32_t destinationMip,
	int32_t destinationX,
	int32_t destinationY,
	int32_t destinationZ,
	int32_t width,
	int32_t height,
	int32_t depth) {
	WGPUTexelCopyTextureInfo from = textureInfo(source, sourceMip, sourceX, sourceY, sourceZ);
	WGPUTexelCopyTextureInfo to = textureInfo(destination, destinationMip, destinationX, destinationY, destinationZ);
	WGPUExtent3D extent = extentOf(width, height, depth);
	wgpuCommandEncoderCopyTextureToTexture(encoder, &from, &to, &extent);
}

WgView wgCreateView(
	WgTexture texture,
	int32_t aspect,
	int32_t dimension,
	int32_t baseMip,
	int32_t mipCount,
	int32_t baseLayer,
	int32_t layerCount,
	const char *label) {
	WGPUTextureViewDescriptor desc = WGPU_TEXTURE_VIEW_DESCRIPTOR_INIT;
	desc.label = text(label);
	desc.dimension = (WGPUTextureViewDimension)dimension;
	desc.baseMipLevel = (uint32_t)baseMip;
	desc.mipLevelCount = (uint32_t)mipCount;
	desc.baseArrayLayer = (uint32_t)baseLayer;
	desc.arrayLayerCount = (uint32_t)layerCount;
	desc.aspect = (WGPUTextureAspect)aspect;
	return (WgView)wgpuTextureCreateView((WGPUTexture)texture, &desc);
}

void wgReleaseView(WgView view) {
	if (view) wgpuTextureViewRelease((WGPUTextureView)view);
}

WgSampler wgCreateSampler(
	int32_t addressU,
	int32_t addressV,
	int32_t addressW,
	int32_t magFilter,
	int32_t minFilter,
	int32_t mipmapFilter,
	double lodMin,
	double lodMax,
	int32_t compare,
	int32_t maxAnisotropy,
	const char *label) {
	WGPUSamplerDescriptor desc = WGPU_SAMPLER_DESCRIPTOR_INIT;
	desc.label = text(label);
	desc.addressModeU = (WGPUAddressMode)addressU;
	desc.addressModeV = (WGPUAddressMode)addressV;
	desc.addressModeW = (WGPUAddressMode)addressW;
	desc.magFilter = (WGPUFilterMode)magFilter;
	desc.minFilter = (WGPUFilterMode)minFilter;
	desc.mipmapFilter = (WGPUMipmapFilterMode)mipmapFilter;
	desc.lodMinClamp = (float)lodMin;
	desc.lodMaxClamp = (float)lodMax;
	desc.compare = (WGPUCompareFunction)compare;
	desc.maxAnisotropy = (uint16_t)maxAnisotropy;
	return (WgSampler)wgpuDeviceCreateSampler(device, &desc);
}

void wgReleaseSampler(WgSampler sampler) {
	if (sampler) wgpuSamplerRelease((WGPUSampler)sampler);
}

WgModule wgCreateModule(const char *code, const char *label) {
	WGPUShaderSourceWGSL source = WGPU_SHADER_SOURCE_WGSL_INIT;
	source.code = text(code);
	WGPUShaderModuleDescriptor desc = WGPU_SHADER_MODULE_DESCRIPTOR_INIT;
	desc.nextInChain = &source.chain;
	desc.label = text(label);
	return (WgModule)wgpuDeviceCreateShaderModule(device, &desc);
}

void wgReleaseModule(WgModule module) {
	if (module) wgpuShaderModuleRelease((WGPUShaderModule)module);
}

#define LAYOUT_STRIDE 6

enum { LAYOUT_UNIFORM, LAYOUT_TEXTURE, LAYOUT_SAMPLER, LAYOUT_STORAGE_BUFFER, LAYOUT_STORAGE_TEXTURE };

WgLayout wgCreateLayout(const int32_t *entries, int32_t count, const char *label) {
	WGPUBindGroupLayoutEntry layoutEntries[MAX_ENTRIES];
	for (int32_t i = 0; i < count; i++) {
		const int32_t *e = entries + i * LAYOUT_STRIDE;
		int32_t kind = e[2];
		int32_t bindingType = e[3];
		WGPUBindGroupLayoutEntry entry = WGPU_BIND_GROUP_LAYOUT_ENTRY_INIT;
		entry.binding = (uint32_t)e[0];
		entry.visibility = (WGPUShaderStage)e[1];
		if (kind == LAYOUT_UNIFORM) {
			entry.buffer.type = WGPUBufferBindingType_Uniform;
			entry.buffer.hasDynamicOffset = 1;
		} else if (kind == LAYOUT_TEXTURE) {
			entry.texture.sampleType = (WGPUTextureSampleType)bindingType;
			entry.texture.viewDimension = (WGPUTextureViewDimension)e[4];
		} else if (kind == LAYOUT_STORAGE_BUFFER) {
			entry.buffer.type = (WGPUBufferBindingType)bindingType;
		} else if (kind == LAYOUT_STORAGE_TEXTURE) {
			entry.storageTexture.access = (WGPUStorageTextureAccess)bindingType;
			entry.storageTexture.format = (WGPUTextureFormat)e[5];
			entry.storageTexture.viewDimension = (WGPUTextureViewDimension)e[4];
		} else {
			entry.sampler.type = (WGPUSamplerBindingType)bindingType;
		}
		layoutEntries[i] = entry;
	}
	WGPUBindGroupLayoutDescriptor desc = WGPU_BIND_GROUP_LAYOUT_DESCRIPTOR_INIT;
	desc.label = text(label);
	desc.entryCount = (size_t)count;
	desc.entries = layoutEntries;
	return (WgLayout)wgpuDeviceCreateBindGroupLayout(device, &desc);
}

void wgReleaseLayout(WgLayout layout) {
	if (layout) wgpuBindGroupLayoutRelease((WGPUBindGroupLayout)layout);
}

enum {
	PL_BUFFER_COUNT,
	PL_TARGET_COUNT,
	PL_TOPOLOGY,
	PL_STRIP_INDEX_FORMAT,
	PL_CULL_MODE,
	PL_FRONT_FACE,
	PL_SAMPLE_COUNT,
	PL_DEPTH_FORMAT,
	PL_DEPTH_WRITE,
	PL_DEPTH_COMPARE,
	PL_STENCIL_READ_MASK,
	PL_STENCIL_WRITE_MASK,
	PL_DEPTH_BIAS,
	PL_STENCIL_FRONT,
	PL_STENCIL_BACK = PL_STENCIL_FRONT + 4,
	PL_BUFFERS = PL_STENCIL_BACK + 4,
	PL_BUFFER_STRIDE = 3 + MAX_ATTRIBUTES * 3,
	PL_TARGETS = PL_BUFFERS + MAX_BUFFERS * PL_BUFFER_STRIDE,
	PL_TARGET_STRIDE = 10
};

static WGPUStencilFaceState stencilFaceOf(const int32_t *face) {
	WGPUStencilFaceState state = WGPU_STENCIL_FACE_STATE_INIT;
	state.compare = (WGPUCompareFunction)face[0];
	state.failOp = (WGPUStencilOperation)face[1];
	state.depthFailOp = (WGPUStencilOperation)face[2];
	state.passOp = (WGPUStencilOperation)face[3];
	return state;
}

static WGPUPipelineLayout pipelineLayoutOf(WgLayout uniformLayout, WgLayout resourceLayout, const char *label) {
	WGPUBindGroupLayout groups[2] = {
		(WGPUBindGroupLayout)uniformLayout,
		(WGPUBindGroupLayout)resourceLayout};
	WGPUPipelineLayoutDescriptor desc = WGPU_PIPELINE_LAYOUT_DESCRIPTOR_INIT;
	desc.label = text(label);
	desc.bindGroupLayoutCount = 2;
	desc.bindGroupLayouts = groups;
	return wgpuDeviceCreatePipelineLayout(device, &desc);
}

WgPipeline wgCreatePipeline(
	WgModule vertex,
	const char *vertexEntry,
	WgModule fragment,
	const char *fragmentEntry,
	WgLayout uniformLayout,
	WgLayout resourceLayout,
	const int32_t *state,
	const double *depthBias,
	const char *label) {
	WGPUPipelineLayout layout = pipelineLayoutOf(uniformLayout, resourceLayout, label);
	WGPURenderPipeline pipeline = NULL;
	if (layout) {
		int32_t targetCount = state[PL_TARGET_COUNT];
		WGPUVertexBufferLayout vertexBuffers[MAX_BUFFERS];
		WGPUVertexAttribute vertexAttributes[MAX_BUFFERS][MAX_ATTRIBUTES];
		WGPUColorTargetState colorTargets[MAX_TARGETS];
		WGPUBlendState blendStates[MAX_TARGETS];
		WGPUDepthStencilState depthStencil;
		memset(vertexBuffers, 0, sizeof(vertexBuffers));
		memset(colorTargets, 0, sizeof(colorTargets));
		for (int32_t b = 0; b < state[PL_BUFFER_COUNT]; b++) {
			const int32_t *buffer = state + PL_BUFFERS + b * PL_BUFFER_STRIDE;
			if (buffer[0] == 0 && buffer[2] == 0) continue;
			vertexBuffers[b].arrayStride = (uint64_t)buffer[0];
			vertexBuffers[b].stepMode = (WGPUVertexStepMode)buffer[1];
			vertexBuffers[b].attributeCount = (size_t)buffer[2];
			vertexBuffers[b].attributes = vertexAttributes[b];
			for (int32_t a = 0; a < buffer[2]; a++) {
				vertexAttributes[b][a].format = (WGPUVertexFormat)buffer[3 + a * 3];
				vertexAttributes[b][a].offset = (uint64_t)buffer[4 + a * 3];
				vertexAttributes[b][a].shaderLocation = (uint32_t)buffer[5 + a * 3];
			}
		}
		for (int32_t i = 0; i < targetCount; i++) {
			const int32_t *t = state + PL_TARGETS + i * PL_TARGET_STRIDE;
			if (t[0] == 0) continue;
			WGPUColorTargetState target = WGPU_COLOR_TARGET_STATE_INIT;
			target.format = (WGPUTextureFormat)t[0];
			target.writeMask = (WGPUColorWriteMask)t[9];
			if (t[1]) {
				blendStates[i].color.operation = (WGPUBlendOperation)t[2];
				blendStates[i].color.srcFactor = (WGPUBlendFactor)t[3];
				blendStates[i].color.dstFactor = (WGPUBlendFactor)t[4];
				blendStates[i].alpha.operation = (WGPUBlendOperation)t[5];
				blendStates[i].alpha.srcFactor = (WGPUBlendFactor)t[6];
				blendStates[i].alpha.dstFactor = (WGPUBlendFactor)t[7];
				target.blend = &blendStates[i];
			}
			colorTargets[i] = target;
		}
		WGPURenderPipelineDescriptor desc = WGPU_RENDER_PIPELINE_DESCRIPTOR_INIT;
		desc.label = text(label);
		desc.layout = layout;
		desc.vertex.module = (WGPUShaderModule)vertex;
		desc.vertex.entryPoint = text(vertexEntry);
		desc.vertex.bufferCount = (size_t)state[PL_BUFFER_COUNT];
		desc.vertex.buffers = vertexBuffers;
		desc.primitive.topology = (WGPUPrimitiveTopology)state[PL_TOPOLOGY];
		desc.primitive.stripIndexFormat = (WGPUIndexFormat)state[PL_STRIP_INDEX_FORMAT];
		desc.primitive.cullMode = (WGPUCullMode)state[PL_CULL_MODE];
		desc.primitive.frontFace = (WGPUFrontFace)state[PL_FRONT_FACE];
		if (state[PL_DEPTH_FORMAT] != WGPUTextureFormat_Undefined) {
			depthStencil = (WGPUDepthStencilState)WGPU_DEPTH_STENCIL_STATE_INIT;
			depthStencil.format = (WGPUTextureFormat)state[PL_DEPTH_FORMAT];
			depthStencil.depthWriteEnabled =
				state[PL_DEPTH_WRITE] ? WGPUOptionalBool_True : WGPUOptionalBool_False;
			depthStencil.depthCompare = (WGPUCompareFunction)state[PL_DEPTH_COMPARE];
			depthStencil.stencilReadMask = (uint32_t)state[PL_STENCIL_READ_MASK];
			depthStencil.stencilWriteMask = (uint32_t)state[PL_STENCIL_WRITE_MASK];
			depthStencil.depthBias = state[PL_DEPTH_BIAS];
			depthStencil.depthBiasSlopeScale = (float)depthBias[0];
			depthStencil.depthBiasClamp = (float)depthBias[1];
			depthStencil.stencilFront = stencilFaceOf(state + PL_STENCIL_FRONT);
			depthStencil.stencilBack = stencilFaceOf(state + PL_STENCIL_BACK);
			desc.depthStencil = &depthStencil;
		}
		desc.multisample.count = (uint32_t)state[PL_SAMPLE_COUNT];
		WGPUFragmentState fragmentState = WGPU_FRAGMENT_STATE_INIT;
		if (targetCount > 0) {
			fragmentState.module = (WGPUShaderModule)fragment;
			fragmentState.entryPoint = text(fragmentEntry);
			fragmentState.targetCount = (size_t)targetCount;
			fragmentState.targets = colorTargets;
			desc.fragment = &fragmentState;
		}
		pipeline = wgpuDeviceCreateRenderPipeline(device, &desc);
		wgpuPipelineLayoutRelease(layout);
	}
	return (WgPipeline)pipeline;
}

void wgReleasePipeline(WgPipeline pipeline) {
	if (pipeline) wgpuRenderPipelineRelease((WGPURenderPipeline)pipeline);
}

WgPipeline wgCreateComputePipeline(
	WgModule module,
	const char *entry,
	WgLayout uniformLayout,
	WgLayout resourceLayout,
	const char *label) {
	WGPUPipelineLayout layout = pipelineLayoutOf(uniformLayout, resourceLayout, label);
	WGPUComputePipeline pipeline = NULL;
	if (layout) {
		WGPUComputePipelineDescriptor desc = WGPU_COMPUTE_PIPELINE_DESCRIPTOR_INIT;
		desc.label = text(label);
		desc.layout = layout;
		desc.compute.module = (WGPUShaderModule)module;
		desc.compute.entryPoint = text(entry);
		pipeline = wgpuDeviceCreateComputePipeline(device, &desc);
		wgpuPipelineLayoutRelease(layout);
	}
	return (WgPipeline)pipeline;
}

void wgReleaseComputePipeline(WgPipeline pipeline) {
	if (pipeline) wgpuComputePipelineRelease((WGPUComputePipeline)pipeline);
}

WgBindGroup wgCreateBindGroup(
	WgLayout layout,
	int32_t count,
	const int32_t *bindings,
	const WgBuffer *buffers,
	const int64_t *ranges,
	const WgView *views,
	const WgSampler *samplers,
	const char *label) {
	WGPUBindGroupEntry entries[MAX_ENTRIES];
	for (int32_t i = 0; i < count; i++) {
		WGPUBindGroupEntry entry = WGPU_BIND_GROUP_ENTRY_INIT;
		entry.binding = (uint32_t)bindings[i];
		entry.buffer = (WGPUBuffer)buffers[i];
		if (buffers[i]) {
			entry.offset = (uint64_t)ranges[i * 2];
			entry.size = (uint64_t)ranges[i * 2 + 1];
		}
		entry.textureView = (WGPUTextureView)views[i];
		entry.sampler = (WGPUSampler)samplers[i];
		entries[i] = entry;
	}
	WGPUBindGroupDescriptor desc = WGPU_BIND_GROUP_DESCRIPTOR_INIT;
	desc.label = text(label);
	desc.layout = (WGPUBindGroupLayout)layout;
	desc.entryCount = (size_t)count;
	desc.entries = entries;
	return (WgBindGroup)wgpuDeviceCreateBindGroup(device, &desc);
}

void wgReleaseBindGroup(WgBindGroup group) {
	if (group) wgpuBindGroupRelease((WGPUBindGroup)group);
}

int32_t wgBeginEncoder(void) {
	if (encoder) return 0;
	WGPUCommandEncoderDescriptor desc = WGPU_COMMAND_ENCODER_DESCRIPTOR_INIT;
	encoder = wgpuDeviceCreateCommandEncoder(device, &desc);
	return encoder ? 1 : 0;
}

static WGPUPassTimestampWrites timestampWrites(WgQuerySet set, int32_t begin, int32_t end) {
	WGPUPassTimestampWrites writes = WGPU_PASS_TIMESTAMP_WRITES_INIT;
	writes.querySet = (WGPUQuerySet)set;
	writes.beginningOfPassWriteIndex = begin < 0 ? WGPU_QUERY_SET_INDEX_UNDEFINED : (uint32_t)begin;
	writes.endOfPassWriteIndex = end < 0 ? WGPU_QUERY_SET_INDEX_UNDEFINED : (uint32_t)end;
	return writes;
}

enum {
	PASS_COLOR_COUNT,
	PASS_WIDTH,
	PASS_HEIGHT,
	PASS_TIMESTAMP_BEGIN,
	PASS_TIMESTAMP_END,
	PASS_DEPTH_LOAD,
	PASS_DEPTH_STORE,
	PASS_DEPTH_STENCIL,
	PASS_STENCIL_LOAD,
	PASS_STENCIL_STORE,
	PASS_COLOR_OPS,
	PASS_COLOR_OP_STRIDE = 3
};
enum { PASS_DEPTH_CLEAR = MAX_TARGETS * 4, PASS_STENCIL_CLEAR };

int32_t wgBeginPass(
	const WgView *colorViews,
	const WgView *resolveViews,
	WgView depthView,
	const int32_t *ints,
	const double *reals,
	const char *label,
	WgQuerySet occlusionSet,
	WgQuerySet timestampSet) {
	passWidth = ints[PASS_WIDTH];
	passHeight = ints[PASS_HEIGHT];
	WGPURenderPassColorAttachment colorAttachments[MAX_TARGETS];
	for (int32_t i = 0; i < ints[PASS_COLOR_COUNT]; i++) {
		const int32_t *op = ints + PASS_COLOR_OPS + i * PASS_COLOR_OP_STRIDE;
		WGPURenderPassColorAttachment attachment = WGPU_RENDER_PASS_COLOR_ATTACHMENT_INIT;
		if (op[2] >= 0) attachment.depthSlice = (uint32_t)op[2];
		attachment.view = (WGPUTextureView)colorViews[i];
		attachment.resolveTarget = (WGPUTextureView)resolveViews[i];
		if (colorViews[i]) {
			attachment.loadOp = (WGPULoadOp)op[0];
			attachment.storeOp = (WGPUStoreOp)op[1];
		}
		attachment.clearValue.r = reals[i * 4];
		attachment.clearValue.g = reals[i * 4 + 1];
		attachment.clearValue.b = reals[i * 4 + 2];
		attachment.clearValue.a = reals[i * 4 + 3];
		colorAttachments[i] = attachment;
	}
	WGPURenderPassDepthStencilAttachment depthAttachment =
		WGPU_RENDER_PASS_DEPTH_STENCIL_ATTACHMENT_INIT;
	if (depthView) {
		depthAttachment.view = (WGPUTextureView)depthView;
		depthAttachment.depthLoadOp = (WGPULoadOp)ints[PASS_DEPTH_LOAD];
		depthAttachment.depthStoreOp = (WGPUStoreOp)ints[PASS_DEPTH_STORE];
		depthAttachment.depthClearValue = (float)reals[PASS_DEPTH_CLEAR];
		if (ints[PASS_DEPTH_STENCIL]) {
			depthAttachment.stencilLoadOp = (WGPULoadOp)ints[PASS_STENCIL_LOAD];
			depthAttachment.stencilStoreOp = (WGPUStoreOp)ints[PASS_STENCIL_STORE];
			depthAttachment.stencilClearValue = (uint32_t)reals[PASS_STENCIL_CLEAR];
		}
	}
	WGPURenderPassDescriptor desc = WGPU_RENDER_PASS_DESCRIPTOR_INIT;
	desc.label = text(label);
	desc.occlusionQuerySet = (WGPUQuerySet)occlusionSet;
	WGPUPassTimestampWrites writes =
		timestampWrites(timestampSet, ints[PASS_TIMESTAMP_BEGIN], ints[PASS_TIMESTAMP_END]);
	if (timestampSet) desc.timestampWrites = &writes;
	desc.colorAttachmentCount = (size_t)ints[PASS_COLOR_COUNT];
	desc.colorAttachments = colorAttachments;
	if (depthView) desc.depthStencilAttachment = &depthAttachment;
	pass = wgpuCommandEncoderBeginRenderPass(encoder, &desc);
	return pass ? 1 : 0;
}

void wgEndPass(void) {
	wgpuRenderPassEncoderEnd(pass);
	wgpuRenderPassEncoderRelease(pass);
	pass = NULL;
}

int32_t wgFinish(void) {
	WGPUCommandBufferDescriptor desc = WGPU_COMMAND_BUFFER_DESCRIPTOR_INIT;
	commands = wgpuCommandEncoderFinish(encoder, &desc);
	wgpuCommandEncoderRelease(encoder);
	encoder = NULL;
	return commands ? 1 : 0;
}

void wgSubmit(void) {
	wgpuQueueSubmit(queue, 1, &commands);
	wgpuCommandBufferRelease(commands);
	commands = NULL;
}

void wgSetPipeline(WgPipeline pipeline) {
	wgpuRenderPassEncoderSetPipeline(pass, (WGPURenderPipeline)pipeline);
}

void wgSetVertexBuffer(int32_t slot, WgBuffer buffer, int64_t offset) {
	wgpuRenderPassEncoderSetVertexBuffer(
		pass,
		(uint32_t)slot,
		(WGPUBuffer)buffer,
		(uint64_t)offset,
		WGPU_WHOLE_SIZE);
}

void wgSetIndexBuffer(WgBuffer buffer, int32_t format, int64_t offset) {
	wgpuRenderPassEncoderSetIndexBuffer(
		pass,
		(WGPUBuffer)buffer,
		(WGPUIndexFormat)format,
		(uint64_t)offset,
		WGPU_WHOLE_SIZE);
}

void wgSetBindGroup(int32_t index, WgBindGroup group, int32_t dynamicCount, const uint32_t *offsets) {
	wgpuRenderPassEncoderSetBindGroup(
		pass,
		(uint32_t)index,
		(WGPUBindGroup)group,
		(size_t)dynamicCount,
		offsets);
}

void wgSetScissorRect(int32_t x, int32_t y, int32_t width, int32_t height) {
	x = x < 0 ? 0 : (x > passWidth - 1 ? passWidth - 1 : x);
	y = y < 0 ? 0 : (y > passHeight - 1 ? passHeight - 1 : y);
	if (x + width > passWidth) width = passWidth - x;
	if (y + height > passHeight) height = passHeight - y;
	if (width < 1) width = 1;
	if (height < 1) height = 1;
	wgpuRenderPassEncoderSetScissorRect(
		pass,
		(uint32_t)x,
		(uint32_t)y,
		(uint32_t)width,
		(uint32_t)height);
}

void wgSetViewport(double x, double y, double width, double height, double minDepth, double maxDepth) {
	wgpuRenderPassEncoderSetViewport(
		pass,
		(float)x,
		(float)y,
		(float)width,
		(float)height,
		(float)minDepth,
		(float)maxDepth);
}

void wgSetBlendConstant(double r, double g, double b, double a) {
	WGPUColor color = {r, g, b, a};
	wgpuRenderPassEncoderSetBlendConstant(pass, &color);
}

void wgSetStencilReference(uint32_t reference) {
	wgpuRenderPassEncoderSetStencilReference(pass, reference);
}

void wgDraw(
	int32_t vertexCount,
	int32_t instanceCount,
	int32_t firstVertex,
	int32_t firstInstance) {
	wgpuRenderPassEncoderDraw(
		pass,
		(uint32_t)vertexCount,
		(uint32_t)instanceCount,
		(uint32_t)firstVertex,
		(uint32_t)firstInstance);
}

void wgDrawIndexed(
	int32_t indexCount,
	int32_t instanceCount,
	int32_t firstIndex,
	int32_t baseVertex,
	int32_t firstInstance) {
	wgpuRenderPassEncoderDrawIndexed(
		pass,
		(uint32_t)indexCount,
		(uint32_t)instanceCount,
		(uint32_t)firstIndex,
		baseVertex,
		(uint32_t)firstInstance);
}

int32_t wgBeginComputePass(const char *label, WgQuerySet timestampSet, int32_t timestampBegin, int32_t timestampEnd) {
	WGPUComputePassDescriptor desc = WGPU_COMPUTE_PASS_DESCRIPTOR_INIT;
	desc.label = text(label);
	WGPUPassTimestampWrites writes = timestampWrites(timestampSet, timestampBegin, timestampEnd);
	if (timestampSet) desc.timestampWrites = &writes;
	computePass = wgpuCommandEncoderBeginComputePass(encoder, &desc);
	return computePass ? 1 : 0;
}

void wgEndComputePass(void) {
	wgpuComputePassEncoderEnd(computePass);
	wgpuComputePassEncoderRelease(computePass);
	computePass = NULL;
}

void wgSetComputePipeline(WgPipeline pipeline) {
	wgpuComputePassEncoderSetPipeline(computePass, (WGPUComputePipeline)pipeline);
}

void wgSetComputeBindGroup(int32_t index, WgBindGroup group, int32_t dynamicCount, const uint32_t *offsets) {
	wgpuComputePassEncoderSetBindGroup(
		computePass,
		(uint32_t)index,
		(WGPUBindGroup)group,
		(size_t)dynamicCount,
		offsets);
}

void wgDispatch(int32_t x, int32_t y, int32_t z) {
	wgpuComputePassEncoderDispatchWorkgroups(computePass, (uint32_t)x, (uint32_t)y, (uint32_t)z);
}

void wgDispatchIndirect(WgBuffer buffer, int64_t offset) {
	wgpuComputePassEncoderDispatchWorkgroupsIndirect(computePass, (WGPUBuffer)buffer, (uint64_t)offset);
}

WgQuerySet wgCreateQuerySet(int32_t timestamp, int32_t count, const char *label) {
	WGPUQuerySetDescriptor desc = WGPU_QUERY_SET_DESCRIPTOR_INIT;
	desc.label = text(label);
	desc.type = timestamp ? WGPUQueryType_Timestamp : WGPUQueryType_Occlusion;
	desc.count = (uint32_t)count;
	return (WgQuerySet)wgpuDeviceCreateQuerySet(device, &desc);
}

void wgReleaseQuerySet(WgQuerySet querySet) {
	if (querySet) wgpuQuerySetRelease((WGPUQuerySet)querySet);
}

void wgResolveQuerySet(WgQuerySet querySet, int32_t first, int32_t count, WgBuffer destination, int64_t offset) {
	wgpuCommandEncoderResolveQuerySet(
		encoder, (WGPUQuerySet)querySet, (uint32_t)first, (uint32_t)count, (WGPUBuffer)destination, (uint64_t)offset);
}

void wgBeginOcclusionQuery(int32_t index) { wgpuRenderPassEncoderBeginOcclusionQuery(pass, (uint32_t)index); }
void wgEndOcclusionQuery(void) { wgpuRenderPassEncoderEndOcclusionQuery(pass); }

void wgPushDebugGroup(const char *label) {
	if (pass) wgpuRenderPassEncoderPushDebugGroup(pass, text(label));
	else if (computePass) wgpuComputePassEncoderPushDebugGroup(computePass, text(label));
	else wgpuCommandEncoderPushDebugGroup(encoder, text(label));
}

void wgPopDebugGroup(void) {
	if (pass) wgpuRenderPassEncoderPopDebugGroup(pass);
	else if (computePass) wgpuComputePassEncoderPopDebugGroup(computePass);
	else wgpuCommandEncoderPopDebugGroup(encoder);
}

void wgInsertDebugMarker(const char *label) {
	if (pass) wgpuRenderPassEncoderInsertDebugMarker(pass, text(label));
	else if (computePass) wgpuComputePassEncoderInsertDebugMarker(computePass, text(label));
	else wgpuCommandEncoderInsertDebugMarker(encoder, text(label));
}

typedef struct { const char *name; int32_t value; } DriverConstant;

#define DRIVER(name) { #name, (int32_t)(name) }

static char s_constantsDisagreement[256];

const char *wgConstantsDisagreement(const int32_t *values, int32_t count) {
	const DriverConstant driverConstants[] = {
		DRIVER(WGPUTextureFormat_R8Unorm),
		DRIVER(WGPUTextureFormat_R16Float),
		DRIVER(WGPUTextureFormat_RG8Unorm),
		DRIVER(WGPUTextureFormat_R32Float),
		DRIVER(WGPUTextureFormat_R32Uint),
		DRIVER(WGPUTextureFormat_RG16Float),
		DRIVER(WGPUTextureFormat_RGBA8Unorm),
		DRIVER(WGPUTextureFormat_RGBA8UnormSrgb),
		DRIVER(WGPUTextureFormat_RGBA8Uint),
		DRIVER(WGPUTextureFormat_RGBA8Sint),
		DRIVER(WGPUTextureFormat_BGRA8Unorm),
		DRIVER(WGPUTextureFormat_BGRA8UnormSrgb),
		DRIVER(WGPUTextureFormat_RGB10A2Unorm),
		DRIVER(WGPUTextureFormat_RG11B10Ufloat),
		DRIVER(WGPUTextureFormat_RG32Float),
		DRIVER(WGPUTextureFormat_RGBA16Uint),
		DRIVER(WGPUTextureFormat_RGBA16Float),
		DRIVER(WGPUTextureFormat_RGBA32Float),
		DRIVER(WGPUTextureFormat_RGBA32Uint),
		DRIVER(WGPUTextureFormat_Depth16Unorm),
		DRIVER(WGPUTextureFormat_Depth24PlusStencil8),
		DRIVER(WGPUTextureFormat_Depth32Float),
		DRIVER(WGPUFeatureName_DepthClipControl),
		DRIVER(WGPUFeatureName_Depth32FloatStencil8),
		DRIVER(WGPUFeatureName_TextureCompressionBC),
		DRIVER(WGPUFeatureName_TextureCompressionETC2),
		DRIVER(WGPUFeatureName_TextureCompressionASTC),
		DRIVER(WGPUFeatureName_TimestampQuery),
		DRIVER(WGPUFeatureName_IndirectFirstInstance),
		DRIVER(WGPUFeatureName_ShaderF16),
		DRIVER(WGPUFeatureName_RG11B10UfloatRenderable),
		DRIVER(WGPUFeatureName_BGRA8UnormStorage),
		DRIVER(WGPUFeatureName_Float32Filterable),
		DRIVER(WGPUFeatureName_Float32Blendable),
		DRIVER(WGPUFeatureName_DualSourceBlending),
		DRIVER(WGPUPrimitiveTopology_PointList),
		DRIVER(WGPUPrimitiveTopology_LineList),
		DRIVER(WGPUPrimitiveTopology_LineStrip),
		DRIVER(WGPUPrimitiveTopology_TriangleList),
		DRIVER(WGPUPrimitiveTopology_TriangleStrip),
		DRIVER(WGPUTextureDimension_2D),
		DRIVER(WGPUTextureDimension_3D),
		DRIVER(WGPUTextureViewDimension_2D),
		DRIVER(WGPUTextureViewDimension_2DArray),
		DRIVER(WGPUTextureViewDimension_Cube),
		DRIVER(WGPUTextureViewDimension_CubeArray),
		DRIVER(WGPUTextureViewDimension_3D),
		DRIVER(WGPUMipmapFilterMode_Nearest),
		DRIVER(WGPUMipmapFilterMode_Linear),
		DRIVER(WGPUBufferBindingType_Storage),
		DRIVER(WGPUBufferBindingType_ReadOnlyStorage),
		DRIVER(WGPUStorageTextureAccess_WriteOnly),
		DRIVER(WGPUStorageTextureAccess_ReadOnly),
		DRIVER(WGPUStorageTextureAccess_ReadWrite),
		DRIVER(WGPUTextureSampleType_Float),
		DRIVER(WGPUTextureSampleType_UnfilterableFloat),
		DRIVER(WGPUTextureSampleType_Sint),
		DRIVER(WGPUTextureSampleType_Uint),
		DRIVER(WGPUSamplerBindingType_Filtering),
		DRIVER(WGPUSamplerBindingType_NonFiltering),
		DRIVER(WGPUTextureAspect_All),
		DRIVER(WGPUTextureAspect_DepthOnly),
		DRIVER(WGPULoadOp_Load),
		DRIVER(WGPULoadOp_Clear),
		DRIVER(WGPUStoreOp_Store),
		DRIVER(WGPUStoreOp_Discard),
		DRIVER(WGPUVertexStepMode_Vertex),
		DRIVER(WGPUVertexStepMode_Instance),
		DRIVER(WGPUCullMode_None),
		DRIVER(WGPUCullMode_Front),
		DRIVER(WGPUCullMode_Back),
		DRIVER(WGPUFrontFace_CCW),
		DRIVER(WGPUFrontFace_CW),
		DRIVER(WGPUCompareFunction_Never),
		DRIVER(WGPUCompareFunction_Less),
		DRIVER(WGPUCompareFunction_Equal),
		DRIVER(WGPUCompareFunction_LessEqual),
		DRIVER(WGPUCompareFunction_Greater),
		DRIVER(WGPUCompareFunction_NotEqual),
		DRIVER(WGPUCompareFunction_GreaterEqual),
		DRIVER(WGPUCompareFunction_Always),
		DRIVER(WGPUBlendFactor_Zero),
		DRIVER(WGPUBlendFactor_One),
		DRIVER(WGPUBlendFactor_Src),
		DRIVER(WGPUBlendFactor_OneMinusSrc),
		DRIVER(WGPUBlendFactor_SrcAlpha),
		DRIVER(WGPUBlendFactor_OneMinusSrcAlpha),
		DRIVER(WGPUBlendFactor_Dst),
		DRIVER(WGPUBlendFactor_OneMinusDst),
		DRIVER(WGPUBlendFactor_DstAlpha),
		DRIVER(WGPUBlendFactor_OneMinusDstAlpha),
		DRIVER(WGPUBlendFactor_SrcAlphaSaturated),
		DRIVER(WGPUBlendFactor_Constant),
		DRIVER(WGPUBlendFactor_OneMinusConstant),
		DRIVER(WGPUBlendOperation_Add),
		DRIVER(WGPUBlendOperation_Subtract),
		DRIVER(WGPUBlendOperation_ReverseSubtract),
		DRIVER(WGPUBlendOperation_Min),
		DRIVER(WGPUBlendOperation_Max),
		DRIVER(WGPUStencilOperation_Keep),
		DRIVER(WGPUStencilOperation_Zero),
		DRIVER(WGPUStencilOperation_Replace),
		DRIVER(WGPUStencilOperation_Invert),
		DRIVER(WGPUStencilOperation_IncrementClamp),
		DRIVER(WGPUStencilOperation_DecrementClamp),
		DRIVER(WGPUStencilOperation_IncrementWrap),
		DRIVER(WGPUStencilOperation_DecrementWrap),
		DRIVER(WGPUVertexFormat_Float32),
		DRIVER(WGPUVertexFormat_Float32x2),
		DRIVER(WGPUVertexFormat_Float32x3),
		DRIVER(WGPUVertexFormat_Float32x4),
		DRIVER(WGPUVertexFormat_Uint32),
		DRIVER(WGPUVertexFormat_Uint32x2),
		DRIVER(WGPUVertexFormat_Uint32x3),
		DRIVER(WGPUVertexFormat_Uint32x4),
		DRIVER(WGPUVertexFormat_Sint32),
		DRIVER(WGPUVertexFormat_Sint32x2),
		DRIVER(WGPUVertexFormat_Sint32x3),
		DRIVER(WGPUVertexFormat_Sint32x4),
		DRIVER(WGPUVertexFormat_Uint8x2),
		DRIVER(WGPUVertexFormat_Uint8x4),
		DRIVER(WGPUVertexFormat_Sint8x2),
		DRIVER(WGPUVertexFormat_Sint8x4),
		DRIVER(WGPUVertexFormat_Unorm8x2),
		DRIVER(WGPUVertexFormat_Unorm8x4),
		DRIVER(WGPUVertexFormat_Snorm8x2),
		DRIVER(WGPUVertexFormat_Snorm8x4),
		DRIVER(WGPUVertexFormat_Uint16x2),
		DRIVER(WGPUVertexFormat_Uint16x4),
		DRIVER(WGPUVertexFormat_Sint16x2),
		DRIVER(WGPUVertexFormat_Sint16x4),
		DRIVER(WGPUVertexFormat_Unorm16x2),
		DRIVER(WGPUVertexFormat_Unorm16x4),
		DRIVER(WGPUVertexFormat_Snorm16x2),
		DRIVER(WGPUVertexFormat_Snorm16x4),
		DRIVER(WGPUVertexFormat_Float16x2),
		DRIVER(WGPUVertexFormat_Float16x4),
		DRIVER(WGPUAddressMode_ClampToEdge),
		DRIVER(WGPUAddressMode_Repeat),
		DRIVER(WGPUAddressMode_MirrorRepeat),
		DRIVER(WGPUFilterMode_Nearest),
		DRIVER(WGPUFilterMode_Linear),
		DRIVER(WGPUIndexFormat_Uint16),
		DRIVER(WGPUIndexFormat_Uint32),
		DRIVER(WGPUColorWriteMask_All),
		DRIVER(LIMIT_TEXTURE_DIMENSION_1D),
		DRIVER(LIMIT_TEXTURE_DIMENSION_2D),
		DRIVER(LIMIT_TEXTURE_DIMENSION_3D),
		DRIVER(LIMIT_TEXTURE_ARRAY_LAYERS),
		DRIVER(LIMIT_BIND_GROUPS),
		DRIVER(LIMIT_SAMPLED_TEXTURES),
		DRIVER(LIMIT_SAMPLERS),
		DRIVER(LIMIT_STORAGE_BUFFERS),
		DRIVER(LIMIT_STORAGE_TEXTURES),
		DRIVER(LIMIT_UNIFORM_BUFFERS),
		DRIVER(LIMIT_UNIFORM_BINDING_SIZE),
		DRIVER(LIMIT_STORAGE_BINDING_SIZE),
		DRIVER(LIMIT_VERTEX_BUFFERS),
		DRIVER(LIMIT_VERTEX_ATTRIBUTES),
		DRIVER(LIMIT_COLOR_ATTACHMENTS),
		DRIVER(LIMIT_WORKGROUP_SIZE_X),
		DRIVER(LIMIT_WORKGROUP_SIZE_Y),
		DRIVER(LIMIT_WORKGROUP_SIZE_Z),
		DRIVER(LIMIT_WORKGROUP_INVOCATIONS),
		DRIVER(LIMIT_WORKGROUPS_PER_DIMENSION),
		DRIVER(LIMIT_UNIFORM_ALIGNMENT),
		DRIVER(LIMIT_STORAGE_ALIGNMENT),
		DRIVER(LAYOUT_UNIFORM),
		DRIVER(LAYOUT_TEXTURE),
		DRIVER(LAYOUT_SAMPLER),
		DRIVER(LAYOUT_STORAGE_BUFFER),
		DRIVER(LAYOUT_STORAGE_TEXTURE),
		DRIVER(LAYOUT_STRIDE),
		DRIVER(PL_BUFFER_COUNT),
		DRIVER(PL_TARGET_COUNT),
		DRIVER(PL_TOPOLOGY),
		DRIVER(PL_STRIP_INDEX_FORMAT),
		DRIVER(PL_CULL_MODE),
		DRIVER(PL_FRONT_FACE),
		DRIVER(PL_SAMPLE_COUNT),
		DRIVER(PL_DEPTH_FORMAT),
		DRIVER(PL_DEPTH_WRITE),
		DRIVER(PL_DEPTH_COMPARE),
		DRIVER(PL_STENCIL_READ_MASK),
		DRIVER(PL_STENCIL_WRITE_MASK),
		DRIVER(PL_DEPTH_BIAS),
		DRIVER(PL_STENCIL_FRONT),
		DRIVER(PL_STENCIL_BACK),
		DRIVER(PL_BUFFERS),
		DRIVER(PL_TARGET_STRIDE),
		DRIVER(PASS_COLOR_COUNT),
		DRIVER(PASS_WIDTH),
		DRIVER(PASS_HEIGHT),
		DRIVER(PASS_TIMESTAMP_BEGIN),
		DRIVER(PASS_TIMESTAMP_END),
		DRIVER(PASS_DEPTH_LOAD),
		DRIVER(PASS_DEPTH_STORE),
		DRIVER(PASS_DEPTH_STENCIL),
		DRIVER(PASS_STENCIL_LOAD),
		DRIVER(PASS_STENCIL_STORE),
		DRIVER(PASS_COLOR_OPS),
		DRIVER(PASS_COLOR_OP_STRIDE),
		DRIVER(PL_BUFFER_STRIDE),
		DRIVER(PL_TARGETS),
		DRIVER(PASS_DEPTH_CLEAR),
		DRIVER(PASS_STENCIL_CLEAR),
		DRIVER(MAX_BUFFERS),
		DRIVER(MAX_ATTRIBUTES),
		DRIVER(MAX_TARGETS),
	};
	int32_t known = (int32_t)(sizeof driverConstants / sizeof driverConstants[0]);
	s_constantsDisagreement[0] = 0;
	if (count != known) {
		snprintf(s_constantsDisagreement, sizeof s_constantsDisagreement, "backend.ms lists %d constants and wgpu.c checks %d", (int)count, (int)known);
		return s_constantsDisagreement;
	}
	for (int32_t i = 0; i < known; i++) {
		if (values[i] == driverConstants[i].value) continue;
		snprintf(s_constantsDisagreement, sizeof s_constantsDisagreement, "entry %d: %s is %d in webgpu.h or wgpu.c and %d in backend.ms",
			(int)i, driverConstants[i].name, (int)driverConstants[i].value, (int)values[i]);
		break;
	}
	return s_constantsDisagreement;
}
