import {
	MeshData, MeshError, addTexturedVertex, rayIntersectionElements,
} from "../void3d/meshData";
import { SkinGeometry, SkinGeometryError, bind, syncGeometry } from "../void3d/skinGeometry";
import { SkinPose, bind as bindPose } from "../void3d/skinPose";
import { SkinPalette, create } from "../void3d/skinPalette";
import { DrawContext } from "../void3d/draw";
import { Scene3D, Transform3D, addGroup, rootId, closeScene } from "../void3d/scene";
import { identity, vec3 } from "../math/math3d";
import { Face } from "../gpu/state";
import { Ray } from "../void3d/ray";

function twoTriangles(): MeshData {
	let data = MeshData.withUvs();
	for (let triangle: int32 = 0; triangle < 2; triangle++) {
		for (let corner: int32 = 0; corner < 3; corner++) {
			const x: float32 = corner == 1 ? 1.0 : 0.0;
			const y: float32 = corner == 2 ? 1.0 : 0.0;
			const vertex = addTexturedVertex(data,
				vec3((triangle * 4.0 + x) as float32, y, 0), vec3(0, 0, 1),
				{ u: (triangle * 10.0 + x) as float32, v: (triangle * 20.0 + y) as float32 },
				{ red: 1, green: 1, blue: 1, alpha: 1 });
			if (!vertex.ok) { unreachable; }
		}
	}
	return move data;
}

function nearRay(): Ray { return { origin: vec3(0.25, 0.25, 2), direction: vec3(0, 0, -1) }; }
function farRay(): Ray { return { origin: vec3(4.25, 0.25, 2), direction: vec3(0, 0, -1) }; }

test "element ranges restrict unindexed triangles and preserve global UV corners" {
	const data = twoTriangles();
	const excluded = rayIntersectionElements(data, nearRay(), Face.None, 3, 3);
	assert excluded.ok;
	if (excluded.ok) { assert excluded.value.distance < 0; }
	const selected = rayIntersectionElements(data, farRay(), Face.None, 3, 3);
	assert selected.ok;
	if (selected.ok) {
		assert selected.value.distance == 2;
		const uv = selected.value.uv;
		assert uv !== null;
		if (uv !== null) { assert uv.u == 10.25 && uv.v == 20.25; }
	}
}

test "element ranges follow reordered indices rather than vertex or triangle offsets" {
	let data = twoTriangles();
	data.indices = [3, 4, 5, 0, 1, 2];
	const selected = rayIntersectionElements(data, nearRay(), Face.None, 3, 3);
	assert selected.ok;
	if (selected.ok) {
		assert selected.value.distance == 2;
		const uv = selected.value.uv;
		assert uv !== null;
		if (uv !== null) { assert uv.u == 0.25 && uv.v == 0.25; }
	}
	const excluded = rayIntersectionElements(data, farRay(), Face.None, 3, 3);
	assert excluded.ok;
	if (excluded.ok) { assert excluded.value.distance < 0; }
}

test "element offsets above uint16 remain wide and malformed ranges refuse" {
	let data = twoTriangles();
	for (let triangle: int32 = 0; triangle < 23334; triangle++) {
		data.indices.push(0); data.indices.push(1); data.indices.push(2);
	}
	data.indices[65538] = 3;
	data.indices[65539] = 4;
	data.indices[65540] = 5;
	const wide = rayIntersectionElements(data, farRay(), Face.None, 65538, 3);
	assert wide.ok;
	if (wide.ok) { assert wide.value.distance == 2; }
	for (const range of [
		{ base: -3, count: 3 }, { base: 0, count: -3 }, { base: 1, count: 3 },
		{ base: 0, count: 4 }, { base: 70002, count: 3 },
		{ base: 0x7ffffffe, count: 6 },
	]) {
		const invalid = rayIntersectionElements(
			data, nearRay(), Face.None, range.base, range.count,
		);
		assert !invalid.ok;
		if (!invalid.ok) { assert invalid.error == MeshError.DrawRange; }
	}
	const empty = rayIntersectionElements(data, nearRay(), Face.None, 70002, 0);
	assert empty.ok;
	if (empty.ok) { assert empty.value.distance < 0; }
}

test "posed element query keeps world space and refuses stale publication before range" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	defer closeScene(scene);
	const bone = addGroup(scene, scene.rootId(), {
		...Transform3D.identity(), position: vec3(10, 0, 0),
	});
	const palette = SkinPalette.create([0]);
	assert palette.ok;
	if (!palette.ok) { return; }
	const pose = SkinPose.bindPose(scene, [0], [bone], [identity()], [palette.value]);
	assert pose.ok;
	if (!pose.ok) { return; }
	let joints: Vec<int32> = [];
	let weights: Vec<float32> = [];
	for (let vertex: int32 = 0; vertex < 6; vertex++) {
		for (let slot: int32 = 0; slot < 4; slot++) {
			joints.push(0); weights.push(slot == 0 ? 1.0 : 0.0);
		}
	}
	const geometry = SkinGeometry.bind(
		twoTriangles(), { joints: joints, weights: weights }, pose.value,
	);
	assert geometry.ok;
	if (!geometry.ok) { return; }
	assert geometry.value.syncGeometry().ok;
	const ray: Ray = { origin: vec3(14.25, 0.25, 2), direction: vec3(0, 0, -1) };
	const selected = geometry.value.rayIntersectionElements(ray, Face.None, 3, 3);
	assert selected.ok;
	if (selected.ok) { assert selected.value.distance == 2; }
	const invalid = geometry.value.rayIntersectionElements(ray, Face.None, 1, 3);
	assert !invalid.ok;
	if (!invalid.ok) { assert invalid.error == SkinGeometryError.Range; }
	assert pose.value.syncSkinPose().ok;
	const staleValid = geometry.value.rayIntersectionElements(ray, Face.None, 3, 3);
	assert !staleValid.ok;
	if (!staleValid.ok) { assert staleValid.error == SkinGeometryError.Pose; }
	const stale = geometry.value.rayIntersectionElements(ray, Face.None, 1, 3);
	assert !stale.ok;
	if (!stale.ok) { assert stale.error == SkinGeometryError.Pose; }
}
