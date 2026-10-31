import {
	SkinGeometry, SkinGeometryError, bind, syncGeometry, deformPublished, spatialReady,
	syncBounds, boundsCurrent, deformIfStale,
	rayIntersection as intersectSkin,
} from "../void3d/skinGeometry";
import { SkinPose, bind as bindPose, syncSkinPose } from "../void3d/skinPose";
import { SkinPalette, create } from "../void3d/skinPalette";
import { MeshData, addVertex, addTriangle, rayIntersection, stride } from "../void3d/meshData";
import { SkinInfluences } from "../void3d/skinInfluences";
import { DrawContext, DrawItem, NO_MESH, NO_MATERIAL, validSkin } from "../void3d/draw";
import { Program, ProgramKey, withSkin } from "../void3d/gpu3d";
import { PassList, forPhase, filterFrustum, sortBackToFront } from "../void3d/passList";
import { Phase } from "../void3d/material";
import { Frustum3D, fromMatrix } from "../void3d/frustum";
import {
	Scene3D, NodeId3D, Transform3D, addGroup, rootId, setLocal, remove,
} from "../void3d/scene";
import { Mat4, Vec3, identity, vec3, translation, multiplyAffine } from "../math/math3d";
import { Face } from "../gpu/state";
import { Ray } from "../void3d/ray";
import { Bounds3D, addPoint } from "../void3d/bounds";

function triangle(): MeshData {
	let mesh = MeshData.empty();
	for (const point of [vec3(0, 0, 0), vec3(1, 0, 0), vec3(0, 1, 0)]) {
		const _vertex = addVertex(
			mesh, point, vec3(0, 0, 1), { red: 1, green: 1, blue: 1, alpha: 1 },
		);
	}
	const _triangle = addTriangle(mesh, 0, 1, 2);
	return move mesh;
}

function influences(): SkinInfluences {
	return { joints: [0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0],
		weights: [0.25, 0.75, 0, 0, 0.25, 0.75, 0, 0, 0.25, 0.75, 0, 0] };
}

function uncachedReferencePoint(geometry: SkinGeometry, vertex: int32): Vec3 {
	const at: int32 = vertex * geometry.source.stride();
	const point: Vec3 = vec3(geometry.source.vertices[at], geometry.source.vertices[at + 1],
		geometry.source.vertices[at + 2]);
	let result: Vec3 = vec3(0, 0, 0);
	for (let slot = 0; slot < 4; slot++) {
		const influence: int32 = vertex * 4 + slot;
		const weight: float32 = geometry.influences.weights[influence];
		if (weight == 0) { continue; }
		const joint: int32 = geometry.influences.joints[influence];
		const matrix = geometry.pose.inverseBindMatrices[joint].multiplyAffine(
			geometry.pose.worlds[joint],
		);
		const transformed: Vec3 = point * matrix;
		result.x += transformed.x * weight;
		result.y += transformed.y * weight;
		result.z += transformed.z * weight;
	}
	return result;
}

test "skin source publication and pending copies retain independent uint32 topology" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const bone = addGroup(scene, scene.rootId(), Transform3D.identity());
	const palette = SkinPalette.create([0]);
	assert palette.ok;
	if (!palette.ok) { return; }
	const pose = SkinPose.bindPose(scene, [0], [bone], [identity()], [palette.value]);
	assert pose.ok;
	if (!pose.ok) { return; }
	let source = MeshData.empty();
	source.vertices = new Array(65539 * 10);
	source.vertices[65537 * 10] = 1.0;
	source.vertices[65538 * 10 + 1] = 1.0;
	assert addTriangle(source, 65536, 65537, 65538).ok;
	let values: SkinInfluences = {
		joints: new Array(65539 * 4), weights: new Array(65539 * 4),
	};
	for (let vertex = 0; vertex < 65539; vertex++) { values.weights[vertex * 4] = 1.0; }
	const first = SkinGeometry.bind(source, values, pose.value);
	const second = SkinGeometry.bind(source, values, pose.value);
	assert first.ok && second.ok;
	if (!first.ok || !second.ok) { return; }
	if (source.wideIndices !== null) { source.wideIndices[0] = 0; }
	assert first.value.source.indexAt(0) == 65536;
	assert pose.value.syncSkinPose().ok;
	assert first.value.deformPublished().ok && second.value.deformPublished().ok;
	assert first.value.mesh.indexAt(0) == 65536 && first.value.pending.indexAt(0) == 65536;
	const ray: Ray = { origin: vec3(0.25, 0.25, 1.0), direction: vec3(0.0, 0.0, -1.0) };
	assert first.value.mesh.rayIntersection(ray, Face.None).distance == 1.0;
	if (first.value.pending.wideIndices !== null) { first.value.pending.wideIndices[0] = 1; }
	assert second.value.pending.indexAt(0) == 65536 && first.value.mesh.indexAt(0) == 65536;
}

test "posed bounds and triangle picking use canonical joints, not GPU palette slots or mesh world" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const first = addGroup(scene, scene.rootId(), {
		...Transform3D.identity(), position: vec3(10, 0, 0),
	});
	const second = addGroup(scene, scene.rootId(), {
		...Transform3D.identity(), position: vec3(20, 0, 0),
	});
	const palette = SkinPalette.create([1, 0]);
	assert palette.ok;
	if (!palette.ok) { return; }
	const pose = SkinPose.bindPose(
		scene, [0, 1], [first, second], [identity(), identity()], [palette.value],
	);
	assert pose.ok;
	if (!pose.ok) { return; }
	const geometry = SkinGeometry.bind(triangle(), influences(), pose.value);
	assert geometry.ok;
	if (!geometry.ok) { return; }
	assert geometry.value.syncGeometry().ok;
	assert geometry.value.ready;
	assert geometry.value.mesh.bounds.min.x == 17.5;
	assert geometry.value.mesh.bounds.max.x == 18.5;
	const ray: Ray = { origin: vec3(17.75, 0.25, 2), direction: vec3(0, 0, -1) };
	assert geometry.value.mesh.rayIntersection(ray, Face.None).distance == 2;
	assert geometry.value.source.bounds.min.x == 0;
	setLocal(scene, second, { ...Transform3D.identity(), position: vec3(40, 0, 0) });
	assert geometry.value.syncGeometry().ok;
	assert geometry.value.mesh.bounds.min.x == 32.5;
	assert geometry.value.mesh.rayIntersection(ray, Face.None).distance < 0;
}

test "late nonfinite deformation preserves published vertices and invalidates spatial queries" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const bone = addGroup(scene, scene.rootId(), Transform3D.identity());
	const palette = SkinPalette.create([0]);
	assert palette.ok;
	if (!palette.ok) { return; }
	const pose = SkinPose.bindPose(scene, [0], [bone], [identity()], [palette.value]);
	assert pose.ok;
	if (!pose.ok) { return; }
	let source = triangle();
	source.vertices[20] = 3.0e38;
	let values = influences();
	for (let at = 0; at < values.joints.length; at++) { values.joints[at] = 0; }
	const geometry = SkinGeometry.bind(source, values, pose.value);
	assert geometry.ok;
	if (!geometry.ok) { return; }
	assert geometry.value.syncGeometry().ok;
	assert geometry.value.spatialReady();
	setLocal(scene, bone, {
		...Transform3D.identity(), position: vec3(2, 0, 0), scale: vec3(10, 1, 1),
	});
	const failed = geometry.value.syncGeometry();
	assert !failed.ok && failed.error == SkinGeometryError.NonFinite;
	assert !geometry.value.spatialReady();
	assert geometry.value.mesh.vertices[0] == 0;
	const ray: Ray = { origin: vec3(0, 0, 2), direction: vec3(0, 0, -1) };
	assert !intersectSkin(geometry.value, ray, Face.None).ok;
}

test "published pose revisions and recycled joints invalidate cached geometry" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const bone = addGroup(scene, scene.rootId(), Transform3D.identity());
	const palette = SkinPalette.create([0]);
	assert palette.ok;
	if (!palette.ok) { return; }
	const pose = SkinPose.bindPose(scene, [0], [bone], [identity()], [palette.value]);
	assert pose.ok;
	if (!pose.ok) { return; }
	let values = influences();
	for (let at = 0; at < values.joints.length; at++) { values.joints[at] = 0; }
	const geometry = SkinGeometry.bind(triangle(), values, pose.value);
	assert geometry.ok;
	if (!geometry.ok) { return; }
	assert geometry.value.syncGeometry().ok;
	assert geometry.value.spatialReady();
	assert pose.value.syncSkinPose().ok;
	assert !geometry.value.spatialReady();
	assert geometry.value.deformPublished().ok;
	assert geometry.value.spatialReady();
	const _removed = remove(scene, bone);
	const _replacement = addGroup(scene, scene.rootId(), Transform3D.identity());
	assert !geometry.value.spatialReady();
	assert !geometry.value.deformPublished().ok;
}

test "skin draw validation and frustum filtering use published world bounds without mesh model" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const bone = addGroup(scene, scene.rootId(), Transform3D.identity());
	const palette = SkinPalette.create([0]);
	assert palette.ok;
	if (!palette.ok) { return; }
	const pose = SkinPose.bindPose(scene, [0], [bone], [identity()], [palette.value]);
	assert pose.ok;
	if (!pose.ok) { return; }
	let values = influences();
	for (let at = 0; at < values.joints.length; at++) { values.joints[at] = 0; }
	const geometry = SkinGeometry.bind(triangle(), values, pose.value);
	assert geometry.ok;
	if (!geometry.ok) { return; }
	let item: DrawItem = {
		mesh: { ...NO_MESH, index: 0 }, material: NO_MATERIAL,
		world: translation(1000, 0, 0), order: 0, skin: null,
		skinGeometry: geometry.value, skinPalette: 0, range: null,
	};
	const program = ProgramKey.of(Program.Lit).withSkin();
	assert !item.validSkin(program);
	assert geometry.value.syncGeometry().ok;
	assert item.validSkin(program);
	let list = PassList.forPhase(Phase.Opaque);
	list.indices = [0]; list.layers = [0]; list.orders = [0]; list.count = 1;
	assert filterFrustum(list, [item], [triangle()], Frustum3D.fromMatrix(identity())) == 0;
	assert list.count == 1;
	item.skin = pose.value;
	assert !item.validSkin(program);
	item.skin = null;
	setLocal(scene, bone, { ...Transform3D.identity(), position: vec3(0, 0, 10) });
	assert geometry.value.syncGeometry().ok;
	item.world = translation(1000, 0, -1000);
	const other: DrawItem = { ...item, skinGeometry: null, world: translation(0, 0, 3) };
	list.indices = [0, 1];
	list.depths = [0, 0];
	list.layers = [0, 0];
	list.orders = [0, 0];
	list.count = 2;
	const camera: Vec<float32> = [1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1];
	sortBackToFront(list, [item, other], camera);
	assert list.indices[0] == 0 && list.depths[0] == 10;
}

test "two geometries consume one pose publication and never share pending vertex buffers" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const bone = addGroup(scene, scene.rootId(), Transform3D.identity());
	const palette = SkinPalette.create([0]);
	assert palette.ok;
	if (!palette.ok) { return; }
	const pose = SkinPose.bindPose(scene, [0], [bone], [identity()], [palette.value]);
	assert pose.ok;
	if (!pose.ok) { return; }
	let values = influences();
	for (let at = 0; at < values.joints.length; at++) { values.joints[at] = 0; }
	const first = SkinGeometry.bind(triangle(), values, pose.value);
	const second = SkinGeometry.bind(triangle(), values, pose.value);
	assert first.ok && second.ok;
	if (!first.ok || !second.ok) { return; }
	assert pose.value.syncSkinPose().ok;
	assert first.value.deformPublished().ok && second.value.deformPublished().ok;
	assert first.value.spatialReady() && second.value.spatialReady();
	first.value.pending.vertices[0] = 99;
	assert second.value.pending.vertices[0] == 0;
	pose.value.revision = 0xffffffffffffffff as uint64;
	assert !pose.value.syncSkinPose().ok;
	assert !first.value.spatialReady() && !second.value.spatialReady();
}

test "skin geometry owns canonical inputs and refuses invalid influence shapes" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const bone = addGroup(scene, scene.rootId(), Transform3D.identity());
	const palette = SkinPalette.create([0]);
	assert palette.ok;
	if (!palette.ok) { return; }
	const pose = SkinPose.bindPose(scene, [0], [bone], [identity()], [palette.value]);
	assert pose.ok;
	if (!pose.ok) { return; }
	let values = influences();
	assert !SkinGeometry.bind(triangle(), values, pose.value).ok;
	for (let at = 0; at < values.joints.length; at++) { values.joints[at] = 0; }
	const geometry = SkinGeometry.bind(triangle(), values, pose.value);
	assert geometry.ok;
	if (!geometry.ok) { return; }
	values.weights[0] = -1;
	assert geometry.value.syncGeometry().ok;
	assert geometry.value.influences.weights[0] == 0.25;
	values.weights.pop();
	const short = SkinGeometry.bind(triangle(), values, pose.value);
	assert !short.ok && short.error == SkinGeometryError.Shape;
}

test "skin geometries use one published inverse-bind snapshot until the next pose" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const bone = addGroup(scene, scene.rootId(), {
		...Transform3D.identity(), position: vec3(3, 0, 0),
	});
	const palette = SkinPalette.create([0]);
	assert palette.ok;
	if (!palette.ok) { return; }
	const pose = SkinPose.bindPose(scene, [0], [bone], [translation(-1, 0, 0)], [palette.value]);
	assert pose.ok;
	if (!pose.ok) { return; }
	let values = influences();
	for (let at = 0; at < values.joints.length; at++) { values.joints[at] = 0; }
	const first = SkinGeometry.bind(triangle(), values, pose.value);
	const second = SkinGeometry.bind(triangle(), values, pose.value);
	assert first.ok && second.ok;
	if (!first.ok || !second.ok) { return; }
	assert pose.value.syncSkinPose().ok;
	assert first.value.deformPublished().ok;
	pose.value.inverseBindMatrices[0] = translation(7, 0, 0);
	assert second.value.deformPublished().ok;
	assert first.value.mesh.vertices[0] == 2;
	assert second.value.mesh.vertices[0] == pose.value.blocks[0][3];
	assert second.value.mesh.vertices[0] == 2;
	assert pose.value.syncSkinPose().ok;
	assert !first.value.spatialReady() && !second.value.spatialReady();
	assert first.value.deformPublished().ok && second.value.deformPublished().ok;
	assert first.value.mesh.vertices[0] == 10 && second.value.mesh.vertices[0] == 10;
}

test "97 canonical joints match uncached deformation with reordered overlapping palettes" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	let nodes: Vec<NodeId3D> = [];
	let ids: Vec<int32> = [];
	let ibms: Vec<Mat4> = [];
	for (let joint = 0; joint < 97; joint++) {
		const x: float32 = (joint as float32) * 0.125;
		nodes.push(addGroup(scene, scene.rootId(), {
			...Transform3D.identity(), position: vec3(x, x * 0.5, -0.25),
			scale: vec3(1.5, 0.75, 2),
		}));
		ids.push(joint);
		ibms.push(translation(x * -0.25, 0.5, 0.25));
	}
	const first = SkinPalette.create([96, 64, 0]);
	const second = SkinPalette.create([1, 96]);
	assert first.ok && second.ok;
	if (!first.ok || !second.ok) { return; }
	const pose = SkinPose.bindPose(scene, ids, nodes, ibms, [first.value, second.value]);
	assert pose.ok;
	if (!pose.ok) { return; }
	const values: SkinInfluences = {
		joints: [96, 64, 1, 0, 0, 1, 64, 96, 64, 0, 96, 1],
		weights: [0.125, 0.25, 0.5, 0.125, 0.5, 0.125, 0.25, 0.125, 0.25, 0.25, 0.25, 0.25],
	};
	const geometry = SkinGeometry.bind(triangle(), values, pose.value);
	assert geometry.ok;
	if (!geometry.ok) { return; }
	for (let frame = 0; frame < 3; frame++) {
		setLocal(scene, nodes[96], {
			...Transform3D.identity(), position: vec3(12 + (frame as float32), 6, -0.25),
			scale: vec3(-1.5, 0.75, 2),
		});
		assert pose.value.syncSkinPose().ok;
		assert pose.value.jointMatrices.length == 97;
		assert pose.value.blocks[0][3] == pose.value.jointMatrices[96].m41;
		assert pose.value.blocks[1][3] == pose.value.jointMatrices[1].m41;
		assert geometry.value.deformPublished().ok;
		let expectedBounds = Bounds3D.empty();
		for (let vertex = 0; vertex < 3; vertex++) {
			const expected = uncachedReferencePoint(geometry.value, vertex);
			const at: int32 = vertex * geometry.value.source.stride();
			assert geometry.value.mesh.vertices[at] == expected.x;
			assert geometry.value.mesh.vertices[at + 1] == expected.y;
			assert geometry.value.mesh.vertices[at + 2] == expected.z;
			addPoint(expectedBounds, expected);
		}
		assert geometry.value.mesh.bounds.min.x == expectedBounds.min.x;
		assert geometry.value.mesh.bounds.max.y == expectedBounds.max.y;
	}
}

function pickDeforms(geometry: SkinGeometry): int32 {
	const deformed = geometry.deformIfStale();
	if (!deformed.ok) { unreachable; }
	return deformed.value;
}

function boundsHoldDeformed(geometry: SkinGeometry): boolean {
	const slack: float32 = 0.0001;
	const stride: int32 = geometry.source.stride();
	for (let vertex = 0; vertex < geometry.mesh.vertexCount(); vertex++) {
		const at: int32 = vertex * stride;
		const x: float32 = geometry.mesh.vertices[at];
		const y: float32 = geometry.mesh.vertices[at + 1];
		const z: float32 = geometry.mesh.vertices[at + 2];
		if (x < geometry.bounds.min.x - slack || x > geometry.bounds.max.x + slack ||
			y < geometry.bounds.min.y - slack || y > geometry.bounds.max.y + slack ||
			z < geometry.bounds.min.z - slack || z > geometry.bounds.max.z + slack) {
			return false;
		}
	}
	return true;
}

test "joint sphere bounds hold every vertex of a skin posed by translated joints" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const first = addGroup(scene, scene.rootId(), {
		...Transform3D.identity(), position: vec3(10, 0, 0),
	});
	const second = addGroup(scene, scene.rootId(), {
		...Transform3D.identity(), position: vec3(20, 5, 0),
	});
	const palette = SkinPalette.create([1, 0]);
	assert palette.ok;
	if (!palette.ok) { return; }
	const pose = SkinPose.bindPose(
		scene, [0, 1], [first, second], [identity(), identity()], [palette.value],
	);
	assert pose.ok;
	if (!pose.ok) { return; }
	const geometry = SkinGeometry.bind(triangle(), influences(), pose.value);
	assert geometry.ok;
	if (!geometry.ok) { return; }
	assert geometry.value.syncGeometry().ok;
	assert geometry.value.boundsCurrent() && !geometry.value.bounds.isEmpty();
	assert boundsHoldDeformed(geometry.value);
	setLocal(scene, second, { ...Transform3D.identity(), position: vec3(-40, 7, 3) });
	assert geometry.value.syncGeometry().ok;
	assert boundsHoldDeformed(geometry.value);
}

test "joint sphere bounds hold a skin posed by a rotated and scaled two joint chain" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const root = addGroup(scene, scene.rootId(), {
		position: vec3(5, 0, 0), rotation: { x: 0, y: 0, z: 0.70710678, w: 0.70710678 },
		scale: vec3(2, 2, 2),
	});
	const child = addGroup(scene, root, {
		position: vec3(3, 1, 0), rotation: { x: 0.38268343, y: 0, z: 0, w: 0.92387953 },
		scale: vec3(1, 0.5, 1),
	});
	const palette = SkinPalette.create([0, 1]);
	assert palette.ok;
	if (!palette.ok) { return; }
	const pose = SkinPose.bindPose(
		scene, [0, 1], [root, child], [identity(), identity()], [palette.value],
	);
	assert pose.ok;
	if (!pose.ok) { return; }
	const geometry = SkinGeometry.bind(triangle(), influences(), pose.value);
	assert geometry.ok;
	if (!geometry.ok) { return; }
	assert geometry.value.syncGeometry().ok;
	assert boundsHoldDeformed(geometry.value);
	assert geometry.value.bounds.max.y - geometry.value.bounds.min.y > 1.0;
}

function squareBar(): MeshData {
	let mesh = MeshData.empty();
	for (const point of [vec3(0, 0, 0), vec3(4, 1, 1), vec3(4, 0, 0), vec3(0, 1, 1)]) {
		const _vertex = addVertex(
			mesh, point, vec3(0, 0, 1), { red: 1, green: 1, blue: 1, alpha: 1 },
		);
	}
	const _first = addTriangle(mesh, 0, 1, 2);
	const _second = addTriangle(mesh, 0, 3, 1);
	return move mesh;
}

test "joint bounds hold the edges of a square bar turned about its long side" {
	for (const turn of [0.38268343 as float32, 0.70710678 as float32]) {
		const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
		const bar = addGroup(scene, scene.rootId(), {
			...Transform3D.identity(),
			rotation: { x: turn, y: 0, z: 0, w: Math.sqrt(1 - turn * turn) as float32 },
		});
		const palette = SkinPalette.create([0]);
		assert palette.ok;
		if (!palette.ok) { return; }
		const pose = SkinPose.bindPose(scene, [0], [bar], [identity()], [palette.value]);
		assert pose.ok;
		if (!pose.ok) { return; }
		const whole: SkinInfluences = {
			joints: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
			weights: [1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0],
		};
		const geometry = SkinGeometry.bind(squareBar(), whole, pose.value);
		assert geometry.ok;
		if (!geometry.ok) { return; }
		assert geometry.value.syncGeometry().ok;
		assert boundsHoldDeformed(geometry.value);
	}
}

test "joint bounds publish without deforming and a pick deforms once per pose" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const first = addGroup(scene, scene.rootId(), {
		...Transform3D.identity(), position: vec3(10, 0, 0),
	});
	const second = addGroup(scene, scene.rootId(), Transform3D.identity());
	const palette = SkinPalette.create([1, 0]);
	assert palette.ok;
	if (!palette.ok) { return; }
	const pose = SkinPose.bindPose(
		scene, [0, 1], [first, second], [identity(), identity()], [palette.value],
	);
	assert pose.ok;
	if (!pose.ok) { return; }
	const geometry = SkinGeometry.bind(triangle(), influences(), pose.value);
	assert geometry.ok;
	if (!geometry.ok) { return; }
	assert pose.value.syncSkinPose().ok;
	assert geometry.value.syncBounds().ok;
	assert geometry.value.boundsCurrent() && !geometry.value.ready;
	assert geometry.value.revision == 0 && geometry.value.mesh.vertices[0] == 0;
	const vertices: int32 = geometry.value.source.vertexCount();
	assert pickDeforms(geometry.value) == vertices && geometry.value.spatialReady();
	assert boundsHoldDeformed(geometry.value);
	assert pickDeforms(geometry.value) == 0;
	setLocal(scene, first, { ...Transform3D.identity(), position: vec3(30, 0, 0) });
	assert pose.value.syncSkinPose().ok;
	assert !geometry.value.boundsCurrent() && !geometry.value.spatialReady();
	assert pickDeforms(geometry.value) == vertices;
}

test "a joint that weighs no vertex has no sphere and adds nothing to the bounds" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const used = addGroup(scene, scene.rootId(), {
		...Transform3D.identity(), position: vec3(10, 0, 0),
	});
	const idle = addGroup(scene, scene.rootId(), Transform3D.identity());
	const palette = SkinPalette.create([0, 1]);
	assert palette.ok;
	if (!palette.ok) { return; }
	const pose = SkinPose.bindPose(
		scene, [0, 1], [used, idle], [identity(), identity()], [palette.value],
	);
	assert pose.ok;
	if (!pose.ok) { return; }
	let values = influences();
	for (let at = 0; at < values.joints.length; at++) { values.joints[at] = 0; }
	const geometry = SkinGeometry.bind(triangle(), values, pose.value);
	assert geometry.ok;
	if (!geometry.ok) { return; }
	assert geometry.value.jointSpheres[6] >= 0 && geometry.value.jointSpheres[13] == -1;
	assert geometry.value.syncGeometry().ok;
	const before: Bounds3D = geometry.value.bounds;
	setLocal(scene, idle, { ...Transform3D.identity(), position: vec3(900, 900, 900) });
	assert geometry.value.syncGeometry().ok;
	assert geometry.value.bounds.min.x == before.min.x;
	assert geometry.value.bounds.max.y == before.max.y;
	assert boundsHoldDeformed(geometry.value);
}
