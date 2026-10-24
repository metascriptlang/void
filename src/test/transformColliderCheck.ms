import { vec3, identity, scaling, translation } from "../math/math3d";
import { Ray } from "../void3d/ray";
import { Sphere3D } from "../void3d/sphere";
import {
	TransformFrame, TransformError, transformFrame, isIdentityEpsilon,
} from "../void3d/transformCollider";

function placed(): TransformFrame {
	const r = transformFrame(scaling(2, 2, 2) * translation(10, 0, 0));
	if (!r.ok) { unreachable; }
	return r.value;
}

test "a hit in local space comes back as the world distance through the matrix" {
	const frame = placed();
	const world: Ray = { origin: vec3(0, 0, 0), direction: vec3(1, 0, 0) };
	const local = frame.localRay(world);
	assert local.origin == vec3(-5, 0, 0) && local.direction == vec3(0.5, 0, 0).normalized();
	const unit: Sphere3D = { center: vec3(0, 0, 0), radius: 1.0 };
	const hit = unit.rayIntersection(local);
	assert hit.ok && hit.value == 4.0;
	const distance = frame.worldHitDistance(local, hit.value, world);
	assert distance.ok && distance.value == 8.0;
	const miss = frame.worldHitDistance(local, -1.0, world);
	assert miss.ok && miss.value == -1.0;
}

test "a point and a sphere are carried into the collider's space" {
	const frame = placed();
	assert frame.localPoint(vec3(12, 0, 0)) == vec3(1, 0, 0);
	const world: Sphere3D = { center: vec3(10, 0, 0), radius: 2.0 };
	const local = frame.localSphere(world);
	assert local.ok && local.value.center == vec3(0, 0, 0) && local.value.radius == 1.0;
	const unit: Sphere3D = { center: vec3(0, 0, 0), radius: 1.0 };
	const back = frame.worldSphere(unit);
	assert back.ok && back.value.center == vec3(10, 0, 0) && back.value.radius == 2.0;
}

test "a non-uniform placement grows a sphere by its largest axis scale" {
	const r = transformFrame(scaling(1, 3, 2));
	assert r.ok;
	const unit: Sphere3D = { center: vec3(0, 0, 0), radius: 1.0 };
	const back = r.value.worldSphere(unit);
	assert back.ok && back.value.radius == 3.0;
	const size = r.value.scaledDimension(2.0);
	assert size.ok && size.value == 6.0;
}

test "a mirrored placement keeps a positive radius and dimension" {
	const r = transformFrame(scaling(-2, 2, 2));
	assert r.ok;
	const world: Sphere3D = { center: vec3(0, 0, 0), radius: 1.0 };
	const local = r.value.localSphere(world);
	assert local.ok && local.value.radius == 0.5;
	const size = r.value.scaledDimension(3.0);
	assert size.ok && size.value == 6.0;
}

test "composing a frame places the collider by both matrices" {
	const frame = placed();
	const moved = frame.composed(translation(0, 5, 0));
	assert moved.ok;
	assert moved.value.localPoint(vec3(12, 5, 0)) == vec3(1, -2.5, 0);
}

test "identity within an epsilon" {
	assert isIdentityEpsilon(identity(), 1.0e-10);
	assert isIdentityEpsilon(translation(1.0e-12, 0, 0), 1.0e-10);
	assert !isIdentityEpsilon(translation(1.0e-3, 0, 0), 1.0e-10);
	assert !isIdentityEpsilon(scaling(1, 1, 2), 1.0e-10);
}

test "a singular or non-finite matrix is refused by name" {
	const flat = transformFrame(scaling(0, 1, 1));
	assert !flat.ok && flat.error == TransformError.Singular;
	const bad = transformFrame(translation(NaN as float32, 0, 0));
	assert !bad.ok && bad.error == TransformError.NonFinite;
	const frame = placed();
	const sphere: Sphere3D = { center: vec3(0, 0, 0), radius: Infinity as float32 };
	const r = frame.localSphere(sphere);
	assert !r.ok && r.error == TransformError.NonFinite;
	const composedBad = frame.composed(scaling(0, 1, 1));
	assert !composedBad.ok && composedBad.error == TransformError.Singular;
}
