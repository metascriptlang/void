// expect: void3d: syncMeshFrame on a scene that was closed
import { DrawContext, GpuMesh, MeshId, MeshUploadError, addMesh } from "../../src/void3d/draw";
import { Scene3D, closeScene } from "../../src/void3d/scene";
import {
	AnimationClock,
	AnimationError,
	Interpolation,
	MeshFrameAnimation,
	syncMeshFrame,
} from "../../src/void3d/animation";

let context: DrawContext = DrawContext.withUniformCapacity(0);
const mesh: Result<MeshId, MeshUploadError> = addMesh(context, GpuMesh.fullscreen(0, 3));
const clock: Result<AnimationClock, AnimationError> =
	AnimationClock.forFrames(1, 12.0, Interpolation.Step);
if (!mesh.ok || !clock.ok) { unreachable; }
const frames: Vec<MeshId> = [mesh.value];
const animated: Result<MeshFrameAnimation, AnimationError> =
	MeshFrameAnimation.forMeshes(context, clock.value, "frames", frames);
if (!animated.ok) { unreachable; }
let scene: Scene3D = Scene3D.create(context);
closeScene(scene);
const _synced: Result<int32, AnimationError> = syncMeshFrame(animated.value, scene);
console.log("the call returned");
