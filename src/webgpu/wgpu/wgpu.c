#include <string.h>
#include <webgpu/webgpu.h>
#include "wgpu.h"

#define MAX_ENTRIES 24
#define MAX_BUFFERS 2
#define MAX_ATTRIBUTES 16
#define MAX_TARGETS 4
#define MAX_DYNAMIC_OFFSETS 8

static WGPUDevice device;
static WGPUQueue queue;
static WGPULimits limits;
static WGPUCommandEncoder encoder;
static WGPUCommandBuffer commands;
static WGPURenderPassEncoder pass;
static WGPUComputePassEncoder computePass;
static int32_t passWidth;
static int32_t passHeight;

static WGPUBindGroupLayoutEntry layoutEntries[MAX_ENTRIES];
static WGPUBindGroupEntry bindEntries[MAX_ENTRIES];
static WGPUVertexBufferLayout vertexBuffers[MAX_BUFFERS];
static WGPUVertexAttribute vertexAttributes[MAX_BUFFERS][MAX_ATTRIBUTES];
static WGPUColorTargetState colorTargets[MAX_TARGETS];
static WGPUBlendState blendStates[MAX_TARGETS];
static WGPUDepthStencilState depthStencil;
static WGPURenderPassColorAttachment colorAttachments[MAX_TARGETS];
static WGPURenderPassDepthStencilAttachment depthAttachment;
static uint32_t dynamicOffsets[MAX_DYNAMIC_OFFSETS];

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

int64_t wgLimit(int32_t which) {
	switch (which) {
	case 0: return limits.maxTextureDimension1D;
	case 1: return limits.maxTextureDimension2D;
	case 2: return limits.maxTextureDimension3D;
	case 3: return limits.maxTextureArrayLayers;
	case 4: return limits.maxBindGroups;
	case 5: return limits.maxSampledTexturesPerShaderStage;
	case 6: return limits.maxSamplersPerShaderStage;
	case 7: return limits.maxStorageBuffersPerShaderStage;
	case 8: return limits.maxStorageTexturesPerShaderStage;
	case 9: return limits.maxUniformBuffersPerShaderStage;
	case 10: return (int64_t)limits.maxUniformBufferBindingSize;
	case 11: return (int64_t)limits.maxStorageBufferBindingSize;
	case 12: return limits.maxVertexBuffers;
	case 13: return limits.maxVertexAttributes;
	case 14: return limits.maxColorAttachments;
	case 15: return limits.maxComputeWorkgroupSizeX;
	case 16: return limits.maxComputeWorkgroupSizeY;
	case 17: return limits.maxComputeWorkgroupSizeZ;
	case 18: return limits.maxComputeInvocationsPerWorkgroup;
	case 19: return limits.maxComputeWorkgroupsPerDimension;
	case 20: return limits.minUniformBufferOffsetAlignment;
	case 21: return limits.minStorageBufferOffsetAlignment;
	default: return -1;
	}
}
int32_t wgMaxTextureDimension2D(void) { return (int32_t)limits.maxTextureDimension2D; }
int32_t wgMinUniformBufferOffsetAlignment(void) {
	return (int32_t)limits.minUniformBufferOffsetAlignment;
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

void wgLayoutEntry(
	int32_t index,
	int32_t binding,
	int32_t visibility,
	int32_t kind,
	int32_t bindingType,
	int32_t viewDimension,
	int32_t storageFormat) {
	WGPUBindGroupLayoutEntry entry = WGPU_BIND_GROUP_LAYOUT_ENTRY_INIT;
	entry.binding = (uint32_t)binding;
	entry.visibility = (WGPUShaderStage)visibility;
	if (kind == 0) {
		entry.buffer.type = WGPUBufferBindingType_Uniform;
		entry.buffer.hasDynamicOffset = 1;
	} else if (kind == 1) {
		entry.texture.sampleType = (WGPUTextureSampleType)bindingType;
		entry.texture.viewDimension = (WGPUTextureViewDimension)viewDimension;
	} else if (kind == 3) {
		entry.buffer.type = (WGPUBufferBindingType)bindingType;
	} else if (kind == 4) {
		entry.storageTexture.access = (WGPUStorageTextureAccess)bindingType;
		entry.storageTexture.format = (WGPUTextureFormat)storageFormat;
		entry.storageTexture.viewDimension = (WGPUTextureViewDimension)viewDimension;
	} else {
		entry.sampler.type = (WGPUSamplerBindingType)bindingType;
	}
	layoutEntries[index] = entry;
}

WgLayout wgCreateLayout(int32_t count, const char *label) {
	WGPUBindGroupLayoutDescriptor desc = WGPU_BIND_GROUP_LAYOUT_DESCRIPTOR_INIT;
	desc.label = text(label);
	desc.entryCount = (size_t)count;
	desc.entries = layoutEntries;
	return (WgLayout)wgpuDeviceCreateBindGroupLayout(device, &desc);
}

void wgReleaseLayout(WgLayout layout) {
	if (layout) wgpuBindGroupLayoutRelease((WGPUBindGroupLayout)layout);
}

void wgVertexBuffer(int32_t slot, int32_t stride, int32_t stepMode) {
	vertexBuffers[slot].arrayStride = (uint64_t)stride;
	vertexBuffers[slot].stepMode = (WGPUVertexStepMode)stepMode;
	vertexBuffers[slot].attributes = vertexAttributes[slot];
}

void wgVertexAttribute(int32_t slot, int32_t format, int32_t offset, int32_t location) {
	WGPUVertexAttribute *attribute = &vertexAttributes[slot][vertexBuffers[slot].attributeCount];
	attribute->format = (WGPUVertexFormat)format;
	attribute->offset = (uint64_t)offset;
	attribute->shaderLocation = (uint32_t)location;
	vertexBuffers[slot].attributeCount += 1;
}

void wgColorTarget(
	int32_t index,
	int32_t format,
	int32_t blendEnabled,
	int32_t colorOperation,
	int32_t colorSource,
	int32_t colorDestination,
	int32_t alphaOperation,
	int32_t alphaSource,
	int32_t alphaDestination,
	int32_t writeMask) {
	WGPUColorTargetState target = WGPU_COLOR_TARGET_STATE_INIT;
	target.format = (WGPUTextureFormat)format;
	target.writeMask = (WGPUColorWriteMask)writeMask;
	if (blendEnabled) {
		blendStates[index].color.operation = (WGPUBlendOperation)colorOperation;
		blendStates[index].color.srcFactor = (WGPUBlendFactor)colorSource;
		blendStates[index].color.dstFactor = (WGPUBlendFactor)colorDestination;
		blendStates[index].alpha.operation = (WGPUBlendOperation)alphaOperation;
		blendStates[index].alpha.srcFactor = (WGPUBlendFactor)alphaSource;
		blendStates[index].alpha.dstFactor = (WGPUBlendFactor)alphaDestination;
		target.blend = &blendStates[index];
	}
	colorTargets[index] = target;
}

void wgDepthStencil(
	int32_t format,
	int32_t depthWriteEnabled,
	int32_t depthCompare,
	uint32_t stencilReadMask,
	uint32_t stencilWriteMask,
	int32_t depthBias,
	double depthBiasSlopeScale,
	double depthBiasClamp) {
	depthStencil = (WGPUDepthStencilState)WGPU_DEPTH_STENCIL_STATE_INIT;
	depthStencil.format = (WGPUTextureFormat)format;
	depthStencil.depthWriteEnabled =
		depthWriteEnabled ? WGPUOptionalBool_True : WGPUOptionalBool_False;
	depthStencil.depthCompare = (WGPUCompareFunction)depthCompare;
	depthStencil.stencilReadMask = stencilReadMask;
	depthStencil.stencilWriteMask = stencilWriteMask;
	depthStencil.depthBias = depthBias;
	depthStencil.depthBiasSlopeScale = (float)depthBiasSlopeScale;
	depthStencil.depthBiasClamp = (float)depthBiasClamp;
}

void wgStencilFace(int32_t back, int32_t compare, int32_t failOp, int32_t depthFailOp, int32_t passOp) {
	WGPUStencilFaceState *face = back ? &depthStencil.stencilBack : &depthStencil.stencilFront;
	face->compare = (WGPUCompareFunction)compare;
	face->failOp = (WGPUStencilOperation)failOp;
	face->depthFailOp = (WGPUStencilOperation)depthFailOp;
	face->passOp = (WGPUStencilOperation)passOp;
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
	int32_t bufferCount,
	int32_t targetCount,
	int32_t topology,
	int32_t stripIndexFormat,
	int32_t cullMode,
	int32_t frontFace,
	int32_t sampleCount,
	const char *label) {
	WGPUPipelineLayout layout = pipelineLayoutOf(uniformLayout, resourceLayout, label);
	WGPURenderPipeline pipeline = NULL;
	if (layout) {
		WGPURenderPipelineDescriptor desc = WGPU_RENDER_PIPELINE_DESCRIPTOR_INIT;
		desc.label = text(label);
		desc.layout = layout;
		desc.vertex.module = (WGPUShaderModule)vertex;
		desc.vertex.entryPoint = text(vertexEntry);
		desc.vertex.bufferCount = (size_t)bufferCount;
		desc.vertex.buffers = vertexBuffers;
		desc.primitive.topology = (WGPUPrimitiveTopology)topology;
		desc.primitive.stripIndexFormat = (WGPUIndexFormat)stripIndexFormat;
		desc.primitive.cullMode = (WGPUCullMode)cullMode;
		desc.primitive.frontFace = (WGPUFrontFace)frontFace;
		if (depthStencil.format != WGPUTextureFormat_Undefined) desc.depthStencil = &depthStencil;
		desc.multisample.count = (uint32_t)sampleCount;
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
	memset(vertexBuffers, 0, sizeof(vertexBuffers));
	memset(colorTargets, 0, sizeof(colorTargets));
	memset(&depthStencil, 0, sizeof(depthStencil));
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

void wgBindEntry(
	int32_t index,
	int32_t binding,
	WgBuffer buffer,
	int64_t offset,
	int64_t size,
	WgView view,
	WgSampler sampler) {
	WGPUBindGroupEntry entry = WGPU_BIND_GROUP_ENTRY_INIT;
	entry.binding = (uint32_t)binding;
	entry.buffer = (WGPUBuffer)buffer;
	if (buffer) {
		entry.offset = (uint64_t)offset;
		entry.size = (uint64_t)size;
	}
	entry.textureView = (WGPUTextureView)view;
	entry.sampler = (WGPUSampler)sampler;
	bindEntries[index] = entry;
}

WgBindGroup wgCreateBindGroup(WgLayout layout, int32_t count, const char *label) {
	WGPUBindGroupDescriptor desc = WGPU_BIND_GROUP_DESCRIPTOR_INIT;
	desc.label = text(label);
	desc.layout = (WGPUBindGroupLayout)layout;
	desc.entryCount = (size_t)count;
	desc.entries = bindEntries;
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

void wgColorAttachment(
	int32_t index,
	WgView view,
	WgView resolve,
	int32_t loadOp,
	int32_t storeOp,
	int32_t depthSlice,
	double r,
	double g,
	double b,
	double a) {
	WGPURenderPassColorAttachment attachment = WGPU_RENDER_PASS_COLOR_ATTACHMENT_INIT;
	if (depthSlice >= 0) attachment.depthSlice = (uint32_t)depthSlice;
	attachment.view = (WGPUTextureView)view;
	attachment.resolveTarget = (WGPUTextureView)resolve;
	if (view) {
		attachment.loadOp = (WGPULoadOp)loadOp;
		attachment.storeOp = (WGPUStoreOp)storeOp;
	}
	attachment.clearValue.r = r;
	attachment.clearValue.g = g;
	attachment.clearValue.b = b;
	attachment.clearValue.a = a;
	colorAttachments[index] = attachment;
}

void wgDepthAttachment(
	WgView view,
	int32_t loadOp,
	int32_t storeOp,
	double clearValue,
	int32_t stencil) {
	WGPURenderPassDepthStencilAttachment attachment =
		WGPU_RENDER_PASS_DEPTH_STENCIL_ATTACHMENT_INIT;
	attachment.view = (WGPUTextureView)view;
	attachment.depthLoadOp = (WGPULoadOp)loadOp;
	attachment.depthStoreOp = (WGPUStoreOp)storeOp;
	attachment.depthClearValue = (float)clearValue;
	if (stencil) {
		attachment.stencilLoadOp = WGPULoadOp_Clear;
		attachment.stencilStoreOp = WGPUStoreOp_Discard;
	}
	depthAttachment = attachment;
}

static WGPUPassTimestampWrites timestampWrites(WgQuerySet set, int32_t begin, int32_t end) {
	WGPUPassTimestampWrites writes = WGPU_PASS_TIMESTAMP_WRITES_INIT;
	writes.querySet = (WGPUQuerySet)set;
	writes.beginningOfPassWriteIndex = begin < 0 ? WGPU_QUERY_SET_INDEX_UNDEFINED : (uint32_t)begin;
	writes.endOfPassWriteIndex = end < 0 ? WGPU_QUERY_SET_INDEX_UNDEFINED : (uint32_t)end;
	return writes;
}

int32_t wgBeginPass(
	int32_t colorCount,
	int32_t depth,
	int32_t width,
	int32_t height,
	const char *label,
	WgQuerySet occlusionSet,
	WgQuerySet timestampSet,
	int32_t timestampBegin,
	int32_t timestampEnd) {
	passWidth = width;
	passHeight = height;
	WGPURenderPassDescriptor desc = WGPU_RENDER_PASS_DESCRIPTOR_INIT;
	desc.label = text(label);
	desc.occlusionQuerySet = (WGPUQuerySet)occlusionSet;
	WGPUPassTimestampWrites writes = timestampWrites(timestampSet, timestampBegin, timestampEnd);
	if (timestampSet) desc.timestampWrites = &writes;
	desc.colorAttachmentCount = (size_t)colorCount;
	desc.colorAttachments = colorAttachments;
	if (depth) desc.depthStencilAttachment = &depthAttachment;
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

void wgDynamicOffset(int32_t index, uint32_t offset) { dynamicOffsets[index] = offset; }

void wgSetBindGroup(int32_t index, WgBindGroup group, int32_t dynamicCount) {
	wgpuRenderPassEncoderSetBindGroup(
		pass,
		(uint32_t)index,
		(WGPUBindGroup)group,
		(size_t)dynamicCount,
		dynamicOffsets);
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

void wgSetComputeBindGroup(int32_t index, WgBindGroup group, int32_t dynamicCount) {
	wgpuComputePassEncoderSetBindGroup(
		computePass,
		(uint32_t)index,
		(WGPUBindGroup)group,
		(size_t)dynamicCount,
		dynamicOffsets);
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
