import { void2dBidiClass, void2dBidiBracket, void2dBidiMirror } from "./bidiClass.h";
import { TextDirection } from "./textDirection";

export enum BidiClass {
	L,
	R,
	AL,
	EN,
	ES,
	ET,
	AN,
	CS,
	NSM,
	BN,
	B,
	S,
	WS,
	ON,
	LRE,
	LRO,
	RLE,
	RLO,
	PDF,
	LRI,
	RLI,
	FSI,
	PDI,
}

export const MAX_DEPTH: int32 = 125;
export const MAX_BRACKET_STACK: int32 = 63;

const NO_MATCH: int32 = -1;
const NEUTRAL: int32 = 0;
const OVERRIDE_L: int32 = 1;
const OVERRIDE_R: int32 = 2;

export function bidiClassOf(codepoint: int32): BidiClass {
	return void2dBidiClass(codepoint) as BidiClass;
}

export function bracketCode(codepoint: int32): int32 {
	return void2dBidiBracket(codepoint);
}

export function mirrorOf(codepoint: int32): int32 {
	return void2dBidiMirror(codepoint);
}

export function removedByX9(c: BidiClass): boolean {
	return c == BidiClass.BN || c == BidiClass.LRE || c == BidiClass.RLE ||
		c == BidiClass.LRO || c == BidiClass.RLO || c == BidiClass.PDF;
}

function isolateInitiator(c: BidiClass): boolean {
	return c == BidiClass.LRI || c == BidiClass.RLI || c == BidiClass.FSI;
}

function neutralOrIsolate(c: BidiClass): boolean {
	return c == BidiClass.B || c == BidiClass.S || c == BidiClass.WS || c == BidiClass.ON ||
		c == BidiClass.FSI || c == BidiClass.LRI || c == BidiClass.RLI || c == BidiClass.PDI;
}

function strongDirection(c: BidiClass): BidiClass {
	return c == BidiClass.L ? BidiClass.L : BidiClass.R;
}

function directionOfLevel(level: int32): BidiClass {
	return (level & 1) == 1 ? BidiClass.R : BidiClass.L;
}

function matchIsolates(classes: Readonly<Span<BidiClass>>, ref matching: Vec<int32>): void {
	const count: int32 = classes.length as int32;
	for (let i = 0; i < count; i++) { matching.push(NO_MATCH); }
	let open: Vec<int32> = new Array(0);
	for (let i = 0; i < count; i++) {
		const c: BidiClass = classes[i];
		if (isolateInitiator(c)) {
			open.push(i);
		} else if (c == BidiClass.PDI && (open.length as int32) > 0) {
			const from: int32 = open.pop();
			matching[from] = i;
		} else if (c == BidiClass.B) {
			while ((open.length as int32) > 0) { open.pop(); }
		}
	}
}

function firstStrong(
	classes: Readonly<Span<BidiClass>>, matching: Readonly<Span<int32>>, from: int32, to: int32,
): BidiClass {
	let i: int32 = from;
	while (i < to) {
		const c: BidiClass = classes[i];
		if (c == BidiClass.L) { return BidiClass.L; }
		if (c == BidiClass.R || c == BidiClass.AL) { return BidiClass.R; }
		if (isolateInitiator(c)) {
			if (matching[i] == NO_MATCH) { return BidiClass.BN; }
			i = matching[i];
		}
		i = i + 1;
	}
	return BidiClass.BN;
}

struct Status {
	level: Vec<int32>;
	override: Vec<int32>;
	isolate: Vec<boolean>;
}

function pushStatus(ref s: Status, level: int32, override: int32, isolate: boolean): void {
	s.level.push(level);
	s.override.push(override);
	s.isolate.push(isolate);
}

function popStatus(ref s: Status): void {
	s.level.pop();
	s.override.pop();
	s.isolate.pop();
}

function topLevel(s: Status): int32 {
	return s.level[(s.level.length as int32) - 1];
}

function topOverride(s: Status): int32 {
	return s.override[(s.override.length as int32) - 1];
}

function nextLevel(top: int32, odd: boolean): int32 {
	if (odd) { return (top & 1) == 1 ? top + 2 : top + 1; }
	return (top & 1) == 1 ? top + 1 : top + 2;
}

function overridden(c: BidiClass, override: int32): BidiClass {
	if (override == OVERRIDE_L) { return BidiClass.L; }
	if (override == OVERRIDE_R) { return BidiClass.R; }
	return c;
}

function explicitLevels(
	classes: Readonly<Span<BidiClass>>,
	matching: Readonly<Span<int32>>,
	paragraph: int32,
	ref levels: Vec<int32>,
	ref types: Vec<BidiClass>,
): void {
	const count: int32 = classes.length as int32;
	let status: Status = { level: new Array(0), override: new Array(0), isolate: new Array(0) };
	pushStatus(status, paragraph, NEUTRAL, false);
	let overflowIsolates: int32 = 0;
	let overflowEmbeddings: int32 = 0;
	let validIsolates: int32 = 0;
	for (let i = 0; i < count; i++) {
		const c: BidiClass = classes[i];
		if (c == BidiClass.RLE || c == BidiClass.LRE || c == BidiClass.RLO || c == BidiClass.LRO) {
			levels.push(topLevel(status));
			types.push(c);
			const odd: boolean = c == BidiClass.RLE || c == BidiClass.RLO;
			const level: int32 = nextLevel(topLevel(status), odd);
			if (level <= MAX_DEPTH && overflowIsolates == 0 && overflowEmbeddings == 0) {
				const override: int32 = c == BidiClass.RLO
					? OVERRIDE_R
					: (c == BidiClass.LRO ? OVERRIDE_L : NEUTRAL);
				pushStatus(status, level, override, false);
			} else if (overflowIsolates == 0) {
				overflowEmbeddings = overflowEmbeddings + 1;
			}
		} else if (isolateInitiator(c)) {
			levels.push(topLevel(status));
			types.push(overridden(c, topOverride(status)));
			let odd: boolean = c == BidiClass.RLI;
			if (c == BidiClass.FSI) {
				const end: int32 = matching[i] == NO_MATCH ? count : matching[i];
				odd = firstStrong(classes, matching, i + 1, end) == BidiClass.R;
			}
			const level: int32 = nextLevel(topLevel(status), odd);
			if (level <= MAX_DEPTH && overflowIsolates == 0 && overflowEmbeddings == 0) {
				validIsolates = validIsolates + 1;
				pushStatus(status, level, NEUTRAL, true);
			} else {
				overflowIsolates = overflowIsolates + 1;
			}
		} else if (c == BidiClass.PDI) {
			if (overflowIsolates > 0) {
				overflowIsolates = overflowIsolates - 1;
			} else if (validIsolates > 0) {
				overflowEmbeddings = 0;
				while (!status.isolate[(status.isolate.length as int32) - 1]) { popStatus(status); }
				popStatus(status);
				validIsolates = validIsolates - 1;
			}
			levels.push(topLevel(status));
			types.push(overridden(c, topOverride(status)));
		} else if (c == BidiClass.PDF) {
			levels.push(topLevel(status));
			types.push(c);
			if (overflowIsolates == 0 && overflowEmbeddings > 0) {
				overflowEmbeddings = overflowEmbeddings - 1;
			} else if (overflowIsolates == 0 &&
				!status.isolate[(status.isolate.length as int32) - 1] &&
				(status.level.length as int32) >= 2) {
				popStatus(status);
			}
		} else if (c == BidiClass.B) {
			levels.push(paragraph);
			types.push(c);
			while ((status.level.length as int32) > 1) { popStatus(status); }
			overflowIsolates = 0;
			overflowEmbeddings = 0;
			validIsolates = 0;
		} else if (c == BidiClass.BN) {
			levels.push(topLevel(status));
			types.push(c);
		} else {
			levels.push(topLevel(status));
			types.push(overridden(c, topOverride(status)));
		}
	}
}

function resolveWeak(ref t: Vec<BidiClass>, sos: BidiClass): void {
	const m: int32 = t.length as int32;
	for (let i = 0; i < m; i++) {
		if (t[i] != BidiClass.NSM) { continue; }
		const previous: BidiClass = i == 0 ? sos : t[i - 1];
		t[i] = isolateInitiator(previous) || previous == BidiClass.PDI ? BidiClass.ON : previous;
	}
	for (let i = 0; i < m; i++) {
		if (t[i] != BidiClass.EN) { continue; }
		for (let j = i - 1; j >= 0; j--) {
			if (t[j] == BidiClass.AL) {
				t[i] = BidiClass.AN;
				break;
			}
			if (t[j] == BidiClass.L || t[j] == BidiClass.R) { break; }
		}
	}
	for (let i = 0; i < m; i++) {
		if (t[i] == BidiClass.AL) { t[i] = BidiClass.R; }
	}
	for (let i = 1; i + 1 < m; i++) {
		if (t[i] == BidiClass.ES && t[i - 1] == BidiClass.EN && t[i + 1] == BidiClass.EN) {
			t[i] = BidiClass.EN;
		} else if (t[i] == BidiClass.CS) {
			if (t[i - 1] == BidiClass.EN && t[i + 1] == BidiClass.EN) {
				t[i] = BidiClass.EN;
			} else if (t[i - 1] == BidiClass.AN && t[i + 1] == BidiClass.AN) {
				t[i] = BidiClass.AN;
			}
		}
	}
	let at: int32 = 0;
	while (at < m) {
		if (t[at] != BidiClass.ET) {
			at = at + 1;
			continue;
		}
		let end: int32 = at;
		while (end < m && t[end] == BidiClass.ET) { end = end + 1; }
		const beside: boolean = (at > 0 && t[at - 1] == BidiClass.EN) ||
			(end < m && t[end] == BidiClass.EN);
		if (beside) {
			for (let k = at; k < end; k++) { t[k] = BidiClass.EN; }
		}
		at = end;
	}
	for (let i = 0; i < m; i++) {
		if (t[i] == BidiClass.ES || t[i] == BidiClass.ET || t[i] == BidiClass.CS) {
			t[i] = BidiClass.ON;
		}
	}
	for (let i = 0; i < m; i++) {
		if (t[i] != BidiClass.EN) { continue; }
		let strong: BidiClass = sos;
		for (let j = i - 1; j >= 0; j--) {
			if (t[j] == BidiClass.L || t[j] == BidiClass.R) {
				strong = t[j];
				break;
			}
		}
		if (strong == BidiClass.L) { t[i] = BidiClass.L; }
	}
}

struct BracketPair {
	open: int32;
	close: int32;
}

function pairBrackets(
	t: Readonly<Span<BidiClass>>, codes: Readonly<Span<int32>>, ref pairs: Vec<BracketPair>,
): void {
	const m: int32 = t.length as int32;
	let opens: Vec<int32> = new Array(0);
	for (let i = 0; i < m; i++) {
		const code: int32 = codes[i];
		if (code == 0 || t[i] != BidiClass.ON) { continue; }
		if ((code & 1) == 1) {
			if ((opens.length as int32) == MAX_BRACKET_STACK) { break; }
			opens.push(i);
			continue;
		}
		for (let k = (opens.length as int32) - 1; k >= 0; k--) {
			if ((codes[opens[k]] >> 1) == (code >> 1)) {
				pairs.push({ open: opens[k], close: i });
				while ((opens.length as int32) > k) { opens.pop(); }
				break;
			}
		}
	}
	for (let a = 1; a < (pairs.length as int32); a++) {
		const held: BracketPair = pairs[a];
		let b: int32 = a - 1;
		while (b >= 0 && pairs[b].open > held.open) {
			pairs[b + 1] = pairs[b];
			b = b - 1;
		}
		pairs[b + 1] = held;
	}
}

function followNsm(
	ref t: Vec<BidiClass>, nsm: Readonly<Span<boolean>>, from: int32, to: BidiClass,
): void {
	let k: int32 = from + 1;
	while (k < (t.length as int32) && nsm[k]) {
		t[k] = to;
		k = k + 1;
	}
}

function resolveBrackets(
	ref t: Vec<BidiClass>,
	codes: Readonly<Span<int32>>,
	nsm: Readonly<Span<boolean>>,
	level: int32,
	sos: BidiClass,
): void {
	let pairs: Vec<BracketPair> = new Array(0);
	pairBrackets(t, codes, pairs);
	const embedding: BidiClass = directionOfLevel(level);
	for (const pair of pairs) {
		let foundEmbedding: boolean = false;
		let foundOpposite: boolean = false;
		for (let k = pair.open + 1; k < pair.close; k++) {
			const c: BidiClass = t[k];
			if (c != BidiClass.L && c != BidiClass.R && c != BidiClass.EN && c != BidiClass.AN) {
				continue;
			}
			if (strongDirection(c) == embedding) { foundEmbedding = true; } else { foundOpposite = true; }
		}
		let resolved: BidiClass = BidiClass.ON;
		if (foundEmbedding) {
			resolved = embedding;
		} else if (foundOpposite) {
			let context: BidiClass = sos;
			for (let k = pair.open - 1; k >= 0; k--) {
				const c: BidiClass = t[k];
				if (c == BidiClass.L || c == BidiClass.R || c == BidiClass.EN || c == BidiClass.AN) {
					context = strongDirection(c);
					break;
				}
			}
			resolved = context;
		}
		if (resolved == BidiClass.ON) { continue; }
		t[pair.open] = resolved;
		t[pair.close] = resolved;
		followNsm(t, nsm, pair.open, resolved);
		followNsm(t, nsm, pair.close, resolved);
	}
}

function resolveNeutrals(ref t: Vec<BidiClass>, level: int32, sos: BidiClass, eos: BidiClass): void {
	const m: int32 = t.length as int32;
	const embedding: BidiClass = directionOfLevel(level);
	let at: int32 = 0;
	while (at < m) {
		if (!neutralOrIsolate(t[at])) {
			at = at + 1;
			continue;
		}
		let end: int32 = at;
		while (end < m && neutralOrIsolate(t[end])) { end = end + 1; }
		const before: BidiClass = at == 0 ? sos : strongDirection(t[at - 1]);
		const after: BidiClass = end == m ? eos : strongDirection(t[end]);
		const resolved: BidiClass = before == after ? before : embedding;
		for (let k = at; k < end; k++) { t[k] = resolved; }
		at = end;
	}
}

function implicitLevel(c: BidiClass, level: int32): int32 {
	if ((level & 1) == 0) {
		if (c == BidiClass.R) { return level + 1; }
		if (c == BidiClass.AN || c == BidiClass.EN) { return level + 2; }
		return level;
	}
	if (c == BidiClass.L || c == BidiClass.EN || c == BidiClass.AN) { return level + 1; }
	return level;
}

function filled(count: int32, value: int32): Vec<int32> {
	let out: Vec<int32> = new Array(0);
	for (let i = 0; i < count; i++) { out.push(value); }
	return out;
}

export function paragraphLevel(
	classes: Readonly<Span<BidiClass>>, direction: TextDirection,
): int32 {
	if (direction == TextDirection.Ltr) { return 0; }
	if (direction == TextDirection.Rtl) { return 1; }
	let matching: Vec<int32> = new Array(0);
	matchIsolates(classes, matching);
	return firstStrong(classes, matching, 0, classes.length as int32) == BidiClass.R ? 1 : 0;
}

// A character X9 removes takes the level of the one before it, or the paragraph level when it
// comes first (UAX #9 section 5.2).
export function resolveLevels(
	classes: Readonly<Span<BidiClass>>,
	brackets: Readonly<Span<int32>>,
	direction: TextDirection,
	ref levels: Vec<int32>,
): int32 {
	const count: int32 = classes.length as int32;
	let matching: Vec<int32> = new Array(0);
	matchIsolates(classes, matching);
	let paragraph: int32 = 0;
	if (direction == TextDirection.Rtl) {
		paragraph = 1;
	} else if (direction == TextDirection.Auto) {
		paragraph = firstStrong(classes, matching, 0, count) == BidiClass.R ? 1 : 0;
	}
	let explicit: Vec<int32> = new Array(0);
	let types: Vec<BidiClass> = new Array(0);
	explicitLevels(classes, matching, paragraph, explicit, types);

	let kept: Vec<int32> = new Array(0);
	for (let i = 0; i < count; i++) {
		if (!removedByX9(classes[i])) { kept.push(i); }
	}
	const keptCount: int32 = kept.length as int32;
	let runStart: Vec<int32> = new Array(0);
	let runEnd: Vec<int32> = new Array(0);
	let runOf: Vec<int32> = filled(count, NO_MATCH);
	for (let k = 0; k < keptCount; k++) {
		if (k == 0 || explicit[kept[k]] != explicit[kept[k - 1]]) {
			runStart.push(k);
			runEnd.push(k + 1);
		} else {
			runEnd[(runEnd.length as int32) - 1] = k + 1;
		}
		runOf[kept[k]] = (runStart.length as int32) - 1;
	}
	const runCount: int32 = runStart.length as int32;
	let following: Vec<int32> = filled(runCount, NO_MATCH);
	let hasPrevious: Vec<boolean> = new Array(0);
	for (let r = 0; r < runCount; r++) { hasPrevious.push(false); }
	for (let r = 0; r < runCount; r++) {
		const last: int32 = kept[runEnd[r] - 1];
		if (!isolateInitiator(classes[last]) || matching[last] == NO_MATCH) { continue; }
		const target: int32 = runOf[matching[last]];
		if (kept[runStart[target]] != matching[last]) { continue; }
		following[r] = target;
		hasPrevious[target] = true;
	}

	let resolved: Vec<int32> = new Array(0);
	for (let i = 0; i < count; i++) { resolved.push(explicit[i]); }
	for (let r = 0; r < runCount; r++) {
		if (hasPrevious[r]) { continue; }
		let positions: Vec<int32> = new Array(0);
		let run: int32 = r;
		while (run != NO_MATCH) {
			for (let k = runStart[run]; k < runEnd[run]; k++) { positions.push(kept[k]); }
			run = following[run];
		}
		const m: int32 = positions.length as int32;
		const level: int32 = explicit[positions[0]];
		const last: int32 = positions[m - 1];
		let before: int32 = paragraph;
		const firstKept: int32 = runStart[r];
		if (firstKept > 0) { before = explicit[kept[firstKept - 1]]; }
		let after: int32 = paragraph;
		if (!(isolateInitiator(classes[last]) && matching[last] == NO_MATCH)) {
			const lastKept: int32 = runEnd[runOf[last]] - 1;
			if (lastKept + 1 < keptCount) { after = explicit[kept[lastKept + 1]]; }
		}
		const sos: BidiClass = directionOfLevel(Math.max(level, before));
		const eos: BidiClass = directionOfLevel(Math.max(level, after));
		let t: Vec<BidiClass> = new Array(0);
		let nsm: Vec<boolean> = new Array(0);
		let codes: Vec<int32> = new Array(0);
		for (const p of positions) {
			t.push(types[p]);
			nsm.push(types[p] == BidiClass.NSM);
			codes.push(brackets.length > 0 ? brackets[p] : 0);
		}
		resolveWeak(t, sos);
		if (brackets.length > 0) { resolveBrackets(t, codes, nsm, level, sos); }
		resolveNeutrals(t, level, sos, eos);
		for (let k = 0; k < m; k++) { resolved[positions[k]] = implicitLevel(t[k], level); }
	}
	let carried: int32 = paragraph;
	for (let i = 0; i < count; i++) {
		if (removedByX9(classes[i])) {
			resolved[i] = carried;
		} else {
			carried = resolved[i];
		}
		levels.push(resolved[i]);
	}
	return paragraph;
}

// Characters X9 removes count as whitespace here (UAX #9 section 5.2).
export function resetLineEnds(
	classes: Readonly<Span<BidiClass>>,
	paragraph: int32,
	from: int32,
	to: int32,
	ref levels: Vec<int32>,
): void {
	let trailing: boolean = true;
	for (let i = to - 1; i >= from; i--) {
		const c: BidiClass = classes[i];
		if (c == BidiClass.B || c == BidiClass.S) {
			levels[i] = paragraph;
			trailing = true;
		} else if (c == BidiClass.WS || isolateInitiator(c) || c == BidiClass.PDI ||
			removedByX9(c)) {
			if (trailing) { levels[i] = paragraph; }
		} else {
			trailing = false;
		}
	}
}

export function reorderLine(
	levels: Readonly<Span<int32>>, from: int32, to: int32, ref order: Vec<int32>,
): void {
	const base: int32 = order.length as int32;
	let highest: int32 = 0;
	let lowestOdd: int32 = MAX_DEPTH + 2;
	for (let i = from; i < to; i++) {
		order.push(i);
		if (levels[i] > highest) { highest = levels[i]; }
		if ((levels[i] & 1) == 1 && levels[i] < lowestOdd) { lowestOdd = levels[i]; }
	}
	for (let level = highest; level >= lowestOdd; level--) {
		let i: int32 = from;
		while (i < to) {
			if (levels[i] < level) {
				i = i + 1;
				continue;
			}
			let end: int32 = i;
			while (end < to && levels[end] >= level) { end = end + 1; }
			let a: int32 = base + i - from;
			let b: int32 = base + end - 1 - from;
			while (a < b) {
				const held: int32 = order[a];
				order[a] = order[b];
				order[b] = held;
				a = a + 1;
				b = b - 1;
			}
			i = end;
		}
	}
}
