// expect: 16:1 segment 'relay' returns Frames, and a segment returns its phase struct VertexUv or, reading no carrier, the carrier struct it writes
import { glslSegmentIr } from "../../src/shader/emit";
import { Vec2f } from "../../src/shader/std";
struct VertexUv {
	uv: Vec2f;
}
struct Frames {
	at: Vec2f;
}
struct Cell {
	size: Vec2f;
}
struct CellBindings {
	cellParams: Cell;
}
function relay(vertex: VertexUv, b: CellBindings, carried: Frames): Frames {
	return { at: vertex.uv * b.cellParams.size + carried.at };
}
console.log(glslSegmentIr(relay));
