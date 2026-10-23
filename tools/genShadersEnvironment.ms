// Prints the stages of void3d's environment bake (src/void3d/environmentShader.ms);
// scripts/regen-shaders.sh writes them to src/void3d/environmentGen.glsl, which
// src/void3d/environment.glsl includes.

import { glsl } from "../src/shader/emit";
import { fullscreenVs } from "../src/void3d/post3d";
import {
	environmentIrradianceFs,
	environmentPanoramaFs,
	environmentRadianceFs,
	environmentResampleFs,
} from "../src/void3d/environmentShader";

function stage(kind: string, name: string, source: string): string {
	return "@" + kind + " " + name + "\n" + source + "@end\n";
}

console.log(stage("vs", "fullscreenVs", glsl(fullscreenVs)));
console.log(stage("fs", "environmentPanoramaFs", glsl(environmentPanoramaFs)));
console.log(stage("fs", "environmentResampleFs", glsl(environmentResampleFs)));
console.log(stage("fs", "environmentRadianceFs", glsl(environmentRadianceFs)));
console.log(stage("fs", "environmentIrradianceFs", glsl(environmentIrradianceFs)));
