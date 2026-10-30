// expect: 12:1 attribute 'weights' is an array, which neither WGSL nor GLSL ES 3.00 takes as a vertex input: declare one attribute each
import { glsl } from "../../src/shader/emit";
import { Vec4f, builtin, vec4f } from "../../src/shader/std";
struct Skinned {
	position: Vec4f;
	weights: Vec4f[2];
}
struct Placed {
	@builtin(position) clip: Vec4f;
}

function skinnedVs(input: Skinned): Placed {
	return { clip: input.position * input.weights[0].x + input.weights[1] };
}
console.log(glsl(skinnedVs));
