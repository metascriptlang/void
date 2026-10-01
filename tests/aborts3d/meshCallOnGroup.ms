// expect: void3d: setMeshOf asked of a Group node 1; only a Mesh node has it
import { DrawContext } from "../../src/void3d/draw";
import {
	Scene3D,
	NodeId3D,
	SceneError,
	Transform3D,
	addGroup,
	setMeshOf,
} from "../../src/void3d/scene";

let context: DrawContext = DrawContext.withUniformCapacity(0);
let scene: Scene3D = Scene3D.create();
const group: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
const _set: Result<int32, SceneError> =
	setMeshOf(scene, context, group, { store: 0, index: 0, generation: 1 });
console.log("the call returned");
