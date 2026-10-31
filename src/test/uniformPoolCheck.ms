import { TypedBlock, UniformBlock } from "../void3d/material";
import { LAST_GENERATION } from "../void3d/slots";
import {
	UniformPool,
	UniformError,
	reserveRange,
	reserveBlock,
	releaseRange,
	writeRange,
	writeBlock,
	uniformWrites,
	ownRange,
	disownRange,
} from "../void3d/uniformPool";

struct Pair {
	a: float32;
	b: float32;
}

const NONE: UniformBlock = { store: 0, slot: 0, offset: -1, length: 0, generation: 0 };

function reserved(pool: UniformPool, length: int32): UniformBlock {
	return try reserveRange(pool, 2, length) catch NONE;
}

test "a released range goes to the next reserve of its length, a generation later" {
	const pool: UniformPool = UniformPool.withCapacity(16);
	const first: UniformBlock = reserved(pool, 4);
	const second: UniformBlock = reserved(pool, 4);
	assert releaseRange(pool, first).ok;
	const again: UniformBlock = reserved(pool, 4);
	assert again.offset == first.offset && again.generation == first.generation + 1;
	assert second.offset == 4 && pool.holds(second);
	assert pool.used == 8 && pool.freeRanges() == 0;
}

test "a range of another length is not reused and the pool never compacts" {
	const pool: UniformPool = UniformPool.withCapacity(16);
	const four: UniformBlock = reserved(pool, 4);
	const eight: UniformBlock = reserved(pool, 8);
	assert releaseRange(pool, four).ok;
	const two: UniformBlock = reserved(pool, 2);
	assert two.offset == 12 && eight.offset == 4 && pool.holds(eight);
	const refused: Result<UniformBlock, UniformError> = reserveRange(pool, 2, 3);
	assert !refused.ok && refused.error == UniformError.PoolFull;
	assert pool.freeRanges() == 1;
}

test "a released block is refused where it is written and released again" {
	const pool: UniformPool = UniformPool.withCapacity(8);
	const block: UniformBlock = reserved(pool, 4);
	const values: Vec<float32> = [1.0, 2.0, 3.0, 4.0];
	assert writeRange(pool, block, values).ok;
	assert releaseRange(pool, block).ok;
	assert !pool.holds(block);
	const written: Result<int32, UniformError> = writeRange(pool, block, values);
	assert !written.ok && written.error == UniformError.Released;
	const twice: Result<int32, UniformError> = releaseRange(pool, block);
	assert !twice.ok && twice.error == UniformError.Released;
	const newer: UniformBlock = reserved(pool, 4);
	assert writeRange(pool, newer, values).ok;
	assert !writeRange(pool, block, values).ok;
}

test "a block of no floats names no range and is always held" {
	const pool: UniformPool = UniformPool.withCapacity(4);
	const empty: UniformBlock = reserved(pool, 0);
	assert empty.length == 0 && pool.used == 0 && pool.holds(empty);
	assert releaseRange(pool, empty).ok && pool.freeRanges() == 0;
}

test "a range whose generation would wrap is retired, not handed out again" {
	const pool: UniformPool = UniformPool.withCapacity(8);
	const block: UniformBlock = reserved(pool, 4);
	pool.generations[block.offset] = LAST_GENERATION;
	const last: UniformBlock = { ...block, generation: LAST_GENERATION };
	assert releaseRange(pool, last).ok;
	assert !pool.holds(last) && pool.freeRanges() == 0;
	const next: UniformBlock = reserved(pool, 4);
	assert next.offset == 4;
}

test "blocks fit from released ranges of their length first, then from the rest" {
	const pool: UniformPool = UniformPool.withCapacity(12);
	const four: UniformBlock = reserved(pool, 4);
	const eight: UniformBlock = reserved(pool, 8);
	assert pool.unreserved() == 0;
	assert releaseRange(pool, four).ok && releaseRange(pool, eight).ok;
	const both: Vec<int32> = [8, 4];
	const twoFours: Vec<int32> = [4, 4];
	assert pool.fits(both).ok;
	assert !pool.fits(twoFours).ok;
	const none: Vec<int32> = [];
	assert pool.fits(none).ok;
}

test "an owned range is released only by its owner" {
	const pool: UniformPool = UniformPool.withCapacity(8);
	const block: UniformBlock = reserved(pool, 4);
	assert ownRange(pool, block).ok;
	assert pool.isOwned(block);
	const again: Result<int32, UniformError> = ownRange(pool, block);
	assert !again.ok && again.error == UniformError.Owned;
	const loose: Result<int32, UniformError> = releaseRange(pool, block);
	assert !loose.ok && loose.error == UniformError.Owned;
	assert disownRange(pool, block).ok;
	assert !pool.holds(block) && pool.freeRanges() == 1;
	const reused: UniformBlock = reserved(pool, 4);
	assert !pool.isOwned(reused);
}

test "a typed block write advances the write counter like a range write" {
	const pool: UniformPool = UniformPool.withCapacity(8);
	const typed: Result<TypedBlock<Pair>, UniformError> = reserveBlock<Pair>(pool, 0);
	assert typed.ok;
	const before: int64 = uniformWrites();
	assert writeBlock(pool, typed.value, { a: 1, b: 2 }).ok;
	assert uniformWrites() == before + 1;
	let floats: Vec<float32> = new Array(typed.value.block.length);
	floats[0] = 3.0;
	assert writeRange(pool, typed.value.block, floats).ok;
	assert uniformWrites() == before + 2;
	assert pool.values[typed.value.block.offset] == 3;
}
