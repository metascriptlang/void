import { float32At } from "./gltfDecode";

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

function unsignedAt(bytes: Readonly<Span<uint8>>, at: int32, component: int32): int32 {
	const low: int32 = bytes[at] as int32;
	return component == UNSIGNED_BYTE ? low : low | ((bytes[at + 1] as int32) << 8);
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
	if (jointNormalized || (jointComponent != UNSIGNED_BYTE && jointComponent != UNSIGNED_SHORT)
		|| (weightComponent != UNSIGNED_BYTE && weightComponent != UNSIGNED_SHORT &&
		weightComponent != FLOAT) || weightNormalized != (weightComponent != FLOAT)) {
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
		let total: float64 = 0.0;
		for (let influence = 0; influence < 4; influence++) {
			const at: int32 = vertex * 4 + influence;
			const joint: int32 = unsignedAt(jointBytes, at * jointSize, jointComponent);
			if (joint >= jointCount) { return Result.err(SkinInfluencesError.JointOutOfRange); }
			const weight: float32 = weightComponent == FLOAT ?
				float32At(weightBytes, at * weightSize) :
				unsignedAt(weightBytes, at * weightSize, weightComponent) as float32;
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
			total = total + (weight as float64);
			data.joints.push(joint);
			data.weights.push(weight);
		}
		if (total <= 0.0 || (weightComponent == UNSIGNED_BYTE && total != 255.0) ||
			(weightComponent == UNSIGNED_SHORT && total != 65535.0)) {
			return Result.err(SkinInfluencesError.WeightSum);
		}
		for (let influence = 0; influence < 4; influence++) {
			const at: int32 = vertex * 4 + influence;
			data.weights[at] = ((data.weights[at] as float64) / total) as float32;
		}
	}
	return Result.ok(move data);
}
