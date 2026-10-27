import {
	KbUnpackedLookup,
	kbCoverGlyph,
	kbGetLigatureAttach,
	kbGetLigatureAttachAnchor,
	kbGetLookup,
	kbGetMarkInfo,
	kbGlyphClassFromTable,
	kbLookupBeginsWithCoverage,
	kbUnpackLookup,
} from "./access";
import {
	KB_BLOB_TABLE_ID_GDEF,
	kbBlobTableData,
	kbBoundsFail,
	kbU16,
	kbU32,
} from "./blob";
import {
	KB_GLYPH_CLASS_BASE,
	KB_GLYPH_CLASS_COMPONENT,
	KB_GLYPH_CLASS_LIGATURE,
	KB_GLYPH_CLASS_MARK,
	KB_GLYPH_FLAG_CURSIVE,
	KB_GLYPH_FLAG_FIRST_IN_MULTIPLE_SUBSTITUTION,
	KB_GLYPH_FLAG_LIGATURE,
	KB_GLYPH_FLAG_MULTIPLE_SUBSTITUTION,
	KB_GLYPH_FLAG_NO_BREAK,
	KB_GLYPH_FLAG_USED_IN_GPOS,
	KB_GLYPH_SENTINEL,
	KB_UNICODE_FLAG_DEFAULT_IGNORABLE,
} from "./glyph";
import {
	KB_LOOKUP_FLAG_RIGHT_TO_LEFT,
	kbDoSequenceLookup,
	kbGlyphPassesLookupFilter,
	kbNextGlyph,
	kbSkipFlagsGposRegular,
	kbSkipFlagsGposSequence,
	kbSkipGlyph,
} from "./match";
import { KbResolvedValueRecord, kbResolveAnchorXy, kbResolveValueRecord } from "./resolve";
import {
	KB_SHAPER_ARABIC,
	KB_SHAPER_DEFAULT,
	KB_SHAPER_HEBREW,
	KbScratch,
	kbGlyphIncludedInLookupSubtable,
	kbSetLookupOnePastLastGlyph,
} from "./scratch";

const CURSIVE_FLAG_START: uint8 = 1 << 0;
const CURSIVE_FLAG_END: uint8 = 1 << 1;

class KbAdjustOutcome {
	onePastLastGlyphIndex: int64;
	onePastLastGlyph: int32;
	constructor(index: int64, glyph: int32) {
		this.onePastLastGlyphIndex = index;
		this.onePastLastGlyph = glyph;
	}
}

function popCount16(value: int32): int32 {
	let count: int32 = 0;
	let rest = value;
	while (rest != 0) {
		count += rest & 1;
		rest = rest >> 1;
	}
	return count;
}

function shaperRtl(shaper: int32): boolean {
	return shaper == KB_SHAPER_ARABIC || shaper == KB_SHAPER_HEBREW;
}

function shaperClearsMarkAdvancesInPostGposFixup(shaper: int32): boolean {
	return shaper == KB_SHAPER_ARABIC || shaper == KB_SHAPER_DEFAULT || shaper == KB_SHAPER_HEBREW;
}

function applyValueRecord(s: KbScratch, glyph: int32, record: KbResolvedValueRecord): void {
	s.storage.glyphs[glyph].offsetX += record.placementX;
	s.storage.glyphs[glyph].offsetY += record.placementY;
	s.storage.glyphs[glyph].advanceX += record.advanceX;
	s.storage.glyphs[glyph].advanceY += record.advanceY;
}

function attachGlyph(s: KbScratch, parent: int32, child: int32, x: int32, y: int32): void {
	const deltaOffsetX = x - s.storage.glyphs[child].offsetX;
	const deltaOffsetY = y - s.storage.glyphs[child].offsetY;

	s.storage.glyphs[child].offsetX = x;
	s.storage.glyphs[child].offsetY = y;
	s.storage.glyphs[child].flags |= KB_GLYPH_FLAG_USED_IN_GPOS | KB_GLYPH_FLAG_NO_BREAK;
	s.storage.glyphs[child].attachGlyph = parent;

	s.storage.glyphs[parent].flags |= KB_GLYPH_FLAG_USED_IN_GPOS;

	let middle = s.storage.glyphs[parent].next;
	while (middle != child) {
		s.storage.glyphs[middle].flags |= KB_GLYPH_FLAG_NO_BREAK;
		middle = s.storage.glyphs[middle].next;
	}

	let post = s.storage.glyphs[child].next;
	while (post != KB_GLYPH_SENTINEL) {
		if (s.storage.glyphs[post].attachGlyph == child) {
			s.storage.glyphs[post].offsetX += deltaOffsetX;
			s.storage.glyphs[post].offsetY += deltaOffsetY;
		}
		post = s.storage.glyphs[post].next;
	}
}

function singleAdjustment(s: KbScratch, base: int64, coverIndex: int64, glyph: int32): boolean {
	const font = s.font;
	const blobArr = font.blob;
	const m: Span<uint8> = blobArr[0..blobArr.length];
	const valueFormat = m.kbU16(base + 4);
	const format = m.kbU16(base);

	let record: KbResolvedValueRecord = { placementX: 0, placementY: 0, advanceX: 0, advanceY: 0 };
	if (format == 1) {
		record = kbResolveValueRecord(s, base, valueFormat, base + 6);
	} else if (format == 2) {
		const recordSize = popCount16(valueFormat) as int64;
		record = kbResolveValueRecord(s, base, valueFormat, base + 8 + recordSize * 2 * coverIndex);
	} else {
		throw kbBoundsFail(`unhandled single adjustment format ${format}`, base);
	}

	applyValueRecord(s, glyph, record);
	s.storage.glyphs[glyph].flags |= KB_GLYPH_FLAG_USED_IN_GPOS;
	return true;
}

function pairAdjustment(
	s: KbScratch,
	lookup: KbUnpackedLookup,
	base: int64,
	coverIndex: int64,
	glyph: int32,
	regularSkipFlags: uint32,
	skipUnicodeFlags: uint32,
	outcome: KbAdjustOutcome,
): boolean {
	const font = s.font;
	const blobArr = font.blob;
	const m: Span<uint8> = blobArr[0..blobArr.length];
	const nextGlyph = kbNextGlyph(s, lookup, s.storage.glyphs[glyph].next, regularSkipFlags,
		skipUnicodeFlags, false);
	if (nextGlyph == KB_GLYPH_SENTINEL) { return false; }

	const nextGlyphId = s.storage.glyphs[nextGlyph].id as int32;
	const valueFormat1 = m.kbU16(base + 4);
	const valueFormat2 = m.kbU16(base + 6);
	const size1 = popCount16(valueFormat1) as int64;
	const size2 = popCount16(valueFormat2) as int64;
	const format = m.kbU16(base);

	let unpacked1: int64 = 0;
	let unpacked2: int64 = 0;
	let found = false;

	if (format == 1) {
		const set = base + m.kbU16(base + 10 + coverIndex * 2);
		const pairRecordSize = size1 + size2 + 1;
		let pairCount = m.kbU16(set) as int64;
		let record = set + 2;

		while (pairCount > 1) {
			const halfCount = pairCount / 2;
			const onePastProbe = record + halfCount * pairRecordSize * 2;
			const probe = onePastProbe - pairRecordSize * 2;
			if (m.kbU16(probe) < nextGlyphId) {
				record = onePastProbe;
			}
			pairCount -= halfCount;
		}

		if (m.kbU16(record) == nextGlyphId) {
			unpacked1 = record + 2;
			unpacked2 = unpacked1 + size1 * 2;
			found = true;
		}
	} else if (format == 2) {
		const classDef1 = base + m.kbU16(base + 8);
		const classDef2 = base + m.kbU16(base + 10);
		const class1Count = m.kbU16(base + 12);
		const class2Count = m.kbU16(base + 14);
		const pairRecordSize = size1 + size2;

		const class1 = kbGlyphClassFromTable(m, classDef1, s.storage.glyphs[glyph].id as int64);
		const class2 = kbGlyphClassFromTable(m, classDef2, nextGlyphId as int64);

		if (class1.classValue < class1Count && class2.classValue < class2Count) {
			const record = base + 16 + ((class1.classValue as int64) * pairRecordSize * (class2Count as int64) +
				(class2.classValue as int64) * pairRecordSize) * 2;
			unpacked1 = record;
			unpacked2 = record + size1 * 2;
			found = true;
		}
	} else {
		throw kbBoundsFail(`unhandled pair adjustment format ${format}`, base);
	}

	if (!found) { return false; }

	const valueRecord1 = kbResolveValueRecord(s, base, valueFormat1, unpacked1);
	applyValueRecord(s, glyph, valueRecord1);

	s.storage.glyphs[glyph].flags |= KB_GLYPH_FLAG_USED_IN_GPOS;
	s.storage.glyphs[nextGlyph].flags |= KB_GLYPH_FLAG_USED_IN_GPOS;

	outcome.onePastLastGlyph = s.storage.glyphs[glyph].next;

	if (valueFormat2 != 0) {
		const valueRecord2 = kbResolveValueRecord(s, base, valueFormat2, unpacked2);
		applyValueRecord(s, nextGlyph, valueRecord2);
		outcome.onePastLastGlyph = s.storage.glyphs[nextGlyph].next;
	}
	return true;
}

function cursiveAdjustment(
	s: KbScratch,
	lookup: KbUnpackedLookup,
	base: int64,
	coverIndex: int64,
	glyph: int32,
	regularSkipFlags: uint32,
	skipUnicodeFlags: uint32,
): boolean {
	const font = s.font;
	const blobArr = font.blob;
	const m: Span<uint8> = blobArr[0..blobArr.length];
	const coverage = base + m.kbU16(base + 2);
	const entryExits = base + 6;

	const prev = kbNextGlyph(s, lookup, s.storage.glyphs[glyph].prev, regularSkipFlags,
		skipUnicodeFlags, true);
	if (prev == KB_GLYPH_SENTINEL) { return false; }

	const prevCover = kbCoverGlyph(m, coverage, s.storage.glyphs[prev].id as int32);
	if (!prevCover.valid) { return false; }

	const prevExitOffset = m.kbU16(entryExits + prevCover.index * 4 + 2);
	const entryOffset = m.kbU16(entryExits + coverIndex * 4);
	if (prevExitOffset == 0 || entryOffset == 0) { return false; }

	const anchor0 = kbResolveAnchorXy(s, base + prevExitOffset);
	const anchor1 = kbResolveAnchorXy(s, base + entryOffset);

	let advance0X = s.storage.glyphs[prev].advanceX;
	let advance1X = s.storage.glyphs[glyph].advanceX;
	let offset0X = s.storage.glyphs[prev].offsetX;
	const offset0Y = s.storage.glyphs[prev].offsetY;
	let offset1X = s.storage.glyphs[glyph].offsetX;
	const offset1Y = s.storage.glyphs[glyph].offsetY;

	if (!shaperRtl(s.shaper)) {
		advance0X = offset0X + anchor0.x;
		const dx = -anchor1.x - offset1X;
		advance1X += dx;
		offset1X += dx;
	} else {
		const dx = -anchor0.x - offset0X;
		advance0X += dx;
		offset0X += dx;
		advance1X = offset1X + anchor1.x;
	}

	s.storage.glyphs[prev].advanceX = advance0X;
	s.storage.glyphs[prev].offsetX = offset0X;
	s.storage.glyphs[prev].flags |= KB_GLYPH_FLAG_CURSIVE | KB_GLYPH_FLAG_USED_IN_GPOS |
		KB_GLYPH_FLAG_NO_BREAK;
	s.storage.glyphs[prev].markOrdering = CURSIVE_FLAG_START;
	s.storage.glyphs[glyph].advanceX = advance1X;
	s.storage.glyphs[glyph].offsetX = offset1X;
	s.storage.glyphs[glyph].flags |= KB_GLYPH_FLAG_CURSIVE | KB_GLYPH_FLAG_USED_IN_GPOS;
	s.storage.glyphs[glyph].markOrdering = CURSIVE_FLAG_END;

	let between = s.storage.glyphs[prev].next;
	while (between != glyph) {
		s.storage.glyphs[between].flags |= KB_GLYPH_FLAG_NO_BREAK;
		s.storage.glyphs[between].markOrdering = 0;
		between = s.storage.glyphs[between].next;
	}

	let cursiveDy: int32 = 0;
	let cursiveGlyph = glyph;
	let backward = false;
	let adjustNearbyGlyphs = (s.storage.glyphs[glyph].flags & KB_GLYPH_FLAG_CURSIVE) != 0;

	if ((lookup.flags & KB_LOOKUP_FLAG_RIGHT_TO_LEFT) == 0) {
		const newOffset1Y = offset0Y + anchor0.y - anchor1.y;
		cursiveDy = newOffset1Y - offset1Y;
	} else {
		const newOffset0Y = offset1Y + anchor1.y - anchor0.y;
		cursiveDy = newOffset0Y - offset0Y;
		backward = true;
		cursiveGlyph = prev;
		adjustNearbyGlyphs = true;
	}

	s.storage.glyphs[cursiveGlyph].offsetY += cursiveDy;

	if (adjustNearbyGlyphs) {
		s.storage.glyphs[cursiveGlyph].markOrdering = 0;
		cursiveGlyph = backward ? s.storage.glyphs[cursiveGlyph].prev : s.storage.glyphs[cursiveGlyph].next;

		const stopFlag = backward ? CURSIVE_FLAG_END : CURSIVE_FLAG_START;

		while (cursiveGlyph != KB_GLYPH_SENTINEL) {
			const cursiveFlags = s.storage.glyphs[cursiveGlyph].markOrdering;

			if ((cursiveFlags & stopFlag) != 0) {
				break;
			} else if ((s.storage.glyphs[cursiveGlyph].flags & KB_GLYPH_FLAG_CURSIVE) != 0) {
				s.storage.glyphs[cursiveGlyph].offsetY += cursiveDy;
			} else if ((s.storage.glyphs[cursiveGlyph].classValue as int32) != KB_GLYPH_CLASS_MARK) {
				break;
			}

			cursiveGlyph = backward ? s.storage.glyphs[cursiveGlyph].prev : s.storage.glyphs[cursiveGlyph].next;
		}
	}
	return true;
}

function classBit(classValue: int32): int32 {
	if (classValue > 31) {
		throw kbBoundsFail("glyph class too large for the base class shift", classValue as int64);
	}
	return 1 << classValue;
}

function markToBaseAdjustment(
	s: KbScratch,
	lookup: KbUnpackedLookup,
	base: int64,
	coverIndex: int64,
	glyph: int32,
	regularSkipFlags: uint32,
	skipUnicodeFlags: uint32,
): boolean {
	const font = s.font;
	const blobArr = font.blob;
	const m: Span<uint8> = blobArr[0..blobArr.length];
	const countMarkAdvances = !shaperClearsMarkAdvancesInPostGposFixup(s.shaper);
	const baseCoverage = base + m.kbU16(base + 4);
	const markClassCount = m.kbU16(base + 6) as int64;
	let advanceSinceBaseX: int32 = 0;
	let advanceSinceBaseY: int32 = 0;
	const baseClasses: int32 = lookup.type == 6
		? 1 << KB_GLYPH_CLASS_MARK
		: 1 | (1 << KB_GLYPH_CLASS_BASE) | (1 << KB_GLYPH_CLASS_LIGATURE) | (1 << KB_GLYPH_CLASS_COMPONENT);
	let baseGlyph = KB_GLYPH_SENTINEL;

	let prevGlyph = s.storage.glyphs[glyph].prev;
	while (prevGlyph != KB_GLYPH_SENTINEL) {
		const prevClass = s.storage.glyphs[prevGlyph].classValue as int32;
		if (countMarkAdvances || prevClass != KB_GLYPH_CLASS_MARK) {
			advanceSinceBaseX += s.storage.glyphs[prevGlyph].advanceX;
			advanceSinceBaseY += s.storage.glyphs[prevGlyph].advanceY;
		}

		if (!kbSkipGlyph(s, prevGlyph, lookup, regularSkipFlags, skipUnicodeFlags)) {
			if ((classBit(prevClass) & baseClasses) != 0) {
				const prevFlags = s.storage.glyphs[prevGlyph].flags;
				const beforePrev = s.storage.glyphs[prevGlyph].prev;
				if (lookup.type == 4 &&
					(prevFlags & (KB_GLYPH_FLAG_FIRST_IN_MULTIPLE_SUBSTITUTION |
						KB_GLYPH_FLAG_MULTIPLE_SUBSTITUTION)) == KB_GLYPH_FLAG_MULTIPLE_SUBSTITUTION &&
					(s.storage.glyphs[beforePrev].classValue as int32) != KB_GLYPH_CLASS_MARK) {
					const baseCover = kbCoverGlyph(m, baseCoverage, s.storage.glyphs[prevGlyph].id as int32);
					if (baseCover.valid) {
						baseGlyph = prevGlyph;
						break;
					}
				} else {
					baseGlyph = prevGlyph;
					break;
				}
			} else if (lookup.type == 6) {
				break;
			}
		}
		prevGlyph = s.storage.glyphs[prevGlyph].prev;
	}

	if (baseGlyph == KB_GLYPH_SENTINEL) { return false; }

	const baseState = s.storage.glyphs[baseGlyph];
	const currentState = s.storage.glyphs[glyph];
	const ok = lookup.type == 4 ||
		(baseState.ligatureUid == currentState.ligatureUid &&
			baseState.ligatureComponentIndexPlusOne == currentState.ligatureComponentIndexPlusOne) ||
		((baseState.flags | currentState.flags) & KB_GLYPH_FLAG_LIGATURE) != 0;
	if (!ok) { return false; }

	const baseCover = kbCoverGlyph(m, baseCoverage, baseState.id as int32);
	if (!baseCover.valid) { return false; }

	const baseArray = base + m.kbU16(base + 10);
	const baseAnchorOffsets = baseArray + 2 + baseCover.index * markClassCount * 2;
	const markInfo = kbGetMarkInfo(m, base, m.kbU16(base + 8), coverIndex);

	const baseAnchorOffset = m.kbU16(baseAnchorOffsets + (m.kbU16(markInfo.record) as int64) * 2);
	if (baseAnchorOffset == 0) { return false; }

	const baseAnchor = kbResolveAnchorXy(s, baseArray + baseAnchorOffset);
	const markAnchor = kbResolveAnchorXy(s, markInfo.anchor);

	const newOffsetX = baseState.offsetX - advanceSinceBaseX + (baseAnchor.x - markAnchor.x);
	const newOffsetY = baseState.offsetY - advanceSinceBaseY + (baseAnchor.y - markAnchor.y);

	attachGlyph(s, baseGlyph, glyph, newOffsetX, newOffsetY);
	return true;
}

function markToLigatureAdjustment(
	s: KbScratch,
	lookup: KbUnpackedLookup,
	base: int64,
	coverIndex: int64,
	glyph: int32,
	regularSkipFlags: uint32,
	skipUnicodeFlags: uint32,
): boolean {
	const font = s.font;
	const blobArr = font.blob;
	const m: Span<uint8> = blobArr[0..blobArr.length];
	let advanceSinceBaseX: int32 = 0;
	let advanceSinceBaseY: int32 = 0;
	const baseClasses: int32 =
		1 | (1 << KB_GLYPH_CLASS_BASE) | (1 << KB_GLYPH_CLASS_LIGATURE) | (1 << KB_GLYPH_CLASS_COMPONENT);
	let ligatureGlyph = KB_GLYPH_SENTINEL;

	let prevGlyph = s.storage.glyphs[glyph].prev;
	while (prevGlyph != KB_GLYPH_SENTINEL) {
		advanceSinceBaseX += s.storage.glyphs[prevGlyph].advanceX;
		advanceSinceBaseY += s.storage.glyphs[prevGlyph].advanceY;

		if (!kbSkipGlyph(s, prevGlyph, lookup, regularSkipFlags, skipUnicodeFlags) &&
			(classBit(s.storage.glyphs[prevGlyph].classValue as int32) & baseClasses) != 0) {
			ligatureGlyph = prevGlyph;
			break;
		}
		prevGlyph = s.storage.glyphs[prevGlyph].prev;
	}

	if (ligatureGlyph == KB_GLYPH_SENTINEL) { return false; }

	const ligatureArray = base + m.kbU16(base + 10);
	const ligatureCover = kbCoverGlyph(m, base + m.kbU16(base + 4),
		s.storage.glyphs[ligatureGlyph].id as int32);
	if (!ligatureCover.valid) { return false; }

	const ligatureAttach = kbGetLigatureAttach(m, ligatureArray, ligatureCover.index);
	const markInfo = kbGetMarkInfo(m, base, m.kbU16(base + 8), coverIndex);
	const attachCount = m.kbU16(ligatureAttach) as int64;
	let componentIndexPlusOne = s.storage.glyphs[glyph].ligatureComponentIndexPlusOne as int64;

	if (s.storage.glyphs[glyph].ligatureUid != s.storage.glyphs[ligatureGlyph].uid) {
		componentIndexPlusOne = attachCount;
	}

	if (componentIndexPlusOne > attachCount) { return false; }

	let anchorIndex = componentIndexPlusOne;
	if (anchorIndex != 0) {
		anchorIndex -= 1;
	} else {
		if (attachCount == 0) {
			throw kbBoundsFail("mark to ligature attach with no components", ligatureAttach);
		}
		anchorIndex = attachCount - 1;
	}

	const ligatureAnchorAt = kbGetLigatureAttachAnchor(m, base, ligatureAttach,
		m.kbU16(markInfo.record), anchorIndex);
	if (ligatureAnchorAt == 0) {
		throw kbBoundsFail("mark to ligature anchor offset is null", ligatureAttach);
	}
	const ligatureAnchor = kbResolveAnchorXy(s, ligatureAnchorAt);
	const markAnchor = kbResolveAnchorXy(s, markInfo.anchor);

	const ligatureState = s.storage.glyphs[ligatureGlyph];
	const newOffsetX = ligatureState.offsetX - advanceSinceBaseX + (ligatureAnchor.x - markAnchor.x);
	const newOffsetY = ligatureState.offsetY - advanceSinceBaseY + (ligatureAnchor.y - markAnchor.y);

	attachGlyph(s, ligatureGlyph, glyph, newOffsetX, newOffsetY);

	s.storage.glyphs[glyph].ligatureComponentIndexPlusOne = (componentIndexPlusOne & 0xFFFF) as uint16;
	s.storage.glyphs[glyph].ligatureUid = ligatureState.uid;
	s.storage.glyphs[glyph].advanceX = 0;
	s.storage.glyphs[glyph].advanceY = 0;

	let middle = s.storage.glyphs[ligatureGlyph].next;
	while (middle != glyph) {
		s.storage.glyphs[middle].flags |= KB_GLYPH_FLAG_NO_BREAK;
		middle = s.storage.glyphs[middle].next;
	}
	return true;
}

function contextualAdjustment(
	s: KbScratch,
	m: Span<uint8>,
	lookupList: int64,
	lookup: KbUnpackedLookup,
	base: int64,
	coverIndex: int64,
	glyph: int32,
	startIndex: int64,
	requestedSkipFlags: uint32,
	sequenceSkipFlags: uint32,
	skipUnicodeFlags: uint32,
	outcome: KbAdjustOutcome,
): boolean {
	const sequenceLookup = kbDoSequenceLookup(s, lookup, base, coverIndex, glyph, sequenceSkipFlags,
		skipUnicodeFlags);
	if (sequenceLookup.recordCount == 0) { return false; }

	const gdef = m.kbBlobTableData(KB_BLOB_TABLE_ID_GDEF);

	for (let recordIndex: int32 = 0; recordIndex < sequenceLookup.recordCount; recordIndex++) {
		const record = sequenceLookup.records + (recordIndex as int64) * 4;
		const recordSequenceIndex = m.kbU16(record);
		const recordLookupListIndex = m.kbU16(record + 2);
		const packedRecordLookup = kbGetLookup(m, lookupList, recordLookupListIndex);
		const recordLookup = kbUnpackLookup(m, gdef, packedRecordLookup);

		let nestedCurrentGlyph = glyph;
		let nestedCurrentGlyphIndex: int64 = 0;
		let sequenceIndex: int32 = 0;
		let at = glyph;
		while (at != KB_GLYPH_SENTINEL) {
			if (!kbSkipGlyph(s, at, lookup, sequenceSkipFlags, skipUnicodeFlags)) {
				if (sequenceIndex == recordSequenceIndex) {
					nestedCurrentGlyph = at;
					break;
				}
				sequenceIndex += 1;
			}
			nestedCurrentGlyphIndex += 1;
			at = s.storage.glyphs[at].next;
		}

		for (let nestedSubtableIndex: int32 = 0; nestedSubtableIndex < recordLookup.subtableCount;
			nestedSubtableIndex++) {
			const nestedBase = packedRecordLookup +
				m.kbU16(recordLookup.subtableOffsets + (nestedSubtableIndex as int64) * 2);
			kbDoSingleAdjustment(s, lookupList, recordLookupListIndex as int64,
				nestedSubtableIndex as int64, recordLookup, nestedBase, nestedCurrentGlyph,
				startIndex + nestedCurrentGlyphIndex, requestedSkipFlags);
		}
	}

	outcome.onePastLastGlyphIndex = startIndex +
		(sequenceLookup.inputSequenceCountIncludingSkippedGlyphs as int64);
	outcome.onePastLastGlyph = sequenceLookup.onePastLastGlyphMatched;
	return true;
}

function unhandledAdjustmentType(type: int32, base: int64): boolean {
	throw kbBoundsFail(`unhandled positioning lookup type ${type}`, base);
}

export function kbDoSingleAdjustment(
	s: KbScratch,
	lookupList: int64,
	lookupIndex: int64,
	subtableIndex: int64,
	lookupIn: KbUnpackedLookup,
	baseIn: int64,
	currentGlyph: int32,
	startIndex: int64,
	requestedSkipFlags: uint32,
): boolean {
	const skipUnicodeFlags = KB_UNICODE_FLAG_DEFAULT_IGNORABLE as uint32;
	const regularSkipFlags = kbSkipFlagsGposRegular(requestedSkipFlags);
	const sequenceSkipFlags = kbSkipFlagsGposSequence(requestedSkipFlags);

	let result = false;
	const outcome = new KbAdjustOutcome(startIndex + 1, s.storage.glyphs[currentGlyph].next);

	if (!kbGlyphIncludedInLookupSubtable(s, true, lookupIndex, subtableIndex, currentGlyph)) {
		return false;
	}

	const font = s.font;
	const blobArr = font.blob;
	const m: Span<uint8> = blobArr[0..blobArr.length];
	let lookup = lookupIn;
	let base = baseIn;

	while (lookup.type == 9) {
		lookup.type = m.kbU16(base + 2);
		base = base + m.kbU32(base + 4);
	}

	let coverValid = kbGlyphPassesLookupFilter(s, currentGlyph, lookup);
	let coverIndex: int64 = 0;
	if (coverValid && kbLookupBeginsWithCoverage(true, lookup.type, m.kbU16(base))) {
		const cover = kbCoverGlyph(m, base + m.kbU16(base + 2), s.storage.glyphs[currentGlyph].id as int32);
		coverValid = cover.valid;
		coverIndex = cover.index;
	}

	if (coverValid) {
		result = match (lookup.type) {
			1 => singleAdjustment(s, base, coverIndex, currentGlyph),
			2 => pairAdjustment(s, lookup, base, coverIndex, currentGlyph, regularSkipFlags,
				skipUnicodeFlags, outcome),
			3 => cursiveAdjustment(s, lookup, base, coverIndex, currentGlyph, regularSkipFlags,
				skipUnicodeFlags),
			4 | 6 => markToBaseAdjustment(s, lookup, base, coverIndex, currentGlyph, regularSkipFlags,
				skipUnicodeFlags),
			5 => markToLigatureAdjustment(s, lookup, base, coverIndex, currentGlyph, regularSkipFlags,
				skipUnicodeFlags),
			7 | 8 => contextualAdjustment(s, s.font.blob, lookupList, lookup, base, coverIndex, currentGlyph,
				startIndex, requestedSkipFlags, sequenceSkipFlags, skipUnicodeFlags, outcome),
			_ => unhandledAdjustmentType(lookup.type, base),
		};

		kbSetLookupOnePastLastGlyph(s, outcome.onePastLastGlyphIndex, outcome.onePastLastGlyph);
	}
	return result;
}
