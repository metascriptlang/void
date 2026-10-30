import {
	dx12AdapterDescribe,
	dx12AdapterDescription,
	dx12ClearDepthStencil,
	dx12ClearRenderTarget,
	dx12DepthStencilView,
	dx12DeviceCreate,
	dx12Draw,
	dx12DrawIndexed,
	dx12DrawIndexedSignatureCreate,
	dx12Event,
	dx12ExecuteIndirect,
	dx12FormatSupport,
	dx12InfoDrain,
	dx12QueueCreate,
	dx12Release,
	dx12RenderTargetView,
	dx12ResolveSubresource,
	dx12SetBlendFactor,
	dx12SetIndexBuffer,
	dx12SetPipelineState,
	dx12SetRenderTargets,
	dx12SetScissorRect,
	dx12SetStencilReference,
	dx12SetVertexBuffer,
	dx12SetViewport,
} from "./d3d12.h";
import { formatInfo } from "./conv.ms";
import {
	TextureRecord,
	ViewRecord,
	bindGroupRecords,
	bufferRecords,
	pipelineRecords,
	put,
	slotOf,
	textureRecords,
	vacate,
	viewRecords,
} from "../pool.ms";
import {
	DX12_OK,
	FRAMES_IN_FLIGHT,
	FrameRing,
	NativeError,
	closeFrames,
	closedFrames,
	openFrames,
	retire,
	stop,
	stopOnNative,
	submit as submitFrame,
	waitIdle,
	waitSerial,
} from "./frame.ms";
import * as descriptor from "./descriptor.ms";
import * as resources from "./resources.ms";
import * as pipeline from "./pipeline.ms";
import { SubresourceRange, flushTransitions, transitionRange } from "./tracker.ms";
import { boundFacts, renderPassOpen } from "../validate.ms";
import {
	GPU_MAX_BIND_GROUP_ENTRIES,
	GPU_MAX_COLOR_ATTACHMENTS,
	GPU_MAX_UNIFORM_BLOCKS,
	GPU_MAX_VERTEX_ATTRIBUTES,
	GPU_MAX_VERTEX_BUFFERS,
	GPU_DRAW_INDEXED_INDIRECT_STRIDE,
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
	GPUShaderBinding,
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
const FORMAT_SUPPORT1_RENDER_TARGET: uint32 = 0x4000;
const FORMAT_SUPPORT1_BLENDABLE: uint32 = 0x8000;
const FORMAT_SUPPORT1_DEPTH_STENCIL: uint32 = 0x10000;
const FORMAT_SUPPORT1_SHADER_SAMPLE: uint32 = 0x200;
const STATE_VERTEX_AND_CONSTANT_BUFFER: uint32 = 0x1;
const STATE_INDEX_BUFFER: uint32 = 0x2;
const STATE_RENDER_TARGET: uint32 = 0x4;
const STATE_DEPTH_WRITE: uint32 = 0x10;
const STATE_INDIRECT_ARGUMENT: uint32 = 0x200;
const STATE_RESOLVE_DEST: uint32 = 0x1000;
const STATE_RESOLVE_SOURCE: uint32 = 0x2000;
const DXGI_R16_UINT: int32 = 57;
const DXGI_R32_UINT: int32 = 42;
const VIEW_2D: int32 = 0;
const VIEW_2D_ARRAY: int32 = 1;
const VIEW_3D: int32 = 4;
const CLEAR_DEPTH: int32 = 1;
const CLEAR_STENCIL: int32 = 2;
const EVENT_BEGIN: int32 = 0;
const EVENT_END: int32 = 1;
const EVENT_MARKER: int32 = 2;

export const BACKEND = "d3d12";

let device: uint64 = 0;
let adapter: uint64 = 0;
let queue: uint64 = 0;
let ring: FrameRing = closedFrames();
let r: resources.Resources = resources.closedResources();
let d: descriptor.Descriptors = descriptor.closedDescriptors();
let layouts: Vec<descriptor.PipelineLayout> = [descriptor.NO_LAYOUT];
let encoding = false;
let swapchainColor: uint32 = 0;
let swapchainDepth: uint32 = 0;
let shaders: Vec<pipeline.ShaderNative> = [pipeline.NO_SHADER];
let pipelines: Vec<pipeline.PipelineNative> = [pipeline.NO_PIPELINE];
let drawIndexedSignature: uint64 = 0;

struct PassState {
	colorViews: uint32[GPU_MAX_COLOR_ATTACHMENTS];
	resolveViews: uint32[GPU_MAX_COLOR_ATTACHMENTS];
	labeled: boolean;
	vertexDirty: boolean;
	indexDirty: boolean;
}

struct BufferUse {
	native: uint64;
	address: uint64;
	size: int64;
}

let pass: PassState = { labeled: false };

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
	const heaps = descriptor.openDescriptors(device, FRAMES_IN_FLIGHT);
	if (!heaps.ok) { stopOnFrame("requestDevice", heaps.error); }
	d = heaps.value;
	let signature: uint64 = 0;
	commanded(dx12DrawIndexedSignatureCreate(device, GPU_DRAW_INDEXED_INDIRECT_STRIDE as uint32, signature));
	drawIndexedSignature = signature;
	return { id: 1, queue: { id: 1 } };
}

export function adoptSwapchain(color: uint32, depth: uint32): void {
	swapchainColor = color;
	swapchainDepth = depth;
}

function formatSupport(format: int32): uint32 {
	let support1: uint32 = 0;
	let support2: uint32 = 0;
	commanded(dx12FormatSupport(device, format, support1, support2));
	return support1;
}

export function formatRenderable(format: GPUTextureFormat): boolean {
	const info = formatInfo(format, "formatRenderable format");
	if (info.depth) { return (formatSupport(info.depthStencil) & FORMAT_SUPPORT1_DEPTH_STENCIL) != 0; }
	return (formatSupport(info.renderTarget) & FORMAT_SUPPORT1_RENDER_TARGET) != 0;
}

export function shutdown(): void {
	const closed = closeFrames(ring);
	ring = closedFrames();
	resources.closeResources(r);
	descriptor.closeDescriptors(d);
	for (const layout of layouts) { dx12Release(layout.signature); }
	layouts = [descriptor.NO_LAYOUT];
	for (const native of pipelines) { dx12Release(native.state); }
	pipelines = [pipeline.NO_PIPELINE];
	shaders = [pipeline.NO_SHADER];
	dx12Release(drawIndexedSignature);
	drawIndexedSignature = 0;
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
	descriptor.beginFrame(d, ring);
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
	if (renderPassOpen()) { invalidateBindings(); }
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
	if (renderPassOpen()) { invalidateBindings(); }
}

export function createView(view: ViewRecord, viewDescriptor: GPUTextureViewDescriptor): void {
	ran("createView", descriptor.createView(d, r, view));
}

export function destroyView(view: GPUTextureView): void {
	descriptor.destroyView(d, ring, view.id);
}

export function viewDescriptor(view: GPUTextureView): uint64 { return d.viewHandle(view.id); }

export function acquireSwapchain(swapchain: NativeSwapchain): void {
	notBuilt("acquireSwapchain", "D5");
}

export function createSampler(id: uint32, samplerDescriptor: GPUSamplerDescriptor): void {
	ran("createSampler", descriptor.createSampler(d, id, samplerDescriptor));
}

export function destroySampler(sampler: GPUSampler): void {
	descriptor.destroySampler(d, sampler.id);
}

export function samplerDescriptor(sampler: GPUSampler): uint64 { return d.samplerHandle(sampler.id); }

export function createShaderModule(id: uint32, descriptor: GPUShaderModuleDescriptor): void {
	pipeline.createShaderModule(shaders, id, descriptor);
}

export function destroyShaderModule(module: GPUShaderModule): void {
	pipeline.destroyShaderModule(shaders, module.id);
}

export function createRenderPipeline(id: uint32, descriptor: GPURenderPipelineDescriptor): void {
	const shader = shaders[slotOf(descriptor.vertex.module.id)];
	adoptPipelineLayout(id, shader.bindings, false);
	ran("createRenderPipeline", pipeline.createRenderPipeline(pipelines, device, layouts[slotOf(id)].signature, shader, id, descriptor));
}

export function destroyRenderPipeline(destroyed: GPURenderPipeline): void {
	retire(ring, pipelines[slotOf(destroyed.id)].state);
	vacate(pipelines, destroyed.id);
	releasePipelineLayout(destroyed.id);
}

export function adoptPipelineLayout(pipeline: uint32, bindings: Readonly<Span<GPUShaderBinding>>, compute: boolean): void {
	const layout = descriptor.createPipelineLayout(d, bindings, compute);
	if (!layout.ok) { stopOnFrame("createPipelineLayout", layout.error); }
	put(layouts, pipeline, layout.value);
}

export function releasePipelineLayout(pipeline: uint32): void {
	retire(ring, layouts[slotOf(pipeline)].signature);
	vacate(layouts, pipeline);
}

export function createBindGroup(id: uint32, groupDescriptor: GPUBindGroupDescriptor): void {
	const pipeline = bindGroupRecords.record(id).pipeline;
	const layout = layouts[slotOf(pipeline)];
	if (layout.signature == 0) { stop(`createBindGroup: pipeline ${pipeline} has no d3d12 root signature`); }
	ran("createBindGroup", descriptor.createGroup(d, r, id, layout.shader, groupDescriptor));
}

export function destroyBindGroup(bindGroup: GPUBindGroup): void {
	descriptor.destroyGroup(d, ring, bindGroup.id);
}

export function applyBindings(pipeline: uint32): void {
	ran("applyBindings", descriptor.applyBindings(d, r, ring, layouts[slotOf(pipeline)]));
}

export function descriptorStats(): descriptor.DescriptorStats { return d.stats(); }

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

export function beginRenderPass(encoder: GPUCommandEncoder, passDescriptor: GPURenderPassDescriptor, extent: GPUExtent3D): GPURenderPassEncoder {
	if (passDescriptor.timestampWrites.querySet.id != 0 || passDescriptor.occlusionQuerySet.id != 0) {
		notBuilt("a render pass with timestampWrites or occlusionQuerySet", "D6");
	}
	pass = { labeled: passDescriptor.label != null };
	let targets: uint64[GPU_MAX_COLOR_ATTACHMENTS] = [0];
	let targetCount: int32 = 0;
	for (let i: int32 = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		const attachment = passDescriptor.colorAttachments[i];
		if (attachment.view.id == 0) { continue; }
		checkStoreOp(attachment.storeOp, i, "storeOp");
		targets[i] = attachmentTarget(attachment.view.id, attachment.depthSlice, false);
		targetCount = i + 1;
		pass.colorViews[i] = attachment.view.id;
		pass.resolveViews[i] = attachment.resolveTarget.id;
	}
	const depthAttachment = passDescriptor.depthStencilAttachment;
	let depth: uint64 = 0;
	let stencil = false;
	if (depthAttachment.view.id != 0) {
		stencil = r.textures[textureRecords.slotIndex(viewRecords.record(depthAttachment.view.id).texture)].info.stencil;
		checkStoreOp(depthAttachment.depthStoreOp, -1, "depthStoreOp");
		if (stencil) { checkStoreOp(depthAttachment.stencilStoreOp, -1, "stencilStoreOp"); }
		depth = attachmentTarget(depthAttachment.view.id, 0, true);
	}
	commanded(flushTransitions(r.tracker, ring.list));
	commanded(dx12SetRenderTargets(ring.list, targets[0], targetCount as uint32, depth));
	for (let i: int32 = 0; i < targetCount; i++) {
		if (pass.colorViews[i] == 0 || !isClear(passDescriptor.colorAttachments[i].loadOp, i, "loadOp")) { continue; }
		const color = passDescriptor.colorAttachments[i].clearValue;
		commanded(dx12ClearRenderTarget(ring.list, targets[i], color.r, color.g, color.b, color.a));
	}
	if (depth != 0) {
		const clearDepth = isClear(depthAttachment.depthLoadOp, -1, "depthLoadOp");
		const clearStencil = stencil && isClear(depthAttachment.stencilLoadOp, -1, "stencilLoadOp");
		const flags = (clearDepth ? CLEAR_DEPTH : 0) | (clearStencil ? CLEAR_STENCIL : 0);
		if (flags != 0) {
			commanded(dx12ClearDepthStencil(ring.list, depth, flags, depthAttachment.depthClearValue as float64, depthAttachment.stencilClearValue & 0xFF));
		}
	}
	commanded(dx12SetViewport(ring.list, 0.0, 0.0, extent.width as float64, extent.height as float64, 0.0, 1.0));
	commanded(dx12SetScissorRect(ring.list, 0, 0, extent.width, extent.height));
	commanded(dx12SetBlendFactor(ring.list, 0.0, 0.0, 0.0, 0.0));
	commanded(dx12SetStencilReference(ring.list, 0));
	invalidateBindings();
	const label = passDescriptor.label;
	if (label != null) { commanded(dx12Event(ring.list, EVENT_BEGIN, label)); }
	return { id: 1 };
}

function invalidateBindings(): void {
	d.bound.signature = 0;
	pass.vertexDirty = true;
	pass.indexDirty = true;
}

@noinline function stopOnSwapchainPass(view: uint32): never {
	notBuilt(`a render pass on swapchain GPUTextureView ${view}`, "D5");
}

function attachmentTarget(view: uint32, depthSlice: int32, depthStencil: boolean): uint64 {
	const record = viewRecords.record(view);
	if (record.swapchain || record.texture == swapchainColor || record.texture == swapchainDepth) { stopOnSwapchainPass(view); }
	const t = textureRecords.slotIndex(record.texture);
	const texture = textureRecords.slots[t];
	const native = r.textures[t];
	const dimension = texture.volume ? VIEW_3D : (texture.layers > 1 ? VIEW_2D_ARRAY : VIEW_2D);
	const layer = texture.volume ? depthSlice : record.baseLayer;
	const multisampled = texture.sampleCount > 1 ? 1 : 0;
	const range: SubresourceRange = { baseMip: record.baseMip, mips: 1, baseLayer: texture.volume ? 0 : record.baseLayer, layers: 1 };
	if (depthStencil) {
		const handle = descriptor.depthStencilHandle(d, ring);
		if (!handle.ok) { stopOnFrame("beginRenderPass", handle.error); }
		commanded(dx12DepthStencilView(device, native.native, native.info.depthStencil, dimension, multisampled, record.baseMip as uint32, layer as uint32, handle.value));
		transitionRange(r.tracker, native.tracked, STATE_DEPTH_WRITE, range);
		return handle.value;
	}
	const handle = descriptor.renderTargetHandle(d, ring);
	if (!handle.ok) { stopOnFrame("beginRenderPass", handle.error); }
	commanded(dx12RenderTargetView(device, native.native, native.info.renderTarget, dimension, multisampled, record.baseMip as uint32, layer as uint32, handle.value));
	transitionRange(r.tracker, native.tracked, STATE_RENDER_TARGET, range);
	return handle.value;
}

function attachmentMember(index: int32, field: string): string {
	return index < 0 ? `depthStencilAttachment.${field}` : `colorAttachments[${index}].${field}`;
}

@noinline function stopOnAttachment(index: int32, field: string, value: string): never {
	stop(`GPURenderPassDescriptor ${attachmentMember(index, field)} '${value}' is not supported`);
}

function isClear(loadOp: string, index: int32, field: string): boolean {
	return match (loadOp) {
		"clear" => true,
		"load" => false,
		_ => stopOnAttachment(index, field, loadOp),
	};
}

function checkStoreOp(storeOp: string, index: int32, field: string): void {
	if (storeOp != "store" && storeOp != "discard") { stopOnAttachment(index, field, storeOp); }
}

function subresourceOf(view: ViewRecord, texture: TextureRecord): uint32 {
	return (view.baseMip + view.baseLayer * texture.mipLevels) as uint32;
}

function resolveRange(view: ViewRecord): SubresourceRange {
	return { baseMip: view.baseMip, mips: 1, baseLayer: view.baseLayer, layers: 1 };
}

export function endPass(): void {
	for (let i: int32 = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		if (pass.resolveViews[i] == 0) { continue; }
		const sourceView = viewRecords.record(pass.colorViews[i]);
		const targetView = viewRecords.record(pass.resolveViews[i]);
		if (targetView.swapchain || targetView.texture == swapchainColor) { stopOnSwapchainPass(pass.resolveViews[i]); }
		const s = textureRecords.slotIndex(sourceView.texture);
		const t = textureRecords.slotIndex(targetView.texture);
		transitionRange(r.tracker, r.textures[s].tracked, STATE_RESOLVE_SOURCE, resolveRange(sourceView));
		transitionRange(r.tracker, r.textures[t].tracked, STATE_RESOLVE_DEST, resolveRange(targetView));
		commanded(flushTransitions(r.tracker, ring.list));
		commanded(dx12ResolveSubresource(
			ring.list,
			r.textures[t].native,
			subresourceOf(targetView, textureRecords.slots[t]),
			r.textures[s].native,
			subresourceOf(sourceView, textureRecords.slots[s]),
			r.textures[s].info.renderTarget,
		));
	}
	if (pass.labeled) { commanded(dx12Event(ring.list, EVENT_END, "")); }
	pass = { labeled: false };
}

export function setPipeline(bound: GPURenderPipeline): void {
	const native = pipelines[slotOf(bound.id)];
	commanded(dx12SetPipelineState(ring.list, native.state, native.topology));
	pass.vertexDirty = true;
}

export function setVertexBuffer(slot: int32, buffer: GPUBuffer, offset: int64): void {
	pass.vertexDirty = true;
}

export function setIndexBuffer(buffer: GPUBuffer, format: GPUIndexFormat, offset: int64): void {
	pass.indexDirty = true;
}

export function setBindGroup(index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void {
	descriptor.setGroup(d, index, bindGroup.id, dynamicOffsets);
}

export function setScissorRect(x: int32, y: int32, width: int32, height: int32): void {
	commanded(dx12SetScissorRect(ring.list, x, y, x + width, y + height));
}

export function setViewport(x: float32, y: float32, width: float32, height: float32, minDepth: float32, maxDepth: float32): void {
	commanded(dx12SetViewport(ring.list, x as float64, y as float64, width as float64, height as float64, minDepth as float64, maxDepth as float64));
}

export function setBlendConstant(color: GPUColor): void {
	commanded(dx12SetBlendFactor(ring.list, color.r, color.g, color.b, color.a));
}

export function setStencilReference(reference: uint32): void {
	commanded(dx12SetStencilReference(ring.list, reference));
}

export function draw(vertexCount: int32, instanceCount: int32, firstVertex: int32, firstInstance: int32): void {
	if (instanceCount == 0) { return; }
	prepareDraw(false);
	commanded(dx12Draw(ring.list, vertexCount as uint32, instanceCount as uint32, firstVertex as uint32, firstInstance as uint32));
}

function usedBuffer(id: uint32, state: uint32): BufferUse {
	const b = bufferRecords.slotIndex(id);
	resources.useBuffer(r, id, b, state);
	r.buffers[b].lastUse = ring.recording();
	return { native: r.buffers[b].native, address: r.buffers[b].address, size: bufferRecords.slots[b].size };
}

function prepareDraw(indexed: boolean): void {
	const p = slotOf(boundFacts.pipeline);
	if (pass.vertexDirty) {
		const slots = pipelineRecords.record(boundFacts.pipeline).vertexSlots;
		for (let slot: int32 = 0; slot < GPU_MAX_VERTEX_BUFFERS; slot++) {
			if ((slots & (1 << slot)) == 0) { continue; }
			const used = usedBuffer(boundFacts.vertexBuffers[slot], STATE_VERTEX_AND_CONSTANT_BUFFER);
			const offset = boundFacts.vertexOffsets[slot];
			commanded(dx12SetVertexBuffer(ring.list, slot as uint32, used.address + (offset as uint64), (used.size - offset) as uint32, pipelines[p].strides[slot] as uint32));
		}
		pass.vertexDirty = false;
	}
	if (indexed && pass.indexDirty) {
		const used = usedBuffer(boundFacts.indexBuffer, STATE_INDEX_BUFFER);
		const offset = boundFacts.indexOffset;
		commanded(dx12SetIndexBuffer(ring.list, used.address + (offset as uint64), (used.size - offset) as uint32, indexFormat(boundFacts.indexFormat)));
		pass.indexDirty = false;
	}
	applyBindings(boundFacts.pipeline);
	commanded(flushTransitions(r.tracker, ring.list));
}

@noinline function stopOnIndexFormat(format: string): never {
	stop(`GPUIndexFormat '${format}' is not supported`);
}

function indexFormat(format: GPUIndexFormat): int32 {
	const value: string = format;
	return match (value) {
		"uint16" => DXGI_R16_UINT,
		"uint32" => DXGI_R32_UINT,
		_ => stopOnIndexFormat(value),
	};
}

export function drawIndexed(indexCount: int32, instanceCount: int32, firstIndex: int32, baseVertex: int32, firstInstance: int32): void {
	if (instanceCount == 0) { return; }
	prepareDraw(true);
	commanded(dx12DrawIndexed(ring.list, indexCount as uint32, instanceCount as uint32, firstIndex as uint32, baseVertex, firstInstance as uint32));
}

export function multiDrawIndexedIndirect(buffer: GPUBuffer, offset: int64, drawCount: int32): void {
	if (drawCount == 0) { return; }
	const used = usedBuffer(buffer.id, STATE_INDIRECT_ARGUMENT);
	prepareDraw(true);
	commanded(dx12ExecuteIndirect(ring.list, drawIndexedSignature, drawCount as uint32, used.native, offset as uint64));
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

function sampledSupport(format: GPUTextureFormat): uint32 {
	return formatSupport(formatInfo(format, "features format").shaderResource);
}

export function features(): GPUSupportedFeatures {
	let bits: uint32 = 0;
	const float32 = sampledSupport("r32float") & sampledSupport("rg32float") & sampledSupport("rgba32float");
	if ((float32 & FORMAT_SUPPORT1_SHADER_SAMPLE) != 0) { bits |= featureBit("float32-filterable"); }
	if ((float32 & FORMAT_SUPPORT1_BLENDABLE) != 0) { bits |= featureBit("float32-blendable"); }
	if ((sampledSupport("rg11b10ufloat") & FORMAT_SUPPORT1_RENDER_TARGET) != 0) { bits |= featureBit("rg11b10ufloat-renderable"); }
	bits |= featureBit("indirect-first-instance");
	return { bits: bits };
}

export function pushDebugGroup(label: string): void {
	commanded(dx12Event(ring.list, EVENT_BEGIN, label));
}

export function popDebugGroup(): void {
	commanded(dx12Event(ring.list, EVENT_END, ""));
}

export function insertDebugMarker(label: string): void {
	commanded(dx12Event(ring.list, EVENT_MARKER, label));
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
