import { Vec4, vec3 } from "../math/math3d";
import { GltfCurvePath, GltfPoseTrack, sample } from "./gltfCurve";
export { GltfPoseTrack } from "./gltfCurve";
import { Scene3D, NodeId3D, Transform3D, isLive, setLocal } from "./scene";
import {
	AnimationRestTarget, AnimationChildSample, AnimationCompose, AnimationTrsSample,
	AnimationComponent, stageSmoothCompose, stageExclusiveCompose, checkedTargets, checkedRests,
} from "./animationCompose";

export enum GltfPoseError {
	Shape,
	Target,
	DuplicateTrack,
	Curve,
	Compose,
}

export interface GltfPose {
	readonly scene: Scene3D;
	nodes: Vec<NodeId3D>;
	readonly tracks: Vec<GltfPoseTrack>;
	pending: Vec<Transform3D>;
	touched: Vec<boolean>;
	trackTarget: Vec<int32>;
	boundSources: Vec<int32>;
	seeded: Vec<AnimationTrsSample>;
}

function duplicatesEarlier(tracks: Readonly<Span<GltfPoseTrack>>, index: int32): boolean {
	for (let previous = 0; previous < index; previous++) {
		if (tracks[previous].sourceNode == tracks[index].sourceNode &&
			tracks[previous].curve.path == tracks[index].curve.path) {
			return true;
		}
	}
	return false;
}

function animatedComponent(path: GltfCurvePath): AnimationComponent {
	return match (path) {
		GltfCurvePath.Translation => AnimationComponent.Translation,
		GltfCurvePath.Rotation => AnimationComponent.Rotation,
		GltfCurvePath.Scale => AnimationComponent.Scale,
	};
}

function withSample(this local: Transform3D, path: GltfCurvePath, value: Vec4): Transform3D {
	return match (path) {
		GltfCurvePath.Translation => ({ ...local, position: vec3(value.x, value.y, value.z) }),
		GltfCurvePath.Rotation => ({
			...local,
			rotation: { x: value.x, y: value.y, z: value.z, w: value.w },
		}),
		GltfCurvePath.Scale => ({ ...local, scale: vec3(value.x, value.y, value.z) }),
	};
}

function committed(this compose: Readonly<AnimationCompose>, pose: GltfPose): int32 {
	for (let i = 0; i < compose.targets.length; i++) {
		setLocal(pose.scene, pose.nodes[compose.targets[i].sourceNode], compose.output[i].value);
	}
	return compose.targets.length as int32;
}

function boundTrackTargets(
	this pose: GltfPose,
	targets: Readonly<Span<AnimationRestTarget>>,
): Result<void, GltfPoseError> {
	if (pose.trackTarget.length == pose.tracks.length &&
		pose.boundSources.length == targets.length) {
		let same = true;
		for (let i = 0; i < targets.length; i++) {
			if (pose.boundSources[i] != targets[i].sourceNode) { same = false; break; }
		}
		if (same) {
			if (!checkedRests(targets).ok) { return Result.err(GltfPoseError.Compose); }
			return Result.ok(null);
		}
	}
	pose.trackTarget = [];
	pose.boundSources = [];
	if (!checkedTargets(targets).ok) { return Result.err(GltfPoseError.Compose); }
	let resolved: Vec<int32> = [];
	for (let i = 0; i < pose.tracks.length; i++) {
		let found: int32 = -1;
		for (let target = 0; target < targets.length; target++) {
			if (targets[target].sourceNode == pose.tracks[i].sourceNode) {
				found = target as int32;
				break;
			}
		}
		if (found < 0) { return Result.err(GltfPoseError.Target); }
		resolved.push(found);
	}
	for (let i = 0; i < targets.length; i++) { pose.boundSources.push(targets[i].sourceNode); }
	pose.trackTarget = resolved;
	return Result.ok(null);
}

export function stageTrsChild(
	this pose: GltfPose,
	targets: Readonly<Span<AnimationRestTarget>>,
	seconds: float64,
): Result<AnimationChildSample, GltfPoseError> {
	if (!Number.isFinite(seconds)) { return Result.err(GltfPoseError.Curve); }
	if (targets.length > 0x7fffffff || pose.nodes.length > 0x7fffffff ||
		pose.tracks.length > 0x7fffffff ||
		pose.pending.length != pose.nodes.length || pose.touched.length != pose.nodes.length) {
		return Result.err(GltfPoseError.Shape);
	}
	if (pose.scene.closed) { return Result.err(GltfPoseError.Target); }
	for (const target of targets) {
		if (target.sourceNode < 0 || target.sourceNode >= pose.nodes.length ||
			!pose.scene.isLive(pose.nodes[target.sourceNode])) {
			return Result.err(GltfPoseError.Target);
		}
	}
	const bound = pose.boundTrackTargets(targets);
	if (!bound.ok) { return Result.err(bound.error); }
	for (let i = 0; i < targets.length; i++) {
		const seed: AnimationTrsSample = {
			sourceNode: targets[i].sourceNode,
			value: targets[i].rest,
			present: 0 as BitSet<AnimationComponent>,
		};
		if (i < pose.seeded.length) { pose.seeded[i] = seed; } else { pose.seeded.push(seed); }
	}
	while (pose.seeded.length > targets.length) { pose.seeded.pop(); }
	for (let i = 0; i < pose.tracks.length; i++) {
		const sampled = pose.tracks[i].curve.sample(seconds);
		if (!sampled.ok) { return Result.err(GltfPoseError.Curve); }
		const path = pose.tracks[i].curve.path;
		const index: int32 = pose.trackTarget[i];
		pose.seeded[index].value = pose.seeded[index].value.withSample(path, sampled.value);
		pose.seeded[index].present = pose.seeded[index].present.incl(animatedComponent(path));
	}
	let child: AnimationChildSample = { seconds: seconds, samples: [] };
	for (let i = 0; i < pose.seeded.length; i++) {
		if (pose.seeded[i].present != (0 as BitSet<AnimationComponent>)) {
			child.samples.push(pose.seeded[i]);
		}
	}
	return Result.ok(move child);
}

function checkedTrsOwners(
	this first: GltfPose,
	second: GltfPose,
	targets: Readonly<Span<AnimationRestTarget>>,
): Result<void, GltfPoseError> {
	if (first.scene.closed || second.scene.closed || first.scene.serial != second.scene.serial) {
		return Result.err(GltfPoseError.Target);
	}
	for (const target of targets) {
		const source: int32 = target.sourceNode;
		if (source < 0 || source >= first.nodes.length || source >= second.nodes.length) {
			return Result.err(GltfPoseError.Target);
		}
		const firstId = first.nodes[source];
		const secondId = second.nodes[source];
		if (firstId.scene != secondId.scene || firstId.index != secondId.index ||
			firstId.generation != secondId.generation ||
			!first.scene.isLive(firstId) || !second.scene.isLive(secondId)) {
			return Result.err(GltfPoseError.Target);
		}
	}
	return Result.ok(null);
}

export function commitSmoothTrs(
	ref compose: AnimationCompose,
	first: GltfPose,
	second: GltfPose,
	firstSeconds: float64,
	secondSeconds: float64,
	weight: float32,
): Result<int32, GltfPoseError> {
	const owners = try first.checkedTrsOwners(second, compose.targets);
	const firstChild = try first.stageTrsChild(compose.targets, firstSeconds);
	const secondChild = try second.stageTrsChild(compose.targets, secondSeconds);
	const staged = stageSmoothCompose(compose, firstChild, secondChild, weight);
	if (!staged.ok) { return Result.err(GltfPoseError.Compose); }
	return Result.ok(compose.committed(first));
}

export function commitExclusiveTrs(
	ref compose: AnimationCompose,
	first: GltfPose,
	second: GltfPose,
	firstSeconds: float64,
	secondSeconds: float64,
	secondSources: Readonly<Span<int32>>,
): Result<int32, GltfPoseError> {
	const owners = try first.checkedTrsOwners(second, compose.targets);
	const firstChild = try first.stageTrsChild(compose.targets, firstSeconds);
	const secondChild = try second.stageTrsChild(compose.targets, secondSeconds);
	const staged = stageExclusiveCompose(compose, firstChild, secondChild, secondSources);
	if (!staged.ok) { return Result.err(GltfPoseError.Compose); }
	return Result.ok(compose.committed(first));
}

export function bind(
	this typeof GltfPose,
	scene: Scene3D,
	nodes: Readonly<Span<NodeId3D>>,
	tracks: Readonly<Span<GltfPoseTrack>>,
): Result<GltfPose, GltfPoseError> {
	if (nodes.length > 0x7fffffff || tracks.length > 0x7fffffff) {
		return Result.err(GltfPoseError.Shape);
	}
	let owned: Vec<GltfPoseTrack> = [];
	for (let i = 0; i < tracks.length; i++) {
		const track = tracks[i];
		if (track.sourceNode < 0 || track.sourceNode >= nodes.length ||
			!scene.isLive(nodes[track.sourceNode])) { return Result.err(GltfPoseError.Target); }
		if (duplicatesEarlier(tracks, i as int32)) {
			return Result.err(GltfPoseError.DuplicateTrack);
		}
		const value = track.curve.sample(0.0);
		if (!value.ok) { return Result.err(GltfPoseError.Curve); }
		owned.push({ sourceNode: track.sourceNode, curve: track.curve });
	}
	let pose: GltfPose = {
		scene: scene, nodes: [], tracks: owned, pending: [], touched: [],
		trackTarget: [], boundSources: [], seeded: [],
	};
	for (const node of nodes) {
		pose.nodes.push(node);
		pose.pending.push(Transform3D.identity());
		pose.touched.push(false);
	}
	return Result.ok(pose);
}

export function samplePose(this pose: GltfPose, seconds: float64): Result<int32, GltfPoseError> {
	if (pose.pending.length != pose.nodes.length || pose.touched.length != pose.nodes.length) {
		return Result.err(GltfPoseError.Shape);
	}
	for (let node = 0; node < pose.nodes.length; node++) { pose.touched[node] = false; }
	for (let i = 0; i < pose.tracks.length; i++) {
		const source: int32 = pose.tracks[i].sourceNode;
		if (source < 0 || source >= pose.nodes.length ||
			!pose.scene.isLive(pose.nodes[source])) { return Result.err(GltfPoseError.Target); }
		pose.pending[source] = pose.scene.nodes[pose.nodes[source].index].local;
	}
	for (let i = 0; i < pose.tracks.length; i++) {
		const sampled = pose.tracks[i].curve.sample(seconds);
		if (!sampled.ok) { return Result.err(GltfPoseError.Curve); }
		const source: int32 = pose.tracks[i].sourceNode;
		pose.pending[source] =
			pose.pending[source].withSample(pose.tracks[i].curve.path, sampled.value);
		pose.touched[source] = true;
	}
	let written: int32 = 0;
	for (let source = 0; source < pose.nodes.length; source++) {
		if (!pose.touched[source]) { continue; }
		setLocal(pose.scene, pose.nodes[source], pose.pending[source]);
		written++;
	}
	return Result.ok(written);
}
