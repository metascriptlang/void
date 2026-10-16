import { Vec3, vec3, identity } from "../math/math3d";
import { Anchor } from "../void3d/billboard";
import {
	ParticleValue,
	ValueKind,
	Converge,
	EmitterState,
	ParticleEmitter,
	ParticleRandom,
	ParticleError,
	nextUnit,
	ShapeKind,
	SortMode,
	constant,
	updateEmitter,
	writeInstances,
	writeVisualInstances,
	PARTICLE_INSTANCE_STRIDE,
	PARTICLE_VISUAL_INSTANCE_STRIDE,
} from "../void3d/particles";
import {
	ParticleVisualCurves,
	ParticleVisualRandoms,
	ParticleVisualSample,
	ParticleVisualFrame,
	ParticleVisualRecord,
	ParticleVisualError,
	particleVisualFrameIndex,
	evaluateParticleVisualRecords,
} from "../void3d/particleVisual";

function near(a: float32, b: float32): boolean {
	return Math.abs(a - b) < 0.00001;
}

function noRandoms(): ParticleVisualRandoms {
	return { ratio: 0.0, rotation: 0.0, frame: 0.0 };
}

function frame(width: float32, height: float32): ParticleVisualFrame {
	return {
		tile: { u: 0.25, v: 0.125, u2: 0.5, v2: 0.625 },
		pixelWidth: width,
		pixelHeight: height,
	};
}

function recordA(): ParticleVisualRecord {
	const legacy: Vec<float32> = [4.0, 5.0, 6.0, 3.0, 0.2, 0.4, 0.6, 0.25];
	const samples: Vec<ParticleVisualSample> = [{
		ratio: 1.5, clockwiseRadians: 1.5707963267948966, frame: 1,
	}];
	const frames: Vec<ParticleVisualFrame> = [frame(4.0, 4.0), frame(32.0, 8.0)];
	const made = evaluateParticleVisualRecords(legacy, samples, frames, { x: 0.25, y: -0.5 });
	if (made.ok) { return made.value[0]; }
	unreachable;
}

function recordB(): ParticleVisualRecord {
	const legacy: Vec<float32> = [1.0, 2.0, 3.0, 2.0, 0.8, 0.3, 0.1, 0.49];
	const samples: Vec<ParticleVisualSample> = [{
		ratio: 2.0, clockwiseRadians: -0.5235987755982988, frame: -1,
	}];
	const frames: Vec<ParticleVisualFrame> = [frame(10.0, 30.0), frame(8.0, 8.0)];
	const made = evaluateParticleVisualRecords(legacy, samples, frames, { x: -0.5, y: 0.25 });
	if (made.ok) { return made.value[0]; }
	unreachable;
}

test "particleVisual frame wraps negatives, exact cycles and truncates within cycle" {
	const negative = particleVisualFrameIndex(-0.125, 4);
	assert negative.ok;
	if (negative.ok) { assert negative.value == 3; }
	const cycle = particleVisualFrameIndex(1.0, 4);
	assert cycle.ok;
	if (cycle.ok) { assert cycle.value == 0; }
	const negativeCycle = particleVisualFrameIndex(-2.0, 4);
	assert negativeCycle.ok;
	if (negativeCycle.ok) { assert negativeCycle.value == 0; }
	const truncated = particleVisualFrameIndex(0.499, 4);
	assert truncated.ok;
	if (truncated.ok) { assert truncated.value == 1; }
	const tinyNegative = particleVisualFrameIndex(-0.00000001, 4);
	assert tinyNegative.ok;
	if (tinyNegative.ok) { assert tinyNegative.value == 3; }
	const edge = particleVisualFrameIndex(0.25, 4);
	assert edge.ok;
	if (edge.ok) { assert edge.value == 1; }
}

test "particleVisual reuses life curves and supplied per-life random values" {
	const curves: ParticleVisualCurves = {
		ratio: { kind: ValueKind.Random, start: 1.0, length: 4.0, converge: Converge.Start },
		rotation: { kind: ValueKind.Linear, start: -1.0, length: 2.0 },
		frame: { kind: ValueKind.Random, start: -0.5, length: 1.0, converge: Converge.End },
	};
	const draws: ParticleVisualRandoms = { ratio: 0.5, rotation: 0.0, frame: 0.25 };
	const sampled = curves.sample(0.25, 2, 4, draws);
	assert sampled.ok;
	if (sampled.ok) {
		assert near(sampled.value.ratio, 1.5);
		assert near(sampled.value.clockwiseRadians, -0.5);
		assert sampled.value.frame == 2;
	}
	const repeated = curves.sample(0.25, 2, 4, draws);
	assert repeated.ok;
	if (sampled.ok && repeated.ok) { assert sampled.value == repeated.value; }
	const next = curves.sample(0.5, 2, 4, draws);
	assert next.ok;
	if (next.ok) { assert near(next.value.ratio, 2.0); }
	const rotating: ParticleVisualCurves = {
		ratio: constant(0.75),
		rotation: { kind: ValueKind.Random, start: -1, length: 2, converge: Converge.End },
		frame: constant(1.0),
	};
	const turned = rotating.sample(0.5, 3, 4, { ratio: 0, rotation: 0.75, frame: 0 });
	assert turned.ok;
	if (turned.ok) {
		assert turned.value.ratio == 0.75;
		assert turned.value.clockwiseRadians == -0.25;
		assert turned.value.frame == 0;
	}
}

test "particleVisual absent frame curve keeps caller frame; defaults keep square ratio" {
	const defaults: ParticleVisualCurves = ParticleVisualCurves.defaults();
	const sampled = defaults.sample(0.8, 7, 2, noRandoms());
	assert sampled.ok;
	if (sampled.ok) {
		assert sampled.value.ratio == 1.0;
		assert sampled.value.clockwiseRadians == 0.0;
		assert sampled.value.frame == 7;
	}
	const poly: ParticleVisualCurves = {
		...defaults, ratio: { kind: ValueKind.Poly, values: [1.0, 2.0, 3.0] },
	};
	const curved = poly.sample(0.5, 0, 2, noRandoms());
	assert curved.ok;
	if (curved.ok) { assert curved.value.ratio == 2.75; }
}

test "particleVisual wide tile rotates scaled offcenter corners clockwise in Void basis" {
	const record: ParticleVisualRecord = recordA();
	assert record.width == 3.0 && record.height == 1.125;
	assert record.frame == 1;
	assert record.color.alpha == 0.25;
	const point = record.cornerPoint({ x: 0.5, y: 0.5 }, vec3(1, 0, 0), vec3(0, 1, 0));
	assert point.ok;
	if (point.ok) {
		assert near(point.value.x, 5.125);
		assert near(point.value.y, 4.25);
		assert near(point.value.z, 6.0);
	}
	const pivot = record.cornerPoint(record.anchor, vec3(1, 0, 0), vec3(0, 1, 0));
	assert pivot.ok;
	if (pivot.ok) { assert pivot.value == record.position; }
	const uv = record.cornerUv({ x: 0.5, y: 0.5 });
	assert uv.ok;
	if (uv.ok) { assert uv.value.u == 0.5 && uv.value.v == 0.125; }
}

test "particleVisual tall tile negative rotation fallback and yawed camera basis" {
	const record: ParticleVisualRecord = recordB();
	assert record.width == 2.0 && record.height == 12.0;
	assert record.frame == 0;
	assert record.color.alpha == 0.49;
	const point = record.cornerPoint({ x: 0.5, y: -0.5 }, vec3(0, 0, -1), vec3(0, 1, 0));
	assert point.ok;
	if (point.ok) {
		assert near(point.value.x, 1.0);
		assert near(point.value.y, -4.794228634059948);
		assert near(point.value.z, -3.232050807568877);
	}
	const uv = record.cornerUv({ x: -0.5, y: -0.5 });
	assert uv.ok;
	if (uv.ok) { assert uv.value.u == 0.25 && uv.value.v == 0.625; }
}

test "particleVisual aspect and rotation controls separate from UV and alpha" {
	const original: ParticleVisualRecord = recordA();
	const noAspect: ParticleVisualRecord = { ...original, height: 4.5 };
	const noRotation: ParticleVisualRecord = { ...original, clockwiseRadians: 0.0 };
	const corner: Anchor = { x: 0.5, y: 0.5 };
	const right: Vec3 = vec3(1, 0, 0);
	const up: Vec3 = vec3(0, 1, 0);
	const base = original.cornerPoint(corner, right, up);
	const aspect = noAspect.cornerPoint(corner, right, up);
	const rotation = noRotation.cornerPoint(corner, right, up);
	assert base.ok && aspect.ok && rotation.ok;
	if (base.ok && aspect.ok && rotation.ok) {
		assert near(aspect.value.x, 8.5) && !near(aspect.value.x, base.value.x);
		assert near(rotation.value.x, 4.75) && near(rotation.value.y, 6.125);
		assert !near(rotation.value.y, base.value.y);
	}
	assert noAspect.color.alpha == original.color.alpha;
	assert noRotation.tile == original.tile;
	const tall: ParticleVisualRecord = recordB();
	const tallNoAspect: ParticleVisualRecord = { ...tall, height: 4.0 };
	const tallNoRotation: ParticleVisualRecord = { ...tall, clockwiseRadians: 0.0 };
	const tallCorner: Anchor = { x: 0.5, y: -0.5 };
	const tallRight: Vec3 = vec3(0, 0, -1);
	const tallBase = tall.cornerPoint(tallCorner, tallRight, up);
	const tallAspect = tallNoAspect.cornerPoint(tallCorner, tallRight, up);
	const tallRotation = tallNoRotation.cornerPoint(tallCorner, tallRight, up);
	assert tallBase.ok && tallAspect.ok && tallRotation.ok;
	if (tallBase.ok && tallAspect.ok && tallRotation.ok) {
		assert near(tallAspect.value.y, 0.401923788646684);
		assert !near(tallAspect.value.y, tallBase.value.y);
		assert near(tallRotation.value.y, -7) && near(tallRotation.value.z, 1);
		assert !near(tallRotation.value.z, tallBase.value.z);
	}
}

test "particleVisual records own source snapshots and fallback positive out of range" {
	let legacy: Vec<float32> = [4, 5, 6, 3, 0.2, 0.4, 0.6, 0.25];
	let frames: Vec<ParticleVisualFrame> = [frame(32, 8)];
	let samples: Vec<ParticleVisualSample> = [{ ratio: 1.5, clockwiseRadians: 0, frame: 99 }];
	const made = evaluateParticleVisualRecords(legacy, samples, frames, { x: 0, y: 0 });
	assert made.ok;
	legacy[0] = 100;
	frames[0].tile.u = 0.75;
	samples[0].ratio = 100;
	if (made.ok) {
		assert made.value[0].position.x == 4;
		assert made.value[0].height == 1.125;
		assert made.value[0].tile.u == 0.25;
		assert made.value[0].frame == 0;
	}
}

test "particleVisual refuses empty frames invalid pixels nonfinite and mismatched rows" {
	const legacy: Vec<float32> = [0, 0, 0, 1, 1, 1, 1, 0.25];
	const samples: Vec<ParticleVisualSample> = [{ ratio: 1, clockwiseRadians: 0, frame: 0 }];
	const empty: Vec<ParticleVisualFrame> = [];
	const noFrames = evaluateParticleVisualRecords(legacy, samples, empty, { x: 0, y: 0 });
	assert !noFrames.ok;
	if (!noFrames.ok) { assert noFrames.error == ParticleVisualError.NoFrames; }
	const zero: Vec<ParticleVisualFrame> = [frame(0, 8)];
	const badPixels = evaluateParticleVisualRecords(legacy, samples, zero, { x: 0, y: 0 });
	assert !badPixels.ok;
	if (!badPixels.ok) { assert badPixels.error == ParticleVisualError.InvalidFrame; }
	const inverted: Vec<ParticleVisualFrame> = [{
		...frame(4, 8), tile: { u: 0.5, v: 0.0, u2: 0.25, v2: 1.0 },
	}];
	const badUv = evaluateParticleVisualRecords(legacy, samples, inverted, { x: 0, y: 0 });
	assert !badUv.ok;
	if (!badUv.ok) { assert badUv.error == ParticleVisualError.InvalidFrame; }
	const good: Vec<ParticleVisualFrame> = [frame(4, 8)];
	const short: Vec<float32> = [0, 0, 0, 1];
	const badShape = evaluateParticleVisualRecords(short, samples, good, { x: 0, y: 0 });
	assert !badShape.ok;
	if (!badShape.ok) { assert badShape.error == ParticleVisualError.InstanceShape; }
	const nan: float32 = (0.0 / 0.0) as float32;
	const badAnchor = evaluateParticleVisualRecords(legacy, samples, good, { x: nan, y: 0 });
	assert !badAnchor.ok;
	if (!badAnchor.ok) { assert badAnchor.error == ParticleVisualError.NonFinite; }
	const index = particleVisualFrameIndex(1.0 / 0.0, 2);
	assert !index.ok;
	if (!index.ok) { assert index.error == ParticleVisualError.NonFinite; }
	const absent = particleVisualFrameIndex(0.2, 0);
	assert !absent.ok;
	if (!absent.ok) { assert absent.error == ParticleVisualError.NoFrames; }
	const record: ParticleVisualRecord = recordA();
	const badCorner = record.cornerUv({ x: 0.0, y: 0.5 });
	assert !badCorner.ok;
	if (!badCorner.ok) { assert badCorner.error == ParticleVisualError.InvalidCorner; }
	const badBasis = record.cornerPoint({ x: 0.5, y: 0.5 }, vec3(nan, 0, 0), vec3(0, 1, 0));
	assert !badBasis.ok;
	if (!badBasis.ok) { assert badBasis.error == ParticleVisualError.NonFinite; }
}

test "particleVisual rejects bad randoms coefficients and overflow without clamping sizes" {
	const randomValue: ParticleValue = {
		kind: ValueKind.Random, start: 1, length: 1, converge: Converge.No,
	};
	const curves: ParticleVisualCurves = {
		ratio: randomValue, rotation: constant(0), frame: null,
	};
	const bad = curves.sample(0.5, 0, 1, { ratio: 1.0, rotation: 0, frame: 0 });
	assert !bad.ok;
	if (!bad.ok) { assert bad.error == ParticleVisualError.InvalidRandom; }
	const infinite: ParticleVisualCurves = {
		...curves, ratio: constant((1.0 / 0.0) as float32),
	};
	assert !infinite.sample(0.5, 0, 1, noRandoms()).ok;
	const overflow: Vec<float32> = [0, 0, 0, 3.0e38, 1, 1, 1, 0.25];
	const samples: Vec<ParticleVisualSample> = [{ ratio: 2, clockwiseRadians: 0, frame: 0 }];
	const frames: Vec<ParticleVisualFrame> = [frame(1, 1)];
	const made = evaluateParticleVisualRecords(overflow, samples, frames, { x: 0, y: 0 });
	assert !made.ok;
	if (!made.ok) { assert made.error == ParticleVisualError.NonFinite; }
	const signed: Vec<float32> = [0, 0, 0, -2, 1, 1, 1, 0.25];
	const mirrored = evaluateParticleVisualRecords(signed, samples, frames, { x: 0, y: 0 });
	assert mirrored.ok;
	if (mirrored.ok) { assert mirrored.value[0].width == -2 && mirrored.value[0].height == -4; }
}

test "particleVisual consumes unchanged eight-float world-unit stream and continuous fade" {
	const state: EmitterState = {
		...EmitterState.defaults(),
		maxParts: 1,
		emitRate: constant(0),
		shape: { kind: ShapeKind.Point },
		speed: constant(0),
		size: constant(2),
		globalSize: constant(1.5),
		alpha: constant(0.25),
	};
	const created = ParticleEmitter.create(state, 7);
	assert created.ok;
	if (created.ok) {
		let emitter: ParticleEmitter = created.value;
		emitter.emitCount = 1;
		const stepped = updateEmitter(emitter, 0, identity());
		assert stepped.ok;
		let legacy: Vec<float32> = new Array(PARTICLE_INSTANCE_STRIDE);
		const written = writeInstances(emitter, identity(), legacy);
		assert written.ok;
		assert legacy.length == 8 && legacy[3] == 3 && legacy[7] == 0.25;
		const before: Vec<float32> = legacy;
		const samples: Vec<ParticleVisualSample> = [{ ratio: 1.5, clockwiseRadians: 0, frame: 0 }];
		const frames: Vec<ParticleVisualFrame> = [frame(32, 8)];
		const made = evaluateParticleVisualRecords(legacy, samples, frames, { x: 0, y: 0 });
		assert made.ok;
		if (made.ok) {
			assert made.value[0].width == 3 && made.value[0].height == 1.125;
			assert made.value[0].color.alpha == 0.25;
		}
		for (let i = 0; i < 8; i++) { assert legacy[i] == before[i]; }
		assert emitter.sequence.state == 7;
	}
}

test "particleVisual emitter updates ratio rotation and wrapped frame on life time" {
	const state: EmitterState = {
		...EmitterState.defaults(), maxParts: 1, emitRate: constant(0),
		shape: { kind: ShapeKind.Point }, speed: constant(0),
		ratio: { kind: ValueKind.Linear, start: 1, length: 2 },
		rotation: { kind: ValueKind.Linear, start: -1, length: 2 },
		frame: constant(-0.125), frameCount: 4,
	};
	const made = ParticleEmitter.create(state, 7);
	assert made.ok;
	if (!made.ok) { return; }
	let emitter = made.value;
	emitter.emitCount = 1;
	assert updateEmitter(emitter, 0.25, identity()).ok;
	assert emitter.count == 1;
	assert near(emitter.particles[0].ratio, 1.5);
	assert near(emitter.particles[0].rotation, -0.5);
	assert emitter.particles[0].frame == 3;
	assert emitter.sequence.state == 7;
	emitter.particles[0].time = 2.0;
	assert updateEmitter(emitter, 0, identity()).ok;
	assert emitter.count == 0;
	emitter.state.frame = null;
	emitter.emitCount = 1;
	assert updateEmitter(emitter, 0, identity()).ok;
	assert emitter.count == 1 && emitter.particles[0].frame == 0;
	emitter.state.frame = { kind: ValueKind.Poly, values: [0.0, 1.0] };
	for (let step = 1; step <= 4; step++) {
		assert updateEmitter(emitter, 0.25, identity()).ok;
		assert emitter.particles[0].frame == step % 4;
	}
	const frame = emitter.state.frame;
	assert frame !== null && frame.kind == ValueKind.Poly;
	assert frame.values.length == 2 && frame.values[0] == 0 && frame.values[1] == 1;
	assert emitter.sequence.state == 7;
}

test "particleVisual retained draws follow ratio rotation light alpha frame order" {
	const random: ParticleValue = {
		kind: ValueKind.Random, start: 0, length: 1, converge: Converge.No,
	};
	const state: EmitterState = {
		...EmitterState.defaults(), maxParts: 1, emitRate: constant(0),
		shape: { kind: ShapeKind.Point }, speed: constant(0),
		ratio: random, rotation: random, light: random, alpha: random,
		frame: random, frameCount: 4,
	};
	const made = ParticleEmitter.create(state, 91);
	assert made.ok;
	if (!made.ok) { return; }
	let control = ParticleRandom.seeded(91);
	let draws: Vec<float32> = [];
	for (let slot = 0; slot < 5; slot++) { draws.push(nextUnit(control)); }
	let emitter = made.value;
	emitter.emitCount = 1;
	assert updateEmitter(emitter, 0.25, identity()).ok;
	const value = emitter.particles[0];
	assert near(value.ratio, draws[0]);
	assert near(value.rotation, draws[1]);
	assert near(value.red, draws[2]);
	assert near(value.alpha, draws[3]);
	const frame = particleVisualFrameIndex(draws[4] as float64, 4);
	assert frame.ok && value.frame == frame.value;
	assert value.randomsDrawn == 5 && emitter.sequence.state == control.state;
	assert updateEmitter(emitter, 0, identity()).ok;
	assert emitter.particles[0].ratio == value.ratio;
	assert emitter.particles[0].frame == value.frame;
	assert emitter.sequence.state == control.state;
}

test "particleVisual bad frame count and nonfinite life values return explicit errors" {
	const state: EmitterState = {
		...EmitterState.defaults(), maxParts: 1, emitRate: constant(0),
		shape: { kind: ShapeKind.Point }, speed: constant(0), frame: constant(0), frameCount: 0,
	};
	const invalid = ParticleEmitter.create(state, 7);
	assert !invalid.ok && invalid.error == ParticleError.NoFrames;
	const made = ParticleEmitter.create({ ...state, frameCount: 2 }, 7);
	assert made.ok;
	if (!made.ok) { return; }
	let emitter = made.value;
	emitter.emitCount = 1;
	emitter.state.frameCount = 0;
	const badCount = updateEmitter(emitter, 0.25, identity());
	assert !badCount.ok && badCount.error == ParticleError.NoFrames;
	assert emitter.time == 0 && emitter.count == 0;
	emitter.state.frameCount = 2;
	emitter.state.ratio = constant((1.0 / 0.0) as float32);
	const badValue = updateEmitter(emitter, 0.25, identity());
	assert !badValue.ok && badValue.error == ParticleError.NonFiniteVisual;
}

test "particleVisual ordered writer emits four vec4 rows with one global size draw" {
	const state: EmitterState = {
		...EmitterState.defaults(), maxParts: 1, emitRate: constant(0),
		shape: { kind: ShapeKind.Point }, speed: constant(0), size: constant(2),
		globalSize: { kind: ValueKind.Random, start: 1, length: 1, converge: Converge.No },
		ratio: constant(1.5), rotation: constant(1.5707963267948966),
		alpha: constant(0.25), frame: constant(0.75), frameCount: 2,
	};
	const made = ParticleEmitter.create(state, 7);
	assert made.ok;
	if (!made.ok) { return; }
	let emitter = made.value;
	emitter.emitCount = 1;
	assert updateEmitter(emitter, 0, identity()).ok;
	emitter.particles[0].position = vec3(4, 5, 6);
	let control = emitter;
	let legacy: Vec<float32> = new Array(PARTICLE_INSTANCE_STRIDE);
	assert writeInstances(control, identity(), legacy).ok;
	const frames: Vec<ParticleVisualFrame> = [frame(4, 4), frame(32, 8)];
	let out: Vec<float32> = new Array(PARTICLE_VISUAL_INSTANCE_STRIDE);
	const wrote = writeVisualInstances(
		emitter, identity(), identity(), frames, { x: 0.25, y: -0.5 }, out,
	);
	assert wrote.ok && wrote.value == 1;
	assert out.length == 16 && legacy.length == 8;
	assert out[0] == 4 && out[1] == 5 && out[2] == 6 && out[3] == legacy[3];
	assert near(out[4], (legacy[3] * 1.5 * 0.25) as float32);
	assert out[5] == 0.25 && out[6] == -0.5 && out[7] == emitter.particles[0].rotation;
	assert out[8] == 0.25 && out[9] == 0.125 && out[10] == 0.5 && out[11] == 0.625;
	assert out[12] == legacy[4] && out[15] == 0.25;
	assert emitter.sequence.state == control.sequence.state && emitter.sequence.state != 7;
}

test "particleVisual writer refuses malformed frames and overflow before output writes" {
	const state: EmitterState = {
		...EmitterState.defaults(), maxParts: 1, emitRate: constant(0),
		shape: { kind: ShapeKind.Point }, speed: constant(0), size: constant(3.0e38),
		ratio: constant(2), frame: constant(0), frameCount: 1,
	};
	const made = ParticleEmitter.create(state, 7);
	assert made.ok;
	if (!made.ok) { return; }
	let emitter = made.value;
	emitter.emitCount = 1;
	assert updateEmitter(emitter, 0, identity()).ok;
	let out: Vec<float32> = [];
	for (let at = 0; at < 16; at++) { out.push(-123); }
	const good: Vec<ParticleVisualFrame> = [frame(1, 1)];
	const overflow = writeVisualInstances(
		emitter, identity(), identity(), good, { x: 0, y: 0 }, out,
	);
	assert !overflow.ok && overflow.error == ParticleError.NonFiniteVisual;
	for (const value of out) { assert value == -123; }
	const invalid: Vec<ParticleVisualFrame> = [frame(0, 1)];
	const refused = writeVisualInstances(
		emitter, identity(), identity(), invalid, { x: 0, y: 0 }, out,
	);
	assert !refused.ok && refused.error == ParticleError.InvalidFrame;
	for (const value of out) { assert value == -123; }
	emitter.state.frameCount = 2;
	const mismatch = writeVisualInstances(
		emitter, identity(), identity(), good, { x: 0, y: 0 }, out,
	);
	assert !mismatch.ok && mismatch.error == ParticleError.FrameCountMismatch;
	assert emitter.sequence.state == 7;
}

test "particleVisual all thirteen retained draw slots remain bounded across updates" {
	const random: ParticleValue = {
		kind: ValueKind.Random, start: 0, length: 1, converge: Converge.No,
	};
	const defaults = EmitterState.defaults();
	const state: EmitterState = {
		...defaults, maxParts: 1, emitRate: constant(0), shape: { kind: ShapeKind.Point },
		force: { x: random, y: random, z: random }, gravity: random, damping: random,
		turbulence: { ...defaults.turbulence, enabled: true, noiseStrength: 1, influence: random },
		speed: random, size: random, ratio: random, rotation: random,
		light: random, alpha: random, frame: random, frameCount: 4,
	};
	const made = ParticleEmitter.create(state, 143);
	assert made.ok;
	if (!made.ok) { return; }
	let emitter = made.value;
	emitter.emitCount = 1;
	let control = ParticleRandom.seeded(143);
	let draws: Vec<float32> = [];
	for (let draw = 0; draw < 13; draw++) { draws.push(nextUnit(control)); }
	assert updateEmitter(emitter, 0.0625, identity()).ok;
	assert emitter.particles[0].randomsDrawn == 13;
	assert emitter.particles[0].size == draws[7];
	assert emitter.particles[0].ratio == draws[8];
	assert emitter.particles[0].rotation == draws[9];
	assert emitter.particles[0].red == draws[10] && emitter.particles[0].alpha == draws[11];
	const frame = particleVisualFrameIndex(draws[12] as float64, 4);
	assert frame.ok && emitter.particles[0].frame == frame.value;
	assert emitter.randoms.length == 13;
	assert emitter.sequence.state == control.state;
	assert updateEmitter(emitter, 0, identity()).ok;
	assert emitter.sequence.state == control.state;
	const tooLarge = ParticleEmitter.create({ ...state, maxParts: 165191050 }, 143);
	assert !tooLarge.ok && tooLarge.error == ParticleError.NoCapacity;
}

test "particleVisual all sort modes keep frame ratio rotation alpha with world position" {
	const state: EmitterState = {
		...EmitterState.defaults(), maxParts: 2, emitRate: constant(0), emitLocal: true,
		shape: { kind: ShapeKind.Point }, speed: constant(0), size: constant(2),
	};
	const made = ParticleEmitter.create(state, 7);
	assert made.ok;
	if (!made.ok) { return; }
	let emitter = made.value;
	emitter.emitCount = 2;
	assert updateEmitter(emitter, 0, identity()).ok;
	for (let slot = 0; slot < 2; slot++) {
		emitter.particles[slot].position = vec3(slot as float32, 0, (slot + 1) as float32);
		emitter.particles[slot].frame = slot;
		emitter.particles[slot].ratio = slot == 0 ? 1.0 : 3.0;
		emitter.particles[slot].rotation = slot == 0 ? 0.0 : 0.5;
		emitter.particles[slot].alpha = slot == 0 ? 0.25 : 0.75;
	}
	let world = identity();
	world.m41 = 10;
	world.m43 = 20;
	const frames: Vec<ParticleVisualFrame> = [frame(1, 2), frame(2, 1)];
	const modes: Vec<SortMode> = [SortMode.Sort, SortMode.InvSort, SortMode.Front, SortMode.Back];
	let out: Vec<float32> = new Array(32);
	for (const mode of modes) {
		emitter.state.sortMode = mode;
		const result = writeVisualInstances(
			emitter, world, identity(), frames, { x: 0.25, y: -0.5 }, out,
		);
		assert result.ok && result.value == 2;
		const reversed: boolean = mode == SortMode.Sort || mode == SortMode.Front;
		assert out[0] == (reversed ? 11.0 : 10.0);
		assert out[2] == (reversed ? 22.0 : 21.0);
		assert out[4] == (reversed ? 3.0 : 4.0);
		assert out[7] == (reversed ? 0.5 : 0.0);
		assert out[15] == (reversed ? 0.75 : 0.25);
		assert out[16] == (reversed ? 10.0 : 11.0);
	}
	assert emitter.sequence.state == 7;
}
