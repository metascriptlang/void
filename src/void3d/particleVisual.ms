import { Vec3, vec3 } from "../math/math3d";
import { Anchor, AtlasTile } from "./billboard";
import { Rgba, Uv } from "./meshData";
import { ParticleValue, ValueKind, constant, PARTICLE_INSTANCE_STRIDE } from "./particles";

export enum ParticleVisualError {
	NoFrames,
	InvalidFrame,
	InvalidRandom,
	InstanceShape,
	NonFinite,
	InvalidCorner,
}

export struct ParticleVisualCurves {
	ratio: ParticleValue;
	rotation: ParticleValue;
	frame: ParticleValue | null;
}

// Supply Particle.rand's retained per-life draws; do not draw again at render time.
// Emitter.hx:198-200 samples ratio/rotation before light/alpha, frame at :253-258 after them.
export struct ParticleVisualRandoms {
	ratio: float32;
	rotation: float32;
	frame: float32;
}

export struct ParticleVisualSample {
	ratio: float32;
	clockwiseRadians: float32;
	frame: int32;
}

export struct ParticleVisualFrame {
	tile: AtlasTile;
	pixelWidth: float32;
	pixelHeight: float32;
}

export struct ParticleVisualRecord {
	position: Vec3;
	width: float32;
	height: float32;
	anchor: Anchor;
	clockwiseRadians: float32;
	tile: AtlasTile;
	color: Rgba;
	frame: int32;
}

export function defaults(this typeof ParticleVisualCurves): ParticleVisualCurves {
	return { ratio: constant(1.0), rotation: constant(0.0), frame: null };
}

export function particleVisualFrameIndex(
	value: float64,
	frameCount: int32,
): Result<int32, ParticleVisualError> {
	if (frameCount <= 0) { return Result.err(ParticleVisualError.NoFrames); }
	if (!Number.isFinite(value)) { return Result.err(ParticleVisualError.NonFinite); }
	let cycle: float64 = value % 1.0;
	if (cycle < 0.0) { cycle = cycle + 1.0; }
	return Result.ok((cycle * (frameCount as float64)) as int32);
}

export function sample(
	this curves: ParticleVisualCurves,
	life: float64,
	previousFrame: int32,
	frameCount: int32,
	randoms: ParticleVisualRandoms,
): Result<ParticleVisualSample, ParticleVisualError> {
	if (frameCount <= 0) { return Result.err(ParticleVisualError.NoFrames); }
	const time: float32 = life as float32;
	if (!Number.isFinite(life) || !Number.isFinite(time)) {
		return Result.err(ParticleVisualError.NonFinite);
	}
	const ratio: float32 = try sampleValue(curves.ratio, time, randoms.ratio);
	const rotation: float32 = try sampleValue(curves.rotation, time, randoms.rotation);
	let index: int32 = previousFrame;
	const frameValue: ParticleValue | null = curves.frame;
	if (frameValue !== null) {
		const value: float32 = try sampleValue(frameValue, time, randoms.frame);
		index = try particleVisualFrameIndex(value as float64, frameCount);
	}
	return Result.ok({ ratio: ratio, clockwiseRadians: rotation, frame: index });
}

function sampleValue(
	value: ParticleValue,
	time: float32,
	random: float32,
): Result<float32, ParticleVisualError> {
	if (!value.hasFiniteCoefficients()) { return Result.err(ParticleVisualError.NonFinite); }
	if (value.drawsRandom() && !(random >= 0.0 && random < 1.0)) {
		return Result.err(ParticleVisualError.InvalidRandom);
	}
	const sampled: float32 = value.evaluate(time, random);
	if (!Number.isFinite(sampled)) { return Result.err(ParticleVisualError.NonFinite); }
	return Result.ok(sampled);
}

function hasFiniteCoefficients(this value: ParticleValue): boolean {
	return match (value.kind) {
		ValueKind.Const => Number.isFinite(value.value),
		ValueKind.Linear => Number.isFinite(value.start) && Number.isFinite(value.length),
		ValueKind.Pow => Number.isFinite(value.start) && Number.isFinite(value.length) &&
			Number.isFinite(value.power),
		ValueKind.Sin => Number.isFinite(value.frequency) && Number.isFinite(value.amplitude) &&
			Number.isFinite(value.offset),
		ValueKind.Cos => Number.isFinite(value.frequency) && Number.isFinite(value.amplitude) &&
			Number.isFinite(value.offset),
		ValueKind.Poly => {
			for (const coefficient of value.values) {
				if (!Number.isFinite(coefficient)) { return false; }
			}
			return true;
		},
		ValueKind.Random => Number.isFinite(value.start) && Number.isFinite(value.length),
	};
}

// Consume already ordered/scaled writeInstances output. Keep its globalSize draw and
// world/local placement in particles.ms; never evaluate them a second time here.
export function evaluateParticleVisualRecords(
	legacyInstances: Readonly<Span<float32>>,
	samples: Readonly<Span<ParticleVisualSample>>,
	frames: Readonly<Span<ParticleVisualFrame>>,
	anchor: Anchor,
): Result<Vec<ParticleVisualRecord>, ParticleVisualError> {
	if (frames.length == 0) { return Result.err(ParticleVisualError.NoFrames); }
	if (samples.length > 2147483647 / PARTICLE_INSTANCE_STRIDE ||
		legacyInstances.length != samples.length * PARTICLE_INSTANCE_STRIDE) {
		return Result.err(ParticleVisualError.InstanceShape);
	}
	if (!Number.isFinite(anchor.x) || !Number.isFinite(anchor.y)) {
		return Result.err(ParticleVisualError.NonFinite);
	}
	for (const frame of frames) {
		if (!frame.validPixelFrame()) { return Result.err(ParticleVisualError.InvalidFrame); }
	}
	for (const value of legacyInstances) {
		if (!Number.isFinite(value)) { return Result.err(ParticleVisualError.NonFinite); }
	}
	let records: Vec<ParticleVisualRecord> = [];
	for (let i = 0; i < (samples.length as int32); i++) {
		if (!Number.isFinite(samples[i].ratio) || !Number.isFinite(samples[i].clockwiseRadians)) {
			return Result.err(ParticleVisualError.NonFinite);
		}
		const selected: int32 = samples[i].frame;
		const index: int32 = selected < 0 || selected >= frames.length ? 0 : selected;
		const at: int32 = i * PARTICLE_INSTANCE_STRIDE;
		const width: float32 = legacyInstances[at + 3];
		const height: float32 = width * samples[i].ratio *
			(frames[index].pixelHeight / frames[index].pixelWidth);
		if (!Number.isFinite(height)) { return Result.err(ParticleVisualError.NonFinite); }
		records.push({
			position: vec3(legacyInstances[at], legacyInstances[at + 1], legacyInstances[at + 2]),
			width: width,
			height: height,
			anchor: anchor,
			clockwiseRadians: samples[i].clockwiseRadians,
			tile: frames[index].tile,
			color: {
				red: legacyInstances[at + 4],
				green: legacyInstances[at + 5],
				blue: legacyInstances[at + 6],
				alpha: legacyInstances[at + 7],
			},
			frame: index,
		});
	}
	return Result.ok(records);
}

export function validPixelFrame(this frame: ParticleVisualFrame): boolean {
	return frame.pixelWidth > 0.0 && frame.pixelHeight > 0.0 &&
		Number.isFinite(frame.pixelWidth) && Number.isFinite(frame.pixelHeight) &&
		frame.tile.u >= 0.0 && frame.tile.u < frame.tile.u2 && frame.tile.u2 <= 1.0 &&
		frame.tile.v >= 0.0 && frame.tile.v < frame.tile.v2 && frame.tile.v2 <= 1.0;
}

export function cornerPoint(
	this record: ParticleVisualRecord,
	corner: Anchor,
	cameraRight: Vec3,
	cameraUp: Vec3,
): Result<Vec3, ParticleVisualError> {
	if (!Number.isFinite(corner.x) || !Number.isFinite(corner.y) ||
		!Number.isFinite(record.width) || !Number.isFinite(record.height) ||
		!Number.isFinite(record.anchor.x) || !Number.isFinite(record.anchor.y) ||
		!Number.isFinite(record.clockwiseRadians) ||
		!record.position.hasFiniteComponents() || !cameraRight.hasFiniteComponents() ||
		!cameraUp.hasFiniteComponents()) {
		return Result.err(ParticleVisualError.NonFinite);
	}
	const x: float32 = (corner.x - record.anchor.x) * record.width;
	const y: float32 = (corner.y - record.anchor.y) * record.height;
	const cosine: float32 = Math.cos(record.clockwiseRadians) as float32;
	const sine: float32 = Math.sin(record.clockwiseRadians) as float32;
	// Keep ParticleShader.hx:46-50's clockwise sign: both quads map +y to the top UV edge.
	// Project onto Void's camera right/up, not Heaps' is3D fixed plane or clip-size factor.
	const across: float32 = x * cosine + y * sine;
	const up: float32 = y * cosine - x * sine;
	const point: Vec3 = vec3(
		record.position.x + cameraRight.x * across + cameraUp.x * up,
		record.position.y + cameraRight.y * across + cameraUp.y * up,
		record.position.z + cameraRight.z * across + cameraUp.z * up,
	);
	if (!point.hasFiniteComponents()) { return Result.err(ParticleVisualError.NonFinite); }
	return Result.ok(point);
}

export function cornerUv(
	this record: ParticleVisualRecord,
	corner: Anchor,
): Result<Uv, ParticleVisualError> {
	if ((corner.x != -0.5 && corner.x != 0.5) || (corner.y != -0.5 && corner.y != 0.5)) {
		return Result.err(ParticleVisualError.InvalidCorner);
	}
	if (!Number.isFinite(record.tile.u) || !Number.isFinite(record.tile.v) ||
		!Number.isFinite(record.tile.u2) || !Number.isFinite(record.tile.v2)) {
		return Result.err(ParticleVisualError.NonFinite);
	}
	return Result.ok({
		u: corner.x > 0.0 ? record.tile.u2 : record.tile.u,
		v: corner.y > 0.0 ? record.tile.v : record.tile.v2,
	});
}

function hasFiniteComponents(this value: Vec3): boolean {
	return Number.isFinite(value.x) && Number.isFinite(value.y) && Number.isFinite(value.z);
}
