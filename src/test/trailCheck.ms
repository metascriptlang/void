import { Mat4, identity, rotationX, rotationY, rotationZ, toMatrix } from "../math/math3d";
import { vertexCount, indexCount } from "../void3d/meshData";
import {
	Trail, TrailSettings, TrailError, sampleTrail, clearTrail, buildTrailMesh,
} from "../void3d/trail";

function makeTrail(settings: TrailSettings): Trail {
	const result = Trail.create(settings);
	if (!result.ok) { unreachable; }
	return result.value;
}

function position(x: float32): Mat4 {
	let world = identity();
	world.m41 = x;
	return world;
}

function near(a: float64, b: float64): boolean {
	return Math.abs(a - b) < 0.00001;
}

test "Trail defaults and less than three samples publish no ribbon" {
	const settings = TrailSettings.defaults();
	assert settings.duration == 0.5 && settings.angle == 0;
	assert settings.sizeStart == 4 && settings.sizeEnd == 0;
	assert settings.movementMin == 0.1 && settings.movementMax == 0.5;
	assert settings.smoothness == 0.5;
	let trail = makeTrail(settings);
	assert sampleTrail(trail, position(0), 0).ok;
	assert sampleTrail(trail, position(0.25), 0.25).ok;
	const mesh = buildTrailMesh(trail, 0.25);
	assert mesh.ok;
	assert mesh.value.vertexCount() == 0 && mesh.value.indexCount() == 0;
}

test "Trail strict movement thresholds retain pending point until next active sample" {
	let trail = makeTrail({ ...TrailSettings.defaults(), duration: 2, movementMin: 0.125 });
	assert sampleTrail(trail, position(0), 0).ok;
	assert sampleTrail(trail, position(0.125), 0.125).ok;
	assert trail.points.length == 2 && trail.points[1].size == 0;
	clearTrail(trail);
	assert sampleTrail(trail, position(0), 0).ok;
	assert sampleTrail(trail, position(0.5), 0.25).ok;
	assert trail.points.length == 1 && trail.pending.size == 1;
	assert trail.pending.x == 0.5 && trail.pending.t == 0.25;
	assert sampleTrail(trail, position(0.75), 0.5).ok;
	assert trail.points.length == 3 && trail.pending.size == 0;
	assert trail.points[1].x == 0.5 && trail.points[1].t == 0.25;
}

test "Trail stationary samples replace redundant zero width tails" {
	let trail = makeTrail({ ...TrailSettings.defaults(), duration: 100 });
	for (let i = 0; i < 20; i++) {
		assert sampleTrail(trail, position(0), i as float64).ok;
	}
	assert trail.points.length == 3;
	assert trail.points[0].size == 1;
	assert trail.points[1].size == 0 && trail.points[2].size == 0;
	assert trail.points[2].t == 19;
}

test "Trail pending smoothing caps subdivisions and preserves final endpoint" {
	let trail = makeTrail({ ...TrailSettings.defaults(), duration: 100 });
	assert sampleTrail(trail, position(0), 0).ok;
	assert sampleTrail(trail, position(16), 1).ok;
	assert trail.points.length == 1 && trail.pending.size == 1;
	assert sampleTrail(trail, position(16.25), 2).ok;
	assert trail.points.length == 22 && trail.pending.size == 0;
	assert near(trail.points[20].x, 16) && near(trail.points[20].t, 1);
	assert trail.points[21].x == 16.25;
	assert trail.points[10].x > 0 && trail.points[10].x < 16;
}

test "Trail expiration is strict and keeps last sample without a pending endpoint" {
	let trail = makeTrail(TrailSettings.defaults());
	assert sampleTrail(trail, position(0), 0).ok;
	assert sampleTrail(trail, position(0.25), 0.25).ok;
	assert sampleTrail(trail, position(0.375), 0.5).ok;
	assert trail.points.length == 3 && trail.points[0].t == 0;
	assert sampleTrail(trail, position(0.4375), 0.75).ok;
	assert trail.points[0].t == 0.25;
	assert sampleTrail(trail, position(0.4375), 10).ok;
	assert trail.points.length == 1 && trail.points[0].t == 10;
	clearTrail(trail);
	assert trail.points.length == 0;
	const mesh = buildTrailMesh(trail, 10);
	assert mesh.ok && mesh.value.vertexCount() == 0;
}

test "Trail world ribbon uses age width normals UV and primary index connectivity" {
	let trail = makeTrail({ ...TrailSettings.defaults(), duration: 1 });
	assert sampleTrail(trail, position(0), 0).ok;
	assert sampleTrail(trail, position(0.25), 0.125).ok;
	assert sampleTrail(trail, position(0.5), 0.25).ok;
	const mesh = buildTrailMesh(trail, 0.25);
	assert mesh.ok;
	const data = mesh.value;
	assert data.hasUvs && !data.hasSkin && !data.hasTangents;
	assert data.vertexCount() == 4 && data.indexCount() == 6;
	assert data.vertices[0] == 0 && data.vertices[1] == 0 && data.vertices[2] == -1.5;
	assert data.vertices[3] == 0 && data.vertices[4] == -1 && data.vertices[5] == 0;
	assert data.vertices[6] == 0.25 && data.vertices[7] == 0;
	assert data.vertices[14] == 1.5 && data.vertices[19] == 1;
	assert data.vertices[24] == 0.25 && data.vertices[26] == -1.75;
	assert data.indices[0] == 0 && data.indices[1] == 2 && data.indices[2] == 1;
	assert data.indices[3] == 2 && data.indices[4] == 3 && data.indices[5] == 1;
	assert data.bounds.min.z == -1.75 && data.bounds.max.z == 1.75;
	assert data.vertices[8] == 1 && data.vertices[11] == 1;
}

test "Trail orientation and angle rotate width with the sampled pose" {
	let trail = makeTrail({ ...TrailSettings.defaults(), duration: 1 });
	for (let i = 0; i < 3; i++) {
		let pose = rotationX(-1.5707963267948966);
		pose.m41 = (i as float32) * 0.25;
		assert sampleTrail(trail, pose, (i as float64) * 0.125).ok;
	}
	const mesh = buildTrailMesh(trail, 0.25);
	assert mesh.ok;
	assert near(mesh.value.vertices[1], -1.5) && near(mesh.value.vertices[2], 0);
	assert near(mesh.value.vertices[4], 0) && near(mesh.value.vertices[5], 1);
}

test "Trail noncollinear smoothing uses Bezier and normalized quaternion slerp" {
	let trail = makeTrail({ ...TrailSettings.defaults(), duration: 2 });
	assert sampleTrail(trail, position(0), 0).ok;
	let pending = rotationX(-1.5707963267948966);
	pending.m41 = 2;
	assert sampleTrail(trail, pending, 0.25).ok;
	let current = position(2);
	current.m43 = 2;
	assert sampleTrail(trail, current, 0.5).ok;
	assert trail.points.length == 5 && trail.pending.size == 1;
	const point = trail.points[2];
	assert near(point.x, 1.25) && near(point.z, -0.25) && point.y == 0;
	assert point.t == 0.125 && point.size == 1;
	const orientation = point.q.toMatrix();
	assert near(orientation.m22, 0.7071067811865476);
	assert near(orientation.m23, -0.7071067811865476);
	assert near(orientation.m32, 0.7071067811865476);
}

test "Trail matrix rotation extraction handles each nonpositive trace branch" {
	const poses: Vec<Mat4> = [
		rotationX(3.141592653589793), rotationY(3.141592653589793),
		rotationZ(3.141592653589793),
	];
	for (let axis = 0; axis < 3; axis++) {
		let trail = makeTrail({ ...TrailSettings.defaults(), duration: 1 });
		for (let i = 0; i < 3; i++) {
			let pose = poses[axis];
			pose.m41 = (i as float32) * 0.25;
			assert sampleTrail(trail, pose, (i as float64) * 0.125).ok;
		}
		const mesh = buildTrailMesh(trail, 0.25);
		assert mesh.ok;
		assert near(mesh.value.vertices[2], axis == 2 ? -1.5 : 1.5);
		assert near(mesh.value.vertices[4], axis == 2 ? -1.0 : 1.0);
	}
}

test "Trail clear leaves pending marker for next sample to discard as in primary" {
	let trail = makeTrail(TrailSettings.defaults());
	assert sampleTrail(trail, position(0), 0).ok;
	assert sampleTrail(trail, position(1), 0.25).ok;
	assert trail.pending.size == 1;
	clearTrail(trail);
	assert trail.points.length == 0 && trail.pending.size == 1;
	assert sampleTrail(trail, position(2), 0.5).ok;
	assert trail.points.length == 1 && trail.points[0].x == 2 && trail.pending.size == 0;
}

test "Trail geometry refuses a finite history whose expanded corners exceed float32" {
	let trail = makeTrail({
		...TrailSettings.defaults(), duration: 1, sizeStart: 3.0e38, sizeEnd: 3.0e38,
	});
	for (let i = 0; i < 3; i++) {
		let world = position((i as float32) * 0.25);
		world.m43 = 3.0e38;
		assert sampleTrail(trail, world, (i as float64) * 0.125).ok;
	}
	const mesh = buildTrailMesh(trail, 0.25);
	assert !mesh.ok && mesh.error == TrailError.Geometry;
	assert trail.points.length == 3;
}

test "Trail refuses nonfinite and unsafe settings before changing history" {
	assert !Trail.create({ ...TrailSettings.defaults(), duration: 0 }).ok;
	assert !Trail.create({ ...TrailSettings.defaults(), movementMax: 0 }).ok;
	let trail = makeTrail(TrailSettings.defaults());
	assert sampleTrail(trail, position(0), 0).ok;
	let bad = identity();
	bad.m41 = (1.0 / 0.0) as float32;
	const invalid = sampleTrail(trail, bad, 0.25);
	assert !invalid.ok && invalid.error == TrailError.Transform;
	assert trail.points.length == 1 && trail.points[0].t == 0;
	assert !sampleTrail(trail, position(0), 1.0 / 0.0).ok;
	trail.settings.duration = 0;
	const settings = sampleTrail(trail, position(0.25), 0.25);
	assert !settings.ok && settings.error == TrailError.Settings;
	assert trail.points.length == 1;
	assert !buildTrailMesh(trail, 0.25).ok;
}
