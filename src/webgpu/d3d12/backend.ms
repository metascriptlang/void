import {
	dx12AdapterDescribe,
	dx12AdapterDescription,
	dx12DeviceCreate,
	dx12InfoDrain,
	dx12QueueCreate,
	dx12Release,
} from "./d3d12.h";
import { TextureRecord, ViewRecord } from "../pool.ms";
import {
	DX12_OK,
	FRAMES_IN_FLIGHT,
	FrameRing,
	NativeError,
	closeFrames,
	closedFrames,
	openFrames,
	stop,
	stopOnNative,
	submit as submitFrame,
	waitIdle,
	waitSerial,
} from "./frame.ms";
import * as resources from "./resources.ms";
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
} from "../types.ms";

export struct NativeEnvironment {
	device: Ptr<void> | null;
	context: Ptr<void> | null;
	colorFormat: GPUTextureFormat;
	depthFormat: GPUTextureFormat;
	sampleCount: int32;
	warp: boolean;
	debug: boolean;
}
export struct NativeSwapchain {
	width: int32;
	height: int32;
	sampleCount: int32;
	renderView: Ptr<void> | null;
	resolveView: Ptr<void> | null;
	depthStencilView: Ptr<void> | null;
}

const MAX_TEXTURE_DIMENSION_1D = 16384;
const MAX_TEXTURE_DIMENSION_2D = 16384;
const MAX_TEXTURE_DIMENSION_3D = 2048;
const MAX_TEXTURE_ARRAY_LAYERS = 2048;
const MAX_STAGE_SHADER_RESOURCES = 128;
const MAX_STAGE_SAMPLERS = 16;
const MAX_STAGE_UNORDERED_ACCESS_VIEWS = 8;
const MAX_ROOT_CONSTANT_BUFFERS = 8;
const MAX_UNIFORM_BUFFER_BINDING_SIZE: int64 = 65536;
const MAX_STORAGE_BUFFER_BINDING_SIZE: int64 = 134217728;
const MAX_WORKGROUP_SIZE_X = 1024;
const MAX_WORKGROUP_SIZE_Y = 1024;
const MAX_WORKGROUP_SIZE_Z = 64;
const MAX_WORKGROUP_INVOCATIONS = 1024;
const MAX_DISPATCH_GROUPS = 65535;
const UNIFORM_OFFSET_ALIGNMENT = 256;
const STORAGE_OFFSET_ALIGNMENT = 256;

export const BACKEND = "d3d12";

let device: uint64 = 0;
let adapter: uint64 = 0;
let queue: uint64 = 0;
let ring: FrameRing = closedFrames();
let r: resources.Resources = resources.closedResources();
let encoding = false;
let swapchainColor: uint32 = 0;
let swapchainDepth: uint32 = 0;

@noinline function notBuilt(call: string, step: string): never {
	stop(`${call} not built yet (${step})`);
}

@noinline function stopOnFrame(call: string, error: NativeError): never {
	match (error) {
		NativeError.DeviceRemoved => stop(`${call} lost the device; recovering it is not built yet (D5)`),
		NativeError.OutOfMemory => stop(`${call} ran out of memory`),
	};
}

function commanded(code: int32): void {
	if (code != DX12_OK) { stopOnNative(); }
}

export function setup(environment: NativeEnvironment): GPUDevice {
	if (environment.device !== null || environment.context !== null) {
		stop("requestDevice opens its own ID3D12Device; NativeEnvironment.device and .context stay null");
	}
	if (device != 0) { stop("requestDevice while a D3D12 device is open; destroy that device first"); }
	let opened: uint64 = 0;
	let chosen: uint64 = 0;
	commanded(dx12DeviceCreate(environment.warp ? 1 : 0, environment.debug ? 1 : 0, opened, chosen));
	device = opened;
	adapter = chosen;
	let direct: uint64 = 0;
	commanded(dx12QueueCreate(device, direct));
	queue = direct;
	const frames = openFrames(device, queue, FRAMES_IN_FLIGHT);
	if (!frames.ok) { stopOnFrame("requestDevice", frames.error); }
	ring = frames.value;
	r = resources.openResources(device, FRAMES_IN_FLIGHT);
	return { id: 1, queue: { id: 1 } };
}

export function adoptSwapchain(color: uint32, depth: uint32): void {
	swapchainColor = color;
	swapchainDepth = depth;
}

export function formatRenderable(format: GPUTextureFormat): boolean {
	notBuilt("formatRenderable", "D2");
}

export function shutdown(): void {
	const closed = closeFrames(ring);
	ring = closedFrames();
	resources.closeResources(r);
	encoding = false;
	dx12Release(queue);
	dx12Release(device);
	dx12Release(adapter);
	queue = 0;
	device = 0;
	adapter = 0;
	if (!closed.ok) { stopOnFrame("destroy", closed.error); }
}

export function adapterInfo(): GPUAdapterInfo {
	return { backend: "d3d12", originTopLeft: true, depthZeroToOne: true };
}

export function adapterDescription(): string {
	let vendorId: uint32 = 0;
	let deviceId: uint32 = 0;
	commanded(dx12AdapterDescribe(adapter, vendorId, deviceId));
	return dx12AdapterDescription();
}

export function idleSerial(): uint64 {
	const idle = waitIdle(ring);
	if (!idle.ok) { stopOnFrame("idleSerial", idle.error); }
	return idle.value;
}

export function executedAllocator(): uint64 { return ring.executed; }

export function frameAllocator(slot: int32): uint64 { return ring.allocators[slot]; }

export function retiredCount(): int32 { return ring.retired.length as int32; }

export function drainDebugMessages(): uint64 {
	let count: uint64 = 0;
	commanded(dx12InfoDrain(device, count));
	return count;
}

function ran(call: string, result: Result<void, NativeError>): void {
	if (!result.ok) { stopOnFrame(call, result.error); }
}

function submitted(call: string): void {
	const serial = submitFrame(ring, r.tracker);
	if (!serial.ok) { stopOnFrame(call, serial.error); }
	resources.resetUploads(r, ring.slot());
	encoding = false;
}

export function createBuffer(id: uint32, descriptor: GPUBufferDescriptor): void {
	ran("createBuffer", resources.createBuffer(r, id, descriptor));
}

export function destroyBuffer(buffer: GPUBuffer): void {
	resources.destroyBuffer(r, ring, buffer.id);
}

export function writeBuffer<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	ran("writeBuffer", resources.writeBuffer(r, ring, buffer, offset, data));
}

export function createTexture(texture: TextureRecord, descriptor: GPUTextureDescriptor): void {
	ran("createTexture", resources.createTexture(r, texture));
}

export function destroyTexture(texture: GPUTexture): void {
	resources.destroyTexture(r, ring, texture.id);
}

export function writeTexture<T>(
	destination: GPUTexelCopyTextureInfo,
	data: Readonly<Span<T>>,
	layout: GPUTexelCopyBufferLayout,
	size: GPUExtent3D,
): void {
	ran("writeTexture", resources.writeTexture(r, ring, destination, data, layout, size));
}

export function createView(view: ViewRecord, descriptor: GPUTextureViewDescriptor): void {
	notBuilt("createView", "D2");
}

export function destroyView(view: GPUTextureView): void {
	notBuilt("destroyView", "D2");
}

export function acquireSwapchain(swapchain: NativeSwapchain): void {
	notBuilt("acquireSwapchain", "D5");
}

export function createSampler(id: uint32, descriptor: GPUSamplerDescriptor): void {
	notBuilt("createSampler", "D3");
}

export function destroySampler(sampler: GPUSampler): void {
	notBuilt("destroySampler", "D3");
}

export function createShaderModule(id: uint32, descriptor: GPUShaderModuleDescriptor): void {
	notBuilt("createShaderModule", "D4");
}

export function destroyShaderModule(module: GPUShaderModule): void {
	notBuilt("destroyShaderModule", "D4");
}

export function createRenderPipeline(id: uint32, descriptor: GPURenderPipelineDescriptor): void {
	notBuilt("createRenderPipeline", "D4");
}

export function destroyRenderPipeline(pipeline: GPURenderPipeline): void {
	notBuilt("destroyRenderPipeline", "D4");
}

export function createBindGroup(id: uint32, descriptor: GPUBindGroupDescriptor): void {
	notBuilt("createBindGroup", "D3");
}

export function destroyBindGroup(bindGroup: GPUBindGroup): void {
	notBuilt("destroyBindGroup", "D3");
}

export function createCommandEncoder(): GPUCommandEncoder {
	encoding = true;
	return { id: 1 };
}

export function finish(encoder: GPUCommandEncoder): GPUCommandBuffer {
	return { id: 1 };
}

export function submit(commandBuffer: GPUCommandBuffer): void {
	submitted("submit");
}

export function beginRenderPass(encoder: GPUCommandEncoder, descriptor: GPURenderPassDescriptor, extent: GPUExtent3D): GPURenderPassEncoder {
	notBuilt("beginRenderPass", "D4");
}

export function endPass(): void {
	notBuilt("endPass", "D4");
}

export function setPipeline(pipeline: GPURenderPipeline): void {
	notBuilt("setPipeline", "D4");
}

export function setVertexBuffer(slot: int32, buffer: GPUBuffer, offset: int64): void {
	notBuilt("setVertexBuffer", "D4");
}

export function setIndexBuffer(buffer: GPUBuffer, format: GPUIndexFormat, offset: int64): void {
	notBuilt("setIndexBuffer", "D4");
}

export function setBindGroup(index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void {
	notBuilt("setBindGroup", "D3");
}

export function setScissorRect(x: int32, y: int32, width: int32, height: int32): void {
	notBuilt("setScissorRect", "D4");
}

export function setViewport(x: float32, y: float32, width: float32, height: float32, minDepth: float32, maxDepth: float32): void {
	notBuilt("setViewport", "D4");
}

export function setBlendConstant(color: GPUColor): void {
	notBuilt("setBlendConstant", "D4");
}

export function setStencilReference(reference: uint32): void {
	notBuilt("setStencilReference", "D4");
}

export function draw(vertexCount: int32, instanceCount: int32, firstVertex: int32, firstInstance: int32): void {
	notBuilt("draw", "D4");
}

export function drawIndexed(indexCount: int32, instanceCount: int32, firstIndex: int32, baseVertex: int32, firstInstance: int32): void {
	notBuilt("drawIndexed", "D4");
}

export function multiDrawIndexedIndirect(buffer: GPUBuffer, offset: int64, drawCount: int32): void {
	notBuilt("multiDrawIndexedIndirect", "D4");
}

export function copyBufferToBuffer(source: GPUBuffer, sourceOffset: int64, destination: GPUBuffer, destinationOffset: int64, size: int64): void {
	ran("copyBufferToBuffer", resources.copyBufferToBuffer(r, ring, source, sourceOffset, destination, destinationOffset, size));
}

export function copyTextureToBuffer(source: GPUTexelCopyTextureInfo, destination: GPUTexelCopyBufferInfo, size: GPUExtent3D): void {
	ran("copyTextureToBuffer", resources.copyTextureToBuffer(r, ring, source, destination, size));
}

export function copyBufferToTexture(source: GPUTexelCopyBufferInfo, destination: GPUTexelCopyTextureInfo, size: GPUExtent3D): void {
	ran("copyBufferToTexture", resources.copyBufferToTexture(r, ring, source, destination, size));
}

export function copyTextureToTexture(source: GPUTexelCopyTextureInfo, destination: GPUTexelCopyTextureInfo, size: GPUExtent3D): void {
	ran("copyTextureToTexture", resources.copyTextureToTexture(r, ring, source, destination, size));
}

export function mapAsync(buffer: GPUBuffer, mode: int32, offset: int64, length: int64): void {
	const lastUse = r.lastUse(buffer);
	if (lastUse > ring.submitted) {
		if (encoding) {
			stop(`mapAsync: GPUBuffer ${buffer.id} has work that was not submitted while a command encoder records; submit the encoder first`);
		}
		submitted("mapAsync");
	}
	if (lastUse == 0) { return; }
	const waited = waitSerial(ring, lastUse);
	if (!waited.ok) { stopOnFrame("mapAsync", waited.error); }
}

export function getMappedRange(buffer: GPUBuffer, offset: int64, length: int64): Vec<uint8> {
	const read = resources.readMapped(r, buffer, offset, length);
	if (!read.ok) { stopOnFrame("getMappedRange", read.error); }
	return read.value;
}

export function writeMappedRange<T>(buffer: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	ran("writeMappedRange", resources.writeMapped(r, buffer, offset, data));
}

export function createComputePipeline(id: uint32, descriptor: GPUComputePipelineDescriptor): void {
	notBuilt("createComputePipeline", "D6");
}

export function beginComputePass(encoder: GPUCommandEncoder, descriptor: GPUComputePassDescriptor): GPUComputePassEncoder {
	notBuilt("beginComputePass", "D6");
}

export function setComputePipeline(pipeline: GPUComputePipeline): void {
	notBuilt("setComputePipeline", "D6");
}

export function setComputeBindGroup(index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void {
	notBuilt("setComputeBindGroup", "D6");
}

export function dispatchWorkgroups(x: int32, y: int32, z: int32): void {
	notBuilt("dispatchWorkgroups", "D6");
}

export function dispatchWorkgroupsIndirect(buffer: GPUBuffer, offset: int64): void {
	notBuilt("dispatchWorkgroupsIndirect", "D6");
}

export function endComputePass(): void {
	notBuilt("endComputePass", "D6");
}

export function limits(): GPUSupportedLimits {
	return {
		maxTextureDimension1D: MAX_TEXTURE_DIMENSION_1D,
		maxTextureDimension2D: MAX_TEXTURE_DIMENSION_2D,
		maxTextureDimension3D: MAX_TEXTURE_DIMENSION_3D,
		maxTextureArrayLayers: MAX_TEXTURE_ARRAY_LAYERS,
		maxBindGroups: GPU_RESOURCE_GROUP + 1,
		maxSampledTexturesPerShaderStage: Math.min(MAX_STAGE_SHADER_RESOURCES, GPU_MAX_BIND_GROUP_ENTRIES),
		maxSamplersPerShaderStage: Math.min(MAX_STAGE_SAMPLERS, GPU_MAX_BIND_GROUP_ENTRIES),
		maxStorageBuffersPerShaderStage: Math.min(MAX_STAGE_UNORDERED_ACCESS_VIEWS, GPU_MAX_BIND_GROUP_ENTRIES),
		maxStorageTexturesPerShaderStage: Math.min(MAX_STAGE_UNORDERED_ACCESS_VIEWS, GPU_MAX_BIND_GROUP_ENTRIES),
		maxUniformBuffersPerShaderStage: Math.min(MAX_ROOT_CONSTANT_BUFFERS, GPU_MAX_UNIFORM_BLOCKS),
		maxUniformBufferBindingSize: MAX_UNIFORM_BUFFER_BINDING_SIZE,
		maxStorageBufferBindingSize: MAX_STORAGE_BUFFER_BINDING_SIZE,
		maxVertexBuffers: GPU_MAX_VERTEX_BUFFERS,
		maxVertexAttributes: GPU_MAX_VERTEX_ATTRIBUTES,
		maxColorAttachments: GPU_MAX_COLOR_ATTACHMENTS,
		maxComputeWorkgroupSizeX: MAX_WORKGROUP_SIZE_X,
		maxComputeWorkgroupSizeY: MAX_WORKGROUP_SIZE_Y,
		maxComputeWorkgroupSizeZ: MAX_WORKGROUP_SIZE_Z,
		maxComputeInvocationsPerWorkgroup: MAX_WORKGROUP_INVOCATIONS,
		maxComputeWorkgroupsPerDimension: MAX_DISPATCH_GROUPS,
		minUniformBufferOffsetAlignment: UNIFORM_OFFSET_ALIGNMENT,
		minStorageBufferOffsetAlignment: STORAGE_OFFSET_ALIGNMENT,
	};
}

export function features(): GPUSupportedFeatures {
	return { bits: 0 };
}

export function pushDebugGroup(label: string): void {
	notBuilt("pushDebugGroup", "D4");
}

export function popDebugGroup(): void {
	notBuilt("popDebugGroup", "D4");
}

export function insertDebugMarker(label: string): void {
	notBuilt("insertDebugMarker", "D4");
}

export function createQuerySet(id: uint32, descriptor: GPUQuerySetDescriptor): void {
	notBuilt("createQuerySet", "D6");
}

export function destroyQuerySet(querySet: GPUQuerySet): void {
	notBuilt("destroyQuerySet", "D6");
}

export function resolveQuerySet(querySet: GPUQuerySet, firstQuery: int32, queryCount: int32, destination: GPUBuffer, destinationOffset: int64): void {
	notBuilt("resolveQuerySet", "D6");
}

export function beginOcclusionQuery(queryIndex: int32): void {
	notBuilt("beginOcclusionQuery", "D6");
}

export function endOcclusionQuery(): void {
	notBuilt("endOcclusionQuery", "D6");
}
