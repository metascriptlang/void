// Compute through the door: a registered compute program runs on storage buffers the way a render
// program draws, and the pass state refuses a draw call inside a compute pass and a compute call
// outside one. The dispatch result is read back on d3d11, which executes it.

import { computeModule, programSource } from "../shader/descriptor";
import { glslComputeIr } from "../shader/emit";
import { ShaderTarget } from "../shader/layout";
import { AtomicI32, Vec3u, access, atomicStore, binding, builtin } from "../shader/std";
import { GPUShaderModuleDescriptor } from "../webgpu/types.ms";
import { PassState, computeCallRefusal, openPassRefusal, renderCallRefusal } from "../gpu/doorGpu.ms";

when (voidDummy || (windows && !voidVulkan)) {
	import {
		DOOR_BUFFER_STORAGE,
		doorMakeBuffer,
		doorPassState,
		doorReadBuffer,
		doorSetup,
		doorShutdown,
		doorUpdateBufferRangeOf,
	} from "../gpu/doorGpu.ms";
	import {
		applyComputeBindings,
		applyComputePipeline,
		beginComputePass,
		computeDispatch,
		computePipelineFor,
		computeSlotMask,
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

function doubleDescriptor(index: int32): GPUShaderModuleDescriptor {
	const module = computeModule(glslComputeIr(doubleKernel, [8, 1, 1]), []);
	if (!module.ok) { console.log(`doubleKernel: ${module.error}`); unreachable; }
	const source = programSource(module.value, ShaderTarget.Hlsl5);
	if (!source.ok) { console.log(`doubleKernel: ${source.error}`); unreachable; }
	if (source.value.refusal != "") { console.log(`doubleKernel: ${source.value.refusal}`); unreachable; }
	let descriptor: GPUShaderModuleDescriptor = {
		label: "doubleKernel",
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

	test "a ranged buffer update writes only its bytes and refuses a range outside the buffer" {
		openDoor();
		const buffer = doorMakeBuffer(DOOR_BUFFER_STORAGE, [], 32);
		const two: Vec<int32> = [20, 30];
		const one: Vec<int32> = [70];
		assert doorUpdateBufferRangeOf(buffer, 4, two) == 1;
		assert doorUpdateBufferRangeOf(buffer, 24, one) == 1;
		assert doorUpdateBufferRangeOf(buffer, 28, two) == 0;
		assert doorUpdateBufferRangeOf(buffer, 2, one) == 0;
		assert doorUpdateBufferRangeOf(buffer, -4, one) == 0;
		let out: Vec<uint8> = new Array(32);
		assert doorReadBuffer(buffer, out) == 1;
		const expected: Vec<int32> = [0, 20, 30, 0, 0, 0, 70, 0];
		for (let i = 0; i < 8; i++) { assert wordAt(out, i) == expected[i]; }
		doorShutdown();
	}

	test "the compute pipeline of a program is made once and answers the same id" {
		openDoor();
		const base = registerComputePrograms(doubleDescriptor, 1);
		assert computePipelineFor(base) == computePipelineFor(base);
		assert computePipelineFor(base) != 0;
		doorShutdown();
	}
}
