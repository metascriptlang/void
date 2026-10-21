import { GPUShaderModuleDescriptor, GPUVertexBufferLayout } from "../webgpu/types.ms";
import {
	gpu3dShaderModule,
	litShaderModule,
	skinLitShaderModule,
	unlitTexturedShaderModule,
} from "../void3d/programModules.ms";
import { GPU3D_PROGRAM_TABLE_LENGTH, PROGRAM_LAYOUTS } from "../void3d/programTableData.ms";
import { gpu3dVertexLayout } from "../void3d/vertexLayouts.ms";
import {
	LIGHT_UNIFORM_LENGTH,
	LIGHT_UNIFORM_SLOT,
	MATERIAL_UNIFORM_SLOT,
	SKIN_UNIFORM_LENGTH,
	SKIN_UNIFORM_SLOT,
} from "../void3d/gpu3d";
import { MODEL_LENGTH, MODEL_SLOT } from "../void3d/draw";

function uniformBytes(module: GPUShaderModuleDescriptor, slot: int32): int32 {
	for (let b = 0; b < 24; b++) {
		const binding = module.bindings[b];
		if (binding.kind == "uniform" && binding.binding == slot) { return binding.size; }
	}
	return -1;
}

function feeds(buffers: GPUVertexBufferLayout[2], location: int32): boolean {
	for (let i = 0; i < 2; i++) {
		for (let a = 0; a < 16; a++) {
			const attribute = buffers[i].attributes[a];
			if ((attribute.format as string) != "" && attribute.shaderLocation == location) { return true; }
		}
	}
	return false;
}

test "every void3d program reads only vertex attributes its layout feeds" {
	for (let i = 0; i < GPU3D_PROGRAM_TABLE_LENGTH; i++) {
		const module = gpu3dShaderModule(i);
		const buffers = gpu3dVertexLayout(PROGRAM_LAYOUTS[i]);
		for (let a = 0; a < 16; a++) {
			assert feeds(buffers, module.attributes[a].location);
		}
	}
}

test "uniform blocks hold what their writers fill" {
	assert uniformBytes(litShaderModule(), LIGHT_UNIFORM_SLOT) == LIGHT_UNIFORM_LENGTH * 4;
	assert uniformBytes(litShaderModule(), MODEL_SLOT) == MODEL_LENGTH * 4;
	assert uniformBytes(skinLitShaderModule(), SKIN_UNIFORM_SLOT) == SKIN_UNIFORM_LENGTH * 4;
	assert uniformBytes(unlitTexturedShaderModule(), MODEL_SLOT) == 16 * 4;
	assert uniformBytes(unlitTexturedShaderModule(), MATERIAL_UNIFORM_SLOT) == 8 * 4;
}
