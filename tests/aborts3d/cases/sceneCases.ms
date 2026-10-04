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
	addGroup,
	addMeshNode,
	addLightNode,
	addCameraNode,
	setCameraOf,
	setActiveCamera,
	cameraOf,
	remove,
	removeChildren,
	setLocal,
	setVisible,
	setPickable,
	setMeshOf,
	setLightPower,
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

function run(name: string): void {
	const known: boolean =
		cameraMisuse(name) || closedCase(name) || contextClosedCase(name) || pinTakenCase(name);
	console.log(known ? `${name} returned` : `no case named '${name}'`);
}

run((argv.length as int32) > 1 ? argv[1] : "");
