import {
	dx12BufferSrv,
	dx12BufferUav,
	dx12DescriptorHeapCreate,
	dx12DescriptorsCopy,
	dx12Release,
	dx12RootSignatureCreate,
	dx12RootSignatureSerialize,
	dx12SamplerCreate,
	dx12SetDescriptorHeaps,
	dx12SetRootConstantBufferView,
	dx12SetRootDescriptorTable,
	dx12SetRootSignature,
	dx12TextureSrv,
	dx12TextureUav,
} from "./d3d12.h";
import { FrameRing, NativeError, checked, retire, stop } from "./frame.ms";
import { Resources, useBuffer } from "./resources.ms";
import { STATE_UNORDERED_ACCESS, SubresourceRange, transitionRange } from "./tracker.ms";
import {
	BindingKind,
	GPUBindGroupDescriptor,
	GPUBindGroupEntry,
	GPUSamplerDescriptor,
	GPUShaderBinding,
	GPUShaderStage,
	GPUTextureUsage,
	GPU_MAX_BIND_GROUP_ENTRIES,
	GPU_MAX_UNIFORM_BLOCKS,
	GPU_RESOURCE_GROUP,
	GPU_UNIFORM_GROUP,
	addressModeNative,
	bindingKind,
	compareNative,
	linearFilter,
	samplerMaxLod,
} from "../types.ms";
import { addressesBinding, clampedAnisotropy, entryBytes } from "../validate.ms";
import { ViewRecord, bindGroupRecords, bufferRecords, put, slotOf, textureRecords, vacate, viewRecords } from "../pool.ms";

const HEAP_VIEWS: int32 = 0;
const HEAP_SAMPLERS: int32 = 1;
const HEAP_TARGETS: int32 = 2;
const HEAP_DEPTHS: int32 = 3;
const INITIAL_VIEW_COUNT: int32 = 1024;
const INITIAL_SAMPLER_COUNT: int32 = 1024;
const INITIAL_TARGET_COUNT: int32 = 1024;
const MAX_SAMPLER_COUNT: int32 = 2048;
const VISIBLE_VIEW_COUNT: int32 = 2048;
const VISIBLE_SAMPLER_COUNT: int32 = 2048;
const NO_DESCRIPTOR: int32 = -1;

const VIEW_2D: int32 = 0;
const VIEW_2D_ARRAY: int32 = 1;
const VIEW_CUBE: int32 = 2;
const VIEW_CUBE_ARRAY: int32 = 3;
const VIEW_3D: int32 = 4;

const FILTER_MIP_LINEAR: int32 = 0x01;
const FILTER_MAG_LINEAR: int32 = 0x04;
const FILTER_MIN_LINEAR: int32 = 0x10;
const FILTER_COMPARISON: int32 = 0x80;
const FILTER_ANISOTROPIC: int32 = 0x55;
const COMPARISON_NEVER: int32 = 1;
const ADDRESS_WRAP: int32 = 1;
const ADDRESS_MIRROR: int32 = 2;
const ADDRESS_CLAMP: int32 = 3;
const ADDRESS_MODES: int32[] = [ADDRESS_CLAMP, ADDRESS_WRAP, ADDRESS_MIRROR];
const COMPARE_FUNCTIONS: int32[] = [1, 2, 3, 4, 5, 6, 7, 8];

const ROOT_PARAMETER_TABLE: uint32 = 0;
const ROOT_PARAMETER_CBV: uint32 = 2;
const RANGE_SRV: uint32 = 0;
const RANGE_UAV: uint32 = 1;
const RANGE_SAMPLER: uint32 = 3;
const VISIBILITY_ALL: int32 = 0;
const VISIBILITY_VERTEX: int32 = 1;
const VISIBILITY_PIXEL: int32 = 5;
const ROOT_PARAMETER_WORDS: int32 = 5;
const ROOT_RANGE_WORDS: int32 = 3;
const MAX_ROOT_TABLES: int32 = 4;
const MAX_ROOT_PARAMETERS: int32 = GPU_MAX_UNIFORM_BLOCKS + MAX_ROOT_TABLES;
const MAX_ROOT_RANGES: int32 = MAX_ROOT_TABLES * GPU_MAX_BIND_GROUP_ENTRIES;
const ROOT_ALLOW_INPUT_ASSEMBLER: uint32 = 0x1;
const ROOT_DENY_VERTEX: uint32 = 0x2;
const ROOT_DENY_HULL: uint32 = 0x4;
const ROOT_DENY_DOMAIN: uint32 = 0x8;
const ROOT_DENY_GEOMETRY: uint32 = 0x10;
const ROOT_DENY_PIXEL: uint32 = 0x20;
const ROOT_DENY_AMPLIFICATION: uint32 = 0x100;
const ROOT_DENY_MESH: uint32 = 0x200;
const MAX_CONSTANT_BUFFER_REGISTERS: int32 = 14;
const MAX_SHADER_RESOURCE_REGISTERS: int32 = 128;
const MAX_SAMPLER_REGISTERS: int32 = 16;
const MAX_UNORDERED_ACCESS_REGISTERS: int32 = 8;

const STATE_CONSTANT_BUFFER: uint32 = 0x1;
const STATE_NON_PIXEL_SHADER_RESOURCE: uint32 = 0x40;
const STATE_PIXEL_SHADER_RESOURCE: uint32 = 0x80;

struct DescriptorHeap {
	kind: int32;
	native: uint64;
	start: uint64;
	gpu: uint64;
	increment: uint32;
	capacity: int32;
}

struct RetiredDescriptor {
	serial: uint64;
	index: int32;
}

export struct SamplerKey {
	filter: int32;
	addressU: int32;
	addressV: int32;
	addressW: int32;
	maxAnisotropy: int32;
	compare: int32;
	minLod: float32;
	maxLod: float32;
}

struct VisiblePair {
	views: DescriptorHeap;
	samplers: DescriptorHeap;
}

struct VisibleSlot {
	pairs: Vec<VisiblePair>;
}

export struct VisibleCursor {
	viewCapacity: int32;
	samplerCapacity: int32;
	pair: int32;
	views: int32;
	samplers: int32;
}

export struct ViewNative {
	shaderResource: int32;
	unordered: int32;
	texture: uint32;
	range: SubresourceRange;
}

export struct TableSlot {
	binding: int32;
	kind: BindingKind;
	writable: boolean;
	register: int32;
}

export struct RootTable {
	stage: int32;
	samplers: boolean;
	slots: Vec<TableSlot>;
}

export struct RootUniform {
	binding: int32;
	register: int32;
}

export struct ShaderLayout {
	compute: boolean;
	uniforms: Vec<RootUniform>;
	tables: Vec<RootTable>;
}

export struct PipelineLayout {
	shader: ShaderLayout;
	signature: uint64;
}

export struct SerializedRoot {
	blob: uint64;
	bytes: uint64;
}

export struct TableEntries {
	entries: Vec<int32>;
}

struct GroupTable {
	descriptors: Vec<int32>;
	generation: uint64;
	gpu: uint64;
}

struct GroupUniform {
	buffer: uint32;
	address: uint64;
	dynamicIndex: int32;
}

struct GroupUse {
	buffer: uint32;
	view: uint32;
	state: uint32;
}

struct GroupNative {
	uniforms: Vec<GroupUniform>;
	tables: Vec<GroupTable>;
	owned: Vec<int32>;
	uses: Vec<GroupUse>;
}

struct Bound {
	groups: uint32[2];
	offsets: uint32[GPU_MAX_UNIFORM_BLOCKS];
	dirty: boolean[2];
	signature: uint64;
}

export struct DescriptorStats {
	heapSwitches: int32;
	tableCopies: int32;
	descriptorCopies: int32;
}

export struct Descriptors {
	device: uint64;
	views: DescriptorHeap;
	freeViews: Vec<int32>;
	retiredViews: Vec<RetiredDescriptor>;
	samplers: DescriptorHeap;
	samplerKeys: Vec<SamplerKey>;
	targets: DescriptorHeap;
	targetCursor: int32;
	depths: DescriptorHeap;
	depthCursor: int32;
	visible: Vec<VisibleSlot>;
	cursor: VisibleCursor;
	generation: uint64;
	viewNatives: Vec<ViewNative>;
	samplerNatives: Vec<int32>;
	groups: Vec<GroupNative>;
	bound: Bound;
	stats: DescriptorStats;
}

const NO_HEAP: DescriptorHeap = { kind: 0, native: 0, start: 0, gpu: 0, increment: 0, capacity: 0 };
const NO_RANGE: SubresourceRange = { baseMip: 0, mips: 0, baseLayer: 0, layers: 0 };
const NO_VIEW: ViewNative = { shaderResource: NO_DESCRIPTOR, unordered: NO_DESCRIPTOR, texture: 0, range: NO_RANGE };
const NO_GROUP: GroupNative = { uniforms: [], tables: [], owned: [], uses: [] };
export const NO_LAYOUT: PipelineLayout = { shader: { compute: false, uniforms: [], tables: [] }, signature: 0 };

@inline function has(flags: int32, flag: int32): boolean { return (flags & flag) != 0; }

export function closedDescriptors(): Descriptors {
	return {
		device: 0,
		views: NO_HEAP,
		freeViews: [],
		retiredViews: [],
		samplers: NO_HEAP,
		samplerKeys: [],
		targets: NO_HEAP,
		targetCursor: 0,
		depths: NO_HEAP,
		depthCursor: 0,
		visible: [],
		cursor: newCursor(VISIBLE_VIEW_COUNT, VISIBLE_SAMPLER_COUNT),
		generation: 1,
		viewNatives: [NO_VIEW],
		samplerNatives: [NO_DESCRIPTOR],
		groups: [NO_GROUP],
		bound: { signature: 0 },
		stats: { heapSwitches: 0, tableCopies: 0, descriptorCopies: 0 },
	};
}

function descriptorHeap(device: uint64, kind: int32, capacity: int32, visible: boolean): Result<DescriptorHeap, NativeError> {
	let native: uint64 = 0;
	let start: uint64 = 0;
	let gpu: uint64 = 0;
	let increment: uint32 = 0;
	try checked(dx12DescriptorHeapCreate(device, kind, capacity as uint32, visible ? 1 : 0, native, start, gpu, increment));
	return Result.ok({ kind: kind, native: native, start: start, gpu: gpu, increment: increment, capacity: capacity });
}

function handleAt(heap: DescriptorHeap, index: int32): uint64 {
	return heap.start + (index as uint64) * (heap.increment as uint64);
}

export function openDescriptors(device: uint64, frames: int32): Result<Descriptors, NativeError> {
	let d = closedDescriptors();
	d.device = device;
	const made = makeHeaps(d, frames);
	if (!made.ok) {
		closeDescriptors(d);
		return Result.err(made.error);
	}
	return Result.ok(d);
}

function makeHeaps(ref d: Descriptors, frames: int32): Result<void, NativeError> {
	d.views = try descriptorHeap(d.device, HEAP_VIEWS, INITIAL_VIEW_COUNT, false);
	for (let i = INITIAL_VIEW_COUNT - 1; i >= 0; i--) { d.freeViews.push(i); }
	d.samplers = try descriptorHeap(d.device, HEAP_SAMPLERS, INITIAL_SAMPLER_COUNT, false);
	d.targets = try descriptorHeap(d.device, HEAP_TARGETS, INITIAL_TARGET_COUNT, false);
	d.depths = try descriptorHeap(d.device, HEAP_DEPTHS, INITIAL_TARGET_COUNT, false);
	for (let i: int32 = 0; i < frames; i++) { d.visible.push({ pairs: [] }); }
	return Result.ok(null);
}

export function closeDescriptors(ref d: Descriptors): void {
	dx12Release(d.views.native);
	dx12Release(d.samplers.native);
	dx12Release(d.targets.native);
	dx12Release(d.depths.native);
	for (const slot of d.visible) {
		for (const pair of slot.pairs) {
			dx12Release(pair.views.native);
			dx12Release(pair.samplers.native);
		}
	}
	d = closedDescriptors();
}

function grownCopy(ref d: Descriptors, heap: DescriptorHeap, kept: int32): Result<DescriptorHeap, NativeError> {
	const grown = try descriptorHeap(d.device, heap.kind, (heap.capacity * 3) >> 1, false);
	try checked(dx12DescriptorsCopy(d.device, kept as uint32, grown.start, heap.start, heap.kind));
	dx12Release(heap.native);
	return Result.ok(grown);
}

function allocateView(ref d: Descriptors): Result<int32, NativeError> {
	if (d.freeViews.length == 0) {
		const previous = d.views.capacity;
		d.views = try grownCopy(d, d.views, previous);
		for (let i = d.views.capacity - 1; i >= previous; i--) { d.freeViews.push(i); }
	}
	const index = d.freeViews[d.freeViews.length - 1];
	d.freeViews.pop();
	return Result.ok(index);
}

function retireView(ref d: Descriptors, ref ring: FrameRing, index: int32): void {
	if (index != NO_DESCRIPTOR) { d.retiredViews.push({ serial: ring.recording(), index: index }); }
}

function scratchTarget(ref d: Descriptors, ref ring: FrameRing, depth: boolean): Result<uint64, NativeError> {
	const heap = depth ? d.depths : d.targets;
	let cursor = depth ? d.depthCursor : d.targetCursor;
	let current = heap;
	if (cursor == heap.capacity) {
		retire(ring, heap.native);
		current = try descriptorHeap(d.device, heap.kind, (heap.capacity * 3) >> 1, false);
		cursor = 0;
	}
	if (depth) {
		d.depths = current;
		d.depthCursor = cursor + 1;
	} else {
		d.targets = current;
		d.targetCursor = cursor + 1;
	}
	return Result.ok(handleAt(current, cursor));
}

export function renderTargetHandle(ref d: Descriptors, ref ring: FrameRing): Result<uint64, NativeError> {
	return scratchTarget(d, ring, false);
}

export function depthStencilHandle(ref d: Descriptors, ref ring: FrameRing): Result<uint64, NativeError> {
	return scratchTarget(d, ring, true);
}

export function beginFrame(ref d: Descriptors, ref ring: FrameRing): void {
	d.targetCursor = 0;
	d.depthCursor = 0;
	d.cursor = newCursor(d.cursor.viewCapacity, d.cursor.samplerCapacity);
	d.generation += 1;
	d.bound = { signature: 0 };
	let kept: Vec<RetiredDescriptor> = [];
	for (const retired of d.retiredViews) {
		if (retired.serial > ring.completed) {
			kept.push(retired);
		} else {
			d.freeViews.push(retired.index);
		}
	}
	d.retiredViews = kept;
}

function viewDimensionOf(name: string): int32 {
	return match (name) {
		"2d" => VIEW_2D,
		"2d-array" => VIEW_2D_ARRAY,
		"cube" => VIEW_CUBE,
		"cube-array" => VIEW_CUBE_ARRAY,
		"3d" => VIEW_3D,
		_ => stopOnView(name),
	};
}

@noinline function stopOnView(name: string): int32 {
	stop(`GPUTextureViewDescriptor.dimension '${name}' is not supported`);
}

export function createView(ref d: Descriptors, ref r: Resources, view: ViewRecord): Result<void, NativeError> {
	const t = textureRecords.slotIndex(view.texture);
	const texture = textureRecords.slots[t];
	const info = r.textures[t].info;
	let dimension = viewDimensionOf(view.dimension);
	if (dimension == VIEW_CUBE && view.baseLayer != 0) { dimension = VIEW_CUBE_ARRAY; }
	let native: ViewNative = {
		shaderResource: NO_DESCRIPTOR,
		unordered: NO_DESCRIPTOR,
		texture: view.texture,
		range: texture.volume
			? { baseMip: view.baseMip, mips: view.mipCount, baseLayer: 0, layers: 1 }
			: { baseMip: view.baseMip, mips: view.mipCount, baseLayer: view.baseLayer, layers: view.layerCount },
	};
	if (has(texture.usage, GPUTextureUsage.TEXTURE_BINDING as int32)) {
		const sampled = dimension == VIEW_2D && view.baseLayer > 0 ? VIEW_2D_ARRAY : dimension;
		native.shaderResource = try allocateView(d);
		try checked(dx12TextureSrv(
			d.device,
			r.textures[t].native,
			info.shaderResource,
			sampled,
			texture.sampleCount > 1 ? 1 : 0,
			view.baseMip as uint32,
			view.mipCount as uint32,
			view.baseLayer as uint32,
			view.layerCount as uint32,
			handleAt(d.views, native.shaderResource),
		));
	}
	if (has(texture.usage, GPUTextureUsage.STORAGE_BINDING as int32) && view.mipCount == 1) {
		const unordered = texture.volume ? VIEW_3D : (texture.layers > 1 ? VIEW_2D_ARRAY : VIEW_2D);
		native.unordered = try allocateView(d);
		try checked(dx12TextureUav(
			d.device,
			r.textures[t].native,
			info.renderTarget,
			unordered,
			view.baseMip as uint32,
			view.baseLayer as uint32,
			view.layerCount as uint32,
			handleAt(d.views, native.unordered),
		));
	}
	put(d.viewNatives, view.id, native);
	return Result.ok(null);
}

export function destroyView(ref d: Descriptors, ref ring: FrameRing, id: uint32): void {
	const native = d.viewNatives[slotOf(id)];
	retireView(d, ring, native.shaderResource);
	retireView(d, ring, native.unordered);
	vacate(d.viewNatives, id);
}

export function viewHandle(this d: Descriptors, id: uint32): uint64 {
	const index = d.viewNatives[slotOf(id)].shaderResource;
	return index == NO_DESCRIPTOR ? 0 : handleAt(d.views, index);
}

export function samplerKeyOf(descriptor: GPUSamplerDescriptor): SamplerKey {
	const magLinear = linearFilter(descriptor.magFilter, "GPUSamplerDescriptor.magFilter", "d3d12");
	const minLinear = linearFilter(descriptor.minFilter, "GPUSamplerDescriptor.minFilter", "d3d12");
	const mipLinear = linearFilter(descriptor.mipmapFilter, "GPUSamplerDescriptor.mipmapFilter", "d3d12");
	const compare = descriptor.compare;
	const maxAnisotropy = clampedAnisotropy(descriptor.maxAnisotropy);
	let filter: int32 = 0;
	if (maxAnisotropy > 1) {
		filter = FILTER_ANISOTROPIC;
	} else {
		if (mipLinear) { filter |= FILTER_MIP_LINEAR; }
		if (magLinear) { filter |= FILTER_MAG_LINEAR; }
		if (minLinear) { filter |= FILTER_MIN_LINEAR; }
	}
	if (compare != null) { filter |= FILTER_COMPARISON; }
	return {
		filter: filter,
		addressU: addressModeNative(ADDRESS_MODES, descriptor.addressModeU, "GPUSamplerDescriptor.addressModeU", "d3d12"),
		addressV: addressModeNative(ADDRESS_MODES, descriptor.addressModeV, "GPUSamplerDescriptor.addressModeV", "d3d12"),
		addressW: addressModeNative(ADDRESS_MODES, descriptor.addressModeW, "GPUSamplerDescriptor.addressModeW", "d3d12"),
		maxAnisotropy: maxAnisotropy,
		compare: compare == null ? COMPARISON_NEVER : compareNative(COMPARE_FUNCTIONS, compare, "GPUSamplerDescriptor.compare", "d3d12"),
		minLod: descriptor.lodMinClamp,
		maxLod: samplerMaxLod(descriptor.lodMaxClamp),
	};
}

function sameSampler(a: SamplerKey, b: SamplerKey): boolean {
	return a.filter == b.filter && a.addressU == b.addressU && a.addressV == b.addressV && a.addressW == b.addressW
		&& a.maxAnisotropy == b.maxAnisotropy && a.compare == b.compare && a.minLod == b.minLod && a.maxLod == b.maxLod;
}

function samplerIndex(ref d: Descriptors, key: SamplerKey): Result<int32, NativeError> {
	for (let i: int32 = 0; i < d.samplerKeys.length; i++) {
		if (sameSampler(d.samplerKeys[i], key)) { return Result.ok(i); }
	}
	const index = d.samplerKeys.length as int32;
	if (index == MAX_SAMPLER_COUNT) { stop(`more than ${MAX_SAMPLER_COUNT} distinct samplers`); }
	if (index == d.samplers.capacity) { d.samplers = try grownCopy(d, d.samplers, index); }
	try checked(dx12SamplerCreate(
		d.device,
		key.filter,
		key.addressU,
		key.addressV,
		key.addressW,
		key.maxAnisotropy as uint32,
		key.compare,
		key.minLod as float64,
		key.maxLod as float64,
		handleAt(d.samplers, index),
	));
	d.samplerKeys.push(key);
	return Result.ok(index);
}

export function createSampler(ref d: Descriptors, id: uint32, descriptor: GPUSamplerDescriptor): Result<void, NativeError> {
	const index = try samplerIndex(d, samplerKeyOf(descriptor));
	put(d.samplerNatives, id, index);
	return Result.ok(null);
}

export function destroySampler(ref d: Descriptors, id: uint32): void {
	vacate(d.samplerNatives, id);
}

export function samplerHandle(this d: Descriptors, id: uint32): uint64 {
	return handleAt(d.samplers, d.samplerNatives[slotOf(id)]);
}

function writable(binding: GPUShaderBinding, kind: BindingKind): boolean {
	return match (kind) {
		BindingKind.StorageBuffer => storageBufferWritable(binding),
		BindingKind.StorageTexture => true,
		BindingKind.Uniform | BindingKind.Texture | BindingKind.Sampler => false,
	};
}

function storageBufferWritable(binding: GPUShaderBinding): boolean {
	const bufferType: string = binding.bufferType;
	if (bufferType == "storage") { return true; }
	if (bufferType != "read-only-storage") { stop(`shader binding ${binding.binding} has GPUShaderBinding.bufferType '${bufferType}'`); }
	return false;
}

function registerLimit(kind: BindingKind, isWritable: boolean): int32 {
	if (isWritable) { return MAX_UNORDERED_ACCESS_REGISTERS; }
	return match (kind) {
		BindingKind.Uniform => MAX_CONSTANT_BUFFER_REGISTERS,
		BindingKind.Sampler => MAX_SAMPLER_REGISTERS,
		BindingKind.Texture | BindingKind.StorageBuffer | BindingKind.StorageTexture => MAX_SHADER_RESOURCE_REGISTERS,
	};
}

@noinline function checkedBinding(binding: GPUShaderBinding, kind: BindingKind, isWritable: boolean, compute: boolean): void {
	const allowed = compute ? GPUShaderStage.COMPUTE as int32 : (GPUShaderStage.VERTEX as int32) | (GPUShaderStage.FRAGMENT as int32);
	if (binding.visibility == 0 || (binding.visibility & ~allowed) != 0) {
		stop(`shader binding ${binding.binding} has visibility ${binding.visibility}, which a ${compute ? "compute" : "render"} root signature cannot place`);
	}
	const limit = registerLimit(kind, isWritable);
	if (binding.nativeSlot < 0 || binding.nativeSlot >= limit) {
		stop(`shader binding ${binding.binding} has HLSL register ${binding.nativeSlot}, outside 0..${limit - 1}`);
	}
}

function stageTable(bindings: Readonly<Span<GPUShaderBinding>>, compute: boolean, stage: int32, samplers: boolean): RootTable {
	let slots: Vec<TableSlot> = [];
	for (const binding of bindings) {
		const kindName = binding.kind;
		if (kindName == null || (binding.visibility & stage) == 0) { continue; }
		const kind = bindingKind(kindName, "d3d12");
		if (kind == BindingKind.Uniform || (kind == BindingKind.Sampler) != samplers) { continue; }
		slots.push({ binding: binding.binding, kind: kind, writable: writable(binding, kind), register: binding.nativeSlot });
	}
	slots.sort((a, b) => a.writable != b.writable ? (a.writable ? 1 : -1) : a.register - b.register);
	return { stage: stage, samplers: samplers, slots: slots };
}

export function shaderLayout(bindings: Readonly<Span<GPUShaderBinding>>, compute: boolean): ShaderLayout {
	let layout: ShaderLayout = { compute: compute, uniforms: [], tables: [] };
	for (const binding of bindings) {
		const kindName = binding.kind;
		if (kindName == null) { continue; }
		const kind = bindingKind(kindName, "d3d12");
		checkedBinding(binding, kind, writable(binding, kind), compute);
		if (kind == BindingKind.Uniform) { layout.uniforms.push({ binding: binding.binding, register: binding.nativeSlot }); }
	}
	if (layout.uniforms.length > GPU_MAX_UNIFORM_BLOCKS) {
		stop(`a pipeline layout of ${layout.uniforms.length} uniform blocks is over the ${GPU_MAX_UNIFORM_BLOCKS} root constant buffer views`);
	}
	layout.uniforms.sort((a, b) => a.binding - b.binding);
	const stages: int32[] = compute
		? [GPUShaderStage.COMPUTE as int32]
		: [GPUShaderStage.VERTEX as int32, GPUShaderStage.FRAGMENT as int32];
	for (const stage of stages) {
		for (const samplers of [false, true]) {
			const table = stageTable(bindings, compute, stage, samplers);
			if (table.slots.length > 0) { layout.tables.push(table); }
		}
	}
	return layout;
}

function visibilityOf(stage: int32): int32 {
	if (stage == (GPUShaderStage.VERTEX as int32)) { return VISIBILITY_VERTEX; }
	if (stage == (GPUShaderStage.FRAGMENT as int32)) { return VISIBILITY_PIXEL; }
	return VISIBILITY_ALL;
}

function rangeTypeOf(slot: TableSlot): uint32 {
	if (slot.kind == BindingKind.Sampler) { return RANGE_SAMPLER; }
	return slot.writable ? RANGE_UAV : RANGE_SRV;
}

function rootFlags(compute: boolean): uint32 {
	const unused = ROOT_DENY_HULL | ROOT_DENY_DOMAIN | ROOT_DENY_GEOMETRY | ROOT_DENY_AMPLIFICATION | ROOT_DENY_MESH;
	return compute ? unused | ROOT_DENY_PIXEL | ROOT_DENY_VERTEX : unused | ROOT_ALLOW_INPUT_ASSEMBLER;
}

export function serializeRootSignature(layout: ShaderLayout): Result<SerializedRoot, NativeError> {
	let parameters: uint32[MAX_ROOT_PARAMETERS * ROOT_PARAMETER_WORDS] = [0];
	let ranges: uint32[MAX_ROOT_RANGES * ROOT_RANGE_WORDS] = [0];
	let parameter: int32 = 0;
	let range: int32 = 0;
	for (const uniform of layout.uniforms) {
		const p = parameter * ROOT_PARAMETER_WORDS;
		parameters[p] = ROOT_PARAMETER_CBV;
		parameters[p + 1] = VISIBILITY_ALL as uint32;
		parameters[p + 2] = uniform.register as uint32;
		parameter += 1;
	}
	for (const table of layout.tables) {
		const p = parameter * ROOT_PARAMETER_WORDS;
		parameters[p] = ROOT_PARAMETER_TABLE;
		parameters[p + 1] = visibilityOf(table.stage) as uint32;
		parameters[p + 3] = range as uint32;
		parameters[p + 4] = table.slots.length as uint32;
		for (let i: int32 = 0; i < table.slots.length; i++) {
			const w = range * ROOT_RANGE_WORDS;
			ranges[w] = rangeTypeOf(table.slots[i]);
			ranges[w + 1] = table.slots[i].register as uint32;
			ranges[w + 2] = i as uint32;
			range += 1;
		}
		parameter += 1;
	}
	let blob: uint64 = 0;
	let bytes: uint64 = 0;
	try checked(dx12RootSignatureSerialize(parameters[0], parameter as uint32, ranges[0], range as uint32, rootFlags(layout.compute), blob, bytes));
	return Result.ok({ blob: blob, bytes: bytes });
}

export function createPipelineLayout(ref d: Descriptors, bindings: Readonly<Span<GPUShaderBinding>>, compute: boolean): Result<PipelineLayout, NativeError> {
	const shader = shaderLayout(bindings, compute);
	const serialized = try serializeRootSignature(shader);
	let signature: uint64 = 0;
	const created = checked(dx12RootSignatureCreate(d.device, serialized.blob, signature));
	dx12Release(serialized.blob);
	if (!created.ok) { return Result.err(created.error); }
	return Result.ok({ shader: shader, signature: signature });
}

@noinline function stopOnMissingEntry(group: int32, slot: TableSlot): never {
	stop(`bind group ${group} has no entry for shader binding ${slot.binding}`);
}

export function tableEntries(layout: ShaderLayout, group: int32, descriptor: GPUBindGroupDescriptor): Vec<TableEntries> {
	let tables: Vec<TableEntries> = [];
	for (const table of layout.tables) {
		let entries: Vec<int32> = [];
		for (const slot of table.slots) {
			let found: int32 = -1;
			for (let e: int32 = 0; e < GPU_MAX_BIND_GROUP_ENTRIES && found < 0; e++) {
				const entry: GPUBindGroupEntry = descriptor.entries[e];
				const used = entry.buffer.id != 0 || entry.textureView.id != 0 || entry.sampler.id != 0;
				if (used && addressesBinding(group, entry.binding, slot.binding, slot.kind)) { found = e; }
			}
			if (found < 0) { stopOnMissingEntry(group, slot); }
			entries.push(found);
		}
		tables.push({ entries: entries });
	}
	return tables;
}

function compactIndex(descriptor: GPUBindGroupDescriptor, e: int32): int32 {
	let compact: int32 = 0;
	for (let i: int32 = 0; i < e; i++) {
		const entry: GPUBindGroupEntry = descriptor.entries[i];
		if (entry.buffer.id != 0 || entry.textureView.id != 0 || entry.sampler.id != 0) { compact += 1; }
	}
	return compact;
}

function uniformsOf(ref r: Resources, ref native: GroupNative, layout: ShaderLayout, id: uint32, descriptor: GPUBindGroupDescriptor): void {
	const record = bindGroupRecords.record(id);
	for (const uniform of layout.uniforms) {
		let found: int32 = -1;
		for (let e: int32 = 0; e < GPU_MAX_BIND_GROUP_ENTRIES && found < 0; e++) {
			const entry: GPUBindGroupEntry = descriptor.entries[e];
			if (entry.buffer.id != 0 && addressesBinding(GPU_UNIFORM_GROUP, entry.binding, uniform.binding, BindingKind.Uniform)) { found = e; }
		}
		if (found < 0) { stop(`bind group ${GPU_UNIFORM_GROUP} has no entry for uniform binding ${uniform.binding}`); }
		const entry: GPUBindGroupEntry = descriptor.entries[found];
		const b = bufferRecords.slotIndex(entry.buffer.id);
		native.uniforms.push({
			buffer: entry.buffer.id,
			address: r.buffers[b].address + (entry.offset as uint64),
			dynamicIndex: record.dynamicIndex[compactIndex(descriptor, found)],
		});
		native.uses.push({ buffer: entry.buffer.id, view: 0, state: STATE_CONSTANT_BUFFER });
	}
}

function readState(stage: int32): uint32 {
	return stage == (GPUShaderStage.FRAGMENT as int32) ? STATE_PIXEL_SHADER_RESOURCE : STATE_NON_PIXEL_SHADER_RESOURCE;
}

function storageBufferView(ref d: Descriptors, ref r: Resources, entry: GPUBindGroupEntry, isWritable: boolean): Result<int32, NativeError> {
	const b = bufferRecords.slotIndex(entry.buffer.id);
	const bytes = entryBytes(entry, bufferRecords.slots[b].size) as uint64;
	const index = try allocateView(d);
	const handle = handleAt(d.views, index);
	const native = r.buffers[b].native;
	const offset = entry.offset as uint64;
	try checked(isWritable ? dx12BufferUav(d.device, native, offset, bytes, handle) : dx12BufferSrv(d.device, native, offset, bytes, handle));
	return Result.ok(index);
}

function slotDescriptor(ref d: Descriptors, ref r: Resources, ref owned: int32[GPU_MAX_BIND_GROUP_ENTRIES], slot: TableSlot, e: int32, entry: GPUBindGroupEntry): Result<int32, NativeError> {
	return match (slot.kind) {
		BindingKind.Texture => Result.ok(viewDescriptor(d, entry, false)),
		BindingKind.StorageTexture => Result.ok(viewDescriptor(d, entry, true)),
		BindingKind.Sampler => Result.ok(d.samplerNatives[samplerSlot(entry)]),
		BindingKind.StorageBuffer => {
			if (owned[e] == NO_DESCRIPTOR) { owned[e] = try storageBufferView(d, r, entry, slot.writable); }
			return Result.ok(owned[e]);
		},
		BindingKind.Uniform => stopOnTableUniform(slot),
	};
}

@noinline function stopOnTableUniform(slot: TableSlot): never {
	stop(`uniform binding ${slot.binding} reached a descriptor table; group ${GPU_UNIFORM_GROUP} binds it as a root constant buffer view`);
}

function samplerSlot(entry: GPUBindGroupEntry): int32 {
	if (entry.sampler.id == 0) { stop(`bind group entry ${entry.binding} needs a sampler`); }
	return slotOf(entry.sampler.id);
}

function viewDescriptor(ref d: Descriptors, entry: GPUBindGroupEntry, unordered: boolean): int32 {
	if (entry.textureView.id == 0) { stop(`bind group entry ${entry.binding} needs a texture view`); }
	const view = d.viewNatives[slotOf(entry.textureView.id)];
	const index = unordered ? view.unordered : view.shaderResource;
	if (index == NO_DESCRIPTOR) {
		stop(`texture view ${entry.textureView.id} of bind group entry ${entry.binding} has no ${unordered ? "unordered access (STORAGE_BINDING, one mip)" : "shader resource (TEXTURE_BINDING)"} view`);
	}
	return index;
}

function tablesOf(ref d: Descriptors, ref r: Resources, ref native: GroupNative, layout: ShaderLayout, descriptor: GPUBindGroupDescriptor): Result<void, NativeError> {
	const entries = tableEntries(layout, GPU_RESOURCE_GROUP, descriptor);
	let owned: int32[GPU_MAX_BIND_GROUP_ENTRIES] = [NO_DESCRIPTOR];
	for (let e: int32 = 0; e < GPU_MAX_BIND_GROUP_ENTRIES; e++) { owned[e] = NO_DESCRIPTOR; }
	let states: uint32[GPU_MAX_BIND_GROUP_ENTRIES] = [0];
	for (let t: int32 = 0; t < layout.tables.length; t++) {
		const table = layout.tables[t];
		let descriptors: Vec<int32> = [];
		for (let i: int32 = 0; i < table.slots.length; i++) {
			const slot = table.slots[i];
			const e = entries[t].entries[i];
			const entry: GPUBindGroupEntry = descriptor.entries[e];
			descriptors.push(try slotDescriptor(d, r, owned, slot, e, entry));
			if (slot.kind != BindingKind.Sampler) { states[e] |= slot.writable ? STATE_UNORDERED_ACCESS : readState(table.stage); }
		}
		native.tables.push({ descriptors: descriptors, generation: 0, gpu: 0 });
	}
	for (let e: int32 = 0; e < GPU_MAX_BIND_GROUP_ENTRIES; e++) {
		if (owned[e] != NO_DESCRIPTOR) { native.owned.push(owned[e]); }
		if (states[e] == 0) { continue; }
		const entry: GPUBindGroupEntry = descriptor.entries[e];
		native.uses.push({ buffer: entry.buffer.id, view: entry.textureView.id, state: states[e] });
	}
	return Result.ok(null);
}

export function createGroup(ref d: Descriptors, ref r: Resources, id: uint32, layout: ShaderLayout, descriptor: GPUBindGroupDescriptor): Result<void, NativeError> {
	let native: GroupNative = { uniforms: [], tables: [], owned: [], uses: [] };
	const group = bindGroupRecords.record(id).group;
	if (group == GPU_UNIFORM_GROUP) {
		uniformsOf(r, native, layout, id, descriptor);
	} else {
		try tablesOf(d, r, native, layout, descriptor);
	}
	put(d.groups, id, native);
	return Result.ok(null);
}

export function destroyGroup(ref d: Descriptors, ref ring: FrameRing, id: uint32): void {
	for (const index of d.groups[slotOf(id)].owned) { retireView(d, ring, index); }
	vacate(d.groups, id);
}

export function setGroup(ref d: Descriptors, index: int32, id: uint32, offsets: Readonly<Span<uint32>>): void {
	d.bound.groups[index] = id;
	d.bound.dirty[index] = true;
	if (index == GPU_UNIFORM_GROUP) {
		for (let i: int32 = 0; i < offsets.length; i++) { d.bound.offsets[i] = offsets[i]; }
	}
}

export function newCursor(viewCapacity: int32, samplerCapacity: int32): VisibleCursor {
	return { viewCapacity: viewCapacity, samplerCapacity: samplerCapacity, pair: -1, views: 0, samplers: 0 };
}

export function fits(this cursor: VisibleCursor, views: int32, samplers: int32): boolean {
	return cursor.pair >= 0 && cursor.views + views <= cursor.viewCapacity && cursor.samplers + samplers <= cursor.samplerCapacity;
}

export function nextPair(ref cursor: VisibleCursor, views: int32, samplers: int32): void {
	if (views > cursor.viewCapacity || samplers > cursor.samplerCapacity) {
		stop(`one bind group needs ${views} views and ${samplers} samplers, over a visible heap of ${cursor.viewCapacity} and ${cursor.samplerCapacity}`);
	}
	cursor.pair += 1;
	cursor.views = 0;
	cursor.samplers = 0;
}

function visiblePair(ref d: Descriptors, frame: int32, pair: int32): Result<VisiblePair, NativeError> {
	if (pair < d.visible[frame].pairs.length) { return Result.ok(d.visible[frame].pairs[pair]); }
	const views = try descriptorHeap(d.device, HEAP_VIEWS, d.cursor.viewCapacity, true);
	const samplers = descriptorHeap(d.device, HEAP_SAMPLERS, d.cursor.samplerCapacity, true);
	if (!samplers.ok) {
		dx12Release(views.native);
		return Result.err(samplers.error);
	}
	const created: VisiblePair = { views: views, samplers: samplers.value };
	d.visible[frame].pairs.push(created);
	return Result.ok(created);
}

struct Counts {
	views: int32;
	samplers: int32;
}

function staleCounts(d: Descriptors, native: GroupNative, layout: ShaderLayout, all: boolean): Counts {
	let counts: Counts = { views: 0, samplers: 0 };
	for (let t: int32 = 0; t < layout.tables.length; t++) {
		if (!all && native.tables[t].generation == d.generation) { continue; }
		const count = native.tables[t].descriptors.length as int32;
		if (layout.tables[t].samplers) { counts.samplers += count; } else { counts.views += count; }
	}
	return counts;
}

function copyTable(ref d: Descriptors, pair: VisiblePair, ref native: GroupNative, t: int32, samplers: boolean): Result<void, NativeError> {
	const kind = samplers ? HEAP_SAMPLERS : HEAP_VIEWS;
	const source = samplers ? d.samplers : d.views;
	const target = samplers ? pair.samplers : pair.views;
	const first = samplers ? d.cursor.samplers : d.cursor.views;
	const count = native.tables[t].descriptors.length as int32;
	for (let i: int32 = 0; i < count; i++) {
		try checked(dx12DescriptorsCopy(d.device, 1, handleAt(target, first + i), handleAt(source, native.tables[t].descriptors[i]), kind));
	}
	native.tables[t].gpu = target.gpu + (first as uint64) * (target.increment as uint64);
	native.tables[t].generation = d.generation;
	if (samplers) { d.cursor.samplers += count; } else { d.cursor.views += count; }
	d.stats.tableCopies += 1;
	d.stats.descriptorCopies += count;
	return Result.ok(null);
}

function useGroup(ref d: Descriptors, ref r: Resources, ref ring: FrameRing, uses: Readonly<Span<GroupUse>>): void {
	for (const used of uses) {
		if (used.buffer != 0) {
			const b = bufferRecords.slotIndex(used.buffer);
			useBuffer(r, used.buffer, b, used.state);
			r.buffers[b].lastUse = ring.recording();
		}
		if (used.view != 0) {
			const view = d.viewNatives[viewRecords.slotIndex(used.view)];
			transitionRange(r.tracker, r.textures[textureRecords.slotIndex(view.texture)].tracked, used.state, view.range);
		}
	}
}

@noinline function stopOnUnsetGroup(index: int32): never {
	stop(`the pipeline reads bind group ${index}, which is not set`);
}

function applyUniforms(ref d: Descriptors, ref r: Resources, ref ring: FrameRing, layout: PipelineLayout): Result<void, NativeError> {
	const id = d.bound.groups[GPU_UNIFORM_GROUP];
	if (id == 0) { stopOnUnsetGroup(GPU_UNIFORM_GROUP); }
	const g = bindGroupRecords.slotIndex(id);
	const compute = layout.shader.compute ? 1 : 0;
	for (let u: int32 = 0; u < d.groups[g].uniforms.length; u++) {
		const uniform = d.groups[g].uniforms[u];
		const base = r.buffers[bufferRecords.slotIndex(uniform.buffer)].frameBase(ring);
		const address = uniform.address + base + (d.bound.offsets[uniform.dynamicIndex] as uint64);
		try checked(dx12SetRootConstantBufferView(ring.list, compute, u as uint32, address));
	}
	useGroup(d, r, ring, d.groups[g].uses);
	return Result.ok(null);
}

function applyTables(ref d: Descriptors, ref r: Resources, ref ring: FrameRing, layout: PipelineLayout): Result<void, NativeError> {
	const id = d.bound.groups[GPU_RESOURCE_GROUP];
	if (id == 0) { stopOnUnsetGroup(GPU_RESOURCE_GROUP); }
	const g = bindGroupRecords.slotIndex(id);
	const stale = staleCounts(d, d.groups[g], layout.shader, false);
	if (!d.cursor.fits(stale.views, stale.samplers)) {
		const all = staleCounts(d, d.groups[g], layout.shader, true);
		nextPair(d.cursor, all.views, all.samplers);
		d.generation += 1;
		const switched = try visiblePair(d, ring.slot(), d.cursor.pair);
		try checked(dx12SetDescriptorHeaps(ring.list, switched.views.native, switched.samplers.native));
		d.stats.heapSwitches += 1;
	}
	const pair = d.visible[ring.slot()].pairs[d.cursor.pair];
	const compute = layout.shader.compute ? 1 : 0;
	const first = layout.shader.uniforms.length as int32;
	for (let t: int32 = 0; t < layout.shader.tables.length; t++) {
		if (d.groups[g].tables[t].generation != d.generation) { try copyTable(d, pair, d.groups[g], t, layout.shader.tables[t].samplers); }
		try checked(dx12SetRootDescriptorTable(ring.list, compute, (first + t) as uint32, d.groups[g].tables[t].gpu));
	}
	useGroup(d, r, ring, d.groups[g].uses);
	return Result.ok(null);
}

export function applyBindings(ref d: Descriptors, ref r: Resources, ref ring: FrameRing, layout: PipelineLayout): Result<void, NativeError> {
	if (layout.signature == 0) { stop("a draw or dispatch reached a pipeline with no d3d12 root signature"); }
	if (d.bound.signature != layout.signature) {
		try checked(dx12SetRootSignature(ring.list, layout.shader.compute ? 1 : 0, layout.signature));
		d.bound.signature = layout.signature;
		d.bound.dirty[GPU_UNIFORM_GROUP] = true;
		d.bound.dirty[GPU_RESOURCE_GROUP] = true;
	}
	if (d.bound.dirty[GPU_UNIFORM_GROUP] && layout.shader.uniforms.length > 0) { try applyUniforms(d, r, ring, layout); }
	d.bound.dirty[GPU_UNIFORM_GROUP] = false;
	if (d.bound.dirty[GPU_RESOURCE_GROUP] && layout.shader.tables.length > 0) { try applyTables(d, r, ring, layout); }
	d.bound.dirty[GPU_RESOURCE_GROUP] = false;
	return Result.ok(null);
}

export function stats(this d: Descriptors): DescriptorStats { return d.stats; }
