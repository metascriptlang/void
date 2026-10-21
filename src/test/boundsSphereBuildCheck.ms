import { Bounds3D, SphereBoundsError, addSpherePos } from "../void3d/bounds";
import { vec3 } from "../math/math3d";
import { Ray } from "../void3d/ray";

test "sphere positions accumulate actor envelopes into an empty bounds" {
	let box = Bounds3D.empty();
	assert addSpherePos(box, 2, -3, 4, 1).ok;
	assert box.min == vec3(1, -4, 3);
	assert box.max == vec3(3, -2, 5);
	assert addSpherePos(box, -4, 5, 0, 2).ok;
	assert box.min == vec3(-6, -4, -2);
	assert box.max == vec3(3, 7, 5);
	const ray: Ray = { origin: vec3(-10, 0, 0), direction: vec3(1, 0, 0) };
	assert box.rayIntersection(ray) == 4.0;
}

test "adding a contained sphere does not shrink a populated bounds" {
	let box = Bounds3D.fromValues(-4, -3, -2, 8, 6, 4);
	assert addSpherePos(box, 0, 0, 0, 1).ok;
	assert box.min == vec3(-4, -3, -2);
	assert box.max == vec3(4, 3, 2);
	assert addSpherePos(box, 5, 0, 0, 2).ok;
	assert box.min == vec3(-4, -3, -2);
	assert box.max == vec3(7, 3, 2);
}

test "sphere envelope builder retains primary zero and signed radius parameters" {
	let point = Bounds3D.empty();
	assert addSpherePos(point, 2, 3, 4, 0).ok;
	assert point.min == vec3(2, 3, 4);
	assert point.max == point.min;
	assert !point.isEmpty();
	let inverted = Bounds3D.empty();
	assert addSpherePos(inverted, 0, 0, 0, -1).ok;
	assert inverted.min == vec3(1, 1, 1);
	assert inverted.max == vec3(-1, -1, -1);
	assert inverted.isEmpty();
}

test "sphere envelope rejects nonfinite input without changing bounds" {
	let box = Bounds3D.fromValues(-2, -3, -4, 4, 6, 8);
	const beforeMin = box.min;
	const beforeMax = box.max;
	const infinite: float32 = Infinity as float32;
	for (const invalid of [infinite, -infinite, infinite - infinite]) {
		const centerResult = addSpherePos(box, invalid, 0, 0, 1);
		assert !centerResult.ok;
		if (!centerResult.ok) { assert centerResult.error == SphereBoundsError.NonFinite; }
		const radiusResult = addSpherePos(box, 0, 0, 0, invalid);
		assert !radiusResult.ok;
		if (!radiusResult.ok) { assert radiusResult.error == SphereBoundsError.NonFinite; }
		assert box.min == beforeMin;
		assert box.max == beforeMax;
	}
	let badTarget = Bounds3D.fromPoints(vec3(infinite, 0, 0), vec3(infinite, 1, 1));
	const targetResult = addSpherePos(badTarget, 0, 0, 0, 1);
	assert !targetResult.ok;
	if (!targetResult.ok) { assert targetResult.error == SphereBoundsError.NonFinite; }
	assert badTarget.min.x == infinite;
	assert badTarget.max == vec3(infinite, 1, 1);
}

test "sphere envelope preflights all output bounds before publishing growth" {
	let box = Bounds3D.fromValues(-2, -3, -4, 4, 6, 8);
	const beforeMin = box.min;
	const beforeMax = box.max;
	const result = addSpherePos(box, 3.0e38, 0, 0, 3.0e38);
	assert !result.ok;
	if (!result.ok) { assert result.error == SphereBoundsError.OutOfRange; }
	assert box.min == beforeMin;
	assert box.max == beforeMax;
}
