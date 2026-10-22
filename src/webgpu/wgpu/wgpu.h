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
typedef struct WgQuerySetImpl *WgQuerySet;

int32_t wgSetup(void *device);
void wgShutdown(void);
int64_t wgLimit(int32_t which);
int32_t wgMaxTextureDimension2D(void);
int32_t wgMinUniformBufferOffsetAlignment(void);
int32_t wgHasFeature(int32_t feature);
WgView wgViewFrom(void *native);
void *wgTextureNative(WgTexture texture);

WgBuffer wgCreateBuffer(int64_t bytes, int32_t usage, const char *label);
void wgReleaseBuffer(WgBuffer buffer);
void wgWriteBuffer(WgBuffer buffer, int64_t offset, const void *data, int64_t bytes);

WgTexture wgCreateTexture(
	int32_t width,
	int32_t height,
	int32_t depthOrLayers,
	int32_t mipLevels,
	int32_t dimension,
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
	int32_t mipLevel,
	int32_t x,
	int32_t y,
	int32_t z,
	int32_t width,
	int32_t height,
	int32_t depth);
void wgCopyBufferToBuffer(WgBuffer source, int64_t sourceOffset, WgBuffer destination, int64_t destinationOffset, int64_t bytes);
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
	int32_t depth);
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
	int32_t depth);
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
	int32_t depth);
WgView wgCreateView(
	WgTexture texture,
	int32_t aspect,
	int32_t dimension,
	int32_t baseMip,
	int32_t mipCount,
	int32_t baseLayer,
	int32_t layerCount,
	const char *label);
void wgReleaseView(WgView view);

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
	const char *label);
void wgReleaseSampler(WgSampler sampler);

WgModule wgCreateModule(const char *code, const char *label);
void wgReleaseModule(WgModule module);

WgLayout wgCreateLayout(const int32_t *entries, int32_t count, const char *label);
void wgReleaseLayout(WgLayout layout);

WgPipeline wgCreatePipeline(
	WgModule vertex,
	const char *vertexEntry,
	WgModule fragment,
	const char *fragmentEntry,
	WgLayout uniformLayout,
	WgLayout resourceLayout,
	const int32_t *state,
	const double *depthBias,
	const char *label);
void wgReleasePipeline(WgPipeline pipeline);
WgPipeline wgCreateComputePipeline(
	WgModule module,
	const char *entry,
	WgLayout uniformLayout,
	WgLayout resourceLayout,
	const char *label);
void wgReleaseComputePipeline(WgPipeline pipeline);

void wgBindEntry(
	int32_t index,
	int32_t binding,
	WgBuffer buffer,
	int64_t offset,
	int64_t size,
	WgView view,
	WgSampler sampler);
WgBindGroup wgCreateBindGroup(WgLayout layout, int32_t count, const char *label);
void wgReleaseBindGroup(WgBindGroup group);

int32_t wgBeginEncoder(void);
int32_t wgBeginPass(
	const WgView *colorViews,
	const WgView *resolveViews,
	WgView depthView,
	const int32_t *ints,
	const double *reals,
	const char *label,
	WgQuerySet occlusionSet,
	WgQuerySet timestampSet);
void wgEndPass(void);
int32_t wgFinish(void);
void wgSubmit(void);
void wgSetPipeline(WgPipeline pipeline);
void wgSetVertexBuffer(int32_t slot, WgBuffer buffer, int64_t offset);
void wgSetIndexBuffer(WgBuffer buffer, int32_t format, int64_t offset);
void wgDynamicOffset(int32_t index, uint32_t offset);
void wgSetBindGroup(int32_t index, WgBindGroup group, int32_t dynamicCount);
void wgSetScissorRect(int32_t x, int32_t y, int32_t width, int32_t height);
void wgSetViewport(double x, double y, double width, double height, double minDepth, double maxDepth);
void wgSetBlendConstant(double r, double g, double b, double a);
void wgSetStencilReference(uint32_t reference);
void wgDraw(int32_t vertexCount, int32_t instanceCount, int32_t firstVertex, int32_t firstInstance);
void wgDrawIndexed(
	int32_t indexCount,
	int32_t instanceCount,
	int32_t firstIndex,
	int32_t baseVertex,
	int32_t firstInstance);

int32_t wgBeginComputePass(const char *label, WgQuerySet timestampSet, int32_t timestampBegin, int32_t timestampEnd);
void wgEndComputePass(void);
void wgSetComputePipeline(WgPipeline pipeline);
void wgSetComputeBindGroup(int32_t index, WgBindGroup group, int32_t dynamicCount);
void wgDispatch(int32_t x, int32_t y, int32_t z);
void wgDispatchIndirect(WgBuffer buffer, int64_t offset);

WgQuerySet wgCreateQuerySet(int32_t timestamp, int32_t count, const char *label);
void wgReleaseQuerySet(WgQuerySet querySet);
void wgResolveQuerySet(WgQuerySet querySet, int32_t first, int32_t count, WgBuffer destination, int64_t offset);
void wgBeginOcclusionQuery(int32_t index);
void wgEndOcclusionQuery(void);

void wgPushDebugGroup(const char *label);
void wgPopDebugGroup(void);
void wgInsertDebugMarker(const char *label);
