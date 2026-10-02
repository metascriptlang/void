// expect: void3d: addGroup on a scene that was closed
import { DrawContext } from "../../src/void3d/draw";
import {
	Scene3D,
	NodeId3D,
	Transform3D,
	addGroup,
	closeScene,
} from "../../src/void3d/scene";

let context: DrawContext = DrawContext.withUniformCapacity(0);
let scene: Scene3D = Scene3D.create(context);
const root: NodeId3D = scene.rootId();
closeScene(scene);
const _group: NodeId3D = addGroup(scene, root, Transform3D.identity());
console.log("a closed scene took a group");
