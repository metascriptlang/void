import { UniformBlock } from "../void3d/material";
import { DrawContext, reserveUniforms, writeUniforms, releaseUniforms } from "../void3d/draw";
import {
	UniformPool,
	UniformError,
	GROWING_POOL_LIMIT,
	reserveRange,
	releaseRange,
	writeRange,
} from "../void3d/uniformPool";

const NONE: UniformBlock = { store: 0, slot: 0, offset: -1, length: 0, generation: 0 };

function lengthOf(n: int32): int32 {
	return 1 + (n * 7) % 13;
}

function fill(block: UniformBlock, n: int32): Vec<float32> {
	let values: Vec<float32> = [];
	for (let i = 0; i < block.length; i++) { values.push((n * 16 + i) as float32); }
	return values;
}

test "a growing pool reserves far past its first size, and every block reads back as written" {
	let pool: UniformPool = UniformPool.growing(4);
	let blocks: Vec<UniformBlock> = [];
	for (let n = 0; n < 3000; n++) {
		const block: UniformBlock = try reserveRange(pool, 1, lengthOf(n)) catch NONE;
		assert block.offset >= 0 && block.length == lengthOf(n);
		assert writeRange(pool, block, fill(block, n)).ok;
		blocks.push(block);
	}
	assert blocks[0].offset == 0 && blocks[1].offset == lengthOf(0);
	for (let n = 0; n < 3000; n++) {
		assert pool.holds(blocks[n]);
		const want: Vec<float32> = fill(blocks[n], n);
		for (let i = 0; i < blocks[n].length; i++) {
			assert pool.values[blocks[n].offset + i] == want[i];
		}
	}
	for (let n = 0; n < 3000; n++) { assert releaseRange(pool, blocks[n]).ok; }
	assert pool.liveRanges() == 0;
	const again: UniformBlock = try reserveRange(pool, 1, lengthOf(5)) catch NONE;
	assert again.length == lengthOf(5) && again.generation == 2;
}

test "a pool made with a size still refuses what does not fit, and a growing one refuses past its limit" {
	let fixed: UniformPool = UniformPool.withCapacity(8);
	assert reserveRange(fixed, 1, 8).ok;
	const refused: Result<UniformBlock, UniformError> = reserveRange(fixed, 1, 1);
	assert !refused.ok && refused.error == UniformError.PoolFull && fixed.capacity() == 8;
	let growing: UniformPool = UniformPool.growing(0);
	assert growing.fits([GROWING_POOL_LIMIT]).ok && !growing.fits([GROWING_POOL_LIMIT + 1]).ok;
	const past: Result<UniformBlock, UniformError> = reserveRange(growing, 1, GROWING_POOL_LIMIT + 1);
	assert !past.ok && past.error == UniformError.PoolFull;
	assert growing.capacity() == 0 && growing.used == 0;
	assert reserveRange(growing, 1, 4).ok && growing.capacity() >= 4;
}

test "a draw context made to grow reserves, writes and releases past its first size" {
	const context: DrawContext = DrawContext.withGrowingUniforms(8);
	let blocks: Vec<UniformBlock> = [];
	for (let n = 0; n < 200; n++) {
		const block: UniformBlock = try reserveUniforms(context, 2, 8) catch NONE;
		assert block.length == 8 && writeUniforms(context, block, fill(block, n)).ok;
		blocks.push(block);
	}
	for (let n = 0; n < 200; n++) {
		const want: Vec<float32> = fill(blocks[n], n);
		for (let i = 0; i < 8; i++) {
			assert context.uniforms.values[blocks[n].offset + i] == want[i];
		}
		assert releaseUniforms(context, blocks[n]).ok;
	}
	assert context.uniforms.liveRanges() == 0;
}
