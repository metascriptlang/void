import { Vec3, vec3, vec4, identity } from "../math/math3d";
import { Ray, RayPlaneError } from "../void3d/ray";
import { Frustum3D } from "../void3d/frustum";

function pointIs(hit: Result<Vec3 | null, RayPlaneError>, x: float32, y: float32,
	z: float32): boolean {
	if (hit.ok && hit.value !== null) {
		return hit.value.x == x && hit.value.y == y && hit.value.z == z;
	}
	return false;
}

test "line plane intersection returns a forward world point" {
	const ray = Ray.fromPoints(vec3(1.0, 0.0, 3.0), vec3(1.0, 1.0, 3.0));
	assert pointIs(ray.linePlaneIntersection(vec4(0.0, 1.0, 0.0, -2.0)), 1.0, 2.0, 3.0);
}

test "line plane intersection keeps signed hits behind the ray origin" {
	const ray = Ray.fromPoints(vec3(1.0, 4.0, 3.0), vec3(1.0, 5.0, 3.0));
	assert pointIs(ray.linePlaneIntersection(vec4(0.0, 1.0, 0.0, -2.0)), 1.0, 2.0, 3.0);
}

test "parallel line misses and coplanar lines return their origin" {
	const parallel = Ray.fromPoints(vec3(1.0, 0.0, 3.0), vec3(2.0, 0.0, 3.0));
	const miss = parallel.linePlaneIntersection(vec4(0.0, 1.0, 0.0, -2.0));
	assert miss.ok;
	if (miss.ok) { assert miss.value === null; }
	const coplanar = Ray.fromPoints(vec3(1.0, 2.0, 3.0), vec3(2.0, 2.0, 3.0));
	assert pointIs(coplanar.linePlaneIntersection(vec4(0.0, 1.0, 0.0, -2.0)), 1.0, 2.0, 3.0);
}

test "line plane intersection accepts the existing frustum plane representation" {
	const ray = Ray.fromPoints(vec3(1.0, 0.0, 3.0), vec3(1.0, 1.0, 3.0));
	assert pointIs(ray.linePlaneIntersection(vec4(0.0, 2.0, 0.0, -4.0)), 1.0, 2.0, 3.0);
	const frustum = Frustum3D.fromMatrix(identity());
	const through = Ray.fromPoints(vec3(0.0, 0.0, 0.5), vec3(0.0, 0.0, 1.5));
	assert pointIs(through.linePlaneIntersection(frustum.nearPlane), 0.0, 0.0, 0.0);
	assert pointIs(through.linePlaneIntersection(frustum.farPlane), 0.0, 0.0, 1.0);
}

test "stationary line follows coplanar and separated plane cases" {
	const ray: Ray = { origin: vec3(1.0, 2.0, 3.0), direction: vec3(0.0, 0.0, 0.0) };
	assert pointIs(ray.linePlaneIntersection(vec4(0.0, 1.0, 0.0, -2.0)), 1.0, 2.0, 3.0);
	const miss = ray.linePlaneIntersection(vec4(0.0, 1.0, 0.0, -4.0));
	assert miss.ok;
	if (miss.ok) { assert miss.value === null; }
}

test "line plane query rejects nonfinite inputs instead of publishing a nonfinite point" {
	const infinite: float32 = (1.0 / 0.0) as float32;
	const ray = Ray.fromPoints(vec3(0.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0));
	const result = ray.linePlaneIntersection(vec4(0.0, 1.0, 0.0, infinite));
	assert !result.ok;
	if (!result.ok) { assert result.error == RayPlaneError.NonFinite; }
	const malformed: Ray = { origin: vec3(infinite, 0.0, 0.0), direction: vec3(0.0, 1.0, 0.0) };
	const badOrigin = malformed.linePlaneIntersection(vec4(0.0, 1.0, 0.0, -2.0));
	assert !badOrigin.ok;
	if (!badOrigin.ok) { assert badOrigin.error == RayPlaneError.NonFinite; }
}

test "line plane query refuses an intersection outside float32 world coordinates" {
	const ray = Ray.fromPoints(vec3(0.0, 0.0, 0.0), vec3(0.01, 1.0, 0.0));
	const result = ray.linePlaneIntersection(vec4(1.0, 0.0, 0.0, -3.0e38));
	assert !result.ok;
	if (!result.ok) { assert result.error == RayPlaneError.OutOfRange; }
}
