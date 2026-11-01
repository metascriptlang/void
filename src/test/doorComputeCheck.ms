// Compute through the door: a registered compute program runs on storage buffers the way a render
// program draws, and the pass state refuses a draw call inside a compute pass and a compute call
// outside one. The dispatch result is read back on d3d11, which executes it.

import { computeModule, programSource } from "../shader/descriptor";
import { glslComputeIr } from "../shader/emit";
import { ShaderTarget } from "../shader/layout";
import { AtomicI32, Vec3u, access, atomicStore, binding, builtin } from "../shader/std";
import { GPUComputePipeline, GPUShaderModuleDescriptor } from "../webgpu/types.ms";
import { PassState, computeCallRefusal, openPassRefusal, renderCallRefusal } from "../gpu/doorGpu.ms";

when (voidDummy || (windows && !voidVulkan)) {
	import {
		DOOR_BUFFER_INDIRECT,
		DOOR_BUFFER_STORAGE,
		doorCopyBuffer,
		doorMakeBuffer,
		doorMakeBufferOf,
		doorPassState,
		doorReadBuffer,
		doorSetup,
		doorShutdown,
		doorStorageGroup,
		doorUpdateBufferAtOf,
	} from "../gpu/doorGpu.ms";
	import {
		applyComputeBindings,
		applyComputePipeline,
		applyComputeResources,
		applyComputeUniformsOf,
		beginComputePass,
		computeDispatch,
		computeDispatchIndirect,
		computePipelineFor,
		computeSlotMask,
		computeUniformMask,
		endComputePass,
		makeStorageBuffer,
		registerComputePrograms,
	} from "../gpu/doorCompute.ms";
}
when (windows && !voidDummy && !voidVulkan) {
	import { warpDevice, warpContext } from "./d3d11Warp.h";
	@passL("-ld3d11");
}

const WORKGROUP = 8;
const RGBA8 = 2;
const NO_DEPTH = 0;

export struct DoubleInput {
	@builtin(globalInvocationId) id: Vec3u;
}

export struct Cell {
	value: int32;
}

export struct Slot {
	value: AtomicI32;
}

export struct DoubleBindings {
	@binding(0) @access(read) source: Cell[];
	@binding(1) @access(read_write) result: Slot[];
}

export function doubleKernel(input: DoubleInput, b: DoubleBindings): void {
	const i = input.id.x;
	atomicStore(b.result[i].value, b.source[i].value * 2);
}

export struct Scale {
	factor: float32;
	bias: float32;
}

export struct ScaledBindings {
	@binding(0) scale: Scale;
	@binding(0) @access(read) source: Cell[];
	@binding(1) @access(read_write) result: Slot[];
}

export function scaledKernel(input: DoubleInput, b: ScaledBindings): void {
	const i = input.id.x;
	const value = (b.source[i].value as float32) * b.scale.factor + b.scale.bias;
	atomicStore(b.result[i].value, value as int32);
}

function doubleDescriptor(index: int32): GPUShaderModuleDescriptor {
	return kernelDescriptor("doubleKernel", glslComputeIr(doubleKernel, [8, 1, 1]));
}

function scaledDescriptor(index: int32): GPUShaderModuleDescriptor {
	return kernelDescriptor("scaledKernel", glslComputeIr(scaledKernel, [8, 1, 1]));
}

function kernelDescriptor(label: string, text: string): GPUShaderModuleDescriptor {
	const module = computeModule(text, []);
	if (!module.ok) { console.log(`${label}: ${module.error}`); unreachable; }
	const source = programSource(module.value, ShaderTarget.Hlsl5);
	if (!source.ok) { console.log(`${label}: ${source.error}`); unreachable; }
	if (source.value.refusal != "") { console.log(`${label}: ${source.value.refusal}`); unreachable; }
	let descriptor: GPUShaderModuleDescriptor = {
		label,
		computeCode: source.value.computeCode,
		computeEntryPoint: source.value.entryPoint,
	};
	descriptor.workgroupSize = [
		source.value.reflection.workgroupSize[0],
		source.value.reflection.workgroupSize[1],
		source.value.reflection.workgroupSize[2],
	];
	for (let i = 0; i < source.value.reflection.bindings.length; i++) {
		descriptor.bindings[i] = source.value.reflection.bindings[i];
	}
	return descriptor;
}

test "a pass state names the call and the pass that would end it" {
	assert openPassRefusal("beginComputePass", PassState.None) == "";
	assert openPassRefusal("beginComputePass", PassState.Screen)
		== "beginComputePass with a pass already open; endPass ends it";
	assert openPassRefusal("beginPass", PassState.Compute)
		== "beginPass with a pass already open; endComputePass ends it";
}

test "a draw call inside a compute pass is refused and outside one it is not" {
	assert renderCallRefusal("draw", PassState.Compute)
		== "draw inside a compute pass; endComputePass ends it";
	assert renderCallRefusal("draw", PassState.None) == "";
	assert renderCallRefusal("draw", PassState.Target) == "";
}

test "a compute call needs an open compute pass and says which pass is open instead" {
	assert computeCallRefusal("computeDispatch", PassState.Compute) == "";
	assert computeCallRefusal("computeDispatch", PassState.None)
		== "computeDispatch with no compute pass open; beginComputePass opens one";
	assert computeCallRefusal("computeDispatch", PassState.Target)
		== "computeDispatch inside a render pass; endPass ends it before beginComputePass opens a compute pass";
}

when (voidDummy || (windows && !voidVulkan)) {
	function openDoor(): void {
		when (voidDummy) {
			doorSetup(null, null, RGBA8, NO_DEPTH, 1);
		} else {
			doorSetup(warpDevice(), warpContext(), RGBA8, NO_DEPTH, 1);
		}
	}

	function cellsOf(values: Vec<int32>): Cell[] {
		let cells: Cell[] = [];
		for (const value of values) { cells.push({ value }); }
		return cells;
	}

	function slotsOf(values: Vec<int32>): Slot[] {
		let slots: Slot[] = [];
		for (const value of values) { slots.push({ value: { value } }); }
		return slots;
	}

	function wordAt(bytes: Vec<uint8>, index: int32): int32 {
		return (bytes[index * 4] as int32) + (bytes[index * 4 + 1] as int32) * 256 +
			(bytes[index * 4 + 2] as int32) * 65536;
	}

	test "a registered compute program declares the storage slots it reads and writes" {
		openDoor();
		const base = registerComputePrograms(doubleDescriptor, 1);
		assert computeSlotMask(base) == 3;
		doorShutdown();
	}

	test "a compute pass dispatches a registered program over storage buffers and the pass state follows" {
		openDoor();
		const base = registerComputePrograms(doubleDescriptor, 1);
		const values: Vec<int32> = [1, 2, 3, 4, 5, 6, 7, 40000];
		const zeros: Vec<int32> = [0, 0, 0, 0, 0, 0, 0, 0];
		const source = makeStorageBuffer(values);
		const result = makeStorageBuffer(zeros);
		assert doorPassState() == (PassState.None as int32);
		beginComputePass();
		assert doorPassState() == (PassState.Compute as int32);
		applyComputePipeline(computePipelineFor(base));
		applyComputeBindings([source, result]);
		computeDispatch(1, 1, 1);
		endComputePass();
		assert doorPassState() == (PassState.None as int32);
		let out: Vec<uint8> = new Array(WORKGROUP * 4);
		assert doorReadBuffer(result, out) == 1;
		when (windows && !voidDummy) {
			const cpu: DoubleBindings = { source: cellsOf(values), result: slotsOf(zeros) };
			for (let i = 0; i < WORKGROUP; i++) {
				doubleKernel({ id: { x: i as uint32, y: 0, z: 0 } }, cpu);
				assert wordAt(out, i) == cpu.result[i].value.value;
			}
			assert wordAt(out, 7) == 80000;
		}
		let wrong: Vec<uint8> = new Array(WORKGROUP * 4 - 1);
		assert doorReadBuffer(result, wrong) == 0;
		doorShutdown();
	}

	test "the compute pipeline of a program is made once and answers the same id" {
		openDoor();
		const base = registerComputePrograms(doubleDescriptor, 1);
		assert computePipelineFor(base) == computePipelineFor(base);
		assert computePipelineFor(base) != 0;
		doorShutdown();
	}

	function readWords(buffer: uint32, count: int32): Vec<uint8> {
		let out: Vec<uint8> = new Array(count * 4);
		if (doorReadBuffer(buffer, out) != 1) { console.log(`readBuffer of ${buffer} failed`); unreachable; }
		return out;
	}

	test "a compute program reads a uniform block applied from the frame's uniform ring" {
		openDoor();
		const base = registerComputePrograms(scaledDescriptor, 1);
		assert computeUniformMask(base) == 1;
		assert computeSlotMask(base) == 3;
		const values: Vec<int32> = [1, 2, 3, 4, 5, 6, 7, 40000];
		const zeros: Vec<int32> = [0, 0, 0, 0, 0, 0, 0, 0];
		const source = makeStorageBuffer(values);
		const result = makeStorageBuffer(zeros);
		const block: Vec<float32> = [3.0, 1.0, 0.0, 0.0];
		beginComputePass();
		applyComputePipeline(computePipelineFor(base));
		applyComputeBindings([source, result]);
		applyComputeUniformsOf(0, block);
		computeDispatch(1, 1, 1);
		endComputePass();
		const out = readWords(result, WORKGROUP);
		when (windows && !voidDummy) {
			for (let i = 0; i < WORKGROUP; i++) { assert wordAt(out, i) == values[i] * 3 + 1; }
		}
		doorShutdown();
	}

	test "an indirect dispatch reads its workgroup counts at an offset of an indirect buffer" {
		openDoor();
		const base = registerComputePrograms(doubleDescriptor, 1);
		const values: Vec<int32> = [1, 2, 3, 4, 5, 6, 7, 8];
		const zeros: Vec<int32> = [0, 0, 0, 0, 0, 0, 0, 0];
		const counts: Vec<uint32> = [0, 0, 0, 1, 1, 1];
		const source = makeStorageBuffer(values);
		const result = makeStorageBuffer(zeros);
		const args = doorMakeBufferOf(DOOR_BUFFER_INDIRECT, counts);
		beginComputePass();
		applyComputePipeline(computePipelineFor(base));
		applyComputeBindings([source, result]);
		computeDispatchIndirect(args, 12);
		endComputePass();
		const out = readWords(result, WORKGROUP);
		when (windows && !voidDummy) {
			for (let i = 0; i < WORKGROUP; i++) { assert wordAt(out, i) == values[i] * 2; }
		}
		doorShutdown();
	}

	test "a buffer copy moves a range between storage buffers at their offsets" {
		openDoor();
		const values: Vec<int32> = [1, 2, 3, 4, 5, 6, 7, 8];
		const zeros: Vec<int32> = [0, 0, 0, 0, 0, 0, 0, 0];
		const source = makeStorageBuffer(values);
		const destination = makeStorageBuffer(zeros);
		doorCopyBuffer(source, 8, destination, 16, 8);
		const out = readWords(destination, WORKGROUP);
		when (windows && !voidDummy) {
			assert wordAt(out, 3) == 0;
			assert wordAt(out, 4) == 3;
			assert wordAt(out, 5) == 4;
			assert wordAt(out, 6) == 0;
		}
		doorShutdown();
	}

	test "a buffer update writes at its byte offset and is refused past the buffer's end" {
		openDoor();
		const none: Vec<uint8> = [];
		const buffer = doorMakeBuffer(DOOR_BUFFER_STORAGE, none, 32);
		const pair: Vec<int32> = [7, 9];
		const one: Vec<int32> = [11];
		assert doorUpdateBufferAtOf(buffer, 8, pair) == 1;
		assert doorUpdateBufferAtOf(buffer, 16, one) == 1;
		assert doorUpdateBufferAtOf(buffer, 28, pair) == 0;
		assert doorUpdateBufferAtOf(buffer, -4, one) == 0;
		const out = readWords(buffer, WORKGROUP);
		when (windows && !voidDummy) {
			assert wordAt(out, 2) == 7;
			assert wordAt(out, 3) == 9;
			assert wordAt(out, 4) == 11;
		}
		doorShutdown();
	}

	test "storage groups of one buffer at different offsets or sizes are different groups" {
		openDoor();
		const base = registerComputePrograms(doubleDescriptor, 1);
		const pipeline: GPUComputePipeline = { id: computePipelineFor(base) };
		const none: Vec<uint8> = [];
		const cells = doorMakeBuffer(DOOR_BUFFER_STORAGE, none, 1024);
		const result = doorMakeBuffer(DOOR_BUFFER_STORAGE, none, 256);
		const noSamplers: Vec<uint32> = [];
		const resources: Vec<uint32> = [cells, result];
		const atStart: Vec<int64> = [0, 0];
		const atNext: Vec<int64> = [256, 0];
		const quarter: Vec<int64> = [256, 0];
		const half: Vec<int64> = [512, 0];
		const first = doorStorageGroup(pipeline, 3, 0, 0, resources, atStart, quarter, noSamplers);
		const second = doorStorageGroup(pipeline, 3, 0, 0, resources, atNext, quarter, noSamplers);
		const wider = doorStorageGroup(pipeline, 3, 0, 0, resources, atStart, half, noSamplers);
		assert first.id != 0;
		assert first.id != second.id;
		assert first.id != wider.id;
		assert second.id != wider.id;
		assert doorStorageGroup(pipeline, 3, 0, 0, resources, atStart, quarter, noSamplers).id == first.id;
		doorShutdown();
	}

	test "a dispatch writes a storage buffer bound at an offset and leaves the bytes before it" {
		openDoor();
		const base = registerComputePrograms(doubleDescriptor, 1);
		const values: Vec<int32> = [1, 2, 3, 4, 5, 6, 7, 8];
		const source = makeStorageBuffer(values);
		const none: Vec<uint8> = [];
		const result = doorMakeBuffer(DOOR_BUFFER_STORAGE, none, 512);
		const resources: Vec<uint32> = [source, result];
		const offsets: Vec<int64> = [0, 256];
		const sizes: Vec<int64> = [0, 32];
		const noSamplers: Vec<uint32> = [];
		beginComputePass();
		applyComputePipeline(computePipelineFor(base));
		applyComputeResources(resources, offsets, sizes, noSamplers);
		computeDispatch(1, 1, 1);
		endComputePass();
		const out = readWords(result, 128);
		when (windows && !voidDummy) {
			assert wordAt(out, 0) == 0;
			assert wordAt(out, 63) == 0;
			for (let i = 0; i < WORKGROUP; i++) { assert wordAt(out, 64 + i) == values[i] * 2; }
		}
		doorShutdown();
	}
}
