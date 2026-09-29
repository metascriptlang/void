// expect: void3d: setLocal on node id -1, which names no node of this scene
import {
	Scene3D,
	Transform3D,
	NO_NODE_3D,
	setLocal,
} from "../../src/void3d/scene";

let scene: Scene3D = Scene3D.create();
setLocal(scene, { index: NO_NODE_3D, generation: 0 }, Transform3D.identity());
console.log("the call returned");
