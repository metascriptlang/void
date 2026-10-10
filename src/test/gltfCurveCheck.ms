import { approx } from "./helpers";
import {
	GltfCurve, GltfCurvePath, GltfCurveMode, GltfCurveError, forValues, sample,
} from "../void3d/gltfCurve";

function hasX(this curve: GltfCurve, seconds: float64, expected: float32): boolean {
	const value = curve.sample(seconds);
	return value.ok && value.value.x == expected;
}

test "glTF uneven timestamps clamp independently and preserve exact STEP keys" {
	const made = GltfCurve.forValues(
		GltfCurvePath.Translation, GltfCurveMode.Step,
		[2.0, 3.0, 9.0], [0.0, 0.0, 0.0, 4.0, 8.0, 0.0, 10.0, 0.0, 0.0],
	);
	assert made.ok;
	if (!made.ok) { return; }
	assert made.value.hasX(-1.0, 0.0);
	assert made.value.hasX(2.99, 0.0);
	assert made.value.hasX(3.0, 4.0);
	assert made.value.hasX(8.0, 4.0);
	assert made.value.hasX(20.0, 10.0);
}

test "glTF linear vectors use interval duration rather than frame indices" {
	const made = GltfCurve.forValues(
		GltfCurvePath.Scale, GltfCurveMode.Linear,
		[2.0, 6.0], [1.0, 2.0, 3.0, 5.0, 10.0, 15.0],
	);
	assert made.ok;
	if (!made.ok) { return; }
	const value = made.value.sample(3.0);
	assert value.ok;
	assert approx(value.value.x, 2.0) && approx(value.value.y, 4.0);
	assert approx(value.value.z, 6.0);
}

test "glTF rotation LINEAR is shortest-path SLERP, not M9 nlerp" {
	const made = GltfCurve.forValues(
		GltfCurvePath.Rotation, GltfCurveMode.Linear,
		[0.0, 4.0], [0.0, 0.0, 0.0, 1.0, 0.0, 0.0, -0.8660254, -0.5],
	);
	assert made.ok;
	if (!made.ok) { return; }
	const value = made.value.sample(1.0);
	assert value.ok;
	assert approx(value.value.z, 0.258819);
	assert approx(value.value.w, 0.9659258);
	assert !approx(value.value.z, 0.240192);
}

test "glTF cubic triples scale tangents by seconds and clamp to property values" {
	const made = GltfCurve.forValues(
		GltfCurvePath.Translation, GltfCurveMode.CubicSpline,
		[2.0, 6.0], [
			0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 2.0, 0.0, 0.0,
			0.0, 0.0, 0.0, 5.0, 0.0, 0.0, 0.0, 0.0, 0.0,
		],
	);
	assert made.ok;
	if (!made.ok) { return; }
	assert made.value.hasX(0.0, 1.0);
	assert made.value.hasX(6.0, 5.0);
	assert made.value.hasX(4.0, 4.0);
}

test "glTF cubic rotations normalize Hermite without shortest-path sign repair" {
	const made = GltfCurve.forValues(
		GltfCurvePath.Rotation, GltfCurveMode.CubicSpline,
		[0.0, 2.0], [
			0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0,
			0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -0.8660254, -0.5, 0.0, 0.0, 0.0, 0.0,
		],
	);
	assert made.ok;
	if (!made.ok) { return; }
	const value = made.value.sample(1.0);
	assert value.ok;
	assert approx(value.value.z, -0.8660254) && approx(value.value.w, 0.5);
}

test "glTF invalid zero cubic quaternion fails instead of becoming identity" {
	const made = GltfCurve.forValues(
		GltfCurvePath.Rotation, GltfCurveMode.CubicSpline,
		[0.0, 2.0], [
			0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0, 0.0,
			0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, -1.0, 0.0, 0.0, 0.0, 0.0,
		],
	);
	assert made.ok;
	if (!made.ok) { return; }
	const value = made.value.sample(1.0);
	assert !value.ok;
	if (!value.ok) { assert value.error == GltfCurveError.InvalidQuaternion; }
}

test "glTF curve constructors validate ordering, shapes and own source storage" {
	const duplicate = GltfCurve.forValues(
		GltfCurvePath.Scale, GltfCurveMode.Linear,
		[1.0, 1.0], [1.0, 1.0, 1.0, 2.0, 2.0, 2.0],
	);
	assert !duplicate.ok;
	if (!duplicate.ok) { assert duplicate.error == GltfCurveError.TimeOrder; }
	assert !GltfCurve.forValues(
		GltfCurvePath.Scale, GltfCurveMode.CubicSpline, [1.0], [1.0, 1.0, 1.0],
	).ok;
	assert !GltfCurve.forValues(
		GltfCurvePath.Rotation, GltfCurveMode.Linear, [1.0], [0.0, 0.0, 0.0, 0.0],
	).ok;
	let values: Vec<float32> = [1.0, 2.0, 3.0];
	let times: Vec<float32> = [2.0];
	const made = GltfCurve.forValues(GltfCurvePath.Scale, GltfCurveMode.Linear, times, values);
	assert made.ok;
	if (!made.ok) { return; }
	values[0] = 99.0;
	times[0] = 99.0;
	assert made.value.hasX(0.0, 1.0);
}
