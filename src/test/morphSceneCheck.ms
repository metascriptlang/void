import {
	Scene3D, MorphNodeError, SceneSyncError, SceneMorph, NodeId3D, Transform3D, addMorphMeshNode, bindSceneMorph,
	setMorphWeights, rootId, closeScene, refreshChecked, setPickable, remove,
	fromTranslation,
} from "../void3d/scene";
import {
	MorphData, MorphGeometry, MorphGeometryError, MorphPrimitiveInput, publishMorphGeometry,
} from "../void3d/morphGeometry";
import { GltfWeightCurve, GltfWeightTrack, GltfCurveMode, forWeightValues } from "../void3d/gltfCurve";
import { GltfMorphPose, GltfMorphPoseError, bindMorphPose, sampleMorphPose } from "../void3d/gltfScene";
import { MeshData, addVertex, addTriangle, addSkinAttributes } from "../void3d/meshData";
import {
	DrawItem, MeshId, MaterialId, VertexStorage, MeshWriteError, setMeshVertices,
} from "../void3d/draw";
import { PickError, pickNearest } from "../void3d/pick";
import { Ray } from "../void3d/ray";
import { vec3 } from "../math/math3d";
import { Face } from "../gpu/state";
import { contextOf, meshAt, materialAt } from "./drawHelpers";

function triangle(): MeshData {
	let mesh = MeshData.empty();
	for (const point of [vec3(0, 0, 0), vec3(1, 0, 0), vec3(0, 1, 0)]) {
		const added = addVertex(mesh, point, vec3(0, 0, 1), { red: 1, green: 1, blue: 1, alpha: 1 });
		if (!added.ok) { unreachable; }
	}
	if (!addTriangle(mesh, 0, 1, 2).ok) { unreachable; }
	return move mesh;
}

// Two targets: target 0 moves every vertex by +10 in x, target 1 by +5 in y.
function primitive(): MorphPrimitiveInput {
	return {
		base: triangle(),
		sourceVertexCount: 3,
		sourceVertices: [0, 1, 2],
		targets: [
			{ positions: [10, 0, 0, 10, 0, 0, 10, 0, 0], normals: [], tangents: [] },
			{ positions: [0, 5, 0, 0, 5, 0, 0, 5, 0], normals: [], tangents: [] },
		],
	};
}

function morphData(primitives: int32 = 1): Readonly<MorphData> {
	let inputs: Vec<MorphPrimitiveInput> = [];
	for (let i = 0; i < primitives; i++) { inputs.push(primitive()); }
	const made = MorphData.create(inputs, 2);
	if (!made.ok) { unreachable; }
	return made.value;
}

function sceneMorph(data: Readonly<MorphData>, weights: Vec<float32>): SceneMorph {
	const made = bindSceneMorph(data, weights);
	if (!made.ok) { unreachable; }
	return made.value;
}

// `count` private dynamic meshes holding the base triangle: what addDynamicMeshData makes, with
// no GPU buffer, which a headless check cannot create.
function fixture(count: int32): Scene3D {
	const context = contextOf(count, 1);
	for (let i = 0; i < count; i++) {
		context.meshData[i] = triangle();
		context.meshStorage[i] = VertexStorage.Pending;
	}
	context.materials[0].pass.culling = Face.None;
	return Scene3D.create(context);
}

function owners(morph: SceneMorph | null): Vec<SceneMorph | null> {
	let list: Vec<SceneMorph | null> = [];
	list.push(morph);
	return move list;
}

function place(scene: Scene3D, morph: SceneMorph, mesh: int32, primitive: int32, at: Transform3D): Result<NodeId3D, MorphNodeError> {
	return addMorphMeshNode(scene, scene.rootId(), at, scene.context.meshAt(mesh),
		scene.context.materialAt(0), morph, primitive);
}

test "two instances of one morphed mesh deform independently and every consumer sees the same mesh" {
	const scene = fixture(2);
	defer closeScene(scene);
	const data = morphData();
	const a = sceneMorph(data, [1, 0]);
	const b = sceneMorph(data, [0, 0]);
	const nodeA = place(scene, a, 0, 0, Transform3D.identity());
	const nodeB = place(scene, b, 1, 0, Transform3D.fromTranslation(vec3(0, 100, 0)));
	assert nodeA.ok && nodeB.ok;
	if (!nodeA.ok || !nodeB.ok) { return; }
	setPickable(scene, nodeA.value, true);
	setPickable(scene, nodeB.value, true);
	let items: Vec<DrawItem> = [];
	const refreshed = refreshChecked(scene, items);
	assert refreshed.ok && items.length == 2;
	const context = scene.context;
	assert context.meshData[0].bounds.min.x == 10 && context.meshData[0].bounds.max.x == 11;
	assert context.meshData[1].bounds.min.x == 0 && context.meshData[1].bounds.max.x == 1;
	assert context.meshStorage[0] == VertexStorage.Pending;
	for (const item of items) {
		const deformed = context.meshData[item.mesh.index];
		const expected: float32 = item.mesh.index == 0 ? 10 : 0;
		assert deformed.vertices[0] == expected && deformed.bounds.min.x == expected;
	}
	const missesBase: Ray = { origin: vec3(10.25, 0.25, 2), direction: vec3(0, 0, -1) };
	const hit = pickNearest(scene, missesBase);
	assert hit.ok;
	if (hit.ok) {
		assert hit.value.point.x == 10.25 && hit.value.mesh.index == nodeA.value.index;
		assert hit.value.distance == 2;
	}
	const onlyBase: Ray = { origin: vec3(10.25, 100.25, 2), direction: vec3(0, 0, -1) };
	const none = pickNearest(scene, onlyBase);
	assert !none.ok;
	if (!none.ok) { assert none.error == PickError.NothingHit; }
	assert setMorphWeights(b, [0, 1]).ok;
	const above: Ray = { origin: vec3(0.25, 105.25, 2), direction: vec3(0, 0, -1) };
	const raised = pickNearest(scene, above);
	assert raised.ok;
	if (raised.ok) { assert raised.value.mesh.index == nodeB.value.index; }
	assert context.meshData[1].bounds.min.y == 5 && context.meshData[0].bounds.min.y == 0;
}

test "a weights track publishes its node once and every primitive follows" {
	const scene = fixture(2);
	defer closeScene(scene);
	const morph = sceneMorph(morphData(2), [0, 0]);
	assert place(scene, morph, 0, 0, Transform3D.identity()).ok;
	assert place(scene, morph, 1, 1, Transform3D.identity()).ok;
	const curve = GltfWeightCurve.forWeightValues(GltfCurveMode.Linear, 2, [0, 1], [0, 0, 1, 0.5]);
	assert curve.ok;
	if (!curve.ok) { return; }
	const tracks: Vec<GltfWeightTrack> = [{ sourceNode: 0, curve: curve.value }];
	const pose = GltfMorphPose.bindMorphPose(owners(morph), tracks);
	assert pose.ok;
	if (!pose.ok) { return; }
	const before: uint64 = morph.geometry.revision;
	const sampled = pose.value.sampleMorphPose(0.5);
	assert sampled.ok;
	if (sampled.ok) { assert sampled.value == 1; }
	assert morph.geometry.revision == before + 1;
	assert morph.geometry.weights[0] == 0.5 && morph.geometry.weights[1] == 0.25;
	let items: Vec<DrawItem> = [];
	assert refreshChecked(scene, items).ok;
	assert scene.context.meshData[0].bounds.min.x == 5 && scene.context.meshData[1].bounds.min.x == 5;
	assert scene.context.meshData[1].bounds.min.y == 1.25;
	const other = GltfMorphPose.bindMorphPose(owners(null), tracks);
	assert !other.ok;
	if (!other.ok) { assert other.error == GltfMorphPoseError.Target; }
	const two: Vec<GltfWeightTrack> = [tracks[0], tracks[0]];
	const duplicate = GltfMorphPose.bindMorphPose(owners(morph), two);
	assert !duplicate.ok;
	if (!duplicate.ok) { assert duplicate.error == GltfMorphPoseError.DuplicateTrack; }
}

test "a failed publish is a named error and the scene never draws the previous shape as current" {
	const scene = fixture(1);
	defer closeScene(scene);
	const morph = sceneMorph(morphData(), [1, 0]);
	const node = place(scene, morph, 0, 0, Transform3D.identity());
	assert node.ok;
	if (!node.ok) { return; }
	let items: Vec<DrawItem> = [];
	assert refreshChecked(scene, items).ok;
	const short = setMorphWeights(morph, [1]);
	assert !short.ok;
	if (!short.ok) { assert short.error == MorphGeometryError.Shape; }
	const stale = refreshChecked(scene, items);
	assert !stale.ok;
	if (!stale.ok) { assert stale.error == SceneSyncError.Morph; }
	const loose = setMorphWeights(morph, [1, NaN as float32]);
	assert !loose.ok;
	if (!loose.ok) { assert loose.error == MorphGeometryError.NonFinite; }
	assert !refreshChecked(scene, items).ok;
	morph.geometry.revision = 0xffffffffffffffff as uint64;
	const exhausted = setMorphWeights(morph, [1, 0]);
	assert !exhausted.ok;
	if (!exhausted.ok) { assert exhausted.error == MorphGeometryError.Revision; }
	morph.geometry.revision = 1;
	assert setMorphWeights(morph, [0, 1]).ok;
	assert refreshChecked(scene, items).ok;
	assert scene.context.meshData[0].bounds.min.y == 5;
	setPickable(scene, node.value, true);
	const hit = pickNearest(scene, { origin: vec3(0.25, 5.25, 2), direction: vec3(0, 0, -1) });
	assert hit.ok;
}

test "a morph node refuses a shared, static, skinned, unpublished or mismatched mesh" {
	const scene = fixture(4);
	defer closeScene(scene);
	const context = scene.context;
	const morph = sceneMorph(morphData(), [0, 0]);
	context.meshStorage[1] = VertexStorage.Immutable;
	context.meshHolders[2] = 2;
	context.meshData[3].vertices.pop();
	const stat = place(scene, morph, 1, 0, Transform3D.identity());
	assert !stat.ok;
	if (!stat.ok) { assert stat.error == MorphNodeError.Mesh; }
	const shared = place(scene, morph, 2, 0, Transform3D.identity());
	assert !shared.ok;
	if (!shared.ok) { assert shared.error == MorphNodeError.Mesh; }
	const shaped = place(scene, morph, 3, 0, Transform3D.identity());
	assert !shaped.ok;
	if (!shaped.ok) { assert shaped.error == MorphNodeError.Mesh; }
	const range = place(scene, morph, 0, 1, Transform3D.identity());
	assert !range.ok;
	if (!range.ok) { assert range.error == MorphNodeError.Primitive; }
	const bound = MorphGeometry.bind(morphData());
	assert bound.ok;
	if (!bound.ok) { return; }
	const fresh: SceneMorph = { geometry: bound.value };
	const unpublished = place(scene, fresh, 0, 0, Transform3D.identity());
	assert !unpublished.ok;
	if (!unpublished.ok) { assert unpublished.error == MorphNodeError.Unpublished; }
	context.meshData[0].hasSkin = true;
	const skinned = place(scene, morph, 0, 0, Transform3D.identity());
	assert !skinned.ok;
	if (!skinned.ok) { assert skinned.error == MorphNodeError.Skin; }
	assert scene.morphNodes == 0 && context.meshPins[0] == 0;
}

test "a morph node owns its mesh, keeps it, and gives it back at remove" {
	const scene = fixture(2);
	defer closeScene(scene);
	const context = scene.context;
	const morph = sceneMorph(morphData(), [0, 0]);
	const node = place(scene, morph, 0, 0, Transform3D.identity());
	assert node.ok;
	if (!node.ok) { return; }
	assert scene.morphNodes == 1 && context.meshPins[0] == 1 && context.meshHolders[0] == 2;
	const held: MeshId = context.meshAt(0);
	assert remove(scene, node.value) == 1;
	assert scene.morphNodes == 0;
	assert !context.hasMesh(held);
}

test "setMeshVertices writes only a dynamic mesh of the same shape" {
	const scene = fixture(2);
	defer closeScene(scene);
	const context = scene.context;
	context.meshStorage[1] = VertexStorage.Immutable;
	let moved = triangle();
	moved.vertices[0] = 7;
	const wrote = setMeshVertices(context, context.meshAt(0), moved);
	assert wrote.ok && context.meshData[0].vertices[0] == 7;
	const fixed = setMeshVertices(context, context.meshAt(1), moved);
	assert !fixed.ok;
	if (!fixed.ok) { assert fixed.error == MeshWriteError.NotDynamic; }
	moved.vertices.pop();
	const shaped = setMeshVertices(context, context.meshAt(0), moved);
	assert !shaped.ok;
	if (!shaped.ok) { assert shaped.error == MeshWriteError.Shape; }
}
