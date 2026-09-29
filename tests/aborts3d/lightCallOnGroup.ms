// expect: void3d: setLightPower asked of a Group node 1; only a Light node has it
import {
	Scene3D,
	NodeId3D,
	Transform3D,
	addGroup,
	setLightPower,
} from "../../src/void3d/scene";

let scene: Scene3D = Scene3D.create();
const group: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
setLightPower(scene, group, 1.0);
console.log("the call returned");
