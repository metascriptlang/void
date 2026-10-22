import { Vec3, vec3, identity } from "../math/math3d";
import { Capsule3D, CapsuleError } from "../void3d/capsule";
import { Ray } from "../void3d/ray";
import { Sphere3D } from "../void3d/sphere";
import { Frustum3D } from "../void3d/frustum";

function upright(): Capsule3D {
	return { a: vec3(0, 0, 0), b: vec3(0, 0, 2), radius: 1.0 };
}

function hitIs(capsule: Capsule3D, origin: Vec3, direction: Vec3, expected: float32): boolean {
	const ray: Ray = { origin: origin, direction: direction };
	const r = capsule.rayIntersection(ray);
	if (expected < 0.0) { return r.ok && r.value < 0.0; }
	return r.ok && Math.abs(r.value - expected) < 1.0e-5;
}

test "capsule ray hits the side, a cap sphere and misses" {
	const capsule = upright();
	assert hitIs(capsule, vec3(-5, 0, 1), vec3(1, 0, 0), 4.0);
	assert hitIs(capsule, vec3(-5, 0, -0.5), vec3(1, 0, 0), 5.0 - Math.sqrt(0.75) as float32);
	assert hitIs(capsule, vec3(-5, 0, 2.5), vec3(1, 0, 0), 5.0 - Math.sqrt(0.75) as float32);
	assert hitIs(capsule, vec3(-5, 3, 1), vec3(1, 0, 0), -1.0);
	assert hitIs(capsule, vec3(5, 0, 1), vec3(1, 0, 0), -1.0);
}

test "capsule ray along the axis enters at the near end from either side" {
	const capsule = upright();
	assert hitIs(capsule, vec3(0, 0, -5), vec3(0, 0, 1), 4.0);
	assert hitIs(capsule, vec3(0, 0, 5), vec3(0, 0, -1), 2.0);
	assert hitIs(capsule, vec3(0.5, 0, -5), vec3(0, 0, 1), 5.0 - Math.sqrt(0.75) as float32);
	assert hitIs(capsule, vec3(2, 0, -5), vec3(0, 0, 1), -1.0);
	assert hitIs(capsule, vec3(0, 0, -5), vec3(0, 0, -1), -1.0);
}

test "capsule ray from inside is a miss, as in Heaps" {
	const capsule = upright();
	assert hitIs(capsule, vec3(0, 0, 1), vec3(1, 0, 0), -1.0);
	assert hitIs(capsule, vec3(0, 0, 1), vec3(0, 0, 1), -1.0);
}

test "capsule contains is the distance to the segment under the radius" {
	const capsule = upright();
	const inside = capsule.contains(vec3(0.9, 0, 1));
	const cap = capsule.contains(vec3(0, 0, -0.9));
	const outside = capsule.contains(vec3(1.1, 0, 1));
	const beyond = capsule.contains(vec3(0, 0, -1.1));
	assert inside.ok && inside.value;
	assert cap.ok && cap.value;
	assert outside.ok && !outside.value;
	assert beyond.ok && !beyond.value;
}

test "capsule dimension and bounding sphere sit on the midpoint" {
	const capsule = upright();
	const size = capsule.dimension();
	assert size.ok && size.value == 4.0;
	const sphere = capsule.boundingSphere();
	assert sphere.ok && sphere.value.center == vec3(0, 0, 1) && sphere.value.radius == 2.0;
	const near: Sphere3D = { center: vec3(0, 0, -1.4), radius: 0.5 };
	const far: Sphere3D = { center: vec3(0, 0, -3.5), radius: 0.5 };
	const touching = capsule.inSphere(near);
	const apart = capsule.inSphere(far);
	assert touching.ok && touching.value;
	assert apart.ok && !apart.value;
}

test "capsule frustum test keeps a capsule whose near end is inside" {
	const frustum = Frustum3D.fromMatrix(identity());
	const inside: Capsule3D = { a: vec3(0, 0, 0.2), b: vec3(0, 0, 0.4), radius: 0.1 };
	const outside: Capsule3D = { a: vec3(5, 0, 0.5), b: vec3(7, 0, 0.5), radius: 0.5 };
	const trailing: Capsule3D = { a: vec3(-3.2, 0, 0.5), b: vec3(-1.2, 0, 0.5), radius: 0.1 };
	const one = inside.inFrustum(frustum);
	const two = outside.inFrustum(frustum);
	const three = trailing.inFrustum(frustum);
	assert one.ok && one.value;
	assert two.ok && !two.value;
	assert three.ok && !three.value;
}

function rayFails(capsule: Capsule3D, error: CapsuleError): boolean {
	const ray: Ray = { origin: vec3(-5, 0, 1), direction: vec3(1, 0, 0) };
	const r = capsule.rayIntersection(ray);
	return !r.ok && r.error == error;
}

test "capsule refuses a negative radius, a zero axis and non-finite input by name" {
	assert rayFails({ a: vec3(0, 0, 0), b: vec3(0, 0, 2), radius: -1.0 }, CapsuleError.NegativeRadius);
	assert rayFails({ a: vec3(1, 1, 1), b: vec3(1, 1, 1), radius: 1.0 }, CapsuleError.ZeroLengthAxis);
	assert rayFails({ a: vec3(0, 0, 0), b: vec3(0, 0, NaN as float32), radius: 1.0 }, CapsuleError.NonFinite);
	const stuck: Capsule3D = { a: vec3(1, 1, 1), b: vec3(1, 1, 1), radius: 1.0 };
	const contained = stuck.contains(vec3(1, 1, 1));
	assert !contained.ok && contained.error == CapsuleError.ZeroLengthAxis;
	const bound = stuck.boundingSphere();
	assert !bound.ok && bound.error == CapsuleError.ZeroLengthAxis;
	const bad: Ray = { origin: vec3(Infinity as float32, 0, 0), direction: vec3(1, 0, 0) };
	const r = upright().rayIntersection(bad);
	assert !r.ok && r.error == CapsuleError.NonFinite;
}
