#pragma once
#include <stdint.h>

typedef struct WgBufferImpl *WgBuffer;
typedef struct WgTextureImpl *WgTexture;
typedef struct WgViewImpl *WgView;
typedef struct WgSamplerImpl *WgSampler;
typedef struct WgModuleImpl *WgModule;
typedef struct WgLayoutImpl *WgLayout;
typedef struct WgPipelineImpl *WgPipeline;
typedef struct WgBindGroupImpl *WgBindGroup;

int32_t wgSetup(void *device);
void wgShutdown(void);
int32_t wgMaxTextureDimension2D(void);
int32_t wgMinUniformBufferOffsetAlignment(void);
WgView wgViewFrom(void *native);
void *wgTextureNative(WgTexture texture);

WgBuffer wgCreateBuffer(int64_t bytes, int32_t usage, const char *label);
void wgReleaseBuffer(WgBuffer buffer);
void wgWriteBuffer(WgBuffer buffer, int64_t offset, const void *data, int64_t bytes);

WgTexture wgCreateTexture(
	int32_t width,
	int32_t height,
	int32_t format,
	int32_t usage,
	int32_t sampleCount,
	const char *label);
void wgReleaseTexture(WgTexture texture);
void wgWriteTexture(
	WgTexture texture,
	const void *data,
	int64_t bytes,
	int64_t offset,
	int32_t bytesPerRow,
	int32_t rowsPerImage,
	int32_t x,
	int32_t y,
	int32_t width,
	int32_t height);
WgView wgCreateView(WgTexture texture, int32_t aspect, const char *label);
void wgReleaseView(WgView view);

WgSampler wgCreateSampler(
	int32_t addressU,
	int32_t addressV,
	int32_t magFilter,
	int32_t minFilter,
	const char *label);
void wgReleaseSampler(WgSampler sampler);

WgModule wgCreateModule(const char *code, const char *label);
void wgReleaseModule(WgModule module);

void wgLayoutEntry(
	int32_t index,
	int32_t binding,
	int32_t visibility,
	int32_t kind,
	int32_t bindingType);
WgLayout wgCreateLayout(int32_t count);
void wgReleaseLayout(WgLayout layout);

void wgVertexBuffer(int32_t slot, int32_t stride, int32_t stepMode);
void wgVertexAttribute(int32_t slot, int32_t format, int32_t offset, int32_t location);
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
	int32_t writeMask);
void wgDepthStencil(int32_t format, int32_t depthWriteEnabled, int32_t depthCompare);
WgPipeline wgCreatePipeline(
	WgModule vertex,
	const char *vertexEntry,
	WgModule fragment,
	const char *fragmentEntry,
	WgLayout uniformLayout,
	WgLayout resourceLayout,
	int32_t bufferCount,
	int32_t targetCount,
	int32_t cullMode,
	int32_t frontFace,
	int32_t sampleCount,
	const char *label);
void wgReleasePipeline(WgPipeline pipeline);

void wgBindEntry(
	int32_t index,
	int32_t binding,
	WgBuffer buffer,
	int64_t size,
	WgView view,
	WgSampler sampler);
WgBindGroup wgCreateBindGroup(WgLayout layout, int32_t count);
void wgReleaseBindGroup(WgBindGroup group);

int32_t wgBeginEncoder(void);
void wgColorAttachment(
	int32_t index,
	WgView view,
	WgView resolve,
	int32_t loadOp,
	int32_t storeOp,
	double r,
	double g,
	double b,
	double a);
void wgDepthAttachment(
	WgView view,
	int32_t loadOp,
	int32_t storeOp,
	double clearValue,
	int32_t stencil);
int32_t wgBeginPass(int32_t colorCount, int32_t depth, int32_t width, int32_t height);
void wgEndPass(void);
int32_t wgFinish(void);
void wgSubmit(void);
void wgSetPipeline(WgPipeline pipeline);
void wgSetVertexBuffer(int32_t slot, WgBuffer buffer, int64_t offset);
void wgSetIndexBuffer(WgBuffer buffer, int32_t format, int64_t offset);
void wgDynamicOffset(int32_t index, uint32_t offset);
void wgSetBindGroup(int32_t index, WgBindGroup group, int32_t dynamicCount);
void wgSetScissorRect(int32_t x, int32_t y, int32_t width, int32_t height);
void wgDraw(int32_t vertexCount, int32_t instanceCount, int32_t firstVertex, int32_t firstInstance);
void wgDrawIndexed(
	int32_t indexCount,
	int32_t instanceCount,
	int32_t firstIndex,
	int32_t baseVertex,
	int32_t firstInstance);
