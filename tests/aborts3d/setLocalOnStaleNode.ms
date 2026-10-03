// expect: void3d: setLocal on stale node 1: the handle has generation 1, the row 2
import { DrawContext } from "../../src/void3d/draw";
import {
	Scene3D,
	NodeId3D,
	Transform3D,
	addGroup,
	remove,
	setLocal,
} from "../../src/void3d/scene";

let context: DrawContext = DrawContext.withUniformCapacity(0);
let scene: Scene3D = Scene3D.create(context);
const gone: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
const _removed: int32 = remove(scene, gone);
setLocal(scene, gone, Transform3D.identity());
console.log("the call returned");
