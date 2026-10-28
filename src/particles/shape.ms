// Unity's Shape module (docs/PARTICLES-SIM.md §2): a spawn position and direction in the shape's
// local space, where cone, circle, rectangle and box emit along +Z as Unity's do. Every draw is
// keyed on the particle's seed, so a sample is a pure function of the seed and the emitter's arc
// and radius timers.

import { Vec3, vec3, Mat4, scaling, rotationX, rotationY, rotationZ, translation, transformDirection } from "../math/math3d";
import { ShapeModule, ShapeType, ShapeMultiModeValue } from "./asset";
import { unitDraw } from "./curve";

export struct ShapeSample {
	position: Vec3;
	direction: Vec3;
}

// Where a spawn sits among the particles of its step or burst, for BurstSpread, and the emitter's
// Loop/PingPong timers at the spawn instant.
export struct ShapeSlot {
	index: int32;
	count: int32;
	arcTimer: float32;
	radiusTimer: float32;
}

export enum ShapeError {
	NeedsMesh,
	NegativeRadius,
	ThicknessOutOfRange,
}

const TWO_PI: float32 = 6.283185307179586;
const DEGREE: float32 = 0.017453292519943295;

const DRAW_A: uint32 = 101;
const DRAW_B: uint32 = 102;
const DRAW_C: uint32 = 103;
const DRAW_ARC: uint32 = 104;
const DRAW_RADIUS: uint32 = 105;
const DRAW_FACE: uint32 = 106;
const DRAW_SIDE: uint32 = 107;
const DRAW_DIR_A: uint32 = 108;
const DRAW_DIR_B: uint32 = 109;
const DRAW_POS_X: uint32 = 110;
const DRAW_POS_Y: uint32 = 111;
const DRAW_POS_Z: uint32 = 112;
const DRAW_VOLUME: uint32 = 113;

// Refuses what the simulation cannot sample: the mesh and sprite sources need the app's geometry.
export function validate(this shape: ShapeModule): Result<int32, ShapeError> {
	if (!shape.enabled) { return Result.ok(0); }
	const needsMesh: boolean = match (shape.shapeType) {
		ShapeType.Mesh | ShapeType.MeshRenderer | ShapeType.SkinnedMeshRenderer
			| ShapeType.Sprite | ShapeType.SpriteRenderer => true,
		_ => false,
	};
	if (needsMesh) { return Result.err(ShapeError.NeedsMesh); }
	if (shape.radius < 0.0 || shape.donutRadius < 0.0) { return Result.err(ShapeError.NegativeRadius); }
	if (shape.radiusThickness < 0.0 || shape.radiusThickness > 1.0) {
		return Result.err(ShapeError.ThicknessOutOfRange);
	}
	return Result.ok(1);
}

// The shape's own transform: scale, then Unity's Z-X-Y Euler rotation, then translation.
export function shapeMatrix(this shape: ShapeModule): Mat4 {
	const r: Vec3 = shape.rotation;
	return scaling(shape.scale.x, shape.scale.y, shape.scale.z) * rotationZ(r.z * DEGREE)
		* rotationX(r.x * DEGREE) * rotationY(r.y * DEGREE)
		* translation(shape.position.x, shape.position.y, shape.position.z);
}

function fract(x: float32): float32 {
	return x - (Math.floor(x as float64) as float32);
}

// One multi-mode value in [0, 1]: Random, Loop, PingPong or BurstSpread, then quantized by spread.
// BurstSpread reaches both ends of an open range and stops one step short of closing a full
// circle (tests/unity/goldens/shape_circle_arc180_burstspread4, _arc360_).
function multiMode(
	mode: ShapeMultiModeValue, spread: float32, timer: float32, random: float32, slot: ShapeSlot,
	closed: boolean,
): float32 {
	let u: float32 = match (mode) {
		ShapeMultiModeValue.Random => random,
		ShapeMultiModeValue.Loop => fract(timer),
		ShapeMultiModeValue.PingPong => {
			const x: float32 = fract(timer * 0.5) * 2.0;
			x > 1.0 ? 2.0 - x : x
		},
		ShapeMultiModeValue.BurstSpread => {
			const steps: int32 = closed ? slot.count : slot.count - 1;
			steps > 0 ? (slot.index as float32) / (steps as float32) : 0.0
		},
	};
	if (spread > 0.0) { u = (Math.floor((u / spread) as float64) as float32) * spread; }
	return u;
}

function unitSphere(seed: uint32): Vec3 {
	const z: float32 = unitDraw(seed, DRAW_A) * 2.0 - 1.0;
	const phi: float32 = unitDraw(seed, DRAW_B) * TWO_PI;
	const ring: float32 = Math.sqrt((1.0 - z * z) as float64) as float32;
	return vec3(ring * (Math.cos(phi as float64) as float32), ring * (Math.sin(phi as float64) as float32), z);
}

// The radial fraction that fills a shell of `thickness` uniformly in `dimensions` (2 or 3).
function shellFraction(u: float32, thickness: float32, dimensions: int32): float32 {
	const inner: float32 = 1.0 - thickness;
	if (dimensions == 3) {
		const cube: float32 = inner * inner * inner;
		return Math.cbrt((cube + (1.0 - cube) * u) as float64) as float32;
	}
	const square: float32 = inner * inner;
	return Math.sqrt((square + (1.0 - square) * u) as float64) as float32;
}

function arcAngle(shape: ShapeModule, seed: uint32, slot: ShapeSlot): float32 {
	const u: float32 =
		multiMode(shape.arcMode, shape.arcSpread, slot.arcTimer, unitDraw(seed, DRAW_ARC), slot, shape.arc >= 360.0);
	return u * shape.arc * DEGREE;
}

function radialFraction(shape: ShapeModule, seed: uint32, slot: ShapeSlot, dimensions: int32): float32 {
	const u: float32 = multiMode(
		shape.radiusMode, shape.radiusSpread, slot.radiusTimer, unitDraw(seed, DRAW_RADIUS), slot, false,
	);
	return shellFraction(u, shape.radiusThickness, dimensions);
}

function boxSample(shape: ShapeModule, seed: uint32): Vec3 {
	const x: float32 = unitDraw(seed, DRAW_A) - 0.5;
	const y: float32 = unitDraw(seed, DRAW_B) - 0.5;
	const z: float32 = unitDraw(seed, DRAW_C) - 0.5;
	if (shape.shapeType == ShapeType.Box) { return vec3(x, y, z); }
	const side: float32 = unitDraw(seed, DRAW_SIDE) < 0.5 ? -0.5 : 0.5;
	const pick: float32 = unitDraw(seed, DRAW_FACE) * 3.0;
	if (shape.shapeType == ShapeType.BoxShell) {
		if (pick < 1.0) { return vec3(side, y, z); }
		if (pick < 2.0) { return vec3(x, side, z); }
		return vec3(x, y, side);
	}
	const other: float32 = unitDraw(seed, DRAW_VOLUME) < 0.5 ? -0.5 : 0.5;
	if (pick < 1.0) { return vec3(x, side, other); }
	if (pick < 2.0) { return vec3(side, y, other); }
	return vec3(side, other, z);
}

// The shape-local sample before the direction options.
function rawSample(shape: ShapeModule, seed: uint32, slot: ShapeSlot): ShapeSample {
	const up: Vec3 = vec3(0.0, 0.0, 1.0);
	match (shape.shapeType) {
		ShapeType.Sphere | ShapeType.Hemisphere => {
			let dir: Vec3 = unitSphere(seed);
			if (shape.shapeType == ShapeType.Hemisphere && dir.z < 0.0) { dir = vec3(dir.x, dir.y, -dir.z); }
			const rad: float32 = shape.radius * radialFraction(shape, seed, slot, 3);
			return { position: dir.scaled(rad), direction: dir };
		},
		ShapeType.Circle => {
			const theta: float32 = arcAngle(shape, seed, slot);
			const radial: Vec3 = vec3(Math.cos(theta as float64) as float32, Math.sin(theta as float64) as float32, 0.0);
			return { position: radial.scaled(shape.radius * radialFraction(shape, seed, slot, 2)), direction: radial };
		},
		ShapeType.Cone | ShapeType.ConeVolume => {
			const theta: float32 = arcAngle(shape, seed, slot);
			const radial: Vec3 = vec3(Math.cos(theta as float64) as float32, Math.sin(theta as float64) as float32, 0.0);
			const f: float32 = radialFraction(shape, seed, slot, 2);
			const spread: float32 = Math.tan((shape.angle * DEGREE) as float64) as float32;
			const dir: Vec3 = (radial.scaled(f * spread) + up).normalized();
			let position: Vec3 = radial.scaled(shape.radius * f);
			if (shape.shapeType == ShapeType.ConeVolume) {
				const along: float32 = shape.length * unitDraw(seed, DRAW_VOLUME);
				position = position + dir.scaled(along / dir.z);
			}
			return { position: position, direction: dir };
		},
		ShapeType.Box | ShapeType.BoxShell | ShapeType.BoxEdge => {
			return { position: boxSample(shape, seed), direction: up };
		},
		ShapeType.Rectangle => {
			const x: float32 = unitDraw(seed, DRAW_A) - 0.5;
			const y: float32 = unitDraw(seed, DRAW_B) - 0.5;
			return { position: vec3(x, y, 0.0), direction: up };
		},
		ShapeType.SingleSidedEdge => {
			const u: float32 = multiMode(
				shape.radiusMode, shape.radiusSpread, slot.radiusTimer, unitDraw(seed, DRAW_RADIUS), slot, false,
			);
			return { position: vec3((u * 2.0 - 1.0) * shape.radius, 0.0, 0.0), direction: vec3(0.0, 1.0, 0.0) };
		},
		ShapeType.Donut => {
			const theta: float32 = arcAngle(shape, seed, slot);
			const radial: Vec3 = vec3(Math.cos(theta as float64) as float32, Math.sin(theta as float64) as float32, 0.0);
			const phi: float32 = unitDraw(seed, DRAW_C) * TWO_PI;
			const tube: Vec3 = radial.scaled(Math.cos(phi as float64) as float32) + up.scaled(Math.sin(phi as float64) as float32);
			const tubeRadius: float32 = shape.donutRadius * radialFraction(shape, seed, slot, 2);
			return { position: radial.scaled(shape.radius) + tube.scaled(tubeRadius), direction: tube };
		},
		_ => { return { position: vec3(0.0, 0.0, 0.0), direction: up }; },
	};
}

function blendDirection(from: Vec3, to: Vec3, amount: float32): Vec3 {
	const mixed: Vec3 = from.lerp(to, amount);
	return mixed.lengthSquared() > 0.0 ? mixed.normalized() : from;
}

// The sample in the shape's own space with Unity's direction and position options applied
// (SIM §2.3: spherize, then randomize, then the random position offset).
export function sampleShape(shape: ShapeModule, seed: uint32, slot: ShapeSlot): ShapeSample {
	if (!shape.enabled) { return { position: vec3(0.0, 0.0, 0.0), direction: vec3(0.0, 0.0, 1.0) }; }
	const raw: ShapeSample = rawSample(shape, seed, slot);
	let direction: Vec3 = raw.direction;
	let position: Vec3 = raw.position;
	if (shape.sphericalDirectionAmount > 0.0 && position.lengthSquared() > 0.0) {
		direction = blendDirection(direction, position.normalized(), shape.sphericalDirectionAmount);
	}
	if (shape.randomDirectionAmount > 0.0) {
		const z: float32 = unitDraw(seed, DRAW_DIR_A) * 2.0 - 1.0;
		const phi: float32 = unitDraw(seed, DRAW_DIR_B) * TWO_PI;
		const ring: float32 = Math.sqrt((1.0 - z * z) as float64) as float32;
		const random: Vec3 = vec3(ring * (Math.cos(phi as float64) as float32), ring * (Math.sin(phi as float64) as float32), z);
		direction = blendDirection(direction, random, shape.randomDirectionAmount);
	}
	if (shape.randomPositionAmount > 0.0) {
		const a: float32 = shape.randomPositionAmount;
		position = position + vec3(
			(unitDraw(seed, DRAW_POS_X) * 2.0 - 1.0) * a,
			(unitDraw(seed, DRAW_POS_Y) * 2.0 - 1.0) * a,
			(unitDraw(seed, DRAW_POS_Z) * 2.0 - 1.0) * a,
		);
	}
	const m: Mat4 = shape.shapeMatrix();
	return { position: position * m, direction: direction.transformDirection(m).normalized() };
}
