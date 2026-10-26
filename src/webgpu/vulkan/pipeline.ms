import {
	vulkanCmdBindIndexBuffer,
	vulkanCmdBindPipeline,
	vulkanCmdBindSet,
	vulkanCmdBindVertexBuffer,
	vulkanCmdBlendConstants,
	vulkanCmdDispatch,
	vulkanCmdDispatchIndirect,
	vulkanCmdDraw,
	vulkanCmdDrawIndexed,
	vulkanCmdScissor,
	vulkanCmdStencilReference,
	vulkanCmdViewport,
	vulkanComputePipelineCreate,
	vulkanDescriptorSetWrite,
	vulkanRecordingSerial,
	vulkanRenderPassCreate,
	vulkanRenderPipelineCreate,
	vulkanShaderModuleCreate,
} from "./vulkan.h";
import {
	ACCESS_SHADER_READ,
	ACCESS_SHADER_WRITE,
	ASPECT_STENCIL,
	DESCRIPTOR_SAMPLED_IMAGE,
	DESCRIPTOR_SAMPLER,
	DESCRIPTOR_STORAGE_BUFFER,
	DESCRIPTOR_STORAGE_IMAGE,
	DESCRIPTOR_UNIFORM_BUFFER_DYNAMIC,
	LAYOUT_GENERAL,
	LAYOUT_SHADER_READ_ONLY,
	LOAD_OP_DONT_CARE,
	LOAD_OP_LOAD,
	STAGE_COMPUTE_SHADER,
	STORE_OP_DONT_CARE,
	STORE_OP_STORE,
	blendOp,
	cullMode,
	destinationFactor,
	formatInfo,
	frontFace,
	indexType,
	inputRate,
	pipelineCompare,
	shaderStages,
	sourceFactor,
	stencilOp,
	topology,
	vertexFormat,
} from "./conv";
import { NO_SET, SetAllocation, allocateSet, deallocateSet, pipelineLayoutFor, setLayoutIndex } from "./descriptor";
import {
	RenderPassCache,
	cachedPass,
	colorKeyWords,
	depthKeyWords,
	newPassKey,
	noDepthKeyWords,
	rememberPass,
	unusedColorKeyWords,
} from "./pass";
import { readFromBuffer, readFromTexture, writeToBuffer, writeToTexture } from "./tracker";
import {
	NO_ALLOCATION,
	ResourceError,
	RetiredKind,
	VULKAN_OK,
	VulkanResources,
	checked,
	failure,
	flush,
	retire,
	stopOnVulkan,
} from "./resources";
import {
	BindingKind,
	GPUBindGroupDescriptor,
	GPUBindGroupEntry,
	GPUBuffer,
	GPUBufferUsage,
	GPUColor,
	GPUComputePipelineDescriptor,
	GPUIndexFormat,
	GPURenderPipelineDescriptor,
	GPUShaderBinding,
	GPUShaderModuleDescriptor,
	GPUStencilFaceState,
	GPUTextureViewDimension,
	GPU_MAX_BIND_GROUP_ENTRIES,
	GPU_MAX_COLOR_ATTACHMENTS,
	GPU_MAX_SHADER_BINDINGS,
	GPU_MAX_VERTEX_ATTRIBUTES,
	GPU_MAX_VERTEX_BUFFERS,
	GPU_RESOURCE_GROUP,
	GPU_UNIFORM_GROUP,
	bindingKind,
	stop,
	stopOnUnportedShaderBindings,
} from "../types.ms";
import { boundFacts, checkedComputeModule, checkedRenderModule, colorWriteBits, entryBytes, isStripTopology, stencilMask } from "../validate.ms";
import {
	bindGroupRecords,
	bufferRecords,
	layoutRecords,
	pipelineRecords,
	put,
	slotOf,
	vacate,
	viewRecords,
} from "../pool.ms";

@passC("-I../../../deps/vulkan-headers/include");

// Parked at ~/metascript/.inbox/compiler/2026-10-26-struct-field-array-size-const-chain.md: GPU_RESOURCE_GROUP + 1.
const GROUPS: int32 = 2;
const VERTEX_BUFFER_WORDS: int32 = 3;
const VERTEX_ATTRIBUTE_WORDS: int32 = 4;
const COLOR_TARGET_WORDS: int32 = 8;
const RENDER_STATE_WORDS: int32 = 20;
const BLEND_ONE: uint32 = 1;
const BLEND_OP_ADD: uint32 = 0;

struct ShaderBinding {
	group: int32;
	binding: int32;
	kind: BindingKind;
	stages: uint32;
	writable: boolean;
	size: int32;
	viewDimension: GPUTextureViewDimension;
}

struct ShaderNative {
	compute: boolean;
	vertexOrCompute: uint64;
	fragment: uint64;
	vertexEntry: string;
	fragmentEntry: string;
	computeEntry: string;
	bindings: ShaderBinding[GPU_MAX_SHADER_BINDINGS];
	bindingCount: int32;
	sets: int32[GROUPS];
	layout: uint64;
}

struct PipelineNative {
	native: uint64;
	layout: uint64;
}

struct GroupAccess {
	kind: BindingKind;
	writable: boolean;
	id: uint32;
}

struct BindGroupNative {
	allocation: SetAllocation;
	accesses: GroupAccess[GPU_MAX_BIND_GROUP_ENTRIES];
	accessCount: int32;
}

struct Bound {
	compute: boolean;
	appliedLayout: uint64;
	dirty: boolean[GROUPS];
}

export struct VulkanPipelines {
	shaders: Vec<ShaderNative>;
	pipelines: Vec<PipelineNative>;
	bindGroups: Vec<BindGroupNative>;
	bound: Bound;
}

@inline function has(flags: int32, flag: int32): boolean { return (flags & flag) != 0; }

export function openPipelines(): VulkanPipelines {
	if (GROUPS != GPU_RESOURCE_GROUP + 1) { stop(`vulkan: GROUPS is ${GROUPS}, the bind groups are ${GPU_RESOURCE_GROUP + 1}`); }
	return {
		shaders: [{ compute: false }],
		pipelines: [{ native: 0, layout: 0 }],
		bindGroups: [{ allocation: NO_SET }],
		bound: { compute: false },
	};
}

function bindingWritable(binding: GPUShaderBinding): boolean {
	const kind: string = binding.kind;
	if (kind == "storage-buffer") {
		const bufferType: string = binding.bufferType;
		if (bufferType == "storage") { return true; }
		if (bufferType == "read-only-storage") { return false; }
		stop(`vulkan: GPUShaderBinding.bufferType '${bufferType}' is not a storage type`);
	}
	if (kind == "storage-texture") {
		const access: string = binding.storageAccess;
		if (access == "write-only" || access == "read-write") { return true; }
		if (access == "read-only") { return false; }
		stop(`vulkan: GPUShaderBinding.storageAccess '${access}' is not supported`);
	}
	return false;
}

function descriptorType(kind: BindingKind): uint32 {
	return match (kind) {
		BindingKind.Uniform => DESCRIPTOR_UNIFORM_BUFFER_DYNAMIC,
		BindingKind.Texture => DESCRIPTOR_SAMPLED_IMAGE,
		BindingKind.Sampler => DESCRIPTOR_SAMPLER,
		BindingKind.StorageBuffer => DESCRIPTOR_STORAGE_BUFFER,
		BindingKind.StorageTexture => DESCRIPTOR_STORAGE_IMAGE,
	};
}

@noinline function refuseRenderStorage(binding: int32): never {
	stop(`vulkan: shader binding ${binding} is writable storage or a storage texture in a render stage, which the vulkan backend does not track inside a render pass yet`);
}

@noinline function refuseText(stage: string): never {
	stop(`vulkan: GPUShaderModuleDescriptor.${stage}Code is text; Vulkan takes SPIR-V in ${stage}Bytecode`);
}

function module(code: string, bytes: Vec<uint8>, stage: string): Result<uint64, ResourceError> {
	if (bytes.length == 0) {
		if (code != "") { refuseText(stage); }
		return Result.ok(0 as uint64);
	}
	let native: uint64 = 0;
	try checked(vulkanShaderModuleCreate(bytes[0], bytes.length as uint64, native));
	return Result.ok(native);
}

function entryName(name: string): string { return name == "" ? "main" : name; }

function sortedBindings(ref shader: ShaderNative): void {
	for (let i = 1; i < shader.bindingCount; i++) {
		const moving = shader.bindings[i];
		let j = i - 1;
		while (j >= 0 && shader.bindings[j].binding > moving.binding) {
			shader.bindings[j + 1] = shader.bindings[j];
			j -= 1;
		}
		shader.bindings[j + 1] = moving;
	}
}

function setKey(shader: ShaderNative, group: int32): Vec<uint32> {
	let key: Vec<uint32> = [];
	for (let i = 0; i < shader.bindingCount; i++) {
		if (shader.bindings[i].group != group) { continue; }
		key.push(shader.bindings[i].binding as uint32);
		key.push(descriptorType(shader.bindings[i].kind));
		key.push(shader.bindings[i].stages);
	}
	return key;
}

function retireModules(ref r: VulkanResources, shader: ShaderNative): void {
	if (shader.vertexOrCompute != 0) { retire(r, RetiredKind.Shader, shader.vertexOrCompute, NO_ALLOCATION); }
	if (shader.fragment != 0) { retire(r, RetiredKind.Shader, shader.fragment, NO_ALLOCATION); }
}

export function createShaderModule(
	ref p: VulkanPipelines,
	ref r: VulkanResources,
	id: uint32,
	descriptor: GPUShaderModuleDescriptor,
): Result<void, ResourceError> {
	stopOnUnportedShaderBindings("vulkan", descriptor);
	const compute = descriptor.computeCode != "" || descriptor.computeBytecode.length > 0;
	let shader: ShaderNative = { compute: compute };
	for (let i = 0; i < GPU_MAX_SHADER_BINDINGS; i++) {
		const kindName: string = descriptor.bindings[i].kind;
		if (kindName == "") { continue; }
		const binding: ShaderBinding = {
			group: descriptor.bindings[i].group,
			binding: descriptor.bindings[i].binding,
			kind: bindingKind(kindName, "vulkan"),
			stages: shaderStages(descriptor.bindings[i].visibility),
			writable: bindingWritable(descriptor.bindings[i]),
			size: descriptor.bindings[i].size,
			viewDimension: descriptor.bindings[i].viewDimension,
		};
		if (!compute && (binding.writable || binding.kind == BindingKind.StorageTexture)) { refuseRenderStorage(binding.binding); }
		shader.bindings[shader.bindingCount] = binding;
		shader.bindingCount += 1;
	}
	sortedBindings(shader);
	for (let g = 0; g < GROUPS; g++) {
		const key = setKey(shader, g);
		const status = setLayoutIndex(r.descriptors, key, shader.sets[g]);
		if (status != VULKAN_OK) { return Result.err(failure(status)); }
	}
	const layout = pipelineLayoutFor(
		r.descriptors,
		r.descriptors.setLayoutNative(shader.sets[GPU_UNIFORM_GROUP]),
		r.descriptors.setLayoutNative(shader.sets[GPU_RESOURCE_GROUP]),
		shader.layout,
	);
	if (layout != VULKAN_OK) { return Result.err(failure(layout)); }
	if (compute) {
		shader.computeEntry = entryName(descriptor.computeEntryPoint);
		shader.vertexOrCompute = try module(descriptor.computeCode, descriptor.computeBytecode, "compute");
		if (shader.vertexOrCompute == 0) { stop("vulkan: a compute GPUShaderModule needs computeBytecode"); }
	} else {
		shader.vertexEntry = entryName(descriptor.vertexEntryPoint);
		shader.fragmentEntry = entryName(descriptor.fragmentEntryPoint);
		shader.vertexOrCompute = try module(descriptor.vertexCode, descriptor.vertexBytecode, "vertex");
		if (shader.vertexOrCompute == 0) { stop("vulkan: a render GPUShaderModule needs vertexBytecode"); }
		const fragment = module(descriptor.fragmentCode, descriptor.fragmentBytecode, "fragment");
		if (!fragment.ok) {
			retireModules(r, shader);
			return Result.err(fragment.error);
		}
		shader.fragment = fragment.value;
	}
	put(p.shaders, id, shader);
	return Result.ok(null);
}

export function destroyShaderModule(ref p: VulkanPipelines, ref r: VulkanResources, id: uint32): void {
	retireModules(r, p.shaders[slotOf(id)]);
	vacate(p.shaders, id);
}

function colorTargetWords(ref words: Vec<uint32>, descriptor: GPURenderPipelineDescriptor, i: int32): void {
	const target = descriptor.fragment.targets[i];
	const member = `fragment.targets[${i}]`;
	words.push(target.blendEnabled ? 1 : 0);
	words.push(sourceFactor(target.blend.color.srcFactor, `${member}.blend.color.srcFactor`));
	words.push(destinationFactor(target.blend.color.dstFactor, `${member}.blend.color.dstFactor`));
	words.push(blendOp(target.blend.color.operation, `${member}.blend.color.operation`));
	words.push(sourceFactor(target.blend.alpha.srcFactor, `${member}.blend.alpha.srcFactor`));
	words.push(destinationFactor(target.blend.alpha.dstFactor, `${member}.blend.alpha.dstFactor`));
	words.push(blendOp(target.blend.alpha.operation, `${member}.blend.alpha.operation`));
	words.push(colorWriteBits(target.writeMask) as uint32);
}

function unusedTargetWords(ref words: Vec<uint32>): void {
	words.push(0);
	words.push(BLEND_ONE);
	words.push(0);
	words.push(BLEND_OP_ADD);
	words.push(BLEND_ONE);
	words.push(0);
	words.push(BLEND_OP_ADD);
	words.push(0);
}

function stencilFaceWords(ref words: Vec<uint32>, face: GPUStencilFaceState, member: string): void {
	words.push(stencilOp(face.failOp, `${member}.failOp`));
	words.push(stencilOp(face.passOp, `${member}.passOp`));
	words.push(stencilOp(face.depthFailOp, `${member}.depthFailOp`));
	words.push(pipelineCompare(face.compare, `${member}.compare`));
}

function stateWords(descriptor: GPURenderPipelineDescriptor, depth: boolean, stencil: boolean): Vec<uint32> {
	const strip = isStripTopology(descriptor.primitive.topology);
	const ds = descriptor.depthStencil;
	let words: Vec<uint32> = [];
	words.push(topology(descriptor.primitive.topology));
	words.push(strip ? 1 : 0);
	words.push(cullMode(descriptor.primitive.cullMode));
	words.push(frontFace(descriptor.primitive.frontFace));
	words.push(descriptor.multisample.count as uint32);
	words.push(depth ? 1 : 0);
	words.push(depth && ds.depthWriteEnabled ? 1 : 0);
	words.push(pipelineCompare(ds.depthCompare, "depthStencil.depthCompare"));
	words.push(stencil ? 1 : 0);
	stencilFaceWords(words, ds.stencilFront, "depthStencil.stencilFront");
	stencilFaceWords(words, ds.stencilBack, "depthStencil.stencilBack");
	words.push(stencilMask(ds.stencilReadMask));
	words.push(stencilMask(ds.stencilWriteMask));
	words.push(ds.depthBias as uint32);
	if (words.length != RENDER_STATE_WORDS) { stop(`vulkan: render state has ${words.length} words, not ${RENDER_STATE_WORDS}`); }
	return words;
}

function vertexWords(descriptor: GPURenderPipelineDescriptor, ref bufferCount: uint32, ref attributeCount: uint32): Vec<uint32> {
	let buffers: Vec<uint32> = [];
	let attributes: Vec<uint32> = [];
	for (let b = 0; b < GPU_MAX_VERTEX_BUFFERS; b++) {
		const layout = descriptor.vertex.buffers[b];
		let used = false;
		for (let a = 0; a < GPU_MAX_VERTEX_ATTRIBUTES; a++) {
			const attribute = layout.attributes[a];
			const format: string = attribute.format;
			if (format == "") { continue; }
			attributes.push(attribute.shaderLocation as uint32);
			attributes.push(b as uint32);
			attributes.push(vertexFormat(attribute.format, `vertex.buffers[${b}].attributes[${a}].format`));
			attributes.push(attribute.offset as uint32);
			used = true;
		}
		if (!used) { continue; }
		buffers.push(b as uint32);
		buffers.push(layout.arrayStride as uint32);
		buffers.push(inputRate(layout.stepMode, `vertex.buffers[${b}].stepMode`));
	}
	bufferCount = (buffers.length / VERTEX_BUFFER_WORDS) as uint32;
	attributeCount = (attributes.length / VERTEX_ATTRIBUTE_WORDS) as uint32;
	for (const word of attributes) { buffers.push(word); }
	buffers.push(0);
	return buffers;
}

// Vulkan render pass compatibility ignores load and store ops, so any pass with these formats,
// sample counts and holes takes the pipeline.
function compatiblePass(
	ref r: VulkanResources,
	ref cache: RenderPassCache,
	descriptor: GPURenderPipelineDescriptor,
	ref targets: Vec<uint32>,
	ref depth: boolean,
	ref stencil: boolean,
): Result<uint64, ResourceError> {
	const samples = descriptor.multisample.count;
	let key = newPassKey();
	let colors = 0;
	for (let i = 0; i < GPU_MAX_COLOR_ATTACHMENTS; i++) {
		const format: string = descriptor.fragment.targets[i].format;
		if (format != "") { colors = i + 1; }
	}
	for (let i = 0; i < colors; i++) {
		const format: string = descriptor.fragment.targets[i].format;
		if (format == "") {
			unusedColorKeyWords(key);
			unusedTargetWords(targets);
			continue;
		}
		const info = formatInfo(descriptor.fragment.targets[i].format, r.depthStencil, `fragment.targets[${i}].format`);
		if (info.depth) { stop(`fragment.targets[${i}].format is a depth format`); }
		colorKeyWords(key, info.native, samples, LOAD_OP_LOAD, STORE_OP_STORE, 0);
		colorTargetWords(targets, descriptor, i);
	}
	const depthFormat: string = descriptor.depthStencil.format;
	if (depthFormat != "") {
		const info = formatInfo(descriptor.depthStencil.format, r.depthStencil, "depthStencil.format");
		if (!info.depth) { stop("depthStencil.format is not a depth format"); }
		depth = true;
		stencil = (info.aspect & ASPECT_STENCIL) != 0;
		depthKeyWords(
			key,
			info.native,
			samples,
			LOAD_OP_LOAD,
			STORE_OP_STORE,
			stencil ? LOAD_OP_LOAD : LOAD_OP_DONT_CARE,
			stencil ? STORE_OP_STORE : STORE_OP_DONT_CARE,
			false,
		);
	} else {
		noDepthKeyWords(key);
	}
	if (targets.length == 0) { targets.push(0); }
	let native = cache.cachedPass(key);
	if (native == 0) {
		try checked(vulkanRenderPassCreate(key[0], key.length as uint32, native));
		rememberPass(cache, key, native);
	}
	return Result.ok(native);
}

export function createRenderPipeline(
	ref p: VulkanPipelines,
	ref r: VulkanResources,
	ref cache: RenderPassCache,
	id: uint32,
	descriptor: GPURenderPipelineDescriptor,
): Result<void, ResourceError> {
	const shader = p.shaders[slotOf(descriptor.vertex.module.id)];
	checkedRenderModule(shader.compute);
	let targets: Vec<uint32> = [];
	let depth = false;
	let stencil = false;
	const renderPass = try compatiblePass(r, cache, descriptor, targets, depth, stencil);
	const state = stateWords(descriptor, depth, stencil);
	let bufferCount: uint32 = 0;
	let attributeCount: uint32 = 0;
	const vertex = vertexWords(descriptor, bufferCount, attributeCount);
	let native: uint64 = 0;
	try checked(vulkanRenderPipelineCreate(
		shader.layout,
		renderPass,
		shader.vertexOrCompute,
		shader.vertexEntry,
		shader.fragment,
		shader.fragmentEntry,
		state[0],
		vertex[0],
		bufferCount,
		attributeCount,
		targets[0],
		(targets.length / COLOR_TARGET_WORDS) as uint32,
		descriptor.depthStencil.depthBiasSlopeScale,
		descriptor.depthStencil.depthBiasClamp,
		native,
	));
	put(p.pipelines, id, { native: native, layout: shader.layout });
	return Result.ok(null);
}

export function createComputePipeline(ref p: VulkanPipelines, id: uint32, descriptor: GPUComputePipelineDescriptor): Result<void, ResourceError> {
	const shader = p.shaders[slotOf(descriptor.compute.module.id)];
	const entry = entryName(descriptor.compute.entryPoint);
	checkedComputeModule(shader.compute, entry, shader.computeEntry);
	let native: uint64 = 0;
	try checked(vulkanComputePipelineCreate(shader.layout, shader.vertexOrCompute, entry, native));
	put(p.pipelines, id, { native: native, layout: shader.layout });
	return Result.ok(null);
}

export function destroyPipeline(ref p: VulkanPipelines, ref r: VulkanResources, id: uint32): void {
	retire(r, RetiredKind.Pipeline, p.pipelines[slotOf(id)].native, NO_ALLOCATION);
	vacate(p.pipelines, id);
}

function entryEmpty(entry: GPUBindGroupEntry): boolean {
	return entry.buffer.id == 0 && entry.textureView.id == 0 && entry.sampler.id == 0;
}

function entryFor(descriptor: GPUBindGroupDescriptor, group: int32, binding: int32): int32 {
	for (let e = 0; e < GPU_MAX_BIND_GROUP_ENTRIES; e++) {
		if (!entryEmpty(descriptor.entries[e]) && descriptor.entries[e].binding == binding) { return e; }
	}
	stop(`bind group ${group} has no entry for the shader's binding ${binding}`);
}

@noinline function refuseEntry(group: int32, entry: GPUBindGroupEntry, needs: string): never {
	stop(`bind group ${group} entry ${entry.binding} needs ${needs}`);
}

function viewDimensionOf(dimension: GPUTextureViewDimension): string {
	const name: string = dimension;
	return name == "" ? "2d" : name;
}

export function createBindGroup(
	ref p: VulkanPipelines,
	ref r: VulkanResources,
	id: uint32,
	descriptor: GPUBindGroupDescriptor,
): Result<void, ResourceError> {
	const layout = layoutRecords.record(descriptor.layout.id);
	const group = layout.group;
	const shader = p.shaders[slotOf(pipelineRecords.record(layout.pipeline).shader)];
	const setLayout = shader.sets[group];
	let native: BindGroupNative = { allocation: NO_SET };
	let words: Vec<uint32> = [];
	let handles: Vec<uint64> = [];
	let offsets: Vec<uint64> = [];
	let ranges: Vec<uint64> = [];
	for (let i = 0; i < shader.bindingCount; i++) {
		const binding = shader.bindings[i];
		if (binding.group != group) { continue; }
		const entry = descriptor.entries[entryFor(descriptor, group, binding.binding)];
		let imageLayout: int32 = 0;
		let handle: uint64 = 0;
		let offset: uint64 = 0;
		let range: uint64 = 0;
		let access: GroupAccess = { kind: binding.kind, writable: binding.writable, id: 0 };
		if (binding.kind == BindingKind.Uniform || binding.kind == BindingKind.StorageBuffer) {
			const b = slotOf(entry.buffer.id);
			range = binding.kind == BindingKind.Uniform ? binding.size as uint64 : entryBytes(entry, bufferRecords.slots[b].size) as uint64;
			handle = r.buffers[b].native;
			offset = entry.offset as uint64;
			access.id = entry.buffer.id;
		} else if (binding.kind == BindingKind.Sampler) {
			handle = r.samplers[slotOf(entry.sampler.id)];
		} else {
			const view = viewRecords.record(entry.textureView.id);
			const wanted = viewDimensionOf(binding.viewDimension);
			if (wanted != view.dimension) { refuseEntry(group, entry, `a ${wanted} view, not ${view.dimension}`); }
			imageLayout = binding.kind == BindingKind.Texture ? LAYOUT_SHADER_READ_ONLY : LAYOUT_GENERAL;
			handle = r.views[slotOf(entry.textureView.id)].binding;
			access.id = view.texture;
		}
		words.push(binding.binding as uint32);
		words.push(descriptorType(binding.kind));
		words.push(imageLayout as uint32);
		handles.push(handle);
		offsets.push(offset);
		ranges.push(range);
		if (binding.kind != BindingKind.Sampler) {
			native.accesses[native.accessCount] = access;
			native.accessCount += 1;
		}
	}
	const allocated = allocateSet(r.descriptors, setLayout, native.allocation);
	if (allocated != VULKAN_OK) { return Result.err(failure(allocated)); }
	const written = vulkanDescriptorSetWrite(native.allocation.set, words[0], handles[0], offsets[0], ranges[0], handles.length as uint32);
	if (written != VULKAN_OK) {
		deallocateSet(r.descriptors, native.allocation, vulkanRecordingSerial());
		return Result.err(failure(written));
	}
	put(p.bindGroups, id, native);
	return Result.ok(null);
}

export function destroyBindGroup(ref p: VulkanPipelines, ref r: VulkanResources, id: uint32): void {
	deallocateSet(r.descriptors, p.bindGroups[slotOf(id)].allocation, vulkanRecordingSerial());
	vacate(p.bindGroups, id);
}

export function beginBindings(ref p: VulkanPipelines, compute: boolean): void {
	p.bound = { compute: compute };
}

function commanded(code: int32): void {
	if (code != VULKAN_OK) { stopOnVulkan(); }
}

export function setPipeline(ref p: VulkanPipelines, id: uint32): void {
	commanded(vulkanCmdBindPipeline(p.bound.compute ? 1 : 0, p.pipelines[slotOf(id)].native));
}

export function setBindGroup(ref p: VulkanPipelines, index: int32): void {
	p.bound.dirty[index] = true;
}

// Sets are bound at the draw or dispatch, against the pipeline current then, because WebGPU
// lets setBindGroup come before setPipeline and Vulkan binds a set through a pipeline layout.
function applyBindings(ref p: VulkanPipelines, ref r: VulkanResources): void {
	const pipeline = slotOf(boundFacts.pipeline);
	const layout = p.pipelines[pipeline].layout;
	const groups = pipelineRecords.slots[pipeline].groups;
	const relayout = p.bound.appliedLayout != layout;
	for (let g = 0; g < GROUPS; g++) {
		if ((groups & (1 << g)) == 0) { continue; }
		const id = boundFacts.bindGroups[g];
		const native = p.bindGroups[slotOf(id)];
		if (p.bound.compute) { accessGroup(r, native); }
		if (!relayout && !p.bound.dirty[g]) { continue; }
		const dynamics = g == GPU_UNIFORM_GROUP ? bindGroupRecords.slots[slotOf(id)].dynamicCount : 0;
		commanded(vulkanCmdBindSet(
			p.bound.compute ? 1 : 0,
			layout,
			g as uint32,
			native.allocation.set,
			boundFacts.dynamicOffsets[0],
			dynamics as uint32,
		));
		p.bound.dirty[g] = false;
	}
	p.bound.appliedLayout = layout;
}

function accessGroup(ref r: VulkanResources, group: BindGroupNative): void {
	for (let a = 0; a < group.accessCount; a++) {
		const access = group.accesses[a];
		if (access.kind == BindingKind.Uniform || access.kind == BindingKind.StorageBuffer) {
			const buffer = r.buffers[slotOf(access.id)];
			if (access.writable) {
				writeToBuffer(r.tracker, buffer.native, buffer.rest, STAGE_COMPUTE_SHADER, ACCESS_SHADER_READ | ACCESS_SHADER_WRITE);
			} else {
				readFromBuffer(r.tracker, buffer.native, buffer.rest.stages, buffer.rest.access);
			}
			continue;
		}
		const texture = r.textures[slotOf(access.id)];
		if (access.kind == BindingKind.Texture) {
			readFromTexture(r.tracker, texture.native, texture.rest, texture.rest.stages, texture.rest.access, texture.rest.layout);
		} else {
			writeToTexture(r.tracker, texture.native, texture.rest, STAGE_COMPUTE_SHADER, ACCESS_SHADER_READ | ACCESS_SHADER_WRITE, LAYOUT_GENERAL);
		}
	}
}

export function setVertexBuffer(ref r: VulkanResources, slot: int32, buffer: GPUBuffer, offset: int64): void {
	if (buffer.id == 0) { return; }
	const b = bufferRecords.slotIndex(buffer.id);
	if (!has(bufferRecords.slots[b].usage, GPUBufferUsage.VERTEX as int32)) { stop(`setVertexBuffer: GPUBuffer ${buffer.id} was created without VERTEX`); }
	if (offset < 0 || offset > bufferRecords.slots[b].size) {
		stop(`setVertexBuffer offset ${offset} is outside GPUBuffer ${buffer.id} of ${bufferRecords.slots[b].size}`);
	}
	commanded(vulkanCmdBindVertexBuffer(slot as uint32, r.buffers[b].native, offset as uint64));
}

export function setIndexBuffer(ref r: VulkanResources, buffer: GPUBuffer, format: GPUIndexFormat, offset: int64): void {
	const b = bufferRecords.slotIndex(buffer.id);
	if (!has(bufferRecords.slots[b].usage, GPUBufferUsage.INDEX as int32)) { stop(`setIndexBuffer: GPUBuffer ${buffer.id} was created without INDEX`); }
	const kind = indexType(format, "setIndexBuffer format");
	const alignment: int64 = kind == 0 ? 2 : 4;
	if (offset < 0 || offset % alignment != 0 || offset > bufferRecords.slots[b].size) {
		stop(`setIndexBuffer offset ${offset} is not a multiple of ${alignment} inside GPUBuffer ${buffer.id} of ${bufferRecords.slots[b].size}`);
	}
	commanded(vulkanCmdBindIndexBuffer(r.buffers[b].native, offset as uint64, kind));
}

export function setViewport(x: float32, y: float32, width: float32, height: float32, minDepth: float32, maxDepth: float32): void {
	commanded(vulkanCmdViewport(x, y, width, height, minDepth, maxDepth));
}

export function setScissorRect(x: int32, y: int32, width: int32, height: int32): void {
	commanded(vulkanCmdScissor(x, y, width as uint32, height as uint32));
}

export function setBlendConstant(color: GPUColor): void {
	commanded(vulkanCmdBlendConstants(color.r as float32, color.g as float32, color.b as float32, color.a as float32));
}

export function setStencilReference(reference: uint32): void {
	commanded(vulkanCmdStencilReference(reference));
}

export function draw(ref p: VulkanPipelines, ref r: VulkanResources, vertexCount: int32, instanceCount: int32, firstVertex: int32, firstInstance: int32): void {
	applyBindings(p, r);
	commanded(vulkanCmdDraw(vertexCount as uint32, instanceCount as uint32, firstVertex as uint32, firstInstance as uint32));
}

export function drawIndexed(
	ref p: VulkanPipelines,
	ref r: VulkanResources,
	indexCount: int32,
	instanceCount: int32,
	firstIndex: int32,
	baseVertex: int32,
	firstInstance: int32,
): void {
	applyBindings(p, r);
	commanded(vulkanCmdDrawIndexed(indexCount as uint32, instanceCount as uint32, firstIndex as uint32, baseVertex, firstInstance as uint32));
}

export function dispatchWorkgroups(ref p: VulkanPipelines, ref r: VulkanResources, x: int32, y: int32, z: int32): Result<void, ResourceError> {
	applyBindings(p, r);
	try flush(r);
	return checked(vulkanCmdDispatch(x as uint32, y as uint32, z as uint32));
}

export function dispatchWorkgroupsIndirect(ref p: VulkanPipelines, ref r: VulkanResources, buffer: GPUBuffer, offset: int64): Result<void, ResourceError> {
	applyBindings(p, r);
	const native = r.buffers[slotOf(buffer.id)];
	readFromBuffer(r.tracker, native.native, native.rest.stages, native.rest.access);
	try flush(r);
	return checked(vulkanCmdDispatchIndirect(native.native, offset as uint64));
}

export function closePipelines(ref p: VulkanPipelines): void {
	p.shaders = [{ compute: false }];
	p.pipelines = [{ native: 0, layout: 0 }];
	p.bindGroups = [{ allocation: NO_SET }];
}
