import { vec3, translation } from "../math/math3d";
import { ParticleSystemAsset, SimulationSpace, TrailMode, TrailTextureMode } from "../particles/asset";
import { constantCurve, constantColor, rgbaColor } from "../particles/curve";
import { ParticleSystem, ParticleSystemError, playSystem, updateSystem } from "../particles/system";
import { TrailRings } from "../particles/trailRing";
import { TrailChains, buildTrails } from "../particles/trail";

const H: float64 = 1.0 / 60.0;

function near(a: float32, b: float32, eps: float32): boolean {
	const d: float32 = a - b;
	return d < eps && d > -eps;
}

// One particle along +z at 6 units a second, each with a trail.
function streak(): ParticleSystemAsset {
	let a = ParticleSystemAsset.defaults();
	a.main.duration = 10.0;
	a.main.startLifetime = constantCurve(1.0);
	a.main.startSpeed = constantCurve(6.0);
	a.main.startSizeX = constantCurve(0.5);
	a.main.simulationSpace = SimulationSpace.World;
	a.shape.enabled = false;
	a.emission.rateOverTime = constantCurve(0.0);
	a.emission.bursts = [{ time: 0.0, count: constantCurve(1.0), cycleCount: 1, repeatInterval: 0.01, probability: 1.0 }];
	a.main.startRotationZ = constantCurve(0.0);
	a.trails.enabled = true;
	a.trails.minVertexDistance = 0.2;
	return a;
}

function run(a: ParticleSystemAsset, steps: int32): ParticleSystem {
	const made = ParticleSystem.create(a, 8);
	if (!made.ok) { unreachable; }
	let sys = made.value;
	sys.clock.fixedStep = H;
	playSystem(sys, translation(0.0, 0.0, 0.0));
	for (let k = 0; k < steps; k++) {
		const done = updateSystem(sys, H, translation(0.0, 0.0, 0.0));
		if (!done.ok) { unreachable; }
	}
	return sys;
}

test "a ring records a point once it lies the minimum distance away and drops expired ones" {
	let r = TrailRings.create(1, 4);
	r.record(0, vec3(0.0, 0.0, 0.0), 0.0, 1.0, 0.5);
	r.record(0, vec3(0.25, 0.0, 0.0), 0.1, 1.0, 0.5);
	assert r.pointCount(0) == 1;
	r.record(0, vec3(0.75, 0.0, 0.0), 0.2, 1.0, 0.5);
	assert r.pointCount(0) == 2 && near(r.distanceOf(0, 1), 0.75, 1e-5);
	r.record(0, vec3(1.5, 0.0, 0.0), 1.15, 1.0, 0.5);
	// The point recorded at age 0 is older than a second at age 1.15.
	assert r.pointCount(0) == 2 && near(r.ageOf(0, 0), 0.2, 1e-5);
}

test "a full ring drops its oldest point" {
	let r = TrailRings.create(1, 3);
	for (let k = 0; k < 5; k++) { r.record(0, vec3(k as float32, 0.0, 0.0), (k as float32) * 0.1, 10.0, 0.5); }
	assert r.pointCount(0) == 3;
	assert near(r.pointOf(0, 0).x, 2.0, 1e-5) && near(r.pointOf(0, 2).x, 4.0, 1e-5);
}

test "a moving particle's trail runs from the particle back over spaced points" {
	const sys = run(streak(), 30);
	let chains = TrailChains.create();
	buildTrails(sys, chains);
	assert chains.chainCount() == 1;
	const end = chains.chainEnd(0);
	assert end >= 6;
	// The particle at the head, then older points behind it along -z.
	for (let k = 1; k < end; k++) { assert chains.vertices[k].position.z < chains.vertices[k - 1].position.z; }
	for (let k = 2; k < end; k++) {
		assert chains.vertices[k - 1].position.z - chains.vertices[k].position.z >= 0.2 - 1e-4;
	}
	// Stretch: u runs 0 at the particle to 1 at the oldest point; size scales the width.
	assert near(chains.vertices[0].u, 0.0, 1e-5) && near(chains.vertices[end - 1].u, 1.0, 1e-5);
	assert near(chains.vertices[0].width, 0.5, 1e-5);
}

test "trail points expire after the trail's share of the lifetime" {
	let a = streak();
	a.trails.lifetime = constantCurve(0.25);
	a.trails.minVertexDistance = 0.0;
	const sys = run(a, 50);
	let chains = TrailChains.create();
	buildTrails(sys, chains);
	assert chains.chainCount() == 1;
	const end = chains.chainEnd(0);
	const head = chains.vertices[0].position.z;
	const tail = chains.vertices[end - 1].position.z;
	// A quarter second at 6 units a second, give or take a step.
	assert head - tail <= 1.5 + 0.1 && head - tail >= 1.5 - 0.2;
}

test "a trail that outlives its particle drains on its own, else dies with it" {
	let a = streak();
	a.trails.lifetime = constantCurve(0.5);
	a.trails.dieWithParticles = false;
	let chains = TrailChains.create();
	const after = run(a, 70);
	assert after.count == 0;
	buildTrails(after, chains);
	assert chains.chainCount() == 1;
	const drained = run(a, 100);
	buildTrails(drained, chains);
	assert chains.chainCount() == 0;
	a.trails.dieWithParticles = true;
	const gone = run(a, 70);
	buildTrails(gone, chains);
	assert chains.chainCount() == 0;
}

test "texture modes lay u along the trail by distance or by segment" {
	let a = streak();
	a.trails.minVertexDistance = 0.0;
	a.trails.textureMode = TrailTextureMode.RepeatPerSegment;
	let chains = TrailChains.create();
	buildTrails(run(a, 10), chains);
	const end = chains.chainEnd(0);
	for (let k = 0; k < end; k++) { assert near(chains.vertices[k].u, k as float32, 1e-5); }
	a.trails.textureMode = TrailTextureMode.Tile;
	a.trails.textureScale = vec3(2.0, 1.0, 0.0);
	buildTrails(run(a, 10), chains);
	const last = chains.chainEnd(0) - 1;
	const length: float32 = chains.vertices[0].position.z - chains.vertices[last].position.z;
	assert near(chains.vertices[last].u, length * 2.0, 1e-3);
}

test "colour and width over the trail tint the particle's look" {
	let a = streak();
	a.main.startColor = constantColor(rgbaColor(1.0, 0.5, 1.0, 1.0));
	a.trails.colorOverTrail = constantColor(rgbaColor(0.5, 1.0, 1.0, 0.5));
	a.trails.widthOverTrail = constantCurve(2.0);
	let chains = TrailChains.create();
	buildTrails(run(a, 10), chains);
	const v = chains.vertices[0];
	assert near(v.color.r, 0.5, 1e-5) && near(v.color.g, 0.5, 1e-5) && near(v.color.a, 0.5, 1e-5);
	assert near(v.width, 1.0, 1e-5);
	a.trails.inheritParticleColor = false;
	a.trails.sizeAffectsWidth = false;
	buildTrails(run(a, 10), chains);
	assert near(chains.vertices[0].color.g, 1.0, 1e-5) && near(chains.vertices[0].width, 2.0, 1e-5);
}

// Six particles a second emitted from a still emitter, each moving off along +y.
function fountain(ribbons: int32): ParticleSystemAsset {
	let a = streak();
	a.main.startLifetime = constantCurve(5.0);
	a.main.startSpeed = constantCurve(1.0);
	a.emission.bursts = [];
	a.emission.rateOverTime = constantCurve(6.0);
	a.trails.mode = TrailMode.Ribbon;
	a.trails.ribbonCount = ribbons;
	return a;
}

test "ribbons link the live particles newest first, taking turns between ribbons" {
	const one = run(fountain(1), 60);
	let chains = TrailChains.create();
	buildTrails(one, chains);
	assert one.count >= 5 && chains.chainCount() == 1 && chains.chainEnd(0) == one.count;
	// Newer particles have travelled less.
	for (let k = 1; k < one.count; k++) {
		assert (chains.vertices[k].position.length() >= chains.vertices[k - 1].position.length() - 1e-5);
	}
	const two = run(fountain(2), 60);
	buildTrails(two, chains);
	assert chains.chainCount() == 2 && (chains.vertices.length as int32) == two.count;
}

test "a ribbon splitting into sub-emitter children is refused" {
	let a = fountain(1);
	a.trails.splitSubEmitterRibbons = true;
	const made = ParticleSystem.create(a, 8);
	assert !made.ok && made.error == ParticleSystemError.SplitSubEmitterRibbons;
}
