import {
	vulkanAdapterLimit,
	vulkanCmdBindIndexBuffer,
	vulkanCmdBindPipeline,
	vulkanCmdBindSet,
	vulkanCmdBindVertexBuffer,
	vulkanCmdBlendConstants,
	vulkanCmdDispatch,
	vulkanCmdDispatchIndirect,
	vulkanCmdDraw,
	vulkanCmdDrawIndexed,
	vulkanCmdDrawIndirect,
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
	LOAD_OP_LOAD,
	STAGE_COMPUTE_SHADER,
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
	GPUBindGroup,
	GPUBindGroupDescriptor,
	GPUBindGroupEntry,
	GPUBuffer,
	GPUBufferUsage,
	GPUColor,
	GPUColorWrite,
	GPUComputePipeline,
	GPUComputePipelineDescriptor,
	GPUIndexFormat,
	GPURenderPipeline,
	GPURenderPipelineDescriptor,
	GPUShaderBinding,
	GPUShaderModule,
	GPUShaderModuleDescriptor,
	GPUStencilFaceState,
	GPUTextureUsage,
	GPUTextureViewDimension,
	GPU_MAX_BIND_GROUP_ENTRIES,
	GPU_MAX_COLOR_ATTACHMENTS,
	GPU_MAX_SHADER_BINDINGS,
	GPU_MAX_UNIFORM_BLOCKS,
	GPU_MAX_VERTEX_ATTRIBUTES,
	GPU_MAX_VERTEX_BUFFERS,
	GPU_RESOURCE_GROUP,
	GPU_UNIFORM_GROUP,
	bindingKind,
	checkedDispatchIndirect,
	stop,
	stopOnUnportedShaderBindings,
} from "../types.ms";
import {
	checkedBindGroupSet,
	checkedComputeModule,
	checkedComputePipeline,
	checkedRenderModule,
	checkedRenderPassPipeline,
	checkedSampledView,
	checkedStorageEntry,
	checkedStorageView,
	checkedStripDraw,
	checkedUniformEntry,
	entryBytes,
	isStripTopology,
} from "../validate.ms";
import { Pool, allocate, free, liveIds, newPool, slotIndex, store } from "../pool.ms";

@passC("-I../../../deps/vulkan-headers/include");

// Parked at ~/metascript/.inbox/compiler/2026-10-26-struct-field-array-size-const-chain.md: GPU_RESOURCE_GROUP + 1.
const GROUPS: int32 = 2;
const VERTEX_BUFFER_WORDS: int32 = 3;
const VERTEX_ATTRIBUTE_WORDS: int32 = 4;
const COLOR_TARGET_WORDS: int32 = 8;
const RENDER_STATE_WORDS: int32 = 20;
const BLEND_ONE: uint32 = 1;
const BLEND_OP_ADD: uint32 = 0;
const LIMIT_UNIFORM_OFFSET_ALIGNMENT: int32 = 20;
const LIMIT_STORAGE_OFFSET_ALIGNMENT: int32 = 21;
const LIMIT_STORAGE_BUFFER_BINDING_SIZE: int32 = 11;

struct ShaderBinding {
	group: int32;
	binding: int32;
	kind: BindingKind;
	stages: uint32;
	writable: boolean;
	size: int32;
	viewDimension: GPUTextureViewDimension;
}

struct ShaderRecord {
	id: uint32;
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

struct PipelineRecord {
	id: uint32;
	native: uint64;
	compute: boolean;
	shader: uint32;
	layout: uint64;
	sets: int32[GROUPS];
	strip: boolean;
	stripIndexType: int32;
}

struct GroupAccess {
	kind: BindingKind;
	writable: boolean;
	id: uint32;
}

struct DynamicUniform {
	binding: int32;
	end: int64;
	bufferSize: int64;
}

struct BindGroupRecord {
	id: uint32;
	group: int32;
	setLayout: int32;
	allocation: SetAllocation;
	accesses: GroupAccess[GPU_MAX_BIND_GROUP_ENTRIES];
	accessCount: int32;
	dynamics: DynamicUniform[GPU_MAX_UNIFORM_BLOCKS];
	dynamicCount: int32;
}

struct Bound {
	compute: boolean;
	pipeline: uint32;
	appliedLayout: uint64;
	groups: uint32[GROUPS];
	offsets: uint32[GROUPS * GPU_MAX_UNIFORM_BLOCKS];
	offsetCounts: int32[GROUPS];
	dirty: boolean[GROUPS];
	indexType: int32;
}

export struct VulkanPipelines {
	shaders: Pool<ShaderRecord>;
	pipelines: Pool<PipelineRecord>;
	bindGroups: Pool<BindGroupRecord>;
	bound: Bound;
	uniformAlignment: int64;
	storageAlignment: int64;
	storageLimit: int64;
}

@inline function has(flags: int32, flag: int32): boolean { return (flags & flag) != 0; }

export function openPipelines(): VulkanPipelines {
	if (GROUPS != GPU_RESOURCE_GROUP + 1) { stop(`vulkan: GROUPS is ${GROUPS}, the bind groups are ${GPU_RESOURCE_GROUP + 1}`); }
	return {
		shaders: newPool<ShaderRecord>("vulkan", "GPUShaderModule", "shader module", { id: 0 }),
		pipelines: newPool<PipelineRecord>("vulkan", "GPUPipeline", "pipeline", { id: 0 }),
		bindGroups: newPool<BindGroupRecord>("vulkan", "GPUBindGroup", "bind group", { id: 0, allocation: NO_SET }),
		bound: { indexType: -1 },
		uniformAlignment: vulkanAdapterLimit(LIMIT_UNIFORM_OFFSET_ALIGNMENT),
		storageAlignment: vulkanAdapterLimit(LIMIT_STORAGE_OFFSET_ALIGNMENT),
		storageLimit: vulkanAdapterLimit(LIMIT_STORAGE_BUFFER_BINDING_SIZE),
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

function sortedBindings(ref slot: ShaderRecord): void {
	for (let i = 1; i < slot.bindingCount; i++) {
		const moving = slot.bindings[i];
		let j = i - 1;
		while (j >= 0 && slot.bindings[j].binding > moving.binding) {
			slot.bindings[j + 1] = slot.bindings[j];
			j -= 1;
		}
		slot.bindings[j + 1] = moving;
	}
}

function setKey(slot: ShaderRecord, group: int32): Vec<uint32> {
	let key: Vec<uint32> = [];
	for (let i = 0; i < slot.bindingCount; i++) {
		if (slot.bindings[i].group != group) { continue; }
		key.push(slot.bindings[i].binding as uint32);
		key.push(descriptorType(slot.bindings[i].kind));
		key.push(slot.bindings[i].stages);
	}
	return key;
}

function retireModules(ref r: VulkanResources, slot: ShaderRecord): void {
	if (slot.vertexOrCompute != 0) { retire(r, RetiredKind.Shader, slot.vertexOrCompute, NO_ALLOCATION); }
	if (slot.fragment != 0) { retire(r, RetiredKind.Shader, slot.fragment, NO_ALLOCATION); }
}

export function createShaderModule(
	ref p: VulkanPipelines,
	ref r: VulkanResources,
	descriptor: GPUShaderModuleDescriptor,
): Result<GPUShaderModule, ResourceError> {
	stopOnUnportedShaderBindings("vulkan", descriptor);
	const compute = descriptor.computeCode != "" || descriptor.computeBytecode.length > 0;
	let slot: ShaderRecord = { compute: compute };
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
		slot.bindings[slot.bindingCount] = binding;
		slot.bindingCount += 1;
	}
	sortedBindings(slot);
	for (let g = 0; g < GROUPS; g++) {
		const key = setKey(slot, g);
		const status = setLayoutIndex(r.descriptors, key, slot.sets[g]);
		if (status != VULKAN_OK) { return Result.err(failure(status)); }
	}
	const layout = pipelineLayoutFor(
		r.descriptors,
		r.descriptors.setLayoutNative(slot.sets[GPU_UNIFORM_GROUP]),
		r.descriptors.setLayoutNative(slot.sets[GPU_RESOURCE_GROUP]),
		slot.layout,
	);
	if (layout != VULKAN_OK) { return Result.err(failure(layout)); }
	if (compute) {
		slot.computeEntry = entryName(descriptor.computeEntryPoint);
		slot.vertexOrCompute = try module(descriptor.computeCode, descriptor.computeBytecode, "compute");
		if (slot.vertexOrCompute == 0) { stop("vulkan: a compute GPUShaderModule needs computeBytecode"); }
	} else {
		slot.vertexEntry = entryName(descriptor.vertexEntryPoint);
		slot.fragmentEntry = entryName(descriptor.fragmentEntryPoint);
		slot.vertexOrCompute = try module(descriptor.vertexCode, descriptor.vertexBytecode, "vertex");
		if (slot.vertexOrCompute == 0) { stop("vulkan: a render GPUShaderModule needs vertexBytecode"); }
		const fragment = module(descriptor.fragmentCode, descriptor.fragmentBytecode, "fragment");
		if (!fragment.ok) {
			retireModules(r, slot);
			return Result.err(fragment.error);
		}
		slot.fragment = fragment.value;
	}
	slot.id = allocate(p.shaders);
	store(p.shaders, slot);
	return Result.ok({ id: slot.id });
}

export function destroyShaderModule(ref p: VulkanPipelines, ref r: VulkanResources, shader: GPUShaderModule): void {
	retireModules(r, p.shaders.slots[p.shaders.slotIndex(shader.id)]);
	free(p.shaders, shader.id);
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
	words.push((target.writeMask == 0 ? GPUColorWrite.ALL as int32 : target.writeMask) as uint32);
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
	words.push(ds.stencilReadMask);
	words.push(ds.stencilWriteMask);
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
		depthKeyWords(key, info.native, samples, LOAD_OP_LOAD, STORE_OP_STORE, stencil, false);
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
	descriptor: GPURenderPipelineDescriptor,
): Result<GPURenderPipeline, ResourceError> {
	const shader = p.shaders.slots[p.shaders.slotIndex(descriptor.vertex.module.id)];
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
	const id = allocate(p.pipelines);
	store(p.pipelines, {
		id: id,
		native: native,
		compute: false,
		shader: descriptor.vertex.module.id,
		layout: shader.layout,
		sets: shader.sets,
		strip: isStripTopology(descriptor.primitive.topology),
		stripIndexType: stripIndexType(descriptor.primitive.stripIndexFormat),
	});
	return Result.ok({ id: id });
}

function stripIndexType(format: GPUIndexFormat): int32 {
	const name: string = format;
	return name == "" ? -1 : indexType(format, "primitive.stripIndexFormat");
}

export function createComputePipeline(
	ref p: VulkanPipelines,
	descriptor: GPUComputePipelineDescriptor,
): Result<GPUComputePipeline, ResourceError> {
	const shader = p.shaders.slots[p.shaders.slotIndex(descriptor.compute.module.id)];
	const entry = entryName(descriptor.compute.entryPoint);
	checkedComputeModule(shader.compute, entry, shader.computeEntry);
	let native: uint64 = 0;
	try checked(vulkanComputePipelineCreate(shader.layout, shader.vertexOrCompute, entry, native));
	const id = allocate(p.pipelines);
	store(p.pipelines, {
		id: id,
		native: native,
		compute: true,
		shader: descriptor.compute.module.id,
		layout: shader.layout,
		sets: shader.sets,
		strip: false,
		stripIndexType: -1,
	});
	return Result.ok({ id: id });
}

export function destroyRenderPipeline(ref p: VulkanPipelines, ref r: VulkanResources, pipeline: GPURenderPipeline): void {
	destroyPipeline(p, r, pipeline.id);
}

export function destroyComputePipeline(ref p: VulkanPipelines, ref r: VulkanResources, pipeline: GPUComputePipeline): void {
	destroyPipeline(p, r, pipeline.id);
}

function destroyPipeline(ref p: VulkanPipelines, ref r: VulkanResources, id: uint32): void {
	retire(r, RetiredKind.Pipeline, p.pipelines.slots[p.pipelines.slotIndex(id)].native, NO_ALLOCATION);
	free(p.pipelines, id);
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
	shader: GPUShaderModule,
	group: int32,
	descriptor: GPUBindGroupDescriptor,
): Result<GPUBindGroup, ResourceError> {
	const s = p.shaders.slotIndex(shader.id);
	let slot: BindGroupRecord = { group: group, setLayout: p.shaders.slots[s].sets[group], allocation: NO_SET };
	if (r.descriptors.setLayoutEmpty(slot.setLayout)) { stop(`the shader has no bindings in group ${group}: an empty group takes no bind group`); }
	let words: Vec<uint32> = [];
	let handles: Vec<uint64> = [];
	let offsets: Vec<uint64> = [];
	let ranges: Vec<uint64> = [];
	let addressed = 0;
	for (let i = 0; i < p.shaders.slots[s].bindingCount; i++) {
		const binding = p.shaders.slots[s].bindings[i];
		if (binding.group != group) { continue; }
		const entry = descriptor.entries[entryFor(descriptor, group, binding.binding)];
		addressed += 1;
		let layout: int32 = 0;
		let handle: uint64 = 0;
		let offset: uint64 = 0;
		let range: uint64 = 0;
		let access: GroupAccess = { kind: binding.kind, writable: binding.writable, id: 0 };
		if (binding.kind == BindingKind.Uniform || binding.kind == BindingKind.StorageBuffer) {
			if (entry.buffer.id == 0) { refuseEntry(group, entry, "a buffer"); }
			const b = r.buffers.slotIndex(entry.buffer.id);
			const size = r.buffers.slots[b].size;
			const usage = r.buffers.slots[b].usage;
			if (binding.kind == BindingKind.Uniform) {
				checkedUniformEntry(entry, has(usage, GPUBufferUsage.UNIFORM as int32), size, binding.size, p.uniformAlignment);
				range = binding.size as uint64;
				slot.dynamics[slot.dynamicCount] = { binding: binding.binding, end: entry.offset + (binding.size as int64), bufferSize: size };
				slot.dynamicCount += 1;
			} else {
				checkedStorageEntry(entry, has(usage, GPUBufferUsage.STORAGE as int32), size, p.storageAlignment, p.storageLimit);
				range = entryBytes(entry, size) as uint64;
			}
			handle = r.buffers.slots[b].native;
			offset = entry.offset as uint64;
			access.id = entry.buffer.id;
		} else if (binding.kind == BindingKind.Sampler) {
			if (entry.sampler.id == 0) { refuseEntry(group, entry, "a sampler"); }
			handle = r.samplers.slots[r.samplers.slotIndex(entry.sampler.id)].native;
		} else {
			if (entry.textureView.id == 0) { refuseEntry(group, entry, "a texture view"); }
			const view = r.views.slots[r.views.slotIndex(entry.textureView.id)];
			const usage = r.textures.slots[r.textures.slotIndex(view.texture)].usage;
			const wanted = viewDimensionOf(binding.viewDimension);
			const given: string = view.dimension;
			if (wanted != given) { refuseEntry(group, entry, `a ${wanted} view, not ${given}`); }
			if (binding.kind == BindingKind.Texture) {
				checkedSampledView(entry.binding, has(usage, GPUTextureUsage.TEXTURE_BINDING as int32));
				layout = LAYOUT_SHADER_READ_ONLY;
			} else {
				checkedStorageView(entry.binding, has(usage, GPUTextureUsage.STORAGE_BINDING as int32), view.mipCount);
				layout = LAYOUT_GENERAL;
			}
			handle = view.binding;
			access.id = view.texture;
		}
		words.push(binding.binding as uint32);
		words.push(descriptorType(binding.kind));
		words.push(layout as uint32);
		handles.push(handle);
		offsets.push(offset);
		ranges.push(range);
		if (binding.kind != BindingKind.Sampler) {
			slot.accesses[slot.accessCount] = access;
			slot.accessCount += 1;
		}
	}
	for (let e = 0; e < GPU_MAX_BIND_GROUP_ENTRIES; e++) {
		if (!entryEmpty(descriptor.entries[e])) { addressed -= 1; }
	}
	if (addressed != 0) { stop(`bind group ${group} has an entry that is not a binding of the shader's group ${group}`); }
	const allocated = allocateSet(r.descriptors, slot.setLayout, slot.allocation);
	if (allocated != VULKAN_OK) { return Result.err(failure(allocated)); }
	const written = vulkanDescriptorSetWrite(slot.allocation.set, words[0], handles[0], offsets[0], ranges[0], handles.length as uint32);
	if (written != VULKAN_OK) {
		deallocateSet(r.descriptors, slot.allocation, vulkanRecordingSerial());
		return Result.err(failure(written));
	}
	slot.id = allocate(p.bindGroups);
	store(p.bindGroups, slot);
	return Result.ok({ id: slot.id });
}

export function destroyBindGroup(ref p: VulkanPipelines, ref r: VulkanResources, bindGroup: GPUBindGroup): void {
	deallocateSet(r.descriptors, p.bindGroups.slots[p.bindGroups.slotIndex(bindGroup.id)].allocation, vulkanRecordingSerial());
	free(p.bindGroups, bindGroup.id);
}

export function beginBindings(ref p: VulkanPipelines, compute: boolean): void {
	p.bound = { compute: compute, indexType: -1 };
}

function commanded(code: int32): void {
	if (code != VULKAN_OK) { stopOnVulkan(); }
}

function bindPipeline(ref p: VulkanPipelines, id: uint32): void {
	commanded(vulkanCmdBindPipeline(p.bound.compute ? 1 : 0, p.pipelines.slots[p.pipelines.slotIndex(id)].native));
	p.bound.pipeline = id;
}

export function setPipeline(ref p: VulkanPipelines, pipeline: GPURenderPipeline): void {
	checkedRenderPassPipeline(pipeline.id, p.pipelines.slots[p.pipelines.slotIndex(pipeline.id)].compute);
	bindPipeline(p, pipeline.id);
}

export function setComputePipeline(ref p: VulkanPipelines, pipeline: GPUComputePipeline): void {
	checkedComputePipeline(pipeline.id, p.pipelines.slots[p.pipelines.slotIndex(pipeline.id)].compute);
	bindPipeline(p, pipeline.id);
}

@noinline function refuseDynamicOffset(offset: uint32, dynamic: DynamicUniform): never {
	stop(`dynamic offset ${offset} moves uniform binding ${dynamic.binding} to end at ${dynamic.end + (offset as int64)}, past its buffer of ${dynamic.bufferSize}`);
}

export function setBindGroup(ref p: VulkanPipelines, index: int32, bindGroup: GPUBindGroup, dynamicOffsets: Readonly<Span<uint32>>): void {
	p.bound.groups[index] = bindGroup.id;
	p.bound.dirty[index] = true;
	p.bound.offsetCounts[index] = 0;
	if (bindGroup.id == 0) { return; }
	const g = p.bindGroups.slotIndex(bindGroup.id);
	checkedBindGroupSet(index, p.bindGroups.slots[g].group, p.bindGroups.slots[g].dynamicCount, dynamicOffsets, p.uniformAlignment as uint32);
	for (let i = 0; i < p.bindGroups.slots[g].dynamicCount; i++) {
		const dynamic = p.bindGroups.slots[g].dynamics[i];
		if (dynamic.end + (dynamicOffsets[i] as int64) > dynamic.bufferSize) { refuseDynamicOffset(dynamicOffsets[i], dynamic); }
		p.bound.offsets[index * GPU_MAX_UNIFORM_BLOCKS + i] = dynamicOffsets[i];
	}
	p.bound.offsetCounts[index] = p.bindGroups.slots[g].dynamicCount;
}

// Sets are bound at the draw or dispatch, against the pipeline current then, because WebGPU
// lets setBindGroup come before setPipeline and Vulkan binds a set through a pipeline layout.
function applyBindings(ref p: VulkanPipelines, ref r: VulkanResources, call: string): void {
	if (p.bound.pipeline == 0) { stop(`${call} without a pipeline`); }
	const pipeline = p.pipelines.slots[p.pipelines.slotIndex(p.bound.pipeline)];
	const relayout = p.bound.appliedLayout != pipeline.layout;
	for (let g = 0; g < GROUPS; g++) {
		if (r.descriptors.setLayoutEmpty(pipeline.sets[g])) { continue; }
		if (p.bound.groups[g] == 0) { stop(`${call}: the pipeline reads bind group ${g}, which is not set`); }
		const record = p.bindGroups.slots[p.bindGroups.slotIndex(p.bound.groups[g])];
		if (record.setLayout != pipeline.sets[g]) {
			stop(`${call}: bind group ${p.bound.groups[g]} was made for another layout of group ${g} than the pipeline's`);
		}
		if (p.bound.compute) { accessGroup(r, record); }
		if (!relayout && !p.bound.dirty[g]) { continue; }
		commanded(vulkanCmdBindSet(
			p.bound.compute ? 1 : 0,
			pipeline.layout,
			g as uint32,
			record.allocation.set,
			p.bound.offsets[g * GPU_MAX_UNIFORM_BLOCKS],
			p.bound.offsetCounts[g] as uint32,
		));
		p.bound.dirty[g] = false;
	}
	p.bound.appliedLayout = pipeline.layout;
}

function accessGroup(ref r: VulkanResources, record: BindGroupRecord): void {
	for (let a = 0; a < record.accessCount; a++) {
		const access = record.accesses[a];
		if (access.kind == BindingKind.Uniform || access.kind == BindingKind.StorageBuffer) {
			const b = r.buffers.slotIndex(access.id);
			const rest = r.buffers.slots[b].rest;
			if (access.writable) {
				writeToBuffer(r.tracker, r.buffers.slots[b].native, rest, STAGE_COMPUTE_SHADER, ACCESS_SHADER_READ | ACCESS_SHADER_WRITE);
			} else {
				readFromBuffer(r.tracker, r.buffers.slots[b].native, rest.stages, rest.access);
			}
			continue;
		}
		const t = r.textures.slotIndex(access.id);
		const texture = r.textures.slots[t];
		if (access.kind == BindingKind.Texture) {
			readFromTexture(r.tracker, texture.native, texture.rest, texture.rest.stages, texture.rest.access, texture.rest.layout);
		} else {
			writeToTexture(r.tracker, texture.native, texture.rest, STAGE_COMPUTE_SHADER, ACCESS_SHADER_READ | ACCESS_SHADER_WRITE, LAYOUT_GENERAL);
		}
	}
}

export function setVertexBuffer(ref r: VulkanResources, slot: int32, buffer: GPUBuffer, offset: int64): void {
	if (slot < 0 || slot >= GPU_MAX_VERTEX_BUFFERS) { stop(`setVertexBuffer slot ${slot} is outside 0..${GPU_MAX_VERTEX_BUFFERS - 1}`); }
	const b = r.buffers.slotIndex(buffer.id);
	if (!has(r.buffers.slots[b].usage, GPUBufferUsage.VERTEX as int32)) { stop(`setVertexBuffer: GPUBuffer ${buffer.id} was created without VERTEX`); }
	if (offset < 0 || offset > r.buffers.slots[b].size) { stop(`setVertexBuffer offset ${offset} is outside GPUBuffer ${buffer.id} of ${r.buffers.slots[b].size}`); }
	commanded(vulkanCmdBindVertexBuffer(slot as uint32, r.buffers.slots[b].native, offset as uint64));
}

export function setIndexBuffer(ref p: VulkanPipelines, ref r: VulkanResources, buffer: GPUBuffer, format: GPUIndexFormat, offset: int64): void {
	const b = r.buffers.slotIndex(buffer.id);
	if (!has(r.buffers.slots[b].usage, GPUBufferUsage.INDEX as int32)) { stop(`setIndexBuffer: GPUBuffer ${buffer.id} was created without INDEX`); }
	const kind = indexType(format, "setIndexBuffer format");
	const alignment: int64 = kind == 0 ? 2 : 4;
	if (offset < 0 || offset % alignment != 0 || offset > r.buffers.slots[b].size) {
		stop(`setIndexBuffer offset ${offset} is not a multiple of ${alignment} inside GPUBuffer ${buffer.id} of ${r.buffers.slots[b].size}`);
	}
	commanded(vulkanCmdBindIndexBuffer(r.buffers.slots[b].native, offset as uint64, kind));
	p.bound.indexType = kind;
}

export function setViewport(x: float32, y: float32, width: float32, height: float32, minDepth: float32, maxDepth: float32): void {
	commanded(vulkanCmdViewport(x, y, width, height, minDepth, maxDepth));
}

export function setScissorRect(x: int32, y: int32, width: int32, height: int32): void {
	if (x < 0 || y < 0 || width < 0 || height < 0) { stop(`setScissorRect(${x}, ${y}, ${width}, ${height}) has a negative member`); }
	commanded(vulkanCmdScissor(x, y, width as uint32, height as uint32));
}

export function setBlendConstant(color: GPUColor): void {
	commanded(vulkanCmdBlendConstants(color.r as float32, color.g as float32, color.b as float32, color.a as float32));
}

export function setStencilReference(reference: uint32): void {
	commanded(vulkanCmdStencilReference(reference));
}

function readyDraw(ref p: VulkanPipelines, ref r: VulkanResources, call: string, indexed: boolean): void {
	applyBindings(p, r, call);
	if (!indexed) { return; }
	if (p.bound.indexType < 0) { stop(`${call} without an index buffer`); }
	const pipeline = p.pipelines.slots[p.pipelines.slotIndex(p.bound.pipeline)];
	checkedStripDraw(pipeline.strip, pipeline.stripIndexType == p.bound.indexType);
}

export function draw(ref p: VulkanPipelines, ref r: VulkanResources, vertexCount: int32, instanceCount: int32, firstVertex: int32, firstInstance: int32): void {
	readyDraw(p, r, "draw", false);
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
	readyDraw(p, r, "drawIndexed", true);
	commanded(vulkanCmdDrawIndexed(indexCount as uint32, instanceCount as uint32, firstIndex as uint32, baseVertex, firstInstance as uint32));
}

function indirectBuffer(ref r: VulkanResources, call: string, buffer: GPUBuffer, offset: int64, bytes: int64): uint64 {
	const b = r.buffers.slotIndex(buffer.id);
	if (!has(r.buffers.slots[b].usage, GPUBufferUsage.INDIRECT as int32)) { stop(`${call}: GPUBuffer ${buffer.id} was created without INDIRECT`); }
	if (offset < 0 || offset % 4 != 0 || offset + bytes > r.buffers.slots[b].size) {
		stop(`${call} offset ${offset} is not a multiple of 4 with ${bytes} bytes inside GPUBuffer ${buffer.id} of ${r.buffers.slots[b].size}`);
	}
	return r.buffers.slots[b].native;
}

export function drawIndirect(ref p: VulkanPipelines, ref r: VulkanResources, buffer: GPUBuffer, offset: int64): void {
	const native = indirectBuffer(r, "drawIndirect", buffer, offset, 16);
	readyDraw(p, r, "drawIndirect", false);
	commanded(vulkanCmdDrawIndirect(native, offset as uint64, 0));
}

export function drawIndexedIndirect(ref p: VulkanPipelines, ref r: VulkanResources, buffer: GPUBuffer, offset: int64): void {
	const native = indirectBuffer(r, "drawIndexedIndirect", buffer, offset, 20);
	readyDraw(p, r, "drawIndexedIndirect", true);
	commanded(vulkanCmdDrawIndirect(native, offset as uint64, 1));
}

export function dispatchWorkgroups(ref p: VulkanPipelines, ref r: VulkanResources, x: int32, y: int32, z: int32): Result<void, ResourceError> {
	applyBindings(p, r, "dispatchWorkgroups");
	try flush(r);
	return checked(vulkanCmdDispatch(x as uint32, y as uint32, z as uint32));
}

export function dispatchWorkgroupsIndirect(ref p: VulkanPipelines, ref r: VulkanResources, buffer: GPUBuffer, offset: int64): Result<void, ResourceError> {
	const b = r.buffers.slotIndex(buffer.id);
	checkedDispatchIndirect(buffer.id, r.buffers.slots[b].usage, r.buffers.slots[b].size, offset);
	applyBindings(p, r, "dispatchWorkgroupsIndirect");
	readFromBuffer(r.tracker, r.buffers.slots[b].native, r.buffers.slots[b].rest.stages, r.buffers.slots[b].rest.access);
	try flush(r);
	return checked(vulkanCmdDispatchIndirect(r.buffers.slots[b].native, offset as uint64));
}

export function closePipelines(ref p: VulkanPipelines, ref r: VulkanResources): void {
	for (const id of p.bindGroups.liveIds()) { destroyBindGroup(p, r, { id: id }); }
	for (const id of p.pipelines.liveIds()) { destroyPipeline(p, r, id); }
	for (const id of p.shaders.liveIds()) { destroyShaderModule(p, r, { id: id }); }
}
