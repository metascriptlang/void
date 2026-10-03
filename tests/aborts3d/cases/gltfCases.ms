// expect closedScene.addGltfNodes: void3d: addGltfNodes on a scene that was closed
// expect closedContext.addGltfNodes: void3d: addGltfNodes on a draw context that was closed
import { argv } from "std/process";
import { DrawContext, closeContext } from "../../../src/void3d/draw";
import { GltfData, GltfError, loadGltf } from "../../../src/void3d/gltf";
import { GltfMeshBinding, GltfSceneError, addGltfNodes } from "../../../src/void3d/gltfScene";
import { Scene3D, NodeId3D, closeScene } from "../../../src/void3d/scene";

const DOCUMENT: string = "{\"asset\":{\"version\":\"2.0\"},\"scenes\":[{\"nodes\":[0]}],"
	+ "\"nodes\":[{\"name\":\"only\"}],\"meshes\":[],\"accessors\":[],"
	+ "\"bufferViews\":[],\"buffers\":[]}";

function document(): GltfData {
	let bytes: Vec<uint8> = [];
	const loaded: Result<GltfData, GltfError> = loadGltf(DOCUMENT, bytes);
	if (!loaded.ok) { unreachable; }
	return loaded.value;
}

function run(name: string): void {
	let context: DrawContext = DrawContext.withUniformCapacity(0);
	let scene: Scene3D = Scene3D.create(context);
	const root: NodeId3D = scene.rootId();
	let bindings: Vec<GltfMeshBinding> = [];
	if (name == "closedScene.addGltfNodes") {
		closeScene(scene);
	} else if (name == "closedContext.addGltfNodes") {
		closeContext(context);
	} else {
		console.log(`no case named '${name}'`);
		return;
	}
	const _r: Result<int32, GltfSceneError> = addGltfNodes(scene, root, document(), bindings);
	console.log(`${name} returned`);
}

run((argv.length as int32) > 1 ? argv[1] : "");
