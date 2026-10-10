import { vec3 } from "../math/math3d";
import { GltfCurvePath, GltfPoseTrack, sample } from "./gltfCurve";
export { GltfPoseTrack } from "./gltfCurve";
import { Scene3D, NodeId3D, Transform3D, isLive, setLocal } from "./scene";

export enum GltfPoseError {
	Shape,
	Target,
	DuplicateTrack,
	Curve,
}


export interface GltfPose {
	readonly scene: Scene3D;
	nodes: Vec<NodeId3D>;
	tracks: Vec<GltfPoseTrack>;
	pending: Vec<Transform3D>;
	touched: Vec<boolean>;
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
		for (let previous = 0; previous < i; previous++) {
			if (tracks[previous].sourceNode == track.sourceNode &&
				tracks[previous].curve.path == track.curve.path) {
				return Result.err(GltfPoseError.DuplicateTrack);
			}
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
	for (const track of pose.tracks) {
		const source: int32 = track.sourceNode;
		if (source < 0 || source >= pose.nodes.length ||
			!pose.scene.isLive(pose.nodes[source])) { return Result.err(GltfPoseError.Target); }
		pose.pending[source] = pose.scene.nodes[pose.nodes[source].index].local;
	}
	for (const track of pose.tracks) {
		const sampled = track.curve.sample(seconds);
		if (!sampled.ok) { return Result.err(GltfPoseError.Curve); }
		const value = sampled.value;
		const source: int32 = track.sourceNode;
		match (track.curve.path) {
			GltfCurvePath.Translation => {
				pose.pending[source].position = vec3(value.x, value.y, value.z);
			},
			GltfCurvePath.Scale => {
				pose.pending[source].scale = vec3(value.x, value.y, value.z);
			},
			GltfCurvePath.Rotation => {
				pose.pending[source].rotation = { x: value.x, y: value.y, z: value.z, w: value.w };
			},
		}
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
