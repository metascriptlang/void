import { vec3, vec4, Vec3 } from "../math/math3d";
import { Frustum3D, intersectsOrientedBounds } from "../void3d/frustum";
import { OrientedBounds3D, OrientedBoundsError } from "../void3d/orientedBounds";

function testFrustum(): Frustum3D {
	return {
		left: vec4(1, 0, 0, 1), right: vec4(-1, 0, 0, 1),
		bottom: vec4(0, 1, 0, 1), top: vec4(0, -1, 0, 1),
		nearPlane: vec4(0, 0, 1, 1), farPlane: vec4(0, 0, -1, 1),
	};
}

function box(center: Vec3, halfSize: Vec3): OrientedBounds3D {
	return {
		center: center,
		axisX: vec3(1, 0, 0), axisY: vec3(0, 1, 0), axisZ: vec3(0, 0, 1),
		halfSize: halfSize,
	};
}

function rotatedBox(center: Vec3): OrientedBounds3D {
	const r: float32 = 0.70710677;
	return {
		center: center,
		axisX: vec3(r, r, 0), axisY: vec3(-r, r, 0), axisZ: vec3(0, 0, 1),
		halfSize: vec3(0.5, 0.5, 0.5),
	};
}

function hits(bounds: OrientedBounds3D): boolean {
	const result = testFrustum().intersectsOrientedBounds(bounds);
	if (!result.ok) { unreachable; }
	return result.value;
}

function refusal(bounds: OrientedBounds3D): OrientedBoundsError {
	const result = testFrustum().intersectsOrientedBounds(bounds);
	if (result.ok) { unreachable; }
	return result.error;
}

test "frustum oriented bounds keeps a box inside and on a plane" {
	assert hits(box(vec3(0, 0, 0), vec3(0.25, 0.25, 0.25)));
	assert hits(box(vec3(-1.5, 0, 0), vec3(0.5, 0.5, 0.5)));
	assert hits(box(vec3(0, 0, 0), vec3(0, 0, 0)));
}

test "frustum oriented bounds culls a box behind each plane" {
	assert !hits(box(vec3(-2, 0, 0), vec3(0.5, 0.5, 0.5)));
	assert !hits(box(vec3(2, 0, 0), vec3(0.5, 0.5, 0.5)));
	assert !hits(box(vec3(0, -2, 0), vec3(0.5, 0.5, 0.5)));
	assert !hits(box(vec3(0, 2, 0), vec3(0.5, 0.5, 0.5)));
	assert !hits(box(vec3(0, 0, -2), vec3(0.5, 0.5, 0.5)));
	assert !hits(box(vec3(0, 0, 2), vec3(0.5, 0.5, 0.5)));
}

test "frustum oriented bounds reads the box axes" {
	assert !hits(box(vec3(1.6, 0, 0), vec3(0.5, 0.5, 0.5)));
	assert hits(rotatedBox(vec3(1.6, 0, 0)));
	assert !hits(rotatedBox(vec3(1.75, 0, 0)));
}

test "frustum oriented bounds refuses malformed boxes by name" {
	const nan: float32 = NaN as float32;
	assert refusal(box(vec3(nan, 0, 0), vec3(1, 1, 1))) == OrientedBoundsError.NonFinite;
	assert refusal(box(vec3(0, 0, 0), vec3(-1, 1, 1))) == OrientedBoundsError.NegativeHalfSize;
	let skewed: OrientedBounds3D = box(vec3(0, 0, 0), vec3(1, 1, 1));
	skewed.axisY = vec3(1, 0, 0);
	assert refusal(skewed) == OrientedBoundsError.NonOrthonormalAxes;
}
