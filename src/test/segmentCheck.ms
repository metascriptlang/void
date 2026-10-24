import { Vec3, vec3 } from "../math/math3d";
import { Segment3D, SegmentError } from "../void3d/segment";

function along(): Segment3D {
	return { p1: vec3(0, 0, 0), p2: vec3(2, 0, 0) };
}

function squaredIs(seg: Segment3D, point: Vec3, expected: float64): boolean {
	const r = seg.distanceSquared(point);
	return r.ok && Math.abs(r.value - expected) < 1.0e-12;
}

function failsWith(seg: Segment3D, point: Vec3, error: SegmentError): boolean {
	const r = seg.distanceSquared(point);
	return !r.ok && r.error == error;
}

test "segment distance projects inside and clamps to either end" {
	const seg = along();
	assert squaredIs(seg, vec3(1, 3, 0), 9.0);
	assert squaredIs(seg, vec3(-1, 0, 0), 1.0);
	assert squaredIs(seg, vec3(3, 0, 4), 17.0);
	assert squaredIs(seg, vec3(1, 0, 0), 0.0);
	const r = seg.distance(vec3(1, 3, 0));
	assert r.ok && r.value == 3.0;
}

test "segment distance follows an oblique segment" {
	const seg: Segment3D = { p1: vec3(0, 0, 0), p2: vec3(1, 1, 0) };
	assert squaredIs(seg, vec3(1, 0, 0), 0.5);
	assert squaredIs(seg, vec3(2, 2, 1), 3.0);
}

test "segment refuses a zero length and non-finite input by name" {
	const point: Segment3D = { p1: vec3(1, 1, 1), p2: vec3(1, 1, 1) };
	assert failsWith(point, vec3(0, 0, 0), SegmentError.ZeroLength);
	assert failsWith(along(), vec3(NaN as float32, 0, 0), SegmentError.NonFinite);
	const infinite: Segment3D = { p1: vec3(0, 0, 0), p2: vec3(Infinity as float32, 0, 0) };
	assert failsWith(infinite, vec3(0, 0, 0), SegmentError.NonFinite);
}
