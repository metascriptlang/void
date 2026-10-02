// expect: void3d: closeMeshFrames on mesh frames that were closed
import { DrawContext, GpuMesh, MeshId, MeshUploadError, addMesh } from "../../src/void3d/draw";
import {
	AnimationClock,
	AnimationError,
	Interpolation,
	MeshFrameAnimation,
	closeMeshFrames,
} from "../../src/void3d/animation";

let context: DrawContext = DrawContext.withUniformCapacity(0);
const mesh: Result<MeshId, MeshUploadError> = addMesh(context, GpuMesh.fullscreen(0, 3));
const clock: Result<AnimationClock, AnimationError> =
	AnimationClock.forFrames(1, 12.0, Interpolation.Step);
if (!mesh.ok || !clock.ok) { unreachable; }
const frames: Vec<MeshId> = [mesh.value];
const animated: Result<MeshFrameAnimation, AnimationError> =
	MeshFrameAnimation.forMeshes(context, clock.value, "pet", frames);
if (!animated.ok) { unreachable; }
let animation: MeshFrameAnimation = animated.value;
let alias: MeshFrameAnimation = animation;
closeMeshFrames(animation);
closeMeshFrames(alias);
console.log("mesh frames closed twice returned");
