// Prints the shdc stages of the pixel-art preset's MetaScript shaders under the stage names
// src/void3d/programKeys.txt gives them; scripts/regen-shaders.sh writes them to
// src/void3d/pixelArt3dGen.glsl.

import { glsl, glslLinked } from "../src/shader/emit";
import { particleVisualPixelArtVs } from "../src/void3d/shader3d";
import { fullscreenVs } from "../src/void3d/post3d";
import {
	blitFs,
	pixelArtBillboardFs,
	pixelArtBillboardVs,
	pixelArtLitFs,
	pixelArtLitTexturedFs,
	pixelArtLitTexturedVs,
	pixelArtLitVs,
	pixelArtParticleFs,
	pixelArtParticleVs,
	pixelArtUnlitTexturedFs,
	pixelArtUnlitTexturedVs,
	postFs,
} from "../src/void3d/pixelArt3d";

function stage(kind: string, name: string, source: string): string {
	return "@" + kind + " " + name + "\n" + source + "@end\n";
}

console.log(stage("vs", "fullscreenVs", glsl(fullscreenVs)));
console.log(stage("fs", "postFs", glsl(postFs)));
console.log(stage("fs", "blitFs", glsl(blitFs)));
console.log(stage("vs", "particleVisualPixelArtVs", glsl(particleVisualPixelArtVs)));
console.log(stage("vs", "billboardVs", glsl(pixelArtBillboardVs)));
console.log(stage("fs", "billboardFs", glslLinked(pixelArtBillboardFs, pixelArtBillboardVs)));
console.log(stage("vs", "particleVs", glsl(pixelArtParticleVs)));
console.log(stage("fs", "particleFs", glslLinked(pixelArtParticleFs, pixelArtParticleVs)));
console.log(stage("vs", "litVs", glsl(pixelArtLitVs)));
console.log(stage("fs", "litFs", glslLinked(pixelArtLitFs, pixelArtLitVs)));
console.log(stage("vs", "litTexturedVs", glsl(pixelArtLitTexturedVs)));
console.log(stage("fs", "litTexturedFs", glslLinked(pixelArtLitTexturedFs, pixelArtLitTexturedVs)));
console.log(stage("vs", "unlitTexturedVs", glsl(pixelArtUnlitTexturedVs)));
const unlit = glslLinked(pixelArtUnlitTexturedFs, pixelArtUnlitTexturedVs);
console.log(stage("fs", "unlitTexturedFs", unlit));
