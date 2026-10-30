// The frame profiler's clock marks, counters and input timing, ported from frameClock.c. Each
// step of FrameClock takes the time it happens at; the functions after it read the platform
// clock. The C targets reach them through frameClockExports.cms and frameClock.h.

import { exit } from "std/process";
import { clockNow } from "../platform/clockNow";

export const MARK_BEGIN: int32 = 0;
export const MARK_COMMIT: int32 = 1;
export const MARK_PRESENT_START: int32 = 2;
export const MARK_PRESENT_END: int32 = 3;
export const MARK_COUNT: int32 = 4;

export const COUNTER_DRAWS: int32 = 0;
export const COUNTER_UI_INSTANCES: int32 = 1;
export const COUNTER_SPRITE_INSTANCES: int32 = 2;
export const COUNTER_UPLOAD_BYTES: int32 = 3;
export const COUNTER_UPLOADS: int32 = 4;
export const COUNTER_COVERED_PIXELS: int32 = 5;
export const COUNTER_TARGET_PIXELS: int32 = 6;
export const COUNTER_OPAQUE_PIXELS: int32 = 7;
export const COUNTER_FRAME_PIXELS: int32 = 8;
export const COUNTER_SOKOL_DRAWS: int32 = 9;
export const COUNTER_SOKOL_PIPELINES: int32 = 10;
export const COUNTER_SOKOL_PASSES: int32 = 11;
export const COUNTER_SOKOL_BUFFER_BYTES: int32 = 12;
export const COUNTER_SOKOL_IMAGE_BYTES: int32 = 13;
export const COUNTER_SOKOL_MEASURED: int32 = 14;
export const VOID2D_COUNTER_SLOTS: int32 = 9;
export const COUNTER_SLOTS: int32 = 15;

export const FRAME_IDLE: int32 = 0;
export const FRAME_OPEN: int32 = 1;
export const FRAME_COMMITTED: int32 = 2;
export const FRAME_PRESENTED: int32 = 3;

const LOW_WORD: int64 = 4294967295;
const WORD_RANGE: int64 = 4294967296;
const WORD_SIGN: int64 = 2147483648;

// What the door reports at commit: its sokol_gfx counts of the previous frame.
export struct DoorReading {
	valid: boolean;
	draws: int64;
	pipelines: int64;
	passes: int64;
	bufferBytes: int64;
	imageBytes: int64;
}

// The C store of an int64 into an int32 slot keeps the low 32 bits.
function lowWord(value: int64): int32 {
	const low: int64 = value & LOW_WORD;
	return (low >= WORD_SIGN ? low - WORD_RANGE : low) as int32;
}

function noSuch(what: string, which: int32): never {
	console.error(`void2d profiler: no ${what} number ${which}`);
	exit(1);
}

export class FrameClock {
	state: int32 = FRAME_IDLE;
	serial: int32 = 0;
	lost: int32 = 0;
	firstInput: int64 = 0;
	presentStarted: boolean = false;
	inputsPending: int32 = 0;
	inputsDropped: int32 = 0;
	marks: int64[4] = [0, 0, 0, 0];
	counters: int32[15] = [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

	mark(which: int32): int64 {
		if (which < 0 || which >= MARK_COUNT) { noSuch("frame mark", which); }
		return this.marks[which];
	}

	counter(which: int32): int32 {
		if (which < 0 || which >= COUNTER_SLOTS) { noSuch("frame counter", which); }
		return this.counters[which];
	}

	consume(): void { this.state = FRAME_IDLE; }

	input(now: int64): void {
		if (this.state == FRAME_OPEN) {
			this.inputsDropped++;
			return;
		}
		if (this.inputsPending == 0) { this.firstInput = now; }
		this.inputsPending++;
	}

	takePendingInputs(): int32 {
		const count: int32 = this.inputsPending;
		this.inputsPending = 0;
		return count;
	}

	takeDroppedInputs(): int32 {
		const count: int32 = this.inputsDropped;
		this.inputsDropped = 0;
		return count;
	}

	begin(now: int64): void {
		if (this.state != FRAME_IDLE) { this.lost++; }
		this.state = FRAME_OPEN;
		this.presentStarted = false;
		this.marks[MARK_BEGIN] = now;
	}

	commit(
		now: int64,
		serial: int32,
		void2dCounters: Readonly<Span<int32>>,
		door: DoorReading,
	): void {
		if (this.state != FRAME_OPEN) { return; }
		this.marks[MARK_COMMIT] = now;
		this.serial = serial;
		for (let i: int32 = 0; i < VOID2D_COUNTER_SLOTS; i++) { this.counters[i] = void2dCounters[i]; }
		this.counters[COUNTER_SOKOL_MEASURED] = door.valid ? 1 : 0;
		if (door.valid) {
			this.counters[COUNTER_SOKOL_DRAWS] = lowWord(door.draws);
			this.counters[COUNTER_SOKOL_PIPELINES] = lowWord(door.pipelines);
			this.counters[COUNTER_SOKOL_PASSES] = lowWord(door.passes);
			this.counters[COUNTER_SOKOL_BUFFER_BYTES] = lowWord(door.bufferBytes);
			this.counters[COUNTER_SOKOL_IMAGE_BYTES] = lowWord(door.imageBytes);
		} else {
			for (let i: int32 = COUNTER_SOKOL_DRAWS; i < COUNTER_SOKOL_MEASURED; i++) {
				this.counters[i] = 0;
			}
		}
		this.state = FRAME_COMMITTED;
	}

	present(begin: boolean, now: int64): void {
		if (this.state != FRAME_COMMITTED) { return; }
		if (begin) {
			this.marks[MARK_PRESENT_START] = now;
			this.presentStarted = true;
			return;
		}
		if (!this.presentStarted) { return; }
		this.marks[MARK_PRESENT_END] = now;
		this.state = FRAME_PRESENTED;
	}
}

export const frameClock: FrameClock = new FrameClock();

export function profileNow(): int64 { return clockNow(); }

export function profileInput(): void { frameClock.input(clockNow()); }

export function profileBegin(): void { frameClock.begin(clockNow()); }

export function profilePresent(begin: int32): void {
	frameClock.present(begin != 0, clockNow());
}
