import { Vec3, vec3, Quat, eulerQuat } from "../math/math3d";
import { MeshData, Rgba, MeshError, addVertex, addTriangle } from "../void3d/meshData";
import { DrawItem } from "../void3d/draw";
import {
	Scene,
	NodeId,
	Transform3D,
	SceneError,
	NO_NODE,
	identityTransform,
	transformAt,
	addGroup,
	addMeshNode,
	setName,
	setLocal,
	remove,
	syncWorld,
	refresh,
} from "../void3d/scene";
import {
	AnimationClock,
	AnimationError,
	Interpolation,
	KeyPair,
	ObjectAnimation,
	MeshFrameAnimation,
	update,
	forgetSync,
	setFrame,
	addTrack,
	bindTracks,
	syncPose,
	bindMeshFrames,
	syncMeshFrame,
	checkBakedFrames,
} from "../void3d/animation";
import { approx } from "./helpers";

function clockOf(frames: int32, sampling: float64, interpolation: Interpolation): AnimationClock {
	const made: Result<AnimationClock, AnimationError> =
		AnimationClock.forFrames(frames, sampling, interpolation);
	if (made.ok) { return made.value; }
	return {
		frameCount: 0,
		sampling: 0.0,
		speed: 0.0,
		frame: 0.0,
		loop: false,
		pause: true,
		interpolation: interpolation,
	};
}

function moved(ref clock: AnimationClock, dt: float64): boolean {
	const advanced: Result<boolean, AnimationError> = update(clock, dt);
	return advanced.ok && advanced.value;
}

function pair(first: int32, second: int32, weight: float32): KeyPair {
	return { first: first, second: second, weight: weight };
}

function named(ref scene: Scene, parent: NodeId, name: string): NodeId {
	const added: Result<NodeId, SceneError> = addGroup(scene, parent, identityTransform());
	if (!added.ok) { return { index: NO_NODE, generation: 0 }; }
	const renamed: Result<int32, SceneError> = setName(scene, added.value, name);
	return renamed.ok ? added.value : { index: NO_NODE, generation: 0 };
}

function namedMesh(ref scene: Scene, name: string, mesh: int32): NodeId {
	const added: Result<NodeId, SceneError> =
		addMeshNode(scene, scene.rootId(), identityTransform(), mesh, 0);
	if (!added.ok) { return { index: NO_NODE, generation: 0 }; }
	const renamed: Result<int32, SceneError> = setName(scene, added.value, name);
	return renamed.ok ? added.value : { index: NO_NODE, generation: 0 };
}

function slide(x: float32): Transform3D {
	return transformAt(vec3(x, 0.0, 0.0));
}

function turn(angle: float32): Transform3D {
	return { ...identityTransform(), rotation: eulerQuat(0.0, angle, 0.0) };
}

function localX(scene: Scene, id: NodeId): float32 {
	return scene.nodes[id.index].local.position.x;
}

test "a clock needs at least one frame and a positive finite sampling rate" {
	const none: Result<AnimationClock, AnimationError> =
		AnimationClock.forFrames(0, 12.0, Interpolation.Step);
	assert !none.ok;
	if (!none.ok) { assert none.error == AnimationError.NoFrames; }
	const still: Result<AnimationClock, AnimationError> =
		AnimationClock.forFrames(4, 0.0, Interpolation.Step);
	assert !still.ok;
	if (!still.ok) { assert still.error == AnimationError.BadSampling; }
	const infinite: float64 = 1.0 / 0.0;
	const runaway: Result<AnimationClock, AnimationError> =
		AnimationClock.forFrames(4, infinite, Interpolation.Step);
	assert !runaway.ok;
	const fine: Result<AnimationClock, AnimationError> =
		AnimationClock.forFrames(4, 12.0, Interpolation.Linear);
	assert fine.ok;
	if (fine.ok) {
		assert fine.value.loop;
		assert !fine.value.pause;
		assert fine.value.speed == 1.0;
		assert approx(fine.value.duration() as float32, 0.33333334);
	}
}

test "a linear clock blends the two keys around its frame, and a loop blends last into first" {
	let clock: AnimationClock = clockOf(4, 1.0, Interpolation.Linear);
	clock.frame = 1.25;
	assert clock.keys().samePair(pair(1, 2, 0.25));
	clock.frame = 3.5;
	assert clock.keys().samePair(pair(3, 0, 0.5));
	clock.frame = 2.0;
	assert clock.keys().samePair(pair(2, 2, 0.0));
}

test "a clock that does not loop holds its last key rather than extrapolating past it" {
	let clock: AnimationClock = clockOf(4, 1.0, Interpolation.Linear);
	clock.loop = false;
	clock.frame = 2.5;
	assert clock.keys().samePair(pair(2, 3, 0.5));
	clock.frame = 3.5;
	assert clock.keys().samePair(pair(3, 3, 0.0));
	clock.frame = 4.0;
	assert clock.keys().samePair(pair(3, 3, 0.0));
}

test "a stepped clock samples the key its frame has reached, never a blend" {
	let clock: AnimationClock = clockOf(4, 1.0, Interpolation.Step);
	clock.frame = 1.99;
	assert clock.keys().samePair(pair(1, 1, 0.0));
	clock.frame = 3.7;
	assert clock.keys().samePair(pair(3, 3, 0.0));
}

test "a 12 fps stepped clock reports a change only when it reaches the next key" {
	let clock: AnimationClock = clockOf(12, 12.0, Interpolation.Step);
	const tick: float64 = 1.0 / 30.0;
	let changes: int32 = 0;
	for (let i = 0; i < 30; i++) {
		if (moved(clock, tick)) { changes = changes + 1; }
	}
	assert changes == 12;
	assert approx(clock.frame as float32, 0.0);
}

test "a linear clock reports every advance as a change" {
	let clock: AnimationClock = clockOf(12, 12.0, Interpolation.Linear);
	assert moved(clock, 0.01);
	assert moved(clock, 0.01);
}

test "update wraps a loop and clamps a one-shot at its end" {
	let looped: AnimationClock = clockOf(4, 2.0, Interpolation.Linear);
	const _moved: boolean = moved(looped, 2.25);
	assert approx(looped.frame as float32, 0.5);
	let once: AnimationClock = clockOf(4, 2.0, Interpolation.Linear);
	once.loop = false;
	assert !once.isFinished();
	const _ended: boolean = moved(once, 10.0);
	assert once.frame == 4.0;
	assert once.isFinished();
}

test "a paused or stopped clock does not move" {
	let paused: AnimationClock = clockOf(4, 12.0, Interpolation.Step);
	paused.pause = true;
	assert !moved(paused, 1.0);
	assert paused.frame == 0.0;
	let stopped: AnimationClock = clockOf(4, 12.0, Interpolation.Step);
	stopped.speed = 0.0;
	assert !moved(stopped, 1.0);
	assert stopped.frame == 0.0;
}

test "setFrame wraps outside the clip and refuses a non-finite frame" {
	let clock: AnimationClock = clockOf(4, 1.0, Interpolation.Linear);
	const past: Result<float64, AnimationError> = setFrame(clock, 5.5);
	assert past.ok;
	assert clock.frame == 1.5;
	const before: Result<float64, AnimationError> = setFrame(clock, -1.0);
	assert before.ok;
	assert clock.frame == 3.0;
	const nan: float64 = 0.0 / 0.0;
	const refused: Result<float64, AnimationError> = setFrame(clock, nan);
	assert !refused.ok;
	assert clock.frame == 3.0;
}

test "blendTo lerps translation and scale and takes the short way round in rotation" {
	const a: Transform3D = { ...slide(0.0), scale: vec3(1.0, 1.0, 1.0) };
	const b: Transform3D = { ...slide(4.0), scale: vec3(3.0, 1.0, 1.0) };
	const half: Transform3D = a.blendTo(b, 0.5);
	assert approx(half.position.x, 2.0);
	assert approx(half.scale.x, 2.0);
	const q: Quat = eulerQuat(0.0, 0.5, 0.0);
	const flipped: Transform3D = {
		...identityTransform(),
		rotation: { x: -q.x, y: -q.y, z: -q.z, w: -q.w },
	};
	const mid: Transform3D = turn(0.5).blendTo(flipped, 0.5);
	const expected: Quat = eulerQuat(0.0, 0.5, 0.0);
	assert approx(mid.rotation.y, expected.y);
	assert approx(mid.rotation.w, expected.w);
}

test "a track must carry one key per frame of its clock" {
	let animation: ObjectAnimation =
		ObjectAnimation.forClock(clockOf(3, 12.0, Interpolation.Step));
	const short: Vec<Transform3D> = [slide(0.0), slide(1.0)];
	const refused: Result<int32, AnimationError> = addTrack(animation, "arm", short);
	assert !refused.ok;
	if (!refused.ok) { assert refused.error == AnimationError.TrackLength; }
	const full: Vec<Transform3D> = [slide(0.0), slide(1.0), slide(2.0)];
	const added: Result<int32, AnimationError> = addTrack(animation, "arm", full);
	assert added.ok;
	if (added.ok) { assert added.value == 0; }
}

test "tracks bind by name under a base node, and a missing name is refused" {
	let scene: Scene = Scene.create();
	const body: NodeId = named(scene, scene.rootId(), "body");
	const arm: NodeId = named(scene, body, "arm");
	assert arm.index != NO_NODE;
	let animation: ObjectAnimation =
		ObjectAnimation.forClock(clockOf(2, 12.0, Interpolation.Step));
	const keys: Vec<Transform3D> = [slide(0.0), slide(1.0)];
	const _arm: Result<int32, AnimationError> = addTrack(animation, "arm", keys);
	const unbound: Result<int32, AnimationError> = syncPose(animation, scene);
	assert !unbound.ok;
	if (!unbound.ok) { assert unbound.error == AnimationError.NotBound; }
	const bound: Result<int32, AnimationError> = bindTracks(animation, scene, body);
	assert bound.ok;
	assert animation.tracks[0].target.index == arm.index;
	const _tail: Result<int32, AnimationError> = addTrack(animation, "tail", keys);
	const missing: Result<int32, AnimationError> = bindTracks(animation, scene, body);
	assert !missing.ok;
	if (!missing.ok) { assert missing.error == AnimationError.TargetNotFound; }
}

test "syncPose writes the sampled pose into the node and its world follows" {
	let scene: Scene = Scene.create();
	const body: NodeId = named(scene, scene.rootId(), "body");
	const arm: NodeId = named(scene, body, "arm");
	let animation: ObjectAnimation =
		ObjectAnimation.forClock(clockOf(4, 1.0, Interpolation.Linear));
	const keys: Vec<Transform3D> = [slide(0.0), slide(2.0), slide(4.0), slide(6.0)];
	const _arm: Result<int32, AnimationError> = addTrack(animation, "arm", keys);
	const _bound: Result<int32, AnimationError> = bindTracks(animation, scene, scene.rootId());
	animation.clock.frame = 1.5;
	const written: Result<int32, AnimationError> = syncPose(animation, scene);
	assert written.ok;
	if (written.ok) { assert written.value == 1; }
	assert approx(localX(scene, arm), 3.0);
	const _synced: int32 = syncWorld(scene);
	assert approx(scene.nodes[arm.index].world.m41, 3.0);
}

test "syncPose writes nothing while the sampled keys have not moved" {
	let scene: Scene = Scene.create();
	const arm: NodeId = named(scene, scene.rootId(), "arm");
	let animation: ObjectAnimation =
		ObjectAnimation.forClock(clockOf(4, 12.0, Interpolation.Step));
	const keys: Vec<Transform3D> = [slide(0.0), slide(1.0), slide(2.0), slide(3.0)];
	const _arm: Result<int32, AnimationError> = addTrack(animation, "arm", keys);
	const _bound: Result<int32, AnimationError> = bindTracks(animation, scene, scene.rootId());
	const first: Result<int32, AnimationError> = syncPose(animation, scene);
	assert first.ok;
	if (first.ok) { assert first.value == 1; }
	const _synced: int32 = syncWorld(scene);
	const _moved: boolean = moved(animation.clock, 0.01);
	const again: Result<int32, AnimationError> = syncPose(animation, scene);
	assert again.ok;
	if (again.ok) { assert again.value == 0; }
	assert syncWorld(scene) == 0;
	const _stepped: boolean = moved(animation.clock, 0.1);
	const next: Result<int32, AnimationError> = syncPose(animation, scene);
	assert next.ok;
	if (next.ok) { assert next.value == 1; }
	assert approx(localX(scene, arm), 1.0);
}

test "syncPose refuses a target that was removed after binding" {
	let scene: Scene = Scene.create();
	const arm: NodeId = named(scene, scene.rootId(), "arm");
	let animation: ObjectAnimation =
		ObjectAnimation.forClock(clockOf(1, 12.0, Interpolation.Step));
	const keys: Vec<Transform3D> = [slide(1.0)];
	const _arm: Result<int32, AnimationError> = addTrack(animation, "arm", keys);
	const _bound: Result<int32, AnimationError> = bindTracks(animation, scene, scene.rootId());
	const _gone: Result<int32, SceneError> = remove(scene, arm);
	const stale: Result<int32, AnimationError> = syncPose(animation, scene);
	assert !stale.ok;
	if (!stale.ok) { assert stale.error == AnimationError.StaleTarget; }
}

test "mesh frames only step, and carry one mesh per frame" {
	const meshes: Vec<int32> = [4, 5, 6];
	const blended: Result<MeshFrameAnimation, AnimationError> =
		MeshFrameAnimation.forMeshes(clockOf(3, 12.0, Interpolation.Linear), "flame", meshes);
	assert !blended.ok;
	if (!blended.ok) { assert blended.error == AnimationError.InterpolatedMeshFrames; }
	const short: Result<MeshFrameAnimation, AnimationError> =
		MeshFrameAnimation.forMeshes(clockOf(4, 12.0, Interpolation.Step), "flame", meshes);
	assert !short.ok;
	if (!short.ok) { assert short.error == AnimationError.TrackLength; }
}

test "mesh frames swap the node's mesh, and the draw list follows without a rebuild" {
	let scene: Scene = Scene.create();
	const _flame: NodeId = namedMesh(scene, "flame", 4);
	const _group: NodeId = named(scene, scene.rootId(), "group");
	let items: Vec<DrawItem> = [];
	const _first: int32 = refresh(scene, items);
	const meshes: Vec<int32> = [4, 5, 6];
	const made: Result<MeshFrameAnimation, AnimationError> =
		MeshFrameAnimation.forMeshes(clockOf(3, 1.0, Interpolation.Step), "flame", meshes);
	assert made.ok;
	if (made.ok) {
		let animation: MeshFrameAnimation = made.value;
		const notMesh: MeshFrameAnimation = { ...animation, name: "group" };
		let wrong: MeshFrameAnimation = notMesh;
		const refused: Result<int32, AnimationError> =
			bindMeshFrames(wrong, scene, scene.rootId());
		assert !refused.ok;
		if (!refused.ok) { assert refused.error == AnimationError.NotAMeshNode; }
		const _bound: Result<int32, AnimationError> =
			bindMeshFrames(animation, scene, scene.rootId());
		const shown: Result<int32, AnimationError> = syncMeshFrame(animation, scene);
		assert shown.ok;
		if (shown.ok) { assert shown.value == 1; }
		const same: Result<int32, AnimationError> = syncMeshFrame(animation, scene);
		assert same.ok;
		if (same.ok) { assert same.value == 0; }
		const _moved: boolean = moved(animation.clock, 2.0);
		const swapped: Result<int32, AnimationError> = syncMeshFrame(animation, scene);
		assert swapped.ok;
		if (swapped.ok) { assert swapped.value == 1; }
		assert !scene.structureChanged;
		const _drawn: int32 = refresh(scene, items);
		assert items[0].mesh == 6;
	}
}

function fan(lift: float32, count: int32, flip: boolean): MeshData {
	let data: MeshData = MeshData.empty();
	const up: Vec3 = vec3(0.0, 1.0, 0.0);
	const white: Rgba = { red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0 };
	for (let i = 0; i < count; i++) {
		const x: float32 = i as float32;
		const _v: Result<int32, MeshError> = addVertex(data, vec3(x, lift, 0.0), up, white);
	}
	for (let i = 1; i + 1 < count; i++) {
		const _t: Result<int32, MeshError> =
			flip ? addTriangle(data, 0, i + 1, i) : addTriangle(data, 0, i, i + 1);
	}
	return data;
}

test "baked frames share one topology and may only move their vertices" {
	const moving: Vec<MeshData> = [fan(0.0, 4, false), fan(0.5, 4, false), fan(1.0, 4, false)];
	const accepted: Result<int32, AnimationError> = checkBakedFrames(moving);
	assert accepted.ok;
	if (accepted.ok) { assert accepted.value == 3; }
	const grown: Vec<MeshData> = [fan(0.0, 4, false), fan(0.5, 5, false)];
	assert !checkBakedFrames(grown).ok;
	const rewound: Vec<MeshData> = [fan(0.0, 4, false), fan(0.5, 4, true)];
	const refused: Result<int32, AnimationError> = checkBakedFrames(rewound);
	assert !refused.ok;
	if (!refused.ok) { assert refused.error == AnimationError.FrameTopology; }
	const none: Vec<MeshData> = [];
	assert !checkBakedFrames(none).ok;
	const hollow: Vec<MeshData> = [MeshData.empty()];
	assert !checkBakedFrames(hollow).ok;
}

test "a non-finite step is refused and leaves the clock where it was" {
	let clock: AnimationClock = clockOf(4, 12.0, Interpolation.Linear);
	clock.frame = 1.5;
	const infinite: float64 = 1.0 / 0.0;
	const refused: Result<boolean, AnimationError> = update(clock, infinite);
	assert !refused.ok;
	if (!refused.ok) { assert refused.error == AnimationError.BadFrame; }
	assert clock.frame == 1.5;
}

test "setFrame on an exact multiple lands on the clip's end, as Heaps' loops do" {
	let clock: AnimationClock = clockOf(4, 1.0, Interpolation.Linear);
	const _eight: Result<float64, AnimationError> = setFrame(clock, 8.0);
	assert clock.frame == 4.0;
	assert clock.keys().samePair(pair(0, 0, 0.0));
	clock.loop = false;
	assert clock.keys().samePair(pair(3, 3, 0.0));
	const _back: Result<float64, AnimationError> = setFrame(clock, -4.0);
	assert clock.frame == 0.0;
}

test "a clock never extrapolates below its first key" {
	let clock: AnimationClock = clockOf(4, 1.0, Interpolation.Linear);
	clock.loop = false;
	clock.speed = -1.0;
	assert !moved(clock, 0.5);
	assert clock.frame == -0.5;
	assert clock.keys().samePair(pair(0, 0, 0.0));
}

test "a one-key linear clock reports no change, so an idle host can stop drawing" {
	let clock: AnimationClock = clockOf(1, 12.0, Interpolation.Linear);
	for (let i = 0; i < 10; i++) { assert !moved(clock, 0.01); }
}

test "a clock with no frames is refused by every animation built on it" {
	const empty: AnimationClock = {
		frameCount: 0,
		sampling: 1.0,
		speed: 1.0,
		frame: 0.0,
		loop: true,
		pause: false,
		interpolation: Interpolation.Step,
	};
	let animation: ObjectAnimation = ObjectAnimation.forClock(empty);
	const none: Vec<Transform3D> = [];
	const track: Result<int32, AnimationError> = addTrack(animation, "arm", none);
	assert !track.ok;
	if (!track.ok) { assert track.error == AnimationError.NoFrames; }
	const noMeshes: Vec<int32> = [];
	const frames: Result<MeshFrameAnimation, AnimationError> =
		MeshFrameAnimation.forMeshes(empty, "flame", noMeshes);
	assert !frames.ok;
	assert empty.keys().samePair(pair(0, 0, 0.0));
}

test "mesh frames refuse a negative mesh index" {
	const meshes: Vec<int32> = [3, -1];
	const refused: Result<MeshFrameAnimation, AnimationError> =
		MeshFrameAnimation.forMeshes(clockOf(2, 12.0, Interpolation.Step), "flame", meshes);
	assert !refused.ok;
	if (!refused.ok) { assert refused.error == AnimationError.BadMesh; }
}

test "a rebind that fails keeps the previous binding whole" {
	let scene: Scene = Scene.create();
	const a: NodeId = named(scene, scene.rootId(), "a");
	const armA: NodeId = named(scene, a, "arm");
	const _legA: NodeId = named(scene, a, "leg");
	const b: NodeId = named(scene, scene.rootId(), "b");
	const _armB: NodeId = named(scene, b, "arm");
	let animation: ObjectAnimation =
		ObjectAnimation.forClock(clockOf(1, 12.0, Interpolation.Step));
	const keys: Vec<Transform3D> = [slide(3.0)];
	const _arm: Result<int32, AnimationError> = addTrack(animation, "arm", keys);
	const _leg: Result<int32, AnimationError> = addTrack(animation, "leg", keys);
	const first: Result<int32, AnimationError> = bindTracks(animation, scene, a);
	assert first.ok;
	const refused: Result<int32, AnimationError> = bindTracks(animation, scene, b);
	assert !refused.ok;
	assert animation.bound;
	assert animation.tracks[0].target.index == armA.index;
	const posed: Result<int32, AnimationError> = syncPose(animation, scene);
	assert posed.ok;
	assert approx(localX(scene, armA), 3.0);
}

test "a target removed after a sync is refused even while the keys stand still" {
	let scene: Scene = Scene.create();
	const arm: NodeId = named(scene, scene.rootId(), "arm");
	let animation: ObjectAnimation =
		ObjectAnimation.forClock(clockOf(1, 12.0, Interpolation.Step));
	const keys: Vec<Transform3D> = [slide(1.0)];
	const _arm: Result<int32, AnimationError> = addTrack(animation, "arm", keys);
	const _bound: Result<int32, AnimationError> = bindTracks(animation, scene, scene.rootId());
	const first: Result<int32, AnimationError> = syncPose(animation, scene);
	assert first.ok;
	const _gone: Result<int32, SceneError> = remove(scene, arm);
	const stale: Result<int32, AnimationError> = syncPose(animation, scene);
	assert !stale.ok;
}

test "forgetSync makes the next sync write over a node someone else moved" {
	let scene: Scene = Scene.create();
	const arm: NodeId = named(scene, scene.rootId(), "arm");
	let animation: ObjectAnimation =
		ObjectAnimation.forClock(clockOf(1, 12.0, Interpolation.Step));
	const keys: Vec<Transform3D> = [slide(1.0)];
	const _arm: Result<int32, AnimationError> = addTrack(animation, "arm", keys);
	const _bound: Result<int32, AnimationError> = bindTracks(animation, scene, scene.rootId());
	const _first: Result<int32, AnimationError> = syncPose(animation, scene);
	const _moved: Result<int32, SceneError> = setLocal(scene, arm, slide(99.0));
	const cached: Result<int32, AnimationError> = syncPose(animation, scene);
	assert cached.ok;
	if (cached.ok) { assert cached.value == 0; }
	assert approx(localX(scene, arm), 99.0);
	forgetSync(animation);
	const rewritten: Result<int32, AnimationError> = syncPose(animation, scene);
	assert rewritten.ok;
	if (rewritten.ok) { assert rewritten.value == 1; }
	assert approx(localX(scene, arm), 1.0);
}
