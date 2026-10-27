import {
	kbGetAlternateSet,
	kbGetLigature,
	kbGetLigatureSet,
	kbGetLookup,
	kbGetSequence,
	kbCoverGlyph,
	kbLookupBeginsWithCoverage,
	kbUnpackLookup,
	kbUnpackReverseChainSubstitution,
} from "./access";
import {
	KB_BLOB_TABLE_ID_GDEF,
	kbBlobTableData,
	kbBoundsFail,
	kbS16,
	kbU16,
	kbU32,
} from "./blob";
import {
	KB_GLYPH_CLASS_MARK,
	KB_GLYPH_SENTINEL,
	kbInsertGlyphAfter,
} from "./glyph";
import {
	kbDoSequenceLookup,
	kbGlyphPassesLookupFilter,
	kbMatchCoverageSequence,
	kbSkipFlagsGsubRegular,
	kbSkipFlagsGsubSequence,
	kbSkipGlyph,
} from "./match";
import {
	kbFreeGlyph,
	kbGlyphIncludedInLookupSubtable,
	kbGsubMutate,
	kbNextGlyphUid,
	kbSetLookupOnePastLastGlyph,
	KbScratch,
} from "./scratch";
import {
	KB_GLYPH_FLAG_FIRST_IN_MULTIPLE_SUBSTITUTION,
	KB_GLYPH_FLAG_GENERATED_BY_GSUB,
	KB_GLYPH_FLAG_LIGATURE,
	KB_GLYPH_FLAG_MULTIPLE_SUBSTITUTION,
	KB_SUBSTITUTION_RESULT_FLAG_MATCHED_SUBSTITUTION,
	KB_SUBSTITUTION_RESULT_FLAG_TRIED_TO_INSERT_WHILE_CHECK_ONLY,
	KB_UNICODE_FLAG_DEFAULT_IGNORABLE,
} from "./shapeTables";

const SUBTABLE_DONE: int32 = 0xFFFE;

function growStartIndex(start: uint32, grow: int64): uint32 {
	return ((start as int64 + (grow & 0xFFFF)) & 0xFFFFFFFF) as uint32;
}

export function kbDoSubstitution(
	s: KbScratch,
	lookupList: int64,
	sequentialLookupIndex: int32,
	featureValue: int32,
	checkOnly: boolean,
	requestedSkipFlags: uint32,
	generatedGlyphFlagsIn: uint32,
): uint32 {
	return substitution(s, s.font.blob, lookupList, sequentialLookupIndex, featureValue, checkOnly,
		requestedSkipFlags, generatedGlyphFlagsIn);
}

function substitution(
	s: KbScratch,
	m: Span<uint8>,
	lookupList: int64,
	sequentialLookupIndex: int32,
	featureValue: int32,
	checkOnly: boolean,
	requestedSkipFlags: uint32,
	generatedGlyphFlagsIn: uint32,
): uint32 {
	let result: uint32 = 0;
	const skipUnicodeFlags = KB_UNICODE_FLAG_DEFAULT_IGNORABLE as uint32;
	const regularSkipFlags = kbSkipFlagsGsubRegular(requestedSkipFlags);
	const sequenceSkipFlags = kbSkipFlagsGsubSequence(requestedSkipFlags);
	const generatedGlyphFlags = generatedGlyphFlagsIn | KB_GLYPH_FLAG_GENERATED_BY_GSUB;

	const frameIndex = s.frameCount - 1;

	const packedLookup = kbGetLookup(m, lookupList, s.frames[frameIndex].lookupIndex);
	let lookup = kbUnpackLookup(m, m.kbBlobTableData(KB_BLOB_TABLE_ID_GDEF), packedLookup);
	const baseLookupType = lookup.type;

	const currentGlyph = s.frames[frameIndex].inputGlyph;

	while (s.frames[frameIndex].subtableIndex < lookup.subtableCount) {
		let subtable = packedLookup + m.kbU16(lookup.subtableOffsets +
			(s.frames[frameIndex].subtableIndex as int64) * 2);
		lookup.type = baseLookupType;

		while (lookup.type == 7) {
			lookup.type = m.kbU16(subtable + 2);
			subtable = subtable + m.kbU32(subtable + 4);
		}

		if (kbGlyphIncludedInLookupSubtable(s, false, s.frames[frameIndex].lookupIndex as int64,
			s.frames[frameIndex].subtableIndex as int64, currentGlyph)) {
			let coverValid = kbGlyphPassesLookupFilter(s, currentGlyph, lookup);
			let coverIndex: int64 = 0;
			if (coverValid && kbLookupBeginsWithCoverage(false, lookup.type, m.kbU16(subtable))) {
				const coverage = subtable + m.kbU16(subtable + 2);
				const cover = kbCoverGlyph(m, coverage, s.storage.glyphs[currentGlyph].id as int32);
				coverValid = cover.valid;
				coverIndex = cover.index;
			}

			if (coverValid) {
				let onePastLastGlyphOffset: int64 = 1;
				let onePastLastGlyph = s.storage.glyphs[currentGlyph].next;

				if (lookup.type == 5 || lookup.type == 6) {
					const sequenceLookup = kbDoSequenceLookup(s, lookup, subtable, coverIndex,
						currentGlyph, sequenceSkipFlags, skipUnicodeFlags);

					if (sequenceLookup.matched) {
						s.frames[frameIndex].records = sequenceLookup.records;
						s.frames[frameIndex].recordCount = sequenceLookup.recordCount;
						s.frames[frameIndex].recordIndex = 0;

						s.frames[frameIndex].subtableIndex = SUBTABLE_DONE;

						onePastLastGlyphOffset =
							sequenceLookup.inputSequenceCountIncludingSkippedGlyphs as int64;
						onePastLastGlyph = sequenceLookup.onePastLastGlyphMatched;
					}
				} else {
					if (lookup.type == 1) {
						result |= KB_SUBSTITUTION_RESULT_FLAG_MATCHED_SUBSTITUTION;

						if (!checkOnly) {
							const format = m.kbU16(subtable);
							let newId: int32 = 0;
							if (format == 1) {
								newId = ((s.storage.glyphs[currentGlyph].id as int32) + m.kbS16(subtable + 4)) &
									0xFFFF;
							} else if (format == 2) {
								newId = m.kbU16(subtable + 6 + coverIndex * 2);
							} else {
								throw kbBoundsFail(`unhandled single substitution format ${format}`, subtable);
							}

							kbGsubMutate(s, currentGlyph, sequentialLookupIndex, newId as uint16,
								generatedGlyphFlags);
						}
					} else if (lookup.type == 2) {
						const sequence = kbGetSequence(m, subtable, coverIndex);
						result |= KB_SUBSTITUTION_RESULT_FLAG_MATCHED_SUBSTITUTION;
						const glyphCount = m.kbU16(sequence);

						if (!checkOnly) {
							const substGlyphIds = sequence + 2;
							const growCount: int64 = (glyphCount as int64) - 1;

							if (glyphCount != 0) {
								const originalGlyph = s.storage.glyphs[currentGlyph];
								let lastInsert = currentGlyph;

								let runningSortKey: int64 = s.storage.glyphs[currentGlyph].sortKey as int64;
								const sortKeyInterval: int64 =
									(s.storage.glyphs[currentGlyph].sortKeyInterval as int64) / glyphCount;
								for (let substGlyphIndex = 0; substGlyphIndex < glyphCount; substGlyphIndex++) {
									let newGlyphFlags = generatedGlyphFlags | KB_GLYPH_FLAG_MULTIPLE_SUBSTITUTION;
									const newGlyphId = m.kbU16(substGlyphIds + (substGlyphIndex as int64) * 2);

									let newGlyph = currentGlyph;
									if (substGlyphIndex != 0) {
										newGlyph = kbInsertGlyphAfter(s.storage, lastInsert, originalGlyph);
										s.storage.glyphs[newGlyph].uid = kbNextGlyphUid(s);
									} else {
										newGlyphFlags |= KB_GLYPH_FLAG_FIRST_IN_MULTIPLE_SUBSTITUTION;
									}

									s.storage.glyphs[newGlyph].sortKey = (runningSortKey & 0xFFFFFFFF) as uint32;
									s.storage.glyphs[newGlyph].sortKeyInterval =
										(sortKeyInterval & 0xFFFFFFFF) as uint32;

									kbGsubMutate(s, newGlyph, sequentialLookupIndex, newGlyphId as uint16,
										generatedGlyphFlags | newGlyphFlags);

									lastInsert = newGlyph;
									runningSortKey += sortKeyInterval;
								}

								onePastLastGlyph = s.storage.glyphs[lastInsert].next;
							} else {
								kbFreeGlyph(s, currentGlyph);
							}

							onePastLastGlyphOffset = 1 + growCount;

							for (let otherIndex = 0; otherIndex < s.frameCount - 1; otherIndex++) {
								if (s.frames[otherIndex].startIndex > s.frames[frameIndex].startIndex) {
									s.frames[otherIndex].startIndex =
										((s.frames[otherIndex].startIndex as int64 + growCount) & 0xFFFF) as uint32;
								}
							}
						} else if (glyphCount > 1) {
							result |= KB_SUBSTITUTION_RESULT_FLAG_TRIED_TO_INSERT_WHILE_CHECK_ONLY;
						}
					} else if (lookup.type == 3) {
						result |= KB_SUBSTITUTION_RESULT_FLAG_MATCHED_SUBSTITUTION;

						if (!checkOnly) {
							const set = kbGetAlternateSet(m, subtable, coverIndex);
							let alternateIndex = featureValue - 1;
							if (alternateIndex < 0 || alternateIndex >= m.kbU16(set)) {
								alternateIndex = 0;
							}

							const newId = m.kbU16(set + 2 + (alternateIndex as int64) * 2);
							kbGsubMutate(s, currentGlyph, sequentialLookupIndex, newId as uint16,
								generatedGlyphFlags);
						}
					} else if (lookup.type == 4) {
						const set = kbGetLigatureSet(m, subtable, coverIndex);
						const ligatureCount = m.kbU16(set);

						for (let ligatureIndex = 0; ligatureIndex < ligatureCount; ligatureIndex++) {
							const ligature = kbGetLigature(m, set, ligatureIndex);
							const componentIds = ligature + 4;
							const componentCount = m.kbU16(ligature + 2);

							let matchingGlyphCount = 1;

							{
								let ligatureGlyphCursor = s.storage.glyphs[currentGlyph].next;
								while (ligatureGlyphCursor != KB_GLYPH_SENTINEL && matchingGlyphCount < componentCount) {
									if ((s.storage.glyphs[ligatureGlyphCursor].id as int32) ==
										m.kbU16(componentIds + ((matchingGlyphCount - 1) as int64) * 2)) {
										matchingGlyphCount += 1;
									} else if (!kbSkipGlyph(s, ligatureGlyphCursor, lookup, regularSkipFlags,
										skipUnicodeFlags)) {
										break;
									}

									ligatureGlyphCursor = s.storage.glyphs[ligatureGlyphCursor].next;
								}
							}

							if (matchingGlyphCount == componentCount) {
								result |= KB_SUBSTITUTION_RESULT_FLAG_MATCHED_SUBSTITUTION;

								if (!checkOnly) {
									const ligatureUid = kbNextGlyphUid(s) as int32;

									let ligatureGlyphCount = 1;
									let growCount: int64 = 0;

									let previousLigatureUid = s.storage.glyphs[currentGlyph].ligatureUid as int32;
									let previousComponentCount =
										s.storage.glyphs[currentGlyph].ligatureComponentCount as int32;
									if (previousComponentCount == 0) {
										previousComponentCount = 1;
									}
									let runningComponentCount = previousComponentCount;

									let ligatureGlyphCursor = s.storage.glyphs[currentGlyph].next;
									while (ligatureGlyphCursor != KB_GLYPH_SENTINEL && ligatureGlyphCount < componentCount) {
										const next = s.storage.glyphs[ligatureGlyphCursor].next;

										if ((s.storage.glyphs[ligatureGlyphCursor].id as int32) ==
											m.kbU16(componentIds + ((ligatureGlyphCount - 1) as int64) * 2)) {
											previousLigatureUid = s.storage.glyphs[ligatureGlyphCursor].ligatureUid as int32;
											previousComponentCount =
												s.storage.glyphs[ligatureGlyphCursor].ligatureComponentCount as int32;
											if (previousComponentCount == 0) {
												previousComponentCount = 1;
											}
											runningComponentCount += previousComponentCount;

											ligatureGlyphCount += 1;

											kbFreeGlyph(s, ligatureGlyphCursor);
											growCount -= 1;
										} else if (kbSkipGlyph(s, ligatureGlyphCursor, lookup, regularSkipFlags,
											skipUnicodeFlags)) {
											s.storage.glyphs[ligatureGlyphCursor].ligatureComponentIndexPlusOne =
												ligatureGlyphCount as uint16;
											s.storage.glyphs[ligatureGlyphCursor].ligatureUid = ligatureUid as uint16;
											s.storage.glyphs[ligatureGlyphCursor].ligatureComponentCount =
												componentCount as uint16;
										} else {
											break;
										}

										ligatureGlyphCursor = next;
									}

									onePastLastGlyph = s.storage.glyphs[currentGlyph].next;

									if (previousLigatureUid != 0) {
										const deltaComponentCount = runningComponentCount - previousComponentCount;

										while (ligatureGlyphCursor != KB_GLYPH_SENTINEL) {
											let previousComponentIndexPlusOne =
												s.storage.glyphs[ligatureGlyphCursor].ligatureComponentIndexPlusOne as int32;

											if ((s.storage.glyphs[ligatureGlyphCursor].classValue as int32) ==
												KB_GLYPH_CLASS_MARK &&
												(s.storage.glyphs[ligatureGlyphCursor].ligatureUid as int32) ==
												previousLigatureUid &&
												previousComponentIndexPlusOne != 0) {
												if (previousComponentIndexPlusOne > previousComponentCount) {
													previousComponentIndexPlusOne = previousComponentCount;
												}

												const newComponentIndexPlusOne =
													previousComponentIndexPlusOne + deltaComponentCount;

												s.storage.glyphs[ligatureGlyphCursor].ligatureUid = ligatureUid as uint16;
												s.storage.glyphs[ligatureGlyphCursor].ligatureComponentIndexPlusOne =
													(newComponentIndexPlusOne & 0xFFFF) as uint16;
											} else {
												break;
											}

											ligatureGlyphCursor = s.storage.glyphs[ligatureGlyphCursor].next;
										}
									}

									for (let otherIndex = 0; otherIndex < s.frameCount - 1; otherIndex++) {
										if (s.frames[otherIndex].startIndex >= s.frames[frameIndex].startIndex) {
											s.frames[otherIndex].startIndex =
												growStartIndex(s.frames[otherIndex].startIndex, growCount);
										}
									}

									kbGsubMutate(s, currentGlyph, sequentialLookupIndex, m.kbU16(ligature) as uint16,
										generatedGlyphFlags | KB_GLYPH_FLAG_LIGATURE);
									s.storage.glyphs[currentGlyph].uid = ligatureUid as uint16;
									s.storage.glyphs[currentGlyph].ligatureUid = ligatureUid as uint16;
									s.storage.glyphs[currentGlyph].ligatureComponentCount = componentCount as uint16;

									s.storage.glyphs[currentGlyph].flags =
										s.storage.glyphs[currentGlyph].flags & ~KB_GLYPH_FLAG_MULTIPLE_SUBSTITUTION;
								}

								break;
							}
						}
					} else if (lookup.type == 8) {
						const unpacked = kbUnpackReverseChainSubstitution(m, subtable, false);

						if (coverIndex < (unpacked.glyphCount as int64)) {
							const backtrackMatch = kbMatchCoverageSequence(s, lookup, regularSkipFlags,
								skipUnicodeFlags, subtable, unpacked.backtrackCoverageOffsets,
								unpacked.backtrackCount, s.storage.glyphs[currentGlyph].prev, true);
							const lookaheadMatch = kbMatchCoverageSequence(s, lookup, regularSkipFlags,
								skipUnicodeFlags, subtable, unpacked.lookaheadCoverageOffsets,
								unpacked.lookaheadCount, s.storage.glyphs[currentGlyph].next, false);
							if (backtrackMatch.matchCount == unpacked.backtrackCount &&
								lookaheadMatch.matchCount == unpacked.lookaheadCount) {
								result |= KB_SUBSTITUTION_RESULT_FLAG_MATCHED_SUBSTITUTION;
								kbGsubMutate(s, currentGlyph, sequentialLookupIndex,
									m.kbU16(unpacked.substituteGlyphIds + coverIndex * 2) as uint16,
									generatedGlyphFlags);
							}
						}
					} else {
						throw kbBoundsFail(`unhandled gsub lookup type ${lookup.type}`, subtable);
					}

					if ((result & KB_SUBSTITUTION_RESULT_FLAG_MATCHED_SUBSTITUTION) != 0) {
						s.frames[frameIndex].subtableIndex = SUBTABLE_DONE;
					}
				}

				kbSetLookupOnePastLastGlyph(s,
					(s.frames[frameIndex].startIndex as int64) + onePastLastGlyphOffset, onePastLastGlyph);
			}
		}

		s.frames[frameIndex].subtableIndex += 1;
	}

	if (s.frames[frameIndex].recordIndex < s.frames[frameIndex].recordCount) {
		const sequenceRecord = s.frames[frameIndex].records +
			(s.frames[frameIndex].recordIndex as int64) * 4;
		s.frames[frameIndex].recordIndex += 1;

		if (s.frameCount < 32) {
			let newFrame = s.frames[frameIndex];
			newFrame.lookupIndex = m.kbU16(sequenceRecord + 2);
			newFrame.subtableIndex = 0;
			newFrame.records = 0;
			newFrame.recordCount = 0;
			newFrame.recordIndex = 0;

			const sequenceIndex = m.kbU16(sequenceRecord);
			if (sequenceIndex != 0) {
				let sequenceInputIndex = 0;
				let filterGlyph = s.storage.glyphs[s.frames[frameIndex].inputGlyph].next;
				while (filterGlyph != KB_GLYPH_SENTINEL) {
					if (!kbSkipGlyph(s, filterGlyph, lookup, 0, skipUnicodeFlags)) {
						sequenceInputIndex += 1;

						if (sequenceInputIndex == sequenceIndex) {
							newFrame.inputGlyph = filterGlyph;
							break;
						}
					}

					newFrame.startIndex += 1;
					filterGlyph = s.storage.glyphs[filterGlyph].next;
				}
			}

			s.frames[s.frameCount] = newFrame;
			s.frameCount += 1;
		}
	}

	if (frameIndex == s.frameCount - 1) {
		s.frameCount -= 1;
	}

	return result;
}
