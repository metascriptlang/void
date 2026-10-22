import { MeshData, MAX_MESH_VERTICES } from "./meshData";
import { Bounds3D, addPoint } from "./bounds";
import { vec3 } from "../math/math3d";

export enum MorphGeometryError {
	Shape,
	Semantic,
	SourceVertex,
	NonFinite,
	Revision,
}

export struct MorphTarget {
	positions: Vec<float32>;
	normals: Vec<float32>;
	tangents: Vec<float32>;
}

export struct MorphPrimitiveInput {
	base: MeshData;
	sourceVertexCount: int32;
	sourceVertices: Vec<int32>;
	targets: Vec<MorphTarget>;
}

export struct MorphPrimitiveData {
	base: MeshData;
	targetVertexXyz: Vec<float32>;
}

export interface MorphData {
	readonly targetCount: int32;
	readonly primitives: Vec<MorphPrimitiveData>;
}

export struct MorphGeometry {
	readonly data: Readonly<MorphData>;
	weights: Vec<float32>;
	pendingWeights: Vec<float32>;
	meshes: Vec<MeshData>;
	pending: Vec<MeshData>;
	ready: boolean;
	revision: uint64;
}

function meshShape(source: Readonly<MeshData>): boolean {
	if (source.hasTangents && !source.hasUvs) { return false; }
	const stride: int32 = source.stride();
	if (source.vertices.length < stride ||
		(source.vertices.length as int64) > (MAX_MESH_VERTICES as int64) * stride ||
		source.vertices.length % stride != 0 || source.indices.length > 0x7fffffff) {
		return false;
	}
	const count: int32 = source.vertexCount();
	if (source.indices.length == 0) { return count % 3 == 0; }
	if (source.indices.length % 3 != 0) { return false; }
	for (const index of source.indices) {
		if ((index as int32) >= count) { return false; }
	}
	return true;
}

function copiedMesh(source: Readonly<MeshData>): MeshData {
	let mesh = MeshData.empty();
	mesh.hasUvs = source.hasUvs;
	mesh.hasTangents = source.hasTangents;
	mesh.hasSkin = source.hasSkin;
	for (const value of source.vertices) { mesh.vertices.push(value); }
	for (const index of source.indices) { mesh.indices.push(index); }
	const first = vec3(source.vertices[0], source.vertices[1], source.vertices[2]);
	let bounds: Bounds3D = { min: first, max: first };
	for (let vertex = 1; vertex < source.vertexCount(); vertex++) {
		const at: int32 = vertex * source.stride();
		addPoint(bounds, vec3(
			source.vertices[at], source.vertices[at + 1], source.vertices[at + 2],
		));
	}
	mesh.bounds = bounds;
	return move mesh;
}

function validateTarget(
	target: Readonly<MorphTarget>,
	sourceVertexCount: int32,
	hasTangents: boolean,
): Result<void, MorphGeometryError> {
	const width: int32 = sourceVertexCount * 3;
	if ((target.positions.length != 0 && target.positions.length != width) ||
		(target.normals.length != 0 && target.normals.length != width) ||
		(target.tangents.length != 0 && target.tangents.length != width) ||
		(target.positions.length == 0 && target.normals.length == 0 &&
			target.tangents.length == 0)) {
		return Result.err(MorphGeometryError.Shape);
	}
	if (!hasTangents && target.tangents.length != 0) {
		return Result.err(MorphGeometryError.Semantic);
	}
	for (const value of target.positions) {
		if (!Number.isFinite(value)) { return Result.err(MorphGeometryError.NonFinite); }
	}
	for (const value of target.normals) {
		if (!Number.isFinite(value)) { return Result.err(MorphGeometryError.NonFinite); }
	}
	for (const value of target.tangents) {
		if (!Number.isFinite(value)) { return Result.err(MorphGeometryError.NonFinite); }
	}
	return Result.ok(null);
}

export function create(
	this typeof MorphData,
	inputs: Readonly<Span<MorphPrimitiveInput>>,
	targetCount: int32,
): Result<Readonly<MorphData>, MorphGeometryError> {
	if (targetCount < 1 || inputs.length < 1 || inputs.length > 0x7fffffff) {
		return Result.err(MorphGeometryError.Shape);
	}
	let primitives: Vec<MorphPrimitiveData> = [];
	for (let primitive = 0; primitive < inputs.length; primitive++) {
		if (!meshShape(inputs[primitive].base) || inputs[primitive].sourceVertexCount < 1 ||
			inputs[primitive].sourceVertexCount > 0x7fffffff / 3) {
			return Result.err(MorphGeometryError.Shape);
		}
		const count: int32 = inputs[primitive].base.vertexCount();
		if ((targetCount as int64) * (count as int64) * 9 > 0x7fffffff ||
			inputs[primitive].sourceVertices.length != count ||
			(inputs[primitive].targets.length != 0 &&
				inputs[primitive].targets.length != targetCount)) {
			return Result.err(MorphGeometryError.Shape);
		}
		for (const source of inputs[primitive].sourceVertices) {
			if (source < 0 || source >= inputs[primitive].sourceVertexCount) {
				return Result.err(MorphGeometryError.SourceVertex);
			}
		}
		for (const value of inputs[primitive].base.vertices) {
			if (!Number.isFinite(value)) { return Result.err(MorphGeometryError.NonFinite); }
		}
		for (let target = 0; target < inputs[primitive].targets.length; target++) {
			const validated = try validateTarget(
				inputs[primitive].targets[target],
				inputs[primitive].sourceVertexCount,
				inputs[primitive].base.hasTangents,
			);
		}
		let offsets: Vec<float32> = [];
		for (let target = 0; target < targetCount; target++) {
			for (let vertex = 0; vertex < count; vertex++) {
				const at: int32 = inputs[primitive].sourceVertices[vertex] * 3;
				for (let semantic = 0; semantic < 3; semantic++) {
					for (let axis = 0; axis < 3; axis++) {
						let delta: float32 = 0;
						if (inputs[primitive].targets.length != 0) {
							const values: Readonly<Span<float32>> = match (semantic) {
								0 => inputs[primitive].targets[target].positions,
								1 => inputs[primitive].targets[target].normals,
								_ => inputs[primitive].targets[target].tangents,
							};
							if (values.length != 0) { delta = values[at + axis]; }
						}
						offsets.push(delta);
					}
				}
			}
		}
		primitives.push({
			base: copiedMesh(inputs[primitive].base), targetVertexXyz: move offsets,
		});
	}
	return Result.ok({ targetCount: targetCount, primitives: move primitives });
}

export function bind(
	this typeof MorphGeometry,
	data: Readonly<MorphData>,
): Result<MorphGeometry, MorphGeometryError> {
	if (data.targetCount < 1 || data.primitives.length < 1 || data.primitives.length > 0x7fffffff) {
		return Result.err(MorphGeometryError.Shape);
	}
	let geometry: MorphGeometry = {
		data: data, weights: [], pendingWeights: [], meshes: [], pending: [],
		ready: false, revision: 0,
	};
	for (let primitive = 0; primitive < data.primitives.length; primitive++) {
		if (!meshShape(data.primitives[primitive].base)) {
			return Result.err(MorphGeometryError.Shape);
		}
		const width: int64 = (data.targetCount as int64) *
			(data.primitives[primitive].base.vertexCount() as int64) * 9;
		if (width > 0x7fffffff || data.primitives[primitive].targetVertexXyz.length != width) {
			return Result.err(MorphGeometryError.Shape);
		}
		for (const value of data.primitives[primitive].base.vertices) {
			if (!Number.isFinite(value)) { return Result.err(MorphGeometryError.NonFinite); }
		}
		for (let at = 0; at < data.primitives[primitive].targetVertexXyz.length; at++) {
			const value: float32 = data.primitives[primitive].targetVertexXyz[at];
			if (!Number.isFinite(value)) { return Result.err(MorphGeometryError.NonFinite); }
			if (!data.primitives[primitive].base.hasTangents && at % 9 >= 6 && value != 0) {
				return Result.err(MorphGeometryError.Semantic);
			}
		}
		geometry.meshes.push(copiedMesh(data.primitives[primitive].base));
		geometry.pending.push(copiedMesh(data.primitives[primitive].base));
	}
	for (let target = 0; target < data.targetCount; target++) {
		geometry.weights.push(0);
		geometry.pendingWeights.push(0);
	}
	return Result.ok(move geometry);
}

function stagePrimitive(
	primitive: Readonly<MorphPrimitiveData>,
	weights: Readonly<Span<float32>>,
	ref pending: MeshData,
): Result<void, MorphGeometryError> {
	const count: int32 = primitive.base.vertexCount();
	const stride: int32 = primitive.base.stride();
	if (pending.vertices.length != primitive.base.vertices.length ||
		pending.indices.length != primitive.base.indices.length ||
		pending.hasUvs != primitive.base.hasUvs ||
		pending.hasTangents != primitive.base.hasTangents ||
		pending.hasSkin != primitive.base.hasSkin) {
		return Result.err(MorphGeometryError.Shape);
	}
	let bounds = Bounds3D.empty();
	for (let vertex = 0; vertex < count; vertex++) {
		const at: int32 = vertex * stride;
		for (let field = 0; field < stride; field++) {
			pending.vertices[at + field] = primitive.base.vertices[at + field];
		}
		const semanticCount: int32 = primitive.base.hasTangents ? 3 : 2;
		for (let semantic = 0; semantic < semanticCount; semantic++) {
			const field: int32 = semantic == 2 ? 12 : semantic * 3;
			for (let axis = 0; axis < 3; axis++) {
				let value: float64 = primitive.base.vertices[at + field + axis] as float64;
				for (let target = 0; target < weights.length; target++) {
					const offset: int32 = (target * count + vertex) * 9 + semantic * 3 + axis;
					value += (primitive.targetVertexXyz[offset] as float64) *
						(weights[target] as float64);
				}
				const narrowed: float32 = value as float32;
				if (!Number.isFinite(narrowed)) { return Result.err(MorphGeometryError.NonFinite); }
				pending.vertices[at + field + axis] = narrowed;
			}
		}
		const point = vec3(
			pending.vertices[at], pending.vertices[at + 1], pending.vertices[at + 2],
		);
		if (vertex == 0) { bounds = { min: point, max: point }; }
		else { addPoint(bounds, point); }
	}
	for (let index = 0; index < primitive.base.indices.length; index++) {
		pending.indices[index] = primitive.base.indices[index];
	}
	pending.bounds = bounds;
	return Result.ok(null);
}

export function publishMorphGeometry(
	ref geometry: MorphGeometry,
	weights: Readonly<Span<float32>>,
): Result<int32, MorphGeometryError> {
	geometry.ready = false;
	if (geometry.revision == 0xffffffffffffffff as uint64) {
		return Result.err(MorphGeometryError.Revision);
	}
	if (weights.length != geometry.data.targetCount || geometry.weights.length != weights.length ||
		geometry.pendingWeights.length != weights.length ||
		geometry.pending.length != geometry.data.primitives.length ||
		geometry.meshes.length != geometry.pending.length) {
		return Result.err(MorphGeometryError.Shape);
	}
	for (const weight of weights) {
		if (!Number.isFinite(weight)) { return Result.err(MorphGeometryError.NonFinite); }
	}
	for (let target = 0; target < weights.length; target++) {
		geometry.pendingWeights[target] = weights[target];
	}
	for (let primitive = 0; primitive < geometry.data.primitives.length; primitive++) {
		const staged = try stagePrimitive(
			geometry.data.primitives[primitive],
			geometry.pendingWeights,
			geometry.pending[primitive],
		);
	}
	const previousMeshes = move geometry.meshes;
	geometry.meshes = move geometry.pending;
	geometry.pending = move previousMeshes;
	const previousWeights = move geometry.weights;
	geometry.weights = move geometry.pendingWeights;
	geometry.pendingWeights = move previousWeights;
	geometry.revision++;
	geometry.ready = true;
	return Result.ok(geometry.meshes.length as int32);
}
