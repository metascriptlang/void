import { contextGeneration } from "../gpu/door";
import { PipelineCache, PipelineKey, IndexType, indexOf, record, closePipelines } from "../gpu/pipeline";

function keyOf(n: int32): PipelineKey {
	return {
		program: n % 326,
		layout: (n / 326) % 7,
		indexType: n % 2 == 0 ? IndexType.Uint16 : IndexType.Uint32,
		state: ((n * 40503) & 0xFFFF) as uint32,
		targets: (n / 11) as uint32,
		stencilOps: (n % 3) as uint32,
		stencilMasks: (n % 5) as uint32,
		depthBias: 0,
		depthSlope: 0.0,
	};
}

function linear(cache: PipelineCache, key: PipelineKey): int32 {
	for (let i = 0; i < (cache.entries.length as int32); i++) {
		if (cache.entries[i].key == key) { return i; }
	}
	return -1;
}

function agrees(cache: PipelineCache, from: int32, to: int32): boolean {
	for (let n = from; n < to; n++) {
		if (cache.indexOf(keyOf(n)) != linear(cache, keyOf(n))) { return false; }
	}
	return true;
}

test "a lookup answers what a scan of the entries answers, through every growth of the table" {
	const cache: PipelineCache = PipelineCache.empty();
	assert cache.indexOf(keyOf(0)) == -1;
	let checked: int32 = 0;
	for (let n = 0; n < 5000; n++) {
		record(cache, keyOf(n), (n + 1) as uint32);
		if (n == 0 || n == 7 || n == 8 || n == 63 || n == 64 || n == 1000 || n == 4999) {
			assert agrees(cache, 0, n + 200);
			checked = checked + 1;
		}
	}
	assert checked == 7;
	assert cache.entries.length == 5000;
	for (let n = 0; n < 5000; n++) {
		assert cache.indexOf(keyOf(n)) == n;
		assert cache.entries[n].pipeline == (n + 1) as uint32;
	}
	assert cache.indexOf(keyOf(5000)) == -1;
}

test "recording a key the cache holds sets its handle and adds no entry" {
	const cache: PipelineCache = PipelineCache.empty();
	for (let n = 0; n < 40; n++) { record(cache, keyOf(n), (n + 1) as uint32); }
	record(cache, keyOf(17), 0);
	assert cache.entries.length == 40 && cache.entries[17].pipeline == 0;
	record(cache, keyOf(17), 99);
	assert cache.entries.length == 40 && cache.entries[17].pipeline == 99;
	assert cache.indexOf(keyOf(17)) == 17;
}

test "keys that differ in one field are different entries" {
	const cache: PipelineCache = PipelineCache.empty();
	const base: PipelineKey = keyOf(5);
	const variants: Vec<PipelineKey> = [
		base,
		{ ...base, program: base.program + 1 },
		{ ...base, layout: base.layout + 1 },
		{ ...base, indexType: base.indexType == IndexType.Uint16 ? IndexType.Uint32 : IndexType.Uint16 },
		{ ...base, state: base.state + 1 },
		{ ...base, targets: base.targets + 1 },
		{ ...base, stencilOps: base.stencilOps + 1 },
		{ ...base, stencilMasks: base.stencilMasks + 1 },
	];
	for (let i = 0; i < (variants.length as int32); i++) { record(cache, variants[i], (i + 1) as uint32); }
	assert cache.entries.length == 8;
	for (let i = 0; i < (variants.length as int32); i++) { assert cache.indexOf(variants[i]) == i; }
}

test "closing a cache drops its table with its entries" {
	const cache: PipelineCache = PipelineCache.empty();
	for (let n = 0; n < 20; n++) { record(cache, keyOf(n), (n + 1) as uint32); }
	cache.generation = contextGeneration() + 1;
	closePipelines(cache);
	assert cache.slots.length == 0 && cache.indexOf(keyOf(3)) == -1;
}
