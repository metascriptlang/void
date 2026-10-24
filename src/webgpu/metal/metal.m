#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#include <stdio.h>
#include <string.h>

#include "metal.h"

#if __has_feature(objc_arc)
#error "metal.m owns its objects by hand and must be compiled without ARC"
#endif

static dispatch_semaphore_t s_frames;
static int32_t s_framesInFlight;
static char s_log[4096];
static MTLRenderPipelineDescriptor *s_pipeline;
static MTLRenderPassDescriptor *s_pass;
static id<CAMetalDrawable> s_drawable;
static id<MTLCommandBuffer> s_committed;

static void keepLog(NSError *error) {
	const char *text = error ? [[error localizedDescription] UTF8String] : "no error description";
	strncpy(s_log, text, sizeof s_log - 1);
	s_log[sizeof s_log - 1] = 0;
}

MtlDevice mtlDeviceFrom(void *native) { return (MtlDevice)[(id<MTLDevice>)native retain]; }
void mtlReleaseDevice(MtlDevice device) { [(id<MTLDevice>)device release]; }

int32_t mtlUsesSharedStorage(MtlDevice device) {
#if TARGET_OS_OSX
	return [(id<MTLDevice>)device supportsFamily:MTLGPUFamilyApple1] ? 1 : 0;
#else
	(void)device;
	return 1;
#endif
}

int32_t mtlSupportsSampleCount(MtlDevice device, int32_t count) {
	return [(id<MTLDevice>)device supportsTextureSampleCount:(NSUInteger)count] ? 1 : 0;
}

MtlQueue mtlNewCommandQueue(MtlDevice device) { return (MtlQueue)[(id<MTLDevice>)device newCommandQueue]; }
void mtlReleaseQueue(MtlQueue queue) { [(id<MTLCommandQueue>)queue release]; }
MtlTexture mtlTextureFrom(void *native) { return (MtlTexture)native; }
void *mtlTextureNative(MtlTexture texture) { return texture; }
void *mtlQueueNative(MtlQueue queue) { return queue; }

void mtlFrameSemaphoreCreate(int32_t framesInFlight) {
	if (s_frames) dispatch_release(s_frames);
	s_frames = dispatch_semaphore_create(framesInFlight);
	s_framesInFlight = framesInFlight;
}

void mtlFrameSemaphoreWaitAll(void) {
	for (int32_t i = 0; i < s_framesInFlight; i++) dispatch_semaphore_wait(s_frames, DISPATCH_TIME_FOREVER);
	for (int32_t i = 0; i < s_framesInFlight; i++) dispatch_semaphore_signal(s_frames);
}

MtlCommandBuffer mtlBeginCommandBuffer(MtlQueue queue) {
	dispatch_semaphore_wait(s_frames, DISPATCH_TIME_FOREVER);
	@autoreleasepool {
		id<MTLCommandBuffer> commandBuffer = [[(id<MTLCommandQueue>)queue commandBuffer] retain];
		[commandBuffer enqueue];
		dispatch_semaphore_t frames = s_frames;
		[commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> done) {
			(void)done;
			dispatch_semaphore_signal(frames);
		}];
		return (MtlCommandBuffer)commandBuffer;
	}
}

void mtlCommit(MtlCommandBuffer commandBuffer) {
	id<MTLCommandBuffer> cb = (id<MTLCommandBuffer>)commandBuffer;
	[cb commit];
	[s_committed release];
	s_committed = cb;
}

int32_t mtlWaitCommitted(void) {
	if (s_committed == nil) return 1;
	[s_committed waitUntilCompleted];
	return s_committed.status == MTLCommandBufferStatusCompleted ? 1 : 0;
}

void mtlForgetCommitted(void) {
	[s_committed release];
	s_committed = nil;
}

static MTLResourceOptions storageOptions(int32_t shared) {
#if TARGET_OS_OSX
	return shared ? MTLResourceStorageModeShared : MTLResourceStorageModeManaged;
#else
	(void)shared;
	return MTLResourceStorageModeShared;
#endif
}

MtlBuffer mtlNewBuffer(MtlDevice device, int64_t bytes, int32_t shared) {
	MTLResourceOptions options = MTLResourceCPUCacheModeWriteCombined | storageOptions(shared);
	return (MtlBuffer)[(id<MTLDevice>)device newBufferWithLength:(NSUInteger)bytes options:options];
}

MtlBuffer mtlNewMappableBuffer(MtlDevice device, int64_t bytes, int32_t writable) {
	MTLResourceOptions options = MTLResourceStorageModeShared | (writable ? MTLResourceCPUCacheModeWriteCombined : 0);
	return (MtlBuffer)[(id<MTLDevice>)device newBufferWithLength:(NSUInteger)bytes options:options];
}

MtlBuffer mtlNewStagingBuffer(MtlDevice device, const void *data, int64_t offset, int64_t bytes) {
	return (MtlBuffer)[(id<MTLDevice>)device newBufferWithBytes:(const uint8_t *)data + offset
		length:(NSUInteger)bytes
		options:MTLResourceStorageModeShared | MTLResourceCPUCacheModeWriteCombined];
}

void mtlCopyOut(MtlBuffer buffer, int64_t offset, void *bytes, int64_t length) {
	memcpy(bytes, (const uint8_t *)[(id<MTLBuffer>)buffer contents] + offset, (size_t)length);
}

void mtlCopyIn(MtlBuffer buffer, int64_t offset, const void *bytes, int64_t length) {
	memcpy((uint8_t *)[(id<MTLBuffer>)buffer contents] + offset, bytes, (size_t)length);
}

void mtlReleaseBuffer(MtlBuffer buffer) { [(id<MTLBuffer>)buffer release]; }

void mtlWriteBuffer(MtlBuffer buffer, int64_t offset, void *data, int64_t bytes, int32_t managed) {
	id<MTLBuffer> b = (id<MTLBuffer>)buffer;
	memcpy((uint8_t *)[b contents] + offset, data, (size_t)bytes);
#if TARGET_OS_OSX
	if (managed) [b didModifyRange:NSMakeRange((NSUInteger)offset, (NSUInteger)bytes)];
#else
	(void)managed;
#endif
}

MtlTexture mtlNewTexture(
	MtlDevice device,
	int32_t width,
	int32_t height,
	int32_t depthOrLayers,
	int32_t mipLevels,
	int32_t textureType,
	int32_t pixelFormat,
	int32_t sampleCount,
	int32_t renderTarget,
	int32_t storage,
	int32_t shared) {
	MTLTextureDescriptor *desc = [[MTLTextureDescriptor alloc] init];
	desc.textureType = (MTLTextureType)textureType;
	desc.pixelFormat = (MTLPixelFormat)pixelFormat;
	desc.width = (NSUInteger)width;
	desc.height = (NSUInteger)height;
	desc.mipmapLevelCount = (NSUInteger)mipLevels;
	if (textureType == MTLTextureType3D) { desc.depth = (NSUInteger)depthOrLayers; }
	if (textureType == MTLTextureType2DArray) { desc.arrayLength = (NSUInteger)depthOrLayers; }
	desc.sampleCount = (NSUInteger)sampleCount;
	desc.usage = MTLTextureUsageShaderRead | (renderTarget ? MTLTextureUsageRenderTarget : 0) | (storage ? MTLTextureUsageShaderWrite : 0);
	desc.resourceOptions = (renderTarget || storage)
		? MTLResourceStorageModePrivate
		: (storageOptions(shared) | MTLResourceCPUCacheModeWriteCombined);
	id<MTLTexture> texture = [(id<MTLDevice>)device newTextureWithDescriptor:desc];
	[desc release];
	return (MtlTexture)texture;
}

MtlTexture mtlNewTextureView(
	MtlTexture texture,
	int32_t pixelFormat,
	int32_t textureType,
	int32_t baseMip,
	int32_t mipCount,
	int32_t baseLayer,
	int32_t layerCount) {
	return (MtlTexture)[(id<MTLTexture>)texture newTextureViewWithPixelFormat:(MTLPixelFormat)pixelFormat
		textureType:(MTLTextureType)textureType
		levels:NSMakeRange((NSUInteger)baseMip, (NSUInteger)mipCount)
		slices:NSMakeRange((NSUInteger)baseLayer, (NSUInteger)layerCount)];
}

void mtlReleaseTexture(MtlTexture texture) { [(id<MTLTexture>)texture release]; }

void mtlBlitBufferToBuffer(MtlCommandBuffer commandBuffer, MtlBuffer source, int64_t sourceOffset, MtlBuffer destination, int64_t destinationOffset, int64_t size) {
	@autoreleasepool {
		id<MTLBlitCommandEncoder> blit = [(id<MTLCommandBuffer>)commandBuffer blitCommandEncoder];
		[blit copyFromBuffer:(id<MTLBuffer>)source
			sourceOffset:(NSUInteger)sourceOffset
			toBuffer:(id<MTLBuffer>)destination
			destinationOffset:(NSUInteger)destinationOffset
			size:(NSUInteger)size];
		[blit endEncoding];
	}
}

void mtlBlitBufferToTexture(
	MtlCommandBuffer commandBuffer,
	MtlBuffer source,
	int64_t sourceOffset,
	int32_t bytesPerRow,
	int32_t bytesPerImage,
	int32_t width,
	int32_t height,
	int32_t depth,
	MtlTexture destination,
	int32_t slice,
	int32_t level,
	int32_t x,
	int32_t y,
	int32_t z) {
	@autoreleasepool {
		id<MTLBlitCommandEncoder> blit = [(id<MTLCommandBuffer>)commandBuffer blitCommandEncoder];
		[blit copyFromBuffer:(id<MTLBuffer>)source
			sourceOffset:(NSUInteger)sourceOffset
			sourceBytesPerRow:(NSUInteger)bytesPerRow
			sourceBytesPerImage:(NSUInteger)bytesPerImage
			sourceSize:MTLSizeMake((NSUInteger)width, (NSUInteger)height, (NSUInteger)depth)
			toTexture:(id<MTLTexture>)destination
			destinationSlice:(NSUInteger)slice
			destinationLevel:(NSUInteger)level
			destinationOrigin:MTLOriginMake((NSUInteger)x, (NSUInteger)y, (NSUInteger)z)];
		[blit endEncoding];
	}
}

void mtlBlitTextureToBuffer(
	MtlCommandBuffer commandBuffer,
	MtlTexture source,
	int32_t slice,
	int32_t level,
	int32_t x,
	int32_t y,
	int32_t z,
	int32_t width,
	int32_t height,
	int32_t depth,
	MtlBuffer destination,
	int64_t destinationOffset,
	int32_t bytesPerRow,
	int32_t bytesPerImage) {
	@autoreleasepool {
		id<MTLBlitCommandEncoder> blit = [(id<MTLCommandBuffer>)commandBuffer blitCommandEncoder];
		[blit copyFromTexture:(id<MTLTexture>)source
			sourceSlice:(NSUInteger)slice
			sourceLevel:(NSUInteger)level
			sourceOrigin:MTLOriginMake((NSUInteger)x, (NSUInteger)y, (NSUInteger)z)
			sourceSize:MTLSizeMake((NSUInteger)width, (NSUInteger)height, (NSUInteger)depth)
			toBuffer:(id<MTLBuffer>)destination
			destinationOffset:(NSUInteger)destinationOffset
			destinationBytesPerRow:(NSUInteger)bytesPerRow
			destinationBytesPerImage:(NSUInteger)bytesPerImage];
		[blit endEncoding];
	}
}

void mtlBlitTextureToTexture(
	MtlCommandBuffer commandBuffer,
	MtlTexture source,
	int32_t sourceSlice,
	int32_t sourceLevel,
	int32_t sourceX,
	int32_t sourceY,
	int32_t sourceZ,
	int32_t width,
	int32_t height,
	int32_t depth,
	MtlTexture destination,
	int32_t destinationSlice,
	int32_t destinationLevel,
	int32_t destinationX,
	int32_t destinationY,
	int32_t destinationZ) {
	@autoreleasepool {
		id<MTLBlitCommandEncoder> blit = [(id<MTLCommandBuffer>)commandBuffer blitCommandEncoder];
		[blit copyFromTexture:(id<MTLTexture>)source
			sourceSlice:(NSUInteger)sourceSlice
			sourceLevel:(NSUInteger)sourceLevel
			sourceOrigin:MTLOriginMake((NSUInteger)sourceX, (NSUInteger)sourceY, (NSUInteger)sourceZ)
			sourceSize:MTLSizeMake((NSUInteger)width, (NSUInteger)height, (NSUInteger)depth)
			toTexture:(id<MTLTexture>)destination
			destinationSlice:(NSUInteger)destinationSlice
			destinationLevel:(NSUInteger)destinationLevel
			destinationOrigin:MTLOriginMake((NSUInteger)destinationX, (NSUInteger)destinationY, (NSUInteger)destinationZ)];
		[blit endEncoding];
	}
}

void mtlWriteTexture(
	MtlTexture texture,
	void *data,
	int64_t offset,
	int32_t bytesPerRow,
	int32_t bytesPerImage,
	int32_t width,
	int32_t height,
	int32_t depth,
	int32_t slice,
	int32_t level,
	int32_t x,
	int32_t y,
	int32_t z) {
	[(id<MTLTexture>)texture replaceRegion:MTLRegionMake3D((NSUInteger)x, (NSUInteger)y, (NSUInteger)z, (NSUInteger)width, (NSUInteger)height, (NSUInteger)depth)
		mipmapLevel:(NSUInteger)level
		slice:(NSUInteger)slice
		withBytes:(const uint8_t *)data + offset
		bytesPerRow:(NSUInteger)bytesPerRow
		bytesPerImage:(NSUInteger)bytesPerImage];
}

MtlSampler mtlNewSampler(
	MtlDevice device,
	int32_t minFilter,
	int32_t magFilter,
	int32_t mipFilter,
	int32_t addressU,
	int32_t addressV,
	int32_t addressW,
	float lodMin,
	float lodMax,
	int32_t maxAnisotropy,
	int32_t compare,
	const char *label) {
	MTLSamplerDescriptor *desc = [[MTLSamplerDescriptor alloc] init];
	desc.sAddressMode = (MTLSamplerAddressMode)addressU;
	desc.tAddressMode = (MTLSamplerAddressMode)addressV;
	desc.rAddressMode = (MTLSamplerAddressMode)addressW;
	desc.minFilter = (MTLSamplerMinMagFilter)minFilter;
	desc.magFilter = (MTLSamplerMinMagFilter)magFilter;
	desc.mipFilter = (MTLSamplerMipFilter)mipFilter;
	desc.lodMinClamp = lodMin;
	desc.lodMaxClamp = lodMax;
	desc.maxAnisotropy = (NSUInteger)maxAnisotropy;
	desc.normalizedCoordinates = YES;
	desc.compareFunction = (MTLCompareFunction)compare;
	if (label[0]) desc.label = [NSString stringWithUTF8String:label];
	id<MTLSamplerState> sampler = [(id<MTLDevice>)device newSamplerStateWithDescriptor:desc];
	[desc release];
	return (MtlSampler)sampler;
}

void mtlReleaseSampler(MtlSampler sampler) { [(id<MTLSamplerState>)sampler release]; }

MtlLibrary mtlNewLibrary(MtlDevice device, const char *source) {
	@autoreleasepool {
		NSError *error = nil;
		id<MTLLibrary> library = [(id<MTLDevice>)device
			newLibraryWithSource:[NSString stringWithUTF8String:source]
			options:nil
			error:&error];
		if (library == nil) keepLog(error);
		return (MtlLibrary)library;
	}
}

MtlFunction mtlNewFunction(MtlLibrary library, const char *entryPoint) {
	@autoreleasepool {
		return (MtlFunction)[(id<MTLLibrary>)library newFunctionWithName:[NSString stringWithUTF8String:entryPoint]];
	}
}

const char *mtlErrorLog(void) { return s_log; }
void mtlReleaseLibrary(MtlLibrary library) { [(id<MTLLibrary>)library release]; }
void mtlReleaseFunction(MtlFunction shaderFunction) { [(id<MTLFunction>)shaderFunction release]; }

void mtlPipelineReset(void) {
	[s_pipeline release];
	s_pipeline = [[MTLRenderPipelineDescriptor alloc] init];
}

void mtlPipelineLabel(const char *label) {
	if (label[0]) s_pipeline.label = [NSString stringWithUTF8String:label];
}

void mtlPipelineAttribute(int32_t location, int32_t format, int32_t offset, int32_t bufferIndex) {
	MTLVertexAttributeDescriptor *attribute = s_pipeline.vertexDescriptor.attributes[(NSUInteger)location];
	attribute.format = (MTLVertexFormat)format;
	attribute.offset = (NSUInteger)offset;
	attribute.bufferIndex = (NSUInteger)bufferIndex;
}

void mtlPipelineLayout(int32_t bufferIndex, int32_t stride, int32_t perInstance) {
	MTLVertexBufferLayoutDescriptor *layout = s_pipeline.vertexDescriptor.layouts[(NSUInteger)bufferIndex];
	layout.stride = (NSUInteger)stride;
	layout.stepRate = 1;
	layout.stepFunction = perInstance ? MTLVertexStepFunctionPerInstance : MTLVertexStepFunctionPerVertex;
}

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
	int32_t writeMask) {
	MTLRenderPipelineColorAttachmentDescriptor *color = s_pipeline.colorAttachments[(NSUInteger)index];
	color.pixelFormat = (MTLPixelFormat)pixelFormat;
	color.writeMask = (MTLColorWriteMask)writeMask;
	color.blendingEnabled = blendEnabled ? YES : NO;
	color.sourceRGBBlendFactor = (MTLBlendFactor)sourceColor;
	color.destinationRGBBlendFactor = (MTLBlendFactor)destinationColor;
	color.rgbBlendOperation = (MTLBlendOperation)operationColor;
	color.sourceAlphaBlendFactor = (MTLBlendFactor)sourceAlpha;
	color.destinationAlphaBlendFactor = (MTLBlendFactor)destinationAlpha;
	color.alphaBlendOperation = (MTLBlendOperation)operationAlpha;
}

MtlPipeline mtlNewPipeline(
	MtlDevice device,
	MtlFunction vertex,
	MtlFunction fragment,
	int32_t depthFormat,
	int32_t stencilFormat,
	int32_t sampleCount) {
	s_pipeline.vertexFunction = (id<MTLFunction>)vertex;
	s_pipeline.fragmentFunction = (id<MTLFunction>)fragment;
	s_pipeline.rasterSampleCount = (NSUInteger)sampleCount;
	s_pipeline.depthAttachmentPixelFormat = (MTLPixelFormat)depthFormat;
	s_pipeline.stencilAttachmentPixelFormat = (MTLPixelFormat)stencilFormat;
	NSError *error = nil;
	id<MTLRenderPipelineState> state = [(id<MTLDevice>)device newRenderPipelineStateWithDescriptor:s_pipeline error:&error];
	if (state == nil) keepLog(error);
	[s_pipeline release];
	s_pipeline = nil;
	return (MtlPipeline)state;
}

void mtlReleasePipeline(MtlPipeline pipeline) { [(id<MTLRenderPipelineState>)pipeline release]; }

static MTLStencilDescriptor *stencilFace(int32_t fail, int32_t depthFail, int32_t pass, int32_t compare, uint32_t readMask, uint32_t writeMask) {
	MTLStencilDescriptor *face = [[MTLStencilDescriptor alloc] init];
	face.stencilFailureOperation = (MTLStencilOperation)fail;
	face.depthFailureOperation = (MTLStencilOperation)depthFail;
	face.depthStencilPassOperation = (MTLStencilOperation)pass;
	face.stencilCompareFunction = (MTLCompareFunction)compare;
	face.readMask = readMask;
	face.writeMask = writeMask;
	return face;
}

MtlDepthState mtlNewDepthState(
	MtlDevice device,
	int32_t compare,
	int32_t depthWrite,
	int32_t stencil,
	uint32_t readMask,
	uint32_t writeMask,
	int32_t frontFail,
	int32_t frontDepthFail,
	int32_t frontPass,
	int32_t frontCompare,
	int32_t backFail,
	int32_t backDepthFail,
	int32_t backPass,
	int32_t backCompare) {
	MTLDepthStencilDescriptor *desc = [[MTLDepthStencilDescriptor alloc] init];
	desc.depthCompareFunction = (MTLCompareFunction)compare;
	desc.depthWriteEnabled = depthWrite ? YES : NO;
	if (stencil) {
		MTLStencilDescriptor *front = stencilFace(frontFail, frontDepthFail, frontPass, frontCompare, readMask, writeMask);
		MTLStencilDescriptor *back = stencilFace(backFail, backDepthFail, backPass, backCompare, readMask, writeMask);
		desc.frontFaceStencil = front;
		desc.backFaceStencil = back;
		[front release];
		[back release];
	}
	id<MTLDepthStencilState> state = [(id<MTLDevice>)device newDepthStencilStateWithDescriptor:desc];
	[desc release];
	return (MtlDepthState)state;
}

void mtlReleaseDepthState(MtlDepthState state) { [(id<MTLDepthStencilState>)state release]; }

void mtlPassReset(void) {
	[s_pass release];
	s_pass = [[MTLRenderPassDescriptor alloc] init];
}

void mtlPassColor(
	int32_t index,
	MtlTexture texture,
	int32_t level,
	int32_t slice,
	int32_t depthPlane,
	MtlTexture resolve,
	int32_t resolveLevel,
	int32_t resolveSlice,
	int32_t loadAction,
	int32_t storeAction,
	double r,
	double g,
	double b,
	double a) {
	MTLRenderPassColorAttachmentDescriptor *color = s_pass.colorAttachments[(NSUInteger)index];
	color.texture = (id<MTLTexture>)texture;
	color.level = (NSUInteger)level;
	color.slice = (NSUInteger)slice;
	color.depthPlane = (NSUInteger)depthPlane;
	color.resolveTexture = (id<MTLTexture>)resolve;
	color.resolveLevel = (NSUInteger)resolveLevel;
	color.resolveSlice = (NSUInteger)resolveSlice;
	color.loadAction = (MTLLoadAction)loadAction;
	color.storeAction = (MTLStoreAction)storeAction;
	color.clearColor = MTLClearColorMake(r, g, b, a);
}

void mtlPassDepth(MtlTexture texture, int32_t level, int32_t slice, int32_t loadAction, int32_t storeAction, double depth, int32_t stencil) {
	s_pass.depthAttachment.texture = (id<MTLTexture>)texture;
	s_pass.depthAttachment.level = (NSUInteger)level;
	s_pass.depthAttachment.slice = (NSUInteger)slice;
	s_pass.depthAttachment.loadAction = (MTLLoadAction)loadAction;
	s_pass.depthAttachment.storeAction = (MTLStoreAction)storeAction;
	s_pass.depthAttachment.clearDepth = depth;
	if (stencil) {
		s_pass.stencilAttachment.texture = (id<MTLTexture>)texture;
		s_pass.stencilAttachment.level = (NSUInteger)level;
		s_pass.stencilAttachment.slice = (NSUInteger)slice;
		s_pass.stencilAttachment.loadAction = (MTLLoadAction)loadAction;
		s_pass.stencilAttachment.storeAction = (MTLStoreAction)storeAction;
		s_pass.stencilAttachment.clearStencil = 0;
	}
}

MtlEncoder mtlBeginPass(MtlCommandBuffer commandBuffer) {
	@autoreleasepool {
		id<MTLRenderCommandEncoder> encoder =
			[[(id<MTLCommandBuffer>)commandBuffer renderCommandEncoderWithDescriptor:s_pass] retain];
		[s_pass release];
		s_pass = nil;
		return (MtlEncoder)encoder;
	}
}

void mtlEndPass(MtlEncoder encoder) {
	id<MTLCommandEncoder> e = (id<MTLCommandEncoder>)encoder;
	[e endEncoding];
	[e release];
}

void mtlSetDrawable(void *drawable) {
	[(id<CAMetalDrawable>)drawable retain];
	[s_drawable release];
	s_drawable = (id<CAMetalDrawable>)drawable;
}

void mtlPresentDrawable(MtlCommandBuffer commandBuffer) {
	if (s_drawable == nil) return;
	[(id<MTLCommandBuffer>)commandBuffer presentDrawable:s_drawable];
	[s_drawable release];
	s_drawable = nil;
}

void mtlSetViewport(MtlEncoder encoder, double x, double y, double width, double height, double near, double far) {
	MTLViewport viewport = { x, y, width, height, near, far };
	[(id<MTLRenderCommandEncoder>)encoder setViewport:viewport];
}

void mtlSetBlendColor(MtlEncoder encoder, double r, double g, double b, double a) {
	[(id<MTLRenderCommandEncoder>)encoder setBlendColorRed:(float)r green:(float)g blue:(float)b alpha:(float)a];
}

void mtlSetScissorRect(MtlEncoder encoder, int32_t x, int32_t y, int32_t width, int32_t height) {
	MTLScissorRect rect = { (NSUInteger)x, (NSUInteger)y, (NSUInteger)width, (NSUInteger)height };
	[(id<MTLRenderCommandEncoder>)encoder setScissorRect:rect];
}

void mtlSetPipeline(
	MtlEncoder encoder,
	MtlPipeline pipeline,
	MtlDepthState depth,
	int32_t cullMode,
	int32_t winding,
	float depthBias,
	float depthBiasSlope,
	float depthBiasClamp) {
	id<MTLRenderCommandEncoder> e = (id<MTLRenderCommandEncoder>)encoder;
	[e setCullMode:(MTLCullMode)cullMode];
	[e setFrontFacingWinding:(MTLWinding)winding];
	[e setDepthBias:depthBias slopeScale:depthBiasSlope clamp:depthBiasClamp];
	[e setRenderPipelineState:(id<MTLRenderPipelineState>)pipeline];
	[e setDepthStencilState:(id<MTLDepthStencilState>)depth];
}

void mtlSetStencilReference(MtlEncoder encoder, uint32_t reference) {
	[(id<MTLRenderCommandEncoder>)encoder setStencilFrontReferenceValue:reference backReferenceValue:reference];
}

void mtlSetVertexBuffer(MtlEncoder encoder, MtlBuffer buffer, int64_t offset, int32_t index) {
	[(id<MTLRenderCommandEncoder>)encoder setVertexBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index];
}

void mtlSetFragmentBuffer(MtlEncoder encoder, MtlBuffer buffer, int64_t offset, int32_t index) {
	[(id<MTLRenderCommandEncoder>)encoder setFragmentBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index];
}

void mtlSetVertexBufferOffset(MtlEncoder encoder, int64_t offset, int32_t index) {
	[(id<MTLRenderCommandEncoder>)encoder setVertexBufferOffset:(NSUInteger)offset atIndex:(NSUInteger)index];
}

void mtlSetFragmentBufferOffset(MtlEncoder encoder, int64_t offset, int32_t index) {
	[(id<MTLRenderCommandEncoder>)encoder setFragmentBufferOffset:(NSUInteger)offset atIndex:(NSUInteger)index];
}

void mtlSetVertexTexture(MtlEncoder encoder, MtlTexture texture, int32_t index) {
	[(id<MTLRenderCommandEncoder>)encoder setVertexTexture:(id<MTLTexture>)texture atIndex:(NSUInteger)index];
}

void mtlSetFragmentTexture(MtlEncoder encoder, MtlTexture texture, int32_t index) {
	[(id<MTLRenderCommandEncoder>)encoder setFragmentTexture:(id<MTLTexture>)texture atIndex:(NSUInteger)index];
}

void mtlSetVertexSampler(MtlEncoder encoder, MtlSampler sampler, int32_t index) {
	[(id<MTLRenderCommandEncoder>)encoder setVertexSamplerState:(id<MTLSamplerState>)sampler atIndex:(NSUInteger)index];
}

void mtlSetFragmentSampler(MtlEncoder encoder, MtlSampler sampler, int32_t index) {
	[(id<MTLRenderCommandEncoder>)encoder setFragmentSamplerState:(id<MTLSamplerState>)sampler atIndex:(NSUInteger)index];
}

void mtlDraw(MtlEncoder encoder, int32_t primitive, int32_t vertexCount, int32_t instanceCount, int32_t firstVertex, int32_t firstInstance) {
	id<MTLRenderCommandEncoder> e = (id<MTLRenderCommandEncoder>)encoder;
	if (firstInstance == 0) {
		[e drawPrimitives:(MTLPrimitiveType)primitive
			vertexStart:(NSUInteger)firstVertex
			vertexCount:(NSUInteger)vertexCount
			instanceCount:(NSUInteger)instanceCount];
	} else {
		[e drawPrimitives:(MTLPrimitiveType)primitive
			vertexStart:(NSUInteger)firstVertex
			vertexCount:(NSUInteger)vertexCount
			instanceCount:(NSUInteger)instanceCount
			baseInstance:(NSUInteger)firstInstance];
	}
}

void mtlDrawIndexed(
	MtlEncoder encoder,
	int32_t primitive,
	MtlBuffer indexBuffer,
	int32_t indexType,
	int64_t indexOffset,
	int32_t indexCount,
	int32_t instanceCount,
	int32_t baseVertex,
	int32_t firstInstance) {
	id<MTLRenderCommandEncoder> e = (id<MTLRenderCommandEncoder>)encoder;
	if (baseVertex == 0 && firstInstance == 0) {
		[e drawIndexedPrimitives:(MTLPrimitiveType)primitive
			indexCount:(NSUInteger)indexCount
			indexType:(MTLIndexType)indexType
			indexBuffer:(id<MTLBuffer>)indexBuffer
			indexBufferOffset:(NSUInteger)indexOffset
			instanceCount:(NSUInteger)instanceCount];
	} else {
		[e drawIndexedPrimitives:(MTLPrimitiveType)primitive
			indexCount:(NSUInteger)indexCount
			indexType:(MTLIndexType)indexType
			indexBuffer:(id<MTLBuffer>)indexBuffer
			indexBufferOffset:(NSUInteger)indexOffset
			instanceCount:(NSUInteger)instanceCount
			baseVertex:baseVertex
			baseInstance:(NSUInteger)firstInstance];
	}
}

static NSString *labelString(const char *label) { return [NSString stringWithUTF8String:label]; }

void mtlSetLabel(void *object, const char *label) {
	if (label[0]) [(id)object setLabel:labelString(label)];
}

void mtlPushDebugGroup(MtlCommandBuffer commandBuffer, const char *label) { [(id<MTLCommandBuffer>)commandBuffer pushDebugGroup:labelString(label)]; }
void mtlPopDebugGroup(MtlCommandBuffer commandBuffer) { [(id<MTLCommandBuffer>)commandBuffer popDebugGroup]; }
void mtlEncoderPushDebugGroup(MtlEncoder encoder, const char *label) { [(id<MTLCommandEncoder>)encoder pushDebugGroup:labelString(label)]; }
void mtlEncoderPopDebugGroup(MtlEncoder encoder) { [(id<MTLCommandEncoder>)encoder popDebugGroup]; }
void mtlEncoderInsertSignpost(MtlEncoder encoder, const char *label) { [(id<MTLCommandEncoder>)encoder insertDebugSignpost:labelString(label)]; }

int64_t mtlMaxBufferLength(MtlDevice device) { return (int64_t)[(id<MTLDevice>)device maxBufferLength]; }

int32_t mtlMaxThreadsPerThreadgroup(MtlDevice device, int32_t axis) {
	MTLSize size = [(id<MTLDevice>)device maxThreadsPerThreadgroup];
	return (int32_t)(axis == 0 ? size.width : (axis == 1 ? size.height : size.depth));
}

int32_t mtlSupportsFloat32Filtering(MtlDevice device) {
#if TARGET_OS_OSX
	(void)device;
	return 1;
#else
	return [(id<MTLDevice>)device supports32BitFloatFiltering] ? 1 : 0;
#endif
}

int32_t mtlSupportsRg11b10Render(MtlDevice device) {
#if TARGET_OS_OSX
	(void)device;
	return 1;
#else
	return [(id<MTLDevice>)device supportsFamily:MTLGPUFamilyApple3] ? 1 : 0;
#endif
}

int32_t mtlSupportsTimestamps(MtlDevice device) {
	id<MTLDevice> d = (id<MTLDevice>)device;
	if (![d supportsCounterSampling:MTLCounterSamplingPointAtStageBoundary]) return 0;
	if ([[d name] hasPrefix:@"Intel"]) return 0;
	for (id<MTLCounterSet> set in [d counterSets]) {
		if ([[set name] isEqualToString:MTLCommonCounterSetTimestamp]) return 1;
	}
	return 0;
}

MtlComputePipeline mtlNewComputePipeline(MtlDevice device, MtlFunction compute, const char *label) {
	MTLComputePipelineDescriptor *desc = [[MTLComputePipelineDescriptor alloc] init];
	desc.computeFunction = (id<MTLFunction>)compute;
	if (label[0]) desc.label = labelString(label);
	NSError *error = nil;
	id<MTLComputePipelineState> state = [(id<MTLDevice>)device newComputePipelineStateWithDescriptor:desc
		options:MTLPipelineOptionNone
		reflection:nil
		error:&error];
	[desc release];
	if (state == nil) keepLog(error);
	return (MtlComputePipeline)state;
}

int32_t mtlComputeMaxThreads(MtlComputePipeline pipeline) {
	return (int32_t)[(id<MTLComputePipelineState>)pipeline maxTotalThreadsPerThreadgroup];
}

void mtlReleaseComputePipeline(MtlComputePipeline pipeline) { [(id<MTLComputePipelineState>)pipeline release]; }

MtlEncoder mtlBeginComputePass(MtlCommandBuffer commandBuffer, const char *label) {
	@autoreleasepool {
		id<MTLComputeCommandEncoder> encoder = [(id<MTLCommandBuffer>)commandBuffer computeCommandEncoder];
		if (encoder && label[0]) encoder.label = labelString(label);
		return (MtlEncoder)[encoder retain];
	}
}

void mtlComputeSetPipeline(MtlEncoder encoder, MtlComputePipeline pipeline) {
	[(id<MTLComputeCommandEncoder>)encoder setComputePipelineState:(id<MTLComputePipelineState>)pipeline];
}

void mtlComputeSetBuffer(MtlEncoder encoder, MtlBuffer buffer, int64_t offset, int32_t index) {
	[(id<MTLComputeCommandEncoder>)encoder setBuffer:(id<MTLBuffer>)buffer offset:(NSUInteger)offset atIndex:(NSUInteger)index];
}

void mtlComputeSetBufferOffset(MtlEncoder encoder, int64_t offset, int32_t index) {
	[(id<MTLComputeCommandEncoder>)encoder setBufferOffset:(NSUInteger)offset atIndex:(NSUInteger)index];
}

void mtlComputeSetTexture(MtlEncoder encoder, MtlTexture texture, int32_t index) {
	[(id<MTLComputeCommandEncoder>)encoder setTexture:(id<MTLTexture>)texture atIndex:(NSUInteger)index];
}

void mtlComputeSetSampler(MtlEncoder encoder, MtlSampler sampler, int32_t index) {
	[(id<MTLComputeCommandEncoder>)encoder setSamplerState:(id<MTLSamplerState>)sampler atIndex:(NSUInteger)index];
}

void mtlDispatch(MtlEncoder encoder, int32_t x, int32_t y, int32_t z, int32_t threadsX, int32_t threadsY, int32_t threadsZ) {
	[(id<MTLComputeCommandEncoder>)encoder dispatchThreadgroups:MTLSizeMake((NSUInteger)x, (NSUInteger)y, (NSUInteger)z)
		threadsPerThreadgroup:MTLSizeMake((NSUInteger)threadsX, (NSUInteger)threadsY, (NSUInteger)threadsZ)];
}

void mtlDispatchIndirect(MtlEncoder encoder, MtlBuffer arguments, int64_t offset, int32_t threadsX, int32_t threadsY, int32_t threadsZ) {
	[(id<MTLComputeCommandEncoder>)encoder dispatchThreadgroupsWithIndirectBuffer:(id<MTLBuffer>)arguments
		indirectBufferOffset:(NSUInteger)offset
		threadsPerThreadgroup:MTLSizeMake((NSUInteger)threadsX, (NSUInteger)threadsY, (NSUInteger)threadsZ)];
}

MtlSampleBuffer mtlNewSampleBuffer(MtlDevice device, int32_t count, const char *label) {
	@autoreleasepool {
		id<MTLDevice> d = (id<MTLDevice>)device;
		id<MTLCounterSet> timestamp = nil;
		for (id<MTLCounterSet> set in [d counterSets]) {
			if ([[set name] isEqualToString:MTLCommonCounterSetTimestamp]) timestamp = set;
		}
		if (timestamp == nil) return NULL;
		MTLCounterSampleBufferDescriptor *desc = [[MTLCounterSampleBufferDescriptor alloc] init];
		desc.counterSet = timestamp;
		desc.storageMode = MTLStorageModeShared;
		desc.sampleCount = (NSUInteger)count;
		if (label[0]) desc.label = labelString(label);
		NSError *error = nil;
		id<MTLCounterSampleBuffer> samples = [d newCounterSampleBufferWithDescriptor:desc error:&error];
		[desc release];
		if (samples == nil) keepLog(error);
		return (MtlSampleBuffer)samples;
	}
}

void mtlReleaseSampleBuffer(MtlSampleBuffer samples) { [(id<MTLCounterSampleBuffer>)samples release]; }

void mtlResolveCounters(MtlCommandBuffer commandBuffer, MtlSampleBuffer samples, int32_t first, int32_t count, MtlBuffer destination, int64_t destinationOffset) {
	@autoreleasepool {
		id<MTLBlitCommandEncoder> blit = [(id<MTLCommandBuffer>)commandBuffer blitCommandEncoder];
		[blit resolveCounters:(id<MTLCounterSampleBuffer>)samples
			inRange:NSMakeRange((NSUInteger)first, (NSUInteger)count)
			destinationBuffer:(id<MTLBuffer>)destination
			destinationOffset:(NSUInteger)destinationOffset];
		[blit endEncoding];
	}
}

void mtlPassSamples(MtlSampleBuffer samples, int32_t startIndex, int32_t endIndex) {
	MTLRenderPassSampleBufferAttachmentDescriptor *attachment = s_pass.sampleBufferAttachments[0];
	attachment.sampleBuffer = (id<MTLCounterSampleBuffer>)samples;
	attachment.startOfVertexSampleIndex = startIndex < 0 ? MTLCounterDontSample : (NSUInteger)startIndex;
	attachment.endOfVertexSampleIndex = MTLCounterDontSample;
	attachment.startOfFragmentSampleIndex = MTLCounterDontSample;
	attachment.endOfFragmentSampleIndex = endIndex < 0 ? MTLCounterDontSample : (NSUInteger)endIndex;
}

void mtlPassVisibility(MtlBuffer buffer) { s_pass.visibilityResultBuffer = (id<MTLBuffer>)buffer; }

void mtlSetVisibility(MtlEncoder encoder, int32_t enabled, int64_t offset) {
	[(id<MTLRenderCommandEncoder>)encoder setVisibilityResultMode:enabled ? MTLVisibilityResultModeBoolean : MTLVisibilityResultModeDisabled offset:(NSUInteger)offset];
}

typedef struct { const char *name; int32_t value; } DriverConstant;

#define DRIVER(name) { #name, (int32_t)(name) }

static const DriverConstant driverConstants[] = {
	DRIVER(MTLPixelFormatInvalid),
	DRIVER(MTLPixelFormatR8Unorm),
	DRIVER(MTLPixelFormatRG8Unorm),
	DRIVER(MTLPixelFormatRGBA8Unorm),
	DRIVER(MTLPixelFormatRGBA8Unorm_sRGB),
	DRIVER(MTLPixelFormatBGRA8Unorm),
	DRIVER(MTLPixelFormatBGRA8Unorm_sRGB),
	DRIVER(MTLPixelFormatRGBA8Uint),
	DRIVER(MTLPixelFormatRGBA8Sint),
	DRIVER(MTLPixelFormatR16Float),
	DRIVER(MTLPixelFormatRG16Float),
	DRIVER(MTLPixelFormatRGBA16Float),
	DRIVER(MTLPixelFormatRGBA16Uint),
	DRIVER(MTLPixelFormatR32Float),
	DRIVER(MTLPixelFormatRG32Float),
	DRIVER(MTLPixelFormatRGBA32Float),
	DRIVER(MTLPixelFormatRGBA32Uint),
	DRIVER(MTLPixelFormatR32Uint),
	DRIVER(MTLPixelFormatRGB10A2Unorm),
	DRIVER(MTLPixelFormatRG11B10Float),
	DRIVER(MTLPixelFormatDepth16Unorm),
	DRIVER(MTLPixelFormatDepth32Float),
	DRIVER(MTLPixelFormatDepth32Float_Stencil8),
	DRIVER(MTLVertexFormatUChar2),
	DRIVER(MTLVertexFormatUChar4),
	DRIVER(MTLVertexFormatChar2),
	DRIVER(MTLVertexFormatChar4),
	DRIVER(MTLVertexFormatUChar2Normalized),
	DRIVER(MTLVertexFormatUChar4Normalized),
	DRIVER(MTLVertexFormatChar2Normalized),
	DRIVER(MTLVertexFormatChar4Normalized),
	DRIVER(MTLVertexFormatUShort2),
	DRIVER(MTLVertexFormatUShort4),
	DRIVER(MTLVertexFormatShort2),
	DRIVER(MTLVertexFormatShort4),
	DRIVER(MTLVertexFormatUShort2Normalized),
	DRIVER(MTLVertexFormatUShort4Normalized),
	DRIVER(MTLVertexFormatShort2Normalized),
	DRIVER(MTLVertexFormatShort4Normalized),
	DRIVER(MTLVertexFormatHalf2),
	DRIVER(MTLVertexFormatHalf4),
	DRIVER(MTLVertexFormatFloat),
	DRIVER(MTLVertexFormatFloat2),
	DRIVER(MTLVertexFormatFloat3),
	DRIVER(MTLVertexFormatFloat4),
	DRIVER(MTLVertexFormatInt),
	DRIVER(MTLVertexFormatInt2),
	DRIVER(MTLVertexFormatInt3),
	DRIVER(MTLVertexFormatInt4),
	DRIVER(MTLVertexFormatUInt),
	DRIVER(MTLVertexFormatUInt2),
	DRIVER(MTLVertexFormatUInt3),
	DRIVER(MTLVertexFormatUInt4),
	DRIVER(MTLBlendFactorZero),
	DRIVER(MTLBlendFactorOne),
	DRIVER(MTLBlendFactorSourceColor),
	DRIVER(MTLBlendFactorOneMinusSourceColor),
	DRIVER(MTLBlendFactorSourceAlpha),
	DRIVER(MTLBlendFactorOneMinusSourceAlpha),
	DRIVER(MTLBlendFactorDestinationColor),
	DRIVER(MTLBlendFactorOneMinusDestinationColor),
	DRIVER(MTLBlendFactorDestinationAlpha),
	DRIVER(MTLBlendFactorOneMinusDestinationAlpha),
	DRIVER(MTLBlendFactorSourceAlphaSaturated),
	DRIVER(MTLBlendFactorBlendColor),
	DRIVER(MTLBlendFactorOneMinusBlendColor),
	DRIVER(MTLBlendOperationAdd),
	DRIVER(MTLBlendOperationSubtract),
	DRIVER(MTLBlendOperationReverseSubtract),
	DRIVER(MTLBlendOperationMin),
	DRIVER(MTLBlendOperationMax),
	DRIVER(MTLStencilOperationKeep),
	DRIVER(MTLStencilOperationZero),
	DRIVER(MTLStencilOperationReplace),
	DRIVER(MTLStencilOperationIncrementClamp),
	DRIVER(MTLStencilOperationDecrementClamp),
	DRIVER(MTLStencilOperationInvert),
	DRIVER(MTLStencilOperationIncrementWrap),
	DRIVER(MTLStencilOperationDecrementWrap),
	DRIVER(MTLCompareFunctionNever),
	DRIVER(MTLCompareFunctionNever),
	DRIVER(MTLCompareFunctionLess),
	DRIVER(MTLCompareFunctionEqual),
	DRIVER(MTLCompareFunctionLessEqual),
	DRIVER(MTLCompareFunctionGreater),
	DRIVER(MTLCompareFunctionNotEqual),
	DRIVER(MTLCompareFunctionGreaterEqual),
	DRIVER(MTLCompareFunctionAlways),
	DRIVER(MTLCullModeNone),
	DRIVER(MTLCullModeFront),
	DRIVER(MTLCullModeBack),
	DRIVER(MTLWindingClockwise),
	DRIVER(MTLWindingCounterClockwise),
	DRIVER(MTLColorWriteMaskRed),
	DRIVER(MTLColorWriteMaskGreen),
	DRIVER(MTLColorWriteMaskBlue),
	DRIVER(MTLColorWriteMaskAlpha),
	DRIVER(MTLSamplerMinMagFilterNearest),
	DRIVER(MTLSamplerMinMagFilterLinear),
	DRIVER(MTLSamplerMipFilterNearest),
	DRIVER(MTLSamplerMipFilterLinear),
	DRIVER(MTLSamplerAddressModeClampToEdge),
	DRIVER(MTLSamplerAddressModeRepeat),
	DRIVER(MTLSamplerAddressModeMirrorRepeat),
	DRIVER(MTLPrimitiveTypePoint),
	DRIVER(MTLPrimitiveTypeLine),
	DRIVER(MTLPrimitiveTypeLineStrip),
	DRIVER(MTLPrimitiveTypeTriangle),
	DRIVER(MTLPrimitiveTypeTriangleStrip),
	DRIVER(MTLIndexTypeUInt16),
	DRIVER(MTLIndexTypeUInt32),
	DRIVER(MTLTextureType2D),
	DRIVER(MTLTextureType2DArray),
	DRIVER(MTLTextureType2DMultisample),
	DRIVER(MTLTextureTypeCube),
	DRIVER(MTLTextureTypeCubeArray),
	DRIVER(MTLTextureType3D),
	DRIVER(MTLLoadActionLoad),
	DRIVER(MTLLoadActionClear),
	DRIVER(MTLStoreActionDontCare),
	DRIVER(MTLStoreActionStore),
	DRIVER(MTLStoreActionMultisampleResolve),
	DRIVER(MTLStoreActionStoreAndMultisampleResolve),
};

static char s_constantsDisagreement[256];

const char *mtlConstantsDisagreement(const int32_t *values, int32_t count) {
	int32_t known = (int32_t)(sizeof driverConstants / sizeof driverConstants[0]);
	s_constantsDisagreement[0] = 0;
	if (count != known) {
		snprintf(s_constantsDisagreement, sizeof s_constantsDisagreement, "backend.ms lists %d constants and metal.m checks %d", (int)count, (int)known);
		return s_constantsDisagreement;
	}
	for (int32_t i = 0; i < known; i++) {
		if (values[i] == driverConstants[i].value) continue;
		snprintf(s_constantsDisagreement, sizeof s_constantsDisagreement, "entry %d: %s is %d in Metal and %d in backend.ms",
			(int)i, driverConstants[i].name, (int)driverConstants[i].value, (int)values[i]);
		break;
	}
	return s_constantsDisagreement;
}
