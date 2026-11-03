import { FontFeature } from "./font";
import { ShapeDirection, ShapedGlyph } from "./shaper";

export const SHAPE_BREAK: int32 = -1;
export const SHAPE_CACHE_BUCKETS: int32 = 256;
export const SHAPE_CACHE_BUCKET_SIZE: int32 = 8;

export struct ShapeKey {
	face: int32;
	direction: ShapeDirection;
	features: Vec<FontFeature>;
	input: Vec<int32>;
}

export class ShapedRun {
	glyphs: Vec<ShapedGlyph> = new Array(0);
}

struct ShapeEntry {
	hash: int64;
	used: int64;
	key: ShapeKey;
	run: ShapedRun;
}

let buckets: Vec<Vec<ShapeEntry>> = new Array(0);
let clock: int64 = 0;
let hits: int32 = 0;

function mix(hash: int64, value: int64): int64 {
	return ((hash ^ (value & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF;
}

export function shapeKeyHash(key: ShapeKey): int64 {
	let hash: int64 = 2166136261;
	hash = mix(hash, key.face as int64);
	hash = mix(hash, key.direction as int64);
	for (const feature of key.features) {
		for (let i = 0; i < feature.tag.length; i++) {
			hash = mix(hash, feature.tag.charCodeAt(i) as int64);
		}
		hash = mix(hash, feature.value as int64);
	}
	for (const value of key.input) { hash = mix(hash, value as int64); }
	return hash;
}

function sameKey(a: ShapeKey, b: ShapeKey): boolean {
	if (a.face != b.face || a.direction != b.direction) { return false; }
	if (a.features.length != b.features.length || a.input.length != b.input.length) {
		return false;
	}
	for (let i = 0; i < (a.features.length as int32); i++) {
		if (a.features[i].tag != b.features[i].tag || a.features[i].value != b.features[i].value) {
			return false;
		}
	}
	for (let i = 0; i < (a.input.length as int32); i++) {
		if (a.input[i] != b.input[i]) { return false; }
	}
	return true;
}

function bucketOf(hash: int64): int32 {
	if (buckets.length == 0) {
		for (let i = 0; i < SHAPE_CACHE_BUCKETS; i++) { buckets.push(new Array(0)); }
	}
	return (hash % (SHAPE_CACHE_BUCKETS as int64)) as int32;
}

export function shapeCacheGet(key: ShapeKey, hash: int64): ShapedRun | null {
	const b: int32 = bucketOf(hash);
	for (let i = (buckets[b].length as int32) - 1; i >= 0; i--) {
		if (buckets[b][i].hash != hash || !sameKey(buckets[b][i].key, key)) { continue; }
		clock = clock + 1;
		buckets[b][i].used = clock;
		hits = hits + 1;
		return buckets[b][i].run;
	}
	return null;
}

export function shapeCachePut(key: ShapeKey, hash: int64, run: ShapedRun): void {
	const b: int32 = bucketOf(hash);
	clock = clock + 1;
	const entry: ShapeEntry = { hash: hash, used: clock, key: key, run: run };
	if ((buckets[b].length as int32) < SHAPE_CACHE_BUCKET_SIZE) {
		buckets[b].push(entry);
		return;
	}
	let oldest: int32 = 0;
	for (let i = 1; i < SHAPE_CACHE_BUCKET_SIZE; i++) {
		if (buckets[b][i].used < buckets[b][oldest].used) { oldest = i; }
	}
	buckets[b][oldest] = entry;
}

export function shapeCacheHits(): int32 {
	return hits;
}
