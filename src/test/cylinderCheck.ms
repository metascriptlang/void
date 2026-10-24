import { Vec3, vec3, identity } from "../math/math3d";
import { Cylinder3D, CylinderError } from "../void3d/cylinder";
import { Ray } from "../void3d/ray";
import { Sphere3D } from "../void3d/sphere";
import { Frustum3D } from "../void3d/frustum";

function upright(): Cylinder3D {
	return { a: vec3(0, 0, 0), b: vec3(0, 0, 2), radius: 1.0 };
}

function hitIs(cylinder: Cylinder3D, origin: Vec3, direction: Vec3, expected: float32): boolean {
	const ray: Ray = { origin: origin, direction: direction };
	const r = cylinder.rayIntersection(ray);
	if (expected < 0.0) { return r.ok && r.value < 0.0; }
	return r.ok && Math.abs(r.value - expected) < 1.0e-5;
}

test "cylinder ray hits the side, a cap and misses" {
	const cylinder = upright();
	assert hitIs(cylinder, vec3(-5, 0, 1), vec3(1, 0, 0), 4.0);
	assert hitIs(cylinder, vec3(0, 0, 3), vec3(0.6, 0, -0.8), 1.25);
	assert hitIs(cylinder, vec3(0, 0, -1), vec3(0.6, 0, 0.8), 1.25);
	assert hitIs(cylinder, vec3(-5, 3, 1), vec3(1, 0, 0), -1.0);
	assert hitIs(cylinder, vec3(-5, 0, 2.5), vec3(1, 0, 0), -1.0);
	assert hitIs(cylinder, vec3(5, 0, 1), vec3(1, 0, 0), -1.0);
}

test "cylinder ray along the axis hits the near cap from either side" {
	const cylinder = upright();
	assert hitIs(cylinder, vec3(0.5, 0, -5), vec3(0, 0, 1), 5.0);
	assert hitIs(cylinder, vec3(0, 0, 5), vec3(0, 0, -1), 3.0);
	assert hitIs(cylinder, vec3(0, 0, 5), vec3(0, 0, 1), -1.0);
	assert hitIs(cylinder, vec3(2, 0, -5), vec3(0, 0, 1), -1.0);
	assert hitIs(cylinder, vec3(0, 0, 1), vec3(0, 0, 1), -1.0);
}

test "cylinder contains needs the projection on the axis and the radius" {
	const cylinder = upright();
	const inside = cylinder.contains(vec3(0.9, 0, 1.9));
	const past = cylinder.contains(vec3(0.9, 0, 2.1));
	const wide = cylinder.contains(vec3(1.1, 0, 1));
	assert inside.ok && inside.value;
	assert past.ok && !past.value;
	assert wide.ok && !wide.value;
}

test "cylinder dimension and bounding sphere sit on the midpoint" {
	const cylinder = upright();
	const size = cylinder.dimension();
	assert size.ok && Math.abs(size.value - 2.8284271247461903) < 1.0e-12;
	const sphere = cylinder.boundingSphere();
	assert sphere.ok && sphere.value.center == vec3(0, 0, 1);
	assert sphere.ok && Math.abs(sphere.value.radius - 1.4142135) < 1.0e-6;
	const near: Sphere3D = { center: vec3(0, 0, -0.8), radius: 0.5 };
	const far: Sphere3D = { center: vec3(0, 0, -3.0), radius: 0.5 };
	const touching = cylinder.inSphere(near);
	const apart = cylinder.inSphere(far);
	assert touching.ok && touching.value;
	assert apart.ok && !apart.value;
}

test "cylinder frustum test keeps the whole body in view" {
	const frustum = Frustum3D.fromMatrix(identity());
	const inside: Cylinder3D = { a: vec3(0, 0, 0.2), b: vec3(0, 0, 0.4), radius: 0.1 };
	const outside: Cylinder3D = { a: vec3(5, 0, 0.5), b: vec3(7, 0, 0.5), radius: 0.5 };
	const trailing: Cylinder3D = { a: vec3(-3.2, 0, 0.5), b: vec3(-1.2, 0, 0.5), radius: 0.1 };
	const one = inside.inFrustum(frustum);
	const two = outside.inFrustum(frustum);
	const three = trailing.inFrustum(frustum);
	assert one.ok && one.value;
	assert two.ok && !two.value;
	assert three.ok && !three.value;
}

function rayFails(cylinder: Cylinder3D, error: CylinderError): boolean {
	const ray: Ray = { origin: vec3(-5, 0, 1), direction: vec3(1, 0, 0) };
	const r = cylinder.rayIntersection(ray);
	return !r.ok && r.error == error;
}

test "cylinder refuses a negative radius, a zero axis and non-finite input by name" {
	assert rayFails({ a: vec3(0, 0, 0), b: vec3(0, 0, 2), radius: -1.0 }, CylinderError.NegativeRadius);
	assert rayFails({ a: vec3(1, 1, 1), b: vec3(1, 1, 1), radius: 1.0 }, CylinderError.ZeroLengthAxis);
	assert rayFails({ a: vec3(0, 0, 0), b: vec3(0, 0, 2), radius: NaN as float32 }, CylinderError.NonFinite);
	const stuck: Cylinder3D = { a: vec3(1, 1, 1), b: vec3(1, 1, 1), radius: 1.0 };
	const contained = stuck.contains(vec3(1, 1, 1));
	assert !contained.ok && contained.error == CylinderError.ZeroLengthAxis;
	const size = stuck.dimension();
	assert !size.ok && size.error == CylinderError.ZeroLengthAxis;
}
