import { kbBoundsFail } from "./blob";
import { KbShapeConfig } from "./config";
import {
	kbDllistInsertAfter,
	kbDllistInsertBefore,
	kbDllistRemove,
	kbDllistReverseSublist,
	kbDllistSort,
} from "./dllist";
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
const USE_PRE_BASE_CLASSES: uint64 = kbSet64([
	KB_USE_SYLLABIC_CLASS_VOWEL_PRE,
	KB_USE_SYLLABIC_CLASS_VOWEL_MOD_PRE,
]);
const KHMER_CLUSTER_START_CLASSES: uint64 = kbSet64([
	KB_INDIC_SYLLABIC_CLASS_CONSONANT, KB_INDIC_SYLLABIC_CLASS_RA, KB_INDIC_SYLLABIC_CLASS_VOWEL,
	KB_INDIC_SYLLABIC_CLASS_DOTTED_CIRCLE, KB_INDIC_SYLLABIC_CLASS_PLACEHOLDER,
]);
const MYANMAR_BASE_CLASSES: uint64 = kbSet64([
	KB_INDIC_SYLLABIC_CLASS_CONSONANT,
	KB_INDIC_SYLLABIC_CLASS_CONSONANT_WITH_STACKER,
	KB_INDIC_SYLLABIC_CLASS_RA,
	KB_INDIC_SYLLABIC_CLASS_VOWEL,
	KB_INDIC_SYLLABIC_CLASS_PLACEHOLDER,
	KB_INDIC_SYLLABIC_CLASS_DOTTED_CIRCLE,
]);

const USE_STATE_COUNT: int64 = KB_USE_STATE_s0 as int64;
const USE_PRE_BASE_VOWEL_CAPACITY: int32 = 16;
const KHMER_PRE_BASE_GLYPH_CAPACITY: int32 = 3;
const KHMER_PRE_BASE_OVERFLOW = "Khmer syllable has more pre-base glyphs than the C buffer holds";

function transition(
	table: uint8[],
	classValue: int64,
	classCount: int64,
	stateCount: int64,
	state: int64,
	what: string,
): int64 {
	if (classValue >= classCount) {
		throw kbBoundsFail(what, classValue);
	}
	return table[(classValue * stateCount + state) as int32] as int64;
}

// The C leaves Result at Glyph->Next for the shapers with no clusters.
export function kbBeginCluster(
	s: KbScratch,
	m: Span<uint8>,
	config: KbShapeConfig,
	glyph: int32,
): int32 {
	s.realCluster = false;

	return match (config.shaper) {
		KB_SHAPER_INDIC => kbIndicBeginCluster(s, m, config, glyph),
		KB_SHAPER_USE => useBeginCluster(s, glyph),
		KB_SHAPER_KHMER => khmerBeginCluster(s, config, glyph),
		KB_SHAPER_MYANMAR => myanmarBeginCluster(s, glyph),
		_ => s.storage.glyphs[glyph].next,
	};
}

export function kbEndCluster(s: KbScratch, config: KbShapeConfig): void {
	match (config.shaper) {
		KB_SHAPER_INDIC => { kbIndicEndCluster(s, config); },
		KB_SHAPER_USE => { useEndCluster(s, config); },
		KB_SHAPER_MYANMAR => { myanmarEndCluster(s); },
		_ => {},
	}
}

function useBeginCluster(s: KbScratch, start: int32): int32 {
	const glyphs = s.storage.glyphs;

	let glyph = start;
	let nonCluster = false;
	while (glyph != KB_GLYPH_SENTINEL &&
		(glyphs[glyph].useClass == KB_USE_SYLLABIC_CLASS_OTHER ||
			glyphs[glyph].useClass == KB_USE_SYLLABIC_CLASS_CONS_FINAL_MOD_POST)) {
		nonCluster = true;

		glyph = glyphs[glyph].next;
	}

	if (!nonCluster) {
		let state: int64 = 0;

		const startGlyph = glyph;
		while (glyph != KB_GLYPH_SENTINEL && state < USE_STATE_COUNT) {
			state = (transition(KB_USE_TRANSITION, glyphs[glyph].useClass,
				KB_USE_SYLLABIC_CLASS_COUNT as int64, USE_STATE_COUNT, state,
				"USE class outside the transition table") - 1) & 0xFF;
			glyph = glyphs[glyph].next;
		}

		if (state >= USE_STATE_COUNT) {
			glyph = glyphs[glyph].prev;
		}
		if (glyph != KB_GLYPH_SENTINEL && glyphs[glyph].useClass == KB_USE_SYLLABIC_CLASS_ZWNJ) {
			glyph = glyphs[glyph].next;
		}
		if (glyph == startGlyph) {
			glyph = glyphs[glyph].next;
		}

		s.realCluster = true;
	}

	return glyph;
}

function khmerBeginCluster(s: KbScratch, config: KbShapeConfig, start: int32): int32 {
	const storage = s.storage;
	const glyphs = storage.glyphs;

	let glyph = start;
	let nonCluster = false;
	while (glyph != KB_GLYPH_SENTINEL &&
		(glyphs[glyph].syllabicClass == KB_INDIC_SYLLABIC_CLASS_OTHER ||
			glyphs[glyph].syllabicClass >= KB_KHMER_SYLLABIC_CLASS_COUNT)) {
		glyph = glyphs[glyph].next;
		nonCluster = true;
	}

	if (nonCluster) {
		return glyph;
	}

	const stateCount = KB_KHMER_SYLLABIC_STATE_COUNT as int64;
	let state: int64 = 0;
	let firstGlyph = glyph;
	const oneBeforeSyllableGlyph = glyphs[glyph].prev;

	while (glyph != KB_GLYPH_SENTINEL && state < stateCount) {
		state = (transition(KB_KHMER_TRANSITION, glyphs[glyph].syllabicClass,
			KB_KHMER_SYLLABIC_CLASS_COUNT as int64, stateCount, state,
			"Khmer syllabic class outside the transition table") - 1) & 0xFF;
		glyph = glyphs[glyph].next;
	}

	if (state >= stateCount) {
		glyph = glyphs[glyph].prev;
	}
	if (glyph == firstGlyph) {
		glyph = glyphs[glyph].next;
	}

	const onePastLastSyllableGlyph = glyph;

	if (config.dottedCircle.id != 0 &&
		!kbInSet64(glyphs[firstGlyph].syllabicClass, KHMER_CLUSTER_START_CLASSES)) {
		const newFirstGlyph = kbInsertGlyphBefore(storage, firstGlyph, config.dottedCircle);

		glyphs[newFirstGlyph].userIdOrCodepointIndex = glyphs[firstGlyph].userIdOrCodepointIndex;
		firstGlyph = newFirstGlyph;
	}

	const preBaseGlyphs: int32[] = [];
	let sawHalantRa = false;
	let classes: int64 = 0;

	let addFlags: uint32 = KB_GLYPH_FLAG_ABVF | KB_GLYPH_FLAG_BLWF | KB_GLYPH_FLAG_PSTF;

	let lastGlyph = onePastLastSyllableGlyph;
	glyph = glyphs[onePastLastSyllableGlyph].prev;
	while (glyph != oneBeforeSyllableGlyph) {
		const classValue = glyphs[glyph].syllabicClass as int64;

		if (glyph == firstGlyph) {
			addFlags = 0;
		}

		glyphs[glyph].flags |= addFlags;

		classes = ((classes << 8) | classValue) & 0xFFFF;

		if (classValue == KB_INDIC_SYLLABIC_CLASS_VOWEL_PRE) {
			if (preBaseGlyphs.length >= KHMER_PRE_BASE_GLYPH_CAPACITY) {
				throw kbBoundsFail(KHMER_PRE_BASE_OVERFLOW, preBaseGlyphs.length as int64);
			}
			preBaseGlyphs.push(glyph);
		} else if (!sawHalantRa &&
			classes == ((KB_INDIC_SYLLABIC_CLASS_HALANT as int64) |
				((KB_INDIC_SYLLABIC_CLASS_RA as int64) << 8))) {
			glyphs[glyph].flags |= KB_GLYPH_FLAG_PREF;
			glyphs[lastGlyph].flags |= KB_GLYPH_FLAG_PREF;

			if (preBaseGlyphs.length + 2 > KHMER_PRE_BASE_GLYPH_CAPACITY) {
				throw kbBoundsFail(KHMER_PRE_BASE_OVERFLOW, preBaseGlyphs.length as int64);
			}
			preBaseGlyphs.push(glyph);
			preBaseGlyphs.push(lastGlyph);

			let postRaGlyph = glyphs[lastGlyph].next;
			while (postRaGlyph != onePastLastSyllableGlyph) {
				glyphs[postRaGlyph].flags |= KB_GLYPH_FLAG_CFAR;
				postRaGlyph = glyphs[postRaGlyph].next;
			}

			sawHalantRa = true;
		}

		lastGlyph = glyph;
		glyph = glyphs[glyph].prev;
	}

	while (preBaseGlyphs.length > 0) {
		const preBaseGlyph = preBaseGlyphs.pop() as int32;
		kbDllistRemove(storage, preBaseGlyph);
		kbDllistInsertAfter(storage, preBaseGlyph, oneBeforeSyllableGlyph);
	}

	return onePastLastSyllableGlyph;
}

function myanmarBeginCluster(s: KbScratch, start: int32): int32 {
	const glyphs = s.storage.glyphs;

	let glyph = start;
	let nonCluster = false;
	while (glyph != KB_GLYPH_SENTINEL &&
		(glyphs[glyph].syllabicClass == KB_INDIC_SYLLABIC_CLASS_OTHER ||
			glyphs[glyph].syllabicClass >= KB_MYANMAR_SYLLABIC_CLASS_COUNT)) {
		nonCluster = true;
		glyph = glyphs[glyph].next;
	}

	if (!nonCluster) {
		const stateCount = KB_MYANMAR_SYLLABIC_STATE_COUNT as int64;
		let state: int64 = 0;
		const firstGlyph = glyph;
		while (glyph != KB_GLYPH_SENTINEL && state < stateCount) {
			state = (transition(KB_MYANMAR_TRANSITION, glyphs[glyph].syllabicClass,
				KB_MYANMAR_SYLLABIC_CLASS_COUNT as int64, stateCount, state,
				"Myanmar syllabic class outside the transition table") - 1) & 0xFF;

			glyph = glyphs[glyph].next;
		}

		if (state >= stateCount) {
			glyph = glyphs[glyph].prev;
		}
		if (glyph == firstGlyph) {
			glyph = glyphs[glyph].next;
		}

		s.realCluster = true;
	}

	return glyph;
}

function useEndCluster(s: KbScratch, config: KbShapeConfig): void {
	const storage = s.storage;
	const glyphs = storage.glyphs;

	const repha = glyphs[KB_GLYPH_SENTINEL].next;
	if (glyphs[repha].useClass == KB_USE_SYLLABIC_CLASS_REPHA ||
		(glyphs[repha].flags & KB_GLYPH_FLAG_RPHF) != 0) {
		let to = glyphs[repha].next;
		while (to != KB_GLYPH_SENTINEL) {
			if (kbInSet64(glyphs[to].useClass, USE_POST_BASE_CLASSES) ||
				((glyphs[to].flags & KB_GLYPH_FLAG_LIGATURE) == 0 &&
					kbInSet64(glyphs[to].useClass, USE_HALANT_CLASSES))) {
				break;
			}
			to = glyphs[to].next;
		}

		kbDllistRemove(storage, repha);
		kbDllistInsertBefore(storage, repha, to);
	}

	let preBaseVowels: int32[] = [];
	let sawBase = false;
	let glyph = glyphs[KB_GLYPH_SENTINEL].prev;
	while (glyph != KB_GLYPH_SENTINEL) {
		sawBase = sawBase || kbInSet64(glyphs[glyph].useClass, USE_BASE_CLASSES);

		const flags = glyphs[glyph].flags;
		if (((flags & KB_GLYPH_FLAG_FIRST_IN_MULTIPLE_SUBSTITUTION) != 0 ||
			(flags & KB_GLYPH_FLAG_MULTIPLE_SUBSTITUTION) == 0) &&
			(kbInSet64(glyphs[glyph].useClass, USE_PRE_BASE_CLASSES) ||
				(flags & KB_GLYPH_FLAG_PREF) != 0)) {
			if (preBaseVowels.length < USE_PRE_BASE_VOWEL_CAPACITY) {
				preBaseVowels.push(glyph);
			}
		} else if ((glyphs[glyph].flags & KB_GLYPH_FLAG_LIGATURE) == 0 &&
			kbInSet64(glyphs[glyph].useClass, USE_HALANT_CLASSES)) {
			let insertAfter = glyph;
			for (const preBaseVowel of preBaseVowels) {
				kbDllistRemove(storage, preBaseVowel);
				kbDllistInsertAfter(storage, preBaseVowel, insertAfter);
				insertAfter = preBaseVowel;
			}
			preBaseVowels = [];

			sawBase = false;
		}

		glyph = glyphs[glyph].prev;
	}

	const dottedCircleInsertBefore = glyphs[KB_GLYPH_SENTINEL].next;

	let insertAfter = KB_GLYPH_SENTINEL;
	for (const preBaseVowel of preBaseVowels) {
		kbDllistRemove(storage, preBaseVowel);
		kbDllistInsertAfter(storage, preBaseVowel, insertAfter);

		insertAfter = preBaseVowel;
	}

	if (s.realCluster && !sawBase && config.dottedCircle.id != 0) {
		const dottedCircle =
			kbInsertGlyphBefore(storage, dottedCircleInsertBefore, config.dottedCircle);

		glyphs[dottedCircle].userIdOrCodepointIndex =
			glyphs[dottedCircleInsertBefore].userIdOrCodepointIndex;
	}
}

function myanmarEndCluster(s: KbScratch): void {
	if (!s.realCluster) {
		return;
	}

	const storage = s.storage;
	const glyphs = storage.glyphs;

	let baseGlyph = KB_GLYPH_SENTINEL;
	const first = glyphs[baseGlyph].next;
	const second = glyphs[first].next;
	const third = glyphs[second].next;
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
		glyphs[first].syllabicClass == KB_INDIC_SYLLABIC_CLASS_RA &&
		glyphs[second].syllabicClass == KB_INDIC_SYLLABIC_CLASS_ASAT &&
		glyphs[third].syllabicClass == KB_INDIC_SYLLABIC_CLASS_HALANT) {
		glyphs[first].syllabicPosition = KB_SYLLABIC_POSITION_AFTER_MAIN;
		glyphs[second].syllabicPosition = KB_SYLLABIC_POSITION_AFTER_MAIN;
		glyphs[third].syllabicPosition = KB_SYLLABIC_POSITION_AFTER_MAIN;

		onePastReph = glyphs[third].next;
		baseGlyph = first;
	}

	let glyph = onePastReph;
	while (glyph != KB_GLYPH_SENTINEL) {
		if (baseGlyph == KB_GLYPH_SENTINEL &&
			kbInSet64(glyphs[glyph].syllabicClass, MYANMAR_BASE_CLASSES)) {
			baseGlyph = glyph;

			break;
		}
		glyph = glyphs[glyph].next;
	}

	if (baseGlyph == KB_GLYPH_SENTINEL && onePastReph != first) {
		baseGlyph = first;
	}

	if (baseGlyph != KB_GLYPH_SENTINEL) {
		let lastPosition: int32 = KB_SYLLABIC_POSITION_SYLLABLE_BASE;
		let sectionPosition: int32 = KB_SYLLABIC_POSITION_AFTER_MAIN;
		let lastPreBaseMatra = KB_GLYPH_SENTINEL;
		glyph = glyphs[baseGlyph].next;
		while (glyph != KB_GLYPH_SENTINEL) {
			const next = glyphs[glyph].next;
			let position = sectionPosition;
			const classValue = glyphs[glyph].syllabicClass;

			match (classValue) {
				KB_INDIC_SYLLABIC_CLASS_MEDIAL_RA => {
					position = KB_SYLLABIC_POSITION_PREBASE_CONSONANT;
				},
				KB_INDIC_SYLLABIC_CLASS_VOWEL_PRE => {
					position = KB_SYLLABIC_POSITION_PREBASE_MATRA;

					if (lastPreBaseMatra != KB_GLYPH_SENTINEL) {
						kbDllistReverseSublist(storage, lastPreBaseMatra, glyphs[glyph].next);
					} else {
						lastPreBaseMatra = glyph;
					}
				},
				KB_INDIC_SYLLABIC_CLASS_VARIATION_SELECTOR => {
					position = lastPosition;
				},
				KB_INDIC_SYLLABIC_CLASS_VOWEL_BELOW => {
					if (position == KB_SYLLABIC_POSITION_AFTER_MAIN) {
						position = KB_SYLLABIC_POSITION_BELOWBASE_CONSONANT;
					} else if (position == KB_SYLLABIC_POSITION_BELOWBASE_CONSONANT) {
						position = sectionPosition;
					}
				},
				KB_INDIC_SYLLABIC_CLASS_VEDIC_SIGN => {
					if (position == KB_SYLLABIC_POSITION_BELOWBASE_CONSONANT) {
						position = KB_SYLLABIC_POSITION_BEFORE_SUBJOINED;
					}
				},
				_ => {},
			}

			if (sectionPosition == KB_SYLLABIC_POSITION_BELOWBASE_CONSONANT &&
				glyphs[glyph].syllabicClass == KB_INDIC_SYLLABIC_CLASS_VEDIC_SIGN) {
				sectionPosition = KB_SYLLABIC_POSITION_AFTER_SUBJOINED;
				position = sectionPosition;
			}

			glyphs[glyph].syllabicPosition = position as uint8;
			lastPosition = position;
			glyph = next;
		}
	}

	if (minimumGlyphCount > 1) {
		kbDllistSort(storage, glyphs[KB_GLYPH_SENTINEL].next, KB_GLYPH_SENTINEL, true);
	}
}
