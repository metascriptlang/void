import {
	GPUAdapterInfo,
	GPUCanvasConfiguration,
	GPULiveCounts,
	GPUTextureFormat,
	GPUBindGroup,
	GPUBindGroupDescriptor,
	GPUBindGroupLayout,
	GPUBuffer,
	GPUBufferDescriptor,
	GPUCommandBuffer,
	GPUColor,
	GPUCommandEncoder,
	GPUComputePassDescriptor,
	GPUComputePassEncoder,
	GPUComputePipeline,
	GPUComputePipelineDescriptor,
	GPUDevice,
	GPUFeatureName,
	GPUExtent3D,
	GPUIndexFormat,
	GPUQuerySet,
	GPUQuerySetDescriptor,
	GPUQueue,
	GPURenderPassDescriptor,
	GPURenderPassEncoder,
	GPURenderPipeline,
	GPURenderPipelineDescriptor,
	GPUSampler,
	GPUSamplerDescriptor,
	GPUShaderModule,
	GPUShaderModuleDescriptor,
	GPUSupportedFeatures,
	GPUSupportedLimits,
	GPUTexelCopyBufferInfo,
	GPUTexelCopyBufferLayout,
	GPUTexelCopyTextureInfo,
	GPUTexture,
	GPUTextureDescriptor,
	GPUTextureView,
	GPUTextureViewDescriptor,
	featureBit,
} from "./types.ms";
import {
	PASS_COMPUTE,
	PASS_RENDER,
	attachOcclusionSet,
	checkedBeginOcclusion,
	checkedBeginPass,
	checkedBindGroupIndex,
	checkedBuffer,
	checkedCreateEncoder,
	checkedDrawState,
	checkedEndOcclusion,
	checkedEndPass,
	checkedFinish,
	checkedInPass,
	checkedMarker,
	checkedOutsidePass,
	checkedPipelineSet,
	checkedPopGroup,
	checkedPrimitive,
	checkedPushGroup,
	checkedShaderModule,
	checkedShutdown,
	checkedTexture,
	markIndexSet,
	markPipelineSet,
	resetEncoder,
} from "./validate.ms";

when (voidDummy) {
	import * as backend from "./dummy/backend.ms";
} else when (webgpu) {
	import * as backend from "./wgpu/backend.ms";
} else when (windows && !voidGlCore) {
	import * as backend from "./d3d11/backend.ms";
} else when (voidGlCore || webgl2 || android || linux) {
	import * as backend from "./gl/backend.ms";
} else when (macos || ios) {
	import * as backend from "./metal/backend.ms";
}

export type GPUNativeEnvironment = backend.NativeEnvironment;
export type GPUNativeSwapchain = backend.NativeSwapchain;

export function requestDevice(environment: GPUNativeEnvironment): GPUDevice {
	resetEncoder();
	return backend.setup(environment);
}

export function destroy(this self: GPUDevice): void {
	checkedShutdown();
	backend.shutdown();
	resetEncoder();
}

export function getAdapterInfo(this self: GPUDevice): GPUAdapterInfo { return backend.adapterInfo(); }

@inline export function createBuffer(this self: GPUDevice, descriptor: GPUBufferDescriptor): GPUBuffer {
	checkedBuffer(descriptor.size, descriptor.usage);
	return backend.createBuffer(descriptor);
}

@inline export function createTexture(this self: GPUDevice, descriptor: GPUTextureDescriptor): GPUTexture {
	checkedTexture(descriptor, backend.limits());
	return backend.createTexture(descriptor);
}

@inline export function createSampler(this self: GPUDevice, descriptor: GPUSamplerDescriptor): GPUSampler {
	return backend.createSampler(descriptor);
}

@inline export function createShaderModule(this self: GPUDevice, descriptor: GPUShaderModuleDescriptor): GPUShaderModule {
	checkedShaderModule(descriptor, backend.limits());
	return backend.createShaderModule(descriptor);
}

@inline export function createRenderPipeline(this self: GPUDevice, descriptor: GPURenderPipelineDescriptor): GPURenderPipeline {
	checkedPrimitive(descriptor.primitive);
	return backend.createRenderPipeline(descriptor);
}

@inline export function createComputePipeline(this self: GPUDevice, descriptor: GPUComputePipelineDescriptor): GPUComputePipeline {
	return backend.createComputePipeline(descriptor);
}

@inline export function createBindGroup(this self: GPUDevice, descriptor: GPUBindGroupDescriptor): GPUBindGroup {
	return backend.createBindGroup(descriptor);
}

@inline export function createCommandEncoder(this self: GPUDevice): GPUCommandEncoder {
	checkedCreateEncoder();
	return backend.createCommandEncoder();
}

@inline export function createQuerySet(this self: GPUDevice, descriptor: GPUQuerySetDescriptor): GPUQuerySet {
	return backend.createQuerySet(descriptor);
}

@inline export function limits(this self: GPUDevice): GPUSupportedLimits { return backend.limits(); }
@inline export function features(this self: GPUDevice): GPUSupportedFeatures { return backend.features(); }
@inline export function has(this self: GPUSupportedFeatures, name: GPUFeatureName): boolean { return (self.bits & featureBit(name)) != 0; }

@inline export function createView(this self: GPUTexture, descriptor: GPUTextureViewDescriptor): GPUTextureView {
	return backend.createView(self, descriptor);
}

@inline export function getBindGroupLayout(this self: GPURenderPipeline, index: int32): GPUBindGroupLayout {
	return backend.getBindGroupLayout(self, index);
}

@inline export function getBindGroupLayout(this self: GPUComputePipeline, index: int32): GPUBindGroupLayout {
	return backend.getBindGroupLayout({ id: self.id }, index);
}

@inline export function destroy(this self: GPUComputePipeline): void { backend.destroyRenderPipeline({ id: self.id }); }
@inline export function destroy(this self: GPUQuerySet): void { backend.destroyQuerySet(self); }
@inline export function destroy(this self: GPUBuffer): void { backend.destroyBuffer(self); }
@inline export function destroy(this self: GPUTexture): void { backend.destroyTexture(self); }
@inline export function destroy(this self: GPUTextureView): void { backend.destroyView(self); }
@inline export function destroy(this self: GPUSampler): void { backend.destroySampler(self); }
@inline export function destroy(this self: GPUShaderModule): void { backend.destroyShaderModule(self); }
@inline export function destroy(this self: GPURenderPipeline): void { backend.destroyRenderPipeline(self); }
@inline export function destroy(this self: GPUBindGroup): void { backend.destroyBindGroup(self); }

@inline export function size(this self: GPUBuffer): int64 { return backend.bufferSize(self); }
@inline export function width(this self: GPUTexture): int32 { return backend.textureWidth(self); }
@inline export function height(this self: GPUTexture): int32 { return backend.textureHeight(self); }
@inline export function usage(this self: GPUTexture): int32 { return backend.textureUsage(self); }
@inline export function format(this self: GPUTexture): GPUTextureFormat { return backend.textureFormat(self); }
@inline export function texture(this self: GPUTextureView): GPUTexture { return backend.viewTexture(self); }

@inline export function writeBuffer<T>(this self: GPUQueue, buffer: GPUBuffer, bufferOffset: int64, data: Readonly<Span<T>>): void {
	backend.writeBuffer(buffer, bufferOffset, data);
}

@inline export function writeTexture<T>(
	this self: GPUQueue,
	destination: GPUTexelCopyTextureInfo,
	data: Readonly<Span<T>>,
	dataLayout: GPUTexelCopyBufferLayout,
	size: GPUExtent3D,
): void {
	backend.writeTexture(destination, data, dataLayout, size);
}

@inline export function submit(this self: GPUQueue, commandBuffer: GPUCommandBuffer): void {
	backend.submit(commandBuffer);
}

@inline export function beginRenderPass(this self: GPUCommandEncoder, descriptor: GPURenderPassDescriptor): GPURenderPassEncoder {
	checkedBeginPass(PASS_RENDER);
	attachOcclusionSet(descriptor.occlusionQuerySet.id);
	return backend.beginRenderPass(self, descriptor);
}

@inline export function beginComputePass(this self: GPUCommandEncoder, descriptor: GPUComputePassDescriptor): GPUComputePassEncoder {
	checkedBeginPass(PASS_COMPUTE);
	return backend.beginComputePass(self, descriptor);
}

@inline export function setPipeline(this self: GPUComputePassEncoder, pipeline: GPUComputePipeline): void {
	checkedInPass(PASS_COMPUTE, "setPipeline");
	markPipelineSet();
	backend.setComputePipeline(pipeline);
}

@inline export function setBindGroup(this self: GPUComputePassEncoder, index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void {
	checkedInPass(PASS_COMPUTE, "setBindGroup");
	checkedBindGroupIndex(index);
	backend.setComputeBindGroup(index, bindGroup, dynamicOffsets);
}

@inline export function dispatchWorkgroups(this self: GPUComputePassEncoder, x: int32, y: int32, z: int32): void {
	checkedInPass(PASS_COMPUTE, "dispatchWorkgroups");
	checkedPipelineSet("dispatchWorkgroups");
	backend.dispatchWorkgroups(x, y, z);
}

@inline export function dispatchWorkgroupsIndirect(this self: GPUComputePassEncoder, buffer: GPUBuffer, offset: int64): void {
	checkedInPass(PASS_COMPUTE, "dispatchWorkgroupsIndirect");
	checkedPipelineSet("dispatchWorkgroupsIndirect");
	backend.dispatchWorkgroupsIndirect(buffer, offset);
}

@inline export function end(this self: GPUComputePassEncoder): void {
	checkedEndPass(PASS_COMPUTE);
	backend.endComputePass();
}

@inline export function copyBufferToBuffer(
	this self: GPUCommandEncoder,
	source: GPUBuffer,
	sourceOffset: int64,
	destination: GPUBuffer,
	destinationOffset: int64,
	size: int64,
): void {
	checkedOutsidePass("copyBufferToBuffer");
	backend.copyBufferToBuffer(source, sourceOffset, destination, destinationOffset, size);
}

@inline export function copyBufferToTexture(
	this self: GPUCommandEncoder,
	source: GPUTexelCopyBufferInfo,
	destination: GPUTexelCopyTextureInfo,
	copySize: GPUExtent3D,
): void {
	checkedOutsidePass("copyBufferToTexture");
	backend.copyBufferToTexture(source, destination, copySize);
}

@inline export function copyTextureToBuffer(
	this self: GPUCommandEncoder,
	source: GPUTexelCopyTextureInfo,
	destination: GPUTexelCopyBufferInfo,
	copySize: GPUExtent3D,
): void {
	checkedOutsidePass("copyTextureToBuffer");
	backend.copyTextureToBuffer(source, destination, copySize);
}

@inline export function copyTextureToTexture(
	this self: GPUCommandEncoder,
	source: GPUTexelCopyTextureInfo,
	destination: GPUTexelCopyTextureInfo,
	copySize: GPUExtent3D,
): void {
	checkedOutsidePass("copyTextureToTexture");
	backend.copyTextureToTexture(source, destination, copySize);
}

// Writes uint64 nanoseconds (timestamp) or samples passed (occlusion) per query; blocks on native until the GPU has them.
@inline export function resolveQuerySet(
	this self: GPUCommandEncoder,
	querySet: GPUQuerySet,
	firstQuery: int32,
	queryCount: int32,
	destination: GPUBuffer,
	destinationOffset: int64,
): void {
	checkedOutsidePass("resolveQuerySet");
	backend.resolveQuerySet(querySet, firstQuery, queryCount, destination, destinationOffset);
}

@inline export function pushDebugGroup(this self: GPUCommandEncoder, label: string): void {
	checkedPushGroup();
	backend.pushDebugGroup(label);
}
@inline export function popDebugGroup(this self: GPUCommandEncoder): void {
	checkedPopGroup();
	backend.popDebugGroup();
}
@inline export function insertDebugMarker(this self: GPUCommandEncoder, label: string): void {
	checkedMarker();
	backend.insertDebugMarker(label);
}
@inline export function pushDebugGroup(this self: GPURenderPassEncoder, label: string): void {
	checkedPushGroup();
	backend.pushDebugGroup(label);
}
@inline export function popDebugGroup(this self: GPURenderPassEncoder): void {
	checkedPopGroup();
	backend.popDebugGroup();
}
@inline export function insertDebugMarker(this self: GPURenderPassEncoder, label: string): void {
	checkedMarker();
	backend.insertDebugMarker(label);
}
@inline export function pushDebugGroup(this self: GPUComputePassEncoder, label: string): void {
	checkedPushGroup();
	backend.pushDebugGroup(label);
}
@inline export function popDebugGroup(this self: GPUComputePassEncoder): void {
	checkedPopGroup();
	backend.popDebugGroup();
}
@inline export function insertDebugMarker(this self: GPUComputePassEncoder, label: string): void {
	checkedMarker();
	backend.insertDebugMarker(label);
}

@inline export function beginOcclusionQuery(this self: GPURenderPassEncoder, queryIndex: int32): void {
	checkedInPass(PASS_RENDER, "beginOcclusionQuery");
	checkedBeginOcclusion(queryIndex);
	backend.beginOcclusionQuery(queryIndex);
}
@inline export function endOcclusionQuery(this self: GPURenderPassEncoder): void {
	checkedEndOcclusion();
	backend.endOcclusionQuery();
}

// mapAsync blocks on native: the buffer is readable or writable on return. `size` 0 maps to the end.
@inline export function mapAsync(this self: GPUBuffer, mode: int32, offset: int64, size: int64): void {
	backend.mapAsync(self, mode, offset, size);
}

// A copy of the mapped bytes, not WebGPU's live ArrayBuffer view; a MAP_WRITE buffer takes writeMappedRange instead.
@inline export function getMappedRange(this self: GPUBuffer, offset: int64, size: int64): Vec<uint8> {
	return backend.getMappedRange(self, offset, size);
}

@inline export function writeMappedRange<T>(this self: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	backend.writeMappedRange(self, offset, data);
}

@inline export function unmap(this self: GPUBuffer): void { backend.unmap(self); }

@inline export function finish(this self: GPUCommandEncoder): GPUCommandBuffer {
	checkedFinish();
	return backend.finish(self);
}

@inline export function setPipeline(this self: GPURenderPassEncoder, pipeline: GPURenderPipeline): void {
	checkedInPass(PASS_RENDER, "setPipeline");
	markPipelineSet();
	backend.setPipeline(pipeline);
}

@inline export function setVertexBuffer(this self: GPURenderPassEncoder, slot: int32, buffer: GPUBuffer, offset: int64): void {
	checkedInPass(PASS_RENDER, "setVertexBuffer");
	backend.setVertexBuffer(slot, buffer, offset);
}

@inline export function setIndexBuffer(this self: GPURenderPassEncoder, buffer: GPUBuffer, indexFormat: GPUIndexFormat, offset: int64): void {
	checkedInPass(PASS_RENDER, "setIndexBuffer");
	markIndexSet();
	backend.setIndexBuffer(buffer, indexFormat, offset);
}

@inline export function setBindGroup(this self: GPURenderPassEncoder, index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void {
	checkedInPass(PASS_RENDER, "setBindGroup");
	checkedBindGroupIndex(index);
	backend.setBindGroup(index, bindGroup, dynamicOffsets);
}

@inline export function setScissorRect(this self: GPURenderPassEncoder, x: int32, y: int32, width: int32, height: int32): void {
	checkedInPass(PASS_RENDER, "setScissorRect");
	backend.setScissorRect(x, y, width, height);
}

@inline export function setViewport(
	this self: GPURenderPassEncoder,
	x: float32,
	y: float32,
	width: float32,
	height: float32,
	minDepth: float32,
	maxDepth: float32,
): void {
	checkedInPass(PASS_RENDER, "setViewport");
	backend.setViewport(x, y, width, height, minDepth, maxDepth);
}

@inline export function setBlendConstant(this self: GPURenderPassEncoder, color: GPUColor): void {
	checkedInPass(PASS_RENDER, "setBlendConstant");
	backend.setBlendConstant(color);
}

@inline export function setStencilReference(this self: GPURenderPassEncoder, reference: uint32): void {
	checkedInPass(PASS_RENDER, "setStencilReference");
	backend.setStencilReference(reference);
}

@inline export function draw(this self: GPURenderPassEncoder, vertexCount: int32, instanceCount: int32, firstVertex: int32, firstInstance: int32): void {
	checkedInPass(PASS_RENDER, "draw");
	checkedDrawState("draw", false);
	backend.draw(vertexCount, instanceCount, firstVertex, firstInstance);
}

@inline export function drawIndexed(
	this self: GPURenderPassEncoder,
	indexCount: int32,
	instanceCount: int32,
	firstIndex: int32,
	baseVertex: int32,
	firstInstance: int32,
): void {
	checkedInPass(PASS_RENDER, "drawIndexed");
	checkedDrawState("drawIndexed", true);
	backend.drawIndexed(indexCount, instanceCount, firstIndex, baseVertex, firstInstance);
}

@inline export function end(this self: GPURenderPassEncoder): void {
	checkedEndPass(PASS_RENDER);
	backend.endPass();
}

export function getCurrentTexture(swapchain: GPUNativeSwapchain): GPUTexture {
	return backend.swapchainTexture(swapchain);
}

// The depth attachment the window adds to the canvas; valid after getCurrentTexture this frame.
export function getCurrentDepthTexture(): GPUTexture { return backend.swapchainDepthTexture(); }

export function getCanvasConfiguration(this self: GPUDevice): GPUCanvasConfiguration {
	return backend.canvasConfiguration();
}

export function isRenderable(this self: GPUDevice, format: GPUTextureFormat): boolean {
	return backend.formatRenderable(format);
}

export function frameIndex(this self: GPUDevice): uint32 { return backend.frameIndex(); }
export function liveCounts(this self: GPUDevice): GPULiveCounts { return backend.liveCounts(); }

@inline export function isAlive(this self: GPUBuffer): boolean { return backend.bufferAlive(self); }
@inline export function isAlive(this self: GPUTexture): boolean { return backend.textureAlive(self); }
@inline export function isAlive(this self: GPUTextureView): boolean { return backend.viewAlive(self); }
@inline export function isAlive(this self: GPUSampler): boolean { return backend.samplerAlive(self); }
