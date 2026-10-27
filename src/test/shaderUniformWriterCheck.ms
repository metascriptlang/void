// A uniform block reserved from the struct the shader declares and written as a whole value of that
// struct: each field lands where the layout of the block puts it, every lane the fields leave open is
// zero, and a block the renderers write by hand today comes out byte for byte the same.

import { Mat4 } from "../math/math3d";
import { OutlineMaskParams } from "../void3d/post3d";
import { VertexParams } from "../void3d/shader3d";
import { TypedBlock, UniformBlock } from "../void3d/material";
import {
	UniformPool,
	UniformError,
	reserveRange,
	releaseRange,
	reserveBlock,
	writeBlock,
} from "../void3d/uniformPool";
import {
	DrawContext,
	reserveBlock as reserveContextBlock,
	writeBlock as writeContextBlock,
	releaseBlock as releaseContextBlock,
} from "../void3d/draw";
import { uniformSize } from "../shader/uniform";
import { Mat2x2f, Mat3x2f, Mat3x3f, Mat4x4f, Vec2f, Vec3f, Vec4f, bitcastF32toU32 } from "../shader/std";

struct Padded {
	eye: Vec3f;
	time: float32;
	tint: Vec3f;
	basis: Mat3x3f;
	span: Vec2f;
	scale: float32;
}

struct Wide {
	turn: Mat2x2f;
	flat: Mat3x2f;
	gain: float32;
	lights: Vec4f[2];
}

const SENTINEL: float32 = -7.0;

function filledPool(count: int32): UniformPool {
	let pool: UniformPool = UniformPool.withCapacity(count);
	for (let i = 0; i < count; i += 1) { pool.values[i] = SENTINEL; }
	return pool;
}

function lanes(values: Vec<float32>, from: int32, to: int32): float32[] {
	let out: float32[] = [];
	for (let i = from; i < to; i += 1) { out.push(values[i]); }
	return out;
}

function same(a: float32[], b: float32[]): boolean {
	if (a.length != b.length) { return false; }
	for (let i = 0; i < a.length; i += 1) {
		if (bitcastF32toU32(a[i]) != bitcastF32toU32(b[i])) { return false; }
	}
	return true;
}

function bitsEqual(a: Vec<float32>, b: Vec<float32>): boolean {
	return same(lanes(a, 0, a.length as int32), lanes(b, 0, b.length as int32));
}

function spacer(pool: UniformPool, count: int32): boolean {
	return reserveRange(pool, 0, count).ok;
}

test "a block reserved from its struct holds the floats the shader's block reflects" {
	let pool: UniformPool = UniformPool.withCapacity(128);
	const padded: Result<TypedBlock<Padded>, UniformError> = reserveBlock<Padded>(pool, 4);
	assert padded.ok && padded.value.block.length == uniformSize<Padded>() / 4 && padded.value.block.length == 24;
	assert padded.value.block.slot == 4;
	const wide: Result<TypedBlock<Wide>, UniformError> = reserveBlock<Wide>(pool, 5);
	assert wide.ok && wide.value.block.length == 20 && wide.value.block.offset == 24;
	const outline: Result<TypedBlock<OutlineMaskParams>, UniformError> = reserveBlock<OutlineMaskParams>(pool, 6);
	assert outline.ok && outline.value.block.length == 8;
	const vertex: Result<TypedBlock<VertexParams>, UniformError> = reserveBlock<VertexParams>(pool, 7);
	assert vertex.ok && vertex.value.block.length == 28;
}

test "a block that does not fit is the pool's error" {
	let pool: UniformPool = UniformPool.withCapacity(10);
	const full: Result<TypedBlock<Padded>, UniformError> = reserveBlock<Padded>(pool, 0);
	assert !full.ok && full.error == UniformError.PoolFull;
}

test "a vec3 writes its three lanes and the lane it leaves is zero, a float may take it" {
	let pool = filledPool(30);
	assert spacer(pool, 2);
	const block: Result<TypedBlock<Padded>, UniformError> = reserveBlock<Padded>(pool, 0);
	assert block.ok;
	const basis: Mat3x3f = { columns: [{ x: 10, y: 11, z: 12 }, { x: 13, y: 14, z: 15 }, { x: 16, y: 17, z: 18 }] };
	const tint: Vec3f = { x: 5, y: 6, z: 7 };
	const written = writeBlock(pool, block.value, {
		eye: { x: 1, y: 2, z: 3 },
		time: 4,
		tint: tint,
		basis: basis,
		span: { x: 20, y: 21 },
		scale: 22,
	});
	assert written.ok && written.value == 24;
	assert same(lanes(pool.values, 0, 2), [SENTINEL, SENTINEL]);
	assert same(lanes(pool.values, 2, 26), [1, 2, 3, 4, 5, 6, 7, 0, 10, 11, 12, 0, 13, 14, 15, 0, 16, 17, 18, 0, 20, 21, 22, 0]);
	assert same(lanes(pool.values, 26, 30), [SENTINEL, SENTINEL, SENTINEL, SENTINEL]);
}

test "a two-row matrix keeps eight-byte columns, an array takes its element stride" {
	let pool = filledPool(22);
	assert spacer(pool, 1);
	const block: Result<TypedBlock<Wide>, UniformError> = reserveBlock<Wide>(pool, 0);
	assert block.ok;
	const lights: Vec4f[2] = [{ x: 1, y: 2, z: 3, w: 4 }, { x: 5, y: 6, z: 7, w: 8 }];
	assert writeBlock(pool, block.value, {
		turn: { columns: [{ x: 30, y: 31 }, { x: 32, y: 33 }] },
		flat: { columns: [{ x: 40, y: 41 }, { x: 42, y: 43 }, { x: 44, y: 45 }] },
		gain: 9,
		lights: lights,
	}).ok;
	assert same(lanes(pool.values, 1, 21), [30, 31, 32, 33, 40, 41, 42, 43, 44, 45, 9, 0, 1, 2, 3, 4, 5, 6, 7, 8]);
	assert same(lanes(pool.values, 0, 1), [SENTINEL]);
	assert same(lanes(pool.values, 21, 22), [SENTINEL]);
}

test "a literal and a typed value write the same lanes" {
	let literal = filledPool(20);
	let typed = filledPool(20);
	const first: Result<TypedBlock<Wide>, UniformError> = reserveBlock<Wide>(literal, 0);
	const second: Result<TypedBlock<Wide>, UniformError> = reserveBlock<Wide>(typed, 0);
	assert first.ok && second.ok;
	const value: Wide = {
		turn: { columns: [{ x: 30, y: 31 }, { x: 32, y: 33 }] },
		flat: { columns: [{ x: 40, y: 41 }, { x: 42, y: 43 }, { x: 44, y: 45 }] },
		gain: 9,
		lights: [{ x: 1, y: 2, z: 3, w: 4 }, { x: 5, y: 6, z: 7, w: 8 }],
	};
	assert writeBlock(literal, first.value, {
		turn: { columns: [{ x: 30, y: 31 }, { x: 32, y: 33 }] },
		flat: { columns: [{ x: 40, y: 41 }, { x: 42, y: 43 }, { x: 44, y: 45 }] },
		gain: 9,
		lights: [{ x: 1, y: 2, z: 3, w: 4 }, { x: 5, y: 6, z: 7, w: 8 }],
	}).ok;
	assert writeBlock(typed, second.value, value).ok;
	assert bitsEqual(literal.values, typed.values);
}

let built: int32 = 0;

function builtWide(): Wide {
	built += 1;
	return {
		turn: { columns: [{ x: 30, y: 31 }, { x: 32, y: 33 }] },
		flat: { columns: [{ x: 40, y: 41 }, { x: 42, y: 43 }, { x: 44, y: 45 }] },
		gain: 9,
		lights: [{ x: 1, y: 2, z: 3, w: 4 }, { x: 5, y: 6, z: 7, w: 8 }],
	};
}

test "a call as the value runs once, however many lanes read it" {
	let pool = filledPool(20);
	const block: Result<TypedBlock<Wide>, UniformError> = reserveBlock<Wide>(pool, 0);
	assert block.ok;
	assert writeBlock(pool, block.value, builtWide()).ok;
	assert built == 1;
	assert same(lanes(pool.values, 0, 20), [30, 31, 32, 33, 40, 41, 42, 43, 44, 45, 9, 0, 1, 2, 3, 4, 5, 6, 7, 8]);
}

function outlineMaskOld(ref values: Vec<float32>, depthThreshold: float32, normalThreshold: float32, blend: float32, zeroToOne: boolean): void {
	values[0] = 2.0;
	values[1] = depthThreshold;
	values[2] = normalThreshold;
	values[3] = zeroToOne ? 1.0 : 2.0;
	values[4] = zeroToOne ? 0.0 : -1.0;
	values[5] = blend;
	values[6] = 0.0;
	values[7] = 0.0;
}

test "the outline mask block comes out the way forwardOutline writes it by hand" {
	assert uniformSize<OutlineMaskParams>() == 32;
	for (const zeroToOne of [true, false]) {
		let old = filledPool(8);
		outlineMaskOld(old.values, 0.25, 0.5, 0.75, zeroToOne);
		let made = filledPool(8);
		const block: Result<TypedBlock<OutlineMaskParams>, UniformError> = reserveBlock<OutlineMaskParams>(made, 0);
		assert block.ok;
		const depthMap: float32 = zeroToOne ? 0.0 : -1.0;
		const near: float32 = zeroToOne ? 1.0 : 2.0;
		const threshold: float32 = 0.25;
		assert writeBlock(made, block.value, {
			outlineEdge: { x: 2.0, y: threshold, z: 0.5, w: near },
			outlineDepthMap: { x: depthMap, y: 0.75, z: 0.0, w: 0.0 },
		}).ok;
		assert bitsEqual(old.values, made.values);
	}
}

function vertexParamsOld(ref values: Vec<float32>, m: Mat4, right: Vec3f, up: Vec3f): void {
	m.writeTo(values[0..16], 0);
	values[16] = right.x;
	values[17] = right.y;
	values[18] = right.z;
	values[20] = up.x;
	values[21] = up.y;
	values[22] = up.z;
}

test "the vertex block comes out the way the shadow pass writes it by hand, the unwritten lanes zero" {
	assert uniformSize<VertexParams>() == 112;
	const m: Mat4 = {
		m11: 1, m12: 2, m13: 3, m14: 4, m21: 5, m22: 6, m23: 7, m24: 8,
		m31: 9, m32: 10, m33: 11, m34: 12, m41: 13, m42: 14, m43: 15, m44: 16,
	};
	const right: Vec3f = { x: 0.5, y: 0.25, z: 0.125 };
	const up: Vec3f = { x: -1, y: -2, z: -3 };
	let old = UniformPool.withCapacity(28);
	for (let i = 0; i < 28; i += 1) { old.values[i] = 0.0; }
	vertexParamsOld(old.values, m, right, up);
	const view: Mat4x4f = { columns: [
		{ x: m.m11, y: m.m12, z: m.m13, w: m.m14 }, { x: m.m21, y: m.m22, z: m.m23, w: m.m24 },
		{ x: m.m31, y: m.m32, z: m.m33, w: m.m34 }, { x: m.m41, y: m.m42, z: m.m43, w: m.m44 }] };
	let made = filledPool(28);
	const block: Result<TypedBlock<VertexParams>, UniformError> = reserveBlock<VertexParams>(made, 0);
	assert block.ok;
	assert writeBlock(made, block.value, {
		viewProj: view,
		cameraRight: { x: right.x, y: right.y, z: right.z, w: 0.0 },
		cameraUp: { x: up.x, y: up.y, z: up.z, w: 0.0 },
		cameraPosition: { x: 0.0, y: 0.0, z: 0.0, w: 0.0 },
	}).ok;
	assert bitsEqual(old.values, made.values);
}

test "a released block is refused where it is written, and the range stays as it was" {
	let pool = filledPool(20);
	const block: Result<TypedBlock<Wide>, UniformError> = reserveBlock<Wide>(pool, 0);
	assert block.ok;
	assert releaseRange(pool, block.value.block).ok;
	const written = writeBlock(pool, block.value, builtWide());
	assert !written.ok && written.error == UniformError.Released;
	assert same(lanes(pool.values, 0, 20), lanes(filledPool(20).values, 0, 20));
}

test "a block of another pool is refused" {
	let pool = filledPool(20);
	let other = filledPool(20);
	const block: Result<TypedBlock<Wide>, UniformError> = reserveBlock<Wide>(other, 0);
	assert block.ok;
	const written = writeBlock(pool, block.value, builtWide());
	assert !written.ok && written.error == UniformError.Foreign;
}

test "a block of another length is refused, so a write never leaves its range" {
	let pool = filledPool(40);
	const four: Result<UniformBlock, UniformError> = reserveRange(pool, 0, 4);
	assert four.ok;
	const forged: TypedBlock<Wide> = { block: four.value };
	const written = writeBlock(pool, forged, builtWide());
	assert !written.ok && written.error == UniformError.WrongLength;
	assert same(lanes(pool.values, 0, 4), [SENTINEL, SENTINEL, SENTINEL, SENTINEL]);
}

test "a draw context reserves, writes and releases a typed block in its own pool" {
	let context: DrawContext = DrawContext.withUniformCapacity(16);
	const block: Result<TypedBlock<OutlineMaskParams>, UniformError> =
		reserveContextBlock<OutlineMaskParams>(context, 3);
	assert block.ok && block.value.block.slot == 3 && block.value.block.length == 8;
	const written = writeContextBlock(context, block.value, {
		outlineEdge: { x: 1.0, y: 2.0, z: 3.0, w: 4.0 },
		outlineDepthMap: { x: 5.0, y: 6.0, z: 7.0, w: 8.0 },
	});
	assert written.ok && written.value == 8;
	assert same(lanes(context.uniforms.values, 0, 8), [1, 2, 3, 4, 5, 6, 7, 8]);
	assert releaseContextBlock(context, block.value).ok;
	const stale = writeContextBlock(context, block.value, {
		outlineEdge: { x: 0.0, y: 0.0, z: 0.0, w: 0.0 },
		outlineDepthMap: { x: 0.0, y: 0.0, z: 0.0, w: 0.0 },
	});
	assert !stale.ok && stale.error == UniformError.Released;
	assert same(lanes(context.uniforms.values, 0, 8), [1, 2, 3, 4, 5, 6, 7, 8]);
}
