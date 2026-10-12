// Prints the shdc stages of void3d's MetaScript shaders; scripts/regen-shaders.sh writes them to
// src/void3d/shader3dGen.glsl.

import { glsl } from "../src/shader/emit";
import { copyFs } from "../src/void3d/shader3d";

function stage(kind: string, name: string, source: string): string {
	return "@" + kind + " " + name + "\n" + source + "@end\n";
}

console.log(stage("fs", "copyFs", glsl(copyFs)));
