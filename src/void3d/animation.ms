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
	BadMesh,
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
// `frame` stays float64 as Heaps' Float is: a clock may run for hours.
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
const NO_MESH: int32 = -1;
const PLAYING_EPSILON: float64 = 0.000001;
const HOLD_FIRST: KeyPair = { first: 0, second: 0, weight: 0.0 };

export function forFrames(
	this typeof AnimationClock,
	frameCount: int32,
	sampling: float64,
	interpolation: Interpolation,
): Result<AnimationClock, AnimationError> {
	if (frameCount < 1) { return Result.err(AnimationError.NoFrames); }
	if (!Number.isFinite(sampling) || sampling <= 0.0) {
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

// Heaps' `getIFrame` plus the clamps that open `LinearAnimation.sync`, except that this never
// extrapolates: Heaps' weight leaves [0, 1] inside a one-shot's last interval and below frame 0.
// PENDING3D: anim-never-extrapolates
export function keys(this clock: AnimationClock): KeyPair {
	const count: int32 = clock.frameCount;
	if (count <= 1) { return HOLD_FIRST; }
	const last: int32 = count - 1;
	const at: float64 = clock.interpolation == Interpolation.Step
		? Math.floor(clock.frame)
		: clock.frame;
	if (at <= 0.0) { return HOLD_FIRST; }
	if (clock.loop) {
		if (at >= (count as float64)) { return HOLD_FIRST; }
	} else if (at >= (last as float64)) {
		return { first: last, second: last, weight: 0.0 };
	}
	const first: int32 = at as int32;
	const weight: float32 = (at - (first as float64)) as float32;
	if (weight == 0.0) { return { first: first, second: first, weight: 0.0 }; }
	return { first: first, second: (first + 1) % count, weight: weight };
}

// Animation.update without events and `onAnimEnd`: a value clock has no callback to call. It
// answers whether the sampled keys moved, which is what a host on demand pacing needs.
export function update(ref clock: AnimationClock, dt: float64): Result<boolean, AnimationError> {
	if (!clock.isPlaying()) { return Result.ok(false); }
	const count: float64 = clock.frameCount as float64;
	let next: float64 = clock.frame + dt * clock.speed * clock.sampling;
	if (!Number.isFinite(next)) { return Result.err(AnimationError.BadFrame); }
	if (next >= count) {
		next = clock.loop ? next % count : count;
	}
	const before: KeyPair = clock.keys();
	clock.frame = next;
	return Result.ok(!before.samePair(clock.keys()));
}

// Animation.setFrame's two `while` loops, taken in one step: the result lies in [0, frameCount],
// and a positive exact multiple lands on frameCount itself, as the loops do.
export function setFrame(
	ref clock: AnimationClock,
	frame: float64,
): Result<float64, AnimationError> {
	if (!Number.isFinite(frame)) { return Result.err(AnimationError.BadFrame); }
	const count: float64 = clock.frameCount as float64;
	let wrapped: float64 = frame;
	if (wrapped > count) {
		wrapped = wrapped % count;
		if (wrapped == 0.0) { wrapped = count; }
	} else if (wrapped < 0.0) {
		wrapped = wrapped % count;
		if (wrapped < 0.0) { wrapped = wrapped + count; }
	}
	clock.frame = wrapped;
	return Result.ok(wrapped);
}

// LinearAnimation.sync's blend: translation and scale as `f1 * k1 + f2 * k2`, rotation by
// nearest-hemisphere lerp then normalize.
export function blendTo(this a: Transform3D, b: Transform3D, weight: float32): Transform3D {
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
		synced: HOLD_FIRST,
		hasSynced: false,
	};
}

export function addTrack(
	ref animation: ObjectAnimation,
	name: string,
	keys: Span<Transform3D>,
): Result<int32, AnimationError> {
	if (animation.clock.frameCount < 1) { return Result.err(AnimationError.NoFrames); }
	if ((keys.length as int32) != animation.clock.frameCount) {
		return Result.err(AnimationError.TrackLength);
	}
	for (const key of keys) { animation.keys.push(key); }
	animation.tracks.push({ name: name, target: UNBOUND });
	animation.bound = false;
	return Result.ok((animation.tracks.length as int32) - 1);
}

// Animation.bind: each track's object by name under `base`. Heaps drops a track whose object is
// missing and plays the rest; this refuses and keeps the previous binding whole.
// PENDING3D: anim-missing-target-refused
export function bindTracks(
	ref animation: ObjectAnimation,
	scene: Scene,
	base: NodeId,
): Result<int32, AnimationError> {
	if (!scene.isLive(base)) { return Result.err(AnimationError.StaleTarget); }
	const count: int32 = animation.tracks.length as int32;
	const found: Vec<NodeId> = [];
	for (let i = 0; i < count; i++) {
		const named: Result<NodeId, SceneError> = scene.findByName(base, animation.tracks[i].name);
		if (!named.ok) { return Result.err(AnimationError.TargetNotFound); }
		found.push(named.value);
	}
	for (let i = 0; i < count; i++) { animation.tracks[i].target = found[i]; }
	animation.bound = true;
	animation.hasSynced = false;
	return Result.ok(count);
}

// After something other than this animation wrote one of its nodes, the next sync must write
// again even if the sampled keys have not moved.
export function forgetSync(ref animation: ObjectAnimation): void {
	animation.hasSynced = false;
}

// LinearAnimation.sync. The pose replaces the node's local transform, as a glTF channel does;
// Heaps prepends it through `defaultTransform`. PENDING3D: anim-pose-replaces-local
export function syncPose(
	ref animation: ObjectAnimation,
	ref scene: Scene,
): Result<int32, AnimationError> {
	if (!animation.bound) { return Result.err(AnimationError.NotBound); }
	if (animation.clock.frameCount < 1) { return Result.err(AnimationError.NoFrames); }
	const count: int32 = animation.tracks.length as int32;
	for (let track = 0; track < count; track++) {
		if (!scene.isLive(animation.tracks[track].target)) {
			return Result.err(AnimationError.StaleTarget);
		}
	}
	const pair: KeyPair = animation.clock.keys();
	if (animation.hasSynced && pair.samePair(animation.synced)) { return Result.ok(0); }
	const frames: int32 = animation.clock.frameCount;
	for (let track = 0; track < count; track++) {
		const base: int32 = track * frames;
		const pose: Transform3D = animation.keys[base + pair.first].blendTo(
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
	if (clock.frameCount < 1) { return Result.err(AnimationError.NoFrames); }
	if ((meshes.length as int32) != clock.frameCount) {
		return Result.err(AnimationError.TrackLength);
	}
	const kept: Vec<int32> = [];
	for (const mesh of meshes) {
		if (mesh < 0) { return Result.err(AnimationError.BadMesh); }
		kept.push(mesh);
	}
	return Result.ok({
		clock: clock,
		name: name,
		target: UNBOUND,
		meshes: kept,
		bound: false,
		shown: NO_MESH,
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
	animation.shown = NO_MESH;
	return Result.ok(found.value.index);
}

// Returns 1 when the node was given a new mesh, 0 when the frame it shows is still current.
export function syncMeshFrame(
	ref animation: MeshFrameAnimation,
	ref scene: Scene,
): Result<int32, AnimationError> {
	if (!animation.bound) { return Result.err(AnimationError.NotBound); }
	if ((animation.meshes.length as int32) < 1) { return Result.err(AnimationError.NoFrames); }
	if (!scene.isLive(animation.target)) { return Result.err(AnimationError.StaleTarget); }
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

// Every frame goes through `addMeshData`, so the frames always take the `frames.length` slots
// starting at the context's mesh count before the call, and a frame whose upload was refused
// keeps its CPU data for the next rebuild — the error says only that one did not draw yet.
export function addBakedFrames(
	ref context: DrawContext,
	frames: Span<MeshData>,
): Result<int32, AnimationError> {
	const count: int32 = try checkBakedFrames(frames);
	const first: int32 = context.meshes.length as int32;
	let refused: boolean = false;
	for (let f = 0; f < count; f++) {
		const added: Result<int32, MeshUploadError> = addMeshData(context, frames[f]);
		if (!added.ok) { refused = true; }
	}
	if (refused) { return Result.err(AnimationError.UploadRefused); }
	return Result.ok(first);
}
