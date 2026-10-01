// The floats every uniform block lives in, sized once. A released range is handed out again to the
// next reserve of the same length, a generation later, and the pool never compacts: a material
// and a renderer hold their block's offset.

import { UniformBlock } from "./material";
import { nextGeneration } from "./slots";

export enum UniformError {
	PoolFull,
	WrongLength,
	Released,
	Owned,
}

export interface UniformPool {
	values: Vec<float32>;
	used: int32;
	lengths: Vec<int32>;
	generations: Vec<int32>;
	owned: Vec<boolean>;
	free: Vec<int32>;
}

export function withCapacity(this typeof UniformPool, capacity: int32): UniformPool {
	let lengths: Vec<int32> = new Array(capacity);
	let generations: Vec<int32> = new Array(capacity);
	let owned: Vec<boolean> = new Array(capacity);
	for (let i = 0; i < capacity; i++) {
		lengths[i] = 0;
		generations[i] = 0;
		owned[i] = false;
	}
	return {
		values: new Array(capacity),
		used: 0,
		lengths: lengths,
		generations: generations,
		owned: owned,
		free: [],
	};
}

export function capacity(this pool: UniformPool): int32 {
	return pool.values.length as int32;
}

export function unreserved(this pool: UniformPool): int32 {
	return pool.capacity() - pool.used;
}

export function freeRanges(this pool: UniformPool): int32 {
	return pool.free.length as int32;
}

export function fits(this pool: UniformPool, lengths: Span<int32>): Result<int32, UniformError> {
	let taken: Vec<boolean> = new Array(pool.free.length);
	for (let i = 0; i < (pool.free.length as int32); i++) { taken[i] = false; }
	let fresh: int32 = 0;
	for (const length of lengths) {
		let found: boolean = false;
		for (let i = 0; i < (pool.free.length as int32); i++) {
			if (taken[i] || pool.lengths[pool.free[i]] != length) { continue; }
			taken[i] = true;
			found = true;
			break;
		}
		if (!found) { fresh = fresh + length; }
	}
	if (fresh > pool.unreserved()) { return Result.err(UniformError.PoolFull); }
	return Result.ok(fresh);
}

export function isOwned(this pool: UniformPool, block: UniformBlock): boolean {
	return block.length > 0 && pool.holds(block) && pool.owned[block.offset];
}

export function holds(this pool: UniformPool, block: UniformBlock): boolean {
	if (block.length == 0) { return true; }
	if (block.offset < 0 || block.offset >= pool.used) { return false; }
	return pool.lengths[block.offset] == block.length &&
		pool.generations[block.offset] == block.generation;
}

function blockAt(this pool: UniformPool, slot: int32, offset: int32): UniformBlock {
	return {
		slot: slot,
		offset: offset,
		length: pool.lengths[offset],
		generation: pool.generations[offset],
	};
}

export function reserveRange(
	pool: UniformPool,
	slot: int32,
	length: int32,
): Result<UniformBlock, UniformError> {
	if (length < 0) { return Result.err(UniformError.WrongLength); }
	if (length == 0) { return Result.ok({ slot: slot, offset: 0, length: 0, generation: 0 }); }
	for (let i = (pool.free.length as int32) - 1; i >= 0; i--) {
		const offset: int32 = pool.free[i];
		if (pool.lengths[offset] != length) { continue; }
		const last: int32 = (pool.free.length as int32) - 1;
		pool.free[i] = pool.free[last];
		pool.free.pop();
		return Result.ok(pool.blockAt(slot, offset));
	}
	const offset: int32 = pool.used;
	if (length > pool.unreserved()) { return Result.err(UniformError.PoolFull); }
	pool.lengths[offset] = length;
	pool.generations[offset] = 1;
	pool.used = offset + length;
	return Result.ok(pool.blockAt(slot, offset));
}

export function ownRange(pool: UniformPool, block: UniformBlock): Result<int32, UniformError> {
	if (!pool.holds(block)) { return Result.err(UniformError.Released); }
	if (block.length == 0) { return Result.ok(0); }
	if (pool.owned[block.offset]) { return Result.err(UniformError.Owned); }
	pool.owned[block.offset] = true;
	return Result.ok(block.length);
}

export function disownRange(
	pool: UniformPool,
	block: UniformBlock,
): Result<int32, UniformError> {
	if (!pool.holds(block)) { return Result.err(UniformError.Released); }
	if (block.length > 0) { pool.owned[block.offset] = false; }
	return releaseRange(pool, block);
}

export function releaseRange(
	pool: UniformPool,
	block: UniformBlock,
): Result<int32, UniformError> {
	if (!pool.holds(block)) { return Result.err(UniformError.Released); }
	if (block.length == 0) { return Result.ok(0); }
	if (pool.owned[block.offset]) { return Result.err(UniformError.Owned); }
	const next: int32 = nextGeneration(pool.generations[block.offset]);
	pool.generations[block.offset] = next;
	if (next != 0) { pool.free.push(block.offset); }
	return Result.ok(block.length);
}

export function writeRange(
	pool: UniformPool,
	block: UniformBlock,
	values: Span<float32>,
): Result<int32, UniformError> {
	if ((values.length as int32) != block.length) { return Result.err(UniformError.WrongLength); }
	if (!pool.holds(block)) { return Result.err(UniformError.Released); }
	for (let i = 0; i < block.length; i++) {
		pool.values[block.offset + i] = values[i];
	}
	return Result.ok(block.length);
}
