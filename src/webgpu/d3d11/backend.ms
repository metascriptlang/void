import {
	GPUAdapterInfo,
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
} from "../types.ms";

export struct NativeEnvironment { device: Ptr<void> | null; context: Ptr<void> | null; }
export struct NativeSwapchain {
	width: int32;
	height: int32;
	sampleCount: int32;
	renderView: Ptr<void> | null;
	resolveView: Ptr<void> | null;
	depthStencilView: Ptr<void> | null;
}

export function setup(environment: NativeEnvironment): GPUDevice { return { id: 1, queue: { id: 1 } }; }
export function shutdown(): void {}
export function adapterInfo(): GPUAdapterInfo { return { backend: "d3d11", originTopLeft: true, depthZeroToOne: true }; }
export function createBuffer(descriptor: GPUBufferDescriptor): GPUBuffer { return { id: 0 }; }
export function createTexture(descriptor: GPUTextureDescriptor): GPUTexture { return { id: 0 }; }
export function createSampler(descriptor: GPUSamplerDescriptor): GPUSampler { return { id: 0 }; }
export function createShaderModule(descriptor: GPUShaderModuleDescriptor): GPUShaderModule { return { id: 0 }; }
export function createRenderPipeline(descriptor: GPURenderPipelineDescriptor): GPURenderPipeline { return { id: 0 }; }
export function createBindGroup(descriptor: GPUBindGroupDescriptor): GPUBindGroup { return { id: 0 }; }
export function createCommandEncoder(): GPUCommandEncoder { return { id: 1 }; }
export function createView(texture: GPUTexture, descriptor: GPUTextureViewDescriptor): GPUTextureView { return { id: 0 }; }
export function getBindGroupLayout(pipeline: GPURenderPipeline, index: int32): GPUBindGroupLayout { return { id: 0 }; }
export function destroyBuffer(buffer: GPUBuffer): void {}
export function destroyTexture(texture: GPUTexture): void {}
export function destroyView(view: GPUTextureView): void {}
export function destroySampler(sampler: GPUSampler): void {}
export function destroyShaderModule(module: GPUShaderModule): void {}
export function destroyRenderPipeline(pipeline: GPURenderPipeline): void {}
export function destroyBindGroup(bindGroup: GPUBindGroup): void {}
export function bufferSize(buffer: GPUBuffer): int64 { return 0; }
export function textureWidth(texture: GPUTexture): int32 { return 0; }
export function textureHeight(texture: GPUTexture): int32 { return 0; }
export function viewTexture(view: GPUTextureView): GPUTexture { return { id: 0 }; }
export function writeBuffer<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {}
export function writeTexture<T>(destination: GPUTexelCopyTextureInfo, data: Readonly<Span<T>>, layout: GPUTexelCopyBufferLayout, size: GPUExtent3D): void {}
export function submit(commandBuffer: GPUCommandBuffer): void {}
export function beginRenderPass(encoder: GPUCommandEncoder, descriptor: GPURenderPassDescriptor): GPURenderPassEncoder { return { id: 1 }; }
export function finish(encoder: GPUCommandEncoder): GPUCommandBuffer { return { id: 1 }; }
export function setPipeline(pipeline: GPURenderPipeline): void {}
export function setVertexBuffer(slot: int32, buffer: GPUBuffer, offset: int64): void {}
export function setIndexBuffer(buffer: GPUBuffer, indexFormat: GPUIndexFormat, offset: int64): void {}
export function setBindGroup(index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void {}
export function setScissorRect(x: int32, y: int32, width: int32, height: int32): void {}
export function draw(vertexCount: int32, instanceCount: int32, firstVertex: int32, firstInstance: int32): void {}
export function drawIndexed(indexCount: int32, instanceCount: int32, firstIndex: int32, baseVertex: int32, firstInstance: int32): void {}
export function endPass(): void {}
export function swapchainTexture(swapchain: NativeSwapchain): GPUTexture { return { id: 0 }; }
