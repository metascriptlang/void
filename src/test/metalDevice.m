#import <Metal/Metal.h>
#include <string.h>
#include "metalDevice.h"

void *metalSystemDevice(void) {
	static id<MTLDevice> device;
	if (device == nil) device = MTLCreateSystemDefaultDevice();
	return device;
}

int32_t metalReadback(void *queue, void *texture, void *pixels, int32_t width, int32_t height) {
	@autoreleasepool {
		id<MTLCommandQueue> q = (id<MTLCommandQueue>)queue;
		NSUInteger rowBytes = (NSUInteger)width * 4;
		id<MTLBuffer> staging = [q.device newBufferWithLength:rowBytes * (NSUInteger)height options:MTLResourceStorageModeShared];
		if (staging == nil) return 0;
		id<MTLCommandBuffer> commandBuffer = [q commandBuffer];
		id<MTLBlitCommandEncoder> blit = [commandBuffer blitCommandEncoder];
		[blit copyFromTexture:(id<MTLTexture>)texture
			sourceSlice:0
			sourceLevel:0
			sourceOrigin:MTLOriginMake(0, 0, 0)
			sourceSize:MTLSizeMake((NSUInteger)width, (NSUInteger)height, 1)
			toBuffer:staging
			destinationOffset:0
			destinationBytesPerRow:rowBytes
			destinationBytesPerImage:rowBytes * (NSUInteger)height];
		[blit endEncoding];
		[commandBuffer commit];
		[commandBuffer waitUntilCompleted];
		int32_t ok = commandBuffer.status == MTLCommandBufferStatusCompleted ? 1 : 0;
		if (ok) memcpy(pixels, [staging contents], rowBytes * (NSUInteger)height);
		[staging release];
		return ok;
	}
}
