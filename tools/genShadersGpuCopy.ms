// Prints the shdc stages of tests/integration/gpuCopy.glsl's program; scripts/regen-shaders.sh
// writes them to tests/integration/gpuCopyGen.glsl.

import { glsl } from "../src/shader/emit";
import { fullscreenVs } from "../src/void3d/post3d";
import { gpuCopyFs } from "../tests/integration/gpuCopyShader";

function stage(kind: string, name: string, source: string): string {
	return "@" + kind + " " + name + "\n" + source + "@end\n";
}

console.log(stage("vs", "gpuCopyVs", glsl(fullscreenVs)));
console.log(stage("fs", "gpuCopyFs", glsl(gpuCopyFs)));
