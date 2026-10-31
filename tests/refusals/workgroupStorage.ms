// expect: 11:25 compute entry reads workgroup variables 'tile' of 20000 bytes, past 16384
import { glslCompute } from "../../src/shader/emit";
import { Vec3u, binding, builtin } from "../../src/shader/std";
struct Id {
	@builtin(globalInvocationId) id: Vec3u;
}
let tile: float32[5000];
function fill(input: Id): void {
	tile[0] = 1.0;
}
console.log(glslCompute(fill, [64, 1, 1]));
