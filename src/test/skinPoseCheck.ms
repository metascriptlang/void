import { approx } from "./helpers";
import { identity, translation, Mat4 } from "../math/math3d";
import { DrawContext } from "../void3d/draw";
import {
	Scene3D, Transform3D, addGroup, rootId, setLocal, remove,
} from "../void3d/scene";
import { SkinPalette, create } from "../void3d/skinPalette";
import { SkinPose, SkinPoseError, bind, syncSkinPose } from "../void3d/skinPose";

test "skin pose palette uses parent world and IBM, not another mesh model transform" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const actor = addGroup(scene, scene.rootId(), {
		...Transform3D.identity(), position: { x: 10.0, y: 0.0, z: 0.0 },
	});
	const bone = addGroup(scene, actor, {
		...Transform3D.identity(), position: { x: 2.0, y: 0.0, z: 0.0 },
	});
	const palette = SkinPalette.create([0]);
	assert palette.ok;
	if (!palette.ok) { return; }
	const pose = SkinPose.bind(scene, [1], [actor, bone], [translation(-2.0, 0.0, 0.0)],
		[palette.value]);
	assert pose.ok;
	if (!pose.ok) { return; }
	assert !pose.value.ready;
	assert pose.value.syncSkinPose().ok;
	assert pose.value.ready;
	assert approx(pose.value.worlds[0].m41, 12.0);
	assert approx(pose.value.blocks[0][3], 10.0);
	setLocal(scene, actor, { ...Transform3D.identity(), position: { x: 20.0, y: 0.0, z: 0.0 } });
	assert pose.value.syncSkinPose().ok;
	assert approx(pose.value.blocks[0][3], 20.0);
}

test "instances own palette outputs even when definitions and materials are shared" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const a = addGroup(scene, scene.rootId(), Transform3D.identity());
	const b = addGroup(scene, scene.rootId(), {
		...Transform3D.identity(), position: { x: 5.0, y: 0.0, z: 0.0 },
	});
	const palette = SkinPalette.create([0]);
	assert palette.ok;
	if (!palette.ok) { return; }
	const first = SkinPose.bind(scene, [0], [a], [identity()], [palette.value]);
	const second = SkinPose.bind(scene, [0], [b], [identity()], [palette.value]);
	assert first.ok && second.ok;
	if (!first.ok || !second.ok) { return; }
	assert first.value.syncSkinPose().ok;
	assert second.value.syncSkinPose().ok;
	assert approx(first.value.blocks[0][3], 0.0);
	assert approx(second.value.blocks[0][3], 5.0);
}

test "a failed later palette publishes neither earlier palette nor pending joint worlds" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const a = addGroup(scene, scene.rootId(), Transform3D.identity());
	const b = addGroup(scene, scene.rootId(), Transform3D.identity());
	const first = SkinPalette.create([0]);
	const second = SkinPalette.create([1]);
	assert first.ok && second.ok;
	if (!first.ok || !second.ok) { return; }
	const pose = SkinPose.bind(scene, [0, 1], [a, b], [identity(), identity()],
		[first.value, second.value]);
	assert pose.ok;
	if (!pose.ok) { return; }
	assert pose.value.syncSkinPose().ok;
	setLocal(scene, a, { ...Transform3D.identity(), position: { x: 7.0, y: 0.0, z: 0.0 } });
	const invalid: Mat4 = { ...identity(), m14: 1.0 };
	pose.value.inverseBindMatrices[1] = invalid;
	const failed = pose.value.syncSkinPose();
	assert !failed.ok;
	if (!failed.ok) { assert failed.error == SkinPoseError.Palette; }
	assert !pose.value.ready;
	assert pose.value.blocks[0][3] == 0.0 && pose.value.worlds[0].m41 == 0.0;
}

test "stale joint ids invalidate the pose before a recycled node can be read" {
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	const bone = addGroup(scene, scene.rootId(), Transform3D.identity());
	const palette = SkinPalette.create([0]);
	assert palette.ok;
	if (!palette.ok) { return; }
	const pose = SkinPose.bind(scene, [0], [bone], [identity()], [palette.value]);
	assert pose.ok;
	if (!pose.ok) { return; }
	assert pose.value.syncSkinPose().ok;
	const _removed: int32 = remove(scene, bone);
	const _replacement = addGroup(scene, scene.rootId(), Transform3D.identity());
	const failed = pose.value.syncSkinPose();
	assert !failed.ok;
	if (!failed.ok) { assert failed.error == SkinPoseError.Target; }
	assert !pose.value.ready;
}
