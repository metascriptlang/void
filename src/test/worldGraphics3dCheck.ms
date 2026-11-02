import {
	WorldGraphics3D, WorldGraphicsError, worldMoveTo, worldLineTo, worldLineStyle,
	flushWorldGraphics, clearWorldGraphics,
} from "../void3d/worldGraphics3d";
import { vertexCount, indexCount } from "../void3d/meshData";

function near(a: float32, b: float32): boolean { return Math.abs(a - b) < 0.00001; }

test "world Graphics open line has world width XZ offsets and Y up normals" {
	let g = WorldGraphics3D.create();
	assert worldLineStyle(g, 2, 0xff0000, 0.5).ok;
	assert worldMoveTo(g, 0, 0, 0).ok;
	assert worldLineTo(g, 2, 0, 0).ok;
	assert flushWorldGraphics(g).ok;
	assert g.data.vertexCount() == 4 && g.data.indexCount() == 6 && g.points.length == 0;
	assert g.data.vertices[0] == 0 && g.data.vertices[2] == 1;
	assert g.data.vertices[14] == -1 && g.data.vertices[24] == 2;
	assert g.data.vertices[3] == 0 && g.data.vertices[4] == 1 && g.data.vertices[5] == 0;
	assert g.data.vertices[6] == 0 && g.data.vertices[7] == 0;
	assert g.data.vertices[18] == 1 && g.data.vertices[19] == 0;
	assert g.data.vertices[30] == 0 && g.data.vertices[31] == 1;
	assert g.data.vertices[8] == 1 && g.data.vertices[11] == 0.5;
	assert g.data.indices[0] == 0 && g.data.indices[1] == 1 && g.data.indices[2] == 2;
	assert g.data.indices[3] == 2 && g.data.indices[4] == 1 && g.data.indices[5] == 3;
}

test "world Graphics right angle miter is not a separate quad per segment" {
	let g = WorldGraphics3D.create();
	assert worldLineStyle(g, 2).ok;
	assert worldMoveTo(g, 0, 0, 0).ok;
	assert worldLineTo(g, 2, 0, 0).ok;
	assert worldLineTo(g, 2, 0, 2).ok;
	assert flushWorldGraphics(g).ok;
	assert g.data.vertexCount() == 6 && g.data.indexCount() == 12;
	assert near(g.data.vertices[24], 1) && near(g.data.vertices[26], 1);
	assert near(g.data.vertices[36], 3) && near(g.data.vertices[38], -1);
	assert g.data.vertices[31] == 1 && g.data.vertices[55] == 0;
}

test "world Graphics explicit closure drops duplicate endpoint and wraps connectivity" {
	let g = WorldGraphics3D.create();
	assert worldLineStyle(g, 1).ok;
	assert worldMoveTo(g, 0, 0, 0).ok;
	assert worldLineTo(g, 2, 0, 0).ok;
	assert worldLineTo(g, 2, 0, 2).ok;
	assert worldLineTo(g, 0, 0, 2).ok;
	assert worldLineTo(g, 0, 0, 0).ok;
	assert flushWorldGraphics(g).ok;
	assert g.data.vertexCount() == 8 && g.data.indexCount() == 24;
	assert g.data.indices[18] == 6 && g.data.indices[19] == 7 && g.data.indices[20] == 0;
	assert g.data.indices[21] == 0 && g.data.indices[22] == 7 && g.data.indices[23] == 1;
}

test "world Graphics style and move flush old stroke without recoloring it" {
	let g = WorldGraphics3D.create();
	assert worldLineStyle(g, 2, 0xff0000).ok;
	assert worldMoveTo(g, 0, 0, 0).ok;
	assert worldLineTo(g, 2, 0, 0).ok;
	assert worldLineStyle(g, 4, 0x00ff00, 0.5).ok;
	assert g.data.vertexCount() == 4;
	assert worldMoveTo(g, 3, 0, 0).ok;
	assert worldLineTo(g, 5, 0, 0).ok;
	assert flushWorldGraphics(g).ok;
	assert g.data.vertexCount() == 8 && g.data.indexCount() == 12;
	assert g.data.vertices[2] == 1 && g.data.vertices[50] == 2;
	assert g.data.vertices[8] == 1 && g.data.vertices[56] == 0;
	assert g.data.vertices[57] == 1 && g.data.vertices[59] == 0.5;
}

test "world Graphics invalid miter refuses geometry and retains path for explicit recovery" {
	let g = WorldGraphics3D.create();
	assert worldMoveTo(g, 0, 0, 0).ok;
	const single = flushWorldGraphics(g);
	assert !single.ok && single.error == WorldGraphicsError.Degenerate;
	assert g.data.vertexCount() == 0 && g.points.length == 1;
	assert worldLineTo(g, 0, 1, 0).ok;
	const vertical = flushWorldGraphics(g);
	assert !vertical.ok && vertical.error == WorldGraphicsError.Degenerate;
	assert g.data.vertexCount() == 0;
	clearWorldGraphics(g);
	assert worldMoveTo(g, 0, 0, 0).ok;
	assert worldLineTo(g, 1, 0, 0).ok;
	assert worldLineTo(g, 0, 0, 0).ok;
	const reversal = flushWorldGraphics(g);
	assert !reversal.ok && reversal.error == WorldGraphicsError.Degenerate;
	assert g.data.vertexCount() == 0;
}

test "world Graphics zero default width stays finite and nonfinite input is rejected" {
	let g = WorldGraphics3D.create();
	assert g.width == 0;
	assert worldMoveTo(g, 0, 0, 0).ok;
	assert worldLineTo(g, 1, 0, 0).ok;
	assert flushWorldGraphics(g).ok;
	assert g.data.vertices[2] == 0 && g.data.vertices[14] == 0;
	assert !worldLineTo(g, (1.0 / 0.0) as float32, 0, 0).ok;
	assert !worldLineStyle(g, (1.0 / 0.0) as float32).ok;
}
