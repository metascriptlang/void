import { kbBoundsFail } from "./blob";
import { KbShapeConfig } from "./config";
import { kbDllistInsertAfter, kbDllistInsertBefore, kbDllistRemove, kbDllistReverseSublist, kbDllistSort } from "./dllist";
import { KB_GLYPH_SENTINEL, kbInsertGlyphBefore } from "./glyph";
import { kbInSet64, kbSet64 } from "./inset";
import { kbIndicBeginCluster, kbIndicEndCluster } from "./indic";
import { KbScratch } from "./scratch";
import {
	KB_GLYPH_FLAG_ABVF,
	KB_GLYPH_FLAG_BLWF,
	KB_GLYPH_FLAG_CFAR,
	KB_GLYPH_FLAG_FIRST_IN_MULTIPLE_SUBSTITUTION,
	KB_GLYPH_FLAG_LIGATURE,
	KB_GLYPH_FLAG_MULTIPLE_SUBSTITUTION,
	KB_GLYPH_FLAG_PREF,
	KB_GLYPH_FLAG_PSTF,
	KB_GLYPH_FLAG_RPHF,
	KB_INDIC_SYLLABIC_CLASS_ASAT,
	KB_INDIC_SYLLABIC_CLASS_CONSONANT,
	KB_INDIC_SYLLABIC_CLASS_CONSONANT_WITH_STACKER,
	KB_INDIC_SYLLABIC_CLASS_DOTTED_CIRCLE,
	KB_INDIC_SYLLABIC_CLASS_HALANT,
	KB_INDIC_SYLLABIC_CLASS_MEDIAL_RA,
	KB_INDIC_SYLLABIC_CLASS_OTHER,
	KB_INDIC_SYLLABIC_CLASS_PLACEHOLDER,
	KB_INDIC_SYLLABIC_CLASS_RA,
	KB_INDIC_SYLLABIC_CLASS_VARIATION_SELECTOR,
	KB_INDIC_SYLLABIC_CLASS_VEDIC_SIGN,
	KB_INDIC_SYLLABIC_CLASS_VOWEL,
	KB_INDIC_SYLLABIC_CLASS_VOWEL_BELOW,
	KB_INDIC_SYLLABIC_CLASS_VOWEL_PRE,
	KB_KHMER_SYLLABIC_CLASS_COUNT,
	KB_KHMER_SYLLABIC_STATE_COUNT,
	KB_KHMER_TRANSITION,
	KB_MYANMAR_SYLLABIC_CLASS_COUNT,
	KB_MYANMAR_SYLLABIC_STATE_COUNT,
	KB_MYANMAR_TRANSITION,
	KB_SHAPER_INDIC,
	KB_SHAPER_KHMER,
	KB_SHAPER_MYANMAR,
	KB_SHAPER_USE,
	KB_SYLLABIC_POSITION_AFTER_MAIN,
	KB_SYLLABIC_POSITION_AFTER_SUBJOINED,
	KB_SYLLABIC_POSITION_BEFORE_SUBJOINED,
	KB_SYLLABIC_POSITION_BELOWBASE_CONSONANT,
	KB_SYLLABIC_POSITION_PREBASE_CONSONANT,
	KB_SYLLABIC_POSITION_PREBASE_MATRA,
	KB_SYLLABIC_POSITION_SYLLABLE_BASE,
	KB_USE_STATE_s0,
	KB_USE_SYLLABIC_CLASS_BASE,
	KB_USE_SYLLABIC_CLASS_BASE_NUM,
	KB_USE_SYLLABIC_CLASS_BASE_OTHER,
	KB_USE_SYLLABIC_CLASS_CONS_FINAL_ABOVE,
	KB_USE_SYLLABIC_CLASS_CONS_FINAL_BELOW,
	KB_USE_SYLLABIC_CLASS_CONS_FINAL_MOD_ABOVE,
	KB_USE_SYLLABIC_CLASS_CONS_FINAL_MOD_BELOW,
	KB_USE_SYLLABIC_CLASS_CONS_FINAL_MOD_POST,
	KB_USE_SYLLABIC_CLASS_CONS_MED_ABOVE,
	KB_USE_SYLLABIC_CLASS_CONS_MED_BELOW,
	KB_USE_SYLLABIC_CLASS_CONS_MED_POST,
	KB_USE_SYLLABIC_CLASS_CONS_MED_PRE,
	KB_USE_SYLLABIC_CLASS_COUNT,
	KB_USE_SYLLABIC_CLASS_HALANT,
	KB_USE_SYLLABIC_CLASS_HALANT_OR_VOWEL_MODIFIER,
	KB_USE_SYLLABIC_CLASS_INVISIBLE_STACKER,
	KB_USE_SYLLABIC_CLASS_OTHER,
	KB_USE_SYLLABIC_CLASS_REPHA,
	KB_USE_SYLLABIC_CLASS_VOWEL_ABOVE,
	KB_USE_SYLLABIC_CLASS_VOWEL_BELOW,
	KB_USE_SYLLABIC_CLASS_VOWEL_MOD_ABOVE,
	KB_USE_SYLLABIC_CLASS_VOWEL_MOD_BELOW,
	KB_USE_SYLLABIC_CLASS_VOWEL_MOD_POST,
	KB_USE_SYLLABIC_CLASS_VOWEL_MOD_PRE,
	KB_USE_SYLLABIC_CLASS_VOWEL_POST,
	KB_USE_SYLLABIC_CLASS_VOWEL_PRE,
	KB_USE_SYLLABIC_CLASS_ZWNJ,
	KB_USE_TRANSITION,
} from "./shapeTables";

const NO_GLYPH: int32 = -1;

const USE_POST_BASE_CLASSES: uint64 = kbSet64([
	KB_USE_SYLLABIC_CLASS_CONS_FINAL_ABOVE, KB_USE_SYLLABIC_CLASS_CONS_FINAL_BELOW,
	KB_USE_SYLLABIC_CLASS_CONS_FINAL_MOD_ABOVE, KB_USE_SYLLABIC_CLASS_CONS_FINAL_MOD_BELOW,
	KB_USE_SYLLABIC_CLASS_CONS_FINAL_MOD_POST, KB_USE_SYLLABIC_CLASS_CONS_MED_ABOVE,
	KB_USE_SYLLABIC_CLASS_CONS_MED_BELOW, KB_USE_SYLLABIC_CLASS_CONS_MED_POST,
	KB_USE_SYLLABIC_CLASS_CONS_MED_PRE, KB_USE_SYLLABIC_CLASS_VOWEL_ABOVE,
	KB_USE_SYLLABIC_CLASS_VOWEL_BELOW, KB_USE_SYLLABIC_CLASS_VOWEL_POST,
	KB_USE_SYLLABIC_CLASS_VOWEL_PRE, KB_USE_SYLLABIC_CLASS_VOWEL_MOD_ABOVE,
	KB_USE_SYLLABIC_CLASS_VOWEL_MOD_BELOW, KB_USE_SYLLABIC_CLASS_VOWEL_MOD_POST,
	KB_USE_SYLLABIC_CLASS_VOWEL_MOD_PRE,
]);
const USE_HALANT_CLASSES: uint64 = kbSet64([
	KB_USE_SYLLABIC_CLASS_HALANT, KB_USE_SYLLABIC_CLASS_HALANT_OR_VOWEL_MODIFIER,
	KB_USE_SYLLABIC_CLASS_INVISIBLE_STACKER,
]);
const USE_BASE_CLASSES: uint64 = kbSet64([
	KB_USE_SYLLABIC_CLASS_BASE, KB_USE_SYLLABIC_CLASS_BASE_OTHER, KB_USE_SYLLABIC_CLASS_BASE_NUM,
]);
const USE_PRE_BASE_CLASSES: uint64 = kbSet64([KB_USE_SYLLABIC_CLASS_VOWEL_PRE, KB_USE_SYLLABIC_CLASS_VOWEL_MOD_PRE]);
const KHMER_CLUSTER_START_CLASSES: uint64 = kbSet64([
	KB_INDIC_SYLLABIC_CLASS_CONSONANT, KB_INDIC_SYLLABIC_CLASS_RA, KB_INDIC_SYLLABIC_CLASS_VOWEL,
	KB_INDIC_SYLLABIC_CLASS_DOTTED_CIRCLE, KB_INDIC_SYLLABIC_CLASS_PLACEHOLDER,
]);
const MYANMAR_BASE_CLASSES: uint64 = kbSet64([
	KB_INDIC_SYLLABIC_CLASS_CONSONANT, KB_INDIC_SYLLABIC_CLASS_CONSONANT_WITH_STACKER, KB_INDIC_SYLLABIC_CLASS_RA,
	KB_INDIC_SYLLABIC_CLASS_VOWEL, KB_INDIC_SYLLABIC_CLASS_PLACEHOLDER, KB_INDIC_SYLLABIC_CLASS_DOTTED_CIRCLE,
]);

const USE_STATE_COUNT: int64 = KB_USE_STATE_s0 as int64;
const USE_PRE_BASE_VOWEL_CAPACITY: int32 = 16;
const KHMER_PRE_BASE_GLYPH_CAPACITY: int32 = 3;

function transition(table: uint8[], classValue: int64, classCount: int64, stateCount: int64, state: int64, what: string): int64 {
	if (classValue >= classCount) {
		throw kbBoundsFail(what, classValue);
	}
	return table[(classValue * stateCount + state) as int32] as int64;
}

// The C leaves Result at Glyph->Next for the shapers with no clusters.
export function kbBeginCluster(s: KbScratch, m: Span<uint8>, config: KbShapeConfig, glyph: int32): int32 {
	s.realCluster = false;

	if (config.shaper == KB_SHAPER_INDIC) {
		return kbIndicBeginCluster(s, m, config, glyph);
	} else if (config.shaper == KB_SHAPER_USE) {
		return useBeginCluster(s, glyph);
	} else if (config.shaper == KB_SHAPER_KHMER) {
		return khmerBeginCluster(s, config, glyph);
	} else if (config.shaper == KB_SHAPER_MYANMAR) {
		return myanmarBeginCluster(s, glyph);
	}
	return s.storage.glyphs[glyph].next;
}

export function kbEndCluster(s: KbScratch, config: KbShapeConfig): void {
	if (config.shaper == KB_SHAPER_INDIC) {
		kbIndicEndCluster(s, config);
	} else if (config.shaper == KB_SHAPER_USE) {
		useEndCluster(s, config);
	} else if (config.shaper == KB_SHAPER_MYANMAR) {
		myanmarEndCluster(s);
	}
}

function useBeginCluster(s: KbScratch, start: int32): int32 {
	const g = s.storage.glyphs;

	let glyph = start;
	let nonCluster = false;
	while (glyph != KB_GLYPH_SENTINEL &&
		(g[glyph].useClass == KB_USE_SYLLABIC_CLASS_OTHER ||
			g[glyph].useClass == KB_USE_SYLLABIC_CLASS_CONS_FINAL_MOD_POST)) {
		nonCluster = true;

		glyph = g[glyph].next;
	}

	if (!nonCluster) {
		let state: int64 = 0;

		const startGlyph = glyph;
		while (glyph != KB_GLYPH_SENTINEL && state < USE_STATE_COUNT) {
			state = (transition(KB_USE_TRANSITION, g[glyph].useClass, KB_USE_SYLLABIC_CLASS_COUNT as int64,
				USE_STATE_COUNT, state, "USE class outside the transition table") - 1) & 0xFF;
			glyph = g[glyph].next;
		}

		if (state >= USE_STATE_COUNT) {
			glyph = g[glyph].prev;
		}
		if (glyph != KB_GLYPH_SENTINEL && g[glyph].useClass == KB_USE_SYLLABIC_CLASS_ZWNJ) {
			glyph = g[glyph].next;
		}
		if (glyph == startGlyph) {
			glyph = g[glyph].next;
		}

		s.realCluster = true;
	}

	return glyph;
}

function khmerBeginCluster(s: KbScratch, config: KbShapeConfig, start: int32): int32 {
	const storage = s.storage;
	const g = storage.glyphs;

	let glyph = start;
	let nonCluster = false;
	while (glyph != KB_GLYPH_SENTINEL &&
		(g[glyph].syllabicClass == KB_INDIC_SYLLABIC_CLASS_OTHER ||
			g[glyph].syllabicClass >= KB_KHMER_SYLLABIC_CLASS_COUNT)) {
		glyph = g[glyph].next;
		nonCluster = true;
	}

	if (nonCluster) {
		return glyph;
	}

	const stateCount = KB_KHMER_SYLLABIC_STATE_COUNT as int64;
	let state: int64 = 0;
	let firstGlyph = glyph;
	const oneBeforeSyllableGlyph = g[glyph].prev;

	while (glyph != KB_GLYPH_SENTINEL && state < stateCount) {
		state = (transition(KB_KHMER_TRANSITION, g[glyph].syllabicClass, KB_KHMER_SYLLABIC_CLASS_COUNT as int64,
			stateCount, state, "Khmer syllabic class outside the transition table") - 1) & 0xFF;
		glyph = g[glyph].next;
	}

	if (state >= stateCount) {
		glyph = g[glyph].prev;
	}
	if (glyph == firstGlyph) {
		glyph = g[glyph].next;
	}

	const onePastLastSyllableGlyph = glyph;

	if (config.dottedCircle.id != 0 && !kbInSet64(g[firstGlyph].syllabicClass, KHMER_CLUSTER_START_CLASSES)) {
		const newFirstGlyph = kbInsertGlyphBefore(storage, firstGlyph, config.dottedCircle);

		g[newFirstGlyph].userIdOrCodepointIndex = g[firstGlyph].userIdOrCodepointIndex;
		firstGlyph = newFirstGlyph;
	}

	let preBaseGlyphs: int32[] = [];
	let sawHalantRa = false;
	let classes: int64 = 0;

	let addFlags: uint32 = KB_GLYPH_FLAG_ABVF | KB_GLYPH_FLAG_BLWF | KB_GLYPH_FLAG_PSTF;

	let lastGlyph = onePastLastSyllableGlyph;
	glyph = g[onePastLastSyllableGlyph].prev;
	while (glyph != oneBeforeSyllableGlyph) {
		const classValue = g[glyph].syllabicClass as int64;

		if (glyph == firstGlyph) {
			addFlags = 0;
		}

		g[glyph].flags |= addFlags;

		classes = ((classes << 8) | classValue) & 0xFFFF;

		if (classValue == KB_INDIC_SYLLABIC_CLASS_VOWEL_PRE) {
			if (preBaseGlyphs.length >= KHMER_PRE_BASE_GLYPH_CAPACITY) {
				throw kbBoundsFail("Khmer syllable has more pre-base glyphs than the C buffer holds",
					preBaseGlyphs.length as int64);
			}
			preBaseGlyphs.push(glyph);
		} else if (!sawHalantRa &&
			classes == ((KB_INDIC_SYLLABIC_CLASS_HALANT as int64) | ((KB_INDIC_SYLLABIC_CLASS_RA as int64) << 8))) {
			g[glyph].flags |= KB_GLYPH_FLAG_PREF;
			g[lastGlyph].flags |= KB_GLYPH_FLAG_PREF;

			if (preBaseGlyphs.length + 2 > KHMER_PRE_BASE_GLYPH_CAPACITY) {
				throw kbBoundsFail("Khmer syllable has more pre-base glyphs than the C buffer holds",
					preBaseGlyphs.length as int64);
			}
			preBaseGlyphs.push(glyph);
			preBaseGlyphs.push(lastGlyph);

			let postRaGlyph = g[lastGlyph].next;
			while (postRaGlyph != onePastLastSyllableGlyph) {
				g[postRaGlyph].flags |= KB_GLYPH_FLAG_CFAR;
				postRaGlyph = g[postRaGlyph].next;
			}

			sawHalantRa = true;
		}

		lastGlyph = glyph;
		glyph = g[glyph].prev;
	}

	while (preBaseGlyphs.length > 0) {
		const preBaseGlyph = preBaseGlyphs.pop() as int32;
		kbDllistRemove(storage, preBaseGlyph);
		kbDllistInsertAfter(storage, preBaseGlyph, oneBeforeSyllableGlyph);
	}

	return onePastLastSyllableGlyph;
}

function myanmarBeginCluster(s: KbScratch, start: int32): int32 {
	const g = s.storage.glyphs;

	let glyph = start;
	let nonCluster = false;
	while (glyph != KB_GLYPH_SENTINEL &&
		(g[glyph].syllabicClass == KB_INDIC_SYLLABIC_CLASS_OTHER ||
			g[glyph].syllabicClass >= KB_MYANMAR_SYLLABIC_CLASS_COUNT)) {
		nonCluster = true;
		glyph = g[glyph].next;
	}

	if (!nonCluster) {
		const stateCount = KB_MYANMAR_SYLLABIC_STATE_COUNT as int64;
		let state: int64 = 0;
		const firstGlyph = glyph;
		while (glyph != KB_GLYPH_SENTINEL && state < stateCount) {
			state = (transition(KB_MYANMAR_TRANSITION, g[glyph].syllabicClass,
				KB_MYANMAR_SYLLABIC_CLASS_COUNT as int64, stateCount, state,
				"Myanmar syllabic class outside the transition table") - 1) & 0xFF;

			glyph = g[glyph].next;
		}

		if (state >= stateCount) {
			glyph = g[glyph].prev;
		}
		if (glyph == firstGlyph) {
			glyph = g[glyph].next;
		}

		s.realCluster = true;
	}

	return glyph;
}

function useEndCluster(s: KbScratch, config: KbShapeConfig): void {
	const storage = s.storage;
	const g = storage.glyphs;

	const repha = g[KB_GLYPH_SENTINEL].next;
	if (g[repha].useClass == KB_USE_SYLLABIC_CLASS_REPHA || (g[repha].flags & KB_GLYPH_FLAG_RPHF) != 0) {
		let to = g[repha].next;
		while (to != KB_GLYPH_SENTINEL) {
			if (kbInSet64(g[to].useClass, USE_POST_BASE_CLASSES) ||
				((g[to].flags & KB_GLYPH_FLAG_LIGATURE) == 0 && kbInSet64(g[to].useClass, USE_HALANT_CLASSES))) {
				break;
			}
			to = g[to].next;
		}

		kbDllistRemove(storage, repha);
		kbDllistInsertBefore(storage, repha, to);
	}

	let preBaseVowels: int32[] = [];
	let sawBase = false;
	let glyph = g[KB_GLYPH_SENTINEL].prev;
	while (glyph != KB_GLYPH_SENTINEL) {
		sawBase = sawBase || kbInSet64(g[glyph].useClass, USE_BASE_CLASSES);

		const flags = g[glyph].flags;
		if (((flags & KB_GLYPH_FLAG_FIRST_IN_MULTIPLE_SUBSTITUTION) != 0 ||
			(flags & KB_GLYPH_FLAG_MULTIPLE_SUBSTITUTION) == 0) &&
			(kbInSet64(g[glyph].useClass, USE_PRE_BASE_CLASSES) || (flags & KB_GLYPH_FLAG_PREF) != 0)) {
			if (preBaseVowels.length < USE_PRE_BASE_VOWEL_CAPACITY) {
				preBaseVowels.push(glyph);
			}
		} else if ((g[glyph].flags & KB_GLYPH_FLAG_LIGATURE) == 0 && kbInSet64(g[glyph].useClass, USE_HALANT_CLASSES)) {
			let insertAfter = glyph;
			for (let preBaseVowelIndex = 0; preBaseVowelIndex < preBaseVowels.length; preBaseVowelIndex++) {
				const preBaseVowel = preBaseVowels[preBaseVowelIndex];

				kbDllistRemove(storage, preBaseVowel);
				kbDllistInsertAfter(storage, preBaseVowel, insertAfter);
				insertAfter = preBaseVowel;
			}
			preBaseVowels = [];

			sawBase = false;
		}

		glyph = g[glyph].prev;
	}

	const dottedCircleInsertBefore = g[KB_GLYPH_SENTINEL].next;

	let insertAfter = KB_GLYPH_SENTINEL;
	for (let preBaseVowelIndex = 0; preBaseVowelIndex < preBaseVowels.length; preBaseVowelIndex++) {
		const preBaseVowel = preBaseVowels[preBaseVowelIndex];

		kbDllistRemove(storage, preBaseVowel);
		kbDllistInsertAfter(storage, preBaseVowel, insertAfter);

		insertAfter = preBaseVowel;
	}

	if (s.realCluster && !sawBase && config.dottedCircle.id != 0) {
		const dottedCircle = kbInsertGlyphBefore(storage, dottedCircleInsertBefore, config.dottedCircle);

		g[dottedCircle].userIdOrCodepointIndex = g[dottedCircleInsertBefore].userIdOrCodepointIndex;
	}
}

function myanmarEndCluster(s: KbScratch): void {
	if (!s.realCluster) {
		return;
	}

	const storage = s.storage;
	const g = storage.glyphs;

	let baseGlyph = KB_GLYPH_SENTINEL;
	const first = g[baseGlyph].next;
	const second = g[first].next;
	const third = g[second].next;
	let onePastReph = first;

	let minimumGlyphCount = 0;

	if (first != KB_GLYPH_SENTINEL) {
		minimumGlyphCount += 1;

		if (second != KB_GLYPH_SENTINEL) {
			minimumGlyphCount += 1;

			if (third != KB_GLYPH_SENTINEL) {
				minimumGlyphCount += 1;
			}
		}
	}

	if (minimumGlyphCount == 3 &&
		g[first].syllabicClass == KB_INDIC_SYLLABIC_CLASS_RA &&
		g[second].syllabicClass == KB_INDIC_SYLLABIC_CLASS_ASAT &&
		g[third].syllabicClass == KB_INDIC_SYLLABIC_CLASS_HALANT) {
		g[first].syllabicPosition = KB_SYLLABIC_POSITION_AFTER_MAIN;
		g[second].syllabicPosition = KB_SYLLABIC_POSITION_AFTER_MAIN;
		g[third].syllabicPosition = KB_SYLLABIC_POSITION_AFTER_MAIN;

		onePastReph = g[third].next;
		baseGlyph = first;
	}

	let glyph = onePastReph;
	while (glyph != KB_GLYPH_SENTINEL) {
		if (baseGlyph == KB_GLYPH_SENTINEL && kbInSet64(g[glyph].syllabicClass, MYANMAR_BASE_CLASSES)) {
			baseGlyph = glyph;

			break;
		}
		glyph = g[glyph].next;
	}

	if (baseGlyph == KB_GLYPH_SENTINEL && onePastReph != first) {
		baseGlyph = first;
	}

	if (baseGlyph != KB_GLYPH_SENTINEL) {
		let lastPosition: int32 = KB_SYLLABIC_POSITION_SYLLABLE_BASE;
		let sectionPosition: int32 = KB_SYLLABIC_POSITION_AFTER_MAIN;
		let lastPreBaseMatra = KB_GLYPH_SENTINEL;
		glyph = g[baseGlyph].next;
		while (glyph != KB_GLYPH_SENTINEL) {
			const next = g[glyph].next;
			let position = sectionPosition;
			const classValue = g[glyph].syllabicClass;

			if (classValue == KB_INDIC_SYLLABIC_CLASS_MEDIAL_RA) {
				position = KB_SYLLABIC_POSITION_PREBASE_CONSONANT;
			} else if (classValue == KB_INDIC_SYLLABIC_CLASS_VOWEL_PRE) {
				position = KB_SYLLABIC_POSITION_PREBASE_MATRA;

				if (lastPreBaseMatra != KB_GLYPH_SENTINEL) {
					kbDllistReverseSublist(storage, lastPreBaseMatra, g[glyph].next);
				} else {
					lastPreBaseMatra = glyph;
				}
			} else if (classValue == KB_INDIC_SYLLABIC_CLASS_VARIATION_SELECTOR) {
				position = lastPosition;
			} else if (classValue == KB_INDIC_SYLLABIC_CLASS_VOWEL_BELOW) {
				if (position == KB_SYLLABIC_POSITION_AFTER_MAIN) {
					position = KB_SYLLABIC_POSITION_BELOWBASE_CONSONANT;
				} else if (position == KB_SYLLABIC_POSITION_BELOWBASE_CONSONANT) {
					position = sectionPosition;
				}
			} else if (classValue == KB_INDIC_SYLLABIC_CLASS_VEDIC_SIGN) {
				if (position == KB_SYLLABIC_POSITION_BELOWBASE_CONSONANT) {
					position = KB_SYLLABIC_POSITION_BEFORE_SUBJOINED;
				}
			}

			if (sectionPosition == KB_SYLLABIC_POSITION_BELOWBASE_CONSONANT &&
				g[glyph].syllabicClass == KB_INDIC_SYLLABIC_CLASS_VEDIC_SIGN) {
				sectionPosition = KB_SYLLABIC_POSITION_AFTER_SUBJOINED;
				position = sectionPosition;
			}

			g[glyph].syllabicPosition = position as uint8;
			lastPosition = position;
			glyph = next;
		}
	}

	if (minimumGlyphCount > 1) {
		kbDllistSort(storage, g[KB_GLYPH_SENTINEL].next, KB_GLYPH_SENTINEL, true);
	}
}
