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

export function clusterEdges(
	levels: Readonly<Span<int32>>,
	starts: Readonly<Span<boolean>>,
	xs: Readonly<Span<float32>>,
	advances: Readonly<Span<float32>>,
	paragraph: int32,
	ref edges: Vec<float32>,
): void {
	const count: int32 = levels.length as int32;
	let first: Vec<int32> = new Array(0);
	for (let i = 0; i < count; i++) {
		if (i == 0 || starts[i]) { first.push(i); }
	}
	const clusters: int32 = first.length as int32;
	let left: Vec<float32> = new Array(0);
	let right: Vec<float32> = new Array(0);
	let lineLeft: float32 = 0.0;
	let lineRight: float32 = 0.0;
	for (let c = 0; c < clusters; c++) {
		const stop: int32 = c + 1 < clusters ? first[c + 1] : count;
		let low: float32 = xs[first[c]];
		let high: float32 = xs[first[c]] + advances[first[c]];
		for (let k = first[c]; k < stop; k++) {
			if (xs[k] < low) { low = xs[k]; }
			if (xs[k] + advances[k] > high) { high = xs[k] + advances[k]; }
		}
		left.push(low);
		right.push(high);
		if (c == 0 || low < lineLeft) { lineLeft = low; }
		if (c == 0 || high > lineRight) { lineRight = high; }
	}
	const embedding: int32 = paragraph & 1;
	for (let j = 0; j <= clusters; j++) {
		if (clusters == 0) {
			edges.push(0.0);
			continue;
		}
		const next: int32 = j < clusters ? levels[first[j]] & 1 : embedding;
		const previous: int32 = j > 0 ? levels[first[j - 1]] & 1 : embedding;
		const leading: float32 = j < clusters
			? (next == 0 ? xs[first[j]] : right[j])
			: (embedding == 0 ? lineRight : lineLeft);
		const trailing: float32 = j > 0
			? (previous == 0 ? right[j - 1] : left[j - 1])
			: (embedding == 0 ? lineLeft : lineRight);
		if (j == clusters) {
			edges.push(previous == embedding ? trailing : leading);
		} else if (j == 0) {
			edges.push(next == embedding ? leading : trailing);
		} else if (previous == next) {
			edges.push(leading);
		} else {
			edges.push(previous == embedding ? trailing : leading);
		}
	}
}

// The pairs (low, high) of the clusters whose first index is in [from, to), merged where they
// touch within `gap`. `extraLow < extraHigh` adds one more extent that is always selected.
export function selectedSpans(
	starts: Readonly<Span<boolean>>,
	indices: Readonly<Span<int32>>,
	xs: Readonly<Span<float32>>,
	advances: Readonly<Span<float32>>,
	from: int32,
	to: int32,
	gap: float32,
	extraLow: float32,
	extraHigh: float32,
	ref out: Vec<float32>,
): void {
	const count: int32 = xs.length as int32;
	let lows: Vec<float32> = new Array(0);
	let highs: Vec<float32> = new Array(0);
	let k: int32 = 0;
	while (k < count) {
		let stop: int32 = k + 1;
		while (stop < count && !starts[stop]) { stop = stop + 1; }
		if (indices[k] >= from && indices[k] < to) {
			let low: float32 = xs[k];
			let high: float32 = xs[k] + advances[k];
			for (let j = k; j < stop; j++) {
				if (xs[j] < low) { low = xs[j]; }
				if (xs[j] + advances[j] > high) { high = xs[j] + advances[j]; }
			}
			lows.push(low);
			highs.push(high);
		}
		k = stop;
	}
	if (extraHigh > extraLow) {
		lows.push(extraLow);
		highs.push(extraHigh);
	}
	const total: int32 = lows.length as int32;
	for (let a = 1; a < total; a++) {
		const low: float32 = lows[a];
		const high: float32 = highs[a];
		let b: int32 = a - 1;
		while (b >= 0 && lows[b] > low) {
			lows[b + 1] = lows[b];
			highs[b + 1] = highs[b];
			b = b - 1;
		}
		lows[b + 1] = low;
		highs[b + 1] = high;
	}
	let a: int32 = 0;
	while (a < total) {
		let right: float32 = highs[a];
		let b: int32 = a + 1;
		while (b < total && lows[b] <= right + gap) {
			if (highs[b] > right) { right = highs[b]; }
			b = b + 1;
		}
		out.push(lows[a]);
		out.push(right);
		a = b;
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
