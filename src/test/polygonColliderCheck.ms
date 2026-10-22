import { Vec3, vec3 } from "../math/math3d";
import { Ray } from "../void3d/ray";
import {
	Triangle3D, PolygonError, polygonRayIntersection, polygonContainsConvex, polygonClosestPoint,
} from "../void3d/polygonCollider";

function flat(): Triangle3D {
	return { p0: vec3(0, 0, 0), p1: vec3(1, 0, 0), p2: vec3(0, 1, 0) };
}

function down(x: float32, y: float32, z: float32): Ray {
	return { origin: vec3(x, y, z), direction: vec3(0, 0, -1) };
}

function up(x: float32, y: float32, z: float32): Ray {
	return { origin: vec3(x, y, z), direction: vec3(0, 0, 1) };
}

function castIs(tri: Triangle3D, ray: Ray, oriented: boolean, expected: float32): boolean {
	const r = tri.rayIntersection(ray, oriented);
	if (expected == -1.0) { return r.ok && r.value == -1.0; }
	return r.ok && Math.abs(r.value - expected) < 1.0e-6;
}

test "triangle ray hits its front face and culls the back when oriented" {
	const tri = flat();
	assert castIs(tri, down(0.25, 0.25, 2), true, 2.0);
	assert castIs(tri, up(0.25, 0.25, -2), true, -1.0);
	assert castIs(tri, up(0.25, 0.25, -2), false, 2.0);
}

test "triangle ray misses outside the triangle, behind it and parallel to it" {
	const tri = flat();
	assert castIs(tri, down(0.8, 0.8, 2), true, -1.0);
	assert castIs(tri, down(0.25, 0.25, -2), true, -1.0);
	const behind = tri.rayIntersection(down(0.25, 0.25, -2), false);
	assert behind.ok && behind.value == -2.0;
	const along: Ray = { origin: vec3(-1, 0.25, 0), direction: vec3(1, 0, 0) };
	assert castIs(tri, along, false, -1.0);
}

test "a zero-area triangle is never hit and never contains" {
	const line: Triangle3D = { p0: vec3(0, 0, 0), p1: vec3(1, 0, 0), p2: vec3(2, 0, 0) };
	assert castIs(line, down(0.5, 0, 2), false, -1.0);
	const inside = line.containsProjected(vec3(0.5, 0, 0));
	assert inside.ok && !inside.value;
}

test "triangle contains by projection, ignoring the height above the plane" {
	const tri = flat();
	const above = tri.containsProjected(vec3(0.25, 0.25, 9));
	const outside = tri.containsProjected(vec3(0.8, 0.8, 0));
	assert above.ok && above.value;
	assert outside.ok && !outside.value;
}

function closestIs(tri: Triangle3D, point: Vec3, expected: Vec3): boolean {
	const r = tri.closestPoint(point);
	return r.ok && r.value == expected;
}

test "triangle closest point projects inside and clamps to an edge or a corner" {
	const tri = flat();
	assert closestIs(tri, vec3(0.25, 0.25, 3), vec3(0.25, 0.25, 0));
	assert closestIs(tri, vec3(2, 0, 1), vec3(1, 0, 0));
	assert closestIs(tri, vec3(-1, 0.5, 0), vec3(0, 0.5, 0));
	assert closestIs(tri, vec3(1, 1, 0), vec3(0.5, 0.5, 0));
	const line: Triangle3D = { p0: vec3(0, 0, 0), p1: vec3(0, 0, 0), p2: vec3(2, 0, 0) };
	assert closestIs(line, vec3(1, 3, 0), vec3(1, 0, 0));
}

function stacked(): Vec<float32> {
	return [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1, 1, 0, 1, 0, 1, 1];
}

test "a polygon walks its triangles last first, so only a best match is the nearest" {
	const positions: Vec<float32> = stacked();
	const indices: Vec<uint32> = [0, 1, 2, 3, 4, 5];
	const ray: Ray = up(0.25, 0.25, -2);
	const best = polygonRayIntersection(positions, indices, ray, true, false);
	const first = polygonRayIntersection(positions, indices, ray, false, false);
	assert best.ok && best.value == 2.0;
	assert first.ok && first.value == 3.0;
	const culled = polygonRayIntersection(positions, indices, ray, true, true);
	assert culled.ok && culled.value == -1.0;
}

function tetrahedron(): Vec<float32> {
	return [0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1];
}

test "a convex polygon contains the points behind every face" {
	const positions: Vec<float32> = tetrahedron();
	const indices: Vec<uint32> = [0, 2, 1, 0, 1, 3, 0, 3, 2, 1, 2, 3];
	const inside = polygonContainsConvex(positions, indices, vec3(0.1, 0.1, 0.1));
	const outside = polygonContainsConvex(positions, indices, vec3(1, 1, 1));
	const beside = polygonContainsConvex(positions, indices, vec3(-0.1, 0.1, 0.1));
	assert inside.ok && inside.value;
	assert outside.ok && !outside.value;
	assert beside.ok && !beside.value;
}

test "a polygon closest point is the nearest over its triangles" {
	const positions: Vec<float32> = stacked();
	const indices: Vec<uint32> = [0, 1, 2, 3, 4, 5];
	const r = polygonClosestPoint(positions, indices, vec3(0.25, 0.25, 0.8));
	assert r.ok && r.value == vec3(0.25, 0.25, 1);
}

test "a polygon refuses malformed buffers and empty meshes by name" {
	const positions: Vec<float32> = tetrahedron();
	const empty: Vec<uint32> = [];
	const partial: Vec<uint32> = [0, 1];
	const outOfRange: Vec<uint32> = [0, 1, 4];
	const ray: Ray = down(0, 0, 2);
	const a = polygonRayIntersection(positions, partial, ray, true, true);
	const b = polygonRayIntersection(positions, outOfRange, ray, true, true);
	const c = polygonContainsConvex(positions, empty, vec3(0, 0, 0));
	const d = polygonClosestPoint(positions, empty, vec3(0, 0, 0));
	assert !a.ok && a.error == PolygonError.NotTriangles;
	assert !b.ok && b.error == PolygonError.IndexRange;
	assert !c.ok && c.error == PolygonError.EmptyMesh;
	assert !d.ok && d.error == PolygonError.EmptyMesh;
	const bad: Triangle3D = { p0: vec3(NaN as float32, 0, 0), p1: vec3(1, 0, 0), p2: vec3(0, 1, 0) };
	const e = bad.rayIntersection(ray, true);
	assert !e.ok && e.error == PolygonError.NonFinite;
}
