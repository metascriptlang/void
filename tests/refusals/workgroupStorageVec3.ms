// expect: 11:25 compute entry reads workgroup variables 'points' of 17600 bytes, past 16384
import { glslCompute } from "../../src/shader/emit";
import { Vec3f, Vec3u, binding, builtin, vec3f } from "../../src/shader/std";
struct Id {
	@builtin(globalInvocationId) id: Vec3u;
}
let points: Vec3f[1100];
function fill(input: Id): void {
	points[0] = vec3f(1.0, 2.0, 3.0);
}
console.log(glslCompute(fill, [64, 1, 1]));
