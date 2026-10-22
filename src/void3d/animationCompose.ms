import { Vec3, Quat, vec3 } from "../math/math3d";
import { Transform3D } from "./scene";

export enum AnimationComponent {
	Translation,
	Rotation,
	Scale,
}

export enum AnimationComposeError {
	Shape,
	Target,
	DuplicateTarget,
	NonFinite,
	InvalidQuaternion,
	Weight,
}

export struct AnimationRestTarget {
	sourceNode: int32;
	rest: Transform3D;
}

export struct AnimationTrsSample {
	sourceNode: int32;
	value: Transform3D;
	present: BitSet<AnimationComponent>;
}

export struct AnimationChildSample {
	seconds: float64;
	samples: Vec<AnimationTrsSample>;
}

export struct AnimationCompose {
	targets: Vec<AnimationRestTarget>;
	first: Vec<AnimationTrsSample>;
	second: Vec<AnimationTrsSample>;
	third: Vec<AnimationTrsSample>;
	pending: Vec<AnimationTrsSample>;
	output: Vec<AnimationTrsSample>;
	secondMask: Vec<boolean>;
	firstSeconds: float64;
	secondSeconds: float64;
}

function allComponents(): BitSet<AnimationComponent> {
	return AnimationComponent.Translation | AnimationComponent.Rotation | AnimationComponent.Scale;
}

function finiteVector(this value: Readonly<Vec3>): boolean {
	return Number.isFinite(value.x) && Number.isFinite(value.y) && Number.isFinite(value.z);
}

function checkedQuaternion(this value: Readonly<Quat>): Result<void, AnimationComposeError> {
	if (!Number.isFinite(value.x) || !Number.isFinite(value.y) ||
		!Number.isFinite(value.z) || !Number.isFinite(value.w)) {
		return Result.err(AnimationComposeError.NonFinite);
	}
	const x: float64 = value.x as float64;
	const y: float64 = value.y as float64;
	const z: float64 = value.z as float64;
	const w: float64 = value.w as float64;
	if (Math.abs(x * x + y * y + z * z + w * w - 1.0) > 0.0001) {
		return Result.err(AnimationComposeError.InvalidQuaternion);
	}
	return Result.ok(null);
}

function checkedSample(
	this sample: Readonly<AnimationTrsSample>,
): Result<void, AnimationComposeError> {
	if (!sample.present.isSubsetOf(allComponents())) {
		return Result.err(AnimationComposeError.Shape);
	}
	if ((sample.present.has(AnimationComponent.Translation) &&
		!sample.value.position.finiteVector()) ||
		(sample.present.has(AnimationComponent.Scale) && !sample.value.scale.finiteVector())) {
		return Result.err(AnimationComposeError.NonFinite);
	}
	if (sample.present.has(AnimationComponent.Rotation)) {
		const checked = try sample.value.rotation.checkedQuaternion();
	}
	return Result.ok(null);
}

function checkedTargets(
	targets: Readonly<Span<AnimationRestTarget>>,
): Result<void, AnimationComposeError> {
	if (targets.length > 0x7fffffff) { return Result.err(AnimationComposeError.Shape); }
	for (let i = 0; i < targets.length; i++) {
		if (targets[i].sourceNode < 0) { return Result.err(AnimationComposeError.Target); }
		for (let previous = 0; previous < i; previous++) {
			if (targets[previous].sourceNode == targets[i].sourceNode) {
				return Result.err(AnimationComposeError.DuplicateTarget);
			}
		}
		const sample: AnimationTrsSample = {
			sourceNode: targets[i].sourceNode,
			value: targets[i].rest,
			present: allComponents(),
		};
		const checked = try sample.checkedSample();
	}
	return Result.ok(null);
}

export function create(
	this typeof AnimationCompose,
	targets: Readonly<Span<AnimationRestTarget>>,
): Result<AnimationCompose, AnimationComposeError> {
	const checked = try checkedTargets(targets);
	let compose: AnimationCompose = {
		targets: [], first: [], second: [], third: [], pending: [], output: [], secondMask: [],
		firstSeconds: 0.0, secondSeconds: 0.0,
	};
	for (const target of targets) {
		compose.targets.push({ sourceNode: target.sourceNode, rest: target.rest });
		const sample: AnimationTrsSample = {
			sourceNode: target.sourceNode,
			value: target.rest,
			present: 0 as BitSet<AnimationComponent>,
		};
		compose.first.push(sample);
		compose.second.push(sample);
		compose.third.push(sample);
		compose.pending.push(sample);
		compose.output.push(sample);
		compose.secondMask.push(false);
	}
	return Result.ok(move compose);
}

function targetIndex(
	targets: Readonly<Span<AnimationRestTarget>>,
	sourceNode: int32,
): int32 {
	for (let i = 0; i < targets.length; i++) {
		if (targets[i].sourceNode == sourceNode) { return i as int32; }
	}
	return -1;
}

function checkedStorage(
	this compose: Readonly<AnimationCompose>,
): Result<void, AnimationComposeError> {
	const length = compose.targets.length;
	if (compose.first.length != length || compose.second.length != length ||
		compose.third.length != length ||
		compose.pending.length != length || compose.output.length != length ||
		compose.secondMask.length != length) {
		return Result.err(AnimationComposeError.Shape);
	}
	return checkedTargets(compose.targets);
}

function checkedChild(
	this compose: Readonly<AnimationCompose>,
	child: Readonly<AnimationChildSample>,
): Result<void, AnimationComposeError> {
	if (!Number.isFinite(child.seconds)) { return Result.err(AnimationComposeError.NonFinite); }
	if (child.samples.length > compose.targets.length) {
		return Result.err(AnimationComposeError.Shape);
	}
	for (let i = 0; i < child.samples.length; i++) {
		if (targetIndex(compose.targets, child.samples[i].sourceNode) < 0) {
			return Result.err(AnimationComposeError.Target);
		}
		for (let previous = 0; previous < i; previous++) {
			if (child.samples[previous].sourceNode == child.samples[i].sourceNode) {
				return Result.err(AnimationComposeError.DuplicateTarget);
			}
		}
		const checked = try child.samples[i].checkedSample();
	}
	return Result.ok(null);
}

function resolveChild(
	targets: Readonly<Span<AnimationRestTarget>>,
	child: Readonly<AnimationChildSample>,
	resolved: Span<AnimationTrsSample>,
): void {
	for (let i = 0; i < targets.length; i++) {
		resolved[i] = {
			sourceNode: targets[i].sourceNode,
			value: targets[i].rest,
			present: 0 as BitSet<AnimationComponent>,
		};
	}
	for (const sample of child.samples) {
		const index: int32 = targetIndex(targets, sample.sourceNode);
		if (sample.present.has(AnimationComponent.Translation)) {
			resolved[index].value.position = sample.value.position;
		}
		if (sample.present.has(AnimationComponent.Rotation)) {
			resolved[index].value.rotation = sample.value.rotation;
		}
		if (sample.present.has(AnimationComponent.Scale)) {
			resolved[index].value.scale = sample.value.scale;
		}
		resolved[index].present = sample.present;
	}
}

export function blendedScalar(first: float32, second: float32, weight: float32): float32 {
	const toward: float64 = weight as float64;
	return ((first as float64) * (1.0 - toward) + (second as float64) * toward) as float32;
}

function blendedVector(this first: Vec3, second: Vec3, weight: float32): Vec3 {
	return vec3(
		blendedScalar(first.x, second.x, weight),
		blendedScalar(first.y, second.y, weight),
		blendedScalar(first.z, second.z, weight),
	);
}

function publishCompose(
	ref compose: AnimationCompose,
	firstSeconds: float64,
	secondSeconds: float64,
): void {
	for (let i = 0; i < compose.output.length; i++) { compose.output[i] = compose.pending[i]; }
	compose.firstSeconds = firstSeconds;
	compose.secondSeconds = secondSeconds;
}

export function stageSmoothCompose(
	ref compose: AnimationCompose,
	first: Readonly<AnimationChildSample>,
	second: Readonly<AnimationChildSample>,
	weight: float32,
): Result<void, AnimationComposeError> {
	if (!Number.isFinite(weight)) { return Result.err(AnimationComposeError.NonFinite); }
	if (weight < 0.0 || weight > 1.0) { return Result.err(AnimationComposeError.Weight); }
	const storage = try compose.checkedStorage();
	const firstChecked = try compose.checkedChild(first);
	const secondChecked = try compose.checkedChild(second);
	resolveChild(compose.targets, first, compose.first);
	resolveChild(compose.targets, second, compose.second);
	for (let i = 0; i < compose.targets.length; i++) {
		const from = compose.first[i];
		const to = compose.second[i];
		const value: Transform3D = {
			position: from.value.position.blendedVector(to.value.position, weight),
			rotation: from.value.rotation.nlerp(to.value.rotation, weight),
			scale: from.value.scale.blendedVector(to.value.scale, weight),
		};
		const sample: AnimationTrsSample = {
			sourceNode: compose.targets[i].sourceNode,
			value: value,
			present: allComponents(),
		};
		const checked = try sample.checkedSample();
		compose.pending[i] = { ...sample, present: from.present | to.present };
	}
	publishCompose(compose, first.seconds, second.seconds);
	return Result.ok(null);
}

export function stageExclusiveCompose(
	ref compose: AnimationCompose,
	first: Readonly<AnimationChildSample>,
	second: Readonly<AnimationChildSample>,
	secondSources: Readonly<Span<int32>>,
): Result<void, AnimationComposeError> {
	const storage = try compose.checkedStorage();
	const firstChecked = try compose.checkedChild(first);
	const secondChecked = try compose.checkedChild(second);
	if (secondSources.length > compose.targets.length) {
		return Result.err(AnimationComposeError.Shape);
	}
	for (let i = 0; i < secondSources.length; i++) {
		if (targetIndex(compose.targets, secondSources[i]) < 0) {
			return Result.err(AnimationComposeError.Target);
		}
		for (let previous = 0; previous < i; previous++) {
			if (secondSources[previous] == secondSources[i]) {
				return Result.err(AnimationComposeError.DuplicateTarget);
			}
		}
	}
	resolveChild(compose.targets, first, compose.first);
	resolveChild(compose.targets, second, compose.second);
	for (let i = 0; i < compose.secondMask.length; i++) { compose.secondMask[i] = false; }
	for (const source of secondSources) {
		compose.secondMask[targetIndex(compose.targets, source)] = true;
	}
	for (let i = 0; i < compose.targets.length; i++) {
		compose.pending[i] = compose.secondMask[i] ? compose.second[i] : compose.first[i];
	}
	publishCompose(compose, first.seconds, second.seconds);
	return Result.ok(null);
}

function weightedScalar(
	a: float32, b: float32, c: float32, weights: Readonly<Span<float64>>,
): float32 {
	return ((a as float64) * weights[0] + (b as float64) * weights[1] +
		(c as float64) * weights[2]) as float32;
}

function weightedRotation(
	reference: Quat,
	a: Quat, b: Quat, c: Quat,
	weights: Readonly<Span<float64>>,
): Quat {
	const inverse: Quat = reference.conjugate();
	let x: float64 = 0.0;
	let y: float64 = 0.0;
	let z: float64 = 0.0;
	let w: float64 = 0.0;
	const sources: Vec<Quat> = [a, b, c];
	for (let i = 0; i < 3; i++) {
		let relative: Quat = inverse * sources[i];
		if (relative.w < 0.0) {
			relative = { x: -relative.x, y: -relative.y, z: -relative.z, w: -relative.w };
		}
		x += (relative.x as float64) * weights[i];
		y += (relative.y as float64) * weights[i];
		z += (relative.z as float64) * weights[i];
		w += (relative.w as float64) * weights[i];
	}
	const sum: Quat = { x: x as float32, y: y as float32, z: z as float32, w: w as float32 };
	const blended: Quat = reference * sum.normalized();
	return blended.w < 0.0
		? { x: -blended.x, y: -blended.y, z: -blended.z, w: -blended.w }
		: blended;
}

export function stageWeightedCompose(
	ref compose: AnimationCompose,
	first: Readonly<AnimationChildSample>,
	second: Readonly<AnimationChildSample>,
	third: Readonly<AnimationChildSample>,
	weights: Readonly<Span<float64>>,
): Result<void, AnimationComposeError> {
	if (weights.length != 3) { return Result.err(AnimationComposeError.Shape); }
	let total: float64 = 0.0;
	for (const weight of weights) {
		if (!Number.isFinite(weight)) { return Result.err(AnimationComposeError.NonFinite); }
		if (weight < 0.0 || weight > 1.0) { return Result.err(AnimationComposeError.Weight); }
		total += weight;
	}
	if (Math.abs(total - 1.0) > 0.000001) { return Result.err(AnimationComposeError.Weight); }
	const storage = try compose.checkedStorage();
	const firstChecked = try compose.checkedChild(first);
	const secondChecked = try compose.checkedChild(second);
	const thirdChecked = try compose.checkedChild(third);
	resolveChild(compose.targets, first, compose.first);
	resolveChild(compose.targets, second, compose.second);
	resolveChild(compose.targets, third, compose.third);
	for (let i = 0; i < compose.targets.length; i++) {
		const a = compose.first[i];
		const b = compose.second[i];
		const c = compose.third[i];
		const value: Transform3D = {
			position: vec3(
				weightedScalar(a.value.position.x, b.value.position.x, c.value.position.x, weights),
				weightedScalar(a.value.position.y, b.value.position.y, c.value.position.y, weights),
				weightedScalar(a.value.position.z, b.value.position.z, c.value.position.z,
					weights)),
			rotation: weightedRotation(
				compose.targets[i].rest.rotation, a.value.rotation, b.value.rotation,
				c.value.rotation, weights),
			scale: vec3(
				weightedScalar(a.value.scale.x, b.value.scale.x, c.value.scale.x, weights),
				weightedScalar(a.value.scale.y, b.value.scale.y, c.value.scale.y, weights),
				weightedScalar(a.value.scale.z, b.value.scale.z, c.value.scale.z, weights)),
		};
		const sample: AnimationTrsSample = {
			sourceNode: compose.targets[i].sourceNode, value: value, present: allComponents(),
		};
		const checked = try sample.checkedSample();
		let present: BitSet<AnimationComponent> = 0 as BitSet<AnimationComponent>;
		if (weights[0] != 0.0) { present = present | a.present; }
		if (weights[1] != 0.0) { present = present | b.present; }
		if (weights[2] != 0.0) { present = present | c.present; }
		compose.pending[i] = { ...sample, present: present };
	}
	publishCompose(compose, first.seconds, second.seconds);
	return Result.ok(null);
}
