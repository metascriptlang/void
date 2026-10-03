// expect: void3d: addLightNode on stale node 1: the handle has generation 1, the row 2
import { DrawContext } from "../../src/void3d/draw";
import {
	Scene3D,
	NodeId3D,
	Transform3D,
	addGroup,
	remove,
	LightKind,
	addLightNode,
} from "../../src/void3d/scene";

let context: DrawContext = DrawContext.withUniformCapacity(0);
let scene: Scene3D = Scene3D.create(context);
const gone: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
const _removed: int32 = remove(scene, gone);
const _light: NodeId3D = addLightNode(scene, gone, Transform3D.identity(), {
	kind: LightKind.Point,
	color: { x: 1.0, y: 1.0, z: 1.0 },
	radius: 1.0,
	power: 1.0,
	priority: 0,
});
console.log("the call returned");
