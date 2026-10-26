// Compute on the door: a registered compute program runs on storage buffers inside a compute
// pass, the way a render program draws inside a render pass (doorGpu.ms). A program's pipeline is
// keyed by the program alone, as Heaps builds a compute shader's pipeline with no render state
// (h3d/impl/PipelineCache.hx setShader, DX12Driver.hx compileShader); a dispatch is
// Driver.computeDispatch (h3d/impl/Driver.hx).

import { stop } from "./stop";
import { Feature, requireFeature } from "./feature";
import {
	GPUComputePassEncoder,
	GPUComputePipeline,
	GPUShaderModuleDescriptor,
	GPU_RESOURCE_GROUP,
} from "../webgpu/types.ms";
import "../webgpu/device.ms";
import {
	DOOR_BUFFER_STORAGE,
	DOOR_VIEW_SLOTS,
	doorCloseComputePass,
	doorContextGeneration,
	doorDevice,
	doorMakeBufferOf,
	doorOpenComputePass,
	doorRequireComputePass,
	doorStorageGroup,
	frameEncoder,
} from "./doorGpu.ms";

struct ComputeProgram {
	source: (index: int32) => GPUShaderModuleDescriptor;
	index: int32;
	slots: uint32;
	pipeline: GPUComputePipeline;
}

let programs: Vec<ComputeProgram> = [];
let builtFor: int32 = 0;
let computePass: GPUComputePassEncoder = { id: 0 };
// The program whose pipeline this pass applied last, -1 for none, and whether its storage
// slots, if it has any, were bound since.
let applied: int32 = -1;
let bound = false;

// `source(i)` builds the module of program i for i in 0..count. A compute program binds storage
// buffers in group 1 at slots below DOOR_VIEW_SLOTS; any other binding is refused here.
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
		let slots: uint32 = 0;
		for (const binding of reflected.bindings) {
			if ((binding.kind as string) == "") { continue; }
			if (binding.kind != "storage-buffer") {
				stop(`compute program ${i} binds a ${binding.kind} at ${binding.binding}; ` +
					"the door carries storage buffers only");
			}
			if (binding.group != GPU_RESOURCE_GROUP || binding.binding < 0 ||
				binding.binding >= DOOR_VIEW_SLOTS) {
				stop(`compute program ${i} binds a storage buffer at group ${binding.group} ` +
					`binding ${binding.binding}; the door takes group ${GPU_RESOURCE_GROUP}, ` +
					`slots 0..${DOOR_VIEW_SLOTS - 1}`);
			}
			slots |= (1 as uint32) << (binding.binding as uint32);
		}
		programs.push({ source, index: i, slots, pipeline: { id: 0 } });
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

// Pipelines belong to the device that made them; a new setup leaves the registrations and drops
// the handles, as pipeline.ms does for a render cache.
function adoptContext(): void {
	const generation = doorContextGeneration();
	if (builtFor == generation) { return; }
	for (let i = 0; i < programs.length; i++) { programs[i].pipeline = { id: 0 }; }
	computePass = { id: 0 };
	applied = -1;
	bound = false;
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
	bound = programs[found].slots == 0;
}

// `buffers[slot]` is the storage buffer of each slot the applied program binds.
export function applyComputeBindings(buffers: Readonly<Span<uint32>>): void {
	doorRequireComputePass("applyComputeBindings");
	if (applied < 0) { stop("applyComputeBindings before applyComputePipeline"); }
	const slots = programs[applied].slots;
	for (let slot = 0; slot < DOOR_VIEW_SLOTS; slot++) {
		if ((slots & ((1 as uint32) << (slot as uint32))) == 0) { continue; }
		if (slot >= (buffers.length as int32) || buffers[slot] == 0) {
			stop(`applyComputeBindings holds no buffer for the storage slot ${slot} the program binds`);
		}
	}
	if (slots != 0) {
		computePass.setBindGroup(
			GPU_RESOURCE_GROUP,
			doorStorageGroup(programs[applied].pipeline, slots, buffers),
			[],
		);
	}
	bound = true;
}

export function computeDispatch(x: int32, y: int32, z: int32): void {
	doorRequireComputePass("computeDispatch");
	if (applied < 0) { stop("computeDispatch before applyComputePipeline"); }
	if (!bound) {
		stop("computeDispatch with a pipeline whose storage slots were not bound since it was applied");
	}
	computePass.dispatchWorkgroups(x, y, z);
}

export function endComputePass(): void {
	doorCloseComputePass();
	computePass.end();
	computePass = { id: 0 };
	applied = -1;
	bound = false;
}
