#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
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
	[cb release];
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
	int32_t pixelFormat,
	int32_t sampleCount,
	int32_t renderTarget,
	int32_t shared) {
	MTLTextureDescriptor *desc = [[MTLTextureDescriptor alloc] init];
	desc.textureType = sampleCount > 1 ? MTLTextureType2DMultisample : MTLTextureType2D;
	desc.pixelFormat = (MTLPixelFormat)pixelFormat;
	desc.width = (NSUInteger)width;
	desc.height = (NSUInteger)height;
	desc.sampleCount = (NSUInteger)sampleCount;
	desc.usage = MTLTextureUsageShaderRead | (renderTarget ? MTLTextureUsageRenderTarget : 0);
	desc.resourceOptions = renderTarget
		? MTLResourceStorageModePrivate
		: (storageOptions(shared) | MTLResourceCPUCacheModeWriteCombined);
	id<MTLTexture> texture = [(id<MTLDevice>)device newTextureWithDescriptor:desc];
	[desc release];
	return (MtlTexture)texture;
}

void mtlReleaseTexture(MtlTexture texture) { [(id<MTLTexture>)texture release]; }

void mtlWriteTexture(MtlTexture texture, void *data, int64_t offset, int32_t bytesPerRow, int32_t width, int32_t height) {
	[(id<MTLTexture>)texture replaceRegion:MTLRegionMake2D(0, 0, (NSUInteger)width, (NSUInteger)height)
		mipmapLevel:0
		slice:0
		withBytes:(const uint8_t *)data + offset
		bytesPerRow:(NSUInteger)bytesPerRow
		bytesPerImage:0];
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
	int32_t compare) {
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
	MtlTexture resolve,
	int32_t loadAction,
	int32_t storeAction,
	double r,
	double g,
	double b,
	double a) {
	MTLRenderPassColorAttachmentDescriptor *color = s_pass.colorAttachments[(NSUInteger)index];
	color.texture = (id<MTLTexture>)texture;
	color.resolveTexture = (id<MTLTexture>)resolve;
	color.loadAction = (MTLLoadAction)loadAction;
	color.storeAction = (MTLStoreAction)storeAction;
	color.clearColor = MTLClearColorMake(r, g, b, a);
}

void mtlPassDepth(MtlTexture texture, int32_t loadAction, int32_t storeAction, double depth, int32_t stencil) {
	s_pass.depthAttachment.texture = (id<MTLTexture>)texture;
	s_pass.depthAttachment.loadAction = (MTLLoadAction)loadAction;
	s_pass.depthAttachment.storeAction = (MTLStoreAction)storeAction;
	s_pass.depthAttachment.clearDepth = depth;
	if (stencil) {
		s_pass.stencilAttachment.texture = (id<MTLTexture>)texture;
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
	id<MTLRenderCommandEncoder> e = (id<MTLRenderCommandEncoder>)encoder;
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
