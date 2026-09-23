// h3d.anim, cut to what a scene of tens of retained nodes needs: a clock (Animation), object
// keyframes that write a node's local transform (LinearAnimation), and vertex-baked frames that
// swap which uploaded mesh a node draws. docs/VOID3D.md "M9 as built" lists what is not ported.
import { vec3 } from "../math/math3d";
import { MeshData } from "./meshData";
import { DrawContext, addMeshData, MeshUploadError } from "./draw";
import {
	Scene, NodeId, NodeKind, Transform3D, SceneError, NO_NODE,
	setLocal, setMeshOf,
} from "./scene";

export enum Interpolation {
	Linear,
	Step,
}

export enum AnimationError {
	NoFrames,
	BadSampling,
	BadFrame,
	TrackLength,
	TargetNotFound,
	NotBound,
	StaleTarget,
	NotAMeshNode,
	InterpolatedMeshFrames,
	FrameTopology,
	UploadRefused,
}

// Animation's `frameCount`, `sampling` (frames per second), `speed`, `frame`, `loop`, `pause`.
// `frame` stays float64 as Heaps' Float is: a wallpaper clock runs for hours.
export struct AnimationClock {
	frameCount: int32;
	sampling: float64;
	speed: float64;
	frame: float64;
	loop: boolean;
	pause: boolean;
	interpolation: Interpolation;
}

// The two keys a pose blends and the weight of the second, the prelude of Heaps' `sync`.
export struct KeyPair {
	first: int32;
	second: int32;
	weight: float32;
}

export struct ObjectTrack {
	name: string;
	target: NodeId;
}

// LinearAnimation's per-object `frames`, stored track-major in one table:
// `keys[track * frameCount + frame]`.
export struct ObjectAnimation {
	clock: AnimationClock;
	tracks: Vec<ObjectTrack>;
	keys: Vec<Transform3D>;
	bound: boolean;
	synced: KeyPair;
	hasSynced: boolean;
}

export struct MeshFrameAnimation {
	clock: AnimationClock;
	name: string;
	target: NodeId;
	meshes: Vec<int32>;
	bound: boolean;
	shown: int32;
}

const UNBOUND: NodeId = { index: NO_NODE, generation: 0 };
const PLAYING_EPSILON: float64 = 0.000001;

function isFinite(x: float64): boolean { return x - x == 0.0; }

export function forFrames(
	this typeof AnimationClock,
	frameCount: int32,
	sampling: float64,
	interpolation: Interpolation,
): Result<AnimationClock, AnimationError> {
	if (frameCount < 1) { return Result.err(AnimationError.NoFrames); }
	if (!isFinite(sampling) || sampling <= 0.0) {
		return Result.err(AnimationError.BadSampling);
	}
	return Result.ok({
		frameCount: frameCount,
		sampling: sampling,
		speed: 1.0,
		frame: 0.0,
		loop: true,
		pause: false,
		interpolation: interpolation,
	});
}

export function isPlaying(this clock: AnimationClock): boolean {
	const magnitude: float64 = clock.speed < 0.0 ? -clock.speed : clock.speed;
	return !clock.pause && magnitude > PLAYING_EPSILON;
}

export function isFinished(this clock: AnimationClock): boolean {
	return !clock.loop && clock.frame >= (clock.frameCount as float64);
}

export function duration(this clock: AnimationClock): float64 {
	return (clock.frameCount as float64) / (clock.sampling * clock.speed);
}

export function samePair(this a: KeyPair, b: KeyPair): boolean {
	return a.first == b.first && a.second == b.second && a.weight == b.weight;
}

// Heaps' `getIFrame` plus the clamps that open `LinearAnimation.sync`, with one divergence: a
// non-looping clock past its last key holds it, where Heaps extrapolates the last interval
// (k2 in [1, 2)). PENDING3D: anim-holds-last-key
export function keys(this clock: AnimationClock): KeyPair {
	const count: int32 = clock.frameCount;
	const last: int32 = count - 1;
	const at: float64 = clock.interpolation == Interpolation.Step
		? Math.floor(clock.frame)
		: clock.frame;
	if (at <= 0.0) { return { first: 0, second: 0, weight: 0.0 }; }
	if (clock.loop) {
		if (at >= (count as float64)) { return { first: last, second: last, weight: 0.0 }; }
	} else if (at >= (last as float64)) {
		return { first: last, second: last, weight: 0.0 };
	}
	const first: int32 = at as int32;
	const weight: float32 = (at - (first as float64)) as float32;
	if (weight == 0.0) { return { first: first, second: first, weight: 0.0 }; }
	return { first: first, second: (first + 1) % count, weight: weight };
}

// Animation.update without events and `onAnimEnd`: a value clock has no callback to call. It
// answers whether the pose it samples moved, which is what a host on demand pacing needs.
export function update(ref clock: AnimationClock, dt: float64): boolean {
	if (!clock.isPlaying()) { return false; }
	const before: KeyPair = clock.keys();
	const count: float64 = clock.frameCount as float64;
	clock.frame = clock.frame + dt * clock.speed * clock.sampling;
	if (clock.frame >= count) {
		clock.frame = clock.loop ? clock.frame % count : count;
	}
	return !before.samePair(clock.keys());
}

// Animation.setFrame: wraps into [0, frameCount].
export function setFrame(
	ref clock: AnimationClock,
	frame: float64,
): Result<float64, AnimationError> {
	if (!isFinite(frame)) { return Result.err(AnimationError.BadFrame); }
	const count: float64 = clock.frameCount as float64;
	let wrapped: float64 = frame;
	if (wrapped < 0.0 || wrapped > count) {
		wrapped = wrapped % count;
		if (wrapped < 0.0) { wrapped = wrapped + count; }
	}
	clock.frame = wrapped;
	return Result.ok(wrapped);
}

// LinearAnimation.sync's blend: translation and scale as `f1 * k1 + f2 * k2`, rotation by
// nearest-hemisphere lerp then normalize.
export function blendPose(a: Transform3D, b: Transform3D, weight: float32): Transform3D {
	const keep: float32 = 1.0 - weight;
	return {
		position: vec3(
			a.position.x * keep + b.position.x * weight,
			a.position.y * keep + b.position.y * weight,
			a.position.z * keep + b.position.z * weight,
		),
		rotation: a.rotation.nlerp(b.rotation, weight),
		scale: vec3(
			a.scale.x * keep + b.scale.x * weight,
			a.scale.y * keep + b.scale.y * weight,
			a.scale.z * keep + b.scale.z * weight,
		),
	};
}

export function forClock(this typeof ObjectAnimation, clock: AnimationClock): ObjectAnimation {
	return {
		clock: clock,
		tracks: [],
		keys: [],
		bound: false,
		synced: { first: 0, second: 0, weight: 0.0 },
		hasSynced: false,
	};
}

export function addTrack(
	ref animation: ObjectAnimation,
	name: string,
	keys: Span<Transform3D>,
): Result<int32, AnimationError> {
	if ((keys.length as int32) != animation.clock.frameCount) {
		return Result.err(AnimationError.TrackLength);
	}
	for (const key of keys) { animation.keys.push(key); }
	animation.tracks.push({ name: name, target: UNBOUND });
	animation.bound = false;
	return Result.ok((animation.tracks.length as int32) - 1);
}

// Animation.bind: each track's object by name under `base`. Heaps drops a track whose object is
// missing and plays the rest; this refuses, because a pose missing a part is a wrong pose.
// PENDING3D: anim-missing-target-refused
export function bindTracks(
	ref animation: ObjectAnimation,
	scene: Scene,
	base: NodeId,
): Result<int32, AnimationError> {
	if (!scene.isLive(base)) { return Result.err(AnimationError.StaleTarget); }
	const count: int32 = animation.tracks.length as int32;
	for (let i = 0; i < count; i++) {
		const found: Result<NodeId, SceneError> = scene.findByName(base, animation.tracks[i].name);
		if (!found.ok) { return Result.err(AnimationError.TargetNotFound); }
		animation.tracks[i].target = found.value;
	}
	animation.bound = true;
	animation.hasSynced = false;
	return Result.ok(count);
}

// LinearAnimation.sync. Heaps writes the pose into `defaultTransform`, which `calcAbsPos`
// prepends to the object's own x/y/z; here it replaces the node's local transform, as a glTF
// channel does. PENDING3D: anim-pose-replaces-local
// Returns how many nodes were written: zero when the sampled keys have not moved.
export function syncPose(
	ref animation: ObjectAnimation,
	ref scene: Scene,
): Result<int32, AnimationError> {
	if (!animation.bound) { return Result.err(AnimationError.NotBound); }
	const pair: KeyPair = animation.clock.keys();
	if (animation.hasSynced && pair.samePair(animation.synced)) { return Result.ok(0); }
	const frames: int32 = animation.clock.frameCount;
	const count: int32 = animation.tracks.length as int32;
	for (let track = 0; track < count; track++) {
		const base: int32 = track * frames;
		const pose: Transform3D = blendPose(
			animation.keys[base + pair.first],
			animation.keys[base + pair.second],
			pair.weight,
		);
		const written: Result<int32, SceneError> =
			setLocal(scene, animation.tracks[track].target, pose);
		if (!written.ok) { return Result.err(AnimationError.StaleTarget); }
	}
	animation.synced = pair;
	animation.hasSynced = true;
	return Result.ok(count);
}

// Vertex-baked frames only step: blending two of them would mean writing vertices into a live
// buffer every frame, and each frame is instead its own uploaded mesh.
export function forMeshes(
	this typeof MeshFrameAnimation,
	clock: AnimationClock,
	name: string,
	meshes: Span<int32>,
): Result<MeshFrameAnimation, AnimationError> {
	if (clock.interpolation != Interpolation.Step) {
		return Result.err(AnimationError.InterpolatedMeshFrames);
	}
	if ((meshes.length as int32) != clock.frameCount) {
		return Result.err(AnimationError.TrackLength);
	}
	const kept: Vec<int32> = [];
	for (const mesh of meshes) { kept.push(mesh); }
	return Result.ok({
		clock: clock,
		name: name,
		target: UNBOUND,
		meshes: kept,
		bound: false,
		shown: NO_NODE,
	});
}

export function bindMeshFrames(
	ref animation: MeshFrameAnimation,
	scene: Scene,
	base: NodeId,
): Result<int32, AnimationError> {
	if (!scene.isLive(base)) { return Result.err(AnimationError.StaleTarget); }
	const found: Result<NodeId, SceneError> = scene.findByName(base, animation.name);
	if (!found.ok) { return Result.err(AnimationError.TargetNotFound); }
	if (scene.nodes[found.value.index].kind != NodeKind.Mesh) {
		return Result.err(AnimationError.NotAMeshNode);
	}
	animation.target = found.value;
	animation.bound = true;
	animation.shown = NO_NODE;
	return Result.ok(found.value.index);
}

// Returns 1 when the node was given a new mesh, 0 when the frame it shows is still current.
export function syncMeshFrame(
	ref animation: MeshFrameAnimation,
	ref scene: Scene,
): Result<int32, AnimationError> {
	if (!animation.bound) { return Result.err(AnimationError.NotBound); }
	const mesh: int32 = animation.meshes[animation.clock.keys().first];
	if (mesh == animation.shown) { return Result.ok(0); }
	const swapped: Result<int32, SceneError> = setMeshOf(scene, animation.target, mesh);
	if (!swapped.ok) { return Result.err(AnimationError.StaleTarget); }
	animation.shown = mesh;
	return Result.ok(1);
}

// Baked frames of one mesh share its topology: every frame has frame 0's vertex count and
// exactly its indices, so a frame swap moves vertices and never changes which triangles exist.
export function checkBakedFrames(frames: Span<MeshData>): Result<int32, AnimationError> {
	const count: int32 = frames.length as int32;
	if (count < 1) { return Result.err(AnimationError.NoFrames); }
	const vertices: int32 = frames[0].vertexCount();
	const indices: int32 = frames[0].indexCount();
	if (vertices == 0) { return Result.err(AnimationError.FrameTopology); }
	for (let f = 1; f < count; f++) {
		if (frames[f].vertexCount() != vertices || frames[f].indexCount() != indices) {
			return Result.err(AnimationError.FrameTopology);
		}
		for (let i = 0; i < indices; i++) {
			if (frames[f].indices[i] != frames[0].indices[i]) {
				return Result.err(AnimationError.FrameTopology);
			}
		}
	}
	return Result.ok(count);
}

// Uploads every frame through the M5 path, so each one is rebuilt after a context loss like
// any other mesh. Returns the first mesh index; the frames occupy the indices after it.
export function addBakedFrames(
	ref context: DrawContext,
	frames: Span<MeshData>,
): Result<int32, AnimationError> {
	const count: int32 = try checkBakedFrames(frames);
	const first: int32 = context.meshes.length as int32;
	for (let f = 0; f < count; f++) {
		const added: Result<int32, MeshUploadError> = addMeshData(context, frames[f]);
		if (!added.ok) { return Result.err(AnimationError.UploadRefused); }
	}
	return Result.ok(first);
}
