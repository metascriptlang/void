import { vec3 } from "../math/math3d";
import { Ray } from "../void3d/ray";
import { HeightMapError, heightMapContains, heightMapRayIntersection } from "../void3d/heightMap";

function ground(x: float32, y: float32): float32 {
	return 0.0;
}

function slope(x: float32, y: float32): float32 {
	return 0.5 * x;
}

function missing(x: float32, y: float32): float32 {
	return NaN as float32;
}

function falling(x: float32, y: float32): float32 {
	return -x;
}

function downward(x: float32, y: float32, z: float32, dx: float32, dz: float32): Ray {
	return { origin: vec3(x, y, z), direction: vec3(dx, 0, dz) };
}

test "height map contains the points under the surface" {
	assert heightMapContains(slope, vec3(2, 0, 0.5));
	assert !heightMapContains(slope, vec3(2, 0, 1.5));
}

test "height map ray bisects to the surface, not to the last sample" {
	const flat = heightMapRayIntersection(ground, downward(0, 0, 2.5, 0, -1), 1.0, 0.01, 100.0);
	assert flat.ok && Math.abs(flat.value - 2.5) <= 0.01;
	const sloped = heightMapRayIntersection(slope, downward(0, 0, 3, 0, -1), 1.0, 0.001, 100.0);
	assert sloped.ok && Math.abs(sloped.value - 3.0) <= 0.001;
	const oblique = downward(0, 0, 4, 0.6, -0.8);
	const crossing = heightMapRayIntersection(ground, oblique, 0.5, 0.001, 100.0);
	assert crossing.ok && Math.abs(crossing.value - 5.0) <= 0.001;
	const climbing = heightMapRayIntersection(slope, downward(0, 0, 1, 0.6, -0.8), 0.25, 0.001, 100.0);
	assert climbing.ok && Math.abs(climbing.value - 1.0 / 1.1) <= 0.001;
}

test "height map ray misses looking up, level, from under the surface and out of range" {
	const upward = heightMapRayIntersection(ground, downward(0, 0, 2, 0, 1), 1.0, 0.01, 100.0);
	const level = heightMapRayIntersection(ground, downward(0, 0, 2, 1, 0), 1.0, 0.01, 100.0);
	const under = heightMapRayIntersection(ground, downward(0, 0, -1, 0, -1), 1.0, 0.01, 100.0);
	const short = heightMapRayIntersection(ground, downward(0, 0, 50, 0, -1), 1.0, 0.01, 10.0);
	const receding = heightMapRayIntersection(falling, downward(0, 0, 1, 1, -0.5), 1.0, 0.01, 50.0);
	assert upward.ok && upward.value == -1.0;
	assert level.ok && level.value == -1.0;
	assert under.ok && under.value == -1.0;
	assert short.ok && short.value == -1.0;
	assert receding.ok && receding.value == -1.0;
}

test "height map refuses a bad step, precision, range and a non-finite height by name" {
	const ray = downward(0, 0, 2.5, 0, -1);
	const a = heightMapRayIntersection(ground, ray, 0.0, 0.01, 100.0);
	const b = heightMapRayIntersection(ground, ray, 1.0, -0.01, 100.0);
	const c = heightMapRayIntersection(ground, ray, 1.0, 0.01, 0.0);
	const d = heightMapRayIntersection(missing, ray, 1.0, 0.01, 100.0);
	const e = heightMapRayIntersection(ground, downward(NaN as float32, 0, 2, 0, -1), 1.0, 0.01, 1.0);
	assert !a.ok && a.error == HeightMapError.InvalidStep;
	assert !b.ok && b.error == HeightMapError.InvalidPrecision;
	assert !c.ok && c.error == HeightMapError.InvalidRange;
	assert !d.ok && d.error == HeightMapError.NonFiniteHeight;
	assert !e.ok && e.error == HeightMapError.NonFinite;
}
