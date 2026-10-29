import { kbGetLookupList } from "./access";
import { KB_BLOB_TABLE_ID_GSUB, kbBoundsFail } from "./blob";
import { KbShapeConfig } from "./config";
import { kbDllistInsertAfter, kbDllistInsertBefore, kbDllistRemove, kbDllistSort, kbDllistSwap } from "./dllist";
import { KB_GLYPH_SENTINEL, KbGlyph, kbInsertGlyphBefore, kbZeroGlyph } from "./glyph";
import { kbInSet32, kbInSet64, kbSet32, kbSet64 } from "./inset";
import { KbScratch } from "./scratch";
import { kbSubstitute1, kbWouldSubstitute } from "./shapeConfig";
import {
	KB_GLYPH_FLAG_ABVF,
	KB_GLYPH_FLAG_BLWF,
	KB_GLYPH_FLAG_GENERATED_BY_GSUB,
	KB_GLYPH_FLAG_HALF,
	KB_GLYPH_FLAG_INIT,
	KB_GLYPH_FLAG_LIGATURE,
	KB_GLYPH_FLAG_MULTIPLE_SUBSTITUTION,
	KB_GLYPH_FLAG_PREF,
	KB_GLYPH_FLAG_PSTF,
	KB_GLYPH_FLAG_RPHF,
	KB_INDIC_SYLLABIC_CLASS_CONSONANT,
	KB_INDIC_SYLLABIC_CLASS_CONSONANT_MEDIAL,
	KB_INDIC_SYLLABIC_CLASS_CONSONANT_WITH_STACKER,
	KB_INDIC_SYLLABIC_CLASS_COUNT,
	KB_INDIC_SYLLABIC_CLASS_DOTTED_CIRCLE,
	KB_INDIC_SYLLABIC_CLASS_HALANT,
	KB_INDIC_SYLLABIC_CLASS_MATRA,
	KB_INDIC_SYLLABIC_CLASS_MATRA_POST,
	KB_INDIC_SYLLABIC_CLASS_NUKTA,
	KB_INDIC_SYLLABIC_CLASS_OTHER,
	KB_INDIC_SYLLABIC_CLASS_PLACEHOLDER,
	KB_INDIC_SYLLABIC_CLASS_RA,
	KB_INDIC_SYLLABIC_CLASS_REPHA,
	KB_INDIC_SYLLABIC_CLASS_SYLLABLE_MODIFIER,
	KB_INDIC_SYLLABIC_CLASS_SYMBOL,
	KB_INDIC_SYLLABIC_CLASS_VEDIC_SIGN,
	KB_INDIC_SYLLABIC_CLASS_VOWEL,
	KB_INDIC_SYLLABIC_CLASS_ZWJ,
	KB_INDIC_SYLLABIC_CLASS_ZWNJ,
	KB_INDIC_SYLLABIC_STATE_COUNT,
	KB_INDIC_TRANSITION,
	KB_REPH_ENCODING_EXPLICIT,
	KB_REPH_ENCODING_IMPLICIT,
	KB_REPH_ENCODING_LOGICAL_REPHA,
	KB_REPH_POSITION_AFTER_MAIN,
	KB_REPH_POSITION_AFTER_SUBJOINED,
	KB_SCRIPT_KANNADA,
	KB_SCRIPT_MALAYALAM,
	KB_SCRIPT_TAMIL,
	KB_SKIP_FLAG_ZWJ,
	KB_SKIP_FLAG_ZWNJ,
	KB_SYLLABIC_POSITION_AFTER_MAIN,
	KB_SYLLABIC_POSITION_AFTER_POST,
	KB_SYLLABIC_POSITION_BELOWBASE_CONSONANT,
	KB_SYLLABIC_POSITION_POSTBASE_CONSONANT,
	KB_SYLLABIC_POSITION_PREBASE_CONSONANT,
	KB_SYLLABIC_POSITION_PREBASE_MATRA,
	KB_SYLLABIC_POSITION_RA_TO_BECOME_REPH,
	KB_SYLLABIC_POSITION_SMVD,
	KB_SYLLABIC_POSITION_SYLLABLE_BASE,
} from "./shapeTables";

const NO_GLYPH: int32 = -1;

const BROKEN_CLEARING_CLASSES: uint32 = kbSet32([
	KB_INDIC_SYLLABIC_CLASS_RA, KB_INDIC_SYLLABIC_CLASS_CONSONANT, KB_INDIC_SYLLABIC_CLASS_VOWEL,
	KB_INDIC_SYLLABIC_CLASS_DOTTED_CIRCLE, KB_INDIC_SYLLABIC_CLASS_PLACEHOLDER, KB_INDIC_SYLLABIC_CLASS_SYMBOL,
]);
const JOINER_CLASSES: uint32 = kbSet32([KB_INDIC_SYLLABIC_CLASS_ZWJ, KB_INDIC_SYLLABIC_CLASS_ZWNJ]);
const HALANT_OR_VEDIC_CLASSES: uint32 = kbSet32([KB_INDIC_SYLLABIC_CLASS_HALANT, KB_INDIC_SYLLABIC_CLASS_VEDIC_SIGN]);
const NUKTA_OR_HALANT_CLASSES: uint32 = kbSet32([KB_INDIC_SYLLABIC_CLASS_NUKTA, KB_INDIC_SYLLABIC_CLASS_HALANT]);
const CONSONANT_CLASSES: uint32 = kbSet32([
	KB_INDIC_SYLLABIC_CLASS_CONSONANT, KB_INDIC_SYLLABIC_CLASS_RA,
	KB_INDIC_SYLLABIC_CLASS_CONSONANT_WITH_STACKER, KB_INDIC_SYLLABIC_CLASS_CONSONANT_MEDIAL,
]);
const MATRA_HALANT_CLASSES: uint32 = kbSet32([
	KB_INDIC_SYLLABIC_CLASS_MATRA, KB_INDIC_SYLLABIC_CLASS_MATRA_POST, KB_INDIC_SYLLABIC_CLASS_HALANT,
]);
const MATRA_MEDIAL_CLASSES: uint32 = kbSet32([
	KB_INDIC_SYLLABIC_CLASS_MATRA, KB_INDIC_SYLLABIC_CLASS_MATRA_POST, KB_INDIC_SYLLABIC_CLASS_CONSONANT_MEDIAL,
]);
const MATRA_MEDIAL_HALANT_CLASSES: uint32 = kbSet32([
	KB_INDIC_SYLLABIC_CLASS_MATRA, KB_INDIC_SYLLABIC_CLASS_MATRA_POST,
	KB_INDIC_SYLLABIC_CLASS_CONSONANT_MEDIAL, KB_INDIC_SYLLABIC_CLASS_HALANT,
]);
const REPH_AFTER_SUBJOINED_POSITIONS: uint32 = kbSet32([
	KB_SYLLABIC_POSITION_POSTBASE_CONSONANT, KB_SYLLABIC_POSITION_AFTER_POST, KB_SYLLABIC_POSITION_SMVD,
]);
const BASE_INHERITING_CLASSES: uint64 = kbSet64([
	KB_INDIC_SYLLABIC_CLASS_HALANT, KB_INDIC_SYLLABIC_CLASS_VEDIC_SIGN, KB_INDIC_SYLLABIC_CLASS_NUKTA,
	KB_INDIC_SYLLABIC_CLASS_ZWJ, KB_INDIC_SYLLABIC_CLASS_ZWNJ,
]);

function indicTransition(classValue: int64, state: int64): int64 {
	if (classValue >= (KB_INDIC_SYLLABIC_CLASS_COUNT as int64)) {
		throw kbBoundsFail("Indic syllabic class outside the transition table", classValue);
	}
	return KB_INDIC_TRANSITION[(classValue * (KB_INDIC_SYLLABIC_STATE_COUNT as int64) + state) as int32] as int64;
}

export function kbIndicBeginCluster(s: KbScratch, m: Span<uint8>, config: KbShapeConfig, start: int32): int32 {
	const storage = s.storage;
	const g = storage.glyphs;

	let glyph = start;
	let nonCluster = false;
	while (glyph != KB_GLYPH_SENTINEL &&
		(g[glyph].syllabicClass == KB_INDIC_SYLLABIC_CLASS_OTHER ||
			g[glyph].syllabicClass >= KB_INDIC_SYLLABIC_CLASS_COUNT)) {
		nonCluster = true;
		glyph = g[glyph].next;
	}

	let result = glyph;
	if (nonCluster) {
		return result;
	}

	const lookupList = kbGetLookupList(m, m.kbBlobTableData(KB_BLOB_TABLE_ID_GSUB));
	const stateCount = KB_INDIC_SYLLABIC_STATE_COUNT as int64;

	let scanGlyphIndex: int64 = 0;
	let state: int64 = 0;
	let broken: uint64 = 1;
	let brokenState: uint64 = 0;
	let firstGlyphs: int32[] = [NO_GLYPH, NO_GLYPH, NO_GLYPH];

	while (glyph != KB_GLYPH_SENTINEL && state < stateCount) {
		const classValue = g[glyph].syllabicClass as int64;

		if (kbInSet32(classValue, BROKEN_CLEARING_CLASSES)) {
			broken = 0;
		}
		brokenState = (brokenState << 1) | broken;

		if (scanGlyphIndex < 3) {
			firstGlyphs[scanGlyphIndex as int32] = glyph;
		}

		state = indicTransition(classValue, state) - 1;
		if (state < 0) {
			throw kbBoundsFail("Indic transition table produced state zero", classValue);
		}
		glyph = g[glyph].next;
		scanGlyphIndex += 1;
	}

	if (state > stateCount) {
		const back = state - stateCount;
		scanGlyphIndex -= back;
		brokenState = brokenState >> ((back & 63) as uint64);

		while (state > stateCount) {
			glyph = g[glyph].prev;
			state -= 1;
		}

		if (scanGlyphIndex < 0) {
			throw kbBoundsFail("Indic syllable backtracked past its first glyph", scanGlyphIndex);
		}
		if (scanGlyphIndex == 0) {
			scanGlyphIndex = 1;
		}
	}

	const onePastLastSyllableGlyph = glyph;
	const firstGlyph = firstGlyphs[0];
	const oneBeforeSyllableGlyph = g[firstGlyph].prev;

	if (config.script == KB_SCRIPT_KANNADA && scanGlyphIndex >= 3 &&
		g[firstGlyphs[0]].syllabicClass == KB_INDIC_SYLLABIC_CLASS_RA &&
		g[firstGlyphs[1]].syllabicClass == KB_INDIC_SYLLABIC_CLASS_HALANT &&
		g[firstGlyphs[2]].syllabicClass == KB_INDIC_SYLLABIC_CLASS_ZWJ) {
		kbDllistSwap(storage, firstGlyphs[1], firstGlyphs[2]);

		const swap = firstGlyphs[1];
		firstGlyphs[1] = firstGlyphs[2];
		firstGlyphs[2] = swap;
	}

	let rephFlags: uint32 = KB_GLYPH_FLAG_RPHF;
	let onePastReph = firstGlyphs[0];
	let onePastRephIndex: int32 = 0;
	{
		const rphf = config.rphf;
		const encoding = config.indicScriptProperties.rephEncoding;

		if (encoding == KB_REPH_ENCODING_LOGICAL_REPHA) {
			if (g[firstGlyph].syllabicClass == KB_INDIC_SYLLABIC_CLASS_REPHA) {
				rephFlags = 0;
				onePastRephIndex = 1;
			}
		} else if (encoding == KB_REPH_ENCODING_IMPLICIT) {
			if (scanGlyphIndex >= 2 && g[firstGlyphs[1]].syllabicClass == KB_INDIC_SYLLABIC_CLASS_HALANT) {
				const scratch: KbGlyph[] = [g[firstGlyphs[0]], g[firstGlyphs[1]]];
				if (kbWouldSubstitute(s, lookupList, rphf, 0, scratch, 0, 2)) {
					onePastRephIndex = 2;
				}
			}
		} else if (encoding == KB_REPH_ENCODING_EXPLICIT) {
			if (scanGlyphIndex >= 3 && g[firstGlyphs[1]].syllabicClass == KB_INDIC_SYLLABIC_CLASS_HALANT &&
				g[firstGlyphs[2]].syllabicClass == KB_INDIC_SYLLABIC_CLASS_ZWJ) {
				const scratch: KbGlyph[] = [g[firstGlyphs[0]], g[firstGlyphs[1]], g[firstGlyphs[2]]];
				if (kbWouldSubstitute(s, lookupList, rphf, 0, scratch, 0, 3)) {
					onePastRephIndex = 3;
				}
			}
		}

		if (onePastRephIndex != 0) {
			onePastReph = g[firstGlyphs[onePastRephIndex - 1]].next;
			while (onePastReph != KB_GLYPH_SENTINEL && kbInSet32(g[onePastReph].syllabicClass, JOINER_CLASSES)) {
				onePastReph = g[onePastReph].next;
			}
		}
	}

	const pref = config.pref;
	let baseGlyph = onePastLastSyllableGlyph;
	let lastConsonant = NO_GLYPH;
	let lastConsonantPosition: int32 = KB_SYLLABIC_POSITION_SYLLABLE_BASE;
	if (config.dottedCircle.id != 0 && (brokenState & 1) != 0) {
		baseGlyph = kbInsertGlyphBefore(storage, onePastReph, config.dottedCircle);
		g[baseGlyph].userIdOrCodepointIndex = g[onePastReph].userIdOrCodepointIndex;
	} else {
		let scratch: KbGlyph[] = [config.virama, kbZeroGlyph(), config.virama];

		const locl = config.locl;
		const vatu = config.vatu;

		let sectionFeature = config.pstf;
		let sectionPosition: int32 = KB_SYLLABIC_POSITION_POSTBASE_CONSONANT;
		let syllabicPosition: int32 = KB_SYLLABIC_POSITION_SYLLABLE_BASE;
		let lastClass: int32 = KB_INDIC_SYLLABIC_CLASS_COUNT;

		glyph = g[onePastLastSyllableGlyph].prev;
		let scanning = true;
		while (scanning) {
			const classValue = g[glyph].syllabicClass as int32;
			let stepped = true;

			if (kbInSet32(classValue, CONSONANT_CLASSES)) {
				scratch[1] = kbSubstitute1(s, lookupList, locl, KB_SKIP_FLAG_ZWNJ | KB_SKIP_FLAG_ZWJ, g[glyph],
					s.sequentialLookupIndexIndex as int32);

				baseGlyph = glyph;

				if (kbWouldSubstitute(s, lookupList, pref, 0, scratch, 0, 2) ||
					kbWouldSubstitute(s, lookupList, pref, 0, scratch, 1, 2) ||
					kbWouldSubstitute(s, lookupList, vatu, 0, scratch, 0, 2) ||
					kbWouldSubstitute(s, lookupList, vatu, 0, scratch, 1, 2)) {
					syllabicPosition = KB_SYLLABIC_POSITION_POSTBASE_CONSONANT;
				} else {
					let searching = true;
					while (searching) {
						if (kbWouldSubstitute(s, lookupList, sectionFeature, 0, scratch, 0, 2) ||
							kbWouldSubstitute(s, lookupList, sectionFeature, 0, scratch, 1, 2)) {
							syllabicPosition = sectionPosition;
							searching = false;
						} else if (sectionPosition == KB_SYLLABIC_POSITION_POSTBASE_CONSONANT) {
							sectionFeature = config.blwf;
							sectionPosition = KB_SYLLABIC_POSITION_BELOWBASE_CONSONANT;
						} else {
							searching = false;
							stepped = false;
							scanning = false;
						}
					}
				}

				if (stepped) {
					if (lastConsonant == NO_GLYPH) {
						lastConsonant = glyph;
						lastConsonantPosition = syllabicPosition;
					}

					g[glyph].syllabicPosition = syllabicPosition as uint8;
				}
			} else if (classValue == KB_INDIC_SYLLABIC_CLASS_VOWEL || classValue == KB_INDIC_SYLLABIC_CLASS_PLACEHOLDER ||
				classValue == KB_INDIC_SYLLABIC_CLASS_DOTTED_CIRCLE) {
				baseGlyph = glyph;
				stepped = false;
				scanning = false;
			} else if (classValue == KB_INDIC_SYLLABIC_CLASS_HALANT) {
				if (lastClass == KB_INDIC_SYLLABIC_CLASS_ZWJ) {
					stepped = false;
					scanning = false;
				} else {
					g[glyph].syllabicPosition = syllabicPosition as uint8;
				}
			} else if (classValue == KB_INDIC_SYLLABIC_CLASS_NUKTA || classValue == KB_INDIC_SYLLABIC_CLASS_ZWJ ||
				classValue == KB_INDIC_SYLLABIC_CLASS_ZWNJ) {
				g[glyph].syllabicPosition = syllabicPosition as uint8;
			}

			if (stepped) {
				lastClass = classValue;
				if (glyph == onePastReph) {
					scanning = false;
				} else {
					glyph = g[glyph].prev;
				}
			}
		}
	}

	if (onePastReph != firstGlyph) {
		let rephPosition: int32 = KB_SYLLABIC_POSITION_RA_TO_BECOME_REPH;
		let flags = rephFlags;
		if (baseGlyph == onePastLastSyllableGlyph) {
			rephPosition = KB_SYLLABIC_POSITION_SYLLABLE_BASE;
			flags = 0;

			onePastReph = firstGlyph;
			baseGlyph = firstGlyph;
		}

		for (let rephIndex = 0; rephIndex < onePastRephIndex; rephIndex++) {
			const rephGlyph = firstGlyphs[rephIndex];
			g[rephGlyph].syllabicPosition = rephPosition as uint8;
			g[rephGlyph].flags |= flags;
		}
	}

	if (baseGlyph != onePastLastSyllableGlyph) {
		g[baseGlyph].syllabicPosition = KB_SYLLABIC_POSITION_SYLLABLE_BASE;

		if (lastConsonant == NO_GLYPH) {
			lastConsonant = baseGlyph;
		}
	}

	{
		let reorderGlyph = g[onePastLastSyllableGlyph].prev;
		while (reorderGlyph != oneBeforeSyllableGlyph) {
			if (g[reorderGlyph].syllabicClass == KB_INDIC_SYLLABIC_CLASS_NUKTA) {
				let prev = g[reorderGlyph].prev;

				while (prev != oneBeforeSyllableGlyph && kbInSet32(g[prev].syllabicClass, HALANT_OR_VEDIC_CLASSES)) {
					const nextPrev = g[prev].prev;

					kbDllistSwap(storage, prev, g[prev].next);

					prev = nextPrev;
				}

				reorderGlyph = prev;
			} else {
				reorderGlyph = g[reorderGlyph].prev;
			}
		}
	}

	{
		let leftMatraCount: int64 = 0;
		glyph = g[oneBeforeSyllableGlyph].next;
		while (glyph != onePastLastSyllableGlyph) {
			let syllabicPosition = (g[glyph].syllabicPosition as int64) << 4;

			if (syllabicPosition == ((KB_SYLLABIC_POSITION_PREBASE_MATRA as int64) << 4)) {
				syllabicPosition += (15 - leftMatraCount) & 0xF;
				leftMatraCount += 1;
			}

			g[glyph].syllabicPosition = (syllabicPosition & 0xFF) as uint8;
			glyph = g[glyph].next;
		}
	}

	{
		const rephAttachPosition = (KB_SYLLABIC_POSITION_RA_TO_BECOME_REPH as int32) << 4;
		const lastConsonantAttachPosition = (lastConsonantPosition << 4) & 0xFF;
		const prebaseConsonantPosition = (KB_SYLLABIC_POSITION_PREBASE_CONSONANT as int32) << 4;

		let currentPosition: int32[] = [rephAttachPosition, lastConsonantAttachPosition];
		let lastPositionThatWasNotPreBaseMatra: int32[] = [rephAttachPosition, lastConsonantAttachPosition];
		let lastClass: int32[] = [KB_INDIC_SYLLABIC_CLASS_COUNT, KB_INDIC_SYLLABIC_CLASS_COUNT];
		const lastConsonantNext = lastConsonant != NO_GLYPH ? g[lastConsonant].next : onePastLastSyllableGlyph;
		let at: int32[] = [onePastReph, lastConsonantNext];
		const end: int32[] = [baseGlyph, onePastLastSyllableGlyph];

		while (true) {
			let done = true;

			for (let stateIndex = 0; stateIndex < 2; stateIndex++) {
				if (at[stateIndex] != end[stateIndex]) {
					glyph = at[stateIndex];

					const classValue = g[glyph].syllabicClass as int32;
					if (kbInSet32(classValue, CONSONANT_CLASSES)) {
						g[glyph].syllabicPosition = prebaseConsonantPosition as uint8;
						currentPosition[stateIndex] = prebaseConsonantPosition;
					} else if (classValue == KB_INDIC_SYLLABIC_CLASS_MATRA_POST ||
						classValue == KB_INDIC_SYLLABIC_CLASS_MATRA) {
						if (classValue == KB_INDIC_SYLLABIC_CLASS_MATRA_POST &&
							lastClass[stateIndex] == KB_INDIC_SYLLABIC_CLASS_SYLLABLE_MODIFIER) {
							g[g[glyph].prev].syllabicPosition = g[glyph].syllabicPosition;
						}

						currentPosition[stateIndex] = g[glyph].syllabicPosition as int32;
						if ((currentPosition[stateIndex] >> 4) != KB_SYLLABIC_POSITION_PREBASE_MATRA) {
							lastPositionThatWasNotPreBaseMatra[stateIndex] = currentPosition[stateIndex];
						}
					} else if (classValue == KB_INDIC_SYLLABIC_CLASS_HALANT) {
						if ((currentPosition[stateIndex] >> 4) == KB_SYLLABIC_POSITION_PREBASE_MATRA) {
							g[glyph].syllabicPosition = lastPositionThatWasNotPreBaseMatra[stateIndex] as uint8;
						} else {
							g[glyph].syllabicPosition = currentPosition[stateIndex] as uint8;
						}
					} else if (classValue == KB_INDIC_SYLLABIC_CLASS_NUKTA || classValue == KB_INDIC_SYLLABIC_CLASS_ZWJ ||
						classValue == KB_INDIC_SYLLABIC_CLASS_ZWNJ) {
						g[glyph].syllabicPosition = currentPosition[stateIndex] as uint8;
					}

					lastClass[stateIndex] = classValue;
					at[stateIndex] = g[glyph].next;
					done = false;
				}
			}

			if (done) {
				break;
			}
		}
	}

	kbDllistSort(storage, g[oneBeforeSyllableGlyph].next, onePastLastSyllableGlyph, true);

	glyph = g[oneBeforeSyllableGlyph].next;
	while (glyph != onePastLastSyllableGlyph) {
		g[glyph].syllabicPosition = g[glyph].syllabicPosition >> 4;
		glyph = g[glyph].next;
	}

	{
		let baseFlags: uint32 = 0;
		if (config.indicScriptProperties.blwfPostOnly == 0) {
			baseFlags = KB_GLYPH_FLAG_BLWF;
		}

		let lastClass: int32 = 0;
		glyph = g[baseGlyph].prev;
		while (glyph != oneBeforeSyllableGlyph) {
			let flags = baseFlags;

			if (lastClass != KB_INDIC_SYLLABIC_CLASS_ZWNJ) {
				flags |= KB_GLYPH_FLAG_HALF;
			}

			g[glyph].flags |= flags;
			lastClass = g[glyph].syllabicClass as int32;
			glyph = g[glyph].prev;
		}
	}

	{
		let scratch: KbGlyph[] = [kbZeroGlyph(), kbZeroGlyph()];
		let lastGlyph = NO_GLYPH;
		glyph = g[baseGlyph].next;
		while (glyph != onePastLastSyllableGlyph) {
			scratch[1] = g[glyph];
			if (kbWouldSubstitute(s, lookupList, pref, 0, scratch, 0, 2)) {
				if (lastGlyph == NO_GLYPH) {
					throw kbBoundsFail("pref matched before any post-base glyph", glyph);
				}
				g[lastGlyph].flags |= KB_GLYPH_FLAG_PREF;
				g[glyph].flags |= KB_GLYPH_FLAG_PREF;
			}

			g[glyph].flags |= KB_GLYPH_FLAG_BLWF | KB_GLYPH_FLAG_ABVF | KB_GLYPH_FLAG_PSTF;
			scratch[0] = scratch[1];
			lastGlyph = glyph;
			glyph = g[glyph].next;
		}
	}

	if (baseGlyph != onePastLastSyllableGlyph) {
		g[baseGlyph].syllabicPosition = KB_SYLLABIC_POSITION_SYLLABLE_BASE;

		let next = g[baseGlyph].next;
		while (next != onePastLastSyllableGlyph &&
			g[next].syllabicPosition < KB_SYLLABIC_POSITION_SYLLABLE_BASE &&
			kbInSet64(g[next].syllabicClass, BASE_INHERITING_CLASSES)) {
			g[next].syllabicPosition = KB_SYLLABIC_POSITION_SYLLABLE_BASE;

			next = g[next].next;
		}
	}

	result = onePastLastSyllableGlyph;
	s.realCluster = true;
	return result;
}

export function kbIndicEndCluster(s: KbScratch, config: KbShapeConfig): void {
	const storage = s.storage;
	const g = storage.glyphs;
	if (g[KB_GLYPH_SENTINEL].next == KB_GLYPH_SENTINEL) {
		return;
	}

	const pref = config.pref;
	const viramaId = config.virama.id;
	let glyph = g[KB_GLYPH_SENTINEL].next;
	while (glyph != KB_GLYPH_SENTINEL) {
		if (viramaId != 0 && g[glyph].id == viramaId) {
			g[glyph].syllabicClass = KB_INDIC_SYLLABIC_CLASS_HALANT;
			g[glyph].flags &= ~(KB_GLYPH_FLAG_LIGATURE | KB_GLYPH_FLAG_MULTIPLE_SUBSTITUTION);
		} else if ((g[glyph].flags & KB_GLYPH_FLAG_LIGATURE) != 0) {
			g[glyph].syllabicClass = KB_INDIC_SYLLABIC_CLASS_COUNT;
		}
		glyph = g[glyph].next;
	}

	let baseGlyph = KB_GLYPH_SENTINEL;
	{
		let afterPreBase = g[KB_GLYPH_SENTINEL].next;
		while (afterPreBase != KB_GLYPH_SENTINEL && g[afterPreBase].syllabicPosition < KB_SYLLABIC_POSITION_SYLLABLE_BASE) {
			afterPreBase = g[afterPreBase].next;
		}

		if (afterPreBase != KB_GLYPH_SENTINEL) {
			baseGlyph = afterPreBase;

			if (pref != 0 && g[afterPreBase].next != KB_GLYPH_SENTINEL) {
				let atGlyph = g[afterPreBase].next;
				while (atGlyph != KB_GLYPH_SENTINEL && (g[atGlyph].flags & KB_GLYPH_FLAG_PREF) == 0) {
					atGlyph = g[atGlyph].next;
				}

				let prefable = atGlyph;
				if (prefable != KB_GLYPH_SENTINEL &&
					((g[prefable].flags & KB_GLYPH_FLAG_GENERATED_BY_GSUB) == 0 ||
						(g[prefable].flags & KB_GLYPH_FLAG_LIGATURE) == 0 ||
						(g[prefable].flags & KB_GLYPH_FLAG_MULTIPLE_SUBSTITUTION) != 0)) {
					while (prefable != KB_GLYPH_SENTINEL && g[prefable].syllabicClass == KB_INDIC_SYLLABIC_CLASS_HALANT) {
						prefable = g[prefable].next;
					}

					if (prefable != KB_GLYPH_SENTINEL) {
						g[prefable].syllabicPosition = KB_SYLLABIC_POSITION_SYLLABLE_BASE;
						baseGlyph = prefable;
					}
				}
			}

			if (config.script == KB_SCRIPT_MALAYALAM) {
				let atGlyph = g[baseGlyph].next;
				while (atGlyph != KB_GLYPH_SENTINEL) {
					while (atGlyph != KB_GLYPH_SENTINEL && kbInSet32(g[atGlyph].syllabicClass, JOINER_CLASSES)) {
						atGlyph = g[atGlyph].next;
					}

					if (atGlyph != KB_GLYPH_SENTINEL && g[atGlyph].syllabicClass == KB_INDIC_SYLLABIC_CLASS_HALANT) {
						atGlyph = g[atGlyph].next;
					} else {
						break;
					}

					while (atGlyph != KB_GLYPH_SENTINEL && kbInSet32(g[atGlyph].syllabicClass, JOINER_CLASSES)) {
						atGlyph = g[atGlyph].next;
					}

					if (atGlyph != KB_GLYPH_SENTINEL) {
						if (kbInSet32(g[atGlyph].syllabicClass, CONSONANT_CLASSES) &&
							g[atGlyph].syllabicPosition == KB_SYLLABIC_POSITION_BELOWBASE_CONSONANT) {
							g[atGlyph].syllabicPosition = KB_SYLLABIC_POSITION_SYLLABLE_BASE;
							baseGlyph = atGlyph;
						}
					}
				}
			}
		}

		if (baseGlyph != KB_GLYPH_SENTINEL && g[baseGlyph].prev != KB_GLYPH_SENTINEL &&
			g[baseGlyph].syllabicPosition > KB_SYLLABIC_POSITION_SYLLABLE_BASE) {
			baseGlyph = g[baseGlyph].prev;
		}

		if (baseGlyph == KB_GLYPH_SENTINEL && g[g[baseGlyph].prev].syllabicClass == KB_INDIC_SYLLABIC_CLASS_ZWJ) {
			baseGlyph = g[baseGlyph].prev;
		}

		if (baseGlyph != KB_GLYPH_SENTINEL) {
			while (g[baseGlyph].prev != KB_GLYPH_SENTINEL && kbInSet32(g[baseGlyph].syllabicClass, NUKTA_OR_HALANT_CLASSES)) {
				baseGlyph = g[baseGlyph].prev;
			}
		}
	}

	if (g[baseGlyph].prev != KB_GLYPH_SENTINEL && g[KB_GLYPH_SENTINEL].prev != g[KB_GLYPH_SENTINEL].next) {
		const firstGlyph = g[KB_GLYPH_SENTINEL].next;
		let to = g[baseGlyph].prev;
		if (baseGlyph == KB_GLYPH_SENTINEL) {
			to = g[to].prev;
		}

		if (config.script != KB_SCRIPT_MALAYALAM && config.script != KB_SCRIPT_TAMIL) {
			let lastGlyph = g[to].next;

			while (true) {
				while (to != firstGlyph && !kbInSet32(g[to].syllabicClass, MATRA_HALANT_CLASSES)) {
					lastGlyph = to;
					to = g[to].prev;
				}

				if (g[to].syllabicClass != KB_INDIC_SYLLABIC_CLASS_HALANT ||
					g[to].syllabicPosition == KB_SYLLABIC_POSITION_PREBASE_MATRA) {
					to = firstGlyph;

					break;
				} else if (to != firstGlyph && lastGlyph != KB_GLYPH_SENTINEL &&
					g[lastGlyph].syllabicClass == KB_INDIC_SYLLABIC_CLASS_ZWJ) {
					to = g[to].prev;
				} else {
					break;
				}
			}
		}

		if (to != firstGlyph && g[to].syllabicPosition != KB_SYLLABIC_POSITION_PREBASE_MATRA) {
			let matra = g[to].prev;
			while (matra != KB_GLYPH_SENTINEL) {
				const matraPrev = g[matra].prev;

				if (g[matra].syllabicPosition == KB_SYLLABIC_POSITION_PREBASE_MATRA) {
					kbDllistRemove(storage, matra);
					kbDllistInsertAfter(storage, matra, to);

					to = g[matra].prev;
				}

				matra = matraPrev;
			}
		}
	}

	let first = g[KB_GLYPH_SENTINEL].next;
	const second = g[first].next;
	if (g[first].syllabicPosition == KB_SYLLABIC_POSITION_RA_TO_BECOME_REPH && second != KB_GLYPH_SENTINEL &&
		g[second].syllabicPosition != KB_SYLLABIC_POSITION_RA_TO_BECOME_REPH) {
		const rephPosition = config.indicScriptProperties.rephPosition;
		let to = NO_GLYPH;

		glyph = first;
		while (glyph != baseGlyph) {
			const next = g[glyph].next;

			if (g[glyph].syllabicClass == KB_INDIC_SYLLABIC_CLASS_HALANT) {
				to = glyph;

				if (next != baseGlyph) {
					const nextClass = g[next].syllabicClass;

					if (nextClass == KB_INDIC_SYLLABIC_CLASS_ZWJ || nextClass == KB_INDIC_SYLLABIC_CLASS_ZWNJ) {
						to = next;
					}
				}

				break;
			}

			glyph = next;
		}

		if (to == NO_GLYPH) {
			if (rephPosition == KB_REPH_POSITION_AFTER_SUBJOINED) {
				glyph = baseGlyph;
				while (glyph != KB_GLYPH_SENTINEL) {
					if (kbInSet32(g[glyph].syllabicPosition, REPH_AFTER_SUBJOINED_POSITIONS)) {
						to = g[glyph].prev;

						break;
					}
					glyph = g[glyph].next;
				}
			} else if (rephPosition == KB_REPH_POSITION_AFTER_MAIN) {
				glyph = baseGlyph;
				while (glyph != KB_GLYPH_SENTINEL) {
					if (g[glyph].syllabicPosition > KB_SYLLABIC_POSITION_AFTER_MAIN) {
						to = g[glyph].prev;

						break;
					}
					glyph = g[glyph].next;
				}
			}
		}

		if (to == NO_GLYPH) {
			glyph = g[KB_GLYPH_SENTINEL].prev;
			while (glyph != KB_GLYPH_SENTINEL) {
				if (g[glyph].syllabicPosition != KB_SYLLABIC_POSITION_SMVD) {
					to = glyph;

					break;
				}
				glyph = g[glyph].prev;
			}

			if (to == NO_GLYPH) {
				throw kbBoundsFail("reph fallback found no glyph outside SMVD", 0);
			}

			if (g[to].syllabicClass == KB_INDIC_SYLLABIC_CLASS_HALANT) {
				let matra = g[baseGlyph].next;
				while (matra != to) {
					if (kbInSet32(g[matra].syllabicClass, MATRA_MEDIAL_CLASSES)) {
						to = g[to].prev;
					}
					matra = g[matra].next;
				}
			}
		}

		if (to != NO_GLYPH && first != to) {
			kbDllistRemove(storage, first);
			kbDllistInsertAfter(storage, first, to);
		}
	}

	if (pref != 0) {
		first = g[KB_GLYPH_SENTINEL].next;
		let prefGlyph = NO_GLYPH;

		glyph = g[baseGlyph].next;
		while (glyph != KB_GLYPH_SENTINEL) {
			if ((g[glyph].flags & KB_GLYPH_FLAG_PREF) != 0) {
				prefGlyph = glyph;

				break;
			}
			glyph = g[glyph].next;
		}

		if (prefGlyph != NO_GLYPH) {
			if ((g[prefGlyph].flags & KB_GLYPH_FLAG_GENERATED_BY_GSUB) != 0) {
				let to = first;

				let last = baseGlyph;
				glyph = g[baseGlyph].prev;
				while (glyph != KB_GLYPH_SENTINEL) {
					if (kbInSet32(g[glyph].syllabicClass, MATRA_MEDIAL_HALANT_CLASSES)) {
						to = last;

						break;
					}

					last = glyph;
					glyph = g[glyph].prev;
				}

				if (to != first) {
					const prev = g[to].prev;
					const currentClass = g[to].syllabicClass;

					if (g[prev].syllabicClass == KB_INDIC_SYLLABIC_CLASS_HALANT &&
						kbInSet32(currentClass, JOINER_CLASSES)) {
						to = g[to].next;
					}
				}

				kbDllistRemove(storage, prefGlyph);
				kbDllistInsertBefore(storage, prefGlyph, to);
			}
		}
	}

	first = g[KB_GLYPH_SENTINEL].next;

	if (g[first].syllabicPosition == KB_SYLLABIC_POSITION_PREBASE_MATRA && s.clusterAtStartOfWord) {
		g[first].flags |= KB_GLYPH_FLAG_INIT;
	}
}
