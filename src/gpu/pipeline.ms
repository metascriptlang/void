// Port of h3d.impl.PipelineCache / PipelineBuilder: render state + program + vertex layout +
// target formats → one key → one sokol pipeline, created on first use and reused after.
//
// A program or layout here is a door registry id (door.ms), not a layer's enum: the door is
// what both render layers build pipelines through, and each adds its own base to its
// ordinals (void3d: gpu3d.ms doorProgram / doorLayout).

import { stop } from "./stop";
import { RenderState } from "./state";
import { TargetLayout } from "./target";
import { IndexType, PipelineDescriptor, doorLayoutCount, stencilTargetRefusal } from "./doorGpu.ms";
import {
	makeShader,
	uniformSlotMask,
	makePipeline,
	destroyShader,
	destroyPipeline,
	programCount,
	contextGeneration,
	passState,
	PassState,
} from "./door";

export { IndexType } from "./doorGpu.ms";

export struct PipelineKey {
	program: int32;
	layout: int32;
	indexType: IndexType;
	state: uint32;
	targets: uint32;
	// RenderState.stencilOps / stencilMasks: both 0 without a stencil.
	stencilOps: uint32;
	stencilMasks: uint32;
}

export struct PipelineEntry {
	key: PipelineKey;
	pipeline: uint32;
}

export interface PipelineCache {
	entries: Vec<PipelineEntry>;
	// Open addressing over `entries`, an entry's index plus one in the slot its key hashes to,
	// 0 when empty: at least twice as many slots as entries, so a lookup probes a few.
	slots: Vec<int32>;
	shaders: Vec<uint32>;
	blockSlots: Vec<uint32>;
	// The GPU context its handles belong to: renderers sharing a DrawContext forget them once.
	generation: int32;
	closed: boolean;
}

export function empty(this typeof PipelineCache): PipelineCache {
	return {
		entries: [],
		slots: [],
		shaders: [],
		blockSlots: [],
		generation: 0,
		closed: false,
	};
}

function selectedIndexType(indexed: boolean, format: IndexType): IndexType {
	if (!indexed) { return IndexType.None; }
	if (format != IndexType.Uint16 && format != IndexType.Uint32) {
		stop(`indexed pipeline with invalid index type ${format.toString()}`);
	}
	return format;
}

export function pipelineKey(
	program: int32,
	layout: int32,
	indexed: boolean,
	state: RenderState,
	targets: TargetLayout,
	format: IndexType = IndexType.Uint16,
): PipelineKey {
	return {
		program: program,
		layout: layout,
		indexType: selectedIndexType(indexed, format),
		state: state.bits(),
		targets: targets.formatBits(),
		stencilOps: state.stencilOps(),
		stencilMasks: state.stencilMasks(),
	};
}

export function targetLayout(this key: PipelineKey): TargetLayout {
	return TargetLayout.fromFormatBits(key.targets);
}

export function renderState(this key: PipelineKey): RenderState {
	return RenderState.fromBits(key.state)
		.withStencil(RenderState.fromStencilWords(key.stencilOps, key.stencilMasks));
}

// `program=<id> layout=<id> colors=… depth=… sampleCount=… culling=…`: which pipeline a cache
// entry is, for logs and for comparing two entries by eye.
export function toString(this key: PipelineKey): string {
	return `program=${key.program} layout=${key.layout} ` +
		`indexType=${key.indexType.toString()} ` +
		`${key.targetLayout().toString()} ${key.renderState().toString()}`;
}

export function contains(this cache: PipelineCache, key: PipelineKey): boolean {
	return !cache.closed && cache.indexOf(key) >= 0;
}

export function keyHash(key: PipelineKey): uint32 {
	let h: uint32 = (key.program as uint32) * 2654435761;
	h = (h ^ (key.layout as uint32)) * 16777619;
	h = (h ^ ((key.indexType as int32) as uint32)) * 16777619;
	h = (h ^ key.state) * 16777619;
	h = (h ^ key.targets) * 16777619;
	h = (h ^ key.stencilOps) * 16777619;
	h = (h ^ key.stencilMasks) * 16777619;
	return h ^ (h >> 15);
}

// The key's hash picks a bucket and the keys in it are compared. The entry's index, -1 when the
// cache holds none for `key`.
export function indexOf(this cache: PipelineCache, key: PipelineKey): int32 {
	if (cache.slots.length == 0) { return -1; }
	const mask: uint32 = ((cache.slots.length as int32) - 1) as uint32;
	let at: int32 = (keyHash(key) & mask) as int32;
	while (cache.slots[at] != 0) {
		const found: int32 = cache.slots[at] - 1;
		if (cache.entries[found].key == key) { return found; }
		at = (at + 1) & (mask as int32);
	}
	return -1;
}

function place(cache: PipelineCache, index: int32): void {
	const mask: uint32 = ((cache.slots.length as int32) - 1) as uint32;
	let at: int32 = (keyHash(cache.entries[index].key) & mask) as int32;
	while (cache.slots[at] != 0) { at = (at + 1) & (mask as int32); }
	cache.slots[at] = index + 1;
}

// Adds an entry for a key the cache holds none for, or sets the handle of the one it holds.
export function record(cache: PipelineCache, key: PipelineKey, pipeline: uint32): void {
	const found: int32 = cache.indexOf(key);
	if (found >= 0) {
		cache.entries[found].pipeline = pipeline;
		return;
	}
	if ((cache.slots.length as int32) < 2 * ((cache.entries.length as int32) + 1)) {
		let size: int32 = 16;
		while (size < 4 * ((cache.entries.length as int32) + 1)) { size = size * 2; }
		cache.slots = new Array(size);
		for (let i = 0; i < size; i++) { cache.slots[i] = 0; }
		for (let i = 0; i < (cache.entries.length as int32); i++) { place(cache, i); }
	}
	cache.entries.push({ key: key, pipeline: pipeline });
	place(cache, (cache.entries.length as int32) - 1);
}

@noinline function stopOnUnregisteredProgram(program: int32): never {
	stop(`program id ${program} was never registered`);
}

@noinline function stopOnRefusedShader(program: int32): never {
	stop(`sokol refused the shader of program ${program}; ` +
		"its pool is full or it did not compile");
}

// "" when the key's stencil, if it has one, has a depth attachment with stencil bits to test.
function stencilRefusal(key: PipelineKey): string {
	return stencilTargetRefusal(key.stencilOps != 0, key.targetLayout().depth);
}

@noinline function stopOnStencilTarget(refusal: string, key: PipelineKey): never {
	stop(`${refusal}; pipeline ${key.toString()}`);
}

@noinline function stopOnRefusedPipeline(key: PipelineKey): never {
	stop(`sokol refused pipeline ${key.toString()}; ` +
		"its pool is full or its description is invalid");
}

@noinline function stopOnClosed(call: string): never {
	stop(`${call} on a pipeline cache that was closed`);
}

@noinline function stopInsidePass(call: string): never {
	stop(`${call} with a pass already open; endPass ends it`);
}

function registered(program: int32): boolean {
	return program >= 0 && program < programCount();
}

function adoptContext(cache: PipelineCache): void {
	const generation: int32 = contextGeneration();
	if (cache.generation == generation) { return; }
	forgetPipelines(cache);
	cache.generation = generation;
}

export function shaderFor(cache: PipelineCache, program: int32): uint32 {
	if (cache.closed) { stopOnClosed("shaderFor"); }
	if (!registered(program)) { stopOnUnregisteredProgram(program); }
	adoptContext(cache);
	for (let i = cache.shaders.length as int32; i <= program; i++) {
		cache.shaders.push(0);
		cache.blockSlots.push(0);
	}
	if (cache.shaders[program] == 0) {
		const shader: uint32 = makeShader(program);
		if (shader == 0) { stopOnRefusedShader(program); }
		cache.shaders[program] = shader;
		cache.blockSlots[program] = uniformSlotMask(program);
	}
	return cache.shaders[program];
}

// Whether `program` declares a uniform block at `slot`; known once its shader has been made.
export function declaresBlock(this cache: PipelineCache, program: int32, slot: int32): boolean {
	if (cache.closed) { return false; }
	if (program < 0 || program >= (cache.blockSlots.length as int32)) { return false; }
	return (cache.blockSlots[program] & ((1 as uint32) << (slot as uint32))) != 0;
}

// PipelineBuilder.lookup + the driver's makePipeline on a miss.
export function pipelineFor(
	cache: PipelineCache,
	program: int32,
	layout: int32,
	indexed: boolean,
	state: RenderState,
	targets: TargetLayout,
	format: IndexType = IndexType.Uint16,
): uint32 {
	if (cache.closed) { stopOnClosed("pipelineFor"); }
	if (!registered(program)) { stopOnUnregisteredProgram(program); }
	adoptContext(cache);
	const concrete: TargetLayout = targets.resolved();
	const key: PipelineKey = pipelineKey(program, layout, indexed, state, concrete, format);
	const found: int32 = cache.indexOf(key);
	if (found >= 0 && cache.entries[found].pipeline != 0) { return cache.entries[found].pipeline; }
	return buildPipeline(cache, program, layout, state, concrete, key);
}

// The cache-miss path of pipelineFor, out of line so its pipeline description and refusal
// message are not copied into every caller.
@noinline function buildPipeline(
	cache: PipelineCache,
	program: int32,
	layout: int32,
	state: RenderState,
	concrete: TargetLayout,
	key: PipelineKey,
): uint32 {
	const refusal: string = stencilRefusal(key);
	if (refusal != "") { stopOnStencilTarget(refusal, key); }
	const description: PipelineDescriptor = {
		shader: shaderFor(cache, program),
		layout: layout,
		state: state,
		targets: concrete,
		indexType: key.indexType,
	};
	const pipeline: uint32 = makePipeline(description);
	if (pipeline == 0) { stopOnRefusedPipeline(key); }
	record(cache, key, pipeline);
	return pipeline;
}

// ---- prewarm ----
//
// The keys a run built are its record: `keysOf` reads them, `keysText` keeps them, `prewarm` makes
// the missing ones through `pipelineFor`. The recorded set is replayed per shader at compile time
// by the same makePipeline a miss uses (h3d/impl/DX12Driver.hx PSOConfigCache :22-145, :76-91, :3427).

const KEYS_MAGIC: string = "pipelines-1";
const KEY_FIELDS: Vec<string> = [
	"program", "layout", "indexType", "state", "targets", "stencilOps", "stencilMasks",
];
const INT32_MAX: int64 = 2147483647;
const UINT32_MAX: int64 = 4294967295;
const INDEX_TYPE_MAX: int64 = 2;

function fieldLimit(field: int32): int64 {
	if (field < 2) { return INT32_MAX; }
	return field == 2 ? INDEX_TYPE_MAX : UINT32_MAX;
}

// The keys the cache holds, in the order they were first built. A key stays after a context loss
// took its handle, so the list is what the run needed, not what is live.
export function keysOf(this cache: PipelineCache): PipelineKey[] {
	if (cache.closed) { stopOnClosed("keysOf"); }
	const keys: PipelineKey[] = [];
	for (const entry of cache.entries) { keys.push(entry.key); }
	return keys;
}

// `program=3 layout=1 indexType=2 state=… targets=… stencilOps=… stencilMasks=…`, every field a
// decimal number: the program and layout are door registry ids, so the text belongs to the build
// whose registrations made it.
export function keyText(key: PipelineKey): string {
	return `program=${key.program} layout=${key.layout} indexType=${key.indexType as int32} ` +
		`state=${key.state} targets=${key.targets} stencilOps=${key.stencilOps} ` +
		`stencilMasks=${key.stencilMasks}`;
}

// A decimal number of at most `limit`, -1 for anything else: empty, a sign, a prefix, a trailing
// letter or too large.
function readNumber(text: string, limit: int64): int64 {
	if (text.length == 0) { return -1; }
	let value: int64 = 0;
	for (let i = 0; i < text.length; i++) {
		const digit: int32 = (text.charCodeAt(i) as int32) - 48;
		if (digit < 0 || digit > 9) { return -1; }
		value = value * 10 + digit;
		if (value > limit) { return -1; }
	}
	return value;
}

export function parseKey(text: string): Result<PipelineKey, string> {
	const parts: string[] = text.split(" ");
	if (parts.length != KEY_FIELDS.length) {
		return Result.err(`pipeline key text "${text}" has ${parts.length} fields, a key has ` +
			`${KEY_FIELDS.length}`);
	}
	const values: int64[] = [];
	for (let i = 0; i < (KEY_FIELDS.length as int32); i++) {
		const prefix: string = KEY_FIELDS[i] + "=";
		if (!parts[i].startsWith(prefix)) {
			return Result.err(`pipeline key text "${text}": field ${i + 1} is "${parts[i]}", ` +
				`expected ${prefix}<number>`);
		}
		const digits: string = parts[i].slice(prefix.length, parts[i].length);
		const value: int64 = readNumber(digits, fieldLimit(i));
		if (value < 0) {
			return Result.err(`pipeline key text "${text}": ${KEY_FIELDS[i]} holds "${digits}", ` +
				`not a number from 0 to ${fieldLimit(i)}`);
		}
		values.push(value);
	}
	return Result.ok({
		program: values[0] as int32,
		layout: values[1] as int32,
		indexType: (values[2] as int32) as IndexType,
		state: values[3] as uint32,
		targets: values[4] as uint32,
		stencilOps: values[5] as uint32,
		stencilMasks: values[6] as uint32,
	});
}

export function keyFromText(text: string): PipelineKey {
	const parsed: Result<PipelineKey, string> = parseKey(text);
	if (!parsed.ok) { stop(parsed.error); }
	return parsed.value;
}

// A magic line, then one key per line; a file of it is what a run keeps for the next one.
export function keysText(keys: Readonly<Span<PipelineKey>>): string {
	let text: string = KEYS_MAGIC + "
";
	for (const key of keys) { text += keyText(key) + "
"; }
	return text;
}

export function parseKeys(text: string): Result<PipelineKey[], string> {
	const lines: string[] = text.split("
");
	if (lines[0] != KEYS_MAGIC) {
		return Result.err(`pipeline keys text starts with "${lines[0]}", expected "${KEYS_MAGIC}"`);
	}
	if (lines.length < 2 || lines[lines.length - 1] != "") {
		return Result.err("pipeline keys text does not end with a newline");
	}
	const keys: PipelineKey[] = [];
	for (let i = 1; i < (lines.length as int32) - 1; i++) {
		const parsed: Result<PipelineKey, string> = parseKey(lines[i]);
		if (!parsed.ok) { return Result.err(`line ${i + 1}: ${parsed.error}`); }
		keys.push(parsed.value);
	}
	return Result.ok(keys);
}

export function keysFromText(text: string): PipelineKey[] {
	const parsed: Result<PipelineKey[], string> = parseKeys(text);
	if (!parsed.ok) { stop(parsed.error); }
	return parsed.value;
}

// "" when `key` can be built now, else why not, naming the key.
export function prewarmRefusal(key: PipelineKey): string {
	if (!registered(key.program)) {
		return `prewarm of ${keyText(key)}: program ${key.program} was never registered`;
	}
	if (key.layout < 0 || key.layout >= doorLayoutCount()) {
		return `prewarm of ${keyText(key)}: layout ${key.layout} was never registered`;
	}
	if ((key.indexType as int32) < 0 || (key.indexType as int32) > INDEX_TYPE_MAX) {
		return `prewarm of ${keyText(key)}: index type ${key.indexType as int32} is not 0, 1 or 2`;
	}
	if (key.targetLayout().namesEnvironment()) {
		return `prewarm of ${keyText(key)}: its targets name the environment; ` +
			"key a prewarm with resolved targets";
	}
	const refusal: string = stencilRefusal(key);
	if (refusal != "") { return `prewarm of ${keyText(key)}: ${refusal}`; }
	return "";
}

// Makes each key the cache holds no live pipeline for, through `pipelineFor`, so a prewarmed
// pipeline is the one a miss would have made; the number made. Every key is checked first, so a
// refused set makes none. A new context drops the handles first (adoptContext), so the keys a
// cache kept across a loss are made again.
export function prewarm(cache: PipelineCache, keys: Readonly<Span<PipelineKey>>): int32 {
	if (cache.closed) { stopOnClosed("prewarm"); }
	for (const key of keys) {
		const refusal: string = prewarmRefusal(key);
		if (refusal != "") { stop(refusal); }
	}
	adoptContext(cache);
	let made: int32 = 0;
	for (const key of keys) {
		const found: int32 = cache.indexOf(key);
		if (found >= 0 && cache.entries[found].pipeline != 0) { continue; }
		pipelineFor(
			cache,
			key.program,
			key.layout,
			key.indexType != IndexType.None,
			key.renderState(),
			key.targetLayout(),
			key.indexType,
		);
		made++;
	}
	return made;
}

// After a context loss: the GPU objects are gone, so only the handles are dropped. Keys stay,
// and each pipeline is rebuilt on its next pipelineFor.
function forgetPipelines(cache: PipelineCache): void {
	for (let i = 0; i < (cache.entries.length as int32); i++) {
		cache.entries[i].pipeline = 0;
	}
	for (let i = 0; i < (cache.shaders.length as int32); i++) {
		cache.shaders[i] = 0;
	}
}

// Destroys every pipeline and shader, then forgets them.
export function releasePipelines(cache: PipelineCache): void {
	if (cache.closed) { stopOnClosed("releasePipelines"); }
	if (passState() != PassState.None) { stopInsidePass("releasePipelines"); }
	if (cache.generation == contextGeneration()) {
		for (const entry of cache.entries) {
			if (entry.pipeline != 0) { destroyPipeline(entry.pipeline); }
		}
		for (const shader of cache.shaders) {
			if (shader != 0) { destroyShader(shader); }
		}
	}
	forgetPipelines(cache);
}

export function closePipelines(cache: PipelineCache): void {
	if (cache.closed) { stopOnClosed("closePipelines"); }
	if (passState() != PassState.None) { stopInsidePass("closePipelines"); }
	releasePipelines(cache);
	cache.entries = [];
	cache.slots = [];
	cache.shaders = [];
	cache.blockSlots = [];
	cache.closed = true;
}

export function isClosed(this cache: PipelineCache): boolean {
	return cache.closed;
}
