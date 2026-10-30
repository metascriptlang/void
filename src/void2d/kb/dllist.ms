import { KbGlyphStorage } from "./glyph";

// The C list macros over glyph indices; the assignment order is the C order, because it decides the
// result when two links name the same glyph (a two-node ring, a node beside the sentinel).

export function kbDllistRemove(storage: KbGlyphStorage, node: int32): void {
	storage.glyphs[storage.glyphs[node].prev].next = storage.glyphs[node].next;
	storage.glyphs[storage.glyphs[node].next].prev = storage.glyphs[node].prev;
}

function relink(storage: KbGlyphStorage, a: int32): void {
	storage.glyphs[storage.glyphs[a].next].prev = a;
	storage.glyphs[storage.glyphs[a].prev].next = a;
}

export function kbDllistInsertBefore(storage: KbGlyphStorage, a: int32, b: int32): void {
	storage.glyphs[a].next = b;
	storage.glyphs[a].prev = storage.glyphs[b].prev;
	relink(storage, a);
}

export function kbDllistInsertAfter(storage: KbGlyphStorage, a: int32, b: int32): void {
	storage.glyphs[a].prev = b;
	storage.glyphs[a].next = storage.glyphs[b].next;
	relink(storage, a);
}

export function kbDllistSwap(storage: KbGlyphStorage, a: int32, b: int32): void {
	const aPrev = storage.glyphs[a].prev;
	const aNext = storage.glyphs[a].next;
	const bPrev = storage.glyphs[b].prev;
	const bNext = storage.glyphs[b].next;

	storage.glyphs[a].prev = bPrev == a ? b : bPrev;
	storage.glyphs[a].next = bNext == a ? b : bNext;
	storage.glyphs[b].prev = aPrev == b ? a : aPrev;
	storage.glyphs[b].next = aNext == b ? a : aNext;

	relink(storage, a);
	relink(storage, b);
}

export function kbDllistReverseSublist(storage: KbGlyphStorage, first: int32, onePastLast: int32): void {
	const oneBeforeFirst = storage.glyphs[first].prev;
	let last = first;

	let glyph = first;
	while (true) {
		const next = storage.glyphs[glyph].next;

		storage.glyphs[glyph].next = storage.glyphs[glyph].prev;
		storage.glyphs[glyph].prev = next;

		last = glyph;
		glyph = next;
		if (glyph == onePastLast) {
			break;
		}
	}

	if (first != onePastLast) {
		storage.glyphs[last].prev = oneBeforeFirst;
		storage.glyphs[storage.glyphs[last].prev].next = last;
		storage.glyphs[first].next = onePastLast;
		storage.glyphs[storage.glyphs[first].next].prev = first;
	}
}

// KBTS__DLLIST_SORT: an insertion sort over the glyph links, keyed by one u8 member. Equal keys keep
// their order because the swap happens only on a strictly greater predecessor.
function sortKey(storage: KbGlyphStorage, glyph: int32, bySyllabicPosition: boolean): int32 {
	return (bySyllabicPosition ? storage.glyphs[glyph].syllabicPosition : storage.glyphs[glyph].markOrdering) as int32;
}

export function kbDllistSort(
	storage: KbGlyphStorage,
	first: int32,
	onePastLast: int32,
	bySyllabicPosition: boolean,
): void {
	const oneBeforeFirst = storage.glyphs[first].prev;
	let forward = first;
	while (forward != onePastLast) {
		const next = storage.glyphs[forward].next;
		const member = sortKey(storage, forward, bySyllabicPosition);

		while (storage.glyphs[forward].prev != oneBeforeFirst) {
			const prev = storage.glyphs[forward].prev;
			if (sortKey(storage, prev, bySyllabicPosition) > member) {
				kbDllistSwap(storage, forward, prev);
			} else {
				break;
			}
		}
		forward = next;
	}
}
