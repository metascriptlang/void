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
	GPUCommandEncoder,
	GPUDevice,
	GPUExtent3D,
	GPUIndexFormat,
	GPUQueue,
	GPURenderPassDescriptor,
	GPURenderPassEncoder,
	GPURenderPipeline,
	GPURenderPipelineDescriptor,
	GPUSampler,
	GPUSamplerDescriptor,
	GPUShaderModule,
	GPUShaderModuleDescriptor,
	GPUTexelCopyBufferLayout,
	GPUTexelCopyTextureInfo,
	GPUTexture,
	GPUTextureDescriptor,
	GPUTextureView,
	GPUTextureViewDescriptor,
} from "./types.ms";

when (windows && !voidGlCore) {
	import * as backend from "./d3d11/backend.ms";
}

export type GPUNativeEnvironment = backend.NativeEnvironment;
export type GPUNativeSwapchain = backend.NativeSwapchain;

export function requestDevice(environment: GPUNativeEnvironment): GPUDevice {
	return backend.setup(environment);
}

export function destroy(this self: GPUDevice): void { backend.shutdown(); }

export function getAdapterInfo(this self: GPUDevice): GPUAdapterInfo { return backend.adapterInfo(); }

@inline export function createBuffer(this self: GPUDevice, descriptor: GPUBufferDescriptor): GPUBuffer {
	return backend.createBuffer(descriptor);
}

@inline export function createTexture(this self: GPUDevice, descriptor: GPUTextureDescriptor): GPUTexture {
	return backend.createTexture(descriptor);
}

@inline export function createSampler(this self: GPUDevice, descriptor: GPUSamplerDescriptor): GPUSampler {
	return backend.createSampler(descriptor);
}

@inline export function createShaderModule(this self: GPUDevice, descriptor: GPUShaderModuleDescriptor): GPUShaderModule {
	return backend.createShaderModule(descriptor);
}

@inline export function createRenderPipeline(this self: GPUDevice, descriptor: GPURenderPipelineDescriptor): GPURenderPipeline {
	return backend.createRenderPipeline(descriptor);
}

@inline export function createBindGroup(this self: GPUDevice, descriptor: GPUBindGroupDescriptor): GPUBindGroup {
	return backend.createBindGroup(descriptor);
}

@inline export function createCommandEncoder(this self: GPUDevice): GPUCommandEncoder {
	return backend.createCommandEncoder();
}

@inline export function createView(this self: GPUTexture, descriptor: GPUTextureViewDescriptor): GPUTextureView {
	return backend.createView(self, descriptor);
}

@inline export function getBindGroupLayout(this self: GPURenderPipeline, index: int32): GPUBindGroupLayout {
	return backend.getBindGroupLayout(self, index);
}

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
	return backend.beginRenderPass(self, descriptor);
}

@inline export function finish(this self: GPUCommandEncoder): GPUCommandBuffer { return backend.finish(self); }

@inline export function setPipeline(this self: GPURenderPassEncoder, pipeline: GPURenderPipeline): void {
	backend.setPipeline(pipeline);
}

@inline export function setVertexBuffer(this self: GPURenderPassEncoder, slot: int32, buffer: GPUBuffer, offset: int64): void {
	backend.setVertexBuffer(slot, buffer, offset);
}

@inline export function setIndexBuffer(this self: GPURenderPassEncoder, buffer: GPUBuffer, indexFormat: GPUIndexFormat, offset: int64): void {
	backend.setIndexBuffer(buffer, indexFormat, offset);
}

@inline export function setBindGroup(this self: GPURenderPassEncoder, index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void {
	backend.setBindGroup(index, bindGroup, dynamicOffsets);
}

@inline export function setScissorRect(this self: GPURenderPassEncoder, x: int32, y: int32, width: int32, height: int32): void {
	backend.setScissorRect(x, y, width, height);
}

@inline export function draw(this self: GPURenderPassEncoder, vertexCount: int32, instanceCount: int32, firstVertex: int32, firstInstance: int32): void {
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
	backend.drawIndexed(indexCount, instanceCount, firstIndex, baseVertex, firstInstance);
}

@inline export function end(this self: GPURenderPassEncoder): void { backend.endPass(); }

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
