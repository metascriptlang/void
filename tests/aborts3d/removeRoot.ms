// expect: void3d: remove asked of the scene root; removeChildren empties it
import { DrawContext } from "../../src/void3d/draw";
import {
	Scene3D,
	SceneError,
	remove,
} from "../../src/void3d/scene";

let context: DrawContext = DrawContext.withUniformCapacity(0);
let scene: Scene3D = Scene3D.create();
const _removed: Result<int32, SceneError> = remove(scene, context, scene.rootId());
console.log("the call returned");
