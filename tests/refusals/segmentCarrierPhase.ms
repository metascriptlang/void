// expect: 13:1 segment 'doubled' reads its phase struct UvStage as its carrier
import { glslSegmentIr } from "../../src/shader/emit";
import { Vec2f } from "../../src/shader/std";
struct UvStage {
	uv: Vec2f;
}
struct Cell {
	size: Vec2f;
}
struct CellBindings {
	cellParams: Cell;
}
function doubled(stage: UvStage, b: CellBindings, carried: UvStage): UvStage {
	return { uv: stage.uv * b.cellParams.size + carried.uv };
}
console.log(glslSegmentIr(doubled));
