import { Vec3, vec3, identity, translation, scaling, rotationY } from "../math/math3d";
import { Bounds, addPoint, addPos, addBounds } from "../void3d/bounds";
import { approx } from "./helpers";

function near(a: Vec3, x: float32, y: float32, z: float32): boolean {
	return approx(a.x, x) && approx(a.y, y) && approx(a.z, z);
}

function unitBox(): Bounds {
	return Bounds.fromValues(0.0, 0.0, 0.0, 1.0, 2.0, 3.0);
}

test "an empty bounds has no size, no center and contains nothing" {
	const box: Bounds = Bounds.empty();
	assert box.isEmpty();
	assert near(box.size(), 0.0, 0.0, 0.0);
	assert near(box.center(), 0.0, 0.0, 0.0);
	assert !box.contains(vec3(0.0, 0.0, 0.0));
	assert box.boundingSphereRadius() == 0.0;
}

test "the first point makes a bounds of zero size at that point" {
	let box: Bounds = Bounds.empty();
	addPoint(box, vec3(2.0, -3.0, 4.0));
	assert !box.isEmpty();
	assert near(box.min, 2.0, -3.0, 4.0);
	assert near(box.max, 2.0, -3.0, 4.0);
	assert near(box.size(), 0.0, 0.0, 0.0);
	assert near(box.center(), 2.0, -3.0, 4.0);
}

test "points grow the bounds on both sides" {
	let box: Bounds = Bounds.empty();
	addPos(box, 1.0, 1.0, 1.0);
	addPos(box, -1.0, 5.0, 0.0);
	assert near(box.min, -1.0, 1.0, 0.0);
	assert near(box.max, 1.0, 5.0, 1.0);
	assert near(box.size(), 2.0, 4.0, 1.0);
	assert near(box.center(), 0.0, 3.0, 0.5);
}

test "fromValues is a corner and a size" {
	const box: Bounds = unitBox();
	assert near(box.min, 0.0, 0.0, 0.0);
	assert near(box.max, 1.0, 2.0, 3.0);
	assert approx(box.dimension(), 3.0);
}

test "adding an empty bounds changes nothing" {
	let box: Bounds = unitBox();
	addBounds(box, Bounds.empty());
	assert near(box.min, 0.0, 0.0, 0.0);
	assert near(box.max, 1.0, 2.0, 3.0);
}

test "adding a bounds takes the union" {
	let box: Bounds = unitBox();
	addBounds(box, Bounds.fromValues(-2.0, 1.0, 1.0, 1.0, 1.0, 1.0));
	assert near(box.min, -2.0, 0.0, 0.0);
	assert near(box.max, 1.0, 2.0, 3.0);
}

test "contains is min inclusive and max exclusive" {
	const box: Bounds = unitBox();
	assert box.contains(vec3(0.0, 0.0, 0.0));
	assert box.contains(vec3(0.5, 1.0, 2.9));
	assert !box.contains(vec3(1.0, 1.0, 1.0));
	assert !box.contains(vec3(-0.001, 1.0, 1.0));
}

test "collide counts touching, containsBounds does not need it" {
	const box: Bounds = unitBox();
	assert box.collide(Bounds.fromValues(1.0, 2.0, 3.0, 1.0, 1.0, 1.0));
	assert !box.collide(Bounds.fromValues(1.001, 2.0, 3.0, 1.0, 1.0, 1.0));
	assert box.containsBounds(Bounds.fromValues(0.25, 0.25, 0.25, 0.5, 0.5, 0.5));
	assert !box.containsBounds(Bounds.fromValues(0.25, 0.25, 0.25, 0.5, 0.5, 5.0));
}

test "identity leaves a bounds alone and an empty one stays empty" {
	const box: Bounds = unitBox();
	const same: Bounds = box.transformed(identity());
	assert near(same.min, 0.0, 0.0, 0.0);
	assert near(same.max, 1.0, 2.0, 3.0);
	assert Bounds.empty().transformed(translation(5.0, 5.0, 5.0)).isEmpty();
}

test "translation moves a bounds and keeps its size" {
	const moved: Bounds = unitBox().transformed(translation(10.0, -1.0, 0.5));
	assert near(moved.min, 10.0, -1.0, 0.5);
	assert near(moved.size(), 1.0, 2.0, 3.0);
}

test "a quarter turn about Y swaps the X and Z extents" {
	const turned: Bounds = unitBox().transformed(rotationY(1.5707963));
	assert near(turned.size(), 3.0, 2.0, 1.0);
}

test "negative scale still gives a well-ordered bounds" {
	const flipped: Bounds = unitBox().transformed(scaling(-2.0, 1.0, 1.0));
	assert near(flipped.min, -2.0, 0.0, 0.0);
	assert near(flipped.max, 0.0, 2.0, 3.0);
}

test "offsetBy is a translation without a matrix" {
	const moved: Bounds = unitBox().offsetBy(vec3(1.0, 1.0, 1.0));
	assert near(moved.min, 1.0, 1.0, 1.0);
	assert near(moved.max, 2.0, 3.0, 4.0);
}

test "the bounding sphere is half the diagonal" {
	const box: Bounds = Bounds.fromValues(0.0, 0.0, 0.0, 2.0, 3.0, 6.0);
	assert approx(box.boundingSphereRadius(), 3.5);
}

test "closestPoint clamps into the box and leaves inside points alone" {
	const box: Bounds = unitBox();
	assert near(box.closestPoint(vec3(5.0, -5.0, 1.0)), 1.0, 0.0, 1.0);
	assert near(box.closestPoint(vec3(0.5, 0.5, 0.5)), 0.5, 0.5, 0.5);
}

test "closestPoint on an empty bounds answers zero, not the 1e20 corner" {
	// Clamping into an empty box would give (1e20, 1e20, 1e20), whose distance overflows
	// float32 to infinity — a picker would read that as a very far hit instead of no hit.
	const empty: Bounds = Bounds.empty();
	assert near(empty.closestPoint(vec3(1.0, 2.0, 3.0)), 0.0, 0.0, 0.0);
	assert near(empty.closestPoint(vec3(-5.0, -5.0, -5.0)), 0.0, 0.0, 0.0);
}

test "all contains every ordinary point" {
	assert Bounds.all().contains(vec3(1e6, -1e6, 0.0));
	assert !Bounds.all().isEmpty();
}
