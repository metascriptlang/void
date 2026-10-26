// expect: 11:14 storage buffer 'cells' cannot be @access(write): WGSL's storage buffers are read or read_write, and write is a storage texture's mode
import { glslCompute } from "../../src/shader/emit";
import { Vec3u, access, binding, builtin } from "../../src/shader/std";
struct Id {
	@builtin(globalInvocationId) id: Vec3u;
}
struct Cell {
	hits: uint32;
}
struct Cells {
	@binding(0) @access(write) cells: Cell[];
}
function bump(input: Id, b: Cells): void {
	b.cells[input.id.x].hits = 1;
}
console.log(glslCompute(bump, [32, 1, 1]));
