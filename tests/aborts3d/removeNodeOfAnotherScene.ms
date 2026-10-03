// expect: void3d: remove on node 1 of another scene
import { DrawContext } from "../../src/void3d/draw";
import {
	Scene3D,
	NodeId3D,
	Transform3D,
	addGroup,
	remove,
} from "../../src/void3d/scene";

let context: DrawContext = DrawContext.withUniformCapacity(0);
let first: Scene3D = Scene3D.create(context);
let second: Scene3D = Scene3D.create(context);
const theirs: NodeId3D = addGroup(first, first.rootId(), Transform3D.identity());
const _ours: NodeId3D = addGroup(second, second.rootId(), Transform3D.identity());
const _removed: int32 = remove(second, theirs);
console.log("the call returned");
