// expect: void3d: remove asked of the scene root; removeChildren empties it
import { DrawContext } from "../../src/void3d/draw";
import {
	Scene3D,
	remove,
} from "../../src/void3d/scene";

let context: DrawContext = DrawContext.withUniformCapacity(0);
let scene: Scene3D = Scene3D.create(context);
const _removed: int32 = remove(scene, scene.rootId());
console.log("the call returned");
