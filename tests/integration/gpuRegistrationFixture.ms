import "../../src/gpu/door";
import {
	DOOR_BUFFER_VERTEX,
	DoorLayout,
	doorApplyBindings,
	doorApplyPipeline,
	doorDraw,
	doorLayout,
	doorMakeBufferOf,
	doorRegisterLayouts,
	doorRegisterPrograms,
} from "../../src/gpu/doorGpu.ms";
import {
	DOOR_BINDING_SAMPLER,
	DOOR_BINDING_VERTEX_BUFFER,
	DOOR_BINDING_VIEW,
} from "../../src/gpu/doorWords.h";
import { GPUShaderModuleDescriptor } from "../../src/webgpu/types.ms";
import { gpuCopyShaderModule } from "./gpuCopyModules.ms";
import { env } from "std/process";

const TRIANGLE: float32[6] = [-1.0, -1.0, 3.0, -1.0, -1.0, 3.0];

let program: int32 = -1;
let layout: int32 = -1;
let vertices: uint32 = 0;

function copyModule(index: int32): GPUShaderModuleDescriptor {
	return gpuCopyShaderModule();
}

export function foreignProgram(): int32 {
	if (program >= 0) { return program; }
	const position: DoorLayout = doorLayout([{ location: 0, format: "float32x2", buffer: 0 }], ["vertex"]);
	layout = doorRegisterLayouts([position, position, position, position]) + 3;
	program = doorRegisterPrograms(copyModule, [layout, layout, layout, layout, layout, layout]) + 5;
	return program;
}

export let registrationPreload: int32 = env.get("VOID_GPU_REGISTRATION") == "2" ? foreignProgram() : -1;

export function foreignLayout(): int32 {
	foreignProgram();
	return layout;
}

export function drawForeign(pipeline: uint32, texture: uint32, sampler: uint32): void {
	if (vertices == 0) { vertices = doorMakeBufferOf(DOOR_BUFFER_VERTEX, TRIANGLE); }
	doorApplyPipeline(pipeline);
	let bindings: uint32[17] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];
	bindings[DOOR_BINDING_VERTEX_BUFFER] = vertices;
	bindings[DOOR_BINDING_VIEW] = texture;
	bindings[DOOR_BINDING_SAMPLER] = sampler;
	doorApplyBindings(bindings, []);
	doorDraw(0, 3, 1);
}
