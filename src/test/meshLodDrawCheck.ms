import { identity, vec3 } from "../math/math3d";
import { MeshData, addVertex } from "../void3d/meshData";
import { litShape } from "./drawHelpers";
import { SWAPCHAIN_LAYOUT } from "../gpu/target";
import {
	DrawContext, DrawItem, MaterialId, addMaterial, addMesh, drawItem, NO_MESH, NO_MATERIAL,
} from "../void3d/draw";
import { Material, Phase } from "../void3d/material";
import { RenderState } from "../gpu/state";
import { Program, ProgramKey, VERTEX_UNIFORM_LENGTH, LIGHT_UNIFORM_LENGTH } from "../void3d/gpu3d";
import { Renderer, RendererError, RENDERER_UNIFORM_LENGTH, beginFrame } from "../void3d/renderer";

test "LOD draw ranges preserve element offsets above uint16" {
	const item: DrawItem = {
		mesh: NO_MESH, material: NO_MATERIAL, world: identity(),
		range: { base: 65538, count: 3 },
	};
	assert item.validRange(65541);
	assert !item.validRange(65540);
	const whole: DrawItem = { ...item, range: null };
	assert whole.validRange(3);
}

test "LOD draw ranges refuse negative overflow and out of bounds" {
	const item: DrawItem = { mesh: NO_MESH, material: NO_MATERIAL, world: identity() };
	const negative: DrawItem = { ...item, range: { base: -1, count: 3 } };
	const negativeCount: DrawItem = { ...item, range: { base: 0, count: -1 } };
	const overflow: DrawItem = { ...item, range: { base: 2147483646, count: 3 } };
	const after: DrawItem = { ...item, range: { base: 4, count: 0 } };
	assert !negative.validRange(3);
	assert !negativeCount.validRange(3);
	assert !overflow.validRange(2147483647);
	assert !after.validRange(3);
	const empty: DrawItem = { ...item, range: { base: 3, count: 0 } };
	assert empty.validRange(3);
}

test "LOD CPU-backed range survives unavailable GPU buffers without drawing" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	const mesh = addMesh(context, litShape());
	const material = addMaterial(context,
		Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque));
	assert mesh.ok && material.ok;
	let data: MeshData = MeshData.empty();
	for (let i = 0; i < 3; i++) {
		assert addVertex(data, vec3(i as float32, 0.0, 0.0), vec3(0.0, 0.0, 1.0),
			{ red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 }).ok;
	}
	for (let i = 0; i < 9; i++) { data.indices.push(0); }
	const index: int32 = mesh.value.index;
	context.meshData[index] = data;
	context.meshes[index] = {
		...context.meshes[index], vertexBuffer: 0, indexBuffer: 0,
		vertexCount: 0, indexCount: 0, generation: 0,
	};
	assert context.meshes[index].elementCount() == 0;
	assert context.logicalElementCount(index) == 9;
	const item: DrawItem = {
		mesh: mesh.value, material: material.value, world: identity(), range: { base: 6, count: 3 },
	};
	assert item.validRange(context.logicalElementCount(index));
	const malformed: DrawItem = { ...item, range: { base: 8, count: 3 } };
	assert !malformed.validRange(context.logicalElementCount(index));
	drawItem(context, item, ProgramKey.of(Program.Lit), SWAPCHAIN_LAYOUT, []);
	assert context.meshes[index].hasNothingToDraw();
}

test "LOD raw GPU mesh keeps its original logical element count" {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	const mesh = addMesh(context, litShape());
	assert mesh.ok;
	const index: int32 = mesh.value.index;
	assert context.meshData[index].vertexCount() == 0;
	assert context.logicalElementCount(index) == context.meshes[index].elementCount();
}

test "LOD invalid range refuses actual renderer before frame publication" {
	let context: DrawContext = DrawContext.withUniformCapacity(RENDERER_UNIFORM_LENGTH);
	const made = Renderer.create(context);
	assert made.ok;
	const renderer: Renderer = made.value;
	const added = addMaterial(context,
		Material.plain(Program.Copy, RenderState.defaults(), Phase.Opaque));
	assert added.ok;
	const material: MaterialId = added.value;
	const item: DrawItem = {
		mesh: { store: context.serial, index: 0, generation: 1 }, material: material,
		world: identity(), range: { base: 3, count: 1 },
	};
	const camera: Vec<float32> = new Array(VERTEX_UNIFORM_LENGTH);
	const lights: Vec<float32> = new Array(LIGHT_UNIFORM_LENGTH);
	const before: int32 = renderer.generation;
	const refused = beginFrame(renderer, [item], camera, lights);
	assert !refused.ok;
	assert refused.error == RendererError.DrawRange;
	assert renderer.generation == before;
}
