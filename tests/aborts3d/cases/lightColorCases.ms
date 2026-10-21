// expect closed: void3d: setLightColor on a scene that was closed
// expect stale: void3d: setLightColor on stale node 1
// expect group: void3d: setLightColor asked of a Group node 0; only a Light node has it
// expect foreign: void3d: setLightColor on node 0 of another scene
import { argv } from "std/process";
import {
	Scene3D, Transform3D, LightKind, addLightNode, setLightColor, remove, closeScene,
} from "../../../src/void3d/scene";
import { DrawContext } from "../../../src/void3d/draw";
import { vec3 } from "../../../src/math/math3d";

const name = (argv.length as int32) > 1 ? argv[1] : "";
const scene = Scene3D.create(DrawContext.withUniformCapacity(0));
let id = addLightNode(scene, scene.rootId(), Transform3D.identity(), {
	kind: LightKind.Point, color: vec3(1, 1, 1), radius: 9, power: 2, priority: 0,
});
if (name == "closed") {
	closeScene(scene);
} else if (name == "stale") {
	const _removed: int32 = remove(scene, id);
} else if (name == "group") {
	id = scene.rootId();
} else if (name == "foreign") {
	const other = Scene3D.create(scene.context);
	id = other.rootId();
} else {
	console.log(`no light color case named '${name}'`);
	unreachable;
}
setLightColor(scene, id, vec3(0.5, 0.25, 1));
console.log("light color setter returned");
