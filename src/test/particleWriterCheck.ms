import { vec3, translation } from "../math/math3d";
import {
	ParticleSystemAsset, ParticleSortMode, RenderMode, SimulationSpace,
} from "../particles/asset";
import { constantCurve, constantColor, rgbaColor } from "../particles/curve";
import { ParticleSystem, playSystem, updateSystem } from "../particles/system";
import { AtlasTile } from "../void3d/billboard";
import {
	ParticleWriter3D, ParticleWriteError, writeParticles, sheetTiles,
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
	let out: Vec<float32> = new Array(16 * sys.count);
	const n = writeParticles(w, sys, [WHOLE], vec3(0.0, 0.0, -10.0), vec3(0.0, 0.0, 1.0), out);
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
	let out: Vec<float32> = new Array(16 * sys.count);
	const eye = vec3(0.0, 0.0, -10.0);
	const n = writeParticles(w, sys, [WHOLE], eye, vec3(0.0, 0.0, 1.0), out);
	assert n.ok;
	for (let k = 1; k < n.value; k++) { assert out[k * 16 + 2] <= out[(k - 1) * 16 + 2]; }
	const back = writeParticles(w, sys, [WHOLE], vec3(0.0, 0.0, 10.0), vec3(0.0, 0.0, -1.0), out);
	assert back.ok;
	for (let k = 1; k < back.value; k++) { assert out[k * 16 + 2] >= out[(k - 1) * 16 + 2]; }
}

test "oldest in front draws the youngest first" {
	let a = row();
	a.renderer.sortMode = ParticleSortMode.OldestInFront;
	const sys = walked(a);
	let w = ParticleWriter3D.create();
	let out: Vec<float32> = new Array(16 * sys.count);
	const n = writeParticles(w, sys, [WHOLE], vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), out);
	assert n.ok;
	// The youngest was emitted last, nearest the emitter's last place at z = 3.
	for (let k = 1; k < n.value; k++) { assert out[k * 16 + 2] <= out[(k - 1) * 16 + 2]; }
}

test "a local system's particles follow the emitter" {
	let a = row();
	a.main.simulationSpace = SimulationSpace.Local;
	a.emission.rateOverTime = constantCurve(0.0);
	a.emission.bursts = [{ time: 0.0, count: constantCurve(1.0), cycleCount: 1, repeatInterval: 0.01, probability: 1.0 }];
	const sys = walked(a);
	let w = ParticleWriter3D.create();
	let out: Vec<float32> = new Array(16);
	const n = writeParticles(w, sys, [WHOLE], vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), out);
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
	let out: Vec<float32> = new Array(16 * sys.count);
	const n = writeParticles(w, sys, tiles, vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), out);
	assert n.ok;
	// 0.6 of 4 frames is frame 2, the bottom-left quarter, mirrored in u.
	assert near(out[8], 0.5) && near(out[10], 0.0);
	assert near(out[9], 0.5) && near(out[11], 1.0);
}

test "the writer refuses what the visual program cannot draw and a short buffer" {
	let a = row();
	a.renderer.renderMode = RenderMode.Stretch;
	const stretched = walked(a);
	let w = ParticleWriter3D.create();
	let out: Vec<float32> = new Array(16 * 8);
	const mode = writeParticles(w, stretched, [WHOLE], vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), out);
	assert !mode.ok && mode.error == ParticleWriteError.UnsupportedRenderMode;
	const sys = walked(row());
	let short: Vec<float32> = new Array(16);
	const s = writeParticles(w, sys, [WHOLE], vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), short);
	assert !s.ok && s.error == ParticleWriteError.ShortInstances;
	const f = writeParticles(w, sys, [WHOLE, WHOLE], vec3(0.0, 0.0, 0.0), vec3(0.0, 0.0, 1.0), out);
	assert !f.ok && f.error == ParticleWriteError.FrameCount;
}
