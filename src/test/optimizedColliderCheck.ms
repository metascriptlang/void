import { Vec3, vec3 } from "../math/math3d";
import { Ray } from "../void3d/ray";
import { Bounds3D, fromValues, rayIntersection, contains } from "../void3d/bounds";
import { Sphere3D } from "../void3d/sphere";
import {
	OptimizedColliderError, optimizedRayIntersection, optimizedDimension, groupRayIntersection,
} from "../void3d/optimizedCollider";

const box: Bounds3D = Bounds3D.fromValues(-1, -1, -1, 2, 2, 2);
const ball: Sphere3D = { center: vec3(0, 0, 0), radius: 0.5 };

function boxHit(ray: Ray): float32 { return box.rayIntersection(ray); }
function boxHolds(point: Vec3): boolean { return box.contains(point); }
function ballHit(ray: Ray): float32 {
	const r = ball.rayIntersection(ray);
	if (!r.ok) { unreachable; }
	return r.value;
}
function fixedNaN(ray: Ray): float32 { return NaN as float32; }
function at2(ray: Ray): float32 { return 2.0; }
function at5(ray: Ray): float32 { return 5.0; }
function none(ray: Ray): float32 { return -1.0; }

function along(x: float32): Ray { return { origin: vec3(x, 0, 0), direction: vec3(1, 0, 0) }; }

test "the precise collider answers once the cheap one passes" {
	const hit = optimizedRayIntersection(boxHit, boxHolds, ballHit, false, along(-5));
	assert hit.ok && hit.value == 4.5;
}

test "a cheap miss ends the query" {
	const behind = optimizedRayIntersection(boxHit, boxHolds, ballHit, false, along(5));
	assert behind.ok && behind.value == -1.0;
}

test "an origin inside the cheap collider needs checkInside" {
	const off = optimizedRayIntersection(boxHit, boxHolds, ballHit, false, along(0));
	assert off.ok && off.value == -1.0;
	const on = optimizedRayIntersection(boxHit, boxHolds, ballHit, true, along(0));
	assert on.ok && on.value == 0.0;
	const outside = optimizedRayIntersection(boxHit, boxHolds, ballHit, true, along(5));
	assert outside.ok && outside.value == -1.0;
}

test "dimension is the larger of the two" {
	const d = optimizedDimension(2.0, 3.5);
	assert d.ok && d.value == 3.5;
}

test "a group answers the first hit, or the nearest with bestMatch" {
	const casts = [at5, none, at2];
	const first = groupRayIntersection(casts, false, along(0));
	assert first.ok && first.value == 5.0;
	const nearest = groupRayIntersection(casts, true, along(0));
	assert nearest.ok && nearest.value == 2.0;
	const missed = groupRayIntersection([none, none], true, along(0));
	assert missed.ok && missed.value == -1.0;
	const empty: ((ray: Ray) => float32)[] = [];
	const nothing = groupRayIntersection(empty, true, along(0));
	assert nothing.ok && nothing.value == -1.0;
}

test "a NaN answer is refused by name" {
	const near = optimizedRayIntersection(fixedNaN, boxHolds, ballHit, true, along(0));
	assert !near.ok && near.error == OptimizedColliderError.NonFinite;
	const far = optimizedRayIntersection(boxHit, boxHolds, fixedNaN, false, along(-5));
	assert !far.ok && far.error == OptimizedColliderError.NonFinite;
	const d = optimizedDimension(NaN as float32, 1.0);
	assert !d.ok && d.error == OptimizedColliderError.NonFinite;
	const group = groupRayIntersection([fixedNaN], true, along(0));
	assert !group.ok && group.error == OptimizedColliderError.NonFinite;
}
