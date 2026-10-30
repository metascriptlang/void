// expect: 4:1 glsl: a compute entry returns nothing
import { shaderCompute } from "../../src/shader/program";
import { Vec4f, vec4f } from "../../src/shader/std";
function notAKernel(): Vec4f { return vec4f(1.0, 1.0, 1.0, 1.0); }
shaderCompute(fragmentKernel, notAKernel, [64, 1, 1]);
