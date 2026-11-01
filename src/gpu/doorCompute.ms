// Compute on the door: a registered compute program runs on storage buffers inside a compute
// pass, the way a render program draws inside a render pass (doorGpu.ms). A program's pipeline is
// keyed by the program alone, as Heaps builds a compute shader's pipeline with no render state
// (h3d/impl/PipelineCache.hx setShader, DX12Driver.hx compileShader); a dispatch is
// Driver.computeDispatch (h3d/impl/Driver.hx).

import { stop } from "./stop";
import { Feature, requireFeature } from "./feature";
import {
	GPUBindGroup,
	GPUComputePassEncoder,
	GPUComputePipeline,
	GPUShaderModuleDescriptor,
	GPU_RESOURCE_GROUP,
	GPU_UNIFORM_GROUP,
	DUMMY_SAMPLER_BINDING,
} from "../webgpu/types.ms";
import "../webgpu/device.ms";
import {
	DOOR_BUFFER_STORAGE,
	DOOR_SAMPLER_BINDING_BASE,
	DOOR_SAMPLER_SLOTS,
	DOOR_UNIFORM_SLOTS,
	DOOR_VIEW_SLOTS,
	doorCloseComputePass,
	doorContextGeneration,
	doorDevice,
	doorMakeBufferOf,
	doorOpenComputePass,
	doorRequireComputePass,
	doorStageUniformsOf,
	doorStorageGroup,
	doorUniformGroup,
	frameEncoder,
} from "./doorGpu.ms";

struct ComputeProgram {
	source: (index: int32) => GPUShaderModuleDescriptor;
	index: int32;
	slots: uint32;
	views: uint32;
	samplers: uint32;
	uniforms: uint32;
	uniformBytes: int32[DOOR_UNIFORM_SLOTS];
	pipeline: GPUComputePipeline;
	uniformGroup: GPUBindGroup;
}

let programs: Vec<ComputeProgram> = [];
let builtFor: int32 = 0;
let computePass: GPUComputePassEncoder = { id: 0 };
// The program whose pipeline this pass applied last, -1 for none, and whether its storage
// slots, if it has any, were bound since.
let applied: int32 = -1;
let bound = false;
let appliedBlocks: uint32 = 0;
let uniformOffsets: uint32[DOOR_UNIFORM_SLOTS] = [0, 0, 0, 0, 0, 0, 0, 0];

function bitOf(slot: int32): uint32 { return (1 as uint32) << (slot as uint32); }

function resourceSlot(program: int32, kind: string, group: int32, binding: int32): int32 {
	if (group != GPU_RESOURCE_GROUP || binding < 0 || binding >= DOOR_VIEW_SLOTS) {
		stop(`compute program ${program} binds a ${kind} at group ${group} binding ${binding}; ` +
			`the door takes group ${GPU_RESOURCE_GROUP}, slots 0..${DOOR_VIEW_SLOTS - 1}`);
	}
	return binding;
}

// `source(i)` builds the module of program i for i in 0..count. A compute program binds as a
// render program does: uniform blocks in group 0, storage buffers, textures, storage textures
// and samplers in group 1; any other binding is refused here.
export function registerComputePrograms(
	source: (index: int32) => GPUShaderModuleDescriptor,
	count: int32,
): int32 {
	const base = programs.length as int32;
	for (let i = 0; i < count; i++) {
		const reflected = source(i);
		if (reflected.computeCode == "" && reflected.computeBytecode.length == 0) {
			stop(`compute program ${i} has no compute stage`);
		}
		let record: ComputeProgram = {
			source,
			index: i,
			pipeline: { id: 0 },
			uniformGroup: { id: 0 },
		};
		for (const binding of reflected.bindings) {
			const kind = binding.kind;
			if (kind == null) { continue; }
			if (kind == "uniform") {
				if (binding.group != GPU_UNIFORM_GROUP || binding.binding < 0 ||
					binding.binding >= DOOR_UNIFORM_SLOTS) {
					stop(`compute program ${i} reads a uniform block at group ${binding.group} ` +
						`binding ${binding.binding}; the door takes group ${GPU_UNIFORM_GROUP}, ` +
						`slots 0..${DOOR_UNIFORM_SLOTS - 1}`);
				}
				record.uniforms |= bitOf(binding.binding);
				record.uniformBytes[binding.binding] = binding.size;
			} else if (kind == "storage-buffer") {
				record.slots |= bitOf(resourceSlot(i, kind, binding.group, binding.binding));
			} else if (kind == "texture" || kind == "storage-texture") {
				record.views |= bitOf(resourceSlot(i, kind, binding.group, binding.binding));
			} else if (binding.binding != DUMMY_SAMPLER_BINDING) {
				const slot = binding.binding - DOOR_SAMPLER_BINDING_BASE;
				if (binding.group != GPU_RESOURCE_GROUP || slot < 0 || slot >= DOOR_SAMPLER_SLOTS) {
					stop(`compute program ${i} binds a sampler at group ${binding.group} binding ` +
						`${binding.binding}; the door takes group ${GPU_RESOURCE_GROUP}, bindings ` +
						`${DOOR_SAMPLER_BINDING_BASE}..` +
						`${DOOR_SAMPLER_BINDING_BASE + DOOR_SAMPLER_SLOTS - 1}`);
				}
				record.samplers |= bitOf(slot);
			}
		}
		programs.push(record);
	}
	return base;
}

function programAt(program: int32): ComputeProgram {
	if (program < 0 || program >= (programs.length as int32)) {
		stop(`unregistered compute program id ${program}`);
	}
	return programs[program];
}

// Bit n set when `program` binds a storage buffer at slot n.
export function computeSlotMask(program: int32): uint32 {
	return programAt(program).slots;
}

export function computeViewMask(program: int32): uint32 {
	return programAt(program).views;
}

export function computeSamplerMask(program: int32): uint32 {
	return programAt(program).samplers;
}

export function computeUniformMask(program: int32): uint32 {
	return programAt(program).uniforms;
}

// Pipelines belong to the device that made them; a new setup leaves the registrations and drops
// the handles, as pipeline.ms does for a render cache.
function adoptContext(): void {
	const generation = doorContextGeneration();
	if (builtFor == generation) { return; }
	for (let i = 0; i < programs.length; i++) {
		programs[i].pipeline = { id: 0 };
		programs[i].uniformGroup = { id: 0 };
	}
	computePass = { id: 0 };
	applied = -1;
	bound = false;
	appliedBlocks = 0;
	builtFor = generation;
}

export function computePipelineFor(program: int32): uint32 {
	const record = programAt(program);
	adoptContext();
	if (record.pipeline.id != 0) { return record.pipeline.id; }
	const device = doorDevice();
	const descriptor = record.source(record.index);
	const module = device.createShaderModule(descriptor);
	if (module.id == 0) { stop(`the device refused the compute shader of program ${program}`); }
	const pipeline = device.createComputePipeline({
		label: descriptor.label,
		compute: { module, entryPoint: descriptor.computeEntryPoint },
	});
	if (pipeline.id == 0) { stop(`the device refused the compute pipeline of program ${program}`); }
	programs[program].pipeline = pipeline;
	if (record.uniforms != 0) {
		programs[program].uniformGroup = doorUniformGroup(
			pipeline.getBindGroupLayout(GPU_UNIFORM_GROUP),
			record.uniforms,
			record.uniformBytes,
		);
	}
	return pipeline.id;
}

export function makeStorageBuffer<T>(data: Readonly<Span<T>>): uint32 {
	return doorMakeBufferOf(DOOR_BUFFER_STORAGE, data);
}

export function beginComputePass(): void {
	requireFeature(Feature.Compute, "beginComputePass");
	adoptContext();
	doorOpenComputePass();
	computePass = frameEncoder().beginComputePass({ label: null });
	applied = -1;
	bound = false;
	appliedBlocks = 0;
}

export function applyComputePipeline(pipeline: uint32): void {
	doorRequireComputePass("applyComputePipeline");
	let found = -1;
	for (let i = 0; i < programs.length; i++) {
		if (programs[i].pipeline.id == pipeline) { found = i as int32; }
	}
	if (pipeline == 0 || found < 0) {
		stop(`applyComputePipeline of pipeline ${pipeline}, which computePipelineFor did not make`);
	}
	computePass.setPipeline({ id: pipeline });
	applied = found;
	const record = programs[found];
	bound = (record.slots | record.views | record.samplers) == 0;
	appliedBlocks = 0;
	uniformOffsets = [0, 0, 0, 0, 0, 0, 0, 0];
}

// `buffers[slot]` is the storage buffer of each slot the applied program binds.
export function applyComputeBindings(buffers: Readonly<Span<uint32>>): void {
	applyComputeResources(buffers, [], [], []);
}

// `resources[slot]` is the storage buffer or texture view of each slot the applied program
// binds, a buffer bound from byte `offsets[slot]` over `sizes[slot]` bytes or, for 0, the rest.
export function applyComputeResources(
	resources: Readonly<Span<uint32>>,
	offsets: Readonly<Span<int64>>,
	sizes: Readonly<Span<int64>>,
	samplers: Readonly<Span<uint32>>,
): void {
	doorRequireComputePass("applyComputeBindings");
	if (applied < 0) { stop("applyComputeBindings before applyComputePipeline"); }
	const record = programs[applied];
	for (let slot = 0; slot < DOOR_VIEW_SLOTS; slot++) {
		if (((record.slots | record.views) & bitOf(slot)) == 0) { continue; }
		if (slot >= (resources.length as int32) || resources[slot] == 0) {
			const what = (record.slots & bitOf(slot)) != 0 ? "buffer" : "view";
			stop(`applyComputeBindings holds no ${what} for the slot ${slot} the program binds`);
		}
	}
	for (let slot = 0; slot < DOOR_SAMPLER_SLOTS; slot++) {
		if ((record.samplers & bitOf(slot)) == 0) { continue; }
		if (slot >= (samplers.length as int32) || samplers[slot] == 0) {
			stop(`applyComputeBindings holds no sampler for the sampler slot ${slot} ` +
				"the program binds");
		}
	}
	if ((record.slots | record.views | record.samplers) != 0) {
		computePass.setBindGroup(
			GPU_RESOURCE_GROUP,
			doorStorageGroup(
				record.pipeline, record.slots, record.views, record.samplers,
				resources, offsets, sizes, samplers,
			),
			[],
		);
	}
	bound = true;
}

export function applyComputeUniformsOf<T>(slot: int32, data: Readonly<Span<T>>): void {
	doorRequireComputePass("applyComputeUniforms");
	if (applied < 0) { stop("applyComputeUniforms before applyComputePipeline"); }
	const record = programs[applied];
	if (slot < 0 || slot >= DOOR_UNIFORM_SLOTS || (record.uniforms & bitOf(slot)) == 0) {
		stop(`applyComputeUniforms to slot ${slot}, where the program reads no uniform block`);
	}
	uniformOffsets[slot] = doorStageUniformsOf(data);
	appliedBlocks |= bitOf(slot);
	let offsets: uint32[DOOR_UNIFORM_SLOTS] = [0, 0, 0, 0, 0, 0, 0, 0];
	let n = 0;
	for (let s = 0; s < DOOR_UNIFORM_SLOTS; s++) {
		if ((record.uniforms & bitOf(s)) == 0) { continue; }
		offsets[n] = uniformOffsets[s];
		n++;
	}
	computePass.setBindGroup(GPU_UNIFORM_GROUP, record.uniformGroup, offsets[0..n]);
}

function requireReady(call: string): void {
	doorRequireComputePass(call);
	if (applied < 0) { stop(`${call} before applyComputePipeline`); }
	if (!bound) {
		stop(`${call} with a pipeline whose storage slots were not bound since it was applied`);
	}
	const missing = programs[applied].uniforms & ~appliedBlocks;
	for (let s = 0; s < DOOR_UNIFORM_SLOTS; s++) {
		if ((missing & bitOf(s)) != 0) {
			stop(`${call} with a pipeline that reads a uniform block at slot ${s} and none was ` +
				"applied since the pipeline was set");
		}
	}
}

export function computeDispatch(x: int32, y: int32, z: int32): void {
	requireReady("computeDispatch");
	computePass.dispatchWorkgroups(x, y, z);
}

export function computeDispatchIndirect(buffer: uint32, offset: int64): void {
	requireReady("computeDispatchIndirect");
	computePass.dispatchWorkgroupsIndirect({ id: buffer }, offset);
}

export function endComputePass(): void {
	doorCloseComputePass();
	computePass.end();
	computePass = { id: 0 };
	applied = -1;
	bound = false;
	appliedBlocks = 0;
}
