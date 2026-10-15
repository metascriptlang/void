import { Vec4, Quat, slerp } from "../math/math3d";

export struct GltfPoseTrack {
	sourceNode: int32;
	curve: Readonly<GltfCurve>;
}

export enum GltfCurvePath {
	Translation,
	Rotation,
	Scale,
}

export enum GltfCurveMode {
	Step,
	Linear,
	CubicSpline,
}

export enum GltfCurveError {
	Empty,
	Shape,
	TimeOrder,
	NonFinite,
	InvalidQuaternion,
	Mode,
}

export struct GltfCurve {
	path: GltfCurvePath;
	mode: GltfCurveMode;
	times: Vec<float32>;
	values: Vec<float32>;
}

function width(this path: GltfCurvePath): int32 {
	return match (path) {
		GltfCurvePath.Translation | GltfCurvePath.Scale => 3,
		GltfCurvePath.Rotation => 4,
		_ => 0,
	};
}

function keyStride(this curve: Readonly<GltfCurve>): int32 {
	return curve.path.width() * (curve.mode == GltfCurveMode.CubicSpline ? 3 : 1);
}

function readValue(this curve: Readonly<GltfCurve>, at: int32): Vec4 {
	return {
		x: curve.values[at], y: curve.values[at + 1], z: curve.values[at + 2],
		w: curve.path == GltfCurvePath.Rotation ? curve.values[at + 3] : 0.0,
	};
}

function lengthSquared(this value: Vec4): float64 {
	const x: float64 = value.x as float64;
	const y: float64 = value.y as float64;
	const z: float64 = value.z as float64;
	const w: float64 = value.w as float64;
	return x * x + y * y + z * z + w * w;
}

function checked(this curve: Readonly<GltfCurve>, value: Vec4): Result<Vec4, GltfCurveError> {
	if (!Number.isFinite(value.x) || !Number.isFinite(value.y) ||
		!Number.isFinite(value.z) || !Number.isFinite(value.w)) {
		return Result.err(GltfCurveError.NonFinite);
	}
	if (curve.path != GltfCurvePath.Rotation || curve.mode != GltfCurveMode.CubicSpline) {
		return Result.ok(value);
	}
	const squared: float64 = value.lengthSquared();
	if (squared <= 0.0) { return Result.err(GltfCurveError.InvalidQuaternion); }
	const inverse: float64 = 1.0 / Math.sqrt(squared);
	return Result.ok({
		x: ((value.x as float64) * inverse) as float32,
		y: ((value.y as float64) * inverse) as float32,
		z: ((value.z as float64) * inverse) as float32,
		w: ((value.w as float64) * inverse) as float32,
	});
}

export function forValues(
	this typeof GltfCurve,
	path: GltfCurvePath,
	mode: GltfCurveMode,
	times: Readonly<Span<float32>>,
	values: Readonly<Span<float32>>,
): Result<GltfCurve, GltfCurveError> {
	if (times.length < 1) { return Result.err(GltfCurveError.Empty); }
	if (mode != GltfCurveMode.Step && mode != GltfCurveMode.Linear &&
		mode != GltfCurveMode.CubicSpline) { return Result.err(GltfCurveError.Mode); }
	const components: int32 = path.width();
	const stride: int32 = components * (mode == GltfCurveMode.CubicSpline ? 3 : 1);
	if (components == 0 || times.length > 0x7fffffff / stride ||
		values.length != times.length * stride ||
		(mode == GltfCurveMode.CubicSpline && times.length < 2)) {
		return Result.err(GltfCurveError.Shape);
	}
	let previous: float32 = -1.0;
	let curve: GltfCurve = { path: path, mode: mode, times: [], values: [] };
	for (const time of times) {
		if (!Number.isFinite(time)) { return Result.err(GltfCurveError.NonFinite); }
		if (time < 0.0 || time <= previous) { return Result.err(GltfCurveError.TimeOrder); }
		previous = time;
		curve.times.push(time);
	}
	for (const value of values) {
		if (!Number.isFinite(value)) { return Result.err(GltfCurveError.NonFinite); }
		curve.values.push(value);
	}
	if (path == GltfCurvePath.Rotation) {
		const offset: int32 = mode == GltfCurveMode.CubicSpline ? components : 0;
		for (let key = 0; key < times.length; key++) {
			const squared: float64 = curve.readValue(key * stride + offset).lengthSquared();
			if (Math.abs(squared - 1.0) > 0.0001) {
				return Result.err(GltfCurveError.InvalidQuaternion);
			}
		}
	}
	return Result.ok(move curve);
}

function hermite(
	first: float32, outgoing: float32, incoming: float32, second: float32,
	u: float64, seconds: float64,
): float32 {
	const square: float64 = u * u;
	const cube: float64 = square * u;
	return ((2.0 * cube - 3.0 * square + 1.0) * (first as float64) +
		seconds * (cube - 2.0 * square + u) * (outgoing as float64) +
		(-2.0 * cube + 3.0 * square) * (second as float64) +
		seconds * (cube - square) * (incoming as float64)) as float32;
}

export function sample(
	this curve: Readonly<GltfCurve>,
	seconds: float64,
): Result<Vec4, GltfCurveError> {
	if (!Number.isFinite(seconds)) { return Result.err(GltfCurveError.NonFinite); }
	const stride: int32 = curve.keyStride();
	if (curve.times.length < 1 || stride < 1 || curve.times.length > 0x7fffffff / stride ||
		curve.values.length != curve.times.length * stride) {
		return Result.err(GltfCurveError.Shape);
	}
	if (curve.mode != GltfCurveMode.Step && curve.mode != GltfCurveMode.Linear &&
		curve.mode != GltfCurveMode.CubicSpline) { return Result.err(GltfCurveError.Mode); }
	const last: int32 = (curve.times.length as int32) - 1;
	const offset: int32 = curve.mode == GltfCurveMode.CubicSpline ? curve.path.width() : 0;
	if (seconds <= curve.times[0]) { return curve.checked(curve.readValue(offset)); }
	if (seconds >= curve.times[last]) {
		return curve.checked(curve.readValue(last * stride + offset));
	}
	let left: int32 = 0;
	let right: int32 = last;
	while (right - left > 1) {
		const middle: int32 = left + (right - left) / 2;
		if (seconds < curve.times[middle]) { right = middle; }
		else { left = middle; }
	}
	const firstAt: int32 = left * stride + offset;
	const secondAt: int32 = right * stride + offset;
	const first: Vec4 = curve.readValue(firstAt);
	if (seconds == curve.times[left] || curve.mode == GltfCurveMode.Step) {
		return curve.checked(first);
	}
	const duration: float64 = (curve.times[right] as float64) - (curve.times[left] as float64);
	if (duration <= 0.0) { return Result.err(GltfCurveError.TimeOrder); }
	const u: float64 = (seconds - (curve.times[left] as float64)) / duration;
	const second: Vec4 = curve.readValue(secondAt);
	if (curve.mode == GltfCurveMode.CubicSpline) {
		const outgoing: Vec4 = curve.readValue(firstAt + curve.path.width());
		const incoming: Vec4 = curve.readValue(secondAt - curve.path.width());
		return curve.checked({
			x: hermite(first.x, outgoing.x, incoming.x, second.x, u, duration),
			y: hermite(first.y, outgoing.y, incoming.y, second.y, u, duration),
			z: hermite(first.z, outgoing.z, incoming.z, second.z, u, duration),
			w: hermite(first.w, outgoing.w, incoming.w, second.w, u, duration),
		});
	}
	if (curve.path == GltfCurvePath.Rotation) {
		const from: Quat = { x: first.x, y: first.y, z: first.z, w: first.w };
		const to: Quat = { x: second.x, y: second.y, z: second.z, w: second.w };
		const value: Quat = from.slerp(to, u as float32);
		return curve.checked({ x: value.x, y: value.y, z: value.z, w: value.w });
	}
	return curve.checked({
		x: ((1.0 - u) * (first.x as float64) + u * (second.x as float64)) as float32,
		y: ((1.0 - u) * (first.y as float64) + u * (second.y as float64)) as float32,
		z: ((1.0 - u) * (first.z as float64) + u * (second.z as float64)) as float32,
		w: 0.0,
	});
}
