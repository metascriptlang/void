import { vec3, vec4 } from "../math/math3d";
import { Frustum3D, intersectsOrientedBounds } from "../void3d/frustum";
import { OrientedBounds3D } from "../void3d/orientedBounds";

function testFrustum(): Frustum3D {
	return {
		left: vec4(1, 0, 0, 1), right: vec4(-1, 0, 0, 1),
		bottom: vec4(0, 1, 0, 1), top: vec4(0, -1, 0, 1),
		nearPlane: vec4(0, 0, 1, 1), farPlane: vec4(0, 0, -1, 1),
	};
}

function box(centerX: float32, centerY: float32, centerZ: float32,
	halfX: float32, halfY: float32, halfZ: float32): OrientedBounds3D {
	return {
		center: vec3(centerX, centerY, centerZ),
		axisX: vec3(1, 0, 0), axisY: vec3(0, 1, 0), axisZ: vec3(0, 0, 1),
		halfSize: vec3(halfX, halfY, halfZ),
	};
}

test "frustum oriented bounds missing API fails before implementation" {
	const result = testFrustum().intersectsOrientedBounds(box(0, 0, 0, 0.25, 0.25, 0.25));
	assert result.ok && result.value;
}
