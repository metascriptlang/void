// expect: 14:3 storage buffer 'cells' is read-only: declare it @access(read_write) to write it, as WGSL's
import { glslCompute } from "../../src/shader/emit";
import { Vec3u, binding, builtin } from "../../src/shader/std";
struct Id {
	@builtin(globalInvocationId) id: Vec3u;
}
struct Cell {
	hits: uint32;
}
struct Cells {
	@binding(0) cells: Cell[];
}
function bump(input: Id, b: Cells): void {
	b.cells[input.id.x].hits = 1;
}
console.log(glslCompute(bump, [32, 1, 1]));
