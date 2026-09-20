// Port of h3d.impl.PipelineCache / PipelineBuilder: render state + program + vertex layout +
// target formats → one key → one sokol pipeline, created on first use and reused after.
//
// Heaps hashes a byte signature and compares it on collision. Everything that selects a
// pipeline here packs into 64 bits, so the key is the signature itself and a lookup is a scan
// over a few dozen uint64s. Entries keep their key after `forgetPipelines`,
// and every `pipelineFor` call brings the full description, so a pipeline lost with the GPU
// context is built again from CPU data on its next use.

import { RenderState } from "./pass";
import { TargetLayout } from "./target";
import {
	Program,
	VertexLayout,
	IndexType,
	makeShader,
	makePipeline,
	destroyShader,
	destroyPipeline,
} from "./gpu3d";
import {
	GPU3D_PIPELINE_SHADER,
	GPU3D_PIPELINE_LAYOUT,
	GPU3D_PIPELINE_CULLING,
	GPU3D_PIPELINE_DEPTH_TEST,
	GPU3D_PIPELINE_DEPTH_WRITE,
	GPU3D_PIPELINE_BLEND_SOURCE,
	GPU3D_PIPELINE_BLEND_DESTINATION,
	GPU3D_PIPELINE_BLEND_ALPHA_SOURCE,
	GPU3D_PIPELINE_BLEND_ALPHA_DESTINATION,
	GPU3D_PIPELINE_BLEND_OPERATION,
	GPU3D_PIPELINE_BLEND_ALPHA_OPERATION,
	GPU3D_PIPELINE_COLOR_MASK,
	GPU3D_PIPELINE_COLOR_FORMAT,
	GPU3D_PIPELINE_DEPTH_FORMAT,
	GPU3D_PIPELINE_SAMPLE_COUNT,
	GPU3D_PIPELINE_INDEX_TYPE,
	GPU3D_PIPELINE_LENGTH,
} from "./gpu3d.h";

export const PROGRAM_COUNT: int32 = 4;

// Key layout, low to high: vertex layout (3 bits), indexed (1), program (4), target formats
// (24), RenderState.bits (32) — 64 bits, exactly full. The indexed flag shares a nibble with
// the vertex layout because `VertexLayout` has three members and RenderState already owns a
// whole word; `LAYOUT_LIMIT` is what the tests hold that constraint against.
const INDEXED_SHIFT: uint64 = 3;
const PROGRAM_SHIFT: uint64 = 4;
const TARGETS_SHIFT: uint64 = 8;
const STATE_SHIFT: uint64 = 32;
const LAYOUT_MASK: uint64 = 7;
const NIBBLE: uint64 = 15;
const TARGETS_MASK: uint64 = 16777215;
const STATE_MASK: uint64 = 4294967295;

// One more VertexLayout than this and the key needs a second word.
export const LAYOUT_LIMIT: int32 = 8;

// Everything that selects a pipeline, packed; decodes back into its parts.
export struct PipelineKey {
	bits: uint64;
}

export struct PipelineEntry {
	key: PipelineKey;
	pipeline: uint32;
}

export struct PipelineCache {
	entries: Vec<PipelineEntry>;
	shaders: Vec<uint32>;
	descriptor: Vec<uint32>;
}

export function empty(this typeof PipelineCache): PipelineCache {
	const shaders: Vec<uint32> = new Array(PROGRAM_COUNT);
	for (let i = 0; i < PROGRAM_COUNT; i++) {
		shaders[i] = 0;
	}
	return { entries: [], shaders: shaders, descriptor: new Array(GPU3D_PIPELINE_LENGTH) };
}

function ordinal(value: int32): uint64 {
	return (value as uint32) as uint64;
}

export function pipelineKey(
	program: Program,
	layout: VertexLayout,
	indexed: boolean,
	state: RenderState,
	targets: TargetLayout,
): PipelineKey {
	return {
		// Masked on encode as well as on decode: an ordinal of 8 would otherwise set bit 3 and
		// be indistinguishable from `indexed` on layout 0 (LAYOUT_LIMIT is the real guard).
		bits: (ordinal(layout as int32) & LAYOUT_MASK) |
			((indexed ? 1 : 0) as uint64) << INDEXED_SHIFT |
			(ordinal(program as int32) << PROGRAM_SHIFT) |
			((targets.formatBits() as uint64) << TARGETS_SHIFT) |
			((state.bits() as uint64) << STATE_SHIFT),
	};
}

export function vertexLayout(this key: PipelineKey): VertexLayout {
	return ((key.bits & LAYOUT_MASK) as int32) as VertexLayout;
}

export function isIndexed(this key: PipelineKey): boolean {
	return ((key.bits >> INDEXED_SHIFT) & 1) != 0;
}

export function indexType(this key: PipelineKey): IndexType {
	return key.isIndexed() ? IndexType.Uint16 : IndexType.None;
}

export function program(this key: PipelineKey): Program {
	return (((key.bits >> PROGRAM_SHIFT) & NIBBLE) as int32) as Program;
}

export function targetLayout(this key: PipelineKey): TargetLayout {
	return TargetLayout.fromFormatBits(((key.bits >> TARGETS_SHIFT) & TARGETS_MASK) as uint32);
}

export function renderState(this key: PipelineKey): RenderState {
	return RenderState.fromBits(((key.bits >> STATE_SHIFT) & STATE_MASK) as uint32);
}

// `program=Lit layout=Lit colors=… depth=… sampleCount=… culling=…`: which pipeline a
// cache entry is, for logs and for comparing two entries by eye.
export function toString(this key: PipelineKey): string {
	return `program=${key.program().toString()} layout=${key.vertexLayout().toString()} ` +
		`indexType=${key.indexType().toString()} ` +
		`${key.targetLayout().toString()} ${key.renderState().toString()}`;
}

function unsigned(value: int32): uint32 {
	return value as uint32;
}

// The flat sg_pipeline_desc that gpu3d.c reads (GPU3D_PIPELINE_*).
export function describePipeline(
	out: Span<uint32>,
	shader: uint32,
	layout: VertexLayout,
	indexed: boolean,
	state: RenderState,
	targets: TargetLayout,
): void {
	out[GPU3D_PIPELINE_SHADER] = shader;
	out[GPU3D_PIPELINE_LAYOUT] = unsigned(layout as int32);
	out[GPU3D_PIPELINE_CULLING] = unsigned(state.culling as int32);
	out[GPU3D_PIPELINE_DEPTH_TEST] = unsigned(state.depthTest as int32);
	out[GPU3D_PIPELINE_DEPTH_WRITE] = state.depthWrite ? 1 : 0;
	out[GPU3D_PIPELINE_BLEND_SOURCE] = unsigned(state.blendSource as int32);
	out[GPU3D_PIPELINE_BLEND_DESTINATION] = unsigned(state.blendDestination as int32);
	out[GPU3D_PIPELINE_BLEND_ALPHA_SOURCE] = unsigned(state.blendAlphaSource as int32);
	out[GPU3D_PIPELINE_BLEND_ALPHA_DESTINATION] = unsigned(state.blendAlphaDestination as int32);
	out[GPU3D_PIPELINE_BLEND_OPERATION] = unsigned(state.blendOperation as int32);
	out[GPU3D_PIPELINE_BLEND_ALPHA_OPERATION] = unsigned(state.blendAlphaOperation as int32);
	out[GPU3D_PIPELINE_COLOR_MASK] = unsigned(state.colorMask);
	out[GPU3D_PIPELINE_COLOR_FORMAT] = unsigned(targets.color0 as int32);
	out[GPU3D_PIPELINE_COLOR_FORMAT + 1] = unsigned(targets.color1 as int32);
	out[GPU3D_PIPELINE_COLOR_FORMAT + 2] = unsigned(targets.color2 as int32);
	out[GPU3D_PIPELINE_COLOR_FORMAT + 3] = unsigned(targets.color3 as int32);
	out[GPU3D_PIPELINE_DEPTH_FORMAT] = unsigned(targets.depth as int32);
	out[GPU3D_PIPELINE_SAMPLE_COUNT] = unsigned(targets.sampleCount);
	out[GPU3D_PIPELINE_INDEX_TYPE] = unsigned((indexed ? IndexType.Uint16 : IndexType.None) as int32);
}

export function contains(this cache: PipelineCache, key: PipelineKey): boolean {
	for (const entry of cache.entries) {
		if (entry.key.bits == key.bits) { return true; }
	}
	return false;
}

export function shaderFor(ref cache: PipelineCache, program: Program): uint32 {
	const index: int32 = program as int32;
	if (cache.shaders[index] == 0) {
		cache.shaders[index] = makeShader(program);
	}
	return cache.shaders[index];
}

// PipelineBuilder.lookup + the driver's makePipeline on a miss.
export function pipelineFor(
	ref cache: PipelineCache,
	program: Program,
	layout: VertexLayout,
	indexed: boolean,
	state: RenderState,
	targets: TargetLayout,
): uint32 {
	const key: PipelineKey = pipelineKey(program, layout, indexed, state, targets);
	let found: int32 = cache.entries.length as int32;
	for (let i = 0; i < (cache.entries.length as int32); i++) {
		if (cache.entries[i].key.bits == key.bits) {
			if (cache.entries[i].pipeline != 0) { return cache.entries[i].pipeline; }
			found = i;
		}
	}
	const shader: uint32 = shaderFor(cache, program);
	describePipeline(cache.descriptor, shader, layout, indexed, state, targets);
	const pipeline: uint32 = makePipeline(cache.descriptor);
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
	for (let i = 0; i < PROGRAM_COUNT; i++) {
		cache.shaders[i] = 0;
	}
}

// Destroys every pipeline and shader, then forgets them.
export function releasePipelines(ref cache: PipelineCache): void {
	for (const entry of cache.entries) {
		if (entry.pipeline != 0) { destroyPipeline(entry.pipeline); }
	}
	for (const shader of cache.shaders) {
		if (shader != 0) { destroyShader(shader); }
	}
	forgetPipelines(cache);
}
