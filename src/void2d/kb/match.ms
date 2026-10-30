import { KbUnpackedLookup, kbCoverGlyph, kbGlyphClassFromTable, kbGetChainedClassSequenceRule,
	kbGetChainedClassSequenceRuleSet, kbGetChainedSequenceRule, kbGetChainedSequenceRuleSet,
	kbGetClassSequenceRule, kbGetClassSequenceRuleSet, kbGetSequenceRule, kbGetSequenceRuleSet,
	kbUnpackChainedSequenceContext3, kbUnpackChainedSequenceRule } from "./access";
import { kbBoundsFail, kbU16 } from "./blob";
import {
	KB_GLYPH_CLASS_MARK,
	KB_GLYPH_SENTINEL,
} from "./glyph";
import { KbScratch } from "./scratch";
import {
	KB_GLYPH_FLAG_GENERATED_BY_GSUB,
	KB_SKIP_FLAG_DEFAULT_IGNORABLES_NOT_SKIPPED_BY_GSUB,
	KB_SKIP_FLAG_ZWJ,
	KB_SKIP_FLAG_ZWNJ,
} from "./shapeTables";

export const KB_LOOKUP_FLAG_RIGHT_TO_LEFT: int32 = 1 << 0;
export const KB_LOOKUP_FLAG_MARK_ATTACHMENT_CLASS_FILTER: int32 = 0xFF00;

export function kbSkipFlagsGsubRegular(requestedFlags: uint32): uint32 {
	return requestedFlags & KB_SKIP_FLAG_ZWJ;
}

export function kbSkipFlagsGsubSequence(requestedFlags: uint32): uint32 {
	return KB_SKIP_FLAG_ZWJ | (requestedFlags & KB_SKIP_FLAG_ZWNJ);
}

export function kbSkipFlagsGposRegular(requestedFlags: uint32): uint32 {
	return (requestedFlags & KB_SKIP_FLAG_ZWJ) | KB_SKIP_FLAG_ZWNJ |
		KB_SKIP_FLAG_DEFAULT_IGNORABLES_NOT_SKIPPED_BY_GSUB;
}

export function kbSkipFlagsGposSequence(requestedFlags: uint32): uint32 {
	return KB_SKIP_FLAG_ZWJ | KB_SKIP_FLAG_ZWNJ | KB_SKIP_FLAG_DEFAULT_IGNORABLES_NOT_SKIPPED_BY_GSUB;
}

export struct KbSequenceMatch {
	onePastMatchGlyph: int32;
	matchCount: int32;
	matchOrSkipCount: int32;
}

export struct KbSequenceLookupResult {
	records: int64;
	onePastLastGlyphMatched: int32;
	matched: boolean;
	recordCount: int32;
	inputSequenceCountIncludingSkippedGlyphs: int32;
}

const MAX_SEQUENCE_ARRAY: int32 = 64;

export function kbGlyphPassesLookupFilter(s: KbScratch, glyph: int32, lookup: KbUnpackedLookup): boolean {
	let result = true;
	const classValue = s.storage.glyphs[glyph].classValue as int32;

	if (classValue != 0) {
		if (classValue > 31) {
			throw kbBoundsFail("glyph class too large for the lookup flag shift", classValue as int64);
		}
		if ((lookup.flags & (1 << classValue)) != 0) { result = false; }
	}

	if (result && classValue == KB_GLYPH_CLASS_MARK) {
		if ((lookup.flags & KB_LOOKUP_FLAG_MARK_ATTACHMENT_CLASS_FILTER) != 0) {
			const desiredMarkAttachmentClass = lookup.flags >> 8;
			if ((s.storage.glyphs[glyph].markAttachmentClass as int32) != desiredMarkAttachmentClass) {
				result = false;
			}
		}

		if (result && lookup.markFilteringSet != 0) {
			const blobArr = s.font.blob;
			const cover = kbCoverGlyph(blobArr[0..blobArr.length], lookup.markFilteringSet,
				s.storage.glyphs[glyph].id as int32);
			if (!cover.valid) { result = false; }
		}
	}
	return result;
}

export function kbSkipGlyph(
	s: KbScratch,
	glyph: int32,
	lookup: KbUnpackedLookup,
	skipFlags: uint32,
	skipUnicodeFlags: uint32,
): boolean {
	let result = false;
	if (!kbGlyphPassesLookupFilter(s, glyph, lookup)) {
		result = true;
	} else {
		const skipDefaultIgnorable =
			(s.storage.glyphs[glyph].flags & KB_GLYPH_FLAG_GENERATED_BY_GSUB) == 0 &&
			((s.storage.glyphs[glyph].unicodeFlags as uint32) & skipUnicodeFlags) != 0;
		if (skipDefaultIgnorable) {
			const codepoint = s.storage.glyphs[glyph].codepoint;
			if (codepoint >= 0xE0020 && codepoint <= 0xE007F) {
				result = (skipFlags & KB_SKIP_FLAG_DEFAULT_IGNORABLES_NOT_SKIPPED_BY_GSUB) != 0;
			} else {
				result = match (codepoint) {
					0x34F | 0x180B | 0x180C | 0x180D | 0x180F =>
						(skipFlags & KB_SKIP_FLAG_DEFAULT_IGNORABLES_NOT_SKIPPED_BY_GSUB) != 0,
					0x200C => (skipFlags & KB_SKIP_FLAG_ZWNJ) != 0,
					0x200D => (skipFlags & KB_SKIP_FLAG_ZWJ) != 0,
					_ => true,
				};
			}
		}
	}
	return result;
}

export function kbNextGlyph(
	s: KbScratch,
	lookup: KbUnpackedLookup,
	atGlyph: int32,
	skipFlags: uint32,
	skipUnicodeFlags: uint32,
	backward: boolean,
): int32 {
	let current = atGlyph;
	while (current != KB_GLYPH_SENTINEL) {
		if (!kbSkipGlyph(s, current, lookup, skipFlags, skipUnicodeFlags)) {
			return current;
		}
		current = backward ? s.storage.glyphs[current].prev : s.storage.glyphs[current].next;
	}
	return KB_GLYPH_SENTINEL;
}

export function kbMatchCoverageSequence(
	s: KbScratch,
	lookup: KbUnpackedLookup,
	skipFlags: uint32,
	skipUnicodeFlags: uint32,
	base: int64,
	coverageOffsets: int64,
	coverageCount: int64,
	startGlyph: int32,
	backward: boolean,
): KbSequenceMatch {
	const font = s.font;
	const blobArr = font.blob;
	const m: Span<uint8> = blobArr[0..blobArr.length];
	let atGlyph = startGlyph;
	let coverageIndex: int64 = 0;
	let glyphCounter: int64 = 0;
	while (atGlyph != KB_GLYPH_SENTINEL && coverageIndex < coverageCount) {
		const coverage = base + m.kbU16(coverageOffsets + coverageIndex * 2);

		if (!kbSkipGlyph(s, atGlyph, lookup, skipFlags, skipUnicodeFlags)) {
			const cover = kbCoverGlyph(m, coverage, s.storage.glyphs[atGlyph].id as int32);
			if (cover.valid) {
				coverageIndex += 1;
			} else {
				break;
			}
		}

		atGlyph = backward ? s.storage.glyphs[atGlyph].prev : s.storage.glyphs[atGlyph].next;
		glyphCounter += 1;
	}

	return {
		onePastMatchGlyph: atGlyph,
		matchCount: (coverageIndex & 0xFFFF) as int32,
		matchOrSkipCount: (glyphCounter & 0xFFFF) as int32,
	};
}

function arrayMatches(m: Readonly<Span<uint8>>, ids: int32[], idsFrom: int32, at: int64, count: int64): boolean {
	let difference = 0;
	for (let i: int64 = 0; i < count; i++) {
		difference |= (ids[idsFrom + i] & 0xFFFF) ^ m.kbU16(at + i * 2);
	}
	return difference == 0;
}

function classDefinitionClass(m: Readonly<Span<uint8>>, classDefinition: int64, id: int32): int32 {
	if (classDefinition == 0) {
		throw kbBoundsFail("class definition offset is null", 0);
	}
	return kbGlyphClassFromTable(m, classDefinition, id).classValue;
}

function pushChecked(array: int32[], value: int32): void {
	if (array.length >= MAX_SEQUENCE_ARRAY) {
		throw kbBoundsFail("sequence match needs more than 64 entries", array.length as int64);
	}
	array.push(value);
}

function emptyResult(s: KbScratch, atGlyph: int32): KbSequenceLookupResult {
	return {
		records: 0, onePastLastGlyphMatched: s.storage.glyphs[atGlyph].next, matched: false,
		recordCount: 0, inputSequenceCountIncludingSkippedGlyphs: 0,
	};
}

function sequenceContext1(
	s: KbScratch,
	lookup: KbUnpackedLookup,
	base: int64,
	coverIndex: int64,
	atGlyph: int32,
	skipFlags: uint32,
	skipUnicodeFlags: uint32,
): KbSequenceLookupResult {
	const font = s.font;
	const blobArr = font.blob;
	const m: Span<uint8> = blobArr[0..blobArr.length];
	let result = emptyResult(s, atGlyph);
	let inputGlyph = s.storage.glyphs[atGlyph].next;
	let inputGlyphsTraversed: int32 = 1;

	const set = kbGetSequenceRuleSet(m, base, coverIndex);
	if (set != 0) {
		const ids: int32[] = [];
		const inputGlyphOffsets: int32[] = [];
		const inputGlyphs: int32[] = [];

		const ruleCount = m.kbU16(set);
		for (let ruleIndex = 0; ruleIndex < ruleCount; ruleIndex++) {
			const rule = kbGetSequenceRule(m, set, ruleIndex);
			const glyphCount = m.kbU16(rule);
			const sequenceLookupCount = m.kbU16(rule + 2);
			const inputSequence = rule + 4;
			if (glyphCount == 0) { throw kbBoundsFail("sequence rule with no glyphs", rule); }
			if (glyphCount > MAX_SEQUENCE_ARRAY) {
				throw kbBoundsFail("sequence rule needs more than 64 glyphs", rule);
			}

			while (inputGlyph != KB_GLYPH_SENTINEL && ((ids.length + 1) < glyphCount)) {
				if (!kbSkipGlyph(s, inputGlyph, lookup, skipFlags, skipUnicodeFlags)) {
					pushChecked(inputGlyphOffsets, inputGlyphsTraversed & 0xFFFF);
					pushChecked(inputGlyphs, inputGlyph);
					pushChecked(ids, s.storage.glyphs[inputGlyph].id as int32);
				}

				inputGlyph = s.storage.glyphs[inputGlyph].next;
				inputGlyphsTraversed += 1;
			}

			if ((ids.length + 1) >= glyphCount && arrayMatches(m, ids, 0, inputSequence, glyphCount - 1)) {
				result.records = inputSequence + (glyphCount - 1) * 2;
				result.recordCount = sequenceLookupCount;
				result.inputSequenceCountIncludingSkippedGlyphs = 1;
				if (glyphCount > 1) {
					result.inputSequenceCountIncludingSkippedGlyphs =
						inputGlyphOffsets[glyphCount - 2] + 1;
					result.onePastLastGlyphMatched = s.storage.glyphs[inputGlyphs[glyphCount - 2]].next;
				}
				result.matched = true;
				break;
			}
		}
	}
	return result;
}

function sequenceContext2(
	s: KbScratch,
	lookup: KbUnpackedLookup,
	base: int64,
	atGlyph: int32,
	skipFlags: uint32,
	skipUnicodeFlags: uint32,
): KbSequenceLookupResult {
	const font = s.font;
	const blobArr = font.blob;
	const m: Span<uint8> = blobArr[0..blobArr.length];
	let result = emptyResult(s, atGlyph);
	let inputGlyph = s.storage.glyphs[atGlyph].next;
	let inputGlyphsTraversed: int32 = 1;

	const classDefinitionBase = base + m.kbU16(base + 4);
	const inputClasses: int32[] = [];
	const inputOffsets: int32[] = [];
	const inputGlyphs: int32[] = [];

	const currentGlyphClass = classDefinitionClass(m, classDefinitionBase,
		s.storage.glyphs[atGlyph].id as int32);
	const set = kbGetClassSequenceRuleSet(m, base, currentGlyphClass);

	if (set != 0) {
		const ruleCount = m.kbU16(set);
		for (let ruleIndex = 0; ruleIndex < ruleCount; ruleIndex++) {
			const rule = kbGetClassSequenceRule(m, set, ruleIndex);
			const glyphCount = m.kbU16(rule);
			const sequenceLookupCount = m.kbU16(rule + 2);
			const inputSequence = rule + 4;
			if (glyphCount == 0) { throw kbBoundsFail("class sequence rule with no glyphs", rule); }
			if (glyphCount > MAX_SEQUENCE_ARRAY) {
				throw kbBoundsFail("class sequence rule needs more than 64 glyphs", rule);
			}

			while (inputGlyph != KB_GLYPH_SENTINEL && ((inputClasses.length + 1) < glyphCount)) {
				if (!kbSkipGlyph(s, inputGlyph, lookup, skipFlags, skipUnicodeFlags)) {
					pushChecked(inputOffsets, inputGlyphsTraversed & 0xFFFF);
					pushChecked(inputGlyphs, inputGlyph);
					pushChecked(inputClasses, classDefinitionClass(m, classDefinitionBase,
						s.storage.glyphs[inputGlyph].id as int32));
				}

				inputGlyph = s.storage.glyphs[inputGlyph].next;
				inputGlyphsTraversed += 1;
			}

			if ((inputClasses.length + 1) >= glyphCount &&
				arrayMatches(m, inputClasses, 0, inputSequence, glyphCount - 1)) {
				result.records = inputSequence + (glyphCount - 1) * 2;
				result.recordCount = sequenceLookupCount;
				result.inputSequenceCountIncludingSkippedGlyphs = 1;
				if (glyphCount > 1) {
					result.inputSequenceCountIncludingSkippedGlyphs = inputOffsets[glyphCount - 2] + 1;
					result.onePastLastGlyphMatched = s.storage.glyphs[inputGlyphs[glyphCount - 2]].next;
				}
				result.matched = true;
				break;
			}
		}
	}
	return result;
}

function sequenceContext3(
	s: KbScratch,
	lookup: KbUnpackedLookup,
	base: int64,
	atGlyph: int32,
	skipFlags: uint32,
	skipUnicodeFlags: uint32,
): KbSequenceLookupResult {
	const font = s.font;
	const blobArr = font.blob;
	const m: Span<uint8> = blobArr[0..blobArr.length];
	let result = emptyResult(s, atGlyph);
	const glyphCount = m.kbU16(base + 2);
	const coverageOffsets = base + 6;

	const inputMatch = kbMatchCoverageSequence(s, lookup, skipFlags, skipUnicodeFlags, base,
		coverageOffsets, glyphCount, atGlyph, false);

	if (inputMatch.matchCount == glyphCount) {
		result.records = coverageOffsets + (glyphCount as int64) * 2;
		result.recordCount = m.kbU16(base + 4);
		result.inputSequenceCountIncludingSkippedGlyphs = inputMatch.matchOrSkipCount;
		result.onePastLastGlyphMatched = inputMatch.onePastMatchGlyph;
		result.matched = true;
	}
	return result;
}

function chainedSequenceContext1(
	s: KbScratch,
	lookup: KbUnpackedLookup,
	base: int64,
	coverIndex: int64,
	atGlyph: int32,
	skipFlags: uint32,
	skipUnicodeFlags: uint32,
): KbSequenceLookupResult {
	const font = s.font;
	const blobArr = font.blob;
	const m: Span<uint8> = blobArr[0..blobArr.length];
	let result = emptyResult(s, atGlyph);
	let inputGlyph = s.storage.glyphs[atGlyph].next;
	let inputGlyphsTraversed: int32 = 1;
	let backtrackGlyph = s.storage.glyphs[atGlyph].prev;

	const set = kbGetChainedSequenceRuleSet(m, base, coverIndex);
	if (set != 0) {
		const backtrackIds: int32[] = [];
		const inputIds: int32[] = [];
		const inputOffsets: int32[] = [];
		const inputGlyphs: int32[] = [];

		const ruleCount = m.kbU16(set);
		for (let ruleIndex = 0; ruleIndex < ruleCount; ruleIndex++) {
			const rule = kbGetChainedSequenceRule(m, set, ruleIndex);
			const unpacked = kbUnpackChainedSequenceRule(m, rule, false);
			if (unpacked.inputCount == 0) { throw kbBoundsFail("chained rule with no input glyph", rule); }

			while (backtrackGlyph != KB_GLYPH_SENTINEL && backtrackIds.length < unpacked.backtrackCount) {
				if (!kbSkipGlyph(s, backtrackGlyph, lookup, skipFlags, skipUnicodeFlags)) {
					pushChecked(backtrackIds, s.storage.glyphs[backtrackGlyph].id as int32);
				}
				backtrackGlyph = s.storage.glyphs[backtrackGlyph].prev;
			}

			const totalInputGlyphsRequired = unpacked.inputCount - 1 + unpacked.lookaheadCount;
			while (inputGlyph != KB_GLYPH_SENTINEL && inputIds.length < totalInputGlyphsRequired) {
				if (!kbSkipGlyph(s, inputGlyph, lookup, skipFlags, skipUnicodeFlags)) {
					pushChecked(inputGlyphs, inputGlyph);
					pushChecked(inputOffsets, inputGlyphsTraversed & 0xFFFF);
					pushChecked(inputIds, s.storage.glyphs[inputGlyph].id as int32);
				}

				inputGlyph = s.storage.glyphs[inputGlyph].next;
				inputGlyphsTraversed += 1;
			}

			if (backtrackIds.length >= unpacked.backtrackCount &&
				inputIds.length >= totalInputGlyphsRequired &&
				arrayMatches(m, backtrackIds, 0, unpacked.backtrack, unpacked.backtrackCount) &&
				arrayMatches(m, inputIds, 0, unpacked.input, unpacked.inputCount - 1) &&
				arrayMatches(m, inputIds, unpacked.inputCount - 1, unpacked.lookahead,
					unpacked.lookaheadCount)) {
				result.records = unpacked.records;
				result.recordCount = unpacked.recordCount;
				result.inputSequenceCountIncludingSkippedGlyphs = 1;
				if (unpacked.inputCount > 1) {
					result.inputSequenceCountIncludingSkippedGlyphs =
						inputOffsets[unpacked.inputCount - 2] + 1;
					result.onePastLastGlyphMatched =
						s.storage.glyphs[inputGlyphs[unpacked.inputCount - 2]].next;
				}
				result.matched = true;
				break;
			}
		}
	}
	return result;
}

function chainedSequenceContext2(
	s: KbScratch,
	lookup: KbUnpackedLookup,
	base: int64,
	atGlyph: int32,
	skipFlags: uint32,
	skipUnicodeFlags: uint32,
): KbSequenceLookupResult {
	const font = s.font;
	const blobArr = font.blob;
	const m: Span<uint8> = blobArr[0..blobArr.length];
	let result = emptyResult(s, atGlyph);
	let inputGlyph = s.storage.glyphs[atGlyph].next;
	let inputGlyphsTraversed: int32 = 1;
	let backtrackGlyph = s.storage.glyphs[atGlyph].prev;

	const backtrackClassDefinition: int64 = m.kbU16(base + 4) != 0 ? base + m.kbU16(base + 4) : 0;
	const inputClassDefinition: int64 = m.kbU16(base + 6) != 0 ? base + m.kbU16(base + 6) : 0;
	const lookaheadClassDefinition: int64 = m.kbU16(base + 8) != 0 ? base + m.kbU16(base + 8) : 0;
	const ruleSetCount = m.kbU16(base + 10);

	const backtrackClasses: int32[] = [];
	const inputClasses: int32[] = [];
	const inputClassOffsets: int32[] = [];
	const inputGlyphs: int32[] = [];
	const lookaheadClasses: int32[] = [];

	const currentGlyphClass = classDefinitionClass(m, inputClassDefinition,
		s.storage.glyphs[atGlyph].id as int32);
	const set = currentGlyphClass < ruleSetCount ?
		kbGetChainedClassSequenceRuleSet(m, base, currentGlyphClass) : 0;

	if (set != 0) {
		const ruleCount = m.kbU16(set);
		for (let ruleIndex = 0; ruleIndex < ruleCount; ruleIndex++) {
			const rule = kbGetChainedClassSequenceRule(m, set, ruleIndex);
			const unpacked = kbUnpackChainedSequenceRule(m, rule, false);
			if (unpacked.inputCount == 0) { throw kbBoundsFail("chained rule with no input class", rule); }

			while (backtrackGlyph != KB_GLYPH_SENTINEL &&
				backtrackClasses.length < unpacked.backtrackCount) {
				if (!kbSkipGlyph(s, backtrackGlyph, lookup, skipFlags, skipUnicodeFlags)) {
					pushChecked(backtrackClasses, classDefinitionClass(m, backtrackClassDefinition,
						s.storage.glyphs[backtrackGlyph].id as int32));
				}
				backtrackGlyph = s.storage.glyphs[backtrackGlyph].prev;
			}

			const inputClassCountRequired = unpacked.inputCount - 1 + unpacked.lookaheadCount;
			while (inputGlyph != KB_GLYPH_SENTINEL && inputClasses.length < inputClassCountRequired) {
				if (!kbSkipGlyph(s, inputGlyph, lookup, skipFlags, skipUnicodeFlags)) {
					const id = s.storage.glyphs[inputGlyph].id as int32;
					const inputClass = classDefinitionClass(m, inputClassDefinition, id);
					let lookaheadClass = inputClass;
					if (lookaheadClassDefinition != 0 && lookaheadClassDefinition != inputClassDefinition) {
						lookaheadClass = classDefinitionClass(m, lookaheadClassDefinition, id);
					}

					pushChecked(inputGlyphs, inputGlyph);
					pushChecked(inputClassOffsets, inputGlyphsTraversed & 0xFFFF);
					pushChecked(inputClasses, inputClass);
					pushChecked(lookaheadClasses, lookaheadClass);
				}

				inputGlyph = s.storage.glyphs[inputGlyph].next;
				inputGlyphsTraversed += 1;
			}

			if (backtrackClasses.length >= unpacked.backtrackCount &&
				inputClasses.length >= inputClassCountRequired &&
				arrayMatches(m, backtrackClasses, 0, unpacked.backtrack, unpacked.backtrackCount) &&
				arrayMatches(m, inputClasses, 0, unpacked.input, unpacked.inputCount - 1) &&
				arrayMatches(m, lookaheadClasses, unpacked.inputCount - 1, unpacked.lookahead,
					unpacked.lookaheadCount)) {
				result.records = unpacked.records;
				result.recordCount = unpacked.recordCount;
				result.inputSequenceCountIncludingSkippedGlyphs = 1;
				if (unpacked.inputCount > 1) {
					result.inputSequenceCountIncludingSkippedGlyphs =
						inputClassOffsets[unpacked.inputCount - 2] + 1;
					result.onePastLastGlyphMatched =
						s.storage.glyphs[inputGlyphs[unpacked.inputCount - 2]].next;
				}
				result.matched = true;
				break;
			}
		}
	}
	return result;
}

function chainedSequenceContext3(
	s: KbScratch,
	lookup: KbUnpackedLookup,
	base: int64,
	atGlyph: int32,
	skipFlags: uint32,
	skipUnicodeFlags: uint32,
): KbSequenceLookupResult {
	const font = s.font;
	const blobArr = font.blob;
	const m: Span<uint8> = blobArr[0..blobArr.length];
	let result = emptyResult(s, atGlyph);
	const inputGlyph = s.storage.glyphs[atGlyph].next;
	const backtrackGlyph = s.storage.glyphs[atGlyph].prev;

	const unpacked = kbUnpackChainedSequenceContext3(m, base, false);
	if (unpacked.inputCount == 0) {
		throw kbBoundsFail("chained coverage context with no input coverage", base);
	}

	const currentCoverage = base + m.kbU16(unpacked.inputCoverageOffsets);
	const currentCover = kbCoverGlyph(m, currentCoverage, s.storage.glyphs[atGlyph].id as int32);

	if (currentCover.valid) {
		const backtrackMatch = kbMatchCoverageSequence(s, lookup, skipFlags, skipUnicodeFlags, base,
			unpacked.backtrackCoverageOffsets, unpacked.backtrackCount, backtrackGlyph, true);
		const inputMatch = kbMatchCoverageSequence(s, lookup, skipFlags, skipUnicodeFlags, base,
			unpacked.inputCoverageOffsets + 2, unpacked.inputCount - 1, inputGlyph, false);
		const matchingInputGlyphCount = 1 + inputMatch.matchCount;
		const matchedOrSkippedInputGlyphCount = 1 + inputMatch.matchOrSkipCount;
		const lookaheadMatch = kbMatchCoverageSequence(s, lookup, skipFlags, skipUnicodeFlags, base,
			unpacked.lookaheadCoverageOffsets, unpacked.lookaheadCount, inputMatch.onePastMatchGlyph, false);

		if (backtrackMatch.matchCount == unpacked.backtrackCount &&
			matchingInputGlyphCount == unpacked.inputCount &&
			lookaheadMatch.matchCount == unpacked.lookaheadCount) {
			result.records = unpacked.records;
			result.recordCount = unpacked.recordCount;
			result.inputSequenceCountIncludingSkippedGlyphs = matchedOrSkippedInputGlyphCount & 0xFFFF;
			result.onePastLastGlyphMatched = inputMatch.onePastMatchGlyph;
			result.matched = true;
		}
	}
	return result;
}

function unhandledSequenceLookup(key: int32, base: int64): KbSequenceLookupResult {
	throw kbBoundsFail(`unhandled sequence lookup type and format ${key}`, base);
}

export function kbDoSequenceLookup(
	s: KbScratch,
	lookup: KbUnpackedLookup,
	base: int64,
	coverIndex: int64,
	atGlyph: int32,
	skipFlags: uint32,
	skipUnicodeFlags: uint32,
): KbSequenceLookupResult {
	const font = s.font;
	const blobArr = font.blob;
	const m: Span<uint8> = blobArr[0..blobArr.length];
	const key = (lookup.type << 16) | m.kbU16(base);
	return match (key) {
		0x50001 | 0x70001 => sequenceContext1(s, lookup, base, coverIndex, atGlyph, skipFlags,
			skipUnicodeFlags),
		0x50002 | 0x70002 => sequenceContext2(s, lookup, base, atGlyph, skipFlags, skipUnicodeFlags),
		0x50003 | 0x70003 => sequenceContext3(s, lookup, base, atGlyph, skipFlags, skipUnicodeFlags),
		0x60001 | 0x80001 => chainedSequenceContext1(s, lookup, base, coverIndex, atGlyph, skipFlags,
			skipUnicodeFlags),
		0x60002 | 0x80002 => chainedSequenceContext2(s, lookup, base, atGlyph, skipFlags,
			skipUnicodeFlags),
		0x60003 | 0x80003 => chainedSequenceContext3(s, lookup, base, atGlyph, skipFlags,
			skipUnicodeFlags),
		_ => unhandledSequenceLookup(key, base),
	};
}
