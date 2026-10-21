import { vec3, vec4 } from "../math/math3d";
import { signedPlaneDistance, projectPointToPlane, PlaneError } from "../void3d/plane";

function near(a: float64, b: float64): boolean { return Math.abs(a - b) < 0.00001; }

test "plane signed distance and projection use existing normal dot point plus w convention" {
	const plane = vec4(0, 1, 0, -2);
	const above = signedPlaneDistance(plane, vec3(3, 5, 7));
	const below = signedPlaneDistance(plane, vec3(3, -1, 7));
	assert above.ok && above.value == 3;
	assert below.ok && below.value == -3;
	const projected = projectPointToPlane(plane, vec3(3, 5, 7));
	assert projected.ok;
	assert projected.value.x == 3 && projected.value.y == 2 && projected.value.z == 7;
	const on = signedPlaneDistance(plane, projected.value);
	assert on.ok && on.value == 0;
}

test "plane oblique projection is on plane and idempotent" {
	const plane = vec4(0.6, 0.8, 0, -2);
	const point = vec3(4, 1, 3);
	const projected = projectPointToPlane(plane, point);
	assert projected.ok;
	assert near(projected.value.x, 3.28) && near(projected.value.y, 0.04);
	assert projected.value.z == 3;
	const distance = signedPlaneDistance(plane, projected.value);
	assert distance.ok && near(distance.value, 0);
	const again = projectPointToPlane(plane, projected.value);
	assert again.ok && near(again.value.x, projected.value.x);
	assert near(again.value.y, projected.value.y);
}

test "plane reversed normal flips distance but not projection" {
	const point = vec3(2, 5, -1);
	const a = signedPlaneDistance(vec4(0, 0, 1, -3), point);
	const b = signedPlaneDistance(vec4(0, 0, -1, 3), point);
	assert a.ok && b.ok && a.value == -b.value;
	const projected = projectPointToPlane(vec4(0, 0, -1, 3), point);
	assert projected.ok && projected.value.z == 3;
	assert projected.value.x == 2 && projected.value.y == 5;
}

test "plane requires normalized normal explicitly and never silently repairs it" {
	const bad = projectPointToPlane(vec4(0, 2, 0, -4), vec3(1, 2, 3));
	assert !bad.ok && bad.error == PlaneError.NonUnitNormal;
	const zero = signedPlaneDistance(vec4(0, 0, 0, 0), vec3(1, 2, 3));
	assert !zero.ok && zero.error == PlaneError.NonUnitNormal;
}

test "plane nonfinite inputs are refused before arithmetic" {
	const badPlane = projectPointToPlane(vec4(0, 1, 0, (1.0 / 0.0) as float32), vec3(0, 0, 0));
	assert !badPlane.ok && badPlane.error == PlaneError.NonFinite;
	const badPoint = signedPlaneDistance(vec4(0, 1, 0, 0), vec3(0, (0.0 / 0.0) as float32, 0));
	assert !badPoint.ok && badPoint.error == PlaneError.NonFinite;
}

test "plane signed distance keeps widened intermediate and result range" {
	const distance = signedPlaneDistance(
		vec4(0.5773502691896258, 0.5773502691896258, 0.5773502691896258, 0),
		vec3(3.0e38, 3.0e38, 3.0e38),
	);
	assert distance.ok && Number.isFinite(distance.value);
	assert distance.value > 5.0e38 && distance.value < 5.3e38;
}

test "plane projection refuses an unrepresentable Vec3 rather than emitting infinity" {
	const projected = projectPointToPlane(
		vec4(0.5773502691896258, 0.5773502691896258, 0.5773502691896258, 0),
		vec3(-3.0e38, 3.0e38, 3.0e38),
	);
	assert !projected.ok && projected.error == PlaneError.OutOfRange;
}
