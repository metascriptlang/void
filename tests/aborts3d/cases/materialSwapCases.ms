// expect closed: void3d: setMaterialOf on a scene that was closed
// expect stale: void3d: setMaterialOf on stale node 1
// expect group: void3d: setMaterialOf asked of a Group node 0; only a Mesh node has it
// expect foreign: void3d: setMaterialOf on node 0 of another scene
// expect contextClosed: void3d: setMaterialOf on a draw context that was closed
// expect pin: void3d: setMaterialOf found a node's pin taken through the context
import { argv } from "std/process";
import {
	Scene3D, SceneError, Transform3D,
	addMeshNode, setMaterialOf, remove, closeScene,
} from "../../../src/void3d/scene";
import {
	unpinMesh, unpinMaterial, releaseMesh, releaseMaterial, closeContext,
} from "../../../src/void3d/draw";
import { contextOf, meshAt, materialAt } from "../../../src/test/drawHelpers";

const name = (argv.length as int32) > 1 ? argv[1] : "";
const context = contextOf(1, 1);
const scene = Scene3D.create(context);
const mesh = context.meshAt(0);
const material = context.materialAt(0);
const made = addMeshNode(scene, scene.rootId(), Transform3D.identity(), mesh, material);
if (!made.ok) { unreachable; }
let id = made.value;
if (name == "closed") {
	closeScene(scene);
} else if (name == "stale") {
	const _removed: int32 = remove(scene, id);
} else if (name == "group") {
	id = scene.rootId();
} else if (name == "foreign") {
	const other = Scene3D.create(context);
	id = other.rootId();
} else if (name == "contextClosed") {
	const _meshPin = unpinMesh(context, mesh);
	const _materialPin = unpinMaterial(context, material);
	const _meshHold = releaseMesh(context, mesh);
	const _materialHold = releaseMaterial(context, material);
	closeContext(context);
} else if (name == "pin") {
	const _pin = unpinMaterial(context, material);
} else {
	console.log(`no material swap case named '${name}'`);
	unreachable;
}
const _changed: Result<int32, SceneError> = setMaterialOf(scene, id, material);
console.log("material swap returned");
