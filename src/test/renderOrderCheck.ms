import { vec3 } from "../math/math3d";
import { DrawContext, DrawItem } from "../void3d/draw";
import { Material, Phase } from "../void3d/material";
import { Program } from "../void3d/gpu3d";
import { RenderState } from "../gpu/state";
import { PassList, collect, sortBackToFront, sortByLayer } from "../void3d/passList";
import {
	Scene3D,
	NodeId3D,
	NodeFlag,
	NO_NODE_ID,
	SceneError,
	Transform3D,
	addMeshNode,
	addCameraNode,
	collectDrawListFor,
	refresh,
	remove,
	setRenderOrder,
	renderOrderOf,
} from "../void3d/scene";
import { Camera3D, ProjectionKind } from "../void3d/camera";
import { contextOf } from "./drawHelpers";

function meshAt(scene: Scene3D, context: DrawContext, mesh: int32, z: float32): NodeId3D {
	const added: Result<NodeId3D, SceneError> = addMeshNode(
		scene, scene.rootId(), Transform3D.fromTranslation(vec3(0.0, 0.0, z)),
		context.meshAt(mesh), context.materialAt(0),
	);
	return added.ok ? added.value : NO_NODE_ID;
}

function backToFront(): Vec<float32> {
	return [
		1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0,
		0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0,
	];
}

function alphaMaterials(): Vec<Material> {
	return [Material.plain(Program.Lit, RenderState.defaults(), Phase.Alpha)];
}

function alphaOrder(ref list: PassList, items: Vec<DrawItem>): int32 {
	collect(list, items, alphaMaterials());
	sortBackToFront(list, items, backToFront());
	return meshesInOrder(list, items);
}

function meshesInOrder(list: PassList, items: Vec<DrawItem>): int32 {
	let digits: int32 = 0;
	for (let i = 0; i < list.count; i++) {
		digits = digits * 10 + items[list.indices[i]].mesh.index;
	}
	return digits;
}

test "a node draws at order 0 until it is given one, and only that node changes" {
	const context: DrawContext = contextOf(2, 1);
	const scene: Scene3D = Scene3D.create(context);
	const a: NodeId3D = meshAt(scene, context, 0, 0.0);
	const b: NodeId3D = meshAt(scene, context, 1, 0.0);
	assert renderOrderOf(scene, a) == 0 && renderOrderOf(scene, b) == 0;
	assert renderOrderOf(scene, scene.rootId()) == 0;
	setRenderOrder(scene, a, -4);
	assert renderOrderOf(scene, a) == -4 && renderOrderOf(scene, b) == 0;
}

test "the draw list carries each node's order, and a literal that leaves it out draws at 0" {
	const context: DrawContext = contextOf(2, 1);
	const scene: Scene3D = Scene3D.create(context);
	const a: NodeId3D = meshAt(scene, context, 0, 0.0);
	const _b: NodeId3D = meshAt(scene, context, 1, 0.0);
	setRenderOrder(scene, a, 6);
	let items: Vec<DrawItem> = [];
	assert refresh(scene, items) == 2;
	assert items[0].order == 6 && items[1].order == 0;
	const bare: DrawItem = { ...items[1], world: items[1].world };
	assert bare.order == 0;
}

test "an order written on a steady frame reaches the item in place, with no rebuild" {
	const context: DrawContext = contextOf(2, 1);
	const scene: Scene3D = Scene3D.create(context);
	const a: NodeId3D = meshAt(scene, context, 0, 0.0);
	const b: NodeId3D = meshAt(scene, context, 1, 0.0);
	let items: Vec<DrawItem> = [];
	assert refresh(scene, items) == 2;
	assert !scene.structureChanged;
	setRenderOrder(scene, a, 3);
	setRenderOrder(scene, b, 2);
	assert !scene.structureChanged;
	assert refresh(scene, items) == 2;
	assert items[0].order == 3 && items[1].order == 2;
	assert items[0].mesh.index == 0 && items[1].mesh.index == 1;
	assert (items.length as int32) == 2;
}

test "swapping two orders between frames swaps the draw order of an alpha list" {
	const context: DrawContext = contextOf(2, 1);
	const scene: Scene3D = Scene3D.create(context);
	const near: NodeId3D = meshAt(scene, context, 0, 0.9);
	const far: NodeId3D = meshAt(scene, context, 1, 0.1);
	let items: Vec<DrawItem> = [];
	let alpha: PassList = PassList.forPhase(Phase.Alpha);
	assert refresh(scene, items) == 2;
	assert alphaOrder(alpha, items) == 1;
	setRenderOrder(scene, near, 2);
	setRenderOrder(scene, far, 1);
	assert refresh(scene, items) == 2;
	assert alphaOrder(alpha, items) == 10;
	setRenderOrder(scene, near, 1);
	setRenderOrder(scene, far, 2);
	assert refresh(scene, items) == 2;
	assert alphaOrder(alpha, items) == 1;
	setRenderOrder(scene, near, 2);
	setRenderOrder(scene, far, 2);
	assert refresh(scene, items) == 2;
	assert alphaOrder(alpha, items) == 1;
	assert !scene.structureChanged;
}

test "an un-culled node comes back with its order" {
	const context: DrawContext = contextOf(2, 1);
	const scene: Scene3D = Scene3D.create(context);
	const a: NodeId3D = meshAt(scene, context, 0, 0.0);
	const _b: NodeId3D = meshAt(scene, context, 1, 0.0);
	setRenderOrder(scene, a, 9);
	let items: Vec<DrawItem> = [];
	scene.nodes[a.index].flags = scene.nodes[a.index].flags.incl(NodeFlag.Culled);
	assert refresh(scene, items) == 1;
	scene.nodes[a.index].flags = scene.nodes[a.index].flags.excl(NodeFlag.Culled);
	assert refresh(scene, items) == 2;
	assert items[0].order == 9 && items[1].order == 0;
}

test "a second camera's list carries the order, and a reused slot starts at 0" {
	const context: DrawContext = contextOf(2, 1);
	const scene: Scene3D = Scene3D.create(context);
	const a: NodeId3D = meshAt(scene, context, 0, 0.0);
	const request: Camera3D = {
		position: vec3(0.0, 0.0, 4.0), yaw: 0.0, pitch: 0.0, nearPlane: 0.1, farPlane: 10.0,
		projection: { kind: ProjectionKind.Perspective, fovY: 1.0 },
	};
	const camera: NodeId3D = addCameraNode(scene, null, Transform3D.identity(), request);
	setRenderOrder(scene, a, -2);
	let second: Vec<DrawItem> = [];
	assert collectDrawListFor(scene, camera, second) == 1;
	assert second[0].order == -2;
	assert remove(scene, a) == 1;
	const reused: NodeId3D = meshAt(scene, context, 1, 0.0);
	assert renderOrderOf(scene, reused) == 0;
}

test "equal orders keep node order in the layer sort" {
	const context: DrawContext = contextOf(4, 1);
	const scene: Scene3D = Scene3D.create(context);
	const a: NodeId3D = meshAt(scene, context, 0, 0.0);
	const b: NodeId3D = meshAt(scene, context, 1, 0.0);
	const c: NodeId3D = meshAt(scene, context, 2, 0.0);
	const d: NodeId3D = meshAt(scene, context, 3, 0.0);
	setRenderOrder(scene, a, 5);
	setRenderOrder(scene, b, 1);
	setRenderOrder(scene, c, 5);
	setRenderOrder(scene, d, 1);
	let items: Vec<DrawItem> = [];
	assert refresh(scene, items) == 4;
	let opaque: PassList = PassList.forPhase(Phase.Alpha);
	collect(opaque, items, alphaMaterials());
	sortByLayer(opaque);
	assert meshesInOrder(opaque, items) == 1302;
}
