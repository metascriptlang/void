#pragma once
#include <stdint.h>

#define VULKAN_OK 0
#define VULKAN_ERROR_LIBRARY 1
#define VULKAN_ERROR_FUNCTION 2
#define VULKAN_ERROR_CALL 3
#define VULKAN_ERROR_EXTENSION 4
#define VULKAN_ERROR_ADAPTER 5
#define VULKAN_ERROR_ORDER 6
#define VULKAN_SUBOPTIMAL 7
#define VULKAN_OUT_OF_DATE 8
#define VULKAN_SURFACE_LOST 9
#define VULKAN_OUT_OF_MEMORY 10
#define VULKAN_DEVICE_LOST 11

#define VULKAN_POWER_DEFAULT 0
#define VULKAN_POWER_LOW 1
#define VULKAN_POWER_HIGH 2

#define VULKAN_FEATURE_BC 0x2
#define VULKAN_FEATURE_ETC2 0x4
#define VULKAN_FEATURE_ASTC 0x8
#define VULKAN_FEATURE_INDIRECT_FIRST_INSTANCE 0x400

#define VULKAN_LIMIT_TEXTURE_DIMENSION_1D 0
#define VULKAN_LIMIT_TEXTURE_DIMENSION_2D 1
#define VULKAN_LIMIT_TEXTURE_DIMENSION_3D 2
#define VULKAN_LIMIT_TEXTURE_ARRAY_LAYERS 3
#define VULKAN_LIMIT_BIND_GROUPS 4
#define VULKAN_LIMIT_SAMPLED_TEXTURES_PER_STAGE 5
#define VULKAN_LIMIT_SAMPLERS_PER_STAGE 6
#define VULKAN_LIMIT_STORAGE_BUFFERS_PER_STAGE 7
#define VULKAN_LIMIT_STORAGE_TEXTURES_PER_STAGE 8
#define VULKAN_LIMIT_UNIFORM_BUFFERS_PER_STAGE 9
#define VULKAN_LIMIT_UNIFORM_BUFFER_BINDING_SIZE 10
#define VULKAN_LIMIT_STORAGE_BUFFER_BINDING_SIZE 11
#define VULKAN_LIMIT_VERTEX_BUFFERS 12
#define VULKAN_LIMIT_VERTEX_ATTRIBUTES 13
#define VULKAN_LIMIT_COLOR_ATTACHMENTS 14
#define VULKAN_LIMIT_WORKGROUP_SIZE_X 15
#define VULKAN_LIMIT_WORKGROUP_SIZE_Y 16
#define VULKAN_LIMIT_WORKGROUP_SIZE_Z 17
#define VULKAN_LIMIT_WORKGROUP_INVOCATIONS 18
#define VULKAN_LIMIT_WORKGROUPS_PER_DIMENSION 19
#define VULKAN_LIMIT_UNIFORM_OFFSET_ALIGNMENT 20
#define VULKAN_LIMIT_STORAGE_OFFSET_ALIGNMENT 21
#define VULKAN_LIMIT_NON_COHERENT_ATOM_SIZE 22
#define VULKAN_LIMIT_MEMORY_ALLOCATION_COUNT 23

#define VULKAN_SURFACE_MIN_IMAGES 0
#define VULKAN_SURFACE_MAX_IMAGES 1
#define VULKAN_SURFACE_CURRENT_WIDTH 2
#define VULKAN_SURFACE_CURRENT_HEIGHT 3
#define VULKAN_SURFACE_MIN_WIDTH 4
#define VULKAN_SURFACE_MIN_HEIGHT 5
#define VULKAN_SURFACE_MAX_WIDTH 6
#define VULKAN_SURFACE_MAX_HEIGHT 7
#define VULKAN_SURFACE_TRANSFORMS 9
#define VULKAN_SURFACE_COMPOSITE_ALPHA 10
#define VULKAN_SURFACE_USAGE 11

#define VULKAN_DEDICATED_NONE 0
#define VULKAN_DEDICATED_PREFERRED 1
#define VULKAN_DEDICATED_REQUIRED 2

int32_t vulkanLoaderOpen(void);
const char *vulkanError(void);

int32_t vulkanInstanceCreate(void);
int32_t vulkanValidationEnabled(void);
int32_t vulkanValidationErrors(void);
int32_t vulkanValidationWarnings(void);

int32_t vulkanSurfaceCreateWin32(void *hinstance, void *hwnd);
int32_t vulkanSurfaceCreateXlib(void *display, uint64_t window);
int32_t vulkanSurfaceCreateAndroid(void *window);
int32_t vulkanSurfaceQuery(void);
uint32_t vulkanSurfaceCapability(int32_t field);
int32_t vulkanSurfaceFormatCount(void);
int32_t vulkanSurfaceFormat(int32_t index, int32_t *format, uint32_t *colorSpace);
int32_t vulkanSurfacePresentModeCount(void);
uint32_t vulkanSurfacePresentMode(int32_t index);
int32_t vulkanSurfaceDestroy(void);

int32_t vulkanAdapterSelect(int32_t powerPreference);
uint32_t vulkanAdapterVendorId(void);
uint32_t vulkanAdapterDeviceId(void);
const char *vulkanAdapterName(void);
uint32_t vulkanAdapterDriverVersion(void);
uint32_t vulkanAdapterApiVersion(void);
int32_t vulkanAdapterQueueFamily(void);
int64_t vulkanAdapterLimit(int32_t limit);

int32_t vulkanDeviceCreate(void);
uint32_t vulkanDeviceFeatures(void);
int32_t vulkanDeviceReady(void);

int32_t vulkanMemoryTypeCount(void);
int32_t vulkanMemoryType(int32_t index, uint32_t *flags, int32_t *heap);
int32_t vulkanMemoryHeapCount(void);
uint64_t vulkanMemoryHeapSize(int32_t heap);

uint32_t vulkanFormatOptimalFeatures(int32_t format);

int32_t vulkanMemoryAllocate(
	int32_t typeIndex,
	uint64_t size,
	uint64_t dedicatedBuffer,
	uint64_t dedicatedImage,
	uint64_t *memory);
int32_t vulkanMemoryMap(uint64_t memory, uint64_t *address);
void vulkanMemoryFree(uint64_t memory);
int32_t vulkanMappedWrite(
	uint64_t memory,
	uint64_t address,
	uint64_t offset,
	void *data,
	uint64_t dataOffset,
	uint64_t rowBytes,
	uint64_t sourcePitch,
	uint64_t targetPitch,
	uint32_t rows,
	uint64_t flushOffset,
	uint64_t flushSize);
int32_t vulkanMappedRead(
	uint64_t memory,
	uint64_t address,
	uint64_t offset,
	void *out,
	uint64_t bytes,
	uint64_t invalidateOffset,
	uint64_t invalidateSize);

int32_t vulkanBufferCreate(uint64_t size, uint32_t usage, uint64_t *buffer);
void vulkanBufferRequirements(uint64_t buffer, uint64_t *size, uint64_t *alignment, uint32_t *typeBits, int32_t *dedication);
int32_t vulkanBufferBind(uint64_t buffer, uint64_t memory, uint64_t offset);
void vulkanBufferDestroy(uint64_t buffer);

int32_t vulkanImageCreate(
	int32_t imageType,
	int32_t format,
	uint32_t width,
	uint32_t height,
	uint32_t depth,
	uint32_t mipLevels,
	uint32_t layers,
	uint32_t samples,
	uint32_t usage,
	uint32_t flags,
	uint64_t *image);
void vulkanImageRequirements(uint64_t image, uint64_t *size, uint64_t *alignment, uint32_t *typeBits, int32_t *dedication);
int32_t vulkanImageBind(uint64_t image, uint64_t memory, uint64_t offset);
void vulkanImageDestroy(uint64_t image);

int32_t vulkanViewCreate(
	uint64_t image,
	int32_t viewType,
	int32_t format,
	uint32_t aspect,
	uint32_t baseMip,
	uint32_t mipCount,
	uint32_t baseLayer,
	uint32_t layerCount,
	uint64_t *view);
void vulkanViewDestroy(uint64_t view);

int32_t vulkanSamplerCreate(
	int32_t magFilter,
	int32_t minFilter,
	int32_t mipmapMode,
	int32_t addressU,
	int32_t addressV,
	int32_t addressW,
	float lodMin,
	float lodMax,
	int32_t compareOp,
	uint32_t maxAnisotropy,
	uint64_t *sampler);
void vulkanSamplerDestroy(uint64_t sampler);

int32_t vulkanBarrierImage(uint64_t image, uint32_t aspect, uint32_t sourceAccess, uint32_t targetAccess, int32_t oldLayout, int32_t newLayout);
int32_t vulkanBarrierFlush(uint32_t sourceStages, uint32_t targetStages, uint32_t sourceAccess, uint32_t targetAccess);
int32_t vulkanQueueStream(uint32_t on);
int32_t vulkanCopyBuffer(uint64_t source, uint64_t sourceOffset, uint64_t target, uint64_t targetOffset, uint64_t bytes);
int32_t vulkanCopyBufferToImage(
	uint64_t buffer,
	uint64_t offset,
	uint32_t rowLength,
	uint32_t imageHeight,
	uint64_t image,
	uint32_t aspect,
	uint32_t mip,
	int32_t x,
	int32_t y,
	int32_t z,
	uint32_t baseLayer,
	uint32_t layerCount,
	uint32_t width,
	uint32_t height,
	uint32_t depth);
int32_t vulkanCopyImageToBuffer(
	uint64_t buffer,
	uint64_t offset,
	uint32_t rowLength,
	uint32_t imageHeight,
	uint64_t image,
	uint32_t aspect,
	uint32_t mip,
	int32_t x,
	int32_t y,
	int32_t z,
	uint32_t baseLayer,
	uint32_t layerCount,
	uint32_t width,
	uint32_t height,
	uint32_t depth);
int32_t vulkanCopyImage(
	uint64_t source,
	uint32_t sourceMip,
	int32_t sourceX,
	int32_t sourceY,
	int32_t sourceZ,
	uint32_t sourceLayer,
	uint64_t target,
	uint32_t targetMip,
	int32_t targetX,
	int32_t targetY,
	int32_t targetZ,
	uint32_t targetLayer,
	uint32_t aspect,
	uint32_t layerCount,
	uint32_t width,
	uint32_t height,
	uint32_t depth);
int32_t vulkanCmdPushLabel(const char *label);
int32_t vulkanCmdPopLabel(void);
int32_t vulkanCmdInsertLabel(const char *label);

int32_t vulkanRenderPassCreate(const uint32_t *key, uint32_t words, uint64_t *renderPass);
void vulkanRenderPassDestroy(uint64_t renderPass);
int32_t vulkanPassBegin(
	uint64_t renderPass,
	const uint32_t *key,
	uint32_t words,
	const uint64_t *views,
	uint32_t viewCount,
	uint32_t width,
	uint32_t height,
	const float *clears,
	uint32_t clearCount);
int32_t vulkanPassEnd(void);

int32_t vulkanShaderModuleCreate(const uint8_t *code, uint64_t bytes, uint64_t *module);
void vulkanShaderModuleDestroy(uint64_t module);
int32_t vulkanSetLayoutCreate(const uint32_t *entries, uint32_t count, uint64_t *layout);
void vulkanSetLayoutDestroy(uint64_t layout);
int32_t vulkanPipelineLayoutCreate(const uint64_t *setLayouts, uint32_t count, uint64_t *layout);
void vulkanPipelineLayoutDestroy(uint64_t layout);
int32_t vulkanDescriptorPoolCreate(const uint32_t *sizes, uint32_t sizeCount, uint32_t maxSets, uint64_t setLayout, uint64_t *pool);
uint64_t vulkanDescriptorPoolSet(uint32_t index);
void vulkanDescriptorPoolDestroy(uint64_t pool);
int32_t vulkanDescriptorSetWrite(
	uint64_t set,
	const uint32_t *words,
	const uint64_t *handles,
	const uint64_t *offsets,
	const uint64_t *ranges,
	uint32_t count);
int32_t vulkanRenderPipelineCreate(
	uint64_t layout,
	uint64_t renderPass,
	uint64_t vertexModule,
	const char *vertexEntry,
	uint64_t fragmentModule,
	const char *fragmentEntry,
	const uint32_t *state,
	const uint32_t *vertex,
	uint32_t bufferCount,
	uint32_t attributeCount,
	const uint32_t *targets,
	uint32_t targetCount,
	float depthBiasSlope,
	float depthBiasClamp,
	uint64_t *pipeline);
int32_t vulkanComputePipelineCreate(uint64_t layout, uint64_t module, const char *entry, uint64_t *pipeline);
void vulkanPipelineDestroy(uint64_t pipeline);

int32_t vulkanCmdBindPipeline(int32_t compute, uint64_t pipeline);
int32_t vulkanCmdBindSet(int32_t compute, uint64_t layout, uint32_t index, uint64_t set, const uint32_t *offsets, uint32_t offsetCount);
int32_t vulkanCmdBindVertexBuffer(uint32_t slot, uint64_t buffer, uint64_t offset);
int32_t vulkanCmdBindIndexBuffer(uint64_t buffer, uint64_t offset, int32_t indexType);
int32_t vulkanCmdViewport(float x, float y, float width, float height, float minDepth, float maxDepth);
int32_t vulkanCmdScissor(int32_t x, int32_t y, uint32_t width, uint32_t height);
int32_t vulkanCmdBlendConstants(float r, float g, float b, float a);
int32_t vulkanCmdStencilReference(uint32_t reference);
int32_t vulkanCmdDraw(uint32_t vertexCount, uint32_t instanceCount, uint32_t firstVertex, uint32_t firstInstance);
int32_t vulkanCmdDrawIndexed(uint32_t indexCount, uint32_t instanceCount, uint32_t firstIndex, int32_t baseVertex, uint32_t firstInstance);
int32_t vulkanCmdDrawIndexedIndirect(uint64_t buffer, uint64_t offset, uint32_t drawCount);
int32_t vulkanCmdDispatch(uint32_t x, uint32_t y, uint32_t z);
int32_t vulkanCmdDispatchIndirect(uint64_t buffer, uint64_t offset);

int32_t vulkanSwapchainCreate(
	int32_t format,
	uint32_t colorSpace,
	uint32_t width,
	uint32_t height,
	uint32_t minImageCount,
	uint32_t usage,
	uint32_t preTransform,
	uint32_t compositeAlpha,
	uint32_t presentMode);
uint32_t vulkanSwapchainImageCount(void);
uint64_t vulkanSwapchainImage(uint32_t index);
uint64_t vulkanSwapchainView(uint32_t index);
int32_t vulkanSwapchainTarget(void *renderView, uint64_t *image, uint64_t *view);
int32_t vulkanSwapchainAcquire(uint32_t *index);
int32_t vulkanSwapchainPresent(void);
int32_t vulkanSwapchainDestroy(void);

int32_t vulkanFramesCreate(uint32_t count);
int32_t vulkanFrameBegin(uint32_t slot, uint64_t waitSerial);

int32_t vulkanSubmit(uint64_t *serial);
uint32_t vulkanRecordingOpen(void);
uint64_t vulkanRecordingSerial(void);
int32_t vulkanCompletedSerial(uint64_t *serial);
int32_t vulkanWaitSerial(uint64_t serial);

void vulkanShutdown(void);
