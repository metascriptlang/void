import {
	vulkanDescriptorPoolCreate,
	vulkanDescriptorPoolDestroy,
	vulkanDescriptorPoolSet,
	vulkanPipelineLayoutCreate,
	vulkanPipelineLayoutDestroy,
	vulkanSetLayoutCreate,
	vulkanSetLayoutDestroy,
} from "./vulkan.h";

@passC("-I../../../deps/vulkan-headers/include");

const VULKAN_OK: int32 = 0;
const MAX_DESCRIPTORS_PER_POOL: int32 = 512;
const MAX_SET_BINDINGS: int32 = 32;
const MAX_POOL_SIZES: int32 = 11;
export const SET_LAYOUT_ENTRY_WORDS: int32 = 3;

struct DescriptorPool {
	native: uint64;
	sets: Vec<uint64>;
	freeSets: Vec<int32>;
}

struct Deallocation {
	serial: uint64;
	pool: int32;
	set: int32;
}

struct SetLayout {
	key: Vec<uint32>;
	native: uint64;
	sizes: Vec<uint32>;
	maxSets: int32;
	pools: Vec<DescriptorPool>;
	available: Vec<int32>;
	pending: Vec<Deallocation>;
}

struct PipelineLayout {
	first: uint64;
	second: uint64;
	native: uint64;
}

export struct SetAllocation {
	set: uint64;
	layout: int32;
	pool: int32;
	index: int32;
}

export const NO_SET: SetAllocation = { set: 0, layout: -1, pool: -1, index: -1 };

export struct DescriptorCache {
	layouts: Vec<SetLayout>;
	pipelineLayouts: Vec<PipelineLayout>;
}

export function newDescriptorCache(): DescriptorCache {
	return { layouts: [], pipelineLayouts: [] };
}

function sameKey(key: Readonly<Span<uint32>>, other: Readonly<Span<uint32>>): boolean {
	if (key.length != other.length) { return false; }
	for (let i = 0; i < key.length; i++) {
		if (key[i] != other[i]) { return false; }
	}
	return true;
}

function poolSizes(key: Readonly<Span<uint32>>, ref sizes: Vec<uint32>): int32 {
	let total = 0;
	for (let e = 0; e < key.length; e += SET_LAYOUT_ENTRY_WORDS) {
		const descriptorType = key[e + 1];
		let found = false;
		for (let s = 0; s < sizes.length && !found; s += 2) {
			if (sizes[s] == descriptorType) {
				sizes[s + 1] += 1;
				found = true;
			}
		}
		if (!found) {
			sizes.push(descriptorType);
			sizes.push(1);
		}
		total += 1;
	}
	const maxSets = Math.max(MAX_DESCRIPTORS_PER_POOL / Math.max(total, 1), 1);
	for (let s = 1; s < sizes.length; s += 2) { sizes[s] *= maxSets as uint32; }
	return maxSets;
}

// `key` holds SET_LAYOUT_ENTRY_WORDS words per binding (binding, descriptor type, stages) in
// binding order; a layout with the same key is shared, so pipelines built from equal shader
// layouts take each other's sets.
export function setLayoutIndex(ref cache: DescriptorCache, key: Readonly<Span<uint32>>, ref index: int32): int32 {
	for (let i = 0; i < cache.layouts.length; i++) {
		if (sameKey(cache.layouts[i].key, key)) {
			index = i;
			return VULKAN_OK;
		}
	}
	const count = key.length / SET_LAYOUT_ENTRY_WORDS;
	if (count > MAX_SET_BINDINGS) { return refuseBindings(count); }
	let words: uint32[MAX_SET_BINDINGS * SET_LAYOUT_ENTRY_WORDS] = [0];
	for (let i = 0; i < key.length; i++) { words[i] = key[i]; }
	let native: uint64 = 0;
	const status = vulkanSetLayoutCreate(words[0], count as uint32, native);
	if (status != VULKAN_OK) { return status; }
	let sizes: Vec<uint32> = [];
	const maxSets = poolSizes(key, sizes);
	let copied: Vec<uint32> = [];
	for (const word of key) { copied.push(word); }
	cache.layouts.push({
		key: copied,
		native: native,
		sizes: sizes,
		maxSets: maxSets,
		pools: [],
		available: [],
		pending: [],
	});
	index = cache.layouts.length - 1;
	return VULKAN_OK;
}

@noinline function refuseBindings(count: int32): int32 {
	console.log(`webgpu vulkan: a bind group of ${count} bindings is over ${MAX_SET_BINDINGS}`);
	unreachable;
}

export function setLayoutNative(this cache: DescriptorCache, index: int32): uint64 {
	return cache.layouts[index].native;
}

export function setLayoutEmpty(this cache: DescriptorCache, index: int32): boolean {
	return cache.layouts[index].key.length == 0;
}

export function pipelineLayoutFor(ref cache: DescriptorCache, first: uint64, second: uint64, ref native: uint64): int32 {
	for (const layout of cache.pipelineLayouts) {
		if (layout.first == first && layout.second == second) {
			native = layout.native;
			return VULKAN_OK;
		}
	}
	const sets: uint64[2] = [first, second];
	const status = vulkanPipelineLayoutCreate(sets[0], 2, native);
	if (status != VULKAN_OK) { return status; }
	cache.pipelineLayouts.push({ first: first, second: second, native: native });
	return VULKAN_OK;
}

function growPool(ref cache: DescriptorCache, layout: int32): int32 {
	const maxSets = cache.layouts[layout].maxSets;
	const sizeWords = cache.layouts[layout].sizes.length;
	let words: uint32[MAX_POOL_SIZES * 2] = [0];
	for (let i = 0; i < sizeWords; i++) { words[i] = cache.layouts[layout].sizes[i]; }
	let native: uint64 = 0;
	const status = vulkanDescriptorPoolCreate(
		words[0],
		(sizeWords / 2) as uint32,
		maxSets as uint32,
		cache.layouts[layout].native,
		native,
	);
	if (status != VULKAN_OK) { return status; }
	let sets: Vec<uint64> = [];
	let freeSets: Vec<int32> = [];
	for (let i = 0; i < maxSets; i++) {
		sets.push(vulkanDescriptorPoolSet(i as uint32));
		freeSets.push(maxSets - 1 - i);
	}
	cache.layouts[layout].available.push(cache.layouts[layout].pools.length);
	cache.layouts[layout].pools.push({ native: native, sets: sets, freeSets: freeSets });
	return VULKAN_OK;
}

export function allocateSet(ref cache: DescriptorCache, layout: int32, ref allocation: SetAllocation): int32 {
	if (cache.setLayoutEmpty(layout)) {
		console.log("webgpu vulkan: a set of an empty layout is never allocated: an empty group is not bound");
		unreachable;
	}
	if (cache.layouts[layout].available.length == 0) {
		const status = growPool(cache, layout);
		if (status != VULKAN_OK) { return status; }
	}
	const pool = cache.layouts[layout].available[cache.layouts[layout].available.length - 1];
	const index = cache.layouts[layout].pools[pool].freeSets[cache.layouts[layout].pools[pool].freeSets.length - 1];
	cache.layouts[layout].pools[pool].freeSets.pop();
	if (cache.layouts[layout].pools[pool].freeSets.length == 0) { cache.layouts[layout].available.pop(); }
	allocation = { set: cache.layouts[layout].pools[pool].sets[index], layout: layout, pool: pool, index: index };
	return VULKAN_OK;
}

// A command buffer can read a bound set until its submission completes, so the set returns to
// its pool only once `finishDeallocations` sees `serial` completed.
export function deallocateSet(ref cache: DescriptorCache, allocation: SetAllocation, serial: uint64): void {
	cache.layouts[allocation.layout].pending.push({ serial: serial, pool: allocation.pool, set: allocation.index });
}

export function finishDeallocations(ref cache: DescriptorCache, completed: uint64): void {
	for (let l = 0; l < cache.layouts.length; l++) {
		if (cache.layouts[l].pending.length == 0) { continue; }
		let kept: Vec<Deallocation> = [];
		for (const pending of cache.layouts[l].pending) {
			if (pending.serial > completed) {
				kept.push(pending);
				continue;
			}
			if (cache.layouts[l].pools[pending.pool].freeSets.length == 0) { cache.layouts[l].available.push(pending.pool); }
			cache.layouts[l].pools[pending.pool].freeSets.push(pending.set);
		}
		cache.layouts[l].pending = kept;
	}
}

export function closeDescriptors(ref cache: DescriptorCache): void {
	for (const layout of cache.pipelineLayouts) { vulkanPipelineLayoutDestroy(layout.native); }
	for (const layout of cache.layouts) {
		for (const pool of layout.pools) { vulkanDescriptorPoolDestroy(pool.native); }
		vulkanSetLayoutDestroy(layout.native);
	}
	cache.pipelineLayouts.length = 0;
	cache.layouts.length = 0;
}
