// T4 entry: the AoS emitter of src/void3d/particles.ms on the workload of benchParticles.ms.

import { vec3, identity } from "../../src/math/math3d";
import { ANCHOR_CENTER } from "../../src/void3d/billboard";
import { ParticleVisualFrame } from "../../src/void3d/particleVisual";
import {
	ParticleEmitter, EmitterState, ShapeKind, SortMode, ValueKind, constant, updateEmitter,
	writeVisualInstances, PARTICLE_VISUAL_INSTANCE_STRIDE,
} from "../../src/void3d/particles";
import { benchCounts, stepsFor, millisecondsSince, row, isHeadline, WARM_STEPS, STEP } from "./benchParticlesRows";

function makeEmitter(count: int32): ParticleEmitter {
	let state = EmitterState.defaults();
	state.loop = true;
	state.maxParts = count + count / 8;
	state.emitRate = constant(count as float32);
	state.shape = { kind: ShapeKind.Sphere, radius: constant(1.0) };
	state.globalLife = 5.0;
	state.life = constant(1.0);
	state.speed = constant(0.0);
	state.initialSpeed = constant(3.0);
	state.gravity = constant(4.905);
	state.size = { kind: ValueKind.Linear, start: 1.0, length: -1.0 };
	state.colors = [{ time: 0.0, color: 0xFF8040 }, { time: 1.0, color: 0x4080FF }];
	state.alpha = constant(0.5);
	state.sortMode = SortMode.Back;
	const made = ParticleEmitter.create(state, count as uint32);
	if (!made.ok) { console.log(`create failed ${made.error}`); unreachable; }
	return made.value;
}

function measure(count: int32, headline: boolean): void {
	const world = identity();
	let emitter = makeEmitter(count);
	for (let k = 0; k < WARM_STEPS; k++) { const d = updateEmitter(emitter, STEP, world); }
	const steps: int32 = stepsFor(count);
	const updateStarted: float64 = performance.now();
	for (let k = 0; k < steps; k++) { const d = updateEmitter(emitter, STEP, world); }
	const updateMs: float64 = millisecondsSince(updateStarted, steps);

	const frames: Vec<ParticleVisualFrame> = [{
		tile: { u: 0.0, v: 0.0, u2: 1.0, v2: 1.0 }, pixelWidth: 1.0, pixelHeight: 1.0,
	}];
	let out: Vec<float32> = new Array(emitter.capacity * PARTICLE_VISUAL_INSTANCE_STRIDE);
	for (let i = 0; i < out.length; i++) { out[i] = 0.0; }
	const first = writeVisualInstances(emitter, world, world, frames, ANCHOR_CENTER, out);
	if (!first.ok) { console.log(`write failed ${first.error}`); unreachable; }
	const writeStarted: float64 = performance.now();
	for (let k = 0; k < steps; k++) {
		const w = writeVisualInstances(emitter, world, world, frames, ANCHOR_CENTER, out);
	}
	const writeMs: float64 = millisecondsSince(writeStarted, steps);

	emitter.state.sortMode = SortMode.Sort;
	const sortedStarted: float64 = performance.now();
	for (let k = 0; k < steps; k++) {
		const w = writeVisualInstances(emitter, world, world, frames, ANCHOR_CENTER, out);
	}
	const sortMs: float64 = millisecondsSince(sortedStarted, steps) - writeMs;

	row(`live${count}`, emitter.count as float64);
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
