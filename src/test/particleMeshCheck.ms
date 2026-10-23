import { readFile } from "std/fs";
import { JsonValue } from "std/serialize/json/types";
import { Vec3, vec3, Mat4, translation } from "../math/math3d";
import {
	ParticleSystemAsset, ParticleSortMode, RenderMode, RenderAlignment, SimulationSpace,
	MeshDistribution,
} from "../particles/asset";
import { constantCurve } from "../particles/curve";
import {
	ParticleSystem, playSystem, updateSystem, mix, POS_X, POS_Y, POS_Z, SIZE_X,
} from "../particles/system";
import {
	Camera3D, CameraBasis, CameraView, ProjectionKind, resolve,
} from "../void3d/camera";
import {
	writeParticles, ParticleWriter3D, ParticleWriteError, PARTICLE_MESH_INSTANCE_STRIDE,
	PARTICLE_VISUAL_INSTANCE_STRIDE,
} from "../void3d/particleWriter";
import { writeMeshParticles, meshIndexOf } from "../void3d/particleMeshWriter";

// Each m3d_ golden in tests/unity/goldens is a group of Mesh-mode particles seen by a placed
// camera, from a moved and turned emitter; Unity's BakeMesh gives every particle's world vertices
// one mesh after the other. The replay runs Void's simulation, writes the instances and maps the
// recorded mesh vertices through each instance's affine, then compares them with Unity's. Unity
// is left-handed and Void right-handed, so every point crosses with z negated.

// Flip to true once the m3d_ goldens are captured: a missing golden then fails the replay.
const REQUIRE_GOLDENS: boolean = false;
const GOLDEN_DIR: string = "tests/unity/goldens/";
const SEED: uint32 = 12345;
const TOL: float32 = 1e-3;
const TEXEL_WIDTH: int32 = 300;
const TEXEL_HEIGHT: int32 = 200;
const MAX_PARTICLE_DT: float32 = 0.03;
const DEGREE: float32 = 0.017453292519943295;
const ALIGNMENTS: string[5] = ["view", "world", "local", "facing", "velocity"];

function caseNames(): Vec<string> {
	let names: Vec<string> = [];
	for (const al of ALIGNMENTS) {
		names.push(`m3d_${al}`);
		names.push(`m3d_ortho_${al}`);
		names.push(`m3d_localsim_${al}`);
		names.push(`m3d_pose2_${al}`);
	}
	for (const al of ["view", "world", "local"]) { names.push(`m3d_pivot_${al}`); }
	for (const k of ["m3d_localsim_pivot_world", "m3d_flip_x", "m3d_flip_y", "m3d_flip_z",
		"m3d_flip_xyz", "m3d_negsize_x", "m3d_size_uniform", "m3d_rot3d_off", "m3d_rot_x30",
		"m3d_rot_y30", "m3d_rot_z30", "m3d_two_meshes"]) {
		names.push(k);
	}
	return names;
}

function golden(name: string): JsonValue {
	const text = readFile(`${GOLDEN_DIR}${name}.json`);
	if (!text.ok) { unreachable; }
	const parsed = JSON.parseValue(text.value);
	if (!parsed.ok) { unreachable; }
	return parsed.value;
}

function present(name: string): boolean {
	return readFile(`${GOLDEN_DIR}${name}.json`).ok;
}

function numberAt(v: JsonValue, k: int32): float32 {
	return v.at(k).asNumber() as float32;
}

function unityVec(v: JsonValue): Vec3 {
	return vec3(numberAt(v, 0), numberAt(v, 1), numberAt(v, 2));
}

function flipped(v: JsonValue): Vec3 {
	return vec3(numberAt(v, 0), numberAt(v, 1), -numberAt(v, 2));
}

function radians(v: float32): float32 {
	return v * DEGREE;
}

function alignmentOf(name: string): RenderAlignment {
	if (name == "View") { return RenderAlignment.View; }
	if (name == "World") { return RenderAlignment.World; }
	if (name == "Local") { return RenderAlignment.Local; }
	if (name == "Facing") { return RenderAlignment.Facing; }
	if (name == "Velocity") { return RenderAlignment.Velocity; }
	console.log(`unity parity: alignment ${name} has no mesh case`);
	unreachable;
}

// The asset the capture builds: no shape, a burst of identical particles at t = 0 drifting with
// a constant velocity, one to four meshes.
function assetOf(settings: JsonValue): ParticleSystemAsset {
	const sim: SimulationSpace = settings.getDynamicField("simulationSpace").asString() == "Local" ?
		SimulationSpace.Local : SimulationSpace.World;
	const count: int32 = settings.getDynamicField("particleCount").asNumber() as int32;
	let a = ParticleSystemAsset.defaults();
	a.main.duration = 5.0;
	a.main.loop = true;
	a.main.startLifetime = constantCurve(5.0);
	a.main.startSpeed = constantCurve(0.0);
	a.main.maxParticles = 1000;
	a.main.simulationSpace = sim;
	a.shape.enabled = false;
	a.emission.rateOverTime = constantCurve(0.0);
	a.emission.bursts = [{
		time: 0.0, count: constantCurve(count as float32), cycleCount: 1, repeatInterval: 0.01,
		probability: 1.0,
	}];
	const size: Vec3 = unityVec(settings.getDynamicField("startSize3D"));
	a.main.startSize3D = true;
	a.main.startSizeX = constantCurve(size.x);
	a.main.startSizeY = constantCurve(size.y);
	a.main.startSizeZ = constantCurve(size.z);
	if (settings.getDynamicField("startRotation3D").asBoolean()) {
		const rot: Vec3 = unityVec(settings.getDynamicField("startRotationDeg"));
		a.main.startRotation3D = true;
		a.main.startRotationX = constantCurve(radians(rot.x));
		a.main.startRotationY = constantCurve(radians(rot.y));
		a.main.startRotationZ = constantCurve(radians(rot.z));
	} else {
		a.main.startRotationZ = constantCurve(
			radians(settings.getDynamicField("startRotationZDeg").asNumber() as float32));
	}
	const velocity: Vec3 = unityVec(settings.getDynamicField("velocity"));
	a.velocityOverLifetime.enabled = true;
	a.velocityOverLifetime.space = sim;
	a.velocityOverLifetime.x = constantCurve(velocity.x);
	a.velocityOverLifetime.y = constantCurve(velocity.y);
	a.velocityOverLifetime.z = constantCurve(-velocity.z);
	a.renderer.renderMode = RenderMode.Mesh;
	a.renderer.alignment = alignmentOf(settings.getDynamicField("alignment").asString());
	a.renderer.pivot = unityVec(settings.getDynamicField("pivot"));
	a.renderer.flip = unityVec(settings.getDynamicField("flip"));
	const meshes = settings.getDynamicField("meshes");
	const weights = settings.getDynamicField("meshWeights");
	a.renderer.meshCount = meshes.length() as int32;
	for (let k = 0; k < (weights.length() as int32); k++) {
		a.renderer.meshWeights[k] = numberAt(weights, k);
	}
	if (settings.getDynamicField("meshDistribution").asString() == "NonUniformRandom") {
		a.renderer.meshDistribution = MeshDistribution.NonUniformRandom;
	}
	return a;
}

function emitterWorld(e: JsonValue): Mat4 {
	const right: Vec3 = flipped(e.getDynamicField("right"));
	const up: Vec3 = flipped(e.getDynamicField("up"));
	const forward: Vec3 = flipped(e.getDynamicField("forward"));
	const at: Vec3 = flipped(e.getDynamicField("pos"));
	return {
		m11: right.x, m12: right.y, m13: right.z, m14: 0.0,
		m21: up.x, m22: up.y, m23: up.z, m24: 0.0,
		m31: -forward.x, m32: -forward.y, m33: -forward.z, m34: 0.0,
		m41: at.x, m42: at.y, m43: at.z, m44: 1.0,
	};
}

function viewOf(cam: JsonValue): CameraView {
	const orientation: CameraBasis = {
		right: flipped(cam.getDynamicField("right")),
		up: flipped(cam.getDynamicField("up")),
		forward: flipped(cam.getDynamicField("forward")),
	};
	let camera: Camera3D = {
		position: flipped(cam.getDynamicField("pos")), yaw: 0.0, pitch: 0.0,
		orientation: orientation, nearPlane: 0.1, farPlane: 200.0,
		projection: { kind: ProjectionKind.Perspective, fovY: 1.0 },
	};
	if (cam.getDynamicField("orthographic").asBoolean()) {
		const half: float32 = cam.getDynamicField("orthographicSize").asNumber() as float32;
		const height: float32 = 2.0 * half;
		camera.projection = {
			kind: ProjectionKind.Orthographic, worldPerTexel: height / (TEXEL_HEIGHT as float32),
			snap: false,
		};
	} else {
		camera.projection = {
			kind: ProjectionKind.Perspective,
			fovY: (cam.getDynamicField("fov").asNumber() * 0.017453292519943295) as float32,
		};
	}
	const resolved = camera.resolve(TEXEL_WIDTH, TEXEL_HEIGHT);
	if (!resolved.ok) { unreachable; }
	return resolved.value;
}

// A mesh vertex (already in Void's frame) through instance `inst`'s affine rows.
function through(out: Vec<float32>, inst: int32, v: Vec3): Vec3 {
	const at: int32 = inst * PARTICLE_MESH_INSTANCE_STRIDE;
	return vec3(
		out[at] * v.x + out[at + 1] * v.y + out[at + 2] * v.z + out[at + 3],
		out[at + 4] * v.x + out[at + 5] * v.y + out[at + 6] * v.z + out[at + 7],
		out[at + 8] * v.x + out[at + 9] * v.y + out[at + 10] * v.z + out[at + 11]);
}

function close(a: Vec3, b: Vec3): boolean {
	return Math.abs(a.x - b.x) <= TOL && Math.abs(a.y - b.y) <= TOL && Math.abs(a.z - b.z) <= TOL;
}

// Whether the baked vertices from `at` are `mesh` through instance `inst`'s affine.
function matches(
	out: Vec<float32>, inst: int32, mesh: JsonValue, baked: JsonValue, at: int32,
): boolean {
	const n: int32 = mesh.length() as int32;
	if (at + n > (baked.length() as int32)) { return false; }
	for (let v = 0; v < n; v++) {
		if (!close(through(out, inst, flipped(mesh.at(v))), flipped(baked.at(at + v)))) {
			return false;
		}
	}
	return true;
}

// Replays `name`; returns how many frames disagree, printing the first. A particle's mesh is the
// one whose vertices its instance maps onto the next baked vertices, because Unity does not say.
function replay(name: string): int32 {
	const g = golden(name);
	const dt: float64 = g.getDynamicField("dt").asNumber();
	const frames = g.getDynamicField("frames");
	const settings = g.getDynamicField("settings");
	const meshes = settings.getDynamicField("meshes");
	const count: int32 = settings.getDynamicField("particleCount").asNumber() as int32;
	const bakedKey: string = settings.getDynamicField("simulationSpace").asString() == "Local" ?
		"bakedMeshXform" : "bakedMesh";
	const substeps: int32 = Math.ceil(((dt as float32) / MAX_PARTICLE_DT) as float64) as int32;
	const made = ParticleSystem.create(assetOf(settings), SEED);
	if (!made.ok) { unreachable; }
	let sys = made.value;
	sys.clock.fixedStep = dt / (substeps as float64);
	sys.clock.maxFrameTime = 1.0;
	let writer = ParticleWriter3D.create();
	let out: Vec<float32> = new Array(PARTICLE_MESH_INSTANCE_STRIDE * count);
	let perMesh: Vec<int32> = [0, 0, 0, 0];
	let bad: int32 = 0;
	for (let k = 0; k < (frames.length() as int32); k++) {
		const frame = frames.at(k);
		const pose = frame.getDynamicField("pose");
		const world: Mat4 = emitterWorld(pose.getDynamicField("emitter"));
		if (k == 0) {
			playSystem(sys, world);
			continue;
		}
		for (let s = 0; s < substeps; s++) {
			const done = updateSystem(sys, dt / (substeps as float64), world);
			if (!done.ok) { unreachable; }
		}
		const view = viewOf(pose.getDynamicField("camera"));
		const written = writeMeshParticles(
			writer, sys, view.eye, view.basis.forward, view.basis.up, vec3(0.0, 0.0, 0.0), out,
			perMesh);
		if (!written.ok || written.value != count) {
			const got: int32 = written.ok ? written.value : -1;
			console.log(`unity parity: ${name} frame ${k}: wrote ${got} of ${count}`);
			bad = bad + 1;
			continue;
		}
		// Identical particles share an affine, so instance 0 stands for all.
		const baked = frame.getDynamicField(bakedKey);
		let at: int32 = 0;
		let found: int32 = 0;
		while (at < (baked.length() as int32)) {
			let took: int32 = 0;
			for (let m = 0; m < (meshes.length() as int32) && took == 0; m++) {
				if (matches(out, 0, meshes.at(m), baked, at)) {
					took = meshes.at(m).length() as int32;
				}
			}
			if (took == 0) { break; }
			at = at + took;
			found = found + 1;
		}
		if (at != (baked.length() as int32) || found != count) {
			bad = bad + 1;
			if (bad == 1) {
				const seen: int32 = baked.length() as int32;
				console.log(`unity parity: ${name} frame ${k}: ${found} of ${count} particles `
					+ `matched, ${at} of ${seen} baked vertices`);
			}
		}
	}
	return bad;
}

test "every Unity mesh-mode golden replays through the writer at 1e-3" {
	const names = caseNames();
	let found: int32 = 0;
	let bad: int32 = 0;
	for (const name of names) {
		if (!present(name)) { continue; }
		found = found + 1;
		bad = bad + replay(name);
	}
	console.log(`unity parity: found ${found} of ${names.length} m3d goldens`);
	if (REQUIRE_GOLDENS) { assert found == (names.length as int32); }
	assert bad == 0;
}

// ---- pure CPU: no golden needed ----

function near(a: float32, b: float32): boolean {
	const d: float32 = a - b;
	return d < 1e-4 && d > -1e-4;
}

// One drifting-nowhere mesh particle at the origin of a World-space system.
function one(meshes: int32): ParticleSystemAsset {
	let a = ParticleSystemAsset.defaults();
	a.main.duration = 10.0;
	a.main.startLifetime = constantCurve(10.0);
	a.main.startSpeed = constantCurve(0.0);
	a.main.simulationSpace = SimulationSpace.World;
	a.shape.enabled = false;
	a.emission.rateOverTime = constantCurve(0.0);
	a.emission.bursts = [{
		time: 0.0, count: constantCurve(1.0), cycleCount: 1, repeatInterval: 0.01, probability: 1.0,
	}];
	a.main.startSize3D = true;
	a.main.startSizeX = constantCurve(2.0);
	a.main.startSizeY = constantCurve(3.0);
	a.main.startSizeZ = constantCurve(4.0);
	a.renderer.renderMode = RenderMode.Mesh;
	a.renderer.alignment = RenderAlignment.World;
	a.renderer.meshCount = meshes;
	return a;
}

function started(a: ParticleSystemAsset): ParticleSystem {
	const made = ParticleSystem.create(a, 9);
	if (!made.ok) { unreachable; }
	let sys = made.value;
	sys.clock.fixedStep = 1.0 / 60.0;
	playSystem(sys, translation(0.0, 0.0, 0.0));
	const done = updateSystem(sys, 1.0 / 60.0, translation(0.0, 0.0, 0.0));
	if (!done.ok) { unreachable; }
	return sys;
}

// A stream of particles from an emitter walking along +z and +x, so each has its own place.
function walked(a: ParticleSystemAsset): ParticleSystem {
	const made = ParticleSystem.create(a, 9);
	if (!made.ok) { unreachable; }
	let sys = made.value;
	sys.clock.fixedStep = 1.0 / 60.0;
	playSystem(sys, translation(0.0, 0.0, 0.0));
	for (let k = 1; k <= 48; k++) {
		const step: float32 = k as float32;
		const done = updateSystem(sys, 1.0 / 60.0, translation(0.3 * step, 0.0, step));
		if (!done.ok) { unreachable; }
	}
	return sys;
}

const EYE: Vec3 = { x: 0.0, y: 0.0, z: -10.0 };
const FORWARD: Vec3 = { x: 0.0, y: 0.0, z: 1.0 };
const UP: Vec3 = { x: 0.0, y: 1.0, z: 0.0 };
const STILL: Vec3 = { x: 0.0, y: 0.0, z: 0.0 };

test "a World-aligned unrotated mesh is its size on the diagonal, at the particle" {
	const sys = started(one(1));
	let w = ParticleWriter3D.create();
	let out: Vec<float32> = new Array(PARTICLE_MESH_INSTANCE_STRIDE);
	let counts: Vec<int32> = [0, 0, 0, 0];
	const n = writeMeshParticles(w, sys, EYE, FORWARD, UP, STILL, out, counts);
	assert n.ok && n.value == 1 && counts[0] == 1;
	assert near(out[0], 2.0) && near(out[1], 0.0) && near(out[2], 0.0) && near(out[3], 0.0);
	assert near(out[4], 0.0) && near(out[5], 3.0) && near(out[6], 0.0) && near(out[7], 0.0);
	assert near(out[8], 0.0) && near(out[9], 0.0) && near(out[10], 4.0) && near(out[11], 0.0);
	assert near(out[12], 1.0) && near(out[15], 1.0);
}

// The assumed rotation convention, to be confirmed by the m3d_rot_* goldens: a positive value
// turns clockwise along the axis in Unity's frame, and Void's rows are that matrix with z negated.
test "a rotation about z or y turns the sized axes as Unity's frame does, then crosses the mirror" {
	let a = one(1);
	a.main.startRotation3D = true;
	a.main.startRotationZ = constantCurve(1.5707963267948966);
	let sys = started(a);
	let w = ParticleWriter3D.create();
	let out: Vec<float32> = new Array(PARTICLE_MESH_INSTANCE_STRIDE);
	let counts: Vec<int32> = [0, 0, 0, 0];
	assert writeMeshParticles(w, sys, EYE, FORWARD, UP, STILL, out, counts).ok;
	assert near(out[0], 0.0) && near(out[1], 3.0) && near(out[4], -2.0) && near(out[5], 0.0);
	assert near(out[10], 4.0);
	a.main.startRotationZ = constantCurve(0.0);
	a.main.startRotationY = constantCurve(1.5707963267948966);
	sys = started(a);
	assert writeMeshParticles(w, sys, EYE, FORWARD, UP, STILL, out, counts).ok;
	assert near(out[2], 4.0) && near(out[5], 3.0) && near(out[8], -2.0) && near(out[0], 0.0);
}

test "instances are grouped by mesh index in mesh order and keep the draw order inside a group" {
	let a = one(3);
	a.emission.rateOverTime = constantCurve(60.0);
	a.emission.bursts = [];
	a.main.simulationSpace = SimulationSpace.World;
	let sys = walked(a);
	assert sys.count >= 30;
	const total: int32 = sys.count;
	let w = ParticleWriter3D.create();
	let out: Vec<float32> = new Array(PARTICLE_MESH_INSTANCE_STRIDE * total);
	let counts: Vec<int32> = [0, 0, 0, 0];
	const n = writeMeshParticles(w, sys, EYE, FORWARD, UP, STILL, out, counts);
	assert n.ok && n.value == total;
	assert counts[0] + counts[1] + counts[2] == total && counts[3] == 0;
	assert counts[0] > 0 && counts[1] > 0 && counts[2] > 0;
	// With no sorting the draw order is the particle order: group m holds, in order, exactly the
	// particles whose seed draws mesh m, each at its own position.
	let at: int32 = 0;
	const cap: int32 = sys.capacity;
	for (let m = 0; m < 3; m++) {
		for (let i = 0; i < total; i++) {
			if (meshIndexOf(sys.asset.renderer, sys.seeds[i]) != m) { continue; }
			const base: int32 = at * PARTICLE_MESH_INSTANCE_STRIDE;
			assert near(out[base + 3], sys.data[POS_X * cap + i]);
			assert near(out[base + 7], sys.data[POS_Y * cap + i]);
			assert near(out[base + 11], sys.data[POS_Z * cap + i]);
			at = at + 1;
		}
	}
	assert at == total;
}

test "distance sorting orders each mesh's group far to near" {
	let a = one(2);
	a.emission.rateOverTime = constantCurve(60.0);
	a.emission.bursts = [];
	a.renderer.sortMode = ParticleSortMode.Distance;
	const sys = walked(a);
	const total: int32 = sys.count;
	let w = ParticleWriter3D.create();
	let out: Vec<float32> = new Array(PARTICLE_MESH_INSTANCE_STRIDE * total);
	let counts: Vec<int32> = [0, 0, 0, 0];
	assert writeMeshParticles(w, sys, EYE, FORWARD, UP, STILL, out, counts).ok;
	assert counts[0] > 1 && counts[1] > 1;
	let at: int32 = 0;
	for (let m = 0; m < 2; m++) {
		let previous: float32 = 1e30;
		for (let j = 0; j < counts[m]; j++) {
			const base: int32 = at * PARTICLE_MESH_INSTANCE_STRIDE;
			const d: Vec3 = vec3(
				out[base + 3] - EYE.x, out[base + 7] - EYE.y, out[base + 11] - EYE.z);
			const far: float32 = d.length();
			assert far <= previous + 1e-4;
			previous = far;
			at = at + 1;
		}
	}
}

test "uniform draws spread the meshes evenly over many seeds" {
	let a = one(4);
	let seen: Vec<int32> = [0, 0, 0, 0];
	for (let s = 0; s < 4000; s++) {
		const m: int32 = meshIndexOf(a.renderer, mix(s as uint32, 77));
		assert m >= 0 && m < 4;
		seen[m] = seen[m] + 1;
	}
	for (let m = 0; m < 4; m++) { assert seen[m] > 900 && seen[m] < 1100; }
}

test "weighted draws follow the weights to 3 percent and never pick a zero weight" {
	let a = one(4);
	a.renderer.meshDistribution = MeshDistribution.NonUniformRandom;
	a.renderer.meshWeights = [1.0, 3.0, 0.0, 6.0];
	let seen: Vec<int32> = [0, 0, 0, 0];
	for (let s = 0; s < 10000; s++) {
		const m: int32 = meshIndexOf(a.renderer, mix(s as uint32, 77));
		seen[m] = seen[m] + 1;
	}
	assert seen[2] == 0;
	assert seen[0] > 700 && seen[0] < 1300;
	assert seen[1] > 2700 && seen[1] < 3300;
	assert seen[3] > 5700 && seen[3] < 6300;
}

test "a short out, a short counts, another mode and a non-finite size are refused" {
	const sys = started(one(2));
	let w = ParticleWriter3D.create();
	let out: Vec<float32> = new Array(PARTICLE_MESH_INSTANCE_STRIDE);
	let counts: Vec<int32> = [0, 0];
	let short: Vec<float32> = new Array(PARTICLE_MESH_INSTANCE_STRIDE - 1);
	const tooShort = writeMeshParticles(w, sys, EYE, FORWARD, UP, STILL, short, counts);
	assert !tooShort.ok && tooShort.error == ParticleWriteError.ShortInstances;
	let fewer: Vec<int32> = [0];
	const fewCounts = writeMeshParticles(w, sys, EYE, FORWARD, UP, STILL, out, fewer);
	assert !fewCounts.ok && fewCounts.error == ParticleWriteError.ShortInstances;
	const ok = writeMeshParticles(w, sys, EYE, FORWARD, UP, STILL, out, counts);
	assert ok.ok;
	let bad = started(one(2));
	bad.data[SIZE_X * bad.capacity] = Number.NaN as float32;
	const nan = writeMeshParticles(w, bad, EYE, FORWARD, UP, STILL, out, counts);
	assert !nan.ok && nan.error == ParticleWriteError.NonFinite;
	let billboard = one(2);
	billboard.renderer.renderMode = RenderMode.Billboard;
	const refused = writeMeshParticles(w, started(billboard), EYE, FORWARD, UP, STILL, out, counts);
	assert !refused.ok && refused.error == ParticleWriteError.UnsupportedRenderMode;
	let visual: Vec<float32> = new Array(PARTICLE_VISUAL_INSTANCE_STRIDE);
	const other = writeParticles(
		w, started(one(2)), [{ u: 0.0, v: 0.0, u2: 1.0, v2: 1.0 }], EYE, FORWARD, STILL, visual);
	assert !other.ok && other.error == ParticleWriteError.UnsupportedRenderMode;
}
