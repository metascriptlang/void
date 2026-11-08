// Run apart from the index: the refusal stops the process, so it is observed from a child
// `msc run`, whose compile costs a minute or two.

import { exec } from "std/process";

when (windows && !voidVulkan) {
	test "a pipeline built from corrupted embedded DXBC stops by pipeline and module label when the device rejects it" {
		const run = exec("msc run src/test/shaderBytecodeDeviceProbe.ms 2>&1");
		assert !run.ok;
		if (!run.ok) {
			assert run.error.output.includes("probe: the control module loaded");
			assert run.error.output.includes("ID3D12Device::CreateGraphicsPipelineState returned HRESULT");
			assert run.error.output.includes("for pipeline 'garbage' built from module 'garbage'");
			assert !run.error.output.includes("probe: the corrupted pipeline was created");
		}
	}
}
