import { float32At } from "./gltfDecode";
import {
	GltfAccessorBuffer,
	GltfAccessorView,
	GltfAccessorSource,
	GltfAccessorShape,
	GltfAccessorRole,
	GltfAccessorValues,
	GltfAccessorError,
	decode,
} from "./gltfAccessor";

export enum SkinInfluencesError {
	Shape,
	Encoding,
	ExtraSets,
	JointOutOfRange,
	DuplicateJoint,
	BadWeight,
	WeightSum,
}

export struct SkinInfluences {
	joints: Vec<int32>;
	weights: Vec<float32>;
}

const UNSIGNED_BYTE: int32 = 5121;
const UNSIGNED_SHORT: int32 = 5123;
const FLOAT: int32 = 5126;

function componentBytes(component: int32): int32 {
	return match (component) {
		UNSIGNED_BYTE => 1,
		UNSIGNED_SHORT => 2,
		FLOAT => 4,
		_ => 0,
	};
}

function weightScale(component: int32): float64 {
	return match (component) {
		UNSIGNED_BYTE => 255.0,
		UNSIGNED_SHORT => 65535.0,
		_ => 0.0,
	};
}

function jointEncoding(component: int32, normalized: boolean): boolean {
	return !normalized && (component == UNSIGNED_BYTE || component == UNSIGNED_SHORT);
}

function weightEncoding(component: int32, normalized: boolean): boolean {
	return componentBytes(component) > 0 && normalized == (component != FLOAT);
}

function unsignedAt(bytes: Readonly<Span<uint8>>, at: int32, component: int32): int32 {
	const low: int32 = bytes[at] as int32;
	return component == UNSIGNED_BYTE ? low : low | ((bytes[at + 1] as int32) << 8);
}

function normalizeVertex(
	ref data: SkinInfluences,
	vertex: int32,
	jointCount: int32,
	requiredTotal: float64,
): Result<void, SkinInfluencesError> {
	let total: float64 = 0.0;
	for (let influence = 0; influence < 4; influence++) {
		const at: int32 = vertex * 4 + influence;
		const joint: int32 = data.joints[at];
		const weight: float32 = data.weights[at];
		if (joint < 0 || joint >= jointCount) {
			return Result.err(SkinInfluencesError.JointOutOfRange);
		}
		if (!Number.isFinite(weight) || weight < 0.0) {
			return Result.err(SkinInfluencesError.BadWeight);
		}
		if (weight > 0.0) {
			for (let prior = 0; prior < influence; prior++) {
				const previous: int32 = vertex * 4 + prior;
				if (data.weights[previous] > 0.0 && data.joints[previous] == joint) {
					return Result.err(SkinInfluencesError.DuplicateJoint);
				}
			}
		}
		total += weight as float64;
	}
	if (total <= 0.0 || (requiredTotal != 0.0 && total != requiredTotal)) {
		return Result.err(SkinInfluencesError.WeightSum);
	}
	for (let influence = 0; influence < 4; influence++) {
		const at: int32 = vertex * 4 + influence;
		data.weights[at] = ((data.weights[at] as float64) / total) as float32;
	}
	return Result.ok(null);
}

export function fromPacked(
	this typeof SkinInfluences,
	jointBytes: Readonly<Span<uint8>>,
	weightBytes: Readonly<Span<uint8>>,
	vertexCount: int32,
	jointCount: int32,
	jointComponent: int32,
	weightComponent: int32,
	jointNormalized: boolean,
	weightNormalized: boolean,
	sets: int32 = 1,
): Result<SkinInfluences, SkinInfluencesError> {
	if (sets != 1) { return Result.err(SkinInfluencesError.ExtraSets); }
	if (!jointEncoding(jointComponent, jointNormalized) ||
		!weightEncoding(weightComponent, weightNormalized)) {
		return Result.err(SkinInfluencesError.Encoding);
	}
	const jointSize: int32 = componentBytes(jointComponent);
	const weightSize: int32 = componentBytes(weightComponent);
	if (vertexCount < 1 || jointCount < 1 || vertexCount > 0x7fffffff / 16 ||
		jointBytes.length != vertexCount * 4 * jointSize ||
		weightBytes.length != vertexCount * 4 * weightSize) {
		return Result.err(SkinInfluencesError.Shape);
	}
	let data: SkinInfluences = { joints: [], weights: [] };
	for (let vertex = 0; vertex < vertexCount; vertex++) {
		for (let influence = 0; influence < 4; influence++) {
			const at: int32 = vertex * 4 + influence;
			data.joints.push(unsignedAt(jointBytes, at * jointSize, jointComponent));
			data.weights.push(weightComponent == FLOAT ?
				float32At(weightBytes, at * weightSize) :
				unsignedAt(weightBytes, at * weightSize, weightComponent) as float32);
		}
		const normalized = normalizeVertex(data, vertex, jointCount, weightScale(weightComponent));
		if (!normalized.ok) { return Result.err(normalized.error); }
	}
	return Result.ok(move data);
}

export function fromAccessor(
	this typeof SkinInfluences,
	joints: GltfAccessorSource,
	weights: GltfAccessorSource,
	buffers: Readonly<Span<GltfAccessorBuffer>>,
	views: Readonly<Span<GltfAccessorView>>,
	jointCount: int32,
): Result<SkinInfluences, SkinInfluencesError> {
	if (joints.role != GltfAccessorRole.Attribute || weights.role != GltfAccessorRole.Attribute ||
		joints.shape != GltfAccessorShape.Vec4 || weights.shape != GltfAccessorShape.Vec4 ||
		!jointEncoding(joints.componentType, joints.normalized) ||
		!weightEncoding(weights.componentType, weights.normalized)) {
		return Result.err(SkinInfluencesError.Encoding);
	}
	if (jointCount < 1 || joints.count < 1 || joints.count > 0x7fffffff / 16 ||
		weights.count != joints.count) {
		return Result.err(SkinInfluencesError.Shape);
	}
	const decodedJoints = GltfAccessorValues.decode(joints, buffers, views);
	if (!decodedJoints.ok) { return Result.err(SkinInfluencesError.Shape); }
	const decodedWeights = GltfAccessorValues.decode(weights, buffers, views);
	if (!decodedWeights.ok) {
		return Result.err(decodedWeights.error == GltfAccessorError.NonFinite ?
			SkinInfluencesError.BadWeight :
			SkinInfluencesError.Shape);
	}
	const scale: float64 = weightScale(weights.componentType);
	let data: SkinInfluences = { joints: [], weights: [] };
	for (let vertex = 0; vertex < joints.count; vertex++) {
		for (let influence = 0; influence < 4; influence++) {
			const at: int32 = vertex * 4 + influence;
			data.joints.push(decodedJoints.value.values[at] as int32);
			const value: float64 = decodedWeights.value.values[at];
			data.weights.push((scale == 0.0 ? value : Math.round(value * scale)) as float32);
		}
		const normalized = normalizeVertex(data, vertex, jointCount, scale);
		if (!normalized.ok) { return Result.err(normalized.error); }
	}
	return Result.ok(move data);
}
