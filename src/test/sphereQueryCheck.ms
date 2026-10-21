import { Vec3, vec3 } from "../math/math3d";
import { Sphere3D } from "../void3d/sphere";

test "sphere point containment measures distance from its own center" {
	const sphere: Sphere3D = { center: vec3(2.0, 3.0, 4.0), radius: 2.0 };
	assert sphere.contains(vec3(2.0, 3.0, 4.0));
	assert sphere.contains(vec3(3.0, 3.0, 4.0));
	assert !sphere.contains(vec3(4.0, 3.0, 4.0));
	assert !sphere.contains(vec3(4.01, 3.0, 4.0));
	assert !sphere.contains(vec3(0.0, 3.0, 4.0));
}

test "sphere surface points are excluded on every axis" {
	const sphere: Sphere3D = { center: vec3(0.0, 0.0, 0.0), radius: 1.0 };
	let surface: Vec<Vec3> = [
		vec3(-1.0, 0.0, 0.0), vec3(1.0, 0.0, 0.0),
		vec3(0.0, -1.0, 0.0), vec3(0.0, 1.0, 0.0),
		vec3(0.0, 0.0, -1.0), vec3(0.0, 0.0, 1.0),
	];
	for (const point of surface) { assert !sphere.contains(point); }
	assert sphere.contains(vec3(0.5, 0.5, 0.5));
	assert !sphere.contains(vec3(1.0, 1.0, 1.0));
}

test "sphere pair overlap is symmetric and excludes tangency" {
	const first: Sphere3D = { center: vec3(0.0, 0.0, 0.0), radius: 1.0 };
	const second: Sphere3D = { center: vec3(1.5, 0.0, 0.0), radius: 1.0 };
	assert first.overlaps(second) && second.overlaps(first);
	const tangent: Sphere3D = { center: vec3(2.0, 0.0, 0.0), radius: 1.0 };
	assert !first.overlaps(tangent) && !tangent.overlaps(first);
	const distant: Sphere3D = { center: vec3(2.01, 0.0, 0.0), radius: 1.0 };
	assert !first.overlaps(distant);
	const nested: Sphere3D = { center: vec3(0.0, 0.0, 0.0), radius: 0.25 };
	assert first.overlaps(nested) && nested.overlaps(first);
}

test "zero radius predicates retain the Heaps strict distance thresholds" {
	const point: Sphere3D = { center: vec3(0.0, 0.0, 0.0), radius: 0.0 };
	const solid: Sphere3D = { center: vec3(0.0, 0.0, 0.0), radius: 1.0 };
	assert !point.contains(vec3(0.0, 0.0, 0.0));
	assert !point.overlaps(point);
	assert point.overlaps(solid) && solid.overlaps(point);
	const boundary: Sphere3D = { center: vec3(1.0, 0.0, 0.0), radius: 0.0 };
	assert !solid.overlaps(boundary) && !boundary.overlaps(solid);
}
