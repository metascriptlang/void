import {
	DoorReading, FrameClock, COUNTER_SLOTS, MARK_COUNT, VOID2D_COUNTER_SLOTS,
} from "../void2d/frameClock";

const FNV_OFFSET: uint32 = 2166136261;
const FNV_PRIME: uint32 = 16777619;
const LOW_WORD: int64 = 4294967295;
const OBSERVED_PER_STEP: int32 = 25;

// What a script steps and observes: frameClock.ms under the scripted time and door reading, or
// the C frameClock.c behind the same calls.
export class ClockModel {
	setNow(now: int64): void { throw new Error("ClockModel.setNow is not provided"); }
	setDoor(
		valid: boolean,
		draws: int64,
		pipelines: int64,
		passes: int64,
		bufferBytes: int64,
		imageBytes: int64,
	): void { throw new Error("ClockModel.setDoor is not provided"); }
	setVoid2dCounter(slot: int32, value: int32): void {
		throw new Error("ClockModel.setVoid2dCounter is not provided");
	}
	begin(): void { throw new Error("ClockModel.begin is not provided"); }
	input(): void { throw new Error("ClockModel.input is not provided"); }
	commit(serial: int32): void { throw new Error("ClockModel.commit is not provided"); }
	present(begin: int32): void { throw new Error("ClockModel.present is not provided"); }
	consume(): void { throw new Error("ClockModel.consume is not provided"); }
	takePending(): int32 { throw new Error("ClockModel.takePending is not provided"); }
	takeDropped(): int32 { throw new Error("ClockModel.takeDropped is not provided"); }
	state(): int32 { throw new Error("ClockModel.state is not provided"); }
	serial(): int32 { throw new Error("ClockModel.serial is not provided"); }
	lost(): int32 { throw new Error("ClockModel.lost is not provided"); }
	firstInput(): int64 { throw new Error("ClockModel.firstInput is not provided"); }
	mark(which: int32): int64 { throw new Error("ClockModel.mark is not provided"); }
	counter(which: int32): int32 { throw new Error("ClockModel.counter is not provided"); }
}

export class PortModel extends ClockModel {
	clock: FrameClock = new FrameClock();
	now: int64 = 0;
	counters: int32[9] = [0, 0, 0, 0, 0, 0, 0, 0, 0];
	door: DoorReading = {
		valid: false,
		draws: 0,
		pipelines: 0,
		passes: 0,
		bufferBytes: 0,
		imageBytes: 0,
	};

	setNow(now: int64): void { this.now = now; }
	setDoor(
		valid: boolean,
		draws: int64,
		pipelines: int64,
		passes: int64,
		bufferBytes: int64,
		imageBytes: int64,
	): void {
		this.door = { valid, draws, pipelines, passes, bufferBytes, imageBytes };
	}
	setVoid2dCounter(slot: int32, value: int32): void { this.counters[slot] = value; }
	begin(): void { this.clock.begin(this.now); }
	input(): void { this.clock.input(this.now); }
	commit(serial: int32): void {
		this.clock.commit(this.now, serial, this.counters[0..9], this.door);
	}
	present(begin: int32): void { this.clock.present(begin != 0, this.now); }
	consume(): void { this.clock.consume(); }
	takePending(): int32 { return this.clock.takePendingInputs(); }
	takeDropped(): int32 { return this.clock.takeDroppedInputs(); }
	state(): int32 { return this.clock.state; }
	serial(): int32 { return this.clock.serial; }
	lost(): int32 { return this.clock.lost; }
	firstInput(): int64 { return this.clock.firstInput; }
	mark(which: int32): int64 { return this.clock.mark(which); }
	counter(which: int32): int32 { return this.clock.counter(which); }
}

class Source {
	state: uint32;
	constructor(seed: uint32) { this.state = seed; }
}

function next(s: Source): uint32 {
	s.state ^= s.state << 13;
	s.state ^= s.state >> 17;
	s.state ^= s.state << 5;
	return s.state;
}

const WORDS: int32[] = [0, 1, -1, 7, 2147483647, -2147483648, 65536, -65537];
const WIDE: int64[] = [
	0, 1, 7, 2147483647, 2147483648, 4294967295, 4294967301, 8589935715, -1, -2147483649,
	123456789012, 281474976710656,
];

function pickWord(s: Source): int32 {
	if ((next(s) & 1) == 0) { return WORDS[(next(s) % (WORDS.length as uint32)) as int32]; }
	return (next(s) % 100000) as int32;
}

function pickWide(s: Source): int64 {
	if ((next(s) & 1) == 0) { return WIDE[(next(s) % (WIDE.length as uint32)) as int32]; }
	return (next(s) % 100000) as int64;
}

function advance(s: Source, now: int64): int64 {
	const kind: uint32 = next(s) % 16;
	if (kind == 0) { return ((next(s) as int64) << 12) ^ (next(s) as int64); }
	if (kind == 1) { return now - ((next(s) % 1000) as int64); }
	return now + ((next(s) % 1000000) as int64);
}

function observe(model: ClockModel, opcode: int32, returned: int32, out: int64[]): void {
	out.push(opcode as int64);
	out.push(returned as int64);
	out.push(model.state() as int64);
	out.push(model.serial() as int64);
	out.push(model.lost() as int64);
	out.push(model.firstInput());
	for (let i: int32 = 0; i < MARK_COUNT; i++) { out.push(model.mark(i)); }
	for (let i: int32 = 0; i < COUNTER_SLOTS; i++) { out.push(model.counter(i) as int64); }
}

// `steps` random calls on a fresh model, after each of which every getter is read. Each step
// adds OBSERVED_PER_STEP values.
export function runScript(model: ClockModel, seed: uint32, steps: int32): int64[] {
	const s = new Source(seed);
	let out: int64[] = [];
	let now: int64 = 0;
	for (let step: int32 = 0; step < steps; step++) {
		now = advance(s, now);
		model.setNow(now);
		const pick: uint32 = next(s) % 100;
		let returned: int32 = 0;
		let opcode: int32 = 0;
		if (pick < 12) {
			opcode = 1;
			model.begin();
		} else if (pick < 24) {
			opcode = 2;
			model.input();
		} else if (pick < 40) {
			opcode = 3;
			for (let i: int32 = 0; i < VOID2D_COUNTER_SLOTS; i++) {
				model.setVoid2dCounter(i, pickWord(s));
			}
			model.commit(pickWord(s));
		} else if (pick < 62) {
			opcode = 4;
			model.present((next(s) & 1) as int32);
		} else if (pick < 72) {
			opcode = 5;
			model.consume();
		} else if (pick < 80) {
			opcode = 6;
			returned = model.takePending();
		} else if (pick < 88) {
			opcode = 7;
			returned = model.takeDropped();
		} else {
			opcode = 8;
			model.setDoor(
				(next(s) & 3) != 0,
				pickWide(s),
				pickWide(s),
				pickWide(s),
				pickWide(s),
				pickWide(s),
			);
		}
		observe(model, opcode, returned, out);
	}
	return out;
}

// FNV-1a over the observation, a 32-bit word at a time: the low word of each value, then the high.
export function scriptDigest(observed: int64[]): uint32 {
	let h: uint32 = FNV_OFFSET;
	for (let i: int32 = 0; i < (observed.length as int32); i++) {
		const value: int64 = observed[i];
		h = (h ^ ((value & LOW_WORD) as uint32)) * FNV_PRIME;
		h = (h ^ (((value >> 32) & LOW_WORD) as uint32)) * FNV_PRIME;
	}
	return h;
}

export function observedPerStep(): int32 { return OBSERVED_PER_STEP; }
