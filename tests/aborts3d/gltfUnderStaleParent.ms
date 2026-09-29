// expect: void3d: addGltfNodes on stale node 1: the handle has generation 1, the row 2
import { DrawContext } from "../../src/void3d/draw";
import { GltfData, GltfError, loadGltf } from "../../src/void3d/gltf";
import { GltfMeshBinding, GltfSceneError, addGltfNodes } from "../../src/void3d/gltfScene";
import {
	Scene3D,
	NodeId3D,
	SceneError,
	Transform3D,
	addGroup,
	remove,
} from "../../src/void3d/scene";

const DOCUMENT: string = "{\"asset\":{\"version\":\"2.0\"},\"scenes\":[{\"nodes\":[0]}],"
	+ "\"nodes\":[{\"name\":\"only\"}],\"meshes\":[],\"accessors\":[],"
	+ "\"bufferViews\":[],\"buffers\":[]}";

let context: DrawContext = DrawContext.withUniformCapacity(0);
let scene: Scene3D = Scene3D.create();
const gone: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
const _removed: Result<int32, SceneError> = remove(scene, context, gone);
let bytes: Vec<uint8> = [];
const loaded: Result<GltfData, GltfError> = loadGltf(DOCUMENT, bytes);
let bindings: Vec<GltfMeshBinding> = [];
if (loaded.ok) {
	const _added: Result<int32, GltfSceneError> =
		addGltfNodes(scene, context, gone, loaded.value, bindings);
}
console.log("the call returned");
