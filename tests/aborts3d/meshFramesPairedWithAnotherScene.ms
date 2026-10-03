// expect: void3d: bindMeshFrames pairs mesh frames with a scene of another context
import { DrawContext, GpuMesh, MeshId, MeshUploadError, addMesh } from "../../src/void3d/draw";
import { Scene3D } from "../../src/void3d/scene";
import {
	AnimationClock,
	AnimationError,
	Interpolation,
	MeshFrameAnimation,
	bindMeshFrames,
} from "../../src/void3d/animation";

let made: DrawContext = DrawContext.withUniformCapacity(0);
let other: DrawContext = DrawContext.withUniformCapacity(0);
const mesh: Result<MeshId, MeshUploadError> = addMesh(made, GpuMesh.fullscreen(0, 3));
const clock: Result<AnimationClock, AnimationError> =
	AnimationClock.forFrames(1, 12.0, Interpolation.Step);
if (!mesh.ok || !clock.ok) { unreachable; }
const frames: Vec<MeshId> = [mesh.value];
const animated: Result<MeshFrameAnimation, AnimationError> =
	MeshFrameAnimation.forMeshes(made, clock.value, "frames", frames);
if (!animated.ok) { unreachable; }
let scene: Scene3D = Scene3D.create(other);
const _bound: Result<int32, AnimationError> =
	bindMeshFrames(animated.value, scene, scene.rootId());
console.log("the call returned");
