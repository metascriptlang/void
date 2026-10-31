import { vec3, Vec3, Mat4 } from "../math/math3d";
import {
	MeshData,
	MeshRayHit,
	stride,
	vertexCount,
	rayIntersection as intersectMesh,
	rayIntersectionElements as intersectElements,
} from "./meshData";
import { Ray } from "./ray";
import { Face } from "../gpu/state";
import { isLive } from "./scene";
import { SkinInfluences } from "./skinInfluences";
import { SkinPose, syncSkinPose } from "./skinPose";
import { Bounds3D, addPoint, addSpherePos } from "./bounds";
import { finiteVec } from "./colliderMath";

const JOINT_STRIDE: int32 = 7;

export enum SkinGeometryError {
	Shape,
	Influence,
	Pose,
	NonFinite,
	Range,
}

export interface SkinGeometry {
	readonly pose: SkinPose;
	readonly source: MeshData;
	readonly influences: SkinInfluences;
	mesh: MeshData;
	pending: MeshData;
	ready: boolean;
	revision: uint64;
	jointSpheres: Vec<float32>;
	bounds: Bounds3D;
	boundsReady: boolean;
	boundsRevision: uint64;
}

function copied(source: Readonly<MeshData>): MeshData {
	let mesh = MeshData.empty();
	mesh.hasUvs = source.hasUvs;
	mesh.hasTangents = source.hasTangents;
	mesh.hasUvB = source.hasUvB;
	mesh.hasSkin = source.hasSkin;
	mesh.bounds = source.bounds;
	for (const value of source.vertices) { mesh.vertices.push(value); }
	for (const index of source.indices) { mesh.indices.push(index); }
	if (source.wideIndices !== null) {
		let wide: Vec<uint32> = [];
		for (const index of source.wideIndices) { wide.push(index); }
		mesh.wideIndices = move wide;
	}
	return move mesh;
}

export function bind(
	this typeof SkinGeometry,
	source: Readonly<MeshData>,
	influences: Readonly<SkinInfluences>,
	pose: SkinPose,
): Result<SkinGeometry, SkinGeometryError> {
	const count: int32 = source.vertexCount();
	if (count < 1 || !source.validIndices() ||
		source.vertices.length != count * source.stride() ||
		influences.joints.length != count * 4 || influences.weights.length != count * 4) {
		return Result.err(SkinGeometryError.Shape);
	}
	let canonical: SkinInfluences = { joints: [], weights: [] };
	for (let vertex = 0; vertex < count; vertex++) {
		let sum: float64 = 0.0;
		for (let slot = 0; slot < 4; slot++) {
			const at: int32 = vertex * 4 + slot;
			const joint: int32 = influences.joints[at];
			const weight: float32 = influences.weights[at];
			if (joint < 0 || joint >= pose.joints.length || !Number.isFinite(weight) ||
				weight < 0) {
				return Result.err(SkinGeometryError.Influence);
			}
			sum += weight as float64;
			canonical.joints.push(joint);
			canonical.weights.push(weight);
		}
		if (Math.abs(sum - 1.0) > 0.00001) { return Result.err(SkinGeometryError.Influence); }
	}
	const made: SkinGeometry = {
		pose: pose, source: copied(source), influences: move canonical,
		mesh: copied(source), pending: copied(source), ready: false, revision: 0,
		jointSpheres: [], bounds: Bounds3D.empty(), boundsReady: false, boundsRevision: 0,
	};
	made.fitJointSpheres();
	return Result.ok(made);
}

// The radius is the half diagonal of the box's cross-section, not half its larger side: a
// smaller one leaves the box's edges outside and a posed mesh is culled while in view.
function fitJointSpheres(this geometry: SkinGeometry): void {
	const joints: int32 = geometry.pose.joints.length as int32;
	let low: Vec<float32> = [];
	let high: Vec<float32> = [];
	let used: Vec<boolean> = [];
	for (let joint = 0; joint < joints; joint++) {
		for (let axis = 0; axis < 3; axis++) { low.push(0.0); high.push(0.0); }
		used.push(false);
	}
	const count: int32 = geometry.source.vertexCount();
	const stride: int32 = geometry.source.stride();
	for (let vertex = 0; vertex < count; vertex++) {
		for (let slot = 0; slot < 4; slot++) {
			const influence: int32 = vertex * 4 + slot;
			if (geometry.influences.weights[influence] <= 0) { continue; }
			const joint: int32 = geometry.influences.joints[influence];
			for (let axis = 0; axis < 3; axis++) {
				const value: float32 = geometry.source.vertices[vertex * stride + axis];
				const at: int32 = joint * 3 + axis;
				if (!used[joint] || value < low[at]) { low[at] = value; }
				if (!used[joint] || value > high[at]) { high[at] = value; }
			}
			used[joint] = true;
		}
	}
	geometry.jointSpheres = [];
	for (let joint = 0; joint < joints; joint++) {
		if (!used[joint]) {
			for (let i = 0; i < 6; i++) { geometry.jointSpheres.push(0.0); }
			geometry.jointSpheres.push(-1.0);
			continue;
		}
		const dx: float32 = high[joint * 3] - low[joint * 3];
		const dy: float32 = high[joint * 3 + 1] - low[joint * 3 + 1];
		const dz: float32 = high[joint * 3 + 2] - low[joint * 3 + 2];
		const long: int32 = dx > dy && dx > dz ? 0 : dy > dz ? 1 : 2;
		for (let end = 0; end < 2; end++) {
			for (let axis = 0; axis < 3; axis++) {
				const at: int32 = joint * 3 + axis;
				geometry.jointSpheres.push(axis != long ? (low[at] + high[at]) * 0.5 :
					end == 0 ? low[at] : high[at]);
			}
		}
		const across: float64 = long == 0 ? dy * dy + dz * dz :
			long == 1 ? dx * dx + dz * dz : dx * dx + dy * dy;
		geometry.jointSpheres.push((Math.sqrt(across) * 0.5) as float32);
	}
	geometry.boundsReady = false;
}

// The largest factor the linear part of an affine matrix stretches a vector by is at most
// sqrt(max column sum * max row sum) of its absolute values; it is exact for rotation and
// uniform scale.
function stretchOf(matrix: Readonly<Mat4>): float32 {
	const row1: float64 = Math.abs(matrix.m11) + Math.abs(matrix.m12) + Math.abs(matrix.m13);
	const row2: float64 = Math.abs(matrix.m21) + Math.abs(matrix.m22) + Math.abs(matrix.m23);
	const row3: float64 = Math.abs(matrix.m31) + Math.abs(matrix.m32) + Math.abs(matrix.m33);
	const col1: float64 = Math.abs(matrix.m11) + Math.abs(matrix.m21) + Math.abs(matrix.m31);
	const col2: float64 = Math.abs(matrix.m12) + Math.abs(matrix.m22) + Math.abs(matrix.m32);
	const col3: float64 = Math.abs(matrix.m13) + Math.abs(matrix.m23) + Math.abs(matrix.m33);
	const rows: float64 = Math.max(row1, Math.max(row2, row3));
	const cols: float64 = Math.max(col1, Math.max(col2, col3));
	return Math.sqrt(rows * cols) as float32;
}

export function syncBounds(this geometry: SkinGeometry): Result<int32, SkinGeometryError> {
	geometry.boundsReady = false;
	const joints: int32 = geometry.pose.joints.length as int32;
	if (!geometry.pose.ready || geometry.pose.jointMatrices.length != joints) {
		return Result.err(SkinGeometryError.Pose);
	}
	if (geometry.jointSpheres.length != joints * JOINT_STRIDE) {
		return Result.err(SkinGeometryError.Shape);
	}
	for (const joint of geometry.pose.joints) {
		if (!isLive(geometry.pose.scene, joint)) { return Result.err(SkinGeometryError.Pose); }
	}
	let bounds = Bounds3D.empty();
	for (let joint = 0; joint < joints; joint++) {
		const radius: float32 = geometry.jointSpheres[joint * JOINT_STRIDE + 6];
		if (radius < 0) { continue; }
		const matrix = geometry.pose.jointMatrices[joint];
		const reach: float32 = radius * stretchOf(matrix);
		for (let end = 0; end < 2; end++) {
			const at: int32 = joint * JOINT_STRIDE + end * 3;
			const centre: Vec3 = vec3(
				geometry.jointSpheres[at],
				geometry.jointSpheres[at + 1],
				geometry.jointSpheres[at + 2],
			) * matrix;
			const added = addSpherePos(bounds, centre.x, centre.y, centre.z, reach);
			if (!added.ok) { return Result.err(SkinGeometryError.NonFinite); }
		}
	}
	geometry.bounds = bounds;
	geometry.boundsRevision = geometry.pose.revision;
	geometry.boundsReady = true;
	return Result.ok(joints);
}

export function boundsCurrent(this geometry: Readonly<SkinGeometry>): boolean {
	return geometry.boundsReady && geometry.pose.ready &&
		geometry.boundsRevision == geometry.pose.revision;
}

export function deformIfStale(this geometry: SkinGeometry): Result<int32, SkinGeometryError> {
	if (geometry.spatialReady()) { return Result.ok(0); }
	return geometry.deformPublished();
}

// A morphed pose of the bind mesh: the next deform skins these vertices instead of the bind ones.
export function setSourceVertices(
	this geometry: SkinGeometry,
	vertices: Readonly<Span<float32>>,
): Result<int32, SkinGeometryError> {
	if (vertices.length != geometry.source.vertices.length) {
		return Result.err(SkinGeometryError.Shape);
	}
	for (let i = 0; i < vertices.length; i++) { geometry.source.vertices[i] = vertices[i]; }
	geometry.ready = false;
	geometry.fitJointSpheres();
	return Result.ok(geometry.source.vertexCount());
}

export function syncGeometry(this geometry: SkinGeometry): Result<int32, SkinGeometryError> {
	geometry.ready = false;
	geometry.boundsReady = false;
	const synced = geometry.pose.syncSkinPose();
	if (!synced.ok) { return Result.err(SkinGeometryError.Pose); }
	const _bounds: int32 = try geometry.syncBounds();
	return geometry.deformPublished();
}

export function deformPublished(this geometry: SkinGeometry): Result<int32, SkinGeometryError> {
	geometry.ready = false;
	if (!geometry.pose.ready || geometry.pose.jointMatrices.length != geometry.pose.joints.length) {
		return Result.err(SkinGeometryError.Pose);
	}
	for (const joint of geometry.pose.joints) {
		if (!isLive(geometry.pose.scene, joint)) { return Result.err(SkinGeometryError.Pose); }
	}
	const count: int32 = geometry.source.vertexCount();
	const stride: int32 = geometry.source.stride();
	if (geometry.pending.vertices.length != geometry.source.vertices.length ||
		geometry.influences.joints.length != count * 4 ||
		geometry.influences.weights.length != count * 4) {
		return Result.err(SkinGeometryError.Shape);
	}
	let bounds = Bounds3D.empty();
	for (let vertex = 0; vertex < count; vertex++) {
		const at: int32 = vertex * stride;
		const point: Vec3 = vec3(
			geometry.source.vertices[at],
			geometry.source.vertices[at + 1],
			geometry.source.vertices[at + 2],
		);
		let result: Vec3 = vec3(0, 0, 0);
		for (let slot = 0; slot < 4; slot++) {
			const influence: int32 = vertex * 4 + slot;
			const weight: float32 = geometry.influences.weights[influence];
			if (weight == 0) { continue; }
			const joint: int32 = geometry.influences.joints[influence];
			const matrix = geometry.pose.jointMatrices[joint];
			const transformed: Vec3 = point * matrix;
			result.x += transformed.x * weight;
			result.y += transformed.y * weight;
			result.z += transformed.z * weight;
		}
		if (!finiteVec(result)) {
			return Result.err(SkinGeometryError.NonFinite);
		}
		geometry.pending.vertices[at] = result.x;
		geometry.pending.vertices[at + 1] = result.y;
		geometry.pending.vertices[at + 2] = result.z;
		addPoint(bounds, result);
	}
	geometry.pending.bounds = bounds;
	const previous = move geometry.mesh;
	geometry.mesh = move geometry.pending;
	geometry.pending = move previous;
	geometry.revision = geometry.pose.revision;
	geometry.ready = true;
	return Result.ok(count);
}

export function spatialReady(this geometry: Readonly<SkinGeometry>): boolean {
	if (!geometry.ready || !geometry.pose.ready || geometry.revision != geometry.pose.revision) {
		return false;
	}
	for (const joint of geometry.pose.joints) {
		if (!isLive(geometry.pose.scene, joint)) { return false; }
	}
	return true;
}

export function rayIntersectionElements(
	this geometry: Readonly<SkinGeometry>,
	ray: Ray,
	face: Face,
	base: int32,
	count: int32,
): Result<MeshRayHit, SkinGeometryError> {
	if (!geometry.spatialReady()) { return Result.err(SkinGeometryError.Pose); }
	const hit = intersectElements(geometry.mesh, ray, face, base, count);
	if (!hit.ok) { return Result.err(SkinGeometryError.Range); }
	return Result.ok(hit.value);
}

export function rayIntersection(
	this geometry: Readonly<SkinGeometry>,
	ray: Ray,
	face: Face,
): Result<MeshRayHit, SkinGeometryError> {
	if (!geometry.spatialReady()) { return Result.err(SkinGeometryError.Pose); }
	return Result.ok(intersectMesh(geometry.mesh, ray, face));
}
