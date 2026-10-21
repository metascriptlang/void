// Prints the shdc stages of void3d's MetaScript shaders; scripts/regen-shaders.sh writes them to
// src/void3d/shader3dGen.glsl.

import { glsl, glslLinked } from "../src/shader/emit";
import {
	billboardFs,
	billboardVs,
	copyFs,
	litFs,
	litTexturedFs,
	litTexturedVs,
	litVs,
	particleFs,
	particleVs,
	particleVisualVs,
	shadowLitFs,
	shadowLitTexturedFs,
	shadowUnlitTexturedFs,
	unlitTexturedFs,
	unlitTexturedVs,
} from "../src/void3d/shader3d";
import {
	bloomDownsampleFirstFs,
	bloomDownsampleFs,
	bloomUpsampleFs,
	fullscreenVs,
	outlineMaskFs,
	outlineMixFs,
	outlineWidthFs,
	toneMapFs,
} from "../src/void3d/post3d";

function stage(kind: string, name: string, source: string): string {
	return "@" + kind + " " + name + "\n" + source + "@end\n";
}

console.log(stage("vs", "fullscreenVs", glsl(fullscreenVs)));
console.log(stage("fs", "copyFs", glsl(copyFs)));
console.log(stage("fs", "toneMapFs", glsl(toneMapFs)));
console.log(stage("fs", "bloomDownsampleFirstFs", glsl(bloomDownsampleFirstFs)));
console.log(stage("fs", "bloomDownsampleFs", glsl(bloomDownsampleFs)));
console.log(stage("fs", "bloomUpsampleFs", glsl(bloomUpsampleFs)));
console.log(stage("fs", "outlineMaskFs", glsl(outlineMaskFs)));
console.log(stage("fs", "outlineMixFs", glsl(outlineMixFs)));
console.log(stage("fs", "outlineWidthFs", glsl(outlineWidthFs)));
console.log(stage("vs", "particleVisualVs", glsl(particleVisualVs)));
console.log(stage("vs", "particleVs", glsl(particleVs)));
console.log(stage("fs", "particleFs", glslLinked(particleFs, particleVs)));
console.log(stage("vs", "billboardVs", glsl(billboardVs)));
console.log(stage("fs", "billboardFs", glslLinked(billboardFs, billboardVs)));
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
