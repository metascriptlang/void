// expect closed.addMeshNode: void3d: addMeshNode on a scene that was closed
// expect closed.addLightNode: void3d: addLightNode on a scene that was closed
// expect closed.remove: void3d: remove on a scene that was closed
// expect closed.removeChildren: void3d: removeChildren on a scene that was closed
// expect closed.setLocal: void3d: setLocal on a scene that was closed
// expect closed.setVisible: void3d: setVisible on a scene that was closed
// expect closed.setPickable: void3d: setPickable on a scene that was closed
// expect closed.setMeshOf: void3d: setMeshOf on a scene that was closed
// expect closed.setLightPower: void3d: setLightPower on a scene that was closed
// expect closed.setName: void3d: setName on a scene that was closed
// expect closed.setAmbient: void3d: setAmbient on a scene that was closed
// expect closed.syncWorld: void3d: syncWorld on a scene that was closed
// expect closed.collectDrawList: void3d: collectDrawList on a scene that was closed
// expect closed.refresh: void3d: refresh on a scene that was closed
// expect closed.collectLights: void3d: collectLights on a scene that was closed
// expect closed.closeScene: void3d: closeScene on a scene that was closed
// expect closed.pickNearest: void3d: pickNearest on a scene that was closed
// expect contextClosed.addMeshNode: void3d: addMeshNode on a draw context that was closed
// expect contextClosed.setMeshOf: void3d: setMeshOf on a draw context that was closed
// expect pin.remove: void3d: remove found a node's pin taken through the context
// expect pin.removeChildren: void3d: removeChildren found a node's pin taken through the context
// expect pin.closeScene: void3d: closeScene found a node's pin taken through the context
// expect pin.setMeshOf: void3d: setMeshOf found a node's pin taken through the context
// expect closed.addCameraNode: void3d: addCameraNode on a scene that was closed
// expect closed.setCameraOf: void3d: setCameraOf on a scene that was closed
// expect closed.setActiveCamera: void3d: setActiveCamera on a scene that was closed
// expect closed.cameraOf: void3d: cameraOf on a scene that was closed
// expect camera.foreign.setCameraOf: void3d: setCameraOf on node 0 of another scene
// expect camera.foreign.setActiveCamera: void3d: setActiveCamera on node 0 of another scene
// expect camera.unbound.setCameraOf: void3d: setCameraOf on node 0 without a camera binding
// expect camera.unbound.setActiveCamera: void3d: setActiveCamera on node 0 without a camera binding
// expect camera.stale.setCameraOf: void3d: setCameraOf on stale node 1
// expect camera.stale.setActiveCamera: void3d: setActiveCamera on stale node 1
// expect closed.attach: void3d: attach on a scene that was closed
// expect closed.insertBefore: void3d: insertBefore on a scene that was closed
// expect closed.addGroupDetached: void3d: addGroup on a scene that was closed
// expect closed.addMeshDetached: void3d: addMeshNode on a scene that was closed
// expect closed.addLightDetached: void3d: addLightNode on a scene that was closed
// expect closed.addCameraDetached: void3d: addCameraNode on a scene that was closed
// expect move.self.attach: void3d: attach would form a cycle
// expect move.descendant.attach: void3d: attach would form a cycle
// expect move.root.attach: void3d: attach asked to attach the scene root
// expect move.foreign.attach: void3d: attach on node 1 of another scene
// expect move.foreignParent.attach: void3d: attach on node 0 of another scene
// expect move.stale.attach: void3d: attach on stale node 3
// expect move.self.insertBefore: void3d: insertBefore would form a cycle
// expect move.descendant.insertBefore: void3d: insertBefore would form a cycle
// expect move.root.insertBefore: void3d: insertBefore asked to attach the scene root
// expect move.foreign.insertBefore: void3d: insertBefore on node 1 of another scene
// expect move.foreignParent.insertBefore: void3d: insertBefore on node 0 of another scene
// expect move.stale.insertBefore: void3d: insertBefore on stale node 3
// expect move.foreignBefore.insertBefore: void3d: insertBefore on node 0 of another scene
// expect move.staleBefore.insertBefore: void3d: insertBefore on stale node 4
// expect move.wrongBefore.insertBefore: void3d: insertBefore before node has another parent
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
// expect closedScene.addGltfNodes: void3d: addGltfNodes on a scene that was closed
// expect closedContext.addGltfNodes: void3d: addGltfNodes on a draw context that was closed
// expect lightColor.closed: void3d: setLightColor on a scene that was closed
// expect lightColor.stale: void3d: setLightColor on stale node 1
// expect lightColor.group: void3d: setLightColor asked of a Group node 0; only a Light node has it
// expect lightColor.foreign: void3d: setLightColor on node 0 of another scene
// expect stale.addGroup: void3d: addGroup on stale node 1
// expect stale.addGltfNodes: void3d: addGltfNodes on stale node 1: the handle has generation 1, the row 2
// expect stale.addLightNode: void3d: addLightNode on stale node 1: the handle has generation 1, the row 2
// expect stale.addMeshNode: void3d: addMeshNode on stale node 1: the handle has generation 1, the row 2
// expect stale.removeChildren: void3d: removeChildren on stale node 1: the handle has generation 1, the row 2
// expect stale.remove: void3d: remove on stale node 1: the handle has generation 1, the row 2
// expect stale.setLightPower: void3d: setLightPower on stale node 1: the handle has generation 1, the row 2
// expect stale.setMeshOf: void3d: setMeshOf on stale node 1: the handle has generation 1, the row 2
// expect stale.setName: void3d: setName on stale node 1: the handle has generation 1, the row 2
// expect stale.setPickable: void3d: setPickable on stale node 1: the handle has generation 1, the row 2
// expect stale.setVisible: void3d: setVisible on stale node 1: the handle has generation 1, the row 2
// expect stale.setLocal: void3d: setLocal on stale node 1: the handle has generation 1, the row 2
// expect group.setLightPower: void3d: setLightPower asked of a Group node 1; only a Light node has it
// expect group.setMeshOf: void3d: setMeshOf asked of a Group node 1; only a Mesh node has it
// expect foreign.remove: void3d: remove on node 1 of another scene
// expect root.remove: void3d: remove asked of the scene root; removeChildren empties it
// expect unset.setLocal: void3d: setLocal on node id -1, which names no node of this scene
// expect contextClosed.sceneCreate: void3d: Scene3D.create on a draw context that was closed
// expect closedTwice.closeGltfAssets: void3d: closeGltfAssets on glTF assets that were closed
// expect closedTwice.closeMeshFrames: void3d: closeMeshFrames on mesh frames that were closed
// expect otherContext.bindMeshFrames: void3d: bindMeshFrames pairs mesh frames with a scene of another context
// expect closedScene.syncMeshFrame: void3d: syncMeshFrame on a scene that was closed
import { argv } from "std/process";
import { vec3 } from "../../../src/math/math3d";
import { RenderState } from "../../../src/gpu/state";
import { Program } from "../../../src/void3d/gpu3d";
import { Material, Phase } from "../../../src/void3d/material";
import {
	DrawContext,
	DrawItem,
	GpuMesh,
	MeshId,
	MaterialId,
	MaterialError,
	MeshUploadError,
	HandleError,
	NO_MESH,
	NO_MATERIAL,
	addMesh,
	addMaterial,
	releaseMesh,
	releaseMaterial,
	unpinMesh,
	unpinMaterial,
	closeContext,
} from "../../../src/void3d/draw";
import {
	Scene3D,
	NodeId3D,
	SceneError,
	LightError,
	LightInstance,
	LightKind,
	Transform3D,
	NO_NODE_ID,
	addGroup,
	addMeshNode,
	addLightNode,
	addCameraNode,
	setCameraOf,
	setActiveCamera,
	cameraOf,
	attach,
	insertBefore,
	remove,
	removeChildren,
	setLocal,
	setVisible,
	setPickable,
	setMeshOf,
	setLightPower,
	setLightColor,
	setName,
	setAmbient,
	syncWorld,
	collectDrawList,
	refresh,
	collectLights,
	closeScene,
} from "../../../src/void3d/scene";
import { Ray } from "../../../src/void3d/ray";
import { PickHit, PickError, pickNearest } from "../../../src/void3d/pick";
import { Camera3D, CameraError, ProjectionKind } from "../../../src/void3d/camera";
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
import { GltfData, GltfError, loadGltf } from "../../../src/void3d/gltf";
import {
	GltfAssets,
	GltfMeshBinding,
	GltfSceneError,
	addGltfNodes,
	closeGltfAssets,
} from "../../../src/void3d/gltfScene";

const DOCUMENT: string = "{\"asset\":{\"version\":\"2.0\"},\"scenes\":[{\"nodes\":[0]}],"
	+ "\"nodes\":[{\"name\":\"only\"}],\"meshes\":[],\"accessors\":[],"
	+ "\"bufferViews\":[],\"buffers\":[]}";

function cameraRequest(): Camera3D {
	return {
		position: vec3(0.0, 0.0, 4.0), yaw: 0.0, pitch: 0.0,
		nearPlane: 0.1, farPlane: 40.0,
		projection: { kind: ProjectionKind.Perspective, fovY: 1.0 },
	};
}

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

function meshNode(scene: Scene3D, parent: NodeId3D, mesh: MeshId, material: MaterialId): NodeId3D {
	const added: Result<NodeId3D, SceneError> =
		addMeshNode(scene, parent, Transform3D.identity(), mesh, material);
	if (!added.ok) { unreachable; }
	return added.value;
}

function closedCase(name: string): boolean {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	let scene: Scene3D = Scene3D.create(context);
	const root: NodeId3D = scene.rootId();
	closeScene(scene);
	let items: Vec<DrawItem> = [];
	let lights: Vec<float32> = [0.0, 0.0, 0.0, 0.0];
	const light: LightInstance = {
		kind: LightKind.Point,
		color: vec3(1.0, 1.0, 1.0),
		radius: 1.0,
		power: 1.0,
		priority: 0,
	};
	if (name == "closed.addMeshNode") {
		const _r: Result<NodeId3D, SceneError> =
			addMeshNode(scene, root, Transform3D.identity(), NO_MESH, NO_MATERIAL);
	} else if (name == "closed.addLightNode") {
		const _r: NodeId3D = addLightNode(scene, root, Transform3D.identity(), light);
	} else if (name == "closed.remove") {
		const _r: int32 = remove(scene, root);
	} else if (name == "closed.removeChildren") {
		const _r: int32 = removeChildren(scene, root);
	} else if (name == "closed.setLocal") {
		setLocal(scene, root, Transform3D.identity());
	} else if (name == "closed.setVisible") {
		setVisible(scene, root, false);
	} else if (name == "closed.setPickable") {
		setPickable(scene, root, true);
	} else if (name == "closed.setMeshOf") {
		const _r: Result<int32, SceneError> = setMeshOf(scene, root, NO_MESH);
	} else if (name == "closed.setLightPower") {
		setLightPower(scene, root, 0.5);
	} else if (name == "closed.setName") {
		setName(scene, root, "root");
	} else if (name == "closed.setAmbient") {
		setAmbient(scene, vec3(1.0, 1.0, 1.0));
	} else if (name == "closed.syncWorld") {
		const _r: int32 = syncWorld(scene);
	} else if (name == "closed.collectDrawList") {
		const _r: int32 = collectDrawList(scene, items);
	} else if (name == "closed.refresh") {
		const _r: int32 = refresh(scene, items);
	} else if (name == "closed.collectLights") {
		const _r: Result<int32, LightError> = collectLights(scene, lights);
	} else if (name == "closed.closeScene") {
		closeScene(scene);
	} else if (name == "closed.pickNearest") {
		const ray: Ray = { origin: vec3(0.0, 0.0, 5.0), direction: vec3(0.0, 0.0, -1.0) };
		const _r: Result<PickHit, PickError> = pickNearest(scene, ray);
	} else if (name == "closed.addCameraNode") {
		const _r: NodeId3D = addCameraNode(scene, root, Transform3D.identity(), cameraRequest());
	} else if (name == "closed.setCameraOf") {
		setCameraOf(scene, root, cameraRequest());
	} else if (name == "closed.setActiveCamera") {
		setActiveCamera(scene, null);
	} else if (name == "closed.cameraOf") {
		const _r: Result<Camera3D, CameraError> = cameraOf(scene, cameraRequest());
	} else if (name == "closed.attach") {
		attach(scene, root, root);
	} else if (name == "closed.insertBefore") {
		insertBefore(scene, root, root, root);
	} else if (name == "closed.addGroupDetached") {
		const _r: NodeId3D = addGroup(scene, null, Transform3D.identity());
	} else if (name == "closed.addMeshDetached") {
		const _r: Result<NodeId3D, SceneError> =
			addMeshNode(scene, null, Transform3D.identity(), NO_MESH, NO_MATERIAL);
	} else if (name == "closed.addLightDetached") {
		const _r: NodeId3D = addLightNode(scene, null, Transform3D.identity(), {
			kind: LightKind.Point, color: vec3(1.0, 1.0, 1.0),
			radius: 1.0, power: 1.0, priority: 0,
		});
	} else if (name == "closed.addCameraDetached") {
		const _r: NodeId3D = addCameraNode(scene, null, Transform3D.identity(), cameraRequest());
	} else {
		return false;
	}
	return true;
}

function contextClosedCase(name: string): boolean {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	let scene: Scene3D = Scene3D.create(context);
	if (name == "contextClosed.addMeshNode") {
		closeContext(context);
		const _r: Result<NodeId3D, SceneError> =
			addMeshNode(scene, scene.rootId(), Transform3D.identity(), NO_MESH, NO_MATERIAL);
	} else if (name == "contextClosed.setMeshOf") {
		const mesh: MeshId = meshOf(context);
		const material: MaterialId = materialOf(context);
		const node: NodeId3D = meshNode(scene, scene.rootId(), mesh, material);
		const _meshPin: Result<int32, HandleError> = unpinMesh(context, mesh);
		const _materialPin: Result<int32, HandleError> = unpinMaterial(context, material);
		const _meshHold: Result<int32, HandleError> = releaseMesh(context, mesh);
		const _materialHold: Result<int32, HandleError> = releaseMaterial(context, material);
		closeContext(context);
		const _r: Result<int32, SceneError> = setMeshOf(scene, node, NO_MESH);
	} else {
		return false;
	}
	return true;
}

function pinTakenCase(name: string): boolean {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	let scene: Scene3D = Scene3D.create(context);
	const mesh: MeshId = meshOf(context);
	const material: MaterialId = materialOf(context);
	const group: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
	const node: NodeId3D = meshNode(scene, group, mesh, material);
	const _taken: Result<int32, HandleError> = unpinMesh(context, mesh);
	if (name == "pin.remove") {
		const _r: int32 = remove(scene, group);
	} else if (name == "pin.removeChildren") {
		const _r: int32 = removeChildren(scene, group);
	} else if (name == "pin.closeScene") {
		closeScene(scene);
	} else if (name == "pin.setMeshOf") {
		const _r: Result<int32, SceneError> = setMeshOf(scene, node, meshOf(context));
	} else {
		return false;
	}
	return true;
}

function cameraMisuse(name: string): boolean {
	const setPose: boolean = name == "camera.foreign.setCameraOf" ||
		name == "camera.unbound.setCameraOf" || name == "camera.stale.setCameraOf";
	const setActive: boolean = name == "camera.foreign.setActiveCamera" ||
		name == "camera.unbound.setActiveCamera" || name == "camera.stale.setActiveCamera";
	if (!setPose && !setActive) { return false; }
	const context: DrawContext = DrawContext.withUniformCapacity(0);
	const scene: Scene3D = Scene3D.create(context);
	let node: NodeId3D = scene.rootId();
	if (name == "camera.foreign.setCameraOf" || name == "camera.foreign.setActiveCamera") {
		const other: Scene3D = Scene3D.create(context);
		node = other.rootId();
	} else if (name == "camera.stale.setCameraOf" || name == "camera.stale.setActiveCamera") {
		node = addCameraNode(scene, scene.rootId(), Transform3D.identity(), cameraRequest());
		const _removed: int32 = remove(scene, node);
	}
	if (setPose) { setCameraOf(scene, node, cameraRequest()); }
	else { setActiveCamera(scene, node); }
	return true;
}

function moveMisuse(name: string): boolean {
	if (!name.startsWith("move.")) { return false; }
	const context: DrawContext = DrawContext.withUniformCapacity(0);
	const scene: Scene3D = Scene3D.create(context);
	const a: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
	const b: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
	const node: NodeId3D = addGroup(scene, a, Transform3D.identity());
	const before: NodeId3D = addGroup(scene, b, Transform3D.identity());
	if (name == "move.self.attach") {
		attach(scene, node, node);
	} else if (name == "move.descendant.attach") {
		attach(scene, node, a);
	} else if (name == "move.root.attach") {
		attach(scene, a, scene.rootId());
	} else if (name == "move.stale.attach") {
		const _removed: int32 = remove(scene, node);
		attach(scene, b, node);
	} else if (name == "move.self.insertBefore") {
		insertBefore(scene, node, node, before);
	} else if (name == "move.descendant.insertBefore") {
		insertBefore(scene, node, a, before);
	} else if (name == "move.root.insertBefore") {
		insertBefore(scene, b, scene.rootId(), before);
	} else if (name == "move.stale.insertBefore") {
		const _removed: int32 = remove(scene, node);
		insertBefore(scene, b, node, before);
	} else if (name == "move.staleBefore.insertBefore") {
		const _removed: int32 = remove(scene, before);
		insertBefore(scene, b, node, before);
	} else if (name == "move.wrongBefore.insertBefore") {
		insertBefore(scene, b, node, a);
	} else {
		const other: Scene3D = Scene3D.create(context);
		const foreign: NodeId3D = addGroup(other, other.rootId(), Transform3D.identity());
		if (name == "move.foreign.attach") { attach(scene, b, foreign); }
		else if (name == "move.foreignParent.attach") { attach(scene, other.rootId(), node); }
		else if (name == "move.foreign.insertBefore") { insertBefore(scene, b, foreign, before); }
		else if (name == "move.foreignParent.insertBefore") {
			insertBefore(scene, other.rootId(), node, before);
		} else if (name == "move.foreignBefore.insertBefore") {
			insertBefore(scene, b, node, other.rootId());
		} else { return false; }
	}
	return true;
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

function animationClosedCase(name: string): boolean {
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

function animationPinCase(name: string): boolean {
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

function document(): GltfData {
	let bytes: Vec<uint8> = [];
	const loaded: Result<GltfData, GltfError> = loadGltf(DOCUMENT, bytes);
	if (!loaded.ok) { unreachable; }
	return loaded.value;
}

function gltfCase(name: string): boolean {
	if (name != "closedScene.addGltfNodes" && name != "closedContext.addGltfNodes") {
		return false;
	}
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	let scene: Scene3D = Scene3D.create(context);
	const root: NodeId3D = scene.rootId();
	let bindings: Vec<GltfMeshBinding> = [];
	if (name == "closedScene.addGltfNodes") {
		closeScene(scene);
	} else {
		closeContext(context);
	}
	const _r: Result<int32, GltfSceneError> = addGltfNodes(scene, root, document(), bindings);
	return true;
}

function lightColorCase(name: string): boolean {
	if (!name.startsWith("lightColor.")) { return false; }
	const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
	let id = addLightNode(scene, scene.rootId(), Transform3D.identity(), {
		kind: LightKind.Point, color: vec3(1, 1, 1), radius: 9, power: 2, priority: 0,
	});
	if (name == "lightColor.closed") {
		closeScene(scene);
	} else if (name == "lightColor.stale") {
		const _removed: int32 = remove(scene, id);
	} else if (name == "lightColor.group") {
		id = scene.rootId();
	} else if (name == "lightColor.foreign") {
		const other = Scene3D.create(scene.context);
		id = other.rootId();
	} else {
		return false;
	}
	setLightColor(scene, id, vec3(0.5, 0.25, 1));
	return true;
}

function staleCase(name: string): boolean {
	if (!name.startsWith("stale.")) { return false; }
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	let scene: Scene3D = Scene3D.create(context);
	const gone: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
	const _removed: int32 = remove(scene, gone);
	const unbound: MeshId = { store: 0, index: 0, generation: 1 };
	const noMaterial: MaterialId = { store: 0, index: 0, generation: 1 };
	if (name == "stale.addGroup") {
		const _r: NodeId3D = addGroup(scene, gone, Transform3D.identity());
	} else if (name == "stale.addGltfNodes") {
		let bindings: Vec<GltfMeshBinding> = [];
		const _r: Result<int32, GltfSceneError> = addGltfNodes(scene, gone, document(), bindings);
	} else if (name == "stale.addLightNode") {
		const _r: NodeId3D = addLightNode(scene, gone, Transform3D.identity(), {
			kind: LightKind.Point, color: vec3(1.0, 1.0, 1.0),
			radius: 1.0, power: 1.0, priority: 0,
		});
	} else if (name == "stale.addMeshNode") {
		const _r: Result<NodeId3D, SceneError> =
			addMeshNode(scene, gone, Transform3D.identity(), unbound, noMaterial);
	} else if (name == "stale.removeChildren") {
		const _r: int32 = removeChildren(scene, gone);
	} else if (name == "stale.remove") {
		const _r: int32 = remove(scene, gone);
	} else if (name == "stale.setLightPower") {
		setLightPower(scene, gone, 1.0);
	} else if (name == "stale.setMeshOf") {
		const _r: Result<int32, SceneError> = setMeshOf(scene, gone, unbound);
	} else if (name == "stale.setName") {
		setName(scene, gone, "x");
	} else if (name == "stale.setPickable") {
		setPickable(scene, gone, true);
	} else if (name == "stale.setVisible") {
		setVisible(scene, gone, false);
	} else if (name == "stale.setLocal") {
		setLocal(scene, gone, Transform3D.identity());
	} else {
		return false;
	}
	return true;
}

function nodeMisuse(name: string): boolean {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	let scene: Scene3D = Scene3D.create(context);
	if (name == "group.setLightPower") {
		const group: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
		setLightPower(scene, group, 1.0);
	} else if (name == "group.setMeshOf") {
		const group: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
		const _r: Result<int32, SceneError> =
			setMeshOf(scene, group, { store: 0, index: 0, generation: 1 });
	} else if (name == "foreign.remove") {
		let second: Scene3D = Scene3D.create(context);
		const theirs: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
		const _ours: NodeId3D = addGroup(second, second.rootId(), Transform3D.identity());
		const _r: int32 = remove(second, theirs);
	} else if (name == "root.remove") {
		const _r: int32 = remove(scene, scene.rootId());
	} else if (name == "unset.setLocal") {
		setLocal(scene, NO_NODE_ID, Transform3D.identity());
	} else if (name == "contextClosed.sceneCreate") {
		let alias: DrawContext = context;
		closeContext(context);
		const _scene: Scene3D = Scene3D.create(alias);
	} else if (name == "closedTwice.closeGltfAssets") {
		let assets: GltfAssets = {
			context: context,
			bindings: [],
			meshes: [],
			materials: [],
			textures: [],
			closed: false,
		};
		let alias: GltfAssets = assets;
		closeGltfAssets(assets);
		closeGltfAssets(alias);
	} else {
		return false;
	}
	return true;
}

function animationMisuse(name: string): boolean {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	if (name == "closedTwice.closeMeshFrames") {
		let animation: MeshFrameAnimation = framesOf(context);
		let alias: MeshFrameAnimation = animation;
		closeMeshFrames(animation);
		closeMeshFrames(alias);
	} else if (name == "otherContext.bindMeshFrames") {
		let other: DrawContext = DrawContext.withUniformCapacity(0);
		let scene: Scene3D = Scene3D.create(other);
		const _r: Result<int32, AnimationError> =
			bindMeshFrames(framesOf(context), scene, scene.rootId());
	} else if (name == "closedScene.syncMeshFrame") {
		let scene: Scene3D = Scene3D.create(context);
		const frames: MeshFrameAnimation = framesOf(context);
		closeScene(scene);
		const _r: Result<int32, AnimationError> = syncMeshFrame(frames, scene);
	} else {
		return false;
	}
	return true;
}

function run(name: string): void {
	const known: boolean =
		moveMisuse(name) || cameraMisuse(name) || closedCase(name) ||
		contextClosedCase(name) || pinTakenCase(name) || animationClosedCase(name) ||
		otherSceneCase(name) || animationPinCase(name) || gltfCase(name) ||
		lightColorCase(name) || staleCase(name) || nodeMisuse(name) ||
		animationMisuse(name);
	if (!known) {
		console.log(`no case named '${name}'`);
		process.exit(2);
	}
	console.log(`${name} returned`);
}

run((argv.length as int32) > 1 ? argv[1] : "");
