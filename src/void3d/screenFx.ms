// Port of h3d.pass.ScreenFx (and the Copy / Outline passes built on it): a fixed program drawn
// once over the whole target. Heaps draws a Plane2D with its own Pass; here a screen effect is
// an ordinary Material on the Fullscreen layout, drawn as one DrawItem over one triangle, so
// it goes through the same pipeline cache as the scene.

import { identity } from "../math/math3d";
import { Program, makeVertexBuffer } from "./gpu3d";
import { RenderState, Face, Compare } from "../gpu/state";
import { Material, Phase, TypedBlock, UniformBlock } from "./material";
import {
	GpuMesh, DrawItem, DrawContext, MeshId, MaterialId, MaterialError, addMaterial, reserveBlock,
} from "./draw";
import { UniformError } from "./uniformPool";

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
	return GpuMesh.fullscreen(vertexBuffer, 3);
}

export function makeScreenTriangle(): uint32 {
	return makeVertexBuffer(FULLSCREEN_TRIANGLE);
}

export function screenItem(mesh: MeshId, material: MaterialId): DrawItem {
	return { mesh: mesh, material: material, world: identity(), order: 0 };
}

export function reserveScreenBlock<T>(
	context: DrawContext,
	slot: int32,
	call: string,
): TypedBlock<T> {
	const reserved: Result<TypedBlock<T>, UniformError> = reserveBlock<T>(context, slot);
	if (reserved.ok) { return reserved.value; }
	console.log(`void3d: ${call} found no room for a block it was checked to fit: ` +
		`${reserved.error.toString()}`);
	unreachable;
}

export function addScreenMaterial(
	context: DrawContext,
	program: Program,
	state: RenderState,
	block: UniformBlock,
	call: string,
): MaterialId {
	const added: Result<MaterialId, MaterialError> = addMaterial(context, {
		...Material.plain(program, state, Phase.Opaque),
		uniforms: block,
	});
	if (added.ok) { return added.value; }
	console.log(`void3d: ${call} could not add its screen material: ${added.error.toString()}`);
	unreachable;
}
