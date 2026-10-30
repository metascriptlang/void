import { KbShapeConfig } from "./config";
import { kbBoundsFail } from "./blob";
import { kbDllistSort } from "./dllist";
import { kbCodepointToGlyphId } from "./font";
import {
	KB_FREE_GLYPH_SENTINEL,
	KB_GLYPH_SENTINEL,
	KbGlyph,
	KbGlyphStorage,
	kbCodepointToGlyph,
	kbInsertGlyphAfter,
	kbInsertGlyphBefore,
	kbZeroGlyph,
} from "./glyph";
import { KbScratch, kbFreeGlyph, kbNextGlyphUid } from "./scratch";
import {
	KB_DIRECTION_RTL,
	KB_GLYPH_FLAG_DNOM,
	KB_GLYPH_FLAG_DO_NOT_DECOMPOSE,
	KB_GLYPH_FLAG_FRAC,
	KB_GLYPH_FLAG_LJMO,
	KB_GLYPH_FLAG_NUMR,
	KB_GLYPH_FLAG_TJMO,
	KB_GLYPH_FLAG_VJMO,
	KB_HANGUL_SYLLABLE_TYPE_L,
	KB_HANGUL_SYLLABLE_TYPE_LVT,
	KB_HANGUL_SYLLABLE_TYPE_LV,
	KB_HANGUL_SYLLABLE_TYPE_T,
	KB_HANGUL_SYLLABLE_TYPE_V,
	KB_INDIC_SYLLABIC_CLASS_MATRA,
	KB_JOINING_FEATURE_FINA,
	KB_JOINING_FEATURE_INIT,
	KB_JOINING_FEATURE_ISOL,
	KB_JOINING_FEATURE_MED2,
	KB_JOINING_FEATURE_MEDI,
	KB_JOINING_FEATURE_MASK,
	KB_MAXIMUM_RECOMPOSITION_PARENTS,
	KB_MCM_SEQUENCE_STATE_IN,
	KB_MCM_SEQUENCE_STATE_NONE,
	KB_MCM_SEQUENCE_STATE_OUT,
	KB_SCRIPT_ARABIC,
	KB_SCRIPT_LAO,
	KB_SCRIPT_THAI,
	KB_SHAPER_ARABIC,
	KB_SHAPER_HEBREW,
	KB_SHAPER_USE,
	KB_UNICODE_DECOMPOSITION_DO_NOT_RECURSE0,
	KB_UNICODE_DECOMPOSITION_DO_NOT_RECURSE1,
	KB_UNICODE_FLAG_DECIMAL_DIGIT,
	KB_UNICODE_FLAG_MIRRORED,
	KB_UNICODE_FLAG_MODIFIER_COMBINING_MARK,
	KB_UNICODE_JOINING_TYPE_DUAL,
	KB_UNICODE_JOINING_TYPE_FORCE,
	KB_UNICODE_JOINING_TYPE_LEFT,
	KB_UNICODE_JOINING_TYPE_RIGHT,
	KB_UNICODE_JOINING_TYPE_TRANSPARENT,
	kbInvalidIndicCluster,
} from "./shapeTables";
import {
	kbDecomposition,
	kbDecompositionCodepoint,
	kbDecompositionSize,
	kbMirrorCodepoint,
	kbParentInfoCount,
	kbParentInfoOffset,
} from "./unicode";
import { KB_PARENT_DELTAS } from "./unicodeTables";

const NO_GLYPH: int32 = -1;
const REMAPPED_CCC_33: int32 = 27;

export struct KbParent {
	codepoint: uint32;
	codepoint1: uint32;
}

// kbts__SetGlyphPreserveLinksAndUserId: the new glyph keeps the old links and user id, and nothing else.
export function kbSetGlyphPreserveLinksAndUserId(storage: KbGlyphStorage, dest: int32, source: KbGlyph): void {
	const prev = storage.glyphs[dest].prev;
	const next = storage.glyphs[dest].next;
	const userId = storage.glyphs[dest].userIdOrCodepointIndex;

	storage.glyphs[dest] = source;

	storage.glyphs[dest].prev = prev;
	storage.glyphs[dest].next = next;
	storage.glyphs[dest].userIdOrCodepointIndex = userId;
}

function kbLoadParents(glyph: KbGlyph): KbParent[] {
	const offset = kbParentInfoOffset(glyph.parentInfo);
	const count = kbParentInfoCount(glyph.parentInfo);

	let result: KbParent[] = [];
	for (let parentIndex: uint32 = 0; parentIndex < count; parentIndex++) {
		const delta = KB_PARENT_DELTAS[(offset + parentIndex) as int32];
		const codepoint = ((glyph.codepoint as int64 + (delta as int64)) & 0xFFFFFFFF) as uint32;
		const decomposition = kbDecomposition(codepoint);
		result.push({ codepoint, codepoint1: kbDecompositionCodepoint(decomposition, 1) });
	}
	return result;
}

export function kbPreNormalizeDottedCircles(s: KbScratch, config: KbShapeConfig): void {
	const storage = s.storage;
	let codepoints: uint64 = 0;
	let glyph = storage.glyphs[KB_GLYPH_SENTINEL].next;
	while (glyph != KB_GLYPH_SENTINEL) {
		const newCodepoint = (storage.glyphs[glyph].codepoint & 0x1FFFFF) as uint64;
		codepoints = (codepoints << 21) | newCodepoint;

		if (kbInvalidIndicCluster(codepoints)) {
			kbInsertGlyphBefore(storage, glyph, config.dottedCircle);
		}
		glyph = storage.glyphs[glyph].next;
	}
}

function decompose(s: KbScratch, config: KbShapeConfig): void {
	const storage = s.storage;
	const font = config.font;

	let glyph = storage.glyphs[KB_GLYPH_SENTINEL].next;
	while (glyph != KB_GLYPH_SENTINEL) {
		if (kbDecompositionSize(storage.glyphs[glyph].decomposition) != 0) {
			let prevAnchor = storage.glyphs[glyph].prev;

			let stack: KbGlyph[] = [storage.glyphs[glyph]];

			kbFreeGlyph(s, glyph);

			while (stack.length > 0) {
				const toDecompose = stack.pop() as KbGlyph;
				let decomposition: uint64 = 0;
				let decompositionSize: uint32 = 0;
				let anyUnsupported = false;
				let decomposed: KbGlyph[] = [];

				if ((toDecompose.flags & KB_GLYPH_FLAG_DO_NOT_DECOMPOSE) == 0) {
					decomposition = toDecompose.decomposition;
					decompositionSize = kbDecompositionSize(decomposition);

					if (decompositionSize == 2 || toDecompose.id == 0) {
						for (let index: uint32 = 0; index < decompositionSize; index++) {
							const decompositionGlyph = kbCodepointToGlyph(font,
								kbDecompositionCodepoint(decomposition, index) as int32,
								toDecompose.configPlusOne, toDecompose.userIdOrCodepointIndex);
							if (decompositionGlyph.id == 0) { anyUnsupported = true; }
							decomposed.push(decompositionGlyph);
						}
					} else {
						anyUnsupported = true;
					}
				}

				if (anyUnsupported || decompositionSize == 0) {
					prevAnchor = kbInsertGlyphAfter(storage, prevAnchor, toDecompose);
				} else {
					if (decompositionSize > 2) {
						throw kbBoundsFail("decomposition of more than two codepoints", decompositionSize as int64);
					}
					if ((decomposition & KB_UNICODE_DECOMPOSITION_DO_NOT_RECURSE0) != 0) {
						decomposed[0].flags |= KB_GLYPH_FLAG_DO_NOT_DECOMPOSE;
					}
					if ((decomposition & KB_UNICODE_DECOMPOSITION_DO_NOT_RECURSE1) != 0) {
						decomposed[1].flags |= KB_GLYPH_FLAG_DO_NOT_DECOMPOSE;
					}
					// The C keeps a stack, so the last codepoint goes in first.
					for (let index: uint32 = 0; index < decompositionSize; index++) {
						stack.push(decomposed[(decompositionSize - 1 - index) as int32]);
					}
				}
			}

			glyph = prevAnchor;
		}
		glyph = storage.glyphs[glyph].next;
	}
}

function recompose(s: KbScratch, config: KbShapeConfig): void {
	const storage = s.storage;
	const font = config.font;

	let lastBase: int32 = NO_GLYPH;
	let lastBaseParents: KbParent[] = [];
	let preSlashDecimalDigitCount: int64 = 0;
	let preSlashGlyph: int32 = NO_GLYPH;
	let digitGlyph: int32 = NO_GLYPH;
	let decimalDigitCount: int64 = 0;
	let inFraction = false;

	let beforeFractionSlashGlyphFlags: uint32 = KB_GLYPH_FLAG_NUMR | KB_GLYPH_FLAG_FRAC;
	let afterFractionSlashGlyphFlags: uint32 = KB_GLYPH_FLAG_DNOM | KB_GLYPH_FLAG_FRAC;
	if (config.shaper == KB_SHAPER_ARABIC || config.shaper == KB_SHAPER_HEBREW) {
		const swap = beforeFractionSlashGlyphFlags;
		beforeFractionSlashGlyphFlags = afterFractionSlashGlyphFlags;
		afterFractionSlashGlyphFlags = swap;
	}

	const shouldFlip = s.runDirection == KB_DIRECTION_RTL;

	let glyph = storage.glyphs[KB_GLYPH_SENTINEL].next;
	while (glyph != KB_GLYPH_SENTINEL) {
		storage.glyphs[glyph].uid = kbNextGlyphUid(s);

		if (shouldFlip && (storage.glyphs[glyph].unicodeFlags & KB_UNICODE_FLAG_MIRRORED) != 0) {
			const matchingBracketCodepoint = kbMirrorCodepoint(storage.glyphs[glyph].codepoint);
			const matchingBracket = kbCodepointToGlyph(font, matchingBracketCodepoint as int32,
				storage.glyphs[glyph].configPlusOne, 0);
			if (matchingBracket.id != 0) {
				kbSetGlyphPreserveLinksAndUserId(storage, glyph, matchingBracket);
			}
		}

		let doubleRecompositionCount = lastBaseParents.length as int64;

		if (storage.glyphs[glyph].combiningClass == 0) {
			lastBase = glyph;
			if (config.shaper != KB_SHAPER_USE ||
				storage.glyphs[glyph].syllabicClass != KB_INDIC_SYLLABIC_CLASS_MATRA) {
				lastBaseParents = kbLoadParents(storage.glyphs[glyph]);
				if ((lastBaseParents.length as uint32) > KB_MAXIMUM_RECOMPOSITION_PARENTS) {
					throw kbBoundsFail("more recomposition parents than the C buffer holds",
						lastBaseParents.length as int64);
				}
			} else {
				lastBaseParents = [];
			}

			doubleRecompositionCount = 0;
		}

		let recomposed = false;

		for (let parentIndex: int64 = 0; parentIndex < doubleRecompositionCount; parentIndex++) {
			const parent = lastBaseParents[parentIndex as int32];

			if (storage.glyphs[glyph].codepoint == parent.codepoint1) {
				const parentId = kbCodepointToGlyphId(font, parent.codepoint as int32) as uint16;

				if (parentId != 0) {
					let parentGlyph = kbCodepointToGlyph(font, parent.codepoint as int32, 0, 0);
					parentGlyph.uid = storage.glyphs[lastBase].uid;
					parentGlyph.userIdOrCodepointIndex = storage.glyphs[lastBase].userIdOrCodepointIndex;
					parentGlyph.configPlusOne = storage.glyphs[lastBase].configPlusOne;

					const next = storage.glyphs[glyph].next;
					kbFreeGlyph(s, glyph);
					glyph = next;

					recomposed = true;
					kbSetGlyphPreserveLinksAndUserId(storage, lastBase, parentGlyph);

					lastBaseParents = kbLoadParents(storage.glyphs[lastBase]);

					break;
				} else {
					// This glyph is never good. Forget it.
					const lastIndex = lastBaseParents.length - 1;
					lastBaseParents[parentIndex as int32] = lastBaseParents[lastIndex];
					lastBaseParents.pop();

					doubleRecompositionCount -= 1;
					parentIndex -= 1;
				}
			}
		}

		if ((storage.glyphs[glyph].unicodeFlags & KB_UNICODE_FLAG_DECIMAL_DIGIT) != 0) {
			if (inFraction) {
				storage.glyphs[glyph].flags |= afterFractionSlashGlyphFlags;
				for (let digitIndex: int64 = 0; digitIndex < preSlashDecimalDigitCount; digitIndex++) {
					storage.glyphs[preSlashGlyph].flags |= beforeFractionSlashGlyphFlags;
					preSlashGlyph = storage.glyphs[preSlashGlyph].next;
				}
				preSlashDecimalDigitCount = 0;
			}
			if (decimalDigitCount == 0) {
				digitGlyph = glyph;
			}
			decimalDigitCount += 1;
		} else if (storage.glyphs[glyph].codepoint == 0x2044 && (!inFraction || decimalDigitCount != 0)) {
			storage.glyphs[glyph].flags |= KB_GLYPH_FLAG_FRAC;
			preSlashDecimalDigitCount = decimalDigitCount;
			preSlashGlyph = digitGlyph;
			inFraction = decimalDigitCount != 0;
			decimalDigitCount = 0;
		} else {
			inFraction = false;
		}

		if (recomposed) {
			glyph = storage.glyphs[glyph].prev;
		}
		glyph = storage.glyphs[glyph].next;
	}
}

function reorderMarks(s: KbScratch): void {
	const storage = s.storage;
	let glyph = storage.glyphs[KB_GLYPH_SENTINEL].next;
	while (glyph != KB_GLYPH_SENTINEL) {
		const combiningClass = storage.glyphs[glyph].combiningClass;

		if (combiningClass != 0) {
			storage.glyphs[glyph].markOrdering = combiningClass;

			let sequenceGlyph = storage.glyphs[glyph].next;
			while (sequenceGlyph != KB_GLYPH_SENTINEL) {
				const sequenceGlyphCombiningClass = storage.glyphs[sequenceGlyph].combiningClass;
				if (sequenceGlyphCombiningClass != 0) {
					storage.glyphs[sequenceGlyph].markOrdering = sequenceGlyphCombiningClass;
				} else {
					break;
				}
				sequenceGlyph = storage.glyphs[sequenceGlyph].next;
			}

			let afterSequence = sequenceGlyph;
			if (afterSequence != KB_GLYPH_SENTINEL) {
				afterSequence = storage.glyphs[afterSequence].next;
			}

			kbDllistSort(storage, glyph, sequenceGlyph, false);

			glyph = afterSequence;
		} else {
			glyph = storage.glyphs[glyph].next;
		}
	}
}

function reorderArabicMarks(s: KbScratch): void {
	const storage = s.storage;
	let glyph = storage.glyphs[KB_GLYPH_SENTINEL].next;
	while (glyph != KB_GLYPH_SENTINEL) {
		let next = storage.glyphs[glyph].next;

		if (storage.glyphs[glyph].combiningClass != 0) {
			let mcm220SequenceState = KB_MCM_SEQUENCE_STATE_NONE;
			let mcm230SequenceState = KB_MCM_SEQUENCE_STATE_NONE;

			let sequenceGlyph = glyph;
			while (sequenceGlyph != KB_GLYPH_SENTINEL) {
				const sequenceGlyphCombiningClass = storage.glyphs[sequenceGlyph].combiningClass as int32;
				const sequenceGlyphFlags = storage.glyphs[sequenceGlyph].unicodeFlags;

				let markOrdering: uint8 = 3;

				if (sequenceGlyphCombiningClass == REMAPPED_CCC_33) {
					markOrdering = 2;
				} else if (sequenceGlyphCombiningClass == 220) {
					if ((sequenceGlyphFlags & KB_UNICODE_FLAG_MODIFIER_COMBINING_MARK) != 0) {
						if (mcm220SequenceState != KB_MCM_SEQUENCE_STATE_OUT) {
							mcm220SequenceState = KB_MCM_SEQUENCE_STATE_IN;
						}
					} else {
						mcm220SequenceState = KB_MCM_SEQUENCE_STATE_OUT;
					}

					if (mcm220SequenceState == KB_MCM_SEQUENCE_STATE_IN) {
						markOrdering = 0;
					}

					mcm230SequenceState = KB_MCM_SEQUENCE_STATE_NONE;
				} else if (sequenceGlyphCombiningClass == 230) {
					if ((sequenceGlyphFlags & KB_UNICODE_FLAG_MODIFIER_COMBINING_MARK) != 0) {
						if (mcm230SequenceState != KB_MCM_SEQUENCE_STATE_OUT) {
							mcm230SequenceState = KB_MCM_SEQUENCE_STATE_IN;
						}
					} else {
						mcm230SequenceState = KB_MCM_SEQUENCE_STATE_OUT;
					}

					if (mcm230SequenceState == KB_MCM_SEQUENCE_STATE_IN) {
						markOrdering = 1;
					}
				} else if (sequenceGlyphCombiningClass != 0) {
					mcm220SequenceState = KB_MCM_SEQUENCE_STATE_NONE;
					mcm230SequenceState = KB_MCM_SEQUENCE_STATE_NONE;
				} else {
					break;
				}

				storage.glyphs[sequenceGlyph].markOrdering = markOrdering;
				sequenceGlyph = storage.glyphs[sequenceGlyph].next;
			}

			kbDllistSort(storage, glyph, sequenceGlyph, false);

			next = sequenceGlyph;
		}

		glyph = next;
	}
}

function isAboveBaseThaiLaoMark(codepoint: uint32): boolean {
	return codepoint == 0xE31 || (codepoint >= 0xE34 && codepoint <= 0xE37) || codepoint == 0xE3B ||
		(codepoint >= 0xE47 && codepoint <= 0xE4E) ||
		codepoint == 0xEB1 || (codepoint >= 0xEB4 && codepoint <= 0xEB7) || codepoint == 0xEBB ||
		(codepoint >= 0xEC7 && codepoint <= 0xECE);
}

function decomposeSaraAms(s: KbScratch, config: KbShapeConfig): void {
	const storage = s.storage;
	let aboveBaseGlyph: int32 = NO_GLYPH;

	let glyph = storage.glyphs[KB_GLYPH_SENTINEL].next;
	while (glyph != KB_GLYPH_SENTINEL) {
		const codepoint = storage.glyphs[glyph].codepoint;

		if (codepoint == 0xE33 || codepoint == 0xEB3) {
			if (aboveBaseGlyph == NO_GLYPH) {
				aboveBaseGlyph = glyph;
			}

			const newGlyph = kbInsertGlyphBefore(storage, aboveBaseGlyph, config.nikhahit);

			const glyphConfig = storage.glyphs[glyph].configPlusOne;

			storage.glyphs[newGlyph].userIdOrCodepointIndex = storage.glyphs[glyph].userIdOrCodepointIndex;
			storage.glyphs[newGlyph].configPlusOne = glyphConfig;

			kbSetGlyphPreserveLinksAndUserId(storage, glyph, config.saraAa);
			storage.glyphs[glyph].configPlusOne = glyphConfig;

			aboveBaseGlyph = NO_GLYPH;
		} else if (isAboveBaseThaiLaoMark(codepoint)) {
			if (aboveBaseGlyph == NO_GLYPH) {
				aboveBaseGlyph = glyph;
			}
		} else {
			aboveBaseGlyph = NO_GLYPH;
		}
		glyph = storage.glyphs[glyph].next;
	}
}

export function kbNormalize(s: KbScratch, config: KbShapeConfig): void {
	decompose(s, config);
	recompose(s, config);
	reorderMarks(s);

	if (config.script == KB_SCRIPT_ARABIC) {
		reorderArabicMarks(s);
	} else if (config.script == KB_SCRIPT_THAI || config.script == KB_SCRIPT_LAO) {
		decomposeSaraAms(s, config);
	}
}

struct KbHangulInfo {
	syllableType: uint32;
	composable: uint32;
}

// The C tests (Codepoint == 0xAC00) && (Codepoint <= 0xD7A3), so only the first precomposed syllable
// is classified; every other precomposed syllable is NONE.
function hangulSyllableInfo(codepoint: uint32): KbHangulInfo {
	let result: KbHangulInfo = { syllableType: 0, composable: 0 };

	if (codepoint >= 0x1100 && codepoint <= 0x115F) {
		result.syllableType = KB_HANGUL_SYLLABLE_TYPE_L;
		result.composable = codepoint < 0x1113 ? 1 : 0;
	} else if (codepoint >= 0x1160 && codepoint <= 0x11A7) {
		result.syllableType = KB_HANGUL_SYLLABLE_TYPE_V;
		result.composable = (codepoint >= 0x1161 && codepoint <= 0x1175) ? 1 : 0;
	} else if (codepoint >= 0x11A8 && codepoint <= 0x11FF) {
		result.syllableType = KB_HANGUL_SYLLABLE_TYPE_T;
		result.composable = codepoint < 0x11C3 ? 1 : 0;
	} else if (codepoint >= 0xA960 && codepoint <= 0xA97C) {
		result.syllableType = KB_HANGUL_SYLLABLE_TYPE_L;
	} else if (codepoint == 0xAC00 && codepoint <= 0xD7A3) {
		result.syllableType = KB_HANGUL_SYLLABLE_TYPE_LVT;

		if ((codepoint - 0xAC00) % 28 == 0) {
			result.syllableType = KB_HANGUL_SYLLABLE_TYPE_LV;
		}
	} else if (codepoint >= 0xD7B0 && codepoint <= 0xD7C6) {
		result.syllableType = KB_HANGUL_SYLLABLE_TYPE_V;
	} else if (codepoint >= 0xD7CB && codepoint <= 0xD7FB) {
		result.syllableType = KB_HANGUL_SYLLABLE_TYPE_T;
	}
	return result;
}

export function kbNormalizeHangul(s: KbScratch, config: KbShapeConfig): void {
	const storage = s.storage;
	const font = config.font;

	let glyph = storage.glyphs[KB_GLYPH_SENTINEL].next;
	while (glyph != KB_GLYPH_SENTINEL) {
		let next = storage.glyphs[glyph].next;
		const userId = storage.glyphs[glyph].userIdOrCodepointIndex;
		const glyphConfig = storage.glyphs[glyph].configPlusOne;

		let l: int64 = 0;
		let v: int64 = 0;
		let t: int64 = 0;
		let lvtGlyphs: KbGlyph[] = [];

		const lInfo = hangulSyllableInfo(storage.glyphs[glyph].codepoint);
		if (lInfo.syllableType >= KB_HANGUL_SYLLABLE_TYPE_LV) {
			const sIndex = (storage.glyphs[glyph].codepoint - 0xAC00) as int64;

			l = 0x1100 + sIndex / 588;
			v = 0x1161 + (sIndex % 588) / 28;

			const tIndex = sIndex % 28;
			if (tIndex != 0) {
				t = 0x11A7 + tIndex;
			}
		} else if (lInfo.syllableType == KB_HANGUL_SYLLABLE_TYPE_L) {
			l = storage.glyphs[glyph].codepoint as int64;
		}

		if (l != 0) {
			let vInfo: KbHangulInfo = { syllableType: 0, composable: 0 };

			if (v == 0 && next != KB_GLYPH_SENTINEL) {
				const vCodepoint = storage.glyphs[next].codepoint;
				const maybeVInfo = hangulSyllableInfo(vCodepoint);

				if (maybeVInfo.syllableType == KB_HANGUL_SYLLABLE_TYPE_V) {
					v = vCodepoint as int64;
					vInfo = maybeVInfo;

					next = storage.glyphs[next].next;
				}
			}

			if (v != 0) {
				let tInfo: KbHangulInfo = { syllableType: 0, composable: 0 };

				if (t == 0 && next != KB_GLYPH_SENTINEL) {
					const tCodepoint = storage.glyphs[next].codepoint;
					const maybeTInfo = hangulSyllableInfo(tCodepoint);

					if (maybeTInfo.syllableType == KB_HANGUL_SYLLABLE_TYPE_T) {
						t = tCodepoint as int64;
						tInfo = maybeTInfo;

						next = storage.glyphs[next].next;
					}
				}

				if (next != KB_GLYPH_SENTINEL) {
					const toneMarkCodepoint = storage.glyphs[next].codepoint;

					if (toneMarkCodepoint >= 0x302E && toneMarkCodepoint <= 0x302F) {
						lvtGlyphs.push(kbCodepointToGlyph(font, toneMarkCodepoint as int32, glyphConfig, userId));

						next = storage.glyphs[next].next;
					}
				}

				if ((lInfo.composable & vInfo.composable & tInfo.composable) != 0) {
					const lvtCodepoint = 0xAC00 + (l - 0x1100) * 588 + (v - 0x1161) * 28 + (t - 0x11A7);

					const lvtGlyph = kbCodepointToGlyph(font, lvtCodepoint as int32, glyphConfig, userId);
					if (lvtGlyph.id != 0) {
						lvtGlyphs.push(lvtGlyph);
					}
				}

				if (lvtGlyphs.length == 0) {
					let lvGlyph = kbZeroGlyph();
					if ((lInfo.composable & vInfo.composable) != 0) {
						const lvCodepoint = 0xAC00 + (l - 0x1100) * 588 + (v - 0x1161) * 28;

						lvGlyph = kbCodepointToGlyph(font, lvCodepoint as int32, glyphConfig, userId);
					}

					if (lvGlyph.id != 0) {
						lvtGlyphs.push(lvGlyph);
					} else {
						let lGlyph = kbCodepointToGlyph(font, l as int32, glyphConfig, userId);
						lGlyph.flags |= KB_GLYPH_FLAG_LJMO;

						let vGlyph = kbCodepointToGlyph(font, v as int32, glyphConfig, userId);
						vGlyph.flags |= KB_GLYPH_FLAG_VJMO;

						lvtGlyphs.push(lGlyph);
						lvtGlyphs.push(vGlyph);
					}

					if (t != 0) {
						let tGlyph = kbCodepointToGlyph(font, t as int32, glyphConfig, userId);
						tGlyph.flags |= KB_GLYPH_FLAG_TJMO;

						lvtGlyphs.push(tGlyph);
					}
				}
			}
		}

		if (lvtGlyphs.length == 0) {
			lvtGlyphs.push(kbCodepointToGlyph(font, storage.glyphs[glyph].codepoint as int32, glyphConfig, userId));
		}

		{
			const lastConsumed = storage.glyphs[next].prev;
			const before = storage.glyphs[glyph].prev;

			// Remove the sub-list from the main list.
			storage.glyphs[before].next = storage.glyphs[lastConsumed].next;
			storage.glyphs[storage.glyphs[lastConsumed].next].prev = before;

			// Send it to the front of the free list.
			storage.glyphs[glyph].prev = KB_FREE_GLYPH_SENTINEL;
			storage.glyphs[lastConsumed].next = storage.glyphs[KB_FREE_GLYPH_SENTINEL].next;
			storage.glyphs[storage.glyphs[glyph].prev].next = glyph;
			storage.glyphs[storage.glyphs[lastConsumed].next].prev = lastConsumed;

			for (let lvtIndex = 0; lvtIndex < lvtGlyphs.length; lvtIndex++) {
				kbInsertGlyphBefore(storage, next, lvtGlyphs[lvtIndex]);
			}
		}

		glyph = next;
	}
}

export function kbFlagJoiningLetters(s: KbScratch): void {
	const storage = s.storage;

	const joinedAfter: uint64 = ((1 as uint64) << (KB_UNICODE_JOINING_TYPE_RIGHT as uint64)) |
		((1 as uint64) << (KB_UNICODE_JOINING_TYPE_DUAL as uint64)) |
		((1 as uint64) << (KB_UNICODE_JOINING_TYPE_FORCE as uint64));
	const joiningTypesMatchLookup: uint64 =
		(joinedAfter << (8 * (KB_UNICODE_JOINING_TYPE_LEFT as uint64))) |
		(joinedAfter << (8 * (KB_UNICODE_JOINING_TYPE_DUAL as uint64))) |
		(joinedAfter << (8 * (KB_UNICODE_JOINING_TYPE_FORCE as uint64)));

	const joiningFeatureTransition: uint64 =
		((KB_JOINING_FEATURE_INIT as uint64) << (8 * (KB_JOINING_FEATURE_ISOL as uint64))) |
		((KB_JOINING_FEATURE_MEDI as uint64) << (8 * (KB_JOINING_FEATURE_FINA as uint64))) |
		((KB_JOINING_FEATURE_MEDI as uint64) << (8 * (KB_JOINING_FEATURE_MEDI as uint64))) |
		((KB_JOINING_FEATURE_MED2 as uint64) << (8 * (KB_JOINING_FEATURE_MED2 as uint64)));

	// The C starts from a zeroed glyph that is not in the list: it never matches and takes no writes.
	let previous: int32 = NO_GLYPH;

	let glyph = storage.glyphs[KB_GLYPH_SENTINEL].next;
	while (glyph != KB_GLYPH_SENTINEL) {
		if (storage.glyphs[glyph].joiningType != KB_UNICODE_JOINING_TYPE_TRANSPARENT) {
			const previousJoiningType = previous == NO_GLYPH ? 0 : storage.glyphs[previous].joiningType as int32;

			storage.glyphs[glyph].joiningFeature =
				(previousJoiningType == 0 ? KB_JOINING_FEATURE_INIT : KB_JOINING_FEATURE_FINA) as uint8;

			const matchBit = (storage.glyphs[glyph].joiningType as uint64) + 8 * (previousJoiningType as uint64);
			if (((joiningTypesMatchLookup >> matchBit) & 1) != 0) {
				const previousFeature = (joiningFeatureTransition >>
					(8 * (storage.glyphs[previous].joiningFeature as uint64))) & 0xFF;
				storage.glyphs[previous].joiningFeature = previousFeature as uint8;
				storage.glyphs[previous].flags = (storage.glyphs[previous].flags & ~KB_JOINING_FEATURE_MASK) |
					joiningFeatureToGlyphFlag(previousFeature as int32);

				storage.glyphs[glyph].joiningFeature = KB_JOINING_FEATURE_FINA as uint8;
			} else {
				storage.glyphs[glyph].joiningFeature = KB_JOINING_FEATURE_ISOL as uint8;
			}

			if (storage.glyphs[glyph].joiningFeature != 0) {
				storage.glyphs[glyph].flags = (storage.glyphs[glyph].flags & ~KB_JOINING_FEATURE_MASK) |
					joiningFeatureToGlyphFlag(storage.glyphs[glyph].joiningFeature as int32);
			}

			previous = glyph;
		}
		glyph = storage.glyphs[glyph].next;
	}
}

// KBTS__JOINING_FEATURE_TO_GLYPH_FLAG is (1 << (Feature - 1)); the transition table never yields feature
// 0, which would be a negative shift in the C.
function joiningFeatureToGlyphFlag(feature: int32): uint32 {
	if (feature < 1) {
		throw kbBoundsFail("joining feature 0 has no glyph flag", feature as int64);
	}
	return ((1 as uint32) << ((feature - 1) as uint32));
}
