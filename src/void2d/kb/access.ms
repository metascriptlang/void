import {
	KB_LOOKUP_FLAG_USE_MARK_FILTERING_SET,
	KB_SIZE_CMAP,
	KB_SIZE_ENCODING_RECORD,
	KB_SIZE_LIGATURE_ATTACH,
	KB_VALUE_FORMAT_X_ADVANCE,
	KB_VALUE_FORMAT_X_ADVANCE_DEVICE,
	KB_VALUE_FORMAT_X_PLACEMENT,
	KB_VALUE_FORMAT_X_PLACEMENT_DEVICE,
	KB_VALUE_FORMAT_Y_ADVANCE,
	KB_VALUE_FORMAT_Y_ADVANCE_DEVICE,
	KB_VALUE_FORMAT_Y_PLACEMENT,
	KB_VALUE_FORMAT_Y_PLACEMENT_DEVICE,
	kbSwap16,
	kbU16,
	kbU32,
} from "./blob";

export struct KbTaggedPointer {
	tag: int64;
	at: int64;
}

export struct KbCmapSubtablePointer {
	platformId: int32;
	encodingId: int32;
	at: int64;
}

export struct KbUnpackedLookup {
	subtableOffsets: int64;
	markFilteringSet: int64;
	type: int32;
	flags: int32;
	subtableCount: int32;
}

export struct KbUnpackedValueRecord {
	size: int32;
	placementX: int32;
	placementY: int32;
	advanceX: int32;
	advanceY: int32;
	placementXDevice: int64;
	placementYDevice: int64;
	advanceXDevice: int64;
	advanceYDevice: int64;
}

export struct KbUnpackedChainedSequenceRule {
	input: int64;
	backtrack: int64;
	lookahead: int64;
	records: int64;
	backtrackCount: int32;
	inputCount: int32;
	lookaheadCount: int32;
	recordCount: int32;
}

export struct KbUnpackedChainedSequenceContext3 {
	backtrackCoverageOffsets: int64;
	inputCoverageOffsets: int64;
	lookaheadCoverageOffsets: int64;
	records: int64;
	backtrackCount: int32;
	inputCount: int32;
	lookaheadCount: int32;
	recordCount: int32;
}

export struct KbUnpackedReverseChainSubstitution {
	backtrackCoverageOffsets: int64;
	lookaheadCoverageOffsets: int64;
	substituteGlyphIds: int64;
	backtrackCount: int32;
	lookaheadCount: int32;
	glyphCount: int32;
}

export struct KbMarkInfo {
	array: int64;
	record: int64;
	anchor: int64;
}

export struct KbCoverGlyphResult {
	valid: boolean;
	index: int64;
}

export struct KbGlyphClassResult {
	found: boolean;
	classValue: int32;
}

function readCount(m: Readonly<Span<uint8>>, at: int64, byteSwap: boolean): int32 {
	const value = m.kbU16(at);
	return byteSwap ? kbSwap16(value) : value;
}

export function kbUnpackValueRecord(
	m: Readonly<Span<uint8>>,
	parent: int64,
	format: int32,
	record: int64,
): KbUnpackedValueRecord {
	let result: KbUnpackedValueRecord = {
		size: 0, placementX: 0, placementY: 0, advanceX: 0, advanceY: 0,
		placementXDevice: 0, placementYDevice: 0, advanceXDevice: 0, advanceYDevice: 0,
	};
	let at = record;
	if ((format & KB_VALUE_FORMAT_X_PLACEMENT) != 0) {
		result.placementX = m.kbS16(at);
		at += 2;
	}
	if ((format & KB_VALUE_FORMAT_Y_PLACEMENT) != 0) {
		result.placementY = m.kbS16(at);
		at += 2;
	}
	if ((format & KB_VALUE_FORMAT_X_ADVANCE) != 0) {
		result.advanceX = m.kbS16(at);
		at += 2;
	}
	if ((format & KB_VALUE_FORMAT_Y_ADVANCE) != 0) {
		result.advanceY = m.kbS16(at);
		at += 2;
	}
	if ((format & KB_VALUE_FORMAT_X_PLACEMENT_DEVICE) != 0) {
		const offset = m.kbU16(at);
		at += 2;
		if (offset != 0) { result.placementXDevice = parent + offset; }
	}
	if ((format & KB_VALUE_FORMAT_Y_PLACEMENT_DEVICE) != 0) {
		const offset = m.kbU16(at);
		at += 2;
		if (offset != 0) { result.placementYDevice = parent + offset; }
	}
	if ((format & KB_VALUE_FORMAT_X_ADVANCE_DEVICE) != 0) {
		const offset = m.kbU16(at);
		at += 2;
		if (offset != 0) { result.advanceXDevice = parent + offset; }
	}
	if ((format & KB_VALUE_FORMAT_Y_ADVANCE_DEVICE) != 0) {
		const offset = m.kbU16(at);
		at += 2;
		if (offset != 0) { result.advanceYDevice = parent + offset; }
	}
	result.size = ((at - record) / 2) as int32;
	return result;
}

export function kbUnpackReverseChainSubstitution(
	m: Readonly<Span<uint8>>,
	subst: int64,
	byteSwap: boolean,
): KbUnpackedReverseChainSubstitution {
	const backtrackCoverageOffsets = subst + 6;
	const backtrackCount = readCount(m, subst + 4, byteSwap);
	const lookaheadCoverageOffsets = backtrackCoverageOffsets + (backtrackCount as int64) * 2 + 2;
	const lookaheadCount = readCount(m, backtrackCoverageOffsets + (backtrackCount as int64) * 2,
		byteSwap);
	const substituteGlyphIds = lookaheadCoverageOffsets + (lookaheadCount as int64) * 2 + 2;
	const glyphCount = readCount(m, lookaheadCoverageOffsets + (lookaheadCount as int64) * 2,
		byteSwap);
	return {
		backtrackCoverageOffsets, lookaheadCoverageOffsets, substituteGlyphIds,
		backtrackCount, lookaheadCount, glyphCount,
	};
}

export function kbUnpackChainedSequenceRule(
	m: Readonly<Span<uint8>>,
	rule: int64,
	byteSwap: boolean,
): KbUnpackedChainedSequenceRule {
	const backtrack = rule + 2;
	const backtrackCount = readCount(m, rule, byteSwap);
	const input = backtrack + (backtrackCount as int64) * 2 + 2;
	const inputCount = readCount(m, backtrack + (backtrackCount as int64) * 2, byteSwap);
	const lookahead = input + (inputCount as int64) * 2;
	const lookaheadCount = readCount(m, input + ((inputCount as int64) - 1) * 2, byteSwap);
	const records = lookahead + (lookaheadCount as int64) * 2 + 2;
	const recordCount = readCount(m, lookahead + (lookaheadCount as int64) * 2, byteSwap);
	return {
		input, backtrack, lookahead, records, backtrackCount, inputCount, lookaheadCount,
		recordCount,
	};
}

export function kbUnpackChainedSequenceContext3(
	m: Readonly<Span<uint8>>,
	subst: int64,
	byteSwap: boolean,
): KbUnpackedChainedSequenceContext3 {
	const backtrackCoverageOffsets = subst + 4;
	const backtrackCount = readCount(m, subst + 2, byteSwap);
	const inputCoverageOffsets = backtrackCoverageOffsets + (backtrackCount as int64) * 2 + 2;
	const inputCount = readCount(m, backtrackCoverageOffsets + (backtrackCount as int64) * 2,
		byteSwap);
	const lookaheadCoverageOffsets = inputCoverageOffsets + (inputCount as int64) * 2 + 2;
	const lookaheadCount = readCount(m, inputCoverageOffsets + (inputCount as int64) * 2, byteSwap);
	const records = lookaheadCoverageOffsets + (lookaheadCount as int64) * 2 + 2;
	const recordCount = readCount(m, lookaheadCoverageOffsets + (lookaheadCount as int64) * 2,
		byteSwap);
	return {
		backtrackCoverageOffsets, inputCoverageOffsets, lookaheadCoverageOffsets, records,
		backtrackCount, inputCount, lookaheadCount, recordCount,
	};
}

export function kbUnpackLookup(m: Readonly<Span<uint8>>, gdef: int64, lookup: int64): KbUnpackedLookup {
	let result: KbUnpackedLookup = {
		subtableOffsets: lookup + 6, markFilteringSet: 0, type: m.kbU16(lookup),
		flags: m.kbU16(lookup + 2), subtableCount: m.kbU16(lookup + 4),
	};
	if ((result.flags & KB_LOOKUP_FLAG_USE_MARK_FILTERING_SET) != 0) {
		const markFilteringSetIndex = m.kbU16(result.subtableOffsets +
			(result.subtableCount as int64) * 2);
		if (gdef != 0 && m.kbU16(gdef + 12) != 0) {
			const markGlyphSets = gdef + m.kbU16(gdef + 12);
			if (m.kbU16(markGlyphSets + 2) > markFilteringSetIndex) {
				const coverageOffset = m.kbU32(markGlyphSets + 4 + (markFilteringSetIndex as int64) * 4);
				result.markFilteringSet = markGlyphSets + coverageOffset;
			}
		}
	}
	return result;
}

export function kbGetScript(m: Readonly<Span<uint8>>, list: int64, index: int64): KbTaggedPointer {
	const record = list + 2 + index * 6;
	return { tag: m.kbU32(record), at: list + m.kbU16(record + 4) };
}

export function kbGetDefaultLangsys(m: Readonly<Span<uint8>>, script: int64): int64 {
	const offset = m.kbU16(script);
	return offset != 0 ? script + offset : 0;
}

export function kbGetLangsys(m: Readonly<Span<uint8>>, script: int64, index: int64): KbTaggedPointer {
	const record = script + 4 + index * 6;
	return { tag: m.kbU32(record), at: script + m.kbU16(record + 4) };
}

export function kbGetFeature(m: Readonly<Span<uint8>>, list: int64, index: int64): KbTaggedPointer {
	const record = list + 2 + index * 6;
	return { tag: m.kbU32(record), at: list + m.kbU16(record + 4) };
}

export function kbGetLookupList(m: Readonly<Span<uint8>>, gsubGpos: int64): int64 {
	return gsubGpos != 0 ? gsubGpos + m.kbU16(gsubGpos + 8) : 0;
}

export function kbGetLookup(m: Readonly<Span<uint8>>, list: int64, index: int64): int64 {
	return list + m.kbU16(list + 2 + index * 2);
}

export function kbGetSequenceRuleSet(m: Readonly<Span<uint8>>, context: int64, index: int64): int64 {
	const offset = m.kbU16(context + 6 + index * 2);
	return offset != 0 ? context + offset : 0;
}

export function kbGetSequenceRule(m: Readonly<Span<uint8>>, set: int64, index: int64): int64 {
	return set + m.kbU16(set + 2 + index * 2);
}

export function kbGetClassSequenceRuleSet(
	m: Readonly<Span<uint8>>,
	context: int64,
	index: int64,
): int64 {
	if (index >= m.kbU16(context + 6)) { return 0; }
	const offset = m.kbU16(context + 8 + index * 2);
	return offset != 0 ? context + offset : 0;
}

export function kbGetClassSequenceRule(m: Readonly<Span<uint8>>, set: int64, index: int64): int64 {
	return set + m.kbU16(set + 2 + index * 2);
}

export function kbGetChainedSequenceRuleSet(
	m: Readonly<Span<uint8>>,
	context: int64,
	index: int64,
): int64 {
	const offset = m.kbU16(context + 6 + index * 2);
	return offset != 0 ? context + offset : 0;
}

export function kbGetChainedSequenceRule(
	m: Readonly<Span<uint8>>,
	set: int64,
	index: int64,
): int64 {
	return set + m.kbU16(set + 2 + index * 2);
}

export function kbGetChainedClassSequenceRuleSet(
	m: Readonly<Span<uint8>>,
	context: int64,
	index: int64,
): int64 {
	const offset = m.kbU16(context + 12 + index * 2);
	return offset != 0 ? context + offset : 0;
}

export function kbGetChainedClassSequenceRule(
	m: Readonly<Span<uint8>>,
	set: int64,
	index: int64,
): int64 {
	return set + m.kbU16(set + 2 + index * 2);
}

export function kbGetCmapSubtable(
	m: Readonly<Span<uint8>>,
	cmap: int64,
	index: int64,
): KbCmapSubtablePointer {
	const record = cmap + KB_SIZE_CMAP + index * KB_SIZE_ENCODING_RECORD;
	return {
		platformId: m.kbU16(record), encodingId: m.kbU16(record + 2),
		at: cmap + m.kbU32(record + 4),
	};
}

export function kbGetSequence(m: Readonly<Span<uint8>>, subst: int64, index: int64): int64 {
	return subst + m.kbU16(subst + 6 + index * 2);
}

export function kbGetAlternateSet(m: Readonly<Span<uint8>>, subst: int64, index: int64): int64 {
	return subst + m.kbU16(subst + 6 + index * 2);
}

export function kbGetLigatureSet(m: Readonly<Span<uint8>>, subst: int64, index: int64): int64 {
	return subst + m.kbU16(subst + 6 + index * 2);
}

export function kbGetLigature(m: Readonly<Span<uint8>>, set: int64, index: int64): int64 {
	return set + m.kbU16(set + 2 + index * 2);
}

export function kbGetMarkRecord(array: int64, index: int64): int64 {
	return array + 2 + index * 4;
}

export function kbGetLigatureAttach(m: Readonly<Span<uint8>>, array: int64, index: int64): int64 {
	return array + m.kbU16(array + 2 + index * 2);
}

export function kbGetLigatureAttachAnchor(
	m: Readonly<Span<uint8>>,
	adjust: int64,
	attach: int64,
	markClass: int32,
	componentIndex: int64,
): int64 {
	const markClassCount = m.kbU16(adjust + 6) as int64;
	const offset = m.kbU16(attach + KB_SIZE_LIGATURE_ATTACH +
		(componentIndex * markClassCount + (markClass as int64)) * 2);
	return offset != 0 ? attach + offset : 0;
}

export function kbGetMarkInfo(
	m: Readonly<Span<uint8>>,
	subtable: int64,
	subtableOffsetToMarkArray: int64,
	coverageIndex: int64,
): KbMarkInfo {
	const array = subtable + subtableOffsetToMarkArray;
	const record = kbGetMarkRecord(array, coverageIndex);
	return { array, record, anchor: array + m.kbU16(record + 2) };
}

export function kbLookupBeginsWithCoverage(gpos: boolean, lookupType: int32, format: int32): boolean {
	return gpos ? lookupType != 9 && format != 3 : lookupType != 7 && format != 3;
}

export function kbGlyphClassFromTable(
	m: Readonly<Span<uint8>>,
	classDefinitionBase: int64,
	id: int64,
): KbGlyphClassResult {
	let result: KbGlyphClassResult = { found: false, classValue: 0 };
	const format = m.kbU16(classDefinitionBase);
	if (format == 1) {
		const offset = id - m.kbU16(classDefinitionBase + 2);
		if (offset >= 0 && offset < m.kbU16(classDefinitionBase + 4)) {
			result.classValue = m.kbU16(classDefinitionBase + 6 + offset * 2);
			result.found = true;
		}
	} else if (format == 2) {
		let ranges = classDefinitionBase + 4;
		let rangeCount = m.kbU16(classDefinitionBase + 2) as int64;
		if (rangeCount != 0) {
			while (rangeCount > 1) {
				const halfCount = rangeCount / 2;
				ranges = m.kbU16(ranges + (halfCount - 1) * 6 + 2) < id ? ranges + halfCount * 6 : ranges;
				rangeCount -= halfCount;
			}
			if (id >= m.kbU16(ranges) && id <= m.kbU16(ranges + 2)) {
				result.classValue = m.kbU16(ranges + 4);
				result.found = true;
			}
		}
	}
	return result;
}

export function kbCoverGlyph(
	m: Readonly<Span<uint8>>,
	coverage: int64,
	glyphId: int32,
): KbCoverGlyphResult {
	let result: KbCoverGlyphResult = { valid: false, index: 0 };
	let count = m.kbU16(coverage + 2) as int64;
	if (count != 0) {
		const format = m.kbU16(coverage);
		if (format == 1) {
			const first = coverage + 4;
			let glyphIds = first;
			while (count > 1) {
				const halfCount = count / 2;
				glyphIds = m.kbU16(glyphIds + (halfCount - 1) * 2) < glyphId ? glyphIds + halfCount * 2 : glyphIds;
				count -= halfCount;
			}
			if (glyphId == m.kbU16(glyphIds)) {
				result.valid = true;
				result.index = (glyphIds - first) / 2;
			}
		} else if (format == 2) {
			let ranges = coverage + 4;
			while (count > 1) {
				const halfCount = count / 2;
				ranges = m.kbU16(ranges + (halfCount - 1) * 6 + 2) < glyphId ? ranges + halfCount * 6 : ranges;
				count -= halfCount;
			}
			const start = m.kbU16(ranges);
			if (glyphId >= start && glyphId <= m.kbU16(ranges + 2)) {
				result.valid = true;
				result.index = (m.kbU16(ranges + 4) + glyphId - start) as int64;
			}
		}
	}
	return result;
}
