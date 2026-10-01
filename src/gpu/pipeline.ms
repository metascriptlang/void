// Port of h3d.impl.PipelineCache / PipelineBuilder: render state + program + vertex layout +
// target formats → one key → one sokol pipeline, created on first use and reused after.
//
// A program or layout here is a door registry id (door.ms), not a layer's enum: the door is
// what both render layers build pipelines through, and each adds its own base to its
// ordinals (void3d: gpu3d.ms doorProgram / doorLayout).

import { RenderState } from "./state";
import { TargetLayout } from "./target";
import {
	makeShader,
	uniformSlotMask,
	makePipeline,
	destroyShader,
	destroyPipeline,
	programCount,
} from "./door";
import {
	DOOR_PIPELINE_SHADER,
	DOOR_PIPELINE_LAYOUT,
	DOOR_PIPELINE_CULLING,
	DOOR_PIPELINE_DEPTH_TEST,
	DOOR_PIPELINE_DEPTH_WRITE,
	DOOR_PIPELINE_BLEND_SOURCE,
	DOOR_PIPELINE_BLEND_DESTINATION,
	DOOR_PIPELINE_BLEND_ALPHA_SOURCE,
	DOOR_PIPELINE_BLEND_ALPHA_DESTINATION,
	DOOR_PIPELINE_BLEND_OPERATION,
	DOOR_PIPELINE_BLEND_ALPHA_OPERATION,
	DOOR_PIPELINE_COLOR_MASK,
	DOOR_PIPELINE_COLOR_FORMAT,
	DOOR_PIPELINE_DEPTH_FORMAT,
	DOOR_PIPELINE_SAMPLE_COUNT,
	DOOR_PIPELINE_INDEX_TYPE,
	DOOR_PIPELINE_LENGTH,
} from "./door.h";

// sokol bakes the index type into the pipeline, so a mesh drawn from an index buffer and one
// drawn straight from its vertex buffer need different pipelines. Only uint16 is offered: it
// caps a mesh at 65536 vertices, far above Hibernal's budget, and widening the format is a
// decision, not a fallback (meshData.ms MAX_MESH_VERTICES).
export enum IndexType {
	None,
	Uint16,
}

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

export struct PipelineCache {
	entries: Vec<PipelineEntry>;
	shaders: Vec<uint32>;
	blockSlots: Vec<uint32>;
	descriptor: Vec<uint32>;
	// The GPU context its handles belong to: renderers sharing a DrawContext forget them once.
	generation: int32;
}

export function empty(this typeof PipelineCache): PipelineCache {
	return {
		entries: [],
		shaders: [],
		blockSlots: [],
		descriptor: new Array(DOOR_PIPELINE_LENGTH),
		generation: 0,
	};
}

export function pipelineKey(
	program: int32,
	layout: int32,
	indexed: boolean,
	state: RenderState,
	targets: TargetLayout,
): PipelineKey {
	return {
		program: program,
		layout: layout,
		indexType: indexed ? IndexType.Uint16 : IndexType.None,
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

function unsigned(value: int32): uint32 {
	return value as uint32;
}

// The flat sg_pipeline_desc that door.c reads (DOOR_PIPELINE_*).
export function describePipeline(
	out: Span<uint32>,
	shader: uint32,
	layout: int32,
	indexed: boolean,
	state: RenderState,
	targets: TargetLayout,
): void {
	out[DOOR_PIPELINE_SHADER] = shader;
	out[DOOR_PIPELINE_LAYOUT] = unsigned(layout);
	out[DOOR_PIPELINE_CULLING] = unsigned(state.culling as int32);
	out[DOOR_PIPELINE_DEPTH_TEST] = unsigned(state.depthTest as int32);
	out[DOOR_PIPELINE_DEPTH_WRITE] = state.depthWrite ? 1 : 0;
	out[DOOR_PIPELINE_BLEND_SOURCE] = unsigned(state.blendSource as int32);
	out[DOOR_PIPELINE_BLEND_DESTINATION] = unsigned(state.blendDestination as int32);
	out[DOOR_PIPELINE_BLEND_ALPHA_SOURCE] = unsigned(state.blendAlphaSource as int32);
	out[DOOR_PIPELINE_BLEND_ALPHA_DESTINATION] = unsigned(state.blendAlphaDestination as int32);
	out[DOOR_PIPELINE_BLEND_OPERATION] = unsigned(state.blendOperation as int32);
	out[DOOR_PIPELINE_BLEND_ALPHA_OPERATION] = unsigned(state.blendAlphaOperation as int32);
	out[DOOR_PIPELINE_COLOR_MASK] = state.colorMask as uint32;
	out[DOOR_PIPELINE_COLOR_FORMAT] = unsigned(targets.color0 as int32);
	out[DOOR_PIPELINE_COLOR_FORMAT + 1] = unsigned(targets.color1 as int32);
	out[DOOR_PIPELINE_COLOR_FORMAT + 2] = unsigned(targets.color2 as int32);
	out[DOOR_PIPELINE_COLOR_FORMAT + 3] = unsigned(targets.color3 as int32);
	out[DOOR_PIPELINE_DEPTH_FORMAT] = unsigned(targets.depth as int32);
	out[DOOR_PIPELINE_SAMPLE_COUNT] = unsigned(targets.sampleCount);
	const indexType: IndexType = indexed ? IndexType.Uint16 : IndexType.None;
	out[DOOR_PIPELINE_INDEX_TYPE] = unsigned(indexType as int32);
}

export function contains(this cache: PipelineCache, key: PipelineKey): boolean {
	for (const entry of cache.entries) {
		if (entry.key == key) { return true; }
	}
	return false;
}

function stopOnUnregisteredProgram(program: int32): uint32 {
	console.log(`gpu door: program id ${program} was never registered`);
	unreachable;
}

function stopOnRefusedShader(program: int32): uint32 {
	console.log(`gpu door: sokol refused the shader of program ${program}; ` +
		"its pool is full or it did not compile");
	unreachable;
}

function stopOnRefusedPipeline(key: PipelineKey): uint32 {
	console.log(`gpu door: sokol refused pipeline ${key.toString()}; ` +
		"its pool is full or its description is invalid");
	unreachable;
}

function registered(program: int32): boolean {
	return program >= 0 && program < programCount();
}

export function shaderFor(ref cache: PipelineCache, program: int32): uint32 {
	if (!registered(program)) { return stopOnUnregisteredProgram(program); }
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
	if (program < 0 || program >= (cache.blockSlots.length as int32)) { return false; }
	return (cache.blockSlots[program] & ((1 as uint32) << (slot as uint32))) != 0;
}

// PipelineBuilder.lookup + the driver's makePipeline on a miss.
export function pipelineFor(
	ref cache: PipelineCache,
	program: int32,
	layout: int32,
	indexed: boolean,
	state: RenderState,
	targets: TargetLayout,
): uint32 {
	if (!registered(program)) { return stopOnUnregisteredProgram(program); }
	const concrete: TargetLayout = targets.resolved();
	const key: PipelineKey = pipelineKey(program, layout, indexed, state, concrete);
	let found: int32 = cache.entries.length as int32;
	for (let i = 0; i < (cache.entries.length as int32); i++) {
		if (cache.entries[i].key == key) {
			if (cache.entries[i].pipeline != 0) { return cache.entries[i].pipeline; }
			found = i;
		}
	}
	const shader: uint32 = shaderFor(cache, program);
	describePipeline(cache.descriptor, shader, layout, indexed, state, concrete);
	const pipeline: uint32 = makePipeline(cache.descriptor);
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
export function forgetPipelines(ref cache: PipelineCache): void {
	for (let i = 0; i < (cache.entries.length as int32); i++) {
		cache.entries[i].pipeline = 0;
	}
	for (let i = 0; i < (cache.shaders.length as int32); i++) {
		cache.shaders[i] = 0;
	}
}

// Destroys every pipeline and shader, then forgets them.
export function releasePipelines(ref cache: PipelineCache): void {
	for (const entry of cache.entries) {
		if (entry.pipeline != 0) { destroyPipeline(entry.pipeline); }
	}
	for (const shader of cache.shaders) {
		destroyShader(shader);
	}
	forgetPipelines(cache);
}
