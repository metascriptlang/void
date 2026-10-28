import { Graphics3D, GraphicsError, moveTo, lineTo, lineStyle } from "../void3d/graphics3d";
import { clearGraphics, setGraphicsColorF } from "../void3d/graphics3d";
import { flushGraphics, setIs3D } from "../void3d/graphics3d";
import { vertexCount, indexCount } from "../void3d/meshData";

function near(a: float32, b: float32): boolean { return Math.abs(a - b) < 0.00001; }

test "Graphics3D default starts at origin with explicitly initialized black style" {
	const g = Graphics3D.create();
	assert g.width == 1.5 && g.current.x == 0 && g.current.y == 0 && g.current.z == 0;
	assert g.color.red == 0 && g.color.green == 0 && g.color.blue == 0 && g.color.alpha == 1;
	assert g.data.hasUvs && g.data.vertexCount() == 0 && g.data.indexCount() == 0;
}

test "Graphics3D emits four coincident roots with endpoint delta in normal channels" {
	let g = Graphics3D.create();
	assert moveTo(g, 1, 2, 3).ok;
	assert lineStyle(g, 2, 0x804020, 0.25).ok;
	assert lineTo(g, 4, 6, 8).ok;
	assert g.data.vertexCount() == 4 && g.data.indexCount() == 6;
	for (let v = 0; v < 4; v++) {
		const at: int32 = v * 12;
		assert g.data.vertices[at] == 1 && g.data.vertices[at + 1] == 2;
		assert g.data.vertices[at + 2] == 3;
		assert g.data.vertices[at + 3] == 3 && g.data.vertices[at + 4] == 4;
		assert g.data.vertices[at + 5] == 5;
		assert near(g.data.vertices[at + 8], 128.0 / 255.0);
		assert g.data.vertices[at + 11] == 0.25;
	}
	assert g.data.vertices[6] == 0 && g.data.vertices[7] == 0;
	assert g.data.vertices[18] == 0 && g.data.vertices[19] == 1;
	assert g.data.vertices[30] == 1 && g.data.vertices[31] == 0;
	assert g.data.vertices[42] == 1 && g.data.vertices[43] == 1;
	assert g.data.indices[0] == 0 && g.data.indices[1] == 1 && g.data.indices[2] == 2;
	assert g.data.indices[3] == 2 && g.data.indices[4] == 3 && g.data.indices[5] == 1;
	assert g.data.bounds.min.x == 1 && g.data.bounds.max.x == 4;
	assert g.data.bounds.min.y == 2 && g.data.bounds.max.y == 6;
	assert g.data.bounds.min.z == 3 && g.data.bounds.max.z == 8;
	assert g.current.x == 4 && g.current.y == 6 && g.current.z == 8;
}

test "Graphics3D chains from last endpoint and moveTo breaks without emitting geometry" {
	let g = Graphics3D.create();
	assert lineTo(g, 1, 2, 3).ok;
	assert lineTo(g, 4, 6, 8).ok;
	assert g.data.vertices[48] == 1 && g.data.vertices[51] == 3;
	assert moveTo(g, 10, 20, 30).ok;
	assert g.data.vertexCount() == 8;
	assert lineTo(g, 11, 21, 31).ok;
	assert g.data.vertices[96] == 10 && g.data.vertices[97] == 20;
	assert g.data.vertices[99] == 1 && g.data.vertices[100] == 1;
	assert g.data.indices[12] == 8 && g.data.indices[17] == 9;
}

test "Graphics3D positive width is global while color is captured per segment" {
	let g = Graphics3D.create();
	assert lineStyle(g, 2, 0xff0000, 0.25).ok;
	assert lineTo(g, 1, 0, 0).ok;
	assert lineStyle(g, 7, 0x00ff00, 0.75).ok;
	assert lineTo(g, 2, 0, 0).ok;
	assert g.width == 7;
	assert g.data.vertices[8] == 1 && g.data.vertices[9] == 0 && g.data.vertices[11] == 0.25;
	assert g.data.vertices[56] == 0 && g.data.vertices[57] == 1 && g.data.vertices[59] == 0.75;
	assert lineStyle(g, 0, 0x0000ff).ok;
	assert g.width == 7 && g.color.blue == 1;
	assert lineStyle(g, -2, 0xffffff).ok;
	assert g.width == 7 && g.color.red == 1;
}

test "Graphics3D clear keeps cursor and style and floating color is unclamped" {
	let g = Graphics3D.create();
	assert moveTo(g, 1, 2, 3).ok;
	assert lineTo(g, 4, 6, 8).ok;
	assert setGraphicsColorF(g, -0.25, 2, 3.5, 0.5).ok;
	clearGraphics(g);
	assert g.data.vertexCount() == 0;
	assert lineTo(g, 5, 7, 9).ok;
	assert g.data.vertices[0] == 4 && g.data.vertices[1] == 6 && g.data.vertices[2] == 8;
	assert g.data.vertices[8] == -0.25 && g.data.vertices[9] == 2;
	assert g.data.vertices[10] == 3.5 && g.data.vertices[11] == 0.5;
}

test "Graphics3D zero length is a finite encoding, not GPU acceptance" {
	let g = Graphics3D.create();
	assert lineTo(g, 0, 0, 0).ok;
	assert g.data.vertexCount() == 4 && g.data.indexCount() == 6;
	assert g.data.vertices[3] == 0 && g.data.vertices[4] == 0 && g.data.vertices[5] == 0;
}

test "Graphics3D refuses nonfinite coordinates and unrepresentable delta atomically" {
	let g = Graphics3D.create();
	assert moveTo(g, 3.0e38, 0, 0).ok;
	const overflow = lineTo(g, -3.0e38, 0, 0);
	assert !overflow.ok && overflow.error == GraphicsError.DeltaRange;
	assert g.data.vertexCount() == 0 && g.current.x == 3.0e38;
	assert !moveTo(g, (1.0 / 0.0) as float32, 0, 0).ok;
	assert !lineStyle(g, (1.0 / 0.0) as float32).ok;
	assert g.width == 1.5;
	assert !setGraphicsColorF(g, 0, 0, 0, (1.0 / 0.0) as float32).ok;
	assert g.color.alpha == 1;
}

test "Graphics3D refuses a forged non-quad data shape without appending" {
	let g = Graphics3D.create();
	g.data.hasUvs = false;
	const layout = lineTo(g, 1, 0, 0);
	assert !layout.ok && layout.error == GraphicsError.Shape;
	assert g.data.vertices.length == 0 && g.current.x == 0;
	g.data.hasUvs = true;
	g.data.vertices = new Array(48);
	const unindexed = lineTo(g, 1, 0, 0);
	assert !unindexed.ok && unindexed.error == GraphicsError.Shape;
	assert g.data.vertices.length == 48 && g.data.indexCount() == 0;
}

test "Graphics3D reuses MeshData wide index promotion without a second stream ABI" {
	let g = Graphics3D.create();
	for (let i = 0; i < 16385; i++) {
		assert lineTo(g, i as float32, 0, 0).ok;
	}
	assert g.data.vertexCount() == 65540 && g.data.indexCount() == 98310;
	assert g.data.wideIndices !== null && g.data.indices.length == 0;
	assert g.data.wideIndices[98304] == 65536 && g.data.wideIndices[98309] == 65537;
}

function vertexAt(
	g: Graphics3D, v: int32, x: float32, y: float32, u: float32, side: float32,
): boolean {
	const at: int32 = v * 12;
	return near(g.data.vertices[at], x) && near(g.data.vertices[at + 1], y) &&
		g.data.vertices[at + 3] == 0 && g.data.vertices[at + 4] == 0 &&
		g.data.vertices[at + 5] == 1 &&
		g.data.vertices[at + 6] == u && g.data.vertices[at + 7] == side;
}

function indicesAre(g: Graphics3D, expected: int32[]): boolean {
	if (g.data.indexCount() != (expected.length as int32)) { return false; }
	for (let i = 0; i < expected.length; i++) {
		if (g.data.indices[i] != (expected[i] as uint32)) { return false; }
	}
	return true;
}

test "Graphics3D in 3D waits for a flush, then mitres an open polyline in the XY plane" {
	let g = Graphics3D.create();
	assert g.lineSize == 0 && !g.is3D && g.points.length == 0;
	setIs3D(g, true);
	assert lineStyle(g, 1, 0xff0000).ok;
	assert moveTo(g, 0, 0, 3).ok;
	assert lineTo(g, 2, 0, 3).ok;
	assert lineTo(g, 2, 2, 3).ok;
	assert g.data.vertexCount() == 0 && g.points.length == 3;
	assert flushGraphics(g).ok;
	assert g.points.length == 0 && g.data.vertexCount() == 6;
	assert vertexAt(g, 0, 0, 0.5, 0, 0);
	assert vertexAt(g, 1, 0, -0.5, 1, 0);
	assert vertexAt(g, 2, 1.5, 0.5, 0, 1);
	assert vertexAt(g, 3, 2.5, -0.5, 1, 1);
	assert vertexAt(g, 4, 1.5, 2, 0, 0);
	assert vertexAt(g, 5, 2.5, 2, 1, 0);
	assert g.data.vertices[2] == 3 && g.data.vertices[8] == 1 && g.data.vertices[9] == 0;
	assert indicesAre(g, [0, 1, 2, 2, 1, 3, 2, 3, 4, 4, 3, 5]);
	assert g.width == 1.5;
}

test "Graphics3D in 3D closes a loop whose last point is its first and wraps to the start" {
	let g = Graphics3D.create();
	setIs3D(g, true);
	assert lineStyle(g, 2).ok;
	assert moveTo(g, 0, 0, 0).ok;
	assert lineTo(g, 2, 0, 0).ok;
	assert lineTo(g, 2, 2, 0).ok;
	assert lineTo(g, 0, 2, 0).ok;
	assert lineTo(g, 0, 0, 0).ok;
	assert flushGraphics(g).ok;
	assert g.data.vertexCount() == 8;
	assert vertexAt(g, 0, 1, 1, 0, 0);
	assert vertexAt(g, 1, -1, -1, 1, 0);
	assert vertexAt(g, 6, 1, 1, 0, 1);
	assert indicesAre(g, [
		0, 1, 2, 2, 1, 3, 2, 3, 4, 4, 3, 5, 4, 5, 6, 6, 5, 7, 6, 7, 0, 0, 7, 1,
	]);
}

test "Graphics3D in 3D flushes on moveTo, lineStyle and a switch out, and clear drops points" {
	let g = Graphics3D.create();
	setIs3D(g, true);
	assert lineStyle(g, 1).ok;
	assert moveTo(g, 0, 0, 0).ok;
	assert lineTo(g, 1, 0, 0).ok;
	assert moveTo(g, 5, 5, 0).ok;
	assert g.data.vertexCount() == 4 && g.points.length == 1;
	assert lineTo(g, 6, 5, 0).ok;
	assert lineStyle(g, 1, 0x00ff00).ok;
	assert g.data.vertexCount() == 8 && g.points.length == 0;
	assert lineTo(g, 7, 5, 0).ok;
	clearGraphics(g);
	assert g.data.vertexCount() == 0 && g.points.length == 0;
	assert lineTo(g, 7, 5, 0).ok;
	setIs3D(g, true);
	assert g.points.length == 1;
	setIs3D(g, false);
	assert g.points.length == 0 && g.data.vertexCount() == 0 && !g.is3D;
}

test "Graphics3D in 3D refuses a joint with no miter direction and drops its points" {
	let g = Graphics3D.create();
	setIs3D(g, true);
	assert lineStyle(g, 1).ok;
	assert moveTo(g, 1, 1, 0).ok;
	const lone = moveTo(g, 2, 2, 0);
	assert !lone.ok && lone.error == GraphicsError.Degenerate;
	assert g.points.length == 0 && g.data.vertexCount() == 0;
	assert moveTo(g, 0, 0, 0).ok;
	assert lineTo(g, 1, 0, 0).ok;
	assert lineTo(g, 0, 0, 0).ok;
	const back = flushGraphics(g);
	assert !back.ok && back.error == GraphicsError.Degenerate;
	assert g.points.length == 0 && g.data.vertexCount() == 0;
}

test "Graphics3D keeps Heaps' lineSize beside the screen width, and its bounds from the cursor" {
	let g = Graphics3D.create();
	assert lineStyle(g, 4).ok;
	assert g.width == 4 && g.lineSize == 4;
	setIs3D(g, true);
	assert lineStyle(g, 2).ok;
	assert g.width == 4 && g.lineSize == 2;
	setIs3D(g, false);
	assert lineStyle(g, 2).ok;
	assert g.width == 4;
	setIs3D(g, true);
	assert moveTo(g, 5, 5, 5).ok;
	assert lineTo(g, 6, 6, 6).ok;
	assert g.data.bounds.min.x == 0 && g.data.bounds.max.x == 6;
}
