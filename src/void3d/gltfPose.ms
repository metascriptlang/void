import { Vec4, vec3 } from "../math/math3d";
import { GltfCurvePath, GltfPoseTrack, sample } from "./gltfCurve";
export { GltfPoseTrack } from "./gltfCurve";
import { Scene3D, NodeId3D, Transform3D, isLive, setLocal } from "./scene";
import {
	AnimationRestTarget, AnimationChildSample, AnimationCompose, AnimationTrsSample,
	AnimationComponent, stageSmoothCompose, stageExclusiveCompose,
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
	tracks: Vec<GltfPoseTrack>;
	pending: Vec<Transform3D>;
	touched: Vec<boolean>;
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
	const captured = AnimationCompose.create(targets);
	if (!captured.ok) { return Result.err(GltfPoseError.Compose); }
	let resolved: Vec<AnimationTrsSample> = captured.value.output;
	for (let i = 0; i < pose.tracks.length; i++) {
		let targetIndex: int32 = -1;
		for (let target = 0; target < targets.length; target++) {
			if (targets[target].sourceNode == pose.tracks[i].sourceNode) {
				targetIndex = target as int32;
				break;
			}
		}
		if (targetIndex < 0) { return Result.err(GltfPoseError.Target); }
		if (duplicatesEarlier(pose.tracks, i as int32)) {
			return Result.err(GltfPoseError.DuplicateTrack);
		}
		const sampled = pose.tracks[i].curve.sample(seconds);
		if (!sampled.ok) { return Result.err(GltfPoseError.Curve); }
		const path = pose.tracks[i].curve.path;
		resolved[targetIndex].value = resolved[targetIndex].value.withSample(path, sampled.value);
		resolved[targetIndex].present =
			resolved[targetIndex].present.incl(animatedComponent(path));
	}
	let child: AnimationChildSample = { seconds: seconds, samples: [] };
	for (const sample of resolved) {
		if (sample.present != (0 as BitSet<AnimationComponent>)) { child.samples.push(sample); }
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
	let pose: GltfPose = { scene: scene, nodes: [], tracks: [], pending: [], touched: [] };
	for (const node of nodes) {
		pose.nodes.push(node);
		pose.pending.push(Transform3D.identity());
		pose.touched.push(false);
	}
	for (let i = 0; i < tracks.length; i++) {
		const track = tracks[i];
		if (track.sourceNode < 0 || track.sourceNode >= nodes.length ||
			!scene.isLive(nodes[track.sourceNode])) { return Result.err(GltfPoseError.Target); }
		if (duplicatesEarlier(tracks, i as int32)) {
			return Result.err(GltfPoseError.DuplicateTrack);
		}
		const value = track.curve.sample(0.0);
		if (!value.ok) { return Result.err(GltfPoseError.Curve); }
		pose.tracks.push({ sourceNode: track.sourceNode, curve: track.curve });
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
