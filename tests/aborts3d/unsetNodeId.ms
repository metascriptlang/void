// expect: void3d: setLocal on node id -1, which names no node of this scene
import { DrawContext } from "../../src/void3d/draw";
import {
	Scene3D,
	Transform3D,
	NO_NODE_3D,
	setLocal,
	NO_NODE_ID,
} from "../../src/void3d/scene";

let scene: Scene3D = Scene3D.create(DrawContext.withUniformCapacity(0));
setLocal(scene, NO_NODE_ID, Transform3D.identity());
console.log("the call returned");
