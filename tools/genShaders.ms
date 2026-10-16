// Prints the shdc stages of void3d's MetaScript shaders; scripts/regen-shaders.sh writes them to
// src/void3d/shader3dGen.glsl.

import { glsl, glslLinked } from "../src/shader/emit";
import {
	copyFs,
	litFs,
	litTexturedFs,
	litTexturedVs,
	litVs,
	particleVisualVs,
	particleVisualPixelArtVs,
	shadowLitFs,
	shadowLitTexturedFs,
	shadowUnlitTexturedFs,
	unlitTexturedFs,
	unlitTexturedVs,
} from "../src/void3d/shader3d";

function stage(kind: string, name: string, source: string): string {
	return "@" + kind + " " + name + "\n" + source + "@end\n";
}

console.log(stage("fs", "copyFs", glsl(copyFs)));
console.log(stage("vs", "particleVisualVs", glsl(particleVisualVs)));
console.log(stage("vs", "particleVisualPixelArtVs", glsl(particleVisualPixelArtVs)));
console.log(stage("vs", "litVs", glsl(litVs)));
console.log(stage("fs", "litFs", glslLinked(litFs, litVs)));
console.log(stage("fs", "shadowLitFs", glslLinked(shadowLitFs, litVs)));
console.log(stage("vs", "litTexturedVs", glsl(litTexturedVs)));
console.log(stage("fs", "litTexturedFs", glslLinked(litTexturedFs, litTexturedVs)));
console.log(stage("fs", "shadowLitTexturedFs", glslLinked(shadowLitTexturedFs, litTexturedVs)));
console.log(stage("vs", "unlitTexturedVs", glsl(unlitTexturedVs)));
console.log(stage("fs", "unlitTexturedFs", glslLinked(unlitTexturedFs, unlitTexturedVs)));
const shadowUnlit = glslLinked(shadowUnlitTexturedFs, unlitTexturedVs);
console.log(stage("fs", "shadowUnlitTexturedFs", shadowUnlit));
