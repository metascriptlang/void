// Port of h3d.impl.PipelineCache / PipelineBuilder: render state + program + vertex layout +
// target formats → one key → one sokol pipeline, created on first use and reused after.
//
// A program or layout here is a door registry id (door.ms), not a layer's enum: the door is
// what both render layers build pipelines through, and each adds its own base to its
// ordinals (void3d: gpu3d.ms doorProgram / doorLayout).

import { stop } from "./stop";
import { RenderState } from "./state";
import { TargetLayout } from "./target";
import { IndexType, PipelineDescriptor } from "./doorGpu.ms";
import {
	makeShader,
	uniformSlotMask,
	makePipeline,
	destroyShader,
	destroyPipeline,
	programCount,
	contextGeneration,
	passState,
	PassState,
} from "./door";

export { IndexType } from "./doorGpu.ms";

export struct PipelineKey {
	program: int32;
	layout: int32;
	indexType: IndexType;
	state: uint32;
	targets: uint32;
}

export struct PipelineEntry {
	key: PipelineKey;
	pipeline: uint32;
}

export interface PipelineCache {
	entries: Vec<PipelineEntry>;
	// Open addressing over `entries`, an entry's index plus one in the slot its key hashes to,
	// 0 when empty: at least twice as many slots as entries, so a lookup probes a few.
	slots: Vec<int32>;
	shaders: Vec<uint32>;
	blockSlots: Vec<uint32>;
	// The GPU context its handles belong to: renderers sharing a DrawContext forget them once.
	generation: int32;
	closed: boolean;
}

export function empty(this typeof PipelineCache): PipelineCache {
	return {
		entries: [],
		slots: [],
		shaders: [],
		blockSlots: [],
		generation: 0,
		closed: false,
	};
}

function selectedIndexType(indexed: boolean, format: IndexType): IndexType {
	if (!indexed) { return IndexType.None; }
	if (format != IndexType.Uint16 && format != IndexType.Uint32) {
		stop(`indexed pipeline with invalid index type ${format.toString()}`);
	}
	return format;
}

export function pipelineKey(
	program: int32,
	layout: int32,
	indexed: boolean,
	state: RenderState,
	targets: TargetLayout,
	format: IndexType = IndexType.Uint16,
): PipelineKey {
	return {
		program: program,
		layout: layout,
		indexType: selectedIndexType(indexed, format),
		state: state.bits(),
		targets: targets.formatBits(),
	};
}

export function targetLayout(this key: PipelineKey): TargetLayout {
	return TargetLayout.fromFormatBits(key.targets);
}

export function renderState(this key: PipelineKey): RenderState {
	return RenderState.fromBits(key.state);
}

// `program=<id> layout=<id> colors=… depth=… sampleCount=… culling=…`: which pipeline a cache
// entry is, for logs and for comparing two entries by eye.
export function toString(this key: PipelineKey): string {
	return `program=${key.program} layout=${key.layout} ` +
		`indexType=${key.indexType.toString()} ` +
		`${key.targetLayout().toString()} ${key.renderState().toString()}`;
}

export function contains(this cache: PipelineCache, key: PipelineKey): boolean {
	if (cache.closed) { return false; }
	for (const entry of cache.entries) {
		if (entry.key == key) { return true; }
	}
	return false;
}

function keyHash(key: PipelineKey): uint32 {
	let h: uint32 = (key.program as uint32) * 2654435761;
	h = (h ^ (key.layout as uint32)) * 16777619;
	h = (h ^ ((key.indexType as int32) as uint32)) * 16777619;
	h = (h ^ key.state) * 16777619;
	h = (h ^ key.targets) * 16777619;
	return h ^ (h >> 15);
}

// PipelineCache.lookup: the key's hash picks a bucket and the keys in it are compared. The
// entry's index, -1 when the cache holds none for `key`.
export function indexOf(this cache: PipelineCache, key: PipelineKey): int32 {
	if (cache.slots.length == 0) { return -1; }
	const mask: uint32 = ((cache.slots.length as int32) - 1) as uint32;
	let at: int32 = (keyHash(key) & mask) as int32;
	while (cache.slots[at] != 0) {
		const found: int32 = cache.slots[at] - 1;
		if (cache.entries[found].key == key) { return found; }
		at = (at + 1) & (mask as int32);
	}
	return -1;
}

function place(cache: PipelineCache, index: int32): void {
	const mask: uint32 = ((cache.slots.length as int32) - 1) as uint32;
	let at: int32 = (keyHash(cache.entries[index].key) & mask) as int32;
	while (cache.slots[at] != 0) { at = (at + 1) & (mask as int32); }
	cache.slots[at] = index + 1;
}

// Adds an entry for a key the cache holds none for, or sets the handle of the one it holds.
export function record(cache: PipelineCache, key: PipelineKey, pipeline: uint32): void {
	const found: int32 = cache.indexOf(key);
	if (found >= 0) {
		cache.entries[found].pipeline = pipeline;
		return;
	}
	if ((cache.slots.length as int32) < 2 * ((cache.entries.length as int32) + 1)) {
		let size: int32 = 16;
		while (size < 4 * ((cache.entries.length as int32) + 1)) { size = size * 2; }
		cache.slots = new Array(size);
		for (let i = 0; i < size; i++) { cache.slots[i] = 0; }
		for (let i = 0; i < (cache.entries.length as int32); i++) { place(cache, i); }
	}
	cache.entries.push({ key: key, pipeline: pipeline });
	place(cache, (cache.entries.length as int32) - 1);
}

@noinline function stopOnUnregisteredProgram(program: int32): never {
	stop(`program id ${program} was never registered`);
}

@noinline function stopOnRefusedShader(program: int32): never {
	stop(`sokol refused the shader of program ${program}; ` +
		"its pool is full or it did not compile");
}

@noinline function stopOnRefusedPipeline(key: PipelineKey): never {
	stop(`sokol refused pipeline ${key.toString()}; ` +
		"its pool is full or its description is invalid");
}

@noinline function stopOnClosed(call: string): never {
	stop(`${call} on a pipeline cache that was closed`);
}

@noinline function stopInsidePass(call: string): never {
	stop(`${call} with a pass already open; endPass ends it`);
}

function registered(program: int32): boolean {
	return program >= 0 && program < programCount();
}

function adoptContext(cache: PipelineCache): void {
	const generation: int32 = contextGeneration();
	if (cache.generation == generation) { return; }
	forgetPipelines(cache);
	cache.generation = generation;
}

export function shaderFor(cache: PipelineCache, program: int32): uint32 {
	if (cache.closed) { stopOnClosed("shaderFor"); }
	if (!registered(program)) { stopOnUnregisteredProgram(program); }
	adoptContext(cache);
	for (let i = cache.shaders.length as int32; i <= program; i++) {
		cache.shaders.push(0);
		cache.blockSlots.push(0);
	}
	if (cache.shaders[program] == 0) {
		const shader: uint32 = makeShader(program);
		if (shader == 0) { stopOnRefusedShader(program); }
		cache.shaders[program] = shader;
		cache.blockSlots[program] = uniformSlotMask(program);
	}
	return cache.shaders[program];
}

// Whether `program` declares a uniform block at `slot`; known once its shader has been made.
export function declaresBlock(this cache: PipelineCache, program: int32, slot: int32): boolean {
	if (cache.closed) { return false; }
	if (program < 0 || program >= (cache.blockSlots.length as int32)) { return false; }
	return (cache.blockSlots[program] & ((1 as uint32) << (slot as uint32))) != 0;
}

// PipelineBuilder.lookup + the driver's makePipeline on a miss.
export function pipelineFor(
	cache: PipelineCache,
	program: int32,
	layout: int32,
	indexed: boolean,
	state: RenderState,
	targets: TargetLayout,
	format: IndexType = IndexType.Uint16,
): uint32 {
	if (cache.closed) { stopOnClosed("pipelineFor"); }
	if (!registered(program)) { stopOnUnregisteredProgram(program); }
	adoptContext(cache);
	const concrete: TargetLayout = targets.resolved();
	const key: PipelineKey = pipelineKey(program, layout, indexed, state, concrete, format);
	const found: int32 = cache.indexOf(key);
	if (found >= 0 && cache.entries[found].pipeline != 0) { return cache.entries[found].pipeline; }
	return buildPipeline(cache, program, layout, state, concrete, key);
}

// The cache-miss path of pipelineFor, out of line so its pipeline description and refusal
// message are not copied into every caller.
@noinline function buildPipeline(
	cache: PipelineCache,
	program: int32,
	layout: int32,
	state: RenderState,
	concrete: TargetLayout,
	key: PipelineKey,
): uint32 {
	const description: PipelineDescriptor = {
		shader: shaderFor(cache, program),
		layout: layout,
		state: state,
		targets: concrete,
		indexType: key.indexType,
	};
	const pipeline: uint32 = makePipeline(description);
	if (pipeline == 0) { stopOnRefusedPipeline(key); }
	record(cache, key, pipeline);
	return pipeline;
}

// After a context loss: the GPU objects are gone, so only the handles are dropped. Keys stay,
// and each pipeline is rebuilt on its next pipelineFor.
function forgetPipelines(cache: PipelineCache): void {
	for (let i = 0; i < (cache.entries.length as int32); i++) {
		cache.entries[i].pipeline = 0;
	}
	for (let i = 0; i < (cache.shaders.length as int32); i++) {
		cache.shaders[i] = 0;
	}
}

// Destroys every pipeline and shader, then forgets them.
export function releasePipelines(cache: PipelineCache): void {
	if (cache.closed) { stopOnClosed("releasePipelines"); }
	if (passState() != PassState.None) { stopInsidePass("releasePipelines"); }
	if (cache.generation == contextGeneration()) {
		for (const entry of cache.entries) {
			if (entry.pipeline != 0) { destroyPipeline(entry.pipeline); }
		}
		for (const shader of cache.shaders) {
			if (shader != 0) { destroyShader(shader); }
		}
	}
	forgetPipelines(cache);
}

export function closePipelines(cache: PipelineCache): void {
	if (cache.closed) { stopOnClosed("closePipelines"); }
	if (passState() != PassState.None) { stopInsidePass("closePipelines"); }
	releasePipelines(cache);
	cache.entries = [];
	cache.slots = [];
	cache.shaders = [];
	cache.blockSlots = [];
	cache.closed = true;
}

export function isClosed(this cache: PipelineCache): boolean {
	return cache.closed;
}
