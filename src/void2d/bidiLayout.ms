import {
	BidiClass,
	bidiClassOf,
	bracketCode,
	mirrorOf,
	removedByX9,
	resolveLevels,
} from "./bidi";
import {
	NO_RESET,
	SEPARATOR_RESET,
	TextDirection,
	WHITESPACE_RESET,
} from "./textDirection";

const NEWLINE: int32 = 10;

function resetOf(c: BidiClass): int32 {
	if (c == BidiClass.B || c == BidiClass.S) { return SEPARATOR_RESET; }
	if (c == BidiClass.WS || c == BidiClass.LRI || c == BidiClass.RLI || c == BidiClass.FSI ||
		c == BidiClass.PDI || removedByX9(c)) {
		return WHITESPACE_RESET;
	}
	return NO_RESET;
}

export function resolveText(
	values: Readonly<Span<int32>>,
	direction: TextDirection,
	ref levels: Vec<int32>,
	ref resets: Vec<int32>,
	ref paragraphs: Vec<int32>,
): void {
	const count: int32 = values.length as int32;
	let start: int32 = 0;
	while (true) {
		let end: int32 = start;
		while (end < count && values[end] != NEWLINE) { end = end + 1; }
		const stop: int32 = end < count ? end + 1 : end;
		let classes: Vec<BidiClass> = new Array(0);
		let brackets: Vec<int32> = new Array(0);
		for (let i = start; i < stop; i++) {
			classes.push(bidiClassOf(values[i]));
			brackets.push(bracketCode(values[i]));
		}
		let resolved: Vec<int32> = new Array(0);
		paragraphs.push(resolveLevels(classes, brackets, direction, resolved));
		for (let i = 0; i < (classes.length as int32); i++) {
			levels.push(resolved[i]);
			resets.push(resetOf(classes[i]));
		}
		if (end >= count) { break; }
		start = end + 1;
	}
}

export function mirroredValue(codepoint: int32): int32 {
	const mirror: int32 = mirrorOf(codepoint);
	return mirror == 0 ? codepoint : mirror;
}

// A run that reaches past `inkRight` is cut there, so trailing whitespace at the paragraph level
// hangs outside the ink on the paragraph-end side (UAX #9 L1).
export function visualPositions(
	levels: Readonly<Span<int32>>,
	xs: Readonly<Span<float32>>,
	advances: Readonly<Span<float32>>,
	inkRight: float32,
	ref out: Vec<float32>,
): void {
	const count: int32 = levels.length as int32;
	for (let i = 0; i < count; i++) { out.push(xs[i]); }
	let highest: int32 = 0;
	let lowestOdd: int32 = 1000;
	for (let i = 0; i < count; i++) {
		if (levels[i] > highest) { highest = levels[i]; }
		if ((levels[i] & 1) == 1 && levels[i] < lowestOdd) { lowestOdd = levels[i]; }
	}
	for (let level = highest; level >= lowestOdd; level--) {
		let i: int32 = 0;
		while (i < count) {
			if (levels[i] < level) {
				i = i + 1;
				continue;
			}
			let end: int32 = i;
			while (end < count && levels[end] >= level) { end = end + 1; }
			const left: float32 = xs[i];
			const logicalRight: float32 = xs[end - 1] + advances[end - 1];
			const clipped: boolean = end == count && logicalRight > inkRight;
			const right: float32 = clipped ? inkRight : logicalRight;
			for (let k = i; k < end; k++) {
				out[k] = left + right - (out[k] + advances[k]);
			}
			i = end;
		}
	}
}
