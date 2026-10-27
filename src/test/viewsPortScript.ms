// A scripted run of the host views over a recording platform: the same op stream the C views.c
// ran in the differential, so its transcript digest can be pinned against what that C printed.

import { Views, ViewsPlatform } from "../host/views";

const KIND_CREATE: int32 = 0;
const KIND_RESIZE: int32 = 1;
const KIND_FRAME: int32 = 2;
const KIND_DESTROY: int32 = 3;
const KIND_READY: int32 = 4;
const KIND_SWAPCHAIN: int32 = 5;
const KIND_SAMPLES: int32 = 6;
const KIND_OUTSIDE: int32 = 7;
const KIND_FLAGS: int32 = 8;
const KIND_PUMP: int32 = 9;
const KIND_CURRENT: int32 = 10;
const KIND_KINDS: int32 = 11;
const OP_WORDS: int32 = 5;
const GARBAGE_IDS: int32[] = [-5, 0, 1, 2, 31, 32, 33, 1000, 97, 2147483647];
const SIZES: int32[] = [-1, 0, 1, 5, 64, 640];
const SCALES: float32[] = [1.0, 2.0, 0.5, -2.5, 0.0, 1.5, 1234567.0, -0.00001, 0.3333333, -123456789.0, -3.4028235e38, 1.1];
const SAMPLE_COUNTS: int32[] = [0, 1, 2, 3, 4, 8];
const FNV_OFFSET: uint64 = 2166136261;
const FNV_PRIME: uint64 = 16777619;

class Script {
	log: string[] = [];
	ready: boolean = true;
	acquire: boolean = true;
	serials: int32[] = [];
	issued: int32 = 0;
	mode: int32 = 0;
	nested: int32 = 0;
	ids: int32[] = [];
}

class ScriptPlatform extends ViewsPlatform {
	script: Script;

	constructor(script: Script) {
		super();
		this.script = script;
	}

	fail(message: string): never { throw new Error(message); }
	deviceEnsure(): void { this.script.log.push("P ensure"); }
	runInit(init: () => void): void {
		this.script.log.push("P runInit");
		init();
	}
	surfaceCreate(slot: int32, native: int64, width: int32, height: int32): boolean {
		if (native == 13) {
			this.script.log.push(`P create ${native} ${width} ${height} -> null`);
			return false;
		}
		this.script.issued++;
		this.script.serials[slot] = this.script.issued;
		this.script.log.push(`P create ${native} ${width} ${height} -> ${this.script.issued}`);
		return true;
	}
	surfaceResize(slot: int32, width: int32, height: int32): void {
		this.script.log.push(`P resize ${this.script.serials[slot]} ${width} ${height}`);
	}
	surfaceReady(slot: int32): boolean {
		this.script.log.push(`P ready ${this.script.serials[slot]} -> ${this.script.ready ? 1 : 0}`);
		return this.script.ready;
	}
	surfaceAcquire(slot: int32): boolean {
		this.script.log.push(`P acquire ${this.script.serials[slot]} -> ${this.script.acquire ? 1 : 0}`);
		return this.script.acquire;
	}
	surfacePresent(slot: int32): void { this.script.log.push(`P present ${this.script.serials[slot]}`); }
	surfaceDestroy(slot: int32): void { this.script.log.push(`P destroy ${this.script.serials[slot]}`); }
	surfaceNative(slot: int32): int64 {
		this.script.log.push(`P native ${this.script.serials[slot]}`);
		return (this.script.serials[slot] + 1000) as int64;
	}
}

// The op stream of one seed: OP_WORDS int32 per op, drawn from a Lehmer generator.
export function viewsScriptOps(seed: int32, count: int32): int32[] {
	let state: int64 = seed as int64;
	const ops: int32[] = [];
	for (let i: int32 = 0; i < count * OP_WORDS; i++) {
		state = (state * 16807) % 2147483647;
		ops.push((state % 1000003) as int32);
	}
	return ops;
}

// The op stream that mostly creates and destroys valid views, so slots run through their
// generations to retirement and the table fills.
export function viewsScriptChurnOps(seed: int32, count: int32): int32[] {
	const ops = viewsScriptOps(seed, count);
	for (let at: int32 = 0; at < ops.length; at += OP_WORDS) {
		const pick = ops[at] % 6;
		ops[at] = pick < 3 ? KIND_CREATE : (pick < 5 ? KIND_DESTROY : KIND_FRAME);
		ops[at + 2] = 3 + 6 * (ops[at + 2] % 100);
		ops[at + 3] = 3 + 6 * (ops[at + 3] % 100);
		ops[at + 4] = 12 * (ops[at + 4] % 100);
	}
	return ops;
}

function idOf(script: Script, word: int32): int32 {
	const pick = word >> 2;
	if (word % 4 == 0 || script.ids.length == 0) { return GARBAGE_IDS[pick % GARBAGE_IDS.length]; }
	return script.ids[pick % script.ids.length];
}

function attempt(script: Script, label: string, body: () => string): void {
	try {
		script.log.push(`${label} -> ${body()}`);
	} catch (error) {
		script.log.push(`${label} FAIL ${(error as Error).message}`);
	}
}

function size(word: int32): int32 { return SIZES[word % SIZES.length]; }

function frameBody(script: Script, views: Views): void {
	const target = views.currentView;
	script.log.push(`frame body ${script.mode}`);
	if (script.mode == 2) {
		attempt(script, "nested frame", (): string => `${views.frame(target)}`);
	} else if (script.mode == 3) {
		attempt(script, "nested resize", (): string => { views.resize(target, 2, 2, 1.0); return "ok"; });
	} else if (script.mode == 4) {
		attempt(script, "nested destroy", (): string => { views.destroy(target); return "ok"; });
	} else if (script.mode == 5) {
		attempt(script, "fbWidth", (): string => `${views.fbWidth()}`);
		attempt(script, "fbHeight", (): string => `${views.fbHeight()}`);
		attempt(script, "dpiScale", (): string => `${Math.round((views.dpiScale() as float64) * 1000) as int64}`);
		attempt(script, "surface", (): string => `${script.serials[views.currentSurfaceSlot()]}`);
	} else if (script.mode == 7) {
		attempt(script, "nested create", (): string => `${views.create(3, 8, 8, 1.0)}`);
	}
	if (script.mode == 1) { return; }
	attempt(script, "commit", (): string => { views.present(); return "ok"; });
	if (script.mode == 6) {
		attempt(script, "commit again", (): string => { views.present(); return "ok"; });
	}
}

function step(script: Script, views: Views, ops: int32[], at: int32): void {
	const kind = ops[at] % KIND_KINDS;
	const a = ops[at + 1];
	const b = ops[at + 2];
	const c = ops[at + 3];
	const d = ops[at + 4];
	if (kind == KIND_CREATE) {
		attempt(script, `create ${a % 20} ${size(b)} ${size(c)} ${d % SCALES.length}`, (): string => {
			const view = views.create((a % 20) as int64, size(b), size(c), SCALES[d % SCALES.length]);
			script.ids.push(view);
			return `${view}`;
		});
	} else if (kind == KIND_RESIZE) {
		attempt(script, `resize ${idOf(script, a)} ${size(b)} ${size(c)} ${d % SCALES.length}`, (): string => {
			views.resize(idOf(script, a), size(b), size(c), SCALES[d % SCALES.length]);
			return "ok";
		});
	} else if (kind == KIND_FRAME) {
		script.mode = b % 8;
		attempt(script, `frame ${idOf(script, a)} mode ${script.mode}`, (): string => `${views.frame(idOf(script, a))}`);
	} else if (kind == KIND_DESTROY) {
		attempt(script, `destroy ${idOf(script, a)}`, (): string => { views.destroy(idOf(script, a)); return "ok"; });
	} else if (kind == KIND_READY) {
		attempt(script, `ready ${idOf(script, a)}`, (): string => `${views.ready(idOf(script, a))}`);
	} else if (kind == KIND_SWAPCHAIN) {
		attempt(script, `swapChain ${idOf(script, a)}`, (): string => `${views.swapChain(idOf(script, a))}`);
	} else if (kind == KIND_SAMPLES) {
		attempt(script, `samples ${SAMPLE_COUNTS[a % SAMPLE_COUNTS.length]}`, (): string => {
			views.setSampleCount(SAMPLE_COUNTS[a % SAMPLE_COUNTS.length]);
			return `${views.sampleCount()}`;
		});
	} else if (kind == KIND_OUTSIDE) {
		const which = a % 5;
		attempt(script, `outside ${which}`, (): string => {
			if (which == 0) { return `${views.fbWidth()}`; }
			if (which == 1) { return `${views.fbHeight()}`; }
			if (which == 2) { return `${Math.round((views.dpiScale() as float64) * 1000) as int64}`; }
			if (which == 3) { return `${views.currentSurfaceSlot()}`; }
			views.present();
			return "ok";
		});
	} else if (kind == KIND_FLAGS) {
		script.ready = a % 4 != 0;
		script.acquire = b % 4 != 0;
		script.log.push(`flags ${script.ready ? 1 : 0} ${script.acquire ? 1 : 0}`);
	} else if (kind == KIND_PUMP) {
		attempt(script, "pump", (): string => { views.pumpMessages(); return "ok"; });
	} else {
		script.log.push(`current ${views.currentView}`);
	}
}

// The transcript of one run: every op and the platform calls it made, one line each.
export function viewsScriptRun(ops: int32[], lastGeneration: int32): string[] {
	const script = new Script();
	for (let i: int32 = 0; i < 16; i++) { script.serials.push(0); }
	const views = new Views(new ScriptPlatform(script), lastGeneration);
	views.register(
		(): void => { script.log.push("init"); },
		(): void => { frameBody(script, views); },
	);
	views.setMessagePump((): void => { script.log.push("pump"); });
	for (let at: int32 = 0; at < ops.length; at += OP_WORDS) { step(script, views, ops, at); }
	return script.log;
}

export function viewsScriptDigest(lines: string[]): string {
	let hash: uint64 = FNV_OFFSET;
	for (const line of lines) {
		const text = line + "\n";
		for (let i: int32 = 0; i < text.byteLength(); i++) {
			hash = ((hash ^ (text.byteAt(i) as uint64)) * FNV_PRIME) % 4294967296;
		}
	}
	return `${hash}`;
}
