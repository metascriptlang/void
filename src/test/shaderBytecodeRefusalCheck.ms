// Run apart from the index: the refusal stops the process, so it is observed from a child
// `msc run`, whose compile costs a minute or two.

import { exec } from "std/process";

when (windows && !voidVulkan) {
	test "a module whose embedded DXBC is corrupted stops by stage and label when the device rejects it" {
		const run = exec("msc run src/test/shaderBytecodeDeviceProbe.ms 2>&1");
		assert !run.ok;
		if (!run.ok) {
			assert run.error.output.includes("probe: the control module loaded");
			assert run.error.output.includes("CreateVertexShader failed for 'garbage': the device rejected GPUShaderModuleDescriptor.vertexBytecode");
			assert !run.error.output.includes("probe: the corrupted module loaded");
		}
	}
}
