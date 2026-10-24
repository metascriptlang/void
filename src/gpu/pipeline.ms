// Port of h3d.impl.PipelineCache / PipelineBuilder: render state + program + vertex layout +
// target formats → one key → one sokol pipeline, created on first use and reused after.
//
// A program or layout here is a door registry id (door.ms), not a layer's enum: the door is
// what both render layers build pipelines through, and each adds its own base to its
// ordinals (void3d: gpu3d.ms doorProgram / doorLayout).

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
	shaders: Vec<uint32>;
	blockSlots: Vec<uint32>;
	// The GPU context its handles belong to: renderers sharing a DrawContext forget them once.
	generation: int32;
	closed: boolean;
}

export function empty(this typeof PipelineCache): PipelineCache {
	return {
		entries: [],
		shaders: [],
		blockSlots: [],
		generation: 0,
		closed: false,
	};
}

function selectedIndexType(indexed: boolean, format: IndexType): IndexType {
	if (!indexed) { return IndexType.None; }
	if (format != IndexType.Uint16 && format != IndexType.Uint32) {
		console.log(`gpu door: indexed pipeline with invalid index type ${format.toString()}`);
		unreachable;
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

@noinline function stopOnUnregisteredProgram(program: int32): uint32 {
	console.log(`gpu door: program id ${program} was never registered`);
	unreachable;
}

@noinline function stopOnRefusedShader(program: int32): uint32 {
	console.log(`gpu door: sokol refused the shader of program ${program}; ` +
		"its pool is full or it did not compile");
	unreachable;
}

@noinline function stopOnRefusedPipeline(key: PipelineKey): uint32 {
	console.log(`gpu door: sokol refused pipeline ${key.toString()}; ` +
		"its pool is full or its description is invalid");
	unreachable;
}

@noinline function stopOnClosed(call: string): void {
	console.log(`gpu door: ${call} on a pipeline cache that was closed`);
	unreachable;
}

@noinline function stopInsidePass(call: string): void {
	console.log(`gpu door: ${call} with a pass already open; endPass ends it`);
	unreachable;
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
	if (!registered(program)) { return stopOnUnregisteredProgram(program); }
	adoptContext(cache);
	for (let i = cache.shaders.length as int32; i <= program; i++) {
		cache.shaders.push(0);
		cache.blockSlots.push(0);
	}
	if (cache.shaders[program] == 0) {
		const shader: uint32 = makeShader(program);
		if (shader == 0) { return stopOnRefusedShader(program); }
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
	if (!registered(program)) { return stopOnUnregisteredProgram(program); }
	adoptContext(cache);
	const concrete: TargetLayout = targets.resolved();
	const key: PipelineKey = pipelineKey(program, layout, indexed, state, concrete, format);
	let found: int32 = cache.entries.length as int32;
	for (let i = 0; i < (cache.entries.length as int32); i++) {
		if (cache.entries[i].key == key) {
			if (cache.entries[i].pipeline != 0) { return cache.entries[i].pipeline; }
			found = i;
		}
	}
	return buildPipeline(cache, program, layout, state, concrete, key, found);
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
	found: int32,
): uint32 {
	const description: PipelineDescriptor = {
		shader: shaderFor(cache, program),
		layout: layout,
		state: state,
		targets: concrete,
		indexType: key.indexType,
	};
	const pipeline: uint32 = makePipeline(description);
	if (pipeline == 0) { return stopOnRefusedPipeline(key); }
	if (found == (cache.entries.length as int32)) {
		cache.entries.push({ key: key, pipeline: pipeline });
	} else {
		cache.entries[found].pipeline = pipeline;
	}
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
	cache.shaders = [];
	cache.blockSlots = [];
	cache.closed = true;
}

export function isClosed(this cache: PipelineCache): boolean {
	return cache.closed;
}
