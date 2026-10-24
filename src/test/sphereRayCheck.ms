import { Sphere3D, SphereRayError } from "../void3d/sphere";
import { Ray } from "../void3d/ray";
import { vec3 } from "../math/math3d";

function distanceIs(sphere: Sphere3D, ray: Ray, expected: float32,
	tolerance: float32 = 0.0): boolean {
	const result = sphere.rayIntersection(ray);
	return result.ok && Math.abs(result.value - expected) <= tolerance;
}

function unitSphere(): Sphere3D {
	return { center: vec3(0, 0, 0), radius: 1.0 };
}

test "sphere ray picking returns entry distance and world surface point" {
	const sphere = unitSphere();
	const ray: Ray = { origin: vec3(-3, 0, 0), direction: vec3(1, 0, 0) };
	const result = sphere.rayIntersection(ray);
	assert result.ok;
	if (result.ok) {
		assert result.value == 2.0;
		assert ray.pointAt(result.value) == vec3(-1, 0, 0);
	}
	const translated: Sphere3D = { center: vec3(5, -2, 7), radius: 2.0 };
	const forward: Ray = { origin: vec3(5, -2, 3), direction: vec3(0, 0, 1) };
	assert distanceIs(translated, forward, 2.0);
}

test "sphere ray picking excludes misses and behind hits but includes tangency" {
	const sphere = unitSphere();
	const behind: Ray = { origin: vec3(3, 0, 0), direction: vec3(1, 0, 0) };
	const away: Ray = { origin: vec3(-3, 2, 0), direction: vec3(1, 0, 0) };
	const tangent: Ray = { origin: vec3(-3, 1, 0), direction: vec3(1, 0, 0) };
	const reverse: Ray = { origin: vec3(3, 0, 0), direction: vec3(-1, 0, 0) };
	assert distanceIs(sphere, behind, -1.0);
	assert distanceIs(sphere, away, -1.0);
	assert distanceIs(sphere, tangent, 3.0);
	assert distanceIs(sphere, reverse, 2.0);
}

test "sphere ray picking keeps inside and surface origins at zero distance" {
	const sphere = unitSphere();
	const inside: Ray = { origin: vec3(0.5, 0, 0), direction: vec3(-1, 0, 0) };
	const outward: Ray = { origin: vec3(1, 0, 0), direction: vec3(1, 0, 0) };
	const inward: Ray = { origin: vec3(1, 0, 0), direction: vec3(-1, 0, 0) };
	assert distanceIs(sphere, inside, 0.0);
	assert distanceIs(sphere, outward, 0.0);
	assert distanceIs(sphere, inward, 0.0);
	const point: Sphere3D = { center: vec3(0, 0, 0), radius: 0.0 };
	const signed: Sphere3D = { center: vec3(0, 0, 0), radius: -1.0 };
	const toward: Ray = { origin: vec3(-3, 0, 0), direction: vec3(1, 0, 0) };
	assert distanceIs(point, toward, 3.0);
	assert distanceIs(signed, toward, 2.0);
}

test "sphere ray picking consumes the existing two-point camera ray constructor" {
	const sphere: Sphere3D = { center: vec3(3, 4, 0), radius: 1.0 };
	const ray = Ray.fromPoints(vec3(0, 0, 0), vec3(3, 4, 0));
	assert distanceIs(sphere, ray, 4.0, 1.0e-5);
}

test "sphere ray picking rejects nonfinite inputs before publishing distances" {
	const sphere = unitSphere();
	const badOrigin: Ray = { origin: vec3(Infinity as float32, 0, 0), direction: vec3(1, 0, 0) };
	const badDirection: Ray = { origin: vec3(0, 0, 0), direction: vec3(1, NaN as float32, 0) };
	const ray: Ray = { origin: vec3(-3, 0, 0), direction: vec3(1, 0, 0) };
	const badCenter: Sphere3D = { center: vec3(0, Infinity as float32, 0), radius: 1.0 };
	const badRadius: Sphere3D = { center: vec3(0, 0, 0), radius: Infinity as float32 };
	const originResult = sphere.rayIntersection(badOrigin);
	const directionResult = sphere.rayIntersection(badDirection);
	const centerResult = badCenter.rayIntersection(ray);
	const radiusResult = badRadius.rayIntersection(ray);
	assert !originResult.ok && originResult.error == SphereRayError.NonFinite;
	assert !directionResult.ok && directionResult.error == SphereRayError.NonFinite;
	assert !centerResult.ok && centerResult.error == SphereRayError.NonFinite;
	assert !radiusResult.ok && radiusResult.error == SphereRayError.NonFinite;
}

test "sphere ray picking refuses an entry distance beyond float32 storage" {
	const sphere: Sphere3D = { center: vec3(3.0e38, 0, 0), radius: 1.0 };
	const ray: Ray = { origin: vec3(-3.0e38, 0, 0), direction: vec3(1, 0, 0) };
	const result = sphere.rayIntersection(ray);
	assert !result.ok && result.error == SphereRayError.OutOfRange;
}
