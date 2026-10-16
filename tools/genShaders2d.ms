// Prints the shdc stages of void2d's MetaScript shaders; scripts/regen-shaders.sh writes them to
// src/void2d/shader2dGen.glsl, which src/void2d/shader2d.glsl includes.

import { glsl, glslLinked } from "../src/shader/emit";
import {
	blurFs,
	blurVs,
	fs,
	spriteFs,
	spriteVs,
	uiFs,
	uiVs,
	vs,
} from "../src/void2d/shader2d";

function stage(kind: string, name: string, source: string): string {
	return "@" + kind + " " + name + "\n" + source + "@end\n";
}

console.log(stage("vs", "vs", glsl(vs)));
console.log(stage("fs", "fs", glslLinked(fs, vs)));
console.log(stage("vs", "spriteVs", glsl(spriteVs)));
console.log(stage("fs", "spriteFs", glslLinked(spriteFs, spriteVs)));
console.log(stage("vs", "uiVs", glsl(uiVs)));
console.log(stage("fs", "uiFs", glslLinked(uiFs, uiVs)));
console.log(stage("vs", "blurVs", glsl(blurVs)));
console.log(stage("fs", "blurFs", glslLinked(blurFs, blurVs)));
