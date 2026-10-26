import { BindingKind, GPUTextureFormat, GPU_MAX_BIND_GROUP_ENTRIES, GPU_MAX_SHADER_BINDINGS } from "./types.ms";

export const SLOT_SHIFT = 16;
export const SLOT_MASK = 0xFFFF;

export struct PoolCore {
	free: Vec<int32>;
	generations: Vec<uint32>;
	backend: string;
	kind: string;
	what: string;
}

export struct Pool<T> {
	slots: Vec<T>;
	core: PoolCore;
}

export function newPool<T>(backend: string, kind: string, what: string, zero: T): Pool<T> {
	return { slots: [zero], core: { free: [], generations: [], backend: backend, kind: kind, what: what } };
}

@noinline function stopOnPool(backend: string, message: string): never {
	console.log(`webgpu ${backend}: ${message}`);
	unreachable;
}

@noinline function stopNotLive(backend: string, kind: string, id: uint32): never {
	stopOnPool(backend, `${kind} ${id} is not a live handle`);
}

@inline export function slotOf(id: uint32): int32 { return (id & SLOT_MASK) as int32; }

@noinline function allocateId(ref core: PoolCore): uint32 {
	let index: int32 = 0;
	if (core.free.length > 0) {
		index = core.free[core.free.length - 1];
		core.free.pop();
	} else {
		if (core.generations.length == 0) { core.generations.push(0); }
		index = core.generations.length as int32;
		if (index > SLOT_MASK) {
			stopOnPool(core.backend, `${core.what} pool exhausted: all ${SLOT_MASK} slots are live or retired`);
		}
		core.generations.push(0);
	}
	core.generations[index] += 1;
	return (core.generations[index] << SLOT_SHIFT) | (index as uint32);
}

@noinline function releaseId(ref core: PoolCore, id: uint32): void {
	const index = slotOf(id);
	if (core.generations[index] < SLOT_MASK) { core.free.push(index); }
}

export function allocate<T>(ref pool: Pool<T>): uint32 { return allocateId(pool.core); }

export function store<T>(ref pool: Pool<T>, slot: T): void {
	const index = slotOf(slot.id);
	if (index < pool.slots.length) { pool.slots[index] = slot; } else { pool.slots.push(slot); }
}

export function release<T>(ref pool: Pool<T>, id: uint32): void { releaseId(pool.core, id); }

export function free<T>(ref pool: Pool<T>, id: uint32): void {
	pool.slots[pool.slotIndex(id)] = pool.slots[0];
	releaseId(pool.core, id);
}

export function put<T>(ref natives: Vec<T>, id: uint32, native: T): void {
	const index = slotOf(id);
	while (natives.length <= index) { natives.push(natives[0]); }
	natives[index] = native;
}

export function vacate<T>(ref natives: Vec<T>, id: uint32): void { natives[slotOf(id)] = natives[0]; }

export function reset<T>(ref pool: Pool<T>): void {
	const zero = pool.slots[0];
	while (pool.slots.length > 1) { pool.slots.pop(); }
	pool.core.free = [];
	for (let index = pool.core.generations.length as int32 - 1; index >= 1; index--) {
		pool.slots.push(zero);
		if (pool.core.generations[index] < SLOT_MASK) { pool.core.free.push(index); }
	}
}

export function alive<T>(this pool: Pool<T>, id: uint32): boolean {
	const index = slotOf(id);
	return id != 0 && index < pool.slots.length && pool.slots[index].id == id;
}

export function slotIndex<T>(this pool: Pool<T>, id: uint32): int32 {
	if (!pool.alive(id)) { stopNotLive(pool.core.backend, pool.core.kind, id); }
	return slotOf(id);
}

export function live<T>(this pool: Pool<T>): int32 {
	let count: int32 = 0;
	for (let i: int32 = 1; i < pool.slots.length; i++) { if (pool.slots[i].id != 0) { count += 1; } }
	return count;
}

export function liveIds<T>(this pool: Pool<T>): Vec<uint32> {
	let ids: Vec<uint32> = [];
	for (let i: int32 = 1; i < pool.slots.length; i++) { if (pool.slots[i].id != 0) { ids.push(pool.slots[i].id); } }
	return ids;
}

export struct BufferRecord {
	id: uint32;
	size: int64;
	usage: int32;
	writtenFrame: int64;
	writtenEnd: int64;
	mapMode: int32;
	mapOffset: int64;
	mapSize: int64;
}

export struct TextureRecord {
	id: uint32;
	width: int32;
	height: int32;
	format: GPUTextureFormat;
	usage: int32;
	sampleCount: int32;
	mipLevels: int32;
	layers: int32;
	volume: boolean;
	cube: boolean;
	swapchainView: uint32;
}

export struct ViewRecord {
	id: uint32;
	texture: uint32;
	dimension: string;
	baseMip: int32;
	mipCount: int32;
	baseLayer: int32;
	layerCount: int32;
	attachable: boolean;
	swapchain: boolean;
}

export struct PipelineRecord {
	id: uint32;
	shader: uint32;
	vertexSlots: int32;
	groups: int32;
	layouts: uint32[2];
	label: string | null;
	compute: boolean;
	readsInstanceIndex: boolean;
	readsVertexIndex: boolean;
}

export struct ShaderBindingRecord {
	binding: int32;
	kind: BindingKind;
	size: int32;
	storageFormat: GPUTextureFormat;
}

export struct ShaderRecord {
	id: uint32;
	compute: boolean;
	bindings: ShaderBindingRecord[GPU_MAX_SHADER_BINDINGS];
	bindingCount: int32;
	groups: int32;
	readsInstanceIndex: boolean;
	readsVertexIndex: boolean;
}

export struct LayoutRecord {
	id: uint32;
	pipeline: uint32;
	group: int32;
}

export struct BindGroupRecord {
	id: uint32;
	group: int32;
	dynamicCount: int32;
	dynamicIndex: int32[GPU_MAX_BIND_GROUP_ENTRIES];
}

export struct IdRecord { id: uint32; }

export enum QueryState {
	Unwritten,
	Open,
	Written,
}

export struct QuerySetRecord {
	id: uint32;
	timestamp: boolean;
	count: int32;
	state: Vec<QueryState>;
	usedPass: Vec<int64>;
}

export let bufferRecords: Pool<BufferRecord> = newPool<BufferRecord>("", "GPUBuffer", "buffer", { id: 0 });
export let textureRecords: Pool<TextureRecord> = newPool<TextureRecord>("", "GPUTexture", "texture", { id: 0 });
export let viewRecords: Pool<ViewRecord> = newPool<ViewRecord>("", "GPUTextureView", "view", { id: 0 });
export let samplerRecords: Pool<IdRecord> = newPool<IdRecord>("", "GPUSampler", "sampler", { id: 0 });
export let shaderRecords: Pool<ShaderRecord> = newPool<ShaderRecord>("", "GPUShaderModule", "shader module", { id: 0 });
export let pipelineRecords: Pool<PipelineRecord> = newPool<PipelineRecord>("", "GPURenderPipeline", "render or compute pipeline", { id: 0 });
export let layoutRecords: Pool<LayoutRecord> = newPool<LayoutRecord>("", "GPUBindGroupLayout", "bind group layout", { id: 0 });
export let bindGroupRecords: Pool<BindGroupRecord> = newPool<BindGroupRecord>("", "GPUBindGroup", "bind group", { id: 0 });
export let querySetRecords: Pool<QuerySetRecord> = newPool<QuerySetRecord>("", "GPUQuerySet", "query set", { id: 0 });

function resetFor<T>(ref pool: Pool<T>, backend: string): void {
	reset(pool);
	pool.core.backend = backend;
}

export function resetRecords(backend: string): void {
	resetFor(bufferRecords, backend);
	resetFor(textureRecords, backend);
	resetFor(viewRecords, backend);
	resetFor(samplerRecords, backend);
	resetFor(shaderRecords, backend);
	resetFor(pipelineRecords, backend);
	resetFor(layoutRecords, backend);
	resetFor(bindGroupRecords, backend);
	resetFor(querySetRecords, backend);
}

export function record<T>(this pool: Pool<T>, id: uint32): T { return pool.slots[pool.slotIndex(id)]; }
