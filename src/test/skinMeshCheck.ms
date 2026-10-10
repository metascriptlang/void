import {
	MeshData,
	MeshError,
	addSkinAttributes,
	stride,
	vertexCount,
	addVertex,
	addTangents,
} from "../void3d/meshData";
import {
	meshFor,
	DrawItem,
	DrawContext,
	NO_MESH,
	NO_MATERIAL,
	validRange,
	validSkin,
} from "../void3d/draw";
import { VertexLayout, ProgramKey, Program, withSkin } from "../void3d/gpu3d";
import { vec3, identity } from "../math/math3d";
import { Scene3D, Transform3D, addGroup, rootId, remove } from "../void3d/scene";
import { SkinPose, bind, syncSkinPose } from "../void3d/skinPose";
import { SkinPalette, create } from "../void3d/skinPalette";

function triangle(base: int32): MeshData {
	let data = MeshData.empty();
	data.hasUvs = base > 10;
	data.hasTangents = base == 16;
	data.indices = [0, 1, 2];
	for (let vertex = 0; vertex < 3; vertex++) {
		for (let field = 0; field < base; field++) {
			data.vertices.push((vertex * 100 + field) as float32);
		}
	}
	return move data;
}

test "skin draw references require a published live instance and matching program" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const bone = addGroup(scene, scene.rootId(), Transform3D.identity());
	const palette = SkinPalette.create([0]);
	assert palette.ok;
	if (!palette.ok) { return; }
	const pose = SkinPose.bind(scene, [0], [bone], [identity()], [palette.value]);
	assert pose.ok;
	if (!pose.ok) { return; }
	let item: DrawItem = {
		mesh: NO_MESH, material: NO_MATERIAL, world: identity(), order: 0,
		skin: pose.value, skinPalette: 0, range: null,
	};
	const program = ProgramKey.of(Program.Lit).withSkin();
	assert !item.validSkin(program);
	assert pose.value.syncSkinPose().ok;
	assert item.validSkin(program);
	assert !item.validSkin(ProgramKey.of(Program.Lit));
	item.skinPalette = 1;
	assert !item.validSkin(program);
	item.skinPalette = 0;
	const _removed = remove(scene, bone);
	const _replacement = addGroup(scene, scene.rootId(), Transform3D.identity());
	assert !item.validSkin(program);
}

test "element ranges refuse negatives, overrun and integer overflow but allow empty ranges" {
	let item: DrawItem = {
		mesh: NO_MESH, material: NO_MATERIAL, world: identity(), order: 0,
		skin: null, skinPalette: 0, range: null,
	};
	assert item.validRange(9);
	item.range = { base: 3, count: 6 };
	assert item.validRange(9);
	item.range = { base: 9, count: 0 };
	assert item.validRange(9);
	item.range = { base: 3, count: 7 };
	assert !item.validRange(9);
	item.range = { base: -1, count: 1 };
	assert !item.validRange(9);
	item.range = { base: 0x7ffffffe, count: 10 };
	assert !item.validRange(0x7fffffff);
}

function jointSlots(): Vec<int32> { return [0, 63, 2, 0, 2, 1, 0, 0, 63, 0, 0, 0]; }
function weights(): Vec<float32> { return [0.5, 0.25, 0.25, 0, 0.75, 0.25, 0, 0, 1, 0, 0, 0]; }

test "skin vertices preserve base attributes and append joints before weights for all layouts" {
	const joints = jointSlots();
	const amounts = weights();
	for (const base of [10, 12, 16]) {
		let data = triangle(base);
		const packed = addSkinAttributes(data, joints, amounts);
		assert packed.ok;
		assert data.stride() == base + 8;
		assert data.vertexCount() == 3;
		for (let vertex = 0; vertex < 3; vertex++) {
			const at: int32 = vertex * data.stride();
			for (let field = 0; field < base; field++) {
				assert data.vertices[at + field] == (vertex * 100 + field) as float32;
			}
			for (let slot = 0; slot < 4; slot++) {
				assert data.vertices[at + base + slot] == joints[vertex * 4 + slot] as float32;
				assert data.vertices[at + base + 4 + slot] == amounts[vertex * 4 + slot];
			}
		}
		const gpu = data.meshFor(1, 2, 7);
		const expected = base == 10 ? VertexLayout.SkinLit :
			(base == 12 ? VertexLayout.SkinLitTextured : VertexLayout.SkinLitTexturedTangent);
		assert gpu.layout == expected;
		assert gpu.vertexCount == 3 && gpu.indexCount == 3 && gpu.generation == 7;
	}
}

test "late invalid skin attributes leave geometry unmodified" {
	let data = triangle(10);
	let joints = jointSlots();
	let amounts = weights();
	joints[11] = 64;
	const outside = addSkinAttributes(data, joints, amounts);
	assert !outside.ok && outside.error == MeshError.SkinJoint;
	assert !data.hasSkin && data.vertices.length == 30 && data.vertices[29] == 209;
	joints[11] = 0;
	amounts[11] = -0.1;
	const negative = addSkinAttributes(data, joints, amounts);
	assert !negative.ok && negative.error == MeshError.SkinWeight;
	amounts[11] = 1.0;
	const sum = addSkinAttributes(data, joints, amounts);
	assert !sum.ok && sum.error == MeshError.SkinWeight;
	assert !data.hasSkin && data.vertices.length == 30;
	amounts.pop();
	const short = addSkinAttributes(data, joints, amounts);
	assert !short.ok && short.error == MeshError.SkinCount;
}

test "packed skin geometry refuses re-packing and geometry builders" {
	let data = triangle(12);
	const first = addSkinAttributes(data, jointSlots(), weights());
	assert first.ok;
	const again = addSkinAttributes(data, jointSlots(), weights());
	assert !again.ok && again.error == MeshError.SkinAdded;
	const vertex = addVertex(data, vec3(0, 0, 0), vec3(0, 0, 1),
		{ red: 1, green: 1, blue: 1, alpha: 1 });
	assert !vertex.ok && vertex.error == MeshError.SkinAdded;
	const tangent = addTangents(data);
	assert !tangent.ok && tangent.error == MeshError.SkinAdded;
	assert data.vertices.length == 60 && data.vertexCount() == 3;
}
