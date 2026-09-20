// Port of h3d.pass.ScreenFx (and the Copy / Outline passes built on it): a fixed program drawn
// once over the whole target. Heaps draws a Plane2D with its own Pass; here a screen effect is
// an ordinary Material on the Fullscreen layout, drawn as one DrawItem over one triangle, so
// it goes through the same pipeline cache as the scene.

import { identity } from "../math/math3d";
import { VertexLayout, makeVertexBuffer } from "./gpu3d";
import { RenderState, Face, Compare } from "./pass";
import { GpuMesh, DrawItem } from "./draw";

// One triangle covering clip space; the rasterizer clips it to the target.
const FULLSCREEN_TRIANGLE: Vec<float32> = [
	-1.0, -1.0, 3.0, -1.0, -1.0, 3.0,
];

// ScreenFx's pass: no culling, no depth test or write.
export function screenState(): RenderState {
	return RenderState.defaults()
		.withCulling(Face.None)
		.withDepth(false, Compare.Always);
}

// The mesh every screen effect draws; `vertexBuffer` from makeScreenTriangle.
export function screenMesh(vertexBuffer: uint32): GpuMesh {
	return GpuMesh.external(VertexLayout.Fullscreen, vertexBuffer, 0, 3, 1);
}

export function makeScreenTriangle(): uint32 {
	return makeVertexBuffer(FULLSCREEN_TRIANGLE);
}

export function screenItem(mesh: int32, material: int32): DrawItem {
	return { mesh: mesh, material: material, world: identity() };
}
