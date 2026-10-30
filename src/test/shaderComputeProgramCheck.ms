// shaderBuild's compute product lowers a kernel, prints it for the build's target and reflects it,
// as shaderModule does a program: the descriptor carries the text, or the bytecode when a host
// tool compiled it. shaderCompute hands the same descriptor to the door.

import { computeModule, programSource } from "../shader/descriptor";
import { glslComputeIr } from "../shader/emit";
import { ShaderTarget } from "../shader/layout";
import { shaderBuild, stageBlob } from "../shader/program";
import { AtomicU32, Vec3u, access, atomicAdd, binding, builtin } from "../shader/std";

struct CountInput {
	@builtin(globalInvocationId) id: Vec3u;
}

struct CountCell {
	hits: AtomicU32;
}

struct CountBindings {
	@binding(0) @access(read_write) cells: CountCell[];
}

function countCs(input: CountInput, b: CountBindings): void {
	atomicAdd(b.cells[input.id.x].hits, 2);
}

const countedModule = shaderBuild("counted", glslComputeIr(countCs, [64, 1, 1]), "", "",
	"shaderComputeModule");
const volumeModule = shaderBuild("volume", glslComputeIr(countCs, [8, 4, 2]), "", "",
	"shaderComputeModule");

test "a compute descriptor carries the kernel as text or bytecode, with its entry and no render stage" {
	assert (countedModule.computeCode != "") != (countedModule.computeBytecode.length > 0);
	assert countedModule.computeEntryPoint != "";
	assert countedModule.vertexCode == "" && countedModule.fragmentCode == "";
	assert countedModule.vertexBytecode.length == 0 && countedModule.fragmentBytecode.length == 0;
}

test "a compute descriptor reflects the workgroup size the author wrote" {
	assert countedModule.workgroupSize[0] == 64 && countedModule.workgroupSize[1] == 1;
	assert countedModule.workgroupSize[2] == 1;
	assert volumeModule.workgroupSize[0] == 8 && volumeModule.workgroupSize[1] == 4;
	assert volumeModule.workgroupSize[2] == 2;
}

test "a compute descriptor reflects the storage buffer the kernel binds" {
	assert countedModule.bindings[0].kind == "storage-buffer";
	assert countedModule.bindings[0].binding == 0;
	assert countedModule.bindings[0].bufferType == "storage";
	assert (countedModule.bindings[1].kind as string) == "";
}

when (windows) {
	test "on the HLSL target the descriptor holds cs_5_0 bytecode exactly when fxc compiled it" {
		const module = computeModule(glslComputeIr(countCs, [64, 1, 1]), []);
		assert module.ok;
		const source = programSource(module.value, ShaderTarget.Hlsl5);
		assert source.ok;
		const s = source.value;
		const blob = stageBlob("hlsl5", "compute", s.computeCode, s.entryPoint, "");
		assert (countedModule.computeBytecode.length > 0) == (blob.path != "");
		assert (countedModule.computeCode == "") == (blob.path != "");
		assert s.computeCode.includes("[numthreads(64, 1, 1)]");
	}
}
