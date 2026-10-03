// expect closedFrames.bindMeshFrames: void3d: bindMeshFrames on mesh frames that were closed
// expect closedFrames.syncMeshFrame: void3d: syncMeshFrame on mesh frames that were closed
// expect closedScene.bindMeshFrames: void3d: bindMeshFrames on a scene that was closed
// expect closedScene.bindTracks: void3d: bindTracks on a scene that was closed
// expect closedScene.syncPose: void3d: syncPose on a scene that was closed
// expect otherScene.bindTracks: void3d: bindTracks on node 0 of another scene
// expect otherScene.syncPose: void3d: syncPose on node 1 of another scene
// expect otherScene.bindMeshFrames: void3d: bindMeshFrames on node 0 of another scene
// expect otherScene.syncMeshFrame: void3d: syncMeshFrame on node 1 of another scene
// expect pin.syncMeshFrame: void3d: setMeshOf found a node's pin taken through the context
import { argv } from "std/process";
import { RenderState } from "../../../src/gpu/state";
import { Program } from "../../../src/void3d/gpu3d";
import { Material, Phase } from "../../../src/void3d/material";
import {
	DrawContext,
	GpuMesh,
	MeshId,
	MaterialId,
	MaterialError,
	MeshUploadError,
	HandleError,
	addMesh,
	addMaterial,
	unpinMesh,
} from "../../../src/void3d/draw";
import {
	Scene3D,
	NodeId3D,
	SceneError,
	Transform3D,
	addGroup,
	addMeshNode,
	setName,
	closeScene,
} from "../../../src/void3d/scene";
import {
	AnimationClock,
	AnimationError,
	Interpolation,
	ObjectAnimation,
	MeshFrameAnimation,
	addTrack,
	bindTracks,
	syncPose,
	bindMeshFrames,
	syncMeshFrame,
	closeMeshFrames,
} from "../../../src/void3d/animation";

function meshOf(context: DrawContext): MeshId {
	const added: Result<MeshId, MeshUploadError> = addMesh(context, GpuMesh.fullscreen(0, 3));
	if (!added.ok) { unreachable; }
	return added.value;
}

function materialOf(context: DrawContext): MaterialId {
	const plain: Material = Material.plain(Program.Lit, RenderState.defaults(), Phase.Opaque);
	const added: Result<MaterialId, MaterialError> = addMaterial(context, plain);
	if (!added.ok) { unreachable; }
	return added.value;
}

function clockOf(frames: int32): AnimationClock {
	const made: Result<AnimationClock, AnimationError> =
		AnimationClock.forFrames(frames, 12.0, Interpolation.Step);
	if (!made.ok) { unreachable; }
	return made.value;
}

function framesOf(context: DrawContext): MeshFrameAnimation {
	let meshes: Vec<MeshId> = [meshOf(context), meshOf(context)];
	const made: Result<MeshFrameAnimation, AnimationError> =
		MeshFrameAnimation.forMeshes(context, clockOf(2), "frames", meshes);
	if (!made.ok) { unreachable; }
	return made.value;
}

function tracksOf(): ObjectAnimation {
	let animation: ObjectAnimation = ObjectAnimation.forClock(clockOf(2));
	let keys: Vec<Transform3D> = [Transform3D.identity(), Transform3D.identity()];
	const added: Result<int32, AnimationError> = addTrack(animation, "arm", keys);
	if (!added.ok) { unreachable; }
	return animation;
}

function namedMeshNode(scene: Scene3D, name: string): NodeId3D {
	const context: DrawContext = scene.context;
	const added: Result<NodeId3D, SceneError> = addMeshNode(
		scene, scene.rootId(), Transform3D.identity(), meshOf(context), materialOf(context),
	);
	if (!added.ok) { unreachable; }
	setName(scene, added.value, name);
	return added.value;
}

function closedCase(name: string): boolean {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	let scene: Scene3D = Scene3D.create(context);
	let frames: MeshFrameAnimation = framesOf(context);
	let tracks: ObjectAnimation = tracksOf();
	if (name == "closedFrames.bindMeshFrames") {
		closeMeshFrames(frames);
		const _r: Result<int32, AnimationError> = bindMeshFrames(frames, scene, scene.rootId());
	} else if (name == "closedFrames.syncMeshFrame") {
		closeMeshFrames(frames);
		const _r: Result<int32, AnimationError> = syncMeshFrame(frames, scene);
	} else if (name == "closedScene.bindMeshFrames") {
		closeScene(scene);
		const _r: Result<int32, AnimationError> = bindMeshFrames(frames, scene, scene.rootId());
	} else if (name == "closedScene.bindTracks") {
		closeScene(scene);
		const _r: Result<int32, AnimationError> = bindTracks(tracks, scene, scene.rootId());
	} else if (name == "closedScene.syncPose") {
		const arm: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
		setName(scene, arm, "arm");
		const _bound: Result<int32, AnimationError> = bindTracks(tracks, scene, scene.rootId());
		closeScene(scene);
		const _r: Result<int32, AnimationError> = syncPose(tracks, scene);
	} else {
		return false;
	}
	return true;
}

function otherSceneCase(name: string): boolean {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	let first: Scene3D = Scene3D.create(context);
	let second: Scene3D = Scene3D.create(context);
	let frames: MeshFrameAnimation = framesOf(context);
	let tracks: ObjectAnimation = tracksOf();
	if (name == "otherScene.bindTracks") {
		const _r: Result<int32, AnimationError> = bindTracks(tracks, first, second.rootId());
	} else if (name == "otherScene.syncPose") {
		const arm: NodeId3D = addGroup(first, first.rootId(), Transform3D.identity());
		setName(first, arm, "arm");
		const _bound: Result<int32, AnimationError> = bindTracks(tracks, first, first.rootId());
		const _r: Result<int32, AnimationError> = syncPose(tracks, second);
	} else if (name == "otherScene.bindMeshFrames") {
		const _r: Result<int32, AnimationError> = bindMeshFrames(frames, first, second.rootId());
	} else if (name == "otherScene.syncMeshFrame") {
		const _node: NodeId3D = namedMeshNode(first, "frames");
		const _bound: Result<int32, AnimationError> = bindMeshFrames(frames, first, first.rootId());
		const _r: Result<int32, AnimationError> = syncMeshFrame(frames, second);
	} else {
		return false;
	}
	return true;
}

function pinTakenCase(name: string): boolean {
	if (name != "pin.syncMeshFrame") { return false; }
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	let scene: Scene3D = Scene3D.create(context);
	let frames: MeshFrameAnimation = framesOf(context);
	const node: NodeId3D = namedMeshNode(scene, "frames");
	const _bound: Result<int32, AnimationError> = bindMeshFrames(frames, scene, scene.rootId());
	const shown: MeshId = scene.meshes[scene.nodes[node.index].payload].mesh;
	const _taken: Result<int32, HandleError> = unpinMesh(context, shown);
	const _r: Result<int32, AnimationError> = syncMeshFrame(frames, scene);
	return true;
}

function run(name: string): void {
	const known: boolean = closedCase(name) || otherSceneCase(name) || pinTakenCase(name);
	console.log(known ? `${name} returned` : `no case named '${name}'`);
}

run((argv.length as int32) > 1 ? argv[1] : "");
