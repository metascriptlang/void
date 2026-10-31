// expect: 8:47 a float to integer conversion reads its operand three times to saturate it
import { glslCompute } from "../../src/shader/emit";
import { AtomicU32, Vec3u, access, atomicAdd, binding, builtin } from "../../src/shader/std";
struct Id { @builtin(globalInvocationId) id: Vec3u; }
struct Cell { hits: AtomicU32; }
struct Cells { @binding(0) @access(read_write) cells: Cell[]; }
function count(input: Id, b: Cells): void {
	const whole = (atomicAdd(b.cells[0].hits, 1) as float32) as int32;
}
console.log(glslCompute(count, [64, 1, 1]));
