#pragma once
#include <stdint.h>

typedef struct MtlDeviceImpl *MtlDevice;
typedef struct MtlQueueImpl *MtlQueue;
typedef struct MtlBufferImpl *MtlBuffer;
typedef struct MtlTextureImpl *MtlTexture;
typedef struct MtlSamplerImpl *MtlSampler;
typedef struct MtlLibraryImpl *MtlLibrary;
typedef struct MtlFunctionImpl *MtlFunction;
typedef struct MtlPipelineImpl *MtlPipeline;
typedef struct MtlDepthStateImpl *MtlDepthState;
typedef struct MtlCommandBufferImpl *MtlCommandBuffer;
typedef struct MtlEncoderImpl *MtlEncoder;

MtlDevice mtlDeviceFrom(void *native);
void mtlReleaseDevice(MtlDevice device);
int32_t mtlUsesSharedStorage(MtlDevice device);
int32_t mtlSupportsSampleCount(MtlDevice device, int32_t count);
MtlQueue mtlNewCommandQueue(MtlDevice device);
void mtlReleaseQueue(MtlQueue queue);
MtlTexture mtlTextureFrom(void *native);
void *mtlTextureNative(MtlTexture texture);
void *mtlQueueNative(MtlQueue queue);

void mtlFrameSemaphoreCreate(int32_t framesInFlight);
void mtlFrameSemaphoreWaitAll(void);
MtlCommandBuffer mtlBeginCommandBuffer(MtlQueue queue);
void mtlCommit(MtlCommandBuffer commandBuffer);

MtlBuffer mtlNewBuffer(MtlDevice device, int64_t bytes, int32_t shared);
void mtlReleaseBuffer(MtlBuffer buffer);
void mtlWriteBuffer(MtlBuffer buffer, int64_t offset, void *data, int64_t bytes, int32_t managed);

MtlTexture mtlNewTexture(
	MtlDevice device,
	int32_t width,
	int32_t height,
	int32_t pixelFormat,
	int32_t sampleCount,
	int32_t renderTarget,
	int32_t shared);
void mtlReleaseTexture(MtlTexture texture);
void mtlWriteTexture(MtlTexture texture, void *data, int64_t offset, int32_t bytesPerRow, int32_t width, int32_t height);

MtlSampler mtlNewSampler(MtlDevice device, int32_t minFilter, int32_t magFilter, int32_t addressU, int32_t addressV);
void mtlReleaseSampler(MtlSampler sampler);

MtlLibrary mtlNewLibrary(MtlDevice device, const char *source);
MtlFunction mtlNewFunction(MtlLibrary library, const char *entryPoint);
const char *mtlErrorLog(void);
void mtlReleaseLibrary(MtlLibrary library);
void mtlReleaseFunction(MtlFunction shaderFunction);

void mtlPipelineReset(void);
void mtlPipelineAttribute(int32_t location, int32_t format, int32_t offset, int32_t bufferIndex);
void mtlPipelineLayout(int32_t bufferIndex, int32_t stride, int32_t perInstance);
void mtlPipelineColor(
	int32_t index,
	int32_t pixelFormat,
	int32_t blendEnabled,
	int32_t sourceColor,
	int32_t destinationColor,
	int32_t operationColor,
	int32_t sourceAlpha,
	int32_t destinationAlpha,
	int32_t operationAlpha,
	int32_t writeMask);
MtlPipeline mtlNewPipeline(
	MtlDevice device,
	MtlFunction vertex,
	MtlFunction fragment,
	int32_t depthFormat,
	int32_t stencilFormat,
	int32_t sampleCount);
void mtlReleasePipeline(MtlPipeline pipeline);
MtlDepthState mtlNewDepthState(MtlDevice device, int32_t compare, int32_t depthWrite);
void mtlReleaseDepthState(MtlDepthState state);

void mtlPassReset(void);
void mtlPassColor(
	int32_t index,
	MtlTexture texture,
	MtlTexture resolve,
	int32_t loadAction,
	int32_t storeAction,
	double r,
	double g,
	double b,
	double a);
void mtlPassDepth(MtlTexture texture, int32_t loadAction, int32_t storeAction, double depth, int32_t stencil);
MtlEncoder mtlBeginPass(MtlCommandBuffer commandBuffer);
void mtlEndPass(MtlEncoder encoder);

void mtlSetDrawable(void *drawable);
void mtlPresentDrawable(MtlCommandBuffer commandBuffer);

void mtlSetViewport(MtlEncoder encoder, int32_t width, int32_t height);
void mtlSetScissorRect(MtlEncoder encoder, int32_t x, int32_t y, int32_t width, int32_t height);
void mtlSetPipeline(MtlEncoder encoder, MtlPipeline pipeline, MtlDepthState depth, int32_t cullMode, int32_t winding);
void mtlSetVertexBuffer(MtlEncoder encoder, MtlBuffer buffer, int64_t offset, int32_t index);
void mtlSetFragmentBuffer(MtlEncoder encoder, MtlBuffer buffer, int64_t offset, int32_t index);
void mtlSetVertexTexture(MtlEncoder encoder, MtlTexture texture, int32_t index);
void mtlSetFragmentTexture(MtlEncoder encoder, MtlTexture texture, int32_t index);
void mtlSetVertexSampler(MtlEncoder encoder, MtlSampler sampler, int32_t index);
void mtlSetFragmentSampler(MtlEncoder encoder, MtlSampler sampler, int32_t index);
void mtlDraw(MtlEncoder encoder, int32_t vertexCount, int32_t instanceCount, int32_t firstVertex, int32_t firstInstance);
void mtlDrawIndexed(
	MtlEncoder encoder,
	MtlBuffer indexBuffer,
	int32_t indexType,
	int64_t indexOffset,
	int32_t indexCount,
	int32_t instanceCount,
	int32_t baseVertex,
	int32_t firstInstance);
