#pragma once
#include <stdint.h>

#define DX12_OK 0
#define DX12_ERROR_CALL -1
#define DX12_ERROR_ADAPTER -2
#define DX12_ERROR_DEBUG_LAYER -3
#define DX12_OUT_OF_MEMORY -4
#define DX12_DEVICE_REMOVED -5

#define DX12_EVENT_BEGIN 0
#define DX12_EVENT_END 1
#define DX12_EVENT_MARKER 2

const char *dx12Error(void);

int32_t dx12DeviceCreate(int32_t warp, int32_t debug, uint64_t *device, uint64_t *adapter);
int32_t dx12InfoDrain(uint64_t device, uint64_t *count);
int32_t dx12AdapterDescribe(uint64_t adapter, uint32_t *vendorId, uint32_t *deviceId);
const char *dx12AdapterDescription(void);

int32_t dx12QueueCreate(uint64_t device, uint64_t *queue);
int32_t dx12QueueSignal(uint64_t queue, uint64_t fence, uint64_t value);
int32_t dx12QueueExecute(uint64_t queue, uint64_t list);

int32_t dx12FenceCreate(uint64_t device, uint64_t *fence, uint64_t *event);
int32_t dx12FenceCompleted(uint64_t fence, uint64_t *value);
int32_t dx12FenceWait(uint64_t fence, uint64_t event, uint64_t value);
int32_t dx12EventClose(uint64_t event);

int32_t dx12AllocatorCreate(uint64_t device, uint64_t *allocator);
int32_t dx12AllocatorReset(uint64_t allocator);
int32_t dx12ListCreate(uint64_t device, uint64_t allocator, uint64_t *list);
int32_t dx12ListReset(uint64_t list, uint64_t allocator);
int32_t dx12ListClose(uint64_t list);

int32_t dx12BufferCreate(uint64_t device, uint64_t size, int32_t heap, uint32_t state, int32_t unordered, uint64_t *resource);
int32_t dx12ResourceAddress(uint64_t resource, uint64_t *address);
int32_t dx12ResourceMap(uint64_t resource, uint64_t readBegin, uint64_t readEnd, uint64_t *pointer);
int32_t dx12ResourceUnmap(uint64_t resource, uint64_t writtenBegin, uint64_t writtenEnd);
int32_t dx12MemoryWrite(uint64_t pointer, void *data, uint64_t bytes);
int32_t dx12MemoryRead(uint64_t pointer, void *out, uint64_t bytes);
int32_t dx12MemoryWriteRows(uint64_t pointer, void *data, uint64_t dataOffset, uint64_t dataPitch, uint64_t rowBytes, uint64_t rowPitch, uint32_t rows);

int32_t dx12TextureCreate(uint64_t device, int32_t volume, uint32_t width, uint32_t height, uint32_t depthOrArraySize, uint32_t mipLevels, int32_t format, uint32_t sampleCount, uint32_t flags, uint64_t *resource);
int32_t dx12CopyableFootprint(uint64_t device, int32_t format, uint32_t width, uint32_t height, uint32_t *rowPitch, uint32_t *rows, uint64_t *rowBytes, uint64_t *totalBytes);
int32_t dx12FormatSupport(uint64_t device, int32_t format, uint32_t *support1, uint32_t *support2);

int32_t dx12CopyBufferRegion(uint64_t list, uint64_t target, uint64_t targetOffset, uint64_t source, uint64_t sourceOffset, uint64_t bytes);
int32_t dx12CopyBufferTexture(uint64_t list, int32_t toTexture, uint64_t texture, uint32_t subresource, uint32_t x, uint32_t y, uint32_t z, uint64_t buffer, uint64_t offset, int32_t format, uint32_t footprintWidth, uint32_t footprintHeight, uint32_t rowPitch, uint32_t bufferX, uint32_t bufferY, uint32_t width, uint32_t height);
int32_t dx12CopyTexture(uint64_t list, uint64_t target, uint32_t targetSubresource, uint32_t targetX, uint32_t targetY, uint32_t targetZ, uint64_t source, uint32_t sourceSubresource, uint32_t sourceX, uint32_t sourceY, uint32_t sourceZ, uint32_t width, uint32_t height, uint32_t depth);
int32_t dx12BarrierTransition(uint64_t resource, uint32_t subresource, uint32_t before, uint32_t after);
int32_t dx12BarrierFlush(uint64_t list, int32_t uav);

int32_t dx12DescriptorHeapCreate(uint64_t device, int32_t type, uint32_t count, int32_t shaderVisible, uint64_t *heap, uint64_t *cpuStart, uint64_t *gpuStart, uint32_t *increment);
int32_t dx12DescriptorsCopy(uint64_t device, uint32_t count, uint64_t target, uint64_t source, int32_t type);
int32_t dx12DescriptorsGather(uint64_t device, uint32_t count, uint64_t target, uint64_t sourceStart, uint32_t increment, const int32_t *indices, int32_t type);
int32_t dx12TextureSrv(uint64_t device, uint64_t resource, int32_t format, int32_t dimension, int32_t multisampled, uint32_t baseMip, uint32_t mipCount, uint32_t baseLayer, uint32_t layerCount, uint64_t handle);
int32_t dx12TextureUav(uint64_t device, uint64_t resource, int32_t format, int32_t dimension, uint32_t mip, uint32_t baseLayer, uint32_t layerCount, uint64_t handle);
int32_t dx12BufferSrv(uint64_t device, uint64_t resource, uint64_t offset, uint64_t bytes, uint64_t handle);
int32_t dx12BufferUav(uint64_t device, uint64_t resource, uint64_t offset, uint64_t bytes, uint64_t handle);
int32_t dx12SamplerCreate(uint64_t device, int32_t filter, int32_t addressU, int32_t addressV, int32_t addressW, uint32_t maxAnisotropy, int32_t comparison, double minLod, double maxLod, uint64_t handle);
int32_t dx12RootSignatureSerialize(const uint32_t *parameters, uint32_t parameterCount, const uint32_t *ranges, uint32_t rangeCount, uint32_t flags, uint64_t *blob, uint64_t *bytes);
int32_t dx12RootSignatureCreate(uint64_t device, uint64_t blob, uint64_t *signature);
int32_t dx12SetDescriptorHeaps(uint64_t list, uint64_t views, uint64_t samplers);
int32_t dx12SetRootSignature(uint64_t list, int32_t compute, uint64_t signature);
int32_t dx12SetRootConstantBufferView(uint64_t list, int32_t compute, uint32_t parameter, uint64_t address);
int32_t dx12SetRootDescriptorTable(uint64_t list, int32_t compute, uint32_t parameter, uint64_t handle);

int32_t dx12ShaderCompile(const char *source, const char *entryPoint, const char *target, uint64_t *blob, uint64_t *bytes, uint64_t *size);
const char *dx12CompileLog(void);
int32_t dx12RenderPipelineCreate(uint64_t device, uint64_t signature, const uint8_t *vertex, uint64_t vertexBytes, const uint8_t *pixel, uint64_t pixelBytes, const int32_t *elements, uint32_t elementCount, const int32_t *targets, uint32_t targetCount, const int32_t *words, uint32_t wordCount, double depthBiasSlopeScale, double depthBiasClamp, uint64_t *pipeline);
int32_t dx12ComputePipelineCreate(uint64_t device, uint64_t signature, const uint8_t *compute, uint64_t computeBytes, uint64_t *pipeline);
int32_t dx12RenderTargetView(uint64_t device, uint64_t resource, int32_t format, int32_t dimension, int32_t multisampled, uint32_t mip, uint32_t layer, uint64_t handle);
int32_t dx12DepthStencilView(uint64_t device, uint64_t resource, int32_t format, int32_t dimension, int32_t multisampled, uint32_t mip, uint32_t layer, uint64_t handle);
int32_t dx12SetRenderTargets(uint64_t list, const uint64_t *targets, uint32_t count, uint64_t depth);
int32_t dx12ClearRenderTarget(uint64_t list, uint64_t handle, double r, double g, double b, double a);
int32_t dx12ClearDepthStencil(uint64_t list, uint64_t handle, int32_t flags, double depth, uint32_t stencil);
int32_t dx12SetViewport(uint64_t list, double x, double y, double width, double height, double minDepth, double maxDepth);
int32_t dx12SetScissorRect(uint64_t list, int32_t left, int32_t top, int32_t right, int32_t bottom);
int32_t dx12SetBlendFactor(uint64_t list, double r, double g, double b, double a);
int32_t dx12SetStencilReference(uint64_t list, uint32_t reference);
int32_t dx12SetPipelineState(uint64_t list, uint64_t pipeline, int32_t topology);
int32_t dx12SetVertexBuffer(uint64_t list, uint32_t slot, uint64_t address, uint32_t bytes, uint32_t stride);
int32_t dx12SetIndexBuffer(uint64_t list, uint64_t address, uint32_t bytes, int32_t format);
int32_t dx12Draw(uint64_t list, uint32_t vertexCount, uint32_t instanceCount, uint32_t firstVertex, uint32_t firstInstance);
int32_t dx12DrawIndexed(uint64_t list, uint32_t indexCount, uint32_t instanceCount, uint32_t firstIndex, int32_t baseVertex, uint32_t firstInstance);
int32_t dx12Dispatch(uint64_t list, uint32_t x, uint32_t y, uint32_t z);
int32_t dx12CommandSignatureCreate(uint64_t device, int32_t argumentType, uint32_t stride, uint64_t *signature);
int32_t dx12ExecuteIndirect(uint64_t list, uint64_t signature, uint32_t count, uint64_t buffer, uint64_t offset);
int32_t dx12QueryHeapCreate(uint64_t device, int32_t type, uint32_t count, uint64_t *heap);
int32_t dx12QueryBegin(uint64_t list, uint64_t heap, int32_t type, uint32_t index);
int32_t dx12QueryEnd(uint64_t list, uint64_t heap, int32_t type, uint32_t index);
int32_t dx12QueryResolve(uint64_t list, uint64_t heap, int32_t type, uint32_t first, uint32_t count, uint64_t buffer, uint64_t offset);
int32_t dx12TimestampFrequency(uint64_t queue, uint64_t *frequency);
int32_t dx12ResolveSubresource(uint64_t list, uint64_t target, uint32_t targetSubresource, uint64_t source, uint32_t sourceSubresource, int32_t format);
int32_t dx12Event(uint64_t list, int32_t kind, const char *label);
int32_t dx12SetName(uint64_t object, const char *name);
int32_t dx12ObjectName(uint64_t object, uint8_t *out, int32_t size);

int32_t dx12TearingSupported(uint64_t adapter, int32_t *supported);
int32_t dx12SwapchainCreate(uint64_t adapter, uint64_t queue, uint64_t window, int32_t composition, uint32_t width, uint32_t height, int32_t format, uint32_t bufferCount, uint32_t flags, uint32_t latency, uint64_t *swapchain, uint64_t *waitable);
int32_t dx12SwapchainBuffer(uint64_t swapchain, uint32_t index, uint64_t *resource);
int32_t dx12SwapchainCurrent(uint64_t swapchain, uint32_t *index);
int32_t dx12SwapchainResize(uint64_t swapchain, uint32_t bufferCount, uint32_t width, uint32_t height, uint32_t flags);
int32_t dx12SwapchainPresent(uint64_t swapchain, uint32_t interval, uint32_t flags, int32_t *result);
int32_t dx12SwapchainRelease(uint64_t swapchain, uint64_t waitable);
int32_t dx12RemovedReason(uint64_t device, int32_t *reason);
int32_t dx12PointerBits(void *pointer, uint64_t *bits);

int32_t dx12Release(uint64_t object);
