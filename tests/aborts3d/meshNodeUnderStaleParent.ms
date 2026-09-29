// expect: void3d: addMeshNode on stale node 1: the handle has generation 1, the row 2
import { DrawContext, MeshId, MaterialId } from "../../src/void3d/draw";
import {
	Scene3D,
	NodeId3D,
	SceneError,
	Transform3D,
	addGroup,
	remove,
	addMeshNode,
} from "../../src/void3d/scene";

let context: DrawContext = DrawContext.withUniformCapacity(0);
let scene: Scene3D = Scene3D.create();
const gone: NodeId3D = addGroup(scene, scene.rootId(), Transform3D.identity());
const _removed: Result<int32, SceneError> = remove(scene, context, gone);
const mesh: MeshId = { index: 0, generation: 1 };
const material: MaterialId = { index: 0, generation: 1 };
const _orphan: Result<NodeId3D, SceneError> =
	addMeshNode(scene, context, gone, Transform3D.identity(), mesh, material);
console.log("the call returned");
