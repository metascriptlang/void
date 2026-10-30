// expect: 15:26 workgroupUniformLoad is the initializer of a const or let of its own, because the barriers around it sit between two statements
import { glslCompute } from "../../src/shader/emit";
import { Vec3u, access, binding, builtin, workgroupUniformLoad } from "../../src/shader/std";
struct Id {
	@builtin(globalInvocationId) id: Vec3u;
}
struct Cell {
	hits: uint32;
}
struct Cells {
	@binding(0) @access(read_write) cells: Cell[];
}
let flag: uint32;
function bump(input: Id, b: Cells): void {
	if (workgroupUniformLoad(flag) > 2) {
		b.cells[input.id.x].hits = 1;
	}
}
console.log(glslCompute(bump, [32, 1, 1]));
