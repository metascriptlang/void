// expect: 7:1 glsl: a compute entry returns nothing
import { shaderCompute } from "../../src/shader/program";
import { Vec4f, builtin, vec4f } from "../../src/shader/std";
struct Out {
	@builtin(position) position: Vec4f;
}
function notAKernel(): Out { return { position: vec4f(0.0, 0.0, 0.0, 1.0) }; }
shaderCompute(vertexKernel, notAKernel, [64, 1, 1]);
