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
	GPUMapMode,
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
	GPU_MAX_COLOR_ATTACHMENTS,
	GPU_RESOURCE_GROUP,
	GPU_UNIFORM_GROUP,
	GPUTextureUsage,
	checkedMapAsync,
	checkedMappedRange,
	checkedUnmap,
	featureBit,
	stop,
} from "./types.ms";
import {
	allocate,
	alive,
	bindGroupRecords,
	bufferRecords,
	free,
	layoutRecords,
	live,
	liveIds,
	pipelineRecords,
	querySetRecords,
	record,
	resetRecords,
	samplerRecords,
	shaderRecords,
	slotIndex,
	slotOf,
	store,
	textureRecords,
	viewRecords,
} from "./pool.ms";
import {
	AttachmentFacts,
	PASS_COMPUTE,
	PASS_RENDER,
	RenderPassFacts,
	attachOcclusionSet,
	attachmentFactsOf,
	cacheLimits,
	cachedLimits,
	checkedBeginOcclusion,
	checkedBeginPass,
	checkedBindGroupIndex,
	checkedBuffer,
	checkedCreateEncoder,
	checkedDispatch,
	checkedDrawState,
	checkedEndOcclusion,
	checkedEndPass,
	checkedFinish,
	checkedInPass,
	checkedMarker,
	checkedOutsidePass,
	checkedPipelineSet,
	checkedPopGroup,
	checkedPushGroup,
	checkedQuerySet,
	checkedRenderPass,
	checkedRenderPipeline,
	checkedSampler,
	checkedShaderModule,
	checkedShutdown,
	checkedTexture,
	checkedViewRange,
	checkedViewport,
	checkedWriteBuffer,
	markBufferWritten,
	markIndexSet,
	markPipelineSet,
	resetEncoder,
	resetFrame,
	resolvedRenderPipeline,
	textureRecordOf,
	advanceFrame,
	cacheCanvas,
	cachedCanvas,
	currentFrame,
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

let swapchainColor: uint32 = 0;
let swapchainDepth: uint32 = 0;

export function requestDevice(environment: GPUNativeEnvironment): GPUDevice {
	resetEncoder();
	resetFrame();
	resetRecords(backend.BACKEND);
	cacheCanvas(environment.colorFormat, environment.depthFormat, environment.sampleCount);
	const device = backend.setup(environment);
	cacheLimits(backend.limits());
	const canvas = cachedCanvas();
	const depthFormat: string = canvas.depthFormat;
	swapchainColor = reserveSwapchainTexture(canvas.format, (GPUTextureUsage.RENDER_ATTACHMENT as int32) | (GPUTextureUsage.COPY_SRC as int32));
	swapchainDepth = depthFormat == "" ? 0 : reserveSwapchainTexture(canvas.depthFormat, GPUTextureUsage.RENDER_ATTACHMENT as int32);
	backend.adoptSwapchain(swapchainColor, swapchainDepth);
	return device;
}

function reserveSwapchainTexture(format: GPUTextureFormat, usage: int32): uint32 {
	const textureId = allocate(textureRecords);
	const viewId = allocate(viewRecords);
	store(textureRecords, { id: textureId, format: format, usage: usage, sampleCount: 1, mipLevels: 1, layers: 1, swapchainView: viewId });
	store(viewRecords, { id: viewId, texture: textureId, dimension: "2d", mipCount: 1, layerCount: 1, attachable: true, swapchain: true });
	return textureId;
}

export function destroy(this self: GPUDevice): void {
	checkedShutdown();
	for (const id of querySetRecords.liveIds()) { destroy({ id: id } as GPUQuerySet); }
	for (const id of bindGroupRecords.liveIds()) { destroy({ id: id } as GPUBindGroup); }
	for (const id of pipelineRecords.liveIds()) { destroyPipeline(id); }
	for (const id of shaderRecords.liveIds()) { destroy({ id: id } as GPUShaderModule); }
	for (const id of samplerRecords.liveIds()) { destroy({ id: id } as GPUSampler); }
	for (const id of viewRecords.liveIds()) { discardView(id); }
	for (const id of textureRecords.liveIds()) { discardTexture(id); }
	for (const id of bufferRecords.liveIds()) { destroy({ id: id } as GPUBuffer); }
	backend.shutdown();
	resetEncoder();
}

function discardView(id: uint32): void {
	if (!viewRecords.record(id).swapchain) { backend.destroyView({ id: id }); }
	free(viewRecords, id);
}

function discardTexture(id: uint32): void {
	if (textureRecords.record(id).swapchainView == 0) { backend.destroyTexture({ id: id }); }
	free(textureRecords, id);
}

export function getAdapterInfo(this self: GPUDevice): GPUAdapterInfo { return backend.adapterInfo(); }

@inline export function createBuffer(this self: GPUDevice, descriptor: GPUBufferDescriptor): GPUBuffer {
	checkedBuffer(descriptor.size, descriptor.usage);
	const id = allocate(bufferRecords);
	store(bufferRecords, { id: id, size: descriptor.size, usage: descriptor.usage, writtenFrame: -1 });
	backend.createBuffer(id, descriptor);
	return { id: id };
}

@inline export function createTexture(this self: GPUDevice, descriptor: GPUTextureDescriptor): GPUTexture {
	checkedTexture(descriptor, cachedLimits());
	const id = allocate(textureRecords);
	store(textureRecords, textureRecordOf(id, descriptor));
	backend.createTexture(textureRecords.slots[slotOf(id)], descriptor);
	return { id: id };
}

@inline export function createSampler(this self: GPUDevice, descriptor: GPUSamplerDescriptor): GPUSampler {
	checkedSampler(descriptor);
	const id = allocate(samplerRecords);
	store(samplerRecords, { id: id });
	backend.createSampler(id, descriptor);
	return { id: id };
}

@inline export function createShaderModule(this self: GPUDevice, descriptor: GPUShaderModuleDescriptor): GPUShaderModule {
	checkedShaderModule(descriptor, cachedLimits());
	const id = allocate(shaderRecords);
	store(shaderRecords, { id: id });
	backend.createShaderModule(id, descriptor);
	return { id: id };
}

@inline export function createRenderPipeline(this self: GPUDevice, descriptor: GPURenderPipelineDescriptor): GPURenderPipeline {
	checkedRenderPipeline(descriptor);
	const id = allocate(pipelineRecords);
	store(pipelineRecords, { id: id });
	backend.createRenderPipeline(id, resolvedRenderPipeline(descriptor));
	return { id: id };
}

@inline export function createComputePipeline(this self: GPUDevice, descriptor: GPUComputePipelineDescriptor): GPUComputePipeline {
	const id = allocate(pipelineRecords);
	store(pipelineRecords, { id: id });
	backend.createComputePipeline(id, descriptor);
	return { id: id };
}

@inline export function createBindGroup(this self: GPUDevice, descriptor: GPUBindGroupDescriptor): GPUBindGroup {
	const id = allocate(bindGroupRecords);
	store(bindGroupRecords, { id: id });
	backend.createBindGroup(id, descriptor);
	return { id: id };
}

@inline export function createCommandEncoder(this self: GPUDevice): GPUCommandEncoder {
	checkedCreateEncoder();
	return backend.createCommandEncoder();
}

@inline export function createQuerySet(this self: GPUDevice, descriptor: GPUQuerySetDescriptor): GPUQuerySet {
	checkedQuerySet(descriptor);
	const id = allocate(querySetRecords);
	store(querySetRecords, { id: id });
	backend.createQuerySet(id, descriptor);
	return { id: id };
}

@inline export function limits(this self: GPUDevice): GPUSupportedLimits { return cachedLimits(); }
@inline export function features(this self: GPUDevice): GPUSupportedFeatures { return backend.features(); }
@inline export function has(this self: GPUSupportedFeatures, name: GPUFeatureName): boolean { return (self.bits & featureBit(name)) != 0; }

export function createView(this self: GPUTexture, descriptor: GPUTextureViewDescriptor): GPUTextureView {
	const texture = textureRecords.record(self.id);
	if (texture.swapchainView != 0) { return { id: texture.swapchainView }; }
	const range = checkedViewRange(descriptor, texture.id, texture.mipLevels, texture.layers, texture.volume, texture.cube);
	const id = allocate(viewRecords);
	store(viewRecords, {
		id: id,
		texture: texture.id,
		dimension: range.dimension,
		baseMip: range.baseMip,
		mipCount: range.mipCount,
		baseLayer: range.baseLayer,
		layerCount: range.layerCount,
		attachable: range.mipCount == 1 && range.layerCount == 1,
		swapchain: false,
	});
	backend.createView(viewRecords.slots[slotOf(id)], descriptor);
	return { id: id };
}

@inline export function getBindGroupLayout(this self: GPURenderPipeline, index: int32): GPUBindGroupLayout { return layoutOf(self.id, index); }
@inline export function getBindGroupLayout(this self: GPUComputePipeline, index: int32): GPUBindGroupLayout { return layoutOf(self.id, index); }

function layoutOf(pipeline: uint32, index: int32): GPUBindGroupLayout {
	const p = pipelineRecords.slotIndex(pipeline);
	if (index != GPU_UNIFORM_GROUP && index != GPU_RESOURCE_GROUP) { stop(`getBindGroupLayout index '${index}' is not supported`); }
	if (pipelineRecords.slots[p].layouts[index] == 0) {
		const id = allocate(layoutRecords);
		store(layoutRecords, { id: id, pipeline: pipeline, group: index });
		pipelineRecords.slots[p].layouts[index] = id;
	}
	return { id: pipelineRecords.slots[p].layouts[index] };
}

function destroyPipeline(pipeline: uint32): void {
	const layouts = pipelineRecords.record(pipeline).layouts;
	backend.destroyRenderPipeline({ id: pipeline });
	for (let g = 0; g < 2; g++) { if (layouts[g] != 0) { free(layoutRecords, layouts[g]); } }
	free(pipelineRecords, pipeline);
}

@inline export function destroy(this self: GPUComputePipeline): void { destroyPipeline(self.id); }
@inline export function destroy(this self: GPURenderPipeline): void { destroyPipeline(self.id); }
@inline export function destroy(this self: GPUQuerySet): void {
	backend.destroyQuerySet(self);
	free(querySetRecords, self.id);
}
@inline export function destroy(this self: GPUBuffer): void {
	backend.destroyBuffer(self);
	free(bufferRecords, self.id);
}
@inline export function destroy(this self: GPUTexture): void {
	if (textureRecords.record(self.id).swapchainView != 0) { stop("the swapchain texture belongs to the platform"); }
	backend.destroyTexture(self);
	free(textureRecords, self.id);
}
@inline export function destroy(this self: GPUTextureView): void {
	if (viewRecords.record(self.id).swapchain) { return; }
	backend.destroyView(self);
	free(viewRecords, self.id);
}
@inline export function destroy(this self: GPUSampler): void {
	backend.destroySampler(self);
	free(samplerRecords, self.id);
}
@inline export function destroy(this self: GPUShaderModule): void {
	backend.destroyShaderModule(self);
	free(shaderRecords, self.id);
}
@inline export function destroy(this self: GPUBindGroup): void {
	backend.destroyBindGroup(self);
	free(bindGroupRecords, self.id);
}

@inline export function size(this self: GPUBuffer): int64 { return bufferRecords.record(self.id).size; }
@inline export function width(this self: GPUTexture): int32 { return textureRecords.record(self.id).width; }
@inline export function height(this self: GPUTexture): int32 { return textureRecords.record(self.id).height; }
@inline export function usage(this self: GPUTexture): int32 { return textureRecords.record(self.id).usage; }
@inline export function format(this self: GPUTexture): GPUTextureFormat { return textureRecords.record(self.id).format; }
@inline export function texture(this self: GPUTextureView): GPUTexture { return { id: viewRecords.record(self.id).texture }; }

@inline export function writeBuffer<T>(this self: GPUQueue, buffer: GPUBuffer, bufferOffset: int64, data: Readonly<Span<T>>): void {
	if (data.length == 0) { return; }
	const bytes = (data.length as int64) * (sizeof T as int64);
	const index = bufferRecords.slotIndex(buffer.id);
	checkedWriteBuffer(index, bufferOffset, bytes);
	backend.writeBuffer(buffer, bufferOffset, data);
	markBufferWritten(index, bufferOffset, bytes);
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
	advanceFrame();
}

@inline export function beginRenderPass(this self: GPUCommandEncoder, descriptor: GPURenderPassDescriptor): GPURenderPassEncoder {
	checkedBeginPass(PASS_RENDER);
	attachOcclusionSet(descriptor.occlusionQuerySet.id);
	return backend.beginRenderPass(self, descriptor, checkedRenderPass(descriptor, renderPassFacts(descriptor)));
}

function renderPassFacts(descriptor: GPURenderPassDescriptor): RenderPassFacts {
	let facts: RenderPassFacts = { depth: { texture: 0 } };
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		const attachment = descriptor.colorAttachments[i];
		if (attachment.view.id != 0) { facts.colors[i] = attachmentFacts(attachment.view.id); }
		if (attachment.resolveTarget.id != 0) { facts.resolves[i] = attachmentFacts(attachment.resolveTarget.id); }
	}
	const depth = descriptor.depthStencilAttachment.view;
	if (depth.id != 0) { facts.depth = attachmentFacts(depth.id); }
	return facts;
}

function attachmentFacts(view: uint32): AttachmentFacts {
	const record = viewRecords.record(view);
	return attachmentFactsOf(record, textureRecords.record(record.texture));
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
	checkedDispatch(x, y, z, cachedLimits().maxComputeWorkgroupsPerDimension);
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
	const index = bufferRecords.slotIndex(self.id);
	const record = bufferRecords.slots[index];
	const length = checkedMapAsync(self.id, record.usage, record.mapMode, record.size, mode, offset, size);
	backend.mapAsync(self, mode, offset, length);
	bufferRecords.slots[index].mapMode = mode;
	bufferRecords.slots[index].mapOffset = offset;
	bufferRecords.slots[index].mapSize = length;
}

function mappedLength(member: string, buffer: GPUBuffer, mode: GPUMapMode, offset: int64, size: int64): int64 {
	const record = bufferRecords.record(buffer.id);
	return checkedMappedRange(member, buffer.id, record.size, record.mapMode, record.mapOffset, record.mapSize, mode as int32, offset, size);
}

// A copy of the mapped bytes, not WebGPU's live ArrayBuffer view; a MAP_WRITE buffer takes writeMappedRange instead.
@inline export function getMappedRange(this self: GPUBuffer, offset: int64, size: int64): Vec<uint8> {
	return backend.getMappedRange(self, offset, mappedLength("getMappedRange", self, GPUMapMode.READ, offset, size));
}

@inline export function writeMappedRange<T>(this self: GPUBuffer, offset: int64, data: Readonly<Span<T>>): void {
	if (data.length == 0) { return; }
	mappedLength("writeMappedRange", self, GPUMapMode.WRITE, offset, (data.length as int64) * (sizeof T as int64));
	backend.writeMappedRange(self, offset, data);
}

@inline export function unmap(this self: GPUBuffer): void {
	const index = bufferRecords.slotIndex(self.id);
	checkedUnmap(self.id, bufferRecords.slots[index].mapMode);
	bufferRecords.slots[index].mapMode = 0;
}

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
	checkedViewport(width, height, minDepth, maxDepth);
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
	updateSwapchainTexture(swapchainColor, swapchain);
	if (swapchainDepth != 0) { updateSwapchainTexture(swapchainDepth, swapchain); }
	backend.acquireSwapchain(swapchain);
	return { id: swapchainColor };
}

function updateSwapchainTexture(id: uint32, swapchain: GPUNativeSwapchain): void {
	const t = textureRecords.slotIndex(id);
	textureRecords.slots[t].width = swapchain.width;
	textureRecords.slots[t].height = swapchain.height;
	textureRecords.slots[t].sampleCount = swapchain.sampleCount == 0 ? 1 : swapchain.sampleCount;
}

// The depth attachment the window adds to the canvas; valid after getCurrentTexture this frame.
export function getCurrentDepthTexture(): GPUTexture { return { id: swapchainDepth }; }

export function getCanvasConfiguration(this self: GPUDevice): GPUCanvasConfiguration {
	return cachedCanvas();
}

export function isRenderable(this self: GPUDevice, format: GPUTextureFormat): boolean {
	return backend.formatRenderable(format);
}

export function frameIndex(this self: GPUDevice): uint32 { return (currentFrame() + 1) as uint32; }

export function liveCounts(this self: GPUDevice): GPULiveCounts {
	let counts: GPULiveCounts = { buffers: bufferRecords.live() };
	for (const id of textureRecords.liveIds()) { if (textureRecords.record(id).swapchainView == 0) { counts.textures += 1; } }
	for (const id of viewRecords.liveIds()) { if (!viewRecords.record(id).swapchain) { counts.views += 1; } }
	counts.samplers = samplerRecords.live();
	counts.shaderModules = shaderRecords.live();
	counts.pipelines = pipelineRecords.live();
	return counts;
}

@inline export function isAlive(this self: GPUBuffer): boolean { return bufferRecords.alive(self.id); }
@inline export function isAlive(this self: GPUTexture): boolean { return textureRecords.alive(self.id); }
@inline export function isAlive(this self: GPUTextureView): boolean { return viewRecords.alive(self.id); }
@inline export function isAlive(this self: GPUSampler): boolean { return samplerRecords.alive(self.id); }
