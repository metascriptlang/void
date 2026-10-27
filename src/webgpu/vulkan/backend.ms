import {
	vulkanAdapterLimit,
	vulkanCmdInsertLabel,
	vulkanCmdPopLabel,
	vulkanCmdPushLabel,
	vulkanDeviceFeatures,
	vulkanDeviceReady,
	vulkanFormatOptimalFeatures,
	vulkanSwapchainTarget,
} from "./vulkan.h";
import { TextureRecord, ViewRecord } from "../pool.ms";
import * as resources from "./resources";
import * as pass from "./pass";
import * as pipelines from "./pipeline";
import { FRAMES_IN_FLIGHT, FrameRing, beginFrame, endFrame, newFrameRing, openFrames } from "./frame";
import { formatInfo } from "./conv";
import {
	GPU_MAX_BIND_GROUP_ENTRIES,
	GPU_MAX_COLOR_ATTACHMENTS,
	GPU_MAX_UNIFORM_BLOCKS,
	GPU_MAX_VERTEX_ATTRIBUTES,
	GPU_MAX_VERTEX_BUFFERS,
	GPU_RESOURCE_GROUP,
	GPUAdapterInfo,
	GPUBindGroup,
	GPUBindGroupDescriptor,
	GPUBuffer,
	GPUBufferDescriptor,
	GPUColor,
	GPUCommandBuffer,
	GPUCommandEncoder,
	GPUComputePassDescriptor,
	GPUComputePassEncoder,
	GPUComputePipeline,
	GPUComputePipelineDescriptor,
	GPUDevice,
	GPUExtent3D,
	GPUIndexFormat,
	GPUQuerySet,
	GPUQuerySetDescriptor,
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
	GPUTextureFormat,
	GPUTextureView,
	GPUTextureViewDescriptor,
	featureBit,
	stop,
} from "../types.ms";

@passC("-I../../../deps/vulkan-headers/include");

export struct NativeEnvironment {
	device: Ptr<void> | null;
	context: Ptr<void> | null;
	colorFormat: GPUTextureFormat;
	depthFormat: GPUTextureFormat;
	sampleCount: int32;
}
export struct NativeSwapchain {
	width: int32;
	height: int32;
	sampleCount: int32;
	renderView: Ptr<void> | null;
	resolveView: Ptr<void> | null;
	depthStencilView: Ptr<void> | null;
}

const LIMIT_TEXTURE_DIMENSION_1D: int32 = 0;
const LIMIT_TEXTURE_DIMENSION_2D: int32 = 1;
const LIMIT_TEXTURE_DIMENSION_3D: int32 = 2;
const LIMIT_TEXTURE_ARRAY_LAYERS: int32 = 3;
const LIMIT_BIND_GROUPS: int32 = 4;
const LIMIT_SAMPLED_TEXTURES_PER_STAGE: int32 = 5;
const LIMIT_SAMPLERS_PER_STAGE: int32 = 6;
const LIMIT_STORAGE_BUFFERS_PER_STAGE: int32 = 7;
const LIMIT_STORAGE_TEXTURES_PER_STAGE: int32 = 8;
const LIMIT_UNIFORM_BUFFERS_PER_STAGE: int32 = 9;
const LIMIT_UNIFORM_BUFFER_BINDING_SIZE: int32 = 10;
const LIMIT_STORAGE_BUFFER_BINDING_SIZE: int32 = 11;
const LIMIT_VERTEX_BUFFERS: int32 = 12;
const LIMIT_VERTEX_ATTRIBUTES: int32 = 13;
const LIMIT_COLOR_ATTACHMENTS: int32 = 14;
const LIMIT_WORKGROUP_SIZE_X: int32 = 15;
const LIMIT_WORKGROUP_SIZE_Y: int32 = 16;
const LIMIT_WORKGROUP_SIZE_Z: int32 = 17;
const LIMIT_WORKGROUP_INVOCATIONS: int32 = 18;
const LIMIT_WORKGROUPS_PER_DIMENSION: int32 = 19;
const LIMIT_UNIFORM_OFFSET_ALIGNMENT: int32 = 20;
const LIMIT_STORAGE_OFFSET_ALIGNMENT: int32 = 21;
const INT32_LIMIT: int64 = 2147483647;

const FORMAT_FEATURE_COLOR_ATTACHMENT: uint32 = 0x80;
const FORMAT_FEATURE_COLOR_ATTACHMENT_BLEND: uint32 = 0x100;
const FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT: uint32 = 0x200;
const FORMAT_FEATURE_FILTER_LINEAR: uint32 = 0x1000;

export const BACKEND = "vulkan";

let r: resources.VulkanResources = resources.closedResources();
let p: pipelines.VulkanPipelines = pipelines.openPipelines();
let cache: pass.RenderPassCache = pass.newRenderPassCache();
let ring: FrameRing = newFrameRing(0);

@noinline function stopOnResource(call: string, error: resources.ResourceError): never {
	match (error) {
		resources.ResourceError.DeviceLost => stop(`vulkan: ${call} lost the device; recovering it needs the Vulkan window host, not built yet`),
		resources.ResourceError.OutOfMemory => stop(`vulkan: ${call} ran out of device memory`),
	};
}

function ran(call: string, result: Result<void, resources.ResourceError>): void {
	if (!result.ok) { stopOnResource(call, result.error); }
}

function commanded(code: int32): void {
	if (code != resources.VULKAN_OK) { resources.stopOnVulkan(); }
}

@noinline function refuseQueries(): never {
	stop("vulkan: GPUQuerySet is not built on Vulkan yet; the adapter does not advertise timestamp-query");
}

export function setup(environment: NativeEnvironment): GPUDevice {
	if (environment.device !== null || environment.context !== null) {
		stop("vulkan: requestDevice adopts the device vulkanDeviceCreate opened; NativeEnvironment.device and .context stay null");
	}
	commanded(vulkanDeviceReady());
	r = resources.openResources();
	p = pipelines.openPipelines();
	cache = pass.newRenderPassCache();
	return { id: 1, queue: { id: 1 } };
}

export function adoptSwapchain(color: uint32, depth: uint32): void {
	resources.adoptSwapchain(r, color, depth);
}

export function formatRenderable(format: GPUTextureFormat): boolean {
	const info = formatInfo(format, r.depthStencil, "formatRenderable format");
	const features = vulkanFormatOptimalFeatures(info.native);
	return (features & (info.depth ? FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT : FORMAT_FEATURE_COLOR_ATTACHMENT)) != 0;
}

export function shutdown(): void {
	pass.closeRenderPasses(cache);
	pipelines.closePipelines(p);
	const closed = resources.closeResources(r);
	r = resources.closedResources();
	ring = newFrameRing(0);
	if (!closed.ok) { stopOnResource("destroy", closed.error); }
}

export function beginWindowFrame(): void {
	if (ring.serials.length == 0) {
		const opened = openFrames(FRAMES_IN_FLIGHT);
		if (!opened.ok) { stopOnResource("the window's frame ring", opened.error); }
		ring = opened.value;
	}
	const begun = beginFrame(r, ring);
	if (!begun.ok) { stopOnResource("the window's frame", begun.error); }
}

export function endWindowFrame(image: uint64): void {
	resources.presentSwapchain(r, image);
	const ended = endFrame(r, ring);
	if (!ended.ok) { stopOnResource("the window's frame", ended.error); }
}

export function adapterInfo(): GPUAdapterInfo {
	return { backend: "vulkan", originTopLeft: true, depthZeroToOne: true };
}

export function createBuffer(id: uint32, descriptor: GPUBufferDescriptor): void {
	ran("createBuffer", resources.createBuffer(r, id, descriptor));
}

export function destroyBuffer(buffer: GPUBuffer): void {
	resources.destroyBuffer(r, buffer.id);
}

export function writeBuffer<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	ran("writeBuffer", resources.writeBuffer(r, buffer, offset, data));
}

export function createTexture(texture: TextureRecord, descriptor: GPUTextureDescriptor): void {
	ran("createTexture", resources.createTexture(r, texture, descriptor));
}

export function destroyTexture(texture: GPUTexture): void {
	resources.destroyTexture(r, texture.id);
}

export function writeTexture<T>(
	destination: GPUTexelCopyTextureInfo,
	data: Readonly<Span<T>>,
	layout: GPUTexelCopyBufferLayout,
	size: GPUExtent3D,
): void {
	ran("writeTexture", resources.writeTexture(r, destination, data, layout, size));
}

export function createView(view: ViewRecord, descriptor: GPUTextureViewDescriptor): void {
	ran("createView", resources.createView(r, view, descriptor));
}

export function destroyView(view: GPUTextureView): void {
	resources.destroyView(r, view.id);
}

export function acquireSwapchain(swapchain: NativeSwapchain): void {
	if (swapchain.resolveView !== null) {
		stop("vulkan: the backend owns the multisampled canvas and resolves it into renderView; NativeSwapchain.resolveView stays null");
	}
	if (swapchain.depthStencilView !== null) {
		stop("vulkan: the backend owns the swapchain depth; NativeSwapchain.depthStencilView stays null");
	}
	if (swapchain.renderView === null) { stop("vulkan: NativeSwapchain.renderView is null"); }
	let image: uint64 = 0;
	let view: uint64 = 0;
	commanded(vulkanSwapchainTarget(swapchain.renderView, image, view));
	ran("getCurrentTexture", resources.acquireSwapchain(r, swapchain.width, swapchain.height, image, view));
}

export function createSampler(id: uint32, descriptor: GPUSamplerDescriptor): void {
	ran("createSampler", resources.createSampler(r, id, descriptor));
}

export function destroySampler(sampler: GPUSampler): void {
	resources.destroySampler(r, sampler.id);
}

export function createShaderModule(id: uint32, descriptor: GPUShaderModuleDescriptor): void {
	ran("createShaderModule", pipelines.createShaderModule(p, r, id, descriptor));
}

export function destroyShaderModule(module: GPUShaderModule): void {
	pipelines.destroyShaderModule(p, r, module.id);
}

export function createRenderPipeline(id: uint32, descriptor: GPURenderPipelineDescriptor): void {
	ran("createRenderPipeline", pipelines.createRenderPipeline(p, r, cache, id, descriptor));
}

export function destroyRenderPipeline(pipeline: GPURenderPipeline): void {
	pipelines.destroyPipeline(p, r, pipeline.id);
}

export function createBindGroup(id: uint32, descriptor: GPUBindGroupDescriptor): void {
	ran("createBindGroup", pipelines.createBindGroup(p, r, id, descriptor));
}

export function destroyBindGroup(bindGroup: GPUBindGroup): void {
	pipelines.destroyBindGroup(p, r, bindGroup.id);
}

export function createCommandEncoder(): GPUCommandEncoder { return { id: 1 }; }

export function finish(encoder: GPUCommandEncoder): GPUCommandBuffer {
	return { id: 1 };
}

export function submit(commandBuffer: GPUCommandBuffer): void {
	const submitted = resources.submit(r);
	if (!submitted.ok) { stopOnResource("submit", submitted.error); }
	const collected = resources.collect(r);
	if (!collected.ok) { stopOnResource("submit", collected.error); }
}

export function beginRenderPass(encoder: GPUCommandEncoder, descriptor: GPURenderPassDescriptor, extent: GPUExtent3D): GPURenderPassEncoder {
	ran("beginRenderPass", pass.beginRenderPass(r, cache, descriptor, extent));
	pipelines.beginBindings(p, false);
	return { id: 1 };
}

export function endPass(): void {
	pass.endRenderPass();
	resources.settle(r);
}

export function setPipeline(pipeline: GPURenderPipeline): void {
	pipelines.setPipeline(p, pipeline.id);
}

export function setVertexBuffer(slot: int32, buffer: GPUBuffer, offset: int64): void {
	pipelines.setVertexBuffer(r, slot, buffer, offset);
}

export function setIndexBuffer(buffer: GPUBuffer, format: GPUIndexFormat, offset: int64): void {
	pipelines.setIndexBuffer(r, buffer, format, offset);
}

export function setBindGroup(index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void {
	pipelines.setBindGroup(p, index);
}

export function setScissorRect(x: int32, y: int32, width: int32, height: int32): void {
	pipelines.setScissorRect(x, y, width, height);
}

export function setViewport(x: float32, y: float32, width: float32, height: float32, minDepth: float32, maxDepth: float32): void {
	pipelines.setViewport(x, y, width, height, minDepth, maxDepth);
}

export function setBlendConstant(color: GPUColor): void {
	pipelines.setBlendConstant(color);
}

export function setStencilReference(reference: uint32): void {
	pipelines.setStencilReference(reference);
}

export function draw(vertexCount: int32, instanceCount: int32, firstVertex: int32, firstInstance: int32): void {
	pipelines.draw(p, r, vertexCount, instanceCount, firstVertex, firstInstance);
}

export function drawIndexed(indexCount: int32, instanceCount: int32, firstIndex: int32, baseVertex: int32, firstInstance: int32): void {
	pipelines.drawIndexed(p, r, indexCount, instanceCount, firstIndex, baseVertex, firstInstance);
}

export function multiDrawIndexedIndirect(buffer: GPUBuffer, offset: int64, drawCount: int32): void {
	pipelines.multiDrawIndexedIndirect(p, r, buffer, offset, drawCount);
}

export function copyBufferToBuffer(source: GPUBuffer, sourceOffset: int64, destination: GPUBuffer, destinationOffset: int64, size: int64): void {
	ran("copyBufferToBuffer", resources.copyBufferToBuffer(r, source, sourceOffset, destination, destinationOffset, size));
}

export function copyTextureToBuffer(source: GPUTexelCopyTextureInfo, destination: GPUTexelCopyBufferInfo, size: GPUExtent3D): void {
	ran("copyTextureToBuffer", resources.copyTextureToBuffer(r, source, destination, size));
}

export function copyBufferToTexture(source: GPUTexelCopyBufferInfo, destination: GPUTexelCopyTextureInfo, size: GPUExtent3D): void {
	ran("copyBufferToTexture", resources.copyBufferToTexture(r, source, destination, size));
}

export function copyTextureToTexture(source: GPUTexelCopyTextureInfo, destination: GPUTexelCopyTextureInfo, size: GPUExtent3D): void {
	ran("copyTextureToTexture", resources.copyTextureToTexture(r, source, destination, size));
}

export function mapAsync(buffer: GPUBuffer, mode: int32, offset: int64, length: int64): void {
	ran("mapAsync", resources.mapAsync(r, buffer));
}

export function getMappedRange(buffer: GPUBuffer, offset: int64, length: int64): Vec<uint8> {
	const read = resources.readMapped(r, buffer, offset, length);
	if (!read.ok) { stopOnResource("getMappedRange", read.error); }
	return read.value;
}

export function writeMappedRange<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	ran("writeMappedRange", resources.writeMapped(r, buffer, offset, data));
}

export function createComputePipeline(id: uint32, descriptor: GPUComputePipelineDescriptor): void {
	ran("createComputePipeline", pipelines.createComputePipeline(p, id, descriptor));
}

export function beginComputePass(encoder: GPUCommandEncoder, descriptor: GPUComputePassDescriptor): GPUComputePassEncoder {
	resources.settle(r);
	pipelines.beginBindings(p, true);
	return { id: 1 };
}

export function setComputePipeline(pipeline: GPUComputePipeline): void {
	pipelines.setPipeline(p, pipeline.id);
}

export function setComputeBindGroup(index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void {
	pipelines.setBindGroup(p, index);
}

export function dispatchWorkgroups(x: int32, y: int32, z: int32): void {
	ran("dispatchWorkgroups", pipelines.dispatchWorkgroups(p, r, x, y, z));
}

export function dispatchWorkgroupsIndirect(buffer: GPUBuffer, offset: int64): void {
	ran("dispatchWorkgroupsIndirect", pipelines.dispatchWorkgroupsIndirect(p, r, buffer, offset));
}

export function endComputePass(): void {
	resources.settle(r);
}

function capped(limit: int32, ceiling: int64): int32 {
	return Math.min(vulkanAdapterLimit(limit), ceiling) as int32;
}

export function limits(): GPUSupportedLimits {
	return {
		maxTextureDimension1D: capped(LIMIT_TEXTURE_DIMENSION_1D, INT32_LIMIT),
		maxTextureDimension2D: capped(LIMIT_TEXTURE_DIMENSION_2D, INT32_LIMIT),
		maxTextureDimension3D: capped(LIMIT_TEXTURE_DIMENSION_3D, INT32_LIMIT),
		maxTextureArrayLayers: capped(LIMIT_TEXTURE_ARRAY_LAYERS, INT32_LIMIT),
		maxBindGroups: capped(LIMIT_BIND_GROUPS, (GPU_RESOURCE_GROUP + 1) as int64),
		maxSampledTexturesPerShaderStage: capped(LIMIT_SAMPLED_TEXTURES_PER_STAGE, GPU_MAX_BIND_GROUP_ENTRIES as int64),
		maxSamplersPerShaderStage: capped(LIMIT_SAMPLERS_PER_STAGE, GPU_MAX_BIND_GROUP_ENTRIES as int64),
		maxStorageBuffersPerShaderStage: capped(LIMIT_STORAGE_BUFFERS_PER_STAGE, GPU_MAX_BIND_GROUP_ENTRIES as int64),
		maxStorageTexturesPerShaderStage: capped(LIMIT_STORAGE_TEXTURES_PER_STAGE, GPU_MAX_BIND_GROUP_ENTRIES as int64),
		maxUniformBuffersPerShaderStage: capped(LIMIT_UNIFORM_BUFFERS_PER_STAGE, GPU_MAX_UNIFORM_BLOCKS as int64),
		maxUniformBufferBindingSize: vulkanAdapterLimit(LIMIT_UNIFORM_BUFFER_BINDING_SIZE),
		maxStorageBufferBindingSize: vulkanAdapterLimit(LIMIT_STORAGE_BUFFER_BINDING_SIZE),
		maxVertexBuffers: capped(LIMIT_VERTEX_BUFFERS, GPU_MAX_VERTEX_BUFFERS as int64),
		maxVertexAttributes: capped(LIMIT_VERTEX_ATTRIBUTES, GPU_MAX_VERTEX_ATTRIBUTES as int64),
		maxColorAttachments: capped(LIMIT_COLOR_ATTACHMENTS, GPU_MAX_COLOR_ATTACHMENTS as int64),
		maxComputeWorkgroupSizeX: capped(LIMIT_WORKGROUP_SIZE_X, INT32_LIMIT),
		maxComputeWorkgroupSizeY: capped(LIMIT_WORKGROUP_SIZE_Y, INT32_LIMIT),
		maxComputeWorkgroupSizeZ: capped(LIMIT_WORKGROUP_SIZE_Z, INT32_LIMIT),
		maxComputeInvocationsPerWorkgroup: capped(LIMIT_WORKGROUP_INVOCATIONS, INT32_LIMIT),
		maxComputeWorkgroupsPerDimension: capped(LIMIT_WORKGROUPS_PER_DIMENSION, INT32_LIMIT),
		minUniformBufferOffsetAlignment: capped(LIMIT_UNIFORM_OFFSET_ALIGNMENT, INT32_LIMIT),
		minStorageBufferOffsetAlignment: capped(LIMIT_STORAGE_OFFSET_ALIGNMENT, INT32_LIMIT),
	};
}

function formatFeatures(format: GPUTextureFormat): uint32 {
	return vulkanFormatOptimalFeatures(formatInfo(format, r.depthStencil, "features format").native);
}

export function features(): GPUSupportedFeatures {
	let bits: uint32 = 0;
	const float32 = formatFeatures("r32float") & formatFeatures("rg32float") & formatFeatures("rgba32float");
	if ((float32 & FORMAT_FEATURE_FILTER_LINEAR) != 0) { bits |= featureBit("float32-filterable"); }
	if ((float32 & FORMAT_FEATURE_COLOR_ATTACHMENT_BLEND) != 0) { bits |= featureBit("float32-blendable"); }
	const renderable = FORMAT_FEATURE_COLOR_ATTACHMENT | FORMAT_FEATURE_COLOR_ATTACHMENT_BLEND;
	if ((formatFeatures("rg11b10ufloat") & renderable) == renderable) { bits |= featureBit("rg11b10ufloat-renderable"); }
	bits |= vulkanDeviceFeatures() & featureBit("indirect-first-instance");
	return { bits: bits };
}

export function pushDebugGroup(label: string): void {
	commanded(vulkanCmdPushLabel(label));
}

export function popDebugGroup(): void {
	commanded(vulkanCmdPopLabel());
}

export function insertDebugMarker(label: string): void {
	commanded(vulkanCmdInsertLabel(label));
}

export function createQuerySet(id: uint32, descriptor: GPUQuerySetDescriptor): void {
	refuseQueries();
}

export function destroyQuerySet(querySet: GPUQuerySet): void {
	refuseQueries();
}

export function resolveQuerySet(querySet: GPUQuerySet, firstQuery: int32, queryCount: int32, destination: GPUBuffer, destinationOffset: int64): void {
	refuseQueries();
}

export function beginOcclusionQuery(queryIndex: int32): void {
	refuseQueries();
}

export function endOcclusionQuery(): void {
	refuseQueries();
}
