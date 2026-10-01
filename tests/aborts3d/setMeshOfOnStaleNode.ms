// expect: void3d: setMeshOf on stale node 1: the handle has generation 1, the row 2
import { DrawContext } from "../../src/void3d/draw";
import {
	Scene3D,
	NodeId3D,
	SceneError,
	Transform3D,
	addGroup,
	remove,
	setMeshOf,
} from "../../src/void3d/scene";

let context: DrawContext = DrawContext.withUniformCapacity(0);
let scene: Scene3D = Scene3D.create();
const gone: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
const _removed: Result<int32, SceneError> = remove(scene, context, gone);
const _set: Result<int32, SceneError> =
	setMeshOf(scene, context, gone, { store: 0, index: 0, generation: 1 });
console.log("the call returned");
