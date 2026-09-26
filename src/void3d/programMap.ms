// Which program a renderer draws for the one a material names. Heaps composes a pass's output
// shaders into whatever the material brings (h3d.scene.Renderer and its passes); with fixed
// sokol-shdc programs a renderer draws a whole program of its own in the material's place
// instead. The core draws its programs as themselves; the pixel-art preset draws its own.

import { Program } from "./gpu3d";

export struct ProgramMap {
	named: BitSet<Program>;
	drawn: uint64;
}

export enum ProgramError {
	NotDrawn,
}

const PROGRAM_BITS: uint64 = 4;
const PROGRAM_MASK: uint64 = 15;

export function empty(this typeof ProgramMap): ProgramMap {
	return { named: 0 as BitSet<Program>, drawn: 0 };
}

// The core's own: Lit and Particle drawn as themselves.
export function core(this typeof ProgramMap): ProgramMap {
	return ProgramMap.empty()
		.drawing(Program.Lit, Program.Lit)
		.drawing(Program.Particle, Program.Particle);
}

export function drawing(this map: ProgramMap, named: Program, drawn: Program): ProgramMap {
	const shift: uint64 = ((named as int32) as uint64) * PROGRAM_BITS;
	const cleared: uint64 = map.drawn & ~(PROGRAM_MASK << shift);
	return {
		named: map.named.incl(named),
		drawn: cleared | (((drawn as int32) as uint64) << shift),
	};
}

export function draws(this map: ProgramMap, named: Program): boolean {
	return map.named.has(named);
}

export function drawnFor(this map: ProgramMap, named: Program): Result<Program, ProgramError> {
	if (!map.named.has(named)) {
		return Result.err(ProgramError.NotDrawn);
	}
	const shift: uint64 = ((named as int32) as uint64) * PROGRAM_BITS;
	return Result.ok((((map.drawn >> shift) & PROGRAM_MASK) as int32) as Program);
}
