// What a renderer draws for the program a material names. Heaps adds a pass's output shaders to
// the material's; fixed sokol-shdc programs cannot compose, so a preset swaps the whole program.

import { Program, samplesPremultiplied, cutsAlpha } from "./gpu3d";

export struct ProgramMap {
	named: BitSet<Program>;
	drawnLow: uint64;
	drawnHigh: uint64;
}

export enum ProgramError {
	NotDrawn,
}

const PROGRAM_BITS: int32 = 5;
const PROGRAM_MASK: uint64 = 31;
const PROGRAMS_PER_WORD: int32 = 12;

export function empty(this typeof ProgramMap): ProgramMap {
	return { named: 0 as BitSet<Program>, drawnLow: 0, drawnHigh: 0 };
}

function stopOnUnheldProgram(program: Program): void {
	console.log(`void3d: ProgramMap holds ${2 * PROGRAMS_PER_WORD} programs, not ` +
		`${program.toString()} at ${program as int32}`);
	unreachable;
}

function stopOnAlphaMismatch(named: Program, drawn: Program): void {
	console.log(`void3d: ProgramMap draws ${named.toString()} as ${drawn.toString()}; ` +
		"a premultiplied program is drawn only as a premultiplied one");
	unreachable;
}

function stopOnCutMismatch(named: Program, drawn: Program): void {
	console.log(`void3d: ProgramMap draws ${named.toString()} as ${drawn.toString()}; ` +
		"a cutout program is drawn only as a cutout one");
	unreachable;
}

function requireHeld(program: Program): void {
	if ((program as int32) >= 2 * PROGRAMS_PER_WORD) { stopOnUnheldProgram(program); }
}

function shiftOf(program: Program): uint64 {
	requireHeld(program);
	return (((program as int32) % PROGRAMS_PER_WORD) * PROGRAM_BITS) as uint64;
}

function inHighWord(program: Program): boolean {
	return (program as int32) >= PROGRAMS_PER_WORD;
}

export function core(this typeof ProgramMap): ProgramMap {
	return ProgramMap.empty()
		.drawing(Program.Lit, Program.Lit)
		.drawing(Program.Particle, Program.Particle)
		.drawing(Program.Billboard, Program.Billboard)
		.drawing(Program.LitTextured, Program.LitTextured)
		.drawing(Program.UnlitTextured, Program.UnlitTextured)
		.drawing(Program.LitTexturedPremultiplied, Program.LitTexturedPremultiplied)
		.drawing(Program.UnlitTexturedPremultiplied, Program.UnlitTexturedPremultiplied)
		.drawing(Program.LitCutout, Program.LitCutout)
		.drawing(Program.LitTexturedCutout, Program.LitTexturedCutout)
		.drawing(Program.UnlitTexturedCutout, Program.UnlitTexturedCutout);
}

export function drawing(this map: ProgramMap, named: Program, drawn: Program): ProgramMap {
	const shift: uint64 = shiftOf(named);
	const value: uint64 = (((drawn as int32) as uint64) & PROGRAM_MASK) << shift;
	requireHeld(drawn);
	if (samplesPremultiplied(named) != samplesPremultiplied(drawn)) {
		stopOnAlphaMismatch(named, drawn);
	}
	if (cutsAlpha(named) != cutsAlpha(drawn)) { stopOnCutMismatch(named, drawn); }
	if (inHighWord(named)) {
		return {
			named: map.named.incl(named),
			drawnLow: map.drawnLow,
			drawnHigh: (map.drawnHigh & ~(PROGRAM_MASK << shift)) | value,
		};
	}
	return {
		named: map.named.incl(named),
		drawnLow: (map.drawnLow & ~(PROGRAM_MASK << shift)) | value,
		drawnHigh: map.drawnHigh,
	};
}

export function draws(this map: ProgramMap, named: Program): boolean {
	return map.named.has(named);
}

export function drawnFor(this map: ProgramMap, named: Program): Result<Program, ProgramError> {
	if (!map.named.has(named)) {
		return Result.err(ProgramError.NotDrawn);
	}
	const word: uint64 = inHighWord(named) ? map.drawnHigh : map.drawnLow;
	return Result.ok((((word >> shiftOf(named)) & PROGRAM_MASK) as int32) as Program);
}
