import { vec3, translation, rotationY } from "../math/math3d";
import {
	ParticleSystemAsset, ParticleSortMode, RenderMode, RenderAlignment, SimulationSpace,
} from "../particles/asset";
import { constantCurve, constantColor, rgbaColor, twoConstants } from "../particles/curve";
import { ParticleSystem, playSystem, updateSystem, POS_Z, AGE, SIZE_X } from "../particles/system";
import { TrailChains, buildTrails } from "../particles/trail";
import { AtlasTile } from "../void3d/billboard";
import {
	ParticleWriter3D, ParticleWriteError, PARTICLE_INSTANCE_STRIDE, PARTICLE_VISUAL_INSTANCE_STRIDE, writeParticles, writeParticlePoints, writeTrails, sheetTiles,
} from "../void3d/particleWriter";

const WHOLE: AtlasTile = { u: 0.0, v: 0.0, u2: 1.0, v2: 1.0 };

function near(a: float32, b: float32): boolean {
	const d: float32 = a - b;
	return d < 1e-5 && d > -1e-5;
}

// Particles at rest along +z, one a step, each living long.
function row(): ParticleSystemAsset {
	let a = ParticleSystemAsset.defaults();
	a.main.duration = 10.0;
	a.main.startLifetime = constantCurve(10.0);
	a.main.startSpeed = constantCurve(0.0);
	a.main.startSizeX = constantCurve(2.0);
	a.main.startColor = constantColor(rgbaColor(1.0, 0.5, 0.25, 0.75));
	a.main.startRotationZ = constantCurve(0.25);
	a.main.simulationSpace = SimulationSpace.World;
	a.shape.enabled = false;
	a.emission.rateOverTime = constantCurve(60.0);
	return a;
}

// Three particles, emitted while the emitter walks along +z one unit a step.
function walked(a: ParticleSystemAsset): ParticleSystem {
	const made = ParticleSystem.create(a, 9);
	if (!made.ok) { unreachable; }
	let sys = made.value;
	sys.clock.fixedStep = 1.0 / 60.0;
	playSystem(sys, translation(0.0, 0.0, 0.0));
	for (let k = 1; k <= 3; k++) {
		const done = updateSystem(sys, 1.0 / 60.0, translation(0.0, 0.0, k as float32));
		if (!done.ok) { unreachable; }
	}
	return sys;
}

test "a billboard instance carries position, size, rotation, uv and colour in the visual layout" {
	const sys = walked(row());
	let w = ParticleWriter3D.create();
	let out: Vec<float32> = new Array(PARTICLE_VISUAL_INSTANCE_STRIDE * sys.count);
	const n = writeParticles(w, sys, [WHOLE], vec3(0.0, 0.0, -10.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 0.0), out);
	assert n.ok && n.value == sys.count && sys.count >= 2;
	assert near(out[3], 2.0) && near(out[4], 2.0);
	assert near(out[5], 0.0) && near(out[6], 0.0);
	assert near(out[7], 0.25);
	assert near(out[8], 0.0) && near(out[10], 1.0);
	assert near(out[12], 1.0) && near(out[13], 0.5) && near(out[14], 0.25) && near(out[15], 0.75);
}

test "distance sorting draws the farthest particle first" {
	let a = row();
	a.renderer.sortMode = ParticleSortMode.Distance;
	const sys = walked(a);
	let w = ParticleWriter3D.create();
	let out: Vec<float32> = new Array(PARTICLE_VISUAL_INSTANCE_STRIDE * sys.count);
	const eye = vec3(0.0, 0.0, -10.0);
	const n = writeParticles(w, sys, [WHOLE], eye, vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 0.0), out);
	assert n.ok;
	for (let k = 1; k < n.value; k++) { assert out[k * PARTICLE_VISUAL_INSTANCE_STRIDE + 2] <= out[(k - 1) * PARTICLE_VISUAL_INSTANCE_STRIDE + 2]; }
	const back = writeParticles(w, sys, [WHOLE], vec3(0.0, 0.0, 10.0), vec3(0.0, 0.0, -1.0), vec3(0.0, 0.0, 0.0), out);
	assert back.ok;
	for (let k = 1; k < back.value; k++) { assert out[k * PARTICLE_VISUAL_INSTANCE_STRIDE + 2] >= out[(k - 1) * PARTICLE_VISUAL_INSTANCE_STRIDE + 2]; }
}

test "oldest in front draws the youngest first" {
	let a = row();
	a.renderer.sortMode = ParticleSortMode.OldestInFront;
	const sys = walked(a);
	let w = ParticleWriter3D.create();
	let out: Vec<float32> = new Array(PARTICLE_VISUAL_INSTANCE_STRIDE * sys.count);
	const n = writeParticles(w, sys, [WHOLE], vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 0.0), out);
	assert n.ok;
	// The youngest was emitted last, nearest the emitter's last place at z = 3.
	for (let k = 1; k < n.value; k++) { assert out[k * PARTICLE_VISUAL_INSTANCE_STRIDE + 2] <= out[(k - 1) * PARTICLE_VISUAL_INSTANCE_STRIDE + 2]; }
}

// Slots in the order a stable sort by ascending `keys` puts them.
function stableOrder(keys: Vec<float32>): Vec<int32> {
	let order: Vec<int32> = [];
	for (let i = 0; i < (keys.length as int32); i++) {
		let at: int32 = order.length as int32;
		while (at > 0 && keys[order[at - 1]] > keys[i]) { at = at - 1; }
		order.push(0);
		for (let k = (order.length as int32) - 1; k > at; k--) { order[k] = order[k - 1]; }
		order[at] = i;
	}
	return order;
}

// Bursts of eight a tenth of a second apart, each particle its own size, moving either way
// along z at its own speed, so depths cross the eye and ages tie within a burst.
function crossing(mode: ParticleSortMode): ParticleSystem {
	let a = row();
	a.renderer.sortMode = mode;
	a.emission.rateOverTime = constantCurve(0.0);
	a.emission.bursts = [{ time: 0.0, count: constantCurve(8.0), cycleCount: 6, repeatInterval: 0.1, probability: 1.0 }];
	a.main.startSpeed = twoConstants(-3.0, 3.0);
	a.main.startSizeX = twoConstants(1.0, 2.0);
	const made = ParticleSystem.create(a, 17);
	if (!made.ok) { unreachable; }
	let sys = made.value;
	sys.clock.fixedStep = 1.0 / 60.0;
	playSystem(sys, translation(0.0, 0.0, 0.0));
	for (let k = 0; k < 40; k++) {
		const done = updateSystem(sys, 1.0 / 60.0, translation(0.0, 0.0, 0.0));
		if (!done.ok) { unreachable; }
	}
	return sys;
}

test "sorting orders keys of either sign and keeps tied particles in slot order" {
	for (const mode of [ParticleSortMode.Depth, ParticleSortMode.OldestInFront]) {
		const sys = crossing(mode);
		assert sys.count >= 16;
		const cap: int32 = sys.capacity;
		let keys: Vec<float32> = [];
		for (let i = 0; i < sys.count; i++) {
			keys.push(mode == ParticleSortMode.Depth ? -sys.data[POS_Z * cap + i] : sys.data[AGE * cap + i]);
		}
		const expected = stableOrder(keys);
		let w = ParticleWriter3D.create();
		let out: Vec<float32> = new Array(PARTICLE_INSTANCE_STRIDE * sys.count);
		const n = writeParticlePoints(w, sys, vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), out);
		assert n.ok && n.value == sys.count;
		for (let k = 0; k < sys.count; k++) {
			assert out[k * PARTICLE_INSTANCE_STRIDE + 3] == sys.data[SIZE_X * cap + expected[k]];
		}
	}
}

test "a local system's particles follow the emitter" {
	let a = row();
	a.main.simulationSpace = SimulationSpace.Local;
	a.emission.rateOverTime = constantCurve(0.0);
	a.emission.bursts = [{ time: 0.0, count: constantCurve(1.0), cycleCount: 1, repeatInterval: 0.01, probability: 1.0 }];
	const sys = walked(a);
	let w = ParticleWriter3D.create();
	let out: Vec<float32> = new Array(PARTICLE_VISUAL_INSTANCE_STRIDE);
	const n = writeParticles(w, sys, [WHOLE], vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 0.0), out);
	assert n.ok && n.value == 1;
	assert near(out[2], 3.0);
}

test "the sheet frame picks its tile and every flip mirrors the uv" {
	let a = row();
	a.textureSheetAnimation.enabled = true;
	a.textureSheetAnimation.numTilesX = 2;
	a.textureSheetAnimation.numTilesY = 2;
	a.textureSheetAnimation.frameOverTime = constantCurve(0.6);
	a.renderer.flip = vec3(1.0, 0.0, 0.0);
	const sys = walked(a);
	const tiles = sheetTiles(WHOLE, 2, 2);
	let w = ParticleWriter3D.create();
	let out: Vec<float32> = new Array(PARTICLE_VISUAL_INSTANCE_STRIDE * sys.count);
	const n = writeParticles(w, sys, tiles, vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 0.0), out);
	assert n.ok;
	// 0.6 of 4 frames is frame 2, the bottom-left quarter, mirrored in u.
	assert near(out[8], 0.5) && near(out[10], 0.0);
	assert near(out[9], 0.5) && near(out[11], 1.0);
}

test "an instance carries the particle's world velocity and its system's render mode" {
	let a = row();
	a.renderer.renderMode = RenderMode.Stretch;
	a.renderer.alignment = RenderAlignment.Local;
	a.renderer.pivot = vec3(0.0, 0.0, 0.5);
	a.renderer.lengthScale = 2.0;
	a.renderer.velocityScale = 0.25;
	a.renderer.cameraVelocityScale = 0.5;
	a.renderer.minParticleSize = 0.125;
	a.renderer.maxParticleSize = 0.75;
	a.renderer.allowRoll = false;
	a.renderer.rotateWithStretchDirection = true;
	a.main.simulationSpace = SimulationSpace.Local;
	a.main.startSpeed = constantCurve(4.0);
	a.shape.enabled = false;
	const sys = walked(a);
	let w = ParticleWriter3D.create();
	let out: Vec<float32> = new Array(PARTICLE_VISUAL_INSTANCE_STRIDE * sys.count);
	const n = writeParticles(w, sys, [WHOLE], vec3(0.0, 0.0, -10.0), vec3(0.0, 0.0, 1.0), vec3(2.0, 0.0, 0.0), out);
	assert n.ok && n.value >= 1;
	// Local space: the stored velocity (along local +z, the emitter's translation-only transform)
	// reaches the instance as a world direction.
	assert near(out[16], 0.0) && near(out[17], 0.0) && near(out[18], 4.0);
	assert near(out[19], 1.0) && near(out[20], 2.0) && near(out[21], 0.5);
	// allowRoll off is bit 1, rotateWithStretchDirection bit 4.
	assert near(out[22], 5.0);
	assert near(out[23], 2.0) && near(out[24], 0.25) && near(out[25], 0.125) && near(out[26], 0.75);
	assert near(out[27], 1.0) && near(out[28], 0.0) && near(out[29], 0.0);
	assert near(out[30], 1.0) && near(out[31], 0.0) && near(out[32], 0.0);
	assert near(out[33], 0.0) && near(out[34], 1.0) && near(out[35], 0.0);
}

test "a local-space particle's velocity is turned by the emitter into the world direction" {
	let a = row();
	a.main.simulationSpace = SimulationSpace.Local;
	a.main.startSpeed = constantCurve(4.0);
	a.emission.rateOverTime = constantCurve(0.0);
	a.emission.bursts = [{ time: 0.0, count: constantCurve(1.0), cycleCount: 1, repeatInterval: 0.01, probability: 1.0 }];
	const made = ParticleSystem.create(a, 9);
	if (!made.ok) { unreachable; }
	let sys = made.value;
	sys.clock.fixedStep = 1.0 / 60.0;
	const quarter = rotationY(1.5707963267948966 as float32);
	playSystem(sys, quarter);
	const done = updateSystem(sys, 1.0 / 60.0, quarter);
	if (!done.ok) { unreachable; }
	let w = ParticleWriter3D.create();
	let out: Vec<float32> = new Array(PARTICLE_VISUAL_INSTANCE_STRIDE);
	const n = writeParticles(w, sys, [WHOLE], vec3(0.0, 0.0, -10.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 0.0), out);
	assert n.ok && n.value == 1;
	assert near(Math.abs(out[16]) as float32, 4.0) && Math.abs(out[18]) < 1e-4;
}

test "the writer refuses what the visual program cannot draw and a short buffer" {
	let a = row();
	a.renderer.renderMode = RenderMode.Mesh;
	const meshed = walked(a);
	let w = ParticleWriter3D.create();
	let out: Vec<float32> = new Array(PARTICLE_VISUAL_INSTANCE_STRIDE * 8);
	const mode = writeParticles(w, meshed, [WHOLE], vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 0.0), out);
	assert !mode.ok && mode.error == ParticleWriteError.UnsupportedRenderMode;
	const sys = walked(row());
	let short: Vec<float32> = new Array(16);
	const s = writeParticles(w, sys, [WHOLE], vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 0.0), short);
	assert !s.ok && s.error == ParticleWriteError.ShortInstances;
	const f = writeParticles(w, sys, [WHOLE, WHOLE], vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), vec3(0.0, 0.0, 0.0), out);
	assert !f.ok && f.error == ParticleWriteError.FrameCount;
}

test "the point writer writes the visual writer's position, width and colour in the same order" {
	let a = row();
	a.renderer.sortMode = ParticleSortMode.Distance;
	const sys = walked(a);
	let w = ParticleWriter3D.create();
	const eye = vec3(0.0, 0.0, -10.0);
	const forward = vec3(0.0, 0.0, 1.0);
	let visual: Vec<float32> = new Array(PARTICLE_VISUAL_INSTANCE_STRIDE * sys.count);
	let points: Vec<float32> = new Array(PARTICLE_INSTANCE_STRIDE * sys.count);
	const v = writeParticles(w, sys, [WHOLE], eye, forward, vec3(0.0, 0.0, 0.0), visual);
	const p = writeParticlePoints(w, sys, eye, forward, points);
	assert v.ok && p.ok && p.value == v.value && v.value >= 2;
	for (let k = 0; k < v.value; k++) {
		const from: int32 = k * PARTICLE_VISUAL_INSTANCE_STRIDE;
		const to: int32 = k * PARTICLE_INSTANCE_STRIDE;
		for (let c = 0; c < 4; c++) { assert near(points[to + c], visual[from + c]); }
		for (let c = 0; c < 4; c++) { assert near(points[to + 4 + c], visual[from + 12 + c]); }
	}
	assert near(points[3], 2.0) && near(points[7], 0.75);
	for (let k = 1; k < p.value; k++) { assert points[k * PARTICLE_INSTANCE_STRIDE + 2] <= points[(k - 1) * PARTICLE_INSTANCE_STRIDE + 2]; }
}

test "the point writer refuses what the visual program cannot draw and a short buffer" {
	let a = row();
	a.renderer.renderMode = RenderMode.Stretch;
	const stretched = walked(a);
	let w = ParticleWriter3D.create();
	let out: Vec<float32> = new Array(PARTICLE_INSTANCE_STRIDE * 8);
	const eye = vec3(0.0, 0.0, 0.0);
	const forward = vec3(0.0, 0.0, 1.0);
	const mode = writeParticlePoints(w, stretched, eye, forward, out);
	assert !mode.ok && mode.error == ParticleWriteError.UnsupportedRenderMode;
	const sys = walked(row());
	let short: Vec<float32> = new Array(PARTICLE_INSTANCE_STRIDE);
	const s = writeParticlePoints(w, sys, eye, forward, short);
	assert !s.ok && s.error == ParticleWriteError.ShortInstances;
}

test "a trail writes one view-facing quad per segment, turned onto it" {
	let a = row();
	a.emission.rateOverTime = constantCurve(0.0);
	a.emission.bursts = [{ time: 0.0, count: constantCurve(1.0), cycleCount: 1, repeatInterval: 0.01, probability: 1.0 }];
	a.main.startSpeed = constantCurve(6.0);
	a.trails.enabled = true;
	a.trails.minVertexDistance = 0.0;
	const sys = walked(a);
	let chains = TrailChains.create();
	buildTrails(sys, chains);
	const segments: int32 = (chains.vertices.length as int32) - chains.chainCount();
	assert segments >= 2;
	let out: Vec<float32> = new Array(PARTICLE_VISUAL_INSTANCE_STRIDE * segments);
	// Seen from the side, +z the camera's right: each segment runs from the newer point back
	// along -z, so its quad turns half round and keeps u at the newer end.
	const side = writeTrails(chains, WHOLE, vec3(0.0, 0.0, 1.0), vec3(0.0, 1.0, 0.0), out);
	assert side.ok && side.value == segments;
	assert near(out[3], 0.1) && near(out[4], 2.0) && near(Math.abs(out[7]) as float32, 3.1415927);
	assert near(out[8], 0.0) && out[10] > out[8];
	// With +z the camera's up, the segment runs down the view and the quad turns a quarter.
	const up = writeTrails(chains, WHOLE, vec3(1.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), out);
	assert up.ok && near(out[7], 1.5707964);
	let short: Vec<float32> = new Array(16);
	const s = writeTrails(chains, WHOLE, vec3(1.0, 0.0, 0.0), vec3(0.0, 1.0, 0.0), short);
	assert !s.ok && s.error == ParticleWriteError.ShortInstances;
}
