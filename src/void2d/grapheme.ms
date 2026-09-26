import { void2dGraphemeClass } from "./grapheme.h";

export enum ClusterBreak {
	Other,
	CR,
	LF,
	Control,
	Extend,
	ZWJ,
	RegionalIndicator,
	Prepend,
	SpacingMark,
	L,
	V,
	T,
	LV,
	LVT,
}

export enum ConjunctBreak {
	None,
	Linker,
	Consonant,
	Extend,
}

export struct GraphemeProperty {
	cluster: ClusterBreak;
	pictographic: boolean;
	conjunct: ConjunctBreak;
}

export struct GraphemeCursor {
	started: boolean;
	previous: ClusterBreak;
	regionalRun: int32;
	pictographicRun: boolean;
	pictographicJoiner: boolean;
	linkerRun: boolean;
}

export function graphemeProperty(codepoint: int32): GraphemeProperty {
	const packed: int32 = void2dGraphemeClass(codepoint);
	return {
		cluster: (packed & 15) as ClusterBreak,
		pictographic: (packed & 16) != 0,
		conjunct: ((packed >> 5) & 3) as ConjunctBreak,
	};
}

export function startGraphemes(): GraphemeCursor {
	return {
		started: false,
		previous: ClusterBreak.Other,
		regionalRun: 0,
		pictographicRun: false,
		pictographicJoiner: false,
		linkerRun: false,
	};
}

function isBreakControl(c: ClusterBreak): boolean {
	return c == ClusterBreak.Control || c == ClusterBreak.CR || c == ClusterBreak.LF;
}

function boundaryBefore(cursor: GraphemeCursor, next: GraphemeProperty): boolean {
	const before: ClusterBreak = cursor.previous;
	const after: ClusterBreak = next.cluster;
	if (before == ClusterBreak.CR && after == ClusterBreak.LF) { return false; }
	if (isBreakControl(before) || isBreakControl(after)) { return true; }
	if (before == ClusterBreak.L) {
		const hangul: boolean = after == ClusterBreak.L || after == ClusterBreak.V ||
			after == ClusterBreak.LV || after == ClusterBreak.LVT;
		if (hangul) { return false; }
	}
	const vowelOrTrail: boolean = after == ClusterBreak.V || after == ClusterBreak.T;
	if ((before == ClusterBreak.LV || before == ClusterBreak.V) && vowelOrTrail) { return false; }
	if ((before == ClusterBreak.LVT || before == ClusterBreak.T) && after == ClusterBreak.T) {
		return false;
	}
	if (after == ClusterBreak.Extend || after == ClusterBreak.ZWJ) { return false; }
	if (after == ClusterBreak.SpacingMark || before == ClusterBreak.Prepend) { return false; }
	if (cursor.linkerRun && next.conjunct == ConjunctBreak.Consonant) { return false; }
	if (cursor.pictographicJoiner && next.pictographic) { return false; }
	const regional: boolean = before == ClusterBreak.RegionalIndicator &&
		after == ClusterBreak.RegionalIndicator;
	if (regional && cursor.regionalRun % 2 == 1) { return false; }
	return true;
}

// Whether a grapheme boundary falls before `codepoint`, moving the cursor past it (UAX #29).
export function breaksBefore(ref cursor: GraphemeCursor, codepoint: int32): boolean {
	const next: GraphemeProperty = graphemeProperty(codepoint);
	const boundary: boolean = !cursor.started || boundaryBefore(cursor, next);
	const regional: boolean = next.cluster == ClusterBreak.RegionalIndicator;
	const extendsPictograph: boolean = cursor.pictographicRun && next.cluster == ClusterBreak.Extend;
	cursor.pictographicJoiner = cursor.pictographicRun && next.cluster == ClusterBreak.ZWJ;
	cursor.pictographicRun = next.pictographic || extendsPictograph;
	cursor.regionalRun = regional ? cursor.regionalRun + 1 : 0;
	cursor.linkerRun = next.conjunct == ConjunctBreak.Linker ||
		(cursor.linkerRun && next.conjunct == ConjunctBreak.Extend);
	cursor.previous = next.cluster;
	cursor.started = true;
	return boundary;
}
