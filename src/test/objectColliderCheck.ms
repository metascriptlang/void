import { Mat4, vec3, identity, scaling, translation, rotationEuler } from "../math/math3d";
import { Ray } from "../void3d/ray";
import { Sphere3D } from "../void3d/sphere";
import { TransformFrame } from "../void3d/transformCollider";
import { ObjectColliderError, objectFrame } from "../void3d/objectCollider";

test "an object's world matrix places a collider like a transform collider" {
	const placed = objectFrame(scaling(2, 2, 2) * translation(10, 0, 0));
	assert placed.ok;
	const frame: TransformFrame = placed.value;
	const world: Ray = { origin: vec3(0, 0, 0), direction: vec3(1, 0, 0) };
	const local = frame.localRay(world);
	const unit: Sphere3D = { center: vec3(0, 0, 0), radius: 1.0 };
	const hit = unit.rayIntersection(local);
	assert hit.ok && hit.value == 4.0;
	const distance = frame.worldHitDistance(local, hit.value, world);
	assert distance.ok && distance.value == 8.0;
	assert frame.localPoint(vec3(12, 0, 0)) == vec3(1, 0, 0);
	const size = frame.scaledDimension(1.5);
	assert size.ok && size.value == 3.0;
}

test "a rotated and moved object inverts exactly back" {
	const placed = objectFrame(rotationEuler(0.3, 0.7, -0.2) * translation(4, 1, 2));
	assert placed.ok;
	const back = placed.value.localPoint(vec3(4, 1, 2));
	assert Math.abs(back.x) < 1.0e-6 && Math.abs(back.y) < 1.0e-6 && Math.abs(back.z) < 1.0e-6;
}

test "a singular, non-finite or non-affine world matrix is refused by name" {
	const flat = objectFrame(scaling(0, 1, 1));
	assert !flat.ok && flat.error == ObjectColliderError.Singular;
	const bad = objectFrame(translation(NaN as float32, 0, 0));
	assert !bad.ok && bad.error == ObjectColliderError.NonFinite;
	const projective: Mat4 = { ...identity(), m14: 0.5 };
	const skewed = objectFrame(projective);
	assert !skewed.ok && skewed.error == ObjectColliderError.NotAffine;
}
