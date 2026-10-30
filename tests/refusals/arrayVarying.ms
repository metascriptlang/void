// expect: 12:1 varying 'weights' is an array, which WGSL does not pass between stages: declare one varying each
import { glsl } from "../../src/shader/emit";
import { Vec4f, builtin, vec4f } from "../../src/shader/std";
struct Corner {
	@builtin(vertexIndex) index: uint32;
}
struct Spread {
	weights: Vec4f[2];
	@builtin(position) clip: Vec4f;
}

function spreadVs(input: Corner): Spread {
	return { weights: [vec4f(1.0), vec4f(2.0)], clip: vec4f(0.0, 0.0, 0.0, 1.0) };
}
console.log(glsl(spreadVs));
