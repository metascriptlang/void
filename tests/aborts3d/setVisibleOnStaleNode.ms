// expect: void3d: setVisible on stale node 1: the handle has generation 1, the row 2
import { DrawContext, MeshId, MaterialId } from "../../src/void3d/draw";
import {
	Scene3D,
	NodeId3D,
	SceneError,
	Transform3D,
	addGroup,
	remove,
	setVisible,
} from "../../src/void3d/scene";

let context: DrawContext = DrawContext.withUniformCapacity(0);
let scene: Scene3D = Scene3D.create();
const gone: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
const _removed: Result<int32, SceneError> = remove(scene, context, gone);
setVisible(scene, gone, false);
console.log("the call returned");
