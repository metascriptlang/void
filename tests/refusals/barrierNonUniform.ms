// expect: 14:25 workgroupBarrier runs in non-uniform control flow
import { glslCompute } from "../../src/shader/emit";
import { Vec3u, builtin, workgroupBarrier } from "../../src/shader/std";
struct Ids {
	@builtin(localInvocationId) local: Vec3u;
}
let tile: float32[64];
function sync(input: Ids): void {
	if (input.local.x == 0) {
		tile[0] = 1.0;
		workgroupBarrier();
	}
}
console.log(glslCompute(sync, [64, 1, 1]));
