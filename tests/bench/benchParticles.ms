// T4 entry: the SoA simulation of src/particles/system.ms against benchParticlesAos.ms, one
// workload (docs/TESTING.md "Particle bench"). CPU only: no window, no upload.

import { Vec3, vec3, translation } from "../../src/math/math3d";
import { ParticleSystemAsset, SimulationSpace, ShapeType, ParticleSortMode } from "../../src/particles/asset";
import { constantCurve, linearCurve, curveOf, key, gradientOf, rgbaColor, GradientMode, ParticleColorSpace } from "../../src/particles/curve";
import { ParticleSystem, playSystem, updateSystem } from "../../src/particles/system";
import { ParticleWriter3D, writeParticles } from "../../src/void3d/particleWriter";
import { AtlasTile } from "../../src/void3d/billboard";
import { PARTICLE_VISUAL_INSTANCE_STRIDE } from "../../src/void3d/particles";
import { benchCounts, stepsFor, millisecondsSince, row, isHeadline, WARM_STEPS, STEP } from "./benchParticlesRows";

function makeSystem(count: int32): ParticleSystem {
	let a = ParticleSystemAsset.defaults();
	a.main.duration = 5.0;
	a.main.loop = true;
	a.main.maxParticles = count + count / 8;
	a.main.startLifetime = constantCurve(1.0);
	a.main.startSpeed = constantCurve(3.0);
	a.main.gravityModifier = constantCurve(0.5);
	a.main.simulationSpace = SimulationSpace.World;
	a.emission.rateOverTime = constantCurve(count as float32);
	a.shape.shapeType = ShapeType.Sphere;
	a.shape.radius = 1.0;
	a.sizeOverLifetime.enabled = true;
	a.sizeOverLifetime.x = curveOf(1.0, linearCurve([key(0.0, 1.0), key(1.0, 0.0)]));
	a.colorOverLifetime.enabled = true;
	a.colorOverLifetime.color = gradientOf({
		colorKeys: [
			{ color: rgbaColor(1.0, 0.5, 0.25, 0.5), time: 0.0 },
			{ color: rgbaColor(0.25, 0.5, 1.0, 0.5), time: 1.0 },
		],
		alphaKeys: [{ alpha: 0.5, time: 0.0 }, { alpha: 0.5, time: 1.0 }],
		mode: GradientMode.Blend,
		colorSpace: ParticleColorSpace.Gamma,
	});
	a.renderer.sortMode = ParticleSortMode.None;
	const made = ParticleSystem.create(a, count as uint32);
	if (!made.ok) { console.log(`create failed ${made.error}`); unreachable; }
	return made.value;
}

function measure(count: int32, headline: boolean): void {
	const world = translation(0.0, 0.0, 0.0);
	let sys = makeSystem(count);
	sys.clock.fixedStep = STEP;
	playSystem(sys, world);
	for (let k = 0; k < WARM_STEPS; k++) { const d = updateSystem(sys, STEP, world); }
	const steps: int32 = stepsFor(count);
	const updateStarted: float64 = performance.now();
	for (let k = 0; k < steps; k++) { const d = updateSystem(sys, STEP, world); }
	const updateMs: float64 = millisecondsSince(updateStarted, steps);

	let writer = ParticleWriter3D.create();
	const tiles: Vec<AtlasTile> = [{ u: 0.0, v: 0.0, u2: 1.0, v2: 1.0 }];
	const eye: Vec3 = vec3(0.0, 0.0, 10.0);
	const forward: Vec3 = vec3(0.0, 0.0, -1.0);
	let out: Vec<float32> = new Array((sys.capacity as int32) * PARTICLE_VISUAL_INSTANCE_STRIDE);
	for (let i = 0; i < out.length; i++) { out[i] = 0.0; }
	const unsorted = writeParticles(writer, sys, tiles, eye, forward, out);
	if (!unsorted.ok) { console.log(`write failed ${unsorted.error}`); unreachable; }
	const writeStarted: float64 = performance.now();
	for (let k = 0; k < steps; k++) { const w = writeParticles(writer, sys, tiles, eye, forward, out); }
	const writeMs: float64 = millisecondsSince(writeStarted, steps);

	sys.asset.renderer.sortMode = ParticleSortMode.Distance;
	const sortedStarted: float64 = performance.now();
	for (let k = 0; k < steps; k++) { const w = writeParticles(writer, sys, tiles, eye, forward, out); }
	const sortMs: float64 = millisecondsSince(sortedStarted, steps) - writeMs;

	row(`live${count}`, sys.count as float64);
	row(`update${count}.ms`, updateMs);
	row(`sort${count}.ms`, sortMs);
	row(`write${count}.ms`, writeMs);
	if (headline) { row("present.ms", updateMs + writeMs + sortMs); }
}

function main(): void {
	const counts = benchCounts();
	for (let i = 0; i < counts.length; i++) { measure(counts[i], isHeadline(counts, i)); }
}
main();
