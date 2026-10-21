import { Sphere3D, SpherePointError, closestPoint } from "../void3d/sphere";
import { Vec3, vec3 } from "../math/math3d";

struct SpherePointCase {
	point: Vec3;
	expected: Vec3;
}

test "sphere closest point follows primary surface projection inside and outside" {
	const sphere: Sphere3D = { center: vec3(3, -4, 5), radius: 2.0 };
	const cases: Vec<SpherePointCase> = [
		{ point: vec3(7, -4, 5), expected: vec3(5, -4, 5) },
		{ point: vec3(4, -4, 5), expected: vec3(5, -4, 5) },
		{ point: vec3(5, -4, 5), expected: vec3(5, -4, 5) },
		{ point: vec3(3, -4, 5), expected: vec3(3, -4, 5) },
		{ point: vec3(3, -1, 9), expected: vec3(3, -2.8, 6.6) },
	];
	for (const sample of cases) {
		const result = sphere.closestPoint(sample.point);
		assert result.ok;
		if (result.ok) {
			assert Math.abs(result.value.x - sample.expected.x) < 0.000001;
			assert Math.abs(result.value.y - sample.expected.y) < 0.000001;
			assert Math.abs(result.value.z - sample.expected.z) < 0.000001;
		}
	}
}

test "sphere projection keeps primary small-direction cutoff and signed radius semantics" {
	for (const radius of [2.0 as float32, -2.0 as float32, 0.0 as float32]) {
		const sphere: Sphere3D = { center: vec3(0, 0, 0), radius: radius };
		const tiny = sphere.closestPoint(vec3(1.0e-12, 0, 0));
		assert tiny.ok;
		if (tiny.ok) { assert tiny.value == vec3(0, 0, 0); }
		const outsideCutoff = sphere.closestPoint(vec3(1.0e-9, 0, 0));
		assert outsideCutoff.ok;
		if (outsideCutoff.ok) { assert outsideCutoff.value == vec3(radius, 0, 0); }
	}
}

test "sphere projection rejects nonfinite data and unrepresentable output by name" {
	const sphere: Sphere3D = { center: vec3(0, 0, 0), radius: 1.0 };
	const infinite: float32 = (1.0 / 0.0) as float32;
	for (const invalid of [infinite, -infinite, infinite - infinite]) {
		const point = sphere.closestPoint(vec3(invalid, 0, 0));
		assert !point.ok;
		if (!point.ok) { assert point.error == SpherePointError.NonFinite; }
		const badCenter: Sphere3D = { center: vec3(invalid, 0, 0), radius: 1.0 };
		const center = badCenter.closestPoint(vec3(1, 0, 0));
		assert !center.ok;
		if (!center.ok) { assert center.error == SpherePointError.NonFinite; }
		const badRadius: Sphere3D = { center: vec3(0, 0, 0), radius: invalid };
		const radius = badRadius.closestPoint(vec3(1, 0, 0));
		assert !radius.ok;
		if (!radius.ok) { assert radius.error == SpherePointError.NonFinite; }
	}
	const large: Sphere3D = { center: vec3(3.0e38, 0, 0), radius: 3.0e38 };
	const outside = large.closestPoint(vec3(3.2e38, 0, 0));
	assert !outside.ok;
	if (!outside.ok) { assert outside.error == SpherePointError.OutOfRange; }
}
