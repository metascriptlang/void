import { vec3, Vec3 } from "../math/math3d";
import {
	MeshData, MeshRayHit, stride, vertexCount, rayIntersection as intersectMesh,
	rayIntersectionElements as intersectElements,
} from "./meshData";
import { Ray } from "./ray";
import { Face } from "../gpu/state";
import { isLive } from "./scene";
import { SkinInfluences } from "./skinInfluences";
import { SkinPose, syncSkinPose } from "./skinPose";
import { Bounds3D, addPoint } from "./bounds";

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
}

function copied(source: Readonly<MeshData>): MeshData {
	let mesh = MeshData.empty();
	mesh.hasUvs = source.hasUvs;
	mesh.hasTangents = source.hasTangents;
	mesh.hasSkin = source.hasSkin;
	mesh.bounds = source.bounds;
	for (const value of source.vertices) { mesh.vertices.push(value); }
	for (const index of source.indices) { mesh.indices.push(index); }
	return move mesh;
}

export function bind(
	this typeof SkinGeometry,
	source: Readonly<MeshData>,
	influences: Readonly<SkinInfluences>,
	pose: SkinPose,
): Result<SkinGeometry, SkinGeometryError> {
	const count: int32 = source.vertexCount();
	if (count < 1 || source.vertices.length != count * source.stride() ||
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
			if (joint < 0 || joint >= pose.joints.length || !Number.isFinite(weight)
				|| weight < 0) {
				return Result.err(SkinGeometryError.Influence);
			}
			sum += weight as float64;
			canonical.joints.push(joint);
			canonical.weights.push(weight);
		}
		if (Math.abs(sum - 1.0) > 0.00001) { return Result.err(SkinGeometryError.Influence); }
	}
	return Result.ok({
		pose: pose, source: copied(source), influences: move canonical,
		mesh: copied(source), pending: copied(source), ready: false, revision: 0,
	});
}

export function syncGeometry(this geometry: SkinGeometry): Result<int32, SkinGeometryError> {
	geometry.ready = false;
	const synced = geometry.pose.syncSkinPose();
	if (!synced.ok) { return Result.err(SkinGeometryError.Pose); }
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
		geometry.influences.joints.length != count * 4
		|| geometry.influences.weights.length != count * 4) {
		return Result.err(SkinGeometryError.Shape);
	}
	let bounds = Bounds3D.empty();
	for (let vertex = 0; vertex < count; vertex++) {
		const at: int32 = vertex * stride;
		const point: Vec3 = vec3(geometry.source.vertices[at], geometry.source.vertices[at + 1],
			geometry.source.vertices[at + 2]);
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
		if (!Number.isFinite(result.x) || !Number.isFinite(result.y)
			|| !Number.isFinite(result.z)) {
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
	this geometry: Readonly<SkinGeometry>, ray: Ray, face: Face, base: int32, count: int32,
): Result<MeshRayHit, SkinGeometryError> {
	if (!geometry.spatialReady()) { return Result.err(SkinGeometryError.Pose); }
	const hit = intersectElements(geometry.mesh, ray, face, base, count);
	if (!hit.ok) { return Result.err(SkinGeometryError.Range); }
	return Result.ok(hit.value);
}

export function rayIntersection(
	this geometry: Readonly<SkinGeometry>, ray: Ray, face: Face,
): Result<MeshRayHit, SkinGeometryError> {
	if (!geometry.spatialReady()) { return Result.err(SkinGeometryError.Pose); }
	return Result.ok(intersectMesh(geometry.mesh, ray, face));
}
