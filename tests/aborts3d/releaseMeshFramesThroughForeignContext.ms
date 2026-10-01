// expect: void3d: releaseMeshFrames through a context that did not issue its frames
import { DrawContext, GpuMesh, MeshId, MeshUploadError, addMesh } from "../../src/void3d/draw";
import {
	AnimationClock,
	AnimationError,
	Interpolation,
	MeshFrameAnimation,
	releaseMeshFrames,
} from "../../src/void3d/animation";

let made: DrawContext = DrawContext.withUniformCapacity(0);
let other: DrawContext = DrawContext.withUniformCapacity(0);
const mesh: Result<MeshId, MeshUploadError> = addMesh(made, GpuMesh.fullscreen(0, 3));
const clock: Result<AnimationClock, AnimationError> =
	AnimationClock.forFrames(1, 12.0, Interpolation.Step);
if (!mesh.ok || !clock.ok) { unreachable; }
const frames: Vec<MeshId> = [mesh.value];
const animated: Result<MeshFrameAnimation, AnimationError> =
	MeshFrameAnimation.forMeshes(made, clock.value, "pet", frames);
if (!animated.ok) { unreachable; }
let animation: MeshFrameAnimation = animated.value;
const _released: Result<int32, AnimationError> = releaseMeshFrames(animation, other);
console.log("the call returned");
