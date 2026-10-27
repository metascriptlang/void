import {
	KB_LOOKUP_FLAG_USE_MARK_FILTERING_SET,
	KB_SIZE_CLASS_DEFINITION_2,
	KB_SIZE_CHAINED_SEQUENCE_CONTEXT_1,
	KB_SIZE_CHAINED_SEQUENCE_CONTEXT_2,
	KB_SIZE_COVERAGE,
	KB_SIZE_DELTA_SET_INDEX_MAP,
	KB_SIZE_FEATURE,
	KB_SIZE_ITEM_VARIATION_DATA,
	KB_SIZE_LIGATURE,
	KB_SIZE_LOOKUP,
	KB_SIZE_PAIR_ADJUSTMENT_1,
	KB_SIZE_PAIR_ADJUSTMENT_2,
	KB_SIZE_PAIR_VALUE_RECORD,
	KB_SIZE_SEQUENCE_CONTEXT_1,
	KB_SIZE_SEQUENCE_CONTEXT_2,
	KB_SIZE_VARIATION_REGION_LIST,
	kbPopCount32,
	kbSwap16,
	kbSwap32,
	kbUn,
	kbWrap32,
} from "./blob";
import {
	kbGetAlternateSet,
	kbGetChainedClassSequenceRuleSet,
	kbGetChainedSequenceRule,
	kbGetChainedSequenceRuleSet,
	kbGetClassSequenceRule,
	kbGetClassSequenceRuleSet,
	kbGetDefaultLangsys,
	kbGetLigature,
	kbGetLigatureAttach,
	kbGetLigatureAttachAnchor,
	kbGetLigatureSet,
	kbGetSequence,
	kbGetSequenceRule,
	kbGetSequenceRuleSet,
	kbLookupBeginsWithCoverage,
	kbUnpackChainedSequenceContext3,
	kbUnpackChainedSequenceRule,
	kbUnpackReverseChainSubstitution,
	kbUnpackValueRecord,
} from "./access";

export class KbSwapContext {
	fileEnd: int64 = 0;
	pointers: uint32[] = [];
	pointerCapacity: int64 = 0;
	pointerCount: int64 = 0;
	error: boolean = false;
}

export function kbNewSwapContext(fileEnd: int64, pointerCapacity: int64): KbSwapContext {
	const context = new KbSwapContext();
	context.fileEnd = fileEnd;
	context.pointers = new Array<uint32>(pointerCapacity as int32);
	context.pointerCapacity = pointerCapacity;
	return context;
}

function u16At(m: Span<uint8>, at: int64): int64 {
	return m.kbU16(at) as int64;
}

export function kbSwapArray16Context(m: Span<uint8>, c: KbSwapContext, at: int64, count: int64): boolean {
	const ok = m.kbSwapArray16(at, count, c.fileEnd);
	if (!ok) { c.error = true; }
	return ok;
}

export function kbSwapArray32Context(m: Span<uint8>, c: KbSwapContext, at: int64, count: int64): boolean {
	const ok = m.kbSwapArray32(at, count, c.fileEnd);
	if (!ok) { c.error = true; }
	return ok;
}

export function kbAlreadyVisited(c: KbSwapContext, pointer: int64): boolean {
	let result = pointer == 0 || c.error;
	if (!result) {
		const pointer32 = pointer & 0xFFFFFFFF;
		let index: int64 = 0;
		if (c.pointerCount != 0) {
			let pointerCount = c.pointerCount;
			while (pointerCount > 1) {
				const halfCount = pointerCount / 2;
				index = (c.pointers[index + halfCount - 1] as int64) < pointer32 ? index + halfCount : index;
				pointerCount -= halfCount;
			}
			result = pointer32 == (c.pointers[index] as int64);
		}
		if (!result && c.pointerCount < c.pointerCapacity) {
			while (index < c.pointerCount && (c.pointers[index] as int64) < pointer32) { index++; }
			for (let grow = c.pointerCount; grow > index; grow--) {
				c.pointers[grow] = c.pointers[grow - 1];
			}
			c.pointers[index] = pointer32 as uint32;
			c.pointerCount += 1;
		}
	}
	return result;
}

function swapFeature(m: Span<uint8>, c: KbSwapContext, feature: int64): void {
	if (!kbAlreadyVisited(c, feature)) {
		const lookupIndices = feature + KB_SIZE_FEATURE;
		kbSwapArray16Context(m, c, feature, 2);
		kbSwapArray16Context(m, c, lookupIndices, u16At(m, feature + 2));

		const lookupIndexCount = u16At(m, feature + 2);
		for (let iter: int64 = 0; iter < lookupIndexCount; iter++) {
			for (let indexIndex: int64 = 1; indexIndex < lookupIndexCount; indexIndex++) {
				const left = m.kbU16(lookupIndices + (indexIndex - 1) * 2);
				const right = m.kbU16(lookupIndices + indexIndex * 2);
				if (left > right) {
					m.kbSetU16(lookupIndices + (indexIndex - 1) * 2, right);
					m.kbSetU16(lookupIndices + indexIndex * 2, left);
				}
			}
		}
	}
}

function swapLangsys(m: Span<uint8>, c: KbSwapContext, langsys: int64): void {
	kbSwapArray16Context(m, c, langsys, 3);
	kbSwapArray16Context(m, c, langsys + 6, u16At(m, langsys + 4));
}

function swapFeatureVariations(m: Span<uint8>, c: KbSwapContext, header: int64): void {
	const featureVariations = header + m.kbU32(header + 10);
	if (kbAlreadyVisited(c, featureVariations)) { return; }
	kbSwapArray16Context(m, c, featureVariations, 2);
	m.kbSwapU32At(featureVariations + 4);

	const records = featureVariations + 8;
	for (let variationIndex: int64 = 0; variationIndex < m.kbU32(featureVariations + 4); variationIndex++) {
		const record = records + variationIndex * 8;
		kbSwapArray32Context(m, c, record, 2);

		const set = featureVariations + m.kbU32(record);
		if (!kbAlreadyVisited(c, set)) {
			m.kbSwapU16At(set);

			const conditionOffsets = set + 2;
			kbSwapArray32Context(m, c, conditionOffsets, u16At(m, set));

			for (let conditionIndex: int64 = 0; conditionIndex < u16At(m, set); conditionIndex++) {
				const condition = set + m.kbU32(conditionOffsets + conditionIndex * 4);
				if (!kbAlreadyVisited(c, condition)) {
					kbSwapArray16Context(m, c, condition, 4);
				}
			}

			const featureSubst = featureVariations + m.kbU32(record + 4);
			if (!kbAlreadyVisited(c, featureSubst)) {
				kbSwapArray16Context(m, c, featureSubst, 3);

				const substRecords = featureSubst + 6;
				for (let substIndex: int64 = 0; substIndex < u16At(m, featureSubst + 4); substIndex++) {
					const substRecord = substRecords + substIndex * 6;
					m.kbSwapU16At(substRecord);
					m.kbSwapU32At(substRecord + 2);

					swapFeature(m, c, featureSubst + m.kbU32(substRecord + 2));
				}
			}
		}
	}
}

export function kbSwapGsubGposCommon(m: Span<uint8>, c: KbSwapContext, header: int64): void {
	kbSwapArray16Context(m, c, header, 5);

	if (u16At(m, header + 2) == 1) {
		m.kbSwapU32At(header + 10);
	}

	const scriptList = header + u16At(m, header + 4);
	if (!kbAlreadyVisited(c, scriptList)) {
		m.kbSwapU16At(scriptList);

		const scriptRecords = scriptList + 2;
		for (let it: int64 = 0; it < u16At(m, scriptList); it++) {
			const scriptRecord = scriptRecords + it * 6;
			m.kbSwapU16At(scriptRecord + 4);

			const script = scriptList + u16At(m, scriptRecord + 4);
			if (!kbAlreadyVisited(c, script)) {
				m.kbSwapU16At(script);
				m.kbSwapU16At(script + 2);

				const defaultLangsys = kbGetDefaultLangsys(m, script);
				if (defaultLangsys != 0 && !kbAlreadyVisited(c, defaultLangsys)) {
					swapLangsys(m, c, defaultLangsys);
				}

				const langsysRecords = script + 4;
				for (let langsysIndex: int64 = 0; langsysIndex < u16At(m, script + 2); langsysIndex++) {
					const langsysRecord = langsysRecords + langsysIndex * 6;
					m.kbSwapU16At(langsysRecord + 4);

					const langsys = script + u16At(m, langsysRecord + 4);
					if (!kbAlreadyVisited(c, langsys)) {
						swapLangsys(m, c, langsys);
					}
				}
			}
		}

		if (u16At(m, header + 2) == 1 && m.kbU32(header + 10) != 0) {
			swapFeatureVariations(m, c, header);
		}
	}

	const featureList = header + u16At(m, header + 6);
	if (!kbAlreadyVisited(c, featureList)) {
		m.kbSwapU16At(featureList);
		const featureRecords = featureList + 2;
		for (let featureRecordIndex: int64 = 0; featureRecordIndex < u16At(m, featureList); featureRecordIndex++) {
			const featureRecord = featureRecords + featureRecordIndex * 6;
			if (!kbAlreadyVisited(c, featureRecord)) {
				m.kbSwapU16At(featureRecord + 4);
				swapFeature(m, c, featureList + u16At(m, featureRecord + 4));
			}
		}
	}
}

export function kbSwapLookup(m: Span<uint8>, c: KbSwapContext, lookup: int64): boolean {
	let result = false;
	if (!kbAlreadyVisited(c, lookup)) {
		result = true;
		kbSwapArray16Context(m, c, lookup, 3);
		const subtableOffsets = lookup + KB_SIZE_LOOKUP;
		let u16Count = u16At(m, lookup + 4);
		if ((m.kbU16(lookup + 2) & KB_LOOKUP_FLAG_USE_MARK_FILTERING_SET) != 0) {
			u16Count += 1;
		}
		kbSwapArray16Context(m, c, subtableOffsets, u16Count);
	}
	return result;
}

export function kbSwapCoverage(m: Span<uint8>, c: KbSwapContext, coverage: int64): void {
	if (!kbAlreadyVisited(c, coverage)) {
		kbSwapArray16Context(m, c, coverage, 2);

		let u16Count: int64 = 0;
		const format = m.kbU16(coverage);
		if (format == 1) {
			u16Count = u16At(m, coverage + 2);
		} else if (format == 2) {
			u16Count = u16At(m, coverage + 2) * 3;
		}
		kbSwapArray16Context(m, c, coverage + KB_SIZE_COVERAGE, u16Count);
	}
}

function swapAnchor(m: Span<uint8>, c: KbSwapContext, anchor: int64): void {
	if (!kbAlreadyVisited(c, anchor)) {
		m.kbSwapU16At(anchor);

		let u16Count: int64 = 2;
		const format = m.kbU16(anchor);
		if (format == 2) {
			u16Count = 3;
		} else if (format == 3) {
			u16Count = 4;
		}
		kbSwapArray16Context(m, c, anchor + 2, u16Count);
	}
}

function swapBaseArray(
	m: Span<uint8>,
	c: KbSwapContext,
	markClassCount: int64,
	array: int64,
): void {
	if (!kbAlreadyVisited(c, array)) {
		m.kbSwapU16At(array);

		const baseAnchorOffsets = array + 2;
		kbSwapArray16Context(m, c, baseAnchorOffsets, kbUn(kbWrap32(u16At(m, array) * markClassCount)));

		for (let offsetIndex: int64 = 0; offsetIndex < u16At(m, array) * markClassCount; offsetIndex++) {
			const offset = u16At(m, baseAnchorOffsets + offsetIndex * 2);
			if (offset != 0) {
				swapAnchor(m, c, array + offset);
			}
		}
	}
}

function swapDevice(m: Span<uint8>, c: KbSwapContext, device: int64): void {
	if (!kbAlreadyVisited(c, device)) {
		kbSwapArray16Context(m, c, device, 3);
	}
}

function swapValueRecord(
	m: Span<uint8>,
	c: KbSwapContext,
	parent: int64,
	valueFormat: int32,
	record: int64,
): int64 {
	if (valueFormat == 0) { return 0; }
	kbSwapArray16Context(m, c, record, kbPopCount32(valueFormat));

	const unpacked = kbUnpackValueRecord(m, parent, valueFormat, record);
	swapDevice(m, c, unpacked.placementXDevice);
	swapDevice(m, c, unpacked.placementYDevice);
	swapDevice(m, c, unpacked.advanceXDevice);
	swapDevice(m, c, unpacked.advanceYDevice);
	return unpacked.size as int64;
}

export function kbSwapDeltaSetIndexMap(m: Span<uint8>, c: KbSwapContext, map: int64): void {
	if (!kbAlreadyVisited(c, map)) {
		const format = m.kbU8(map);
		const minimumSize = KB_SIZE_DELTA_SET_INDEX_MAP + (format == 0 ? 2 : 4);
		const bytesPerEntry = ((m.kbU8(map + 1) >> 4) & 0x3) + 1;

		if (map + minimumSize <= c.fileEnd) {
			let entries: int64 = 0;
			let entryCount: int64 = 0;

			if (format == 0) {
				m.kbSwapU16At(map + 2);
				entries = map + 4;
				entryCount = u16At(m, map + 2);
			} else if (format == 1) {
				m.kbSwapU32At(map + 2);
				entries = map + 6;
				entryCount = m.kbU32(map + 2);
			}

			if (entries + entryCount * (bytesPerEntry as int64) > c.fileEnd) {
				c.error = true;
			}

			match (bytesPerEntry) {
				1 => {},
				2 => { kbSwapArray16Context(m, c, entries, entryCount); },
				4 => { kbSwapArray32Context(m, c, entries, entryCount); },
				_ => { c.error = true; },
			}
		} else {
			c.error = true;
		}
	}
}

export function kbSwapItemVariationStore(m: Span<uint8>, c: KbSwapContext, store: int64): void {
	if (!kbAlreadyVisited(c, store)) {
		const regionListOffsetAt = store + 2;
		const dataCountAt = store + 6;
		const dataOffsets = store + 8;

		const variationRegionListOffset = kbSwap32(m.kbU32(regionListOffsetAt));
		const itemVariationDataCount = kbSwap16(m.kbU16(dataCountAt)) as int64;

		const variationRegionList = store + variationRegionListOffset;
		if (!kbAlreadyVisited(c, variationRegionList)) {
			const regionAxes = variationRegionList + KB_SIZE_VARIATION_REGION_LIST;

			kbSwapArray16Context(m, c, variationRegionList, 2);
			kbSwapArray16Context(m, c, regionAxes, kbUn(kbWrap32(
				kbWrap32(u16At(m, variationRegionList + 2) * u16At(m, variationRegionList)) * 3)));
		}

		if (kbSwapArray32Context(m, c, dataOffsets, itemVariationDataCount)) {
			for (let dataIndex: int64 = 0; dataIndex < itemVariationDataCount; dataIndex++) {
				const offset = m.kbU32(dataOffsets + dataIndex * 4);

				if (offset != 0) {
					const data = store + offset;

					if (!kbAlreadyVisited(c, data)) {
						kbSwapArray16Context(m, c, data, 3);

						const regionIndices = data + KB_SIZE_ITEM_VARIATION_DATA;
						if (kbSwapArray16Context(m, c, regionIndices, u16At(m, data + 4))) {
							const wordDeltaCount = u16At(m, data + 2) & 0x7FFF;

							let deltaRow = regionIndices + u16At(m, data + 4) * 2;
							const deltaRowSize = u16At(m, data + 4) + wordDeltaCount;
							for (let dataItemIndex: int64 = 0; dataItemIndex < u16At(m, data); dataItemIndex++) {
								if (!kbSwapArray16Context(m, c, deltaRow, wordDeltaCount)) {
									break;
								}
								deltaRow += deltaRowSize;
							}
						}
					}
				}
			}
		}

		m.kbSwapU16At(store);
		m.kbSetU32(regionListOffsetAt, variationRegionListOffset);
		m.kbSetU16(dataCountAt, itemVariationDataCount as int32);
	}
}

function swapMarkArray(m: Span<uint8>, c: KbSwapContext, markArray: int64): void {
	if (!kbAlreadyVisited(c, markArray)) {
		m.kbSwapU16At(markArray);
		kbSwapArray16Context(m, c, markArray + 2, u16At(m, markArray) * 2);

		const markRecords = markArray + 2;
		for (let markRecordIndex: int64 = 0; markRecordIndex < u16At(m, markArray); markRecordIndex++) {
			const markRecord = markRecords + markRecordIndex * 4;
			swapAnchor(m, c, markArray + u16At(m, markRecord + 2));
		}
	}
}

function swapChainedSequenceRuleSet(m: Span<uint8>, c: KbSwapContext, set: int64): void {
	if (set != 0 && !kbAlreadyVisited(c, set)) {
		m.kbSwapU16At(set);
		kbSwapArray16Context(m, c, set + 2, u16At(m, set));

		for (let ruleIndex: int64 = 0; ruleIndex < u16At(m, set); ruleIndex++) {
			const rule = kbGetChainedSequenceRule(m, set, ruleIndex);

			if (!kbAlreadyVisited(c, rule)) {
				const unpacked = kbUnpackChainedSequenceRule(m, rule, true);
				const u16Count = (unpacked.backtrackCount as int64) + (unpacked.inputCount as int64) +
					(unpacked.lookaheadCount as int64) + (unpacked.recordCount as int64) * 2 + 3;
				kbSwapArray16Context(m, c, rule, u16Count);
			}
		}
	}
}

export function kbSwapClassDefinition(m: Span<uint8>, c: KbSwapContext, base: int64): void {
	if (!kbAlreadyVisited(c, base)) {
		m.kbSwapU16At(base);

		const format = m.kbU16(base);
		if (format == 1) {
			kbSwapArray16Context(m, c, base + 2, 2);
			kbSwapArray16Context(m, c, base + 6, u16At(m, base + 4));
		} else if (format == 2) {
			m.kbSwapU16At(base + 2);
			kbSwapArray16Context(m, c, base + KB_SIZE_CLASS_DEFINITION_2, u16At(m, base + 2) * 3);
		}
	}
}

function swapSequenceContextSubtable(m: Span<uint8>, c: KbSwapContext, base: int64): void {
	const format = m.kbU16(base);
	if (format == 1) {
		m.kbSwapU16At(base + 4);
		kbSwapArray16Context(m, c, base + KB_SIZE_SEQUENCE_CONTEXT_1, u16At(m, base + 4));

		for (let setIndex: int64 = 0; setIndex < u16At(m, base + 4); setIndex++) {
			const set = kbGetSequenceRuleSet(m, base, setIndex);

			if (set != 0 && !kbAlreadyVisited(c, set)) {
				m.kbSwapU16At(set);
				kbSwapArray16Context(m, c, set + 2, u16At(m, set));

				for (let ruleIndex: int64 = 0; ruleIndex < u16At(m, set); ruleIndex++) {
					const rule = kbGetSequenceRule(m, set, ruleIndex);

					if (!kbAlreadyVisited(c, rule)) {
						kbSwapArray16Context(m, c, rule, 2);
						kbSwapArray16Context(m, c, rule + 4,
							kbUn(u16At(m, rule) - 1 + u16At(m, rule + 2) * 2));
					}
				}
			}
		}
	} else if (format == 2) {
		kbSwapArray16Context(m, c, base + 4, 2);
		kbSwapArray16Context(m, c, base + KB_SIZE_SEQUENCE_CONTEXT_2, u16At(m, base + 6));

		const classDefBase = base + u16At(m, base + 4);
		kbSwapClassDefinition(m, c, classDefBase);

		for (let setIndex: int64 = 0; setIndex < u16At(m, base + 6); setIndex++) {
			const set = kbGetClassSequenceRuleSet(m, base, setIndex);

			if (set != 0 && !kbAlreadyVisited(c, set)) {
				m.kbSwapU16At(set);
				kbSwapArray16Context(m, c, set + 2, u16At(m, set));

				for (let ruleIndex: int64 = 0; ruleIndex < u16At(m, set); ruleIndex++) {
					const rule = kbGetClassSequenceRule(m, set, ruleIndex);

					if (!kbAlreadyVisited(c, rule)) {
						kbSwapArray16Context(m, c, rule, 2);
						kbSwapArray16Context(m, c, rule + 4,
							kbUn(u16At(m, rule) - 1 + 2 * u16At(m, rule + 2)));
					}
				}
			}
		}
	} else if (format == 3) {
		kbSwapArray16Context(m, c, base + 2, 2);
		kbSwapArray16Context(m, c, base + 6, u16At(m, base + 2) + 2 * u16At(m, base + 4));

		const coverageOffsets = base + 6;
		for (let coverageIndex: int64 = 0; coverageIndex < u16At(m, base + 2); coverageIndex++) {
			kbSwapCoverage(m, c, base + u16At(m, coverageOffsets + coverageIndex * 2));
		}
	}
}

function swapChainedSequenceContextSubtable(m: Span<uint8>, c: KbSwapContext, base: int64): void {
	const format = m.kbU16(base);
	if (format == 1) {
		m.kbSwapU16At(base + 4);
		kbSwapArray16Context(m, c, base + KB_SIZE_CHAINED_SEQUENCE_CONTEXT_1, u16At(m, base + 4));

		for (let setIndex: int64 = 0; setIndex < u16At(m, base + 4); setIndex++) {
			swapChainedSequenceRuleSet(m, c, kbGetChainedSequenceRuleSet(m, base, setIndex));
		}
	} else if (format == 2) {
		kbSwapArray16Context(m, c, base + 4, 4);
		kbSwapArray16Context(m, c, base + KB_SIZE_CHAINED_SEQUENCE_CONTEXT_2, u16At(m, base + 10));

		kbSwapClassDefinition(m, c, base + u16At(m, base + 4));
		kbSwapClassDefinition(m, c, base + u16At(m, base + 6));
		kbSwapClassDefinition(m, c, base + u16At(m, base + 8));

		for (let setIndex: int64 = 0; setIndex < u16At(m, base + 10); setIndex++) {
			swapChainedSequenceRuleSet(m, c, kbGetChainedClassSequenceRuleSet(m, base, setIndex));
		}
	} else if (format == 3) {
		const unpacked = kbUnpackChainedSequenceContext3(m, base, true);

		const u16Count = (unpacked.backtrackCount as int64) + (unpacked.inputCount as int64) +
			(unpacked.lookaheadCount as int64) + (unpacked.recordCount as int64) * 2 + 4;
		kbSwapArray16Context(m, c, base + 2, u16Count);

		for (let index: int64 = 0; index < (unpacked.backtrackCount as int64); index++) {
			kbSwapCoverage(m, c, base + u16At(m, unpacked.backtrackCoverageOffsets + index * 2));
		}
		for (let index: int64 = 0; index < (unpacked.inputCount as int64); index++) {
			kbSwapCoverage(m, c, base + u16At(m, unpacked.inputCoverageOffsets + index * 2));
		}
		for (let index: int64 = 0; index < (unpacked.lookaheadCount as int64); index++) {
			kbSwapCoverage(m, c, base + u16At(m, unpacked.lookaheadCoverageOffsets + index * 2));
		}
	}
}

export function kbSwapGsubLookupSubtable(
	m: Span<uint8>,
	c: KbSwapContext,
	lookupTypeIn: int32,
	baseIn: int64,
): void {
	let lookupType = lookupTypeIn;
	let base = baseIn;
	let swap = !kbAlreadyVisited(c, base);
	while (swap && lookupType == 7) {
		m.kbSwapU16At(base);
		m.kbSwapU16At(base + 2);
		m.kbSwapU32At(base + 4);

		const next = base + m.kbU32(base + 4);
		lookupType = m.kbU16(base + 2);
		base = next;

		swap = !kbAlreadyVisited(c, base);
	}

	if (swap) {
		m.kbSwapU16At(base);

		if (kbLookupBeginsWithCoverage(false, lookupType, m.kbU16(base))) {
			m.kbSwapU16At(base + 2);
			kbSwapCoverage(m, c, base + u16At(m, base + 2));
		}

		match (lookupType) {
			1 => {
				m.kbSwapU16At(base + 4);

				if (m.kbU16(base) == 2) {
					kbSwapArray16Context(m, c, base + 6, u16At(m, base + 4));
				}
			},
			2 => {
				m.kbSwapU16At(base + 4);
				kbSwapArray16Context(m, c, base + 6, u16At(m, base + 4));

				for (let sequenceIndex: int64 = 0; sequenceIndex < u16At(m, base + 4); sequenceIndex++) {
					const sequence = kbGetSequence(m, base, sequenceIndex);

					if (!kbAlreadyVisited(c, sequence)) {
						m.kbSwapU16At(sequence);
						kbSwapArray16Context(m, c, sequence + 2, u16At(m, sequence));
					}
				}
			},
			3 => {
				m.kbSwapU16At(base + 4);
				kbSwapArray16Context(m, c, base + 6, u16At(m, base + 4));

				for (let setIndex: int64 = 0; setIndex < u16At(m, base + 4); setIndex++) {
					const set = kbGetAlternateSet(m, base, setIndex);

					if (!kbAlreadyVisited(c, set)) {
						m.kbSwapU16At(set);
						kbSwapArray16Context(m, c, set + 2, u16At(m, set));
					}
				}
			},
			4 => {
				m.kbSwapU16At(base + 4);
				kbSwapArray16Context(m, c, base + 6, u16At(m, base + 4));

				for (let setIndex: int64 = 0; setIndex < u16At(m, base + 4); setIndex++) {
					const set = kbGetLigatureSet(m, base, setIndex);

					if (!kbAlreadyVisited(c, set)) {
						m.kbSwapU16At(set);
						kbSwapArray16Context(m, c, set + 2, u16At(m, set));

						for (let ligatureIndex: int64 = 0; ligatureIndex < u16At(m, set); ligatureIndex++) {
							const ligature = kbGetLigature(m, set, ligatureIndex);

							if (!kbAlreadyVisited(c, ligature)) {
								kbSwapArray16Context(m, c, ligature, 2);
								kbSwapArray16Context(m, c, ligature + KB_SIZE_LIGATURE,
									kbUn(u16At(m, ligature + 2) - 1));
							}
						}
					}
				}
			},
			5 => { swapSequenceContextSubtable(m, c, base); },
			6 => { swapChainedSequenceContextSubtable(m, c, base); },
			8 => {
				const unpacked = kbUnpackReverseChainSubstitution(m, base, true);

				const u16Count = (unpacked.backtrackCount as int64) + (unpacked.glyphCount as int64) +
					(unpacked.lookaheadCount as int64) + 3;
				kbSwapArray16Context(m, c, base + 4, u16Count);

				for (let index: int64 = 0; index < (unpacked.backtrackCount as int64); index++) {
					kbSwapCoverage(m, c, base + u16At(m, unpacked.backtrackCoverageOffsets + index * 2));
				}
				for (let index: int64 = 0; index < (unpacked.lookaheadCount as int64); index++) {
					kbSwapCoverage(m, c, base + u16At(m, unpacked.lookaheadCoverageOffsets + index * 2));
				}
			},
			_ => {},
		}
	}
}

export function kbSwapGposLookupSubtable(
	m: Span<uint8>,
	c: KbSwapContext,
	lookupType: int32,
	base: int64,
): void {
	if (!kbAlreadyVisited(c, base)) {
		m.kbSwapU16At(base);

		if (kbLookupBeginsWithCoverage(true, lookupType, m.kbU16(base))) {
			m.kbSwapU16At(base + 2);
			kbSwapCoverage(m, c, base + u16At(m, base + 2));
		}

		match (lookupType) {
			1 => {
				m.kbSwapU16At(base + 4);

				if (m.kbU16(base) == 1) {
					swapValueRecord(m, c, base, m.kbU16(base + 4), base + 6);
				} else if (m.kbU16(base) == 2) {
					m.kbSwapU16At(base + 6);

					let at = base + 8;
					for (let recordIndex: int64 = 0; recordIndex < u16At(m, base + 6); recordIndex++) {
						const size = swapValueRecord(m, c, base, m.kbU16(base + 4), at);
						at += size * 2;
					}
				}
			},
			2 => {
				if (m.kbU16(base) == 1) {
					kbSwapArray16Context(m, c, base + 4, 3);

					const setOffsets = base + KB_SIZE_PAIR_ADJUSTMENT_1;
					kbSwapArray16Context(m, c, setOffsets, u16At(m, base + 8));

					const size1 = kbPopCount32(m.kbU16(base + 4));
					const size2 = kbPopCount32(m.kbU16(base + 6));
					const pairRecordSize = size1 + size2 + 1;

					for (let setIndex: int64 = 0; setIndex < u16At(m, base + 8); setIndex++) {
						const set = base + u16At(m, setOffsets + setIndex * 2);

						if (!kbAlreadyVisited(c, set)) {
							m.kbSwapU16At(set);

							const at = set + 2;

							for (let recordIndex: int64 = 0; recordIndex < u16At(m, set); recordIndex++) {
								const pairRecord = at + recordIndex * pairRecordSize * 2;

								m.kbSwapU16At(pairRecord);
								let record = pairRecord + KB_SIZE_PAIR_VALUE_RECORD;

								const size = swapValueRecord(m, c, set, m.kbU16(base + 4), record);
								record += size * 2;
								swapValueRecord(m, c, set, m.kbU16(base + 6), record);
							}
						}
					}
				} else if (m.kbU16(base) == 2) {
					kbSwapArray16Context(m, c, base + 4, 6);

					kbSwapClassDefinition(m, c, base + u16At(m, base + 8));
					kbSwapClassDefinition(m, c, base + u16At(m, base + 10));

					const size1 = kbPopCount32(m.kbU16(base + 4));
					const size2 = kbPopCount32(m.kbU16(base + 6));

					let recordPair = base + KB_SIZE_PAIR_ADJUSTMENT_2;
					for (
						let recordIndex: int64 = 0;
						recordIndex < u16At(m, base + 12) * u16At(m, base + 14);
						recordIndex++
					) {
						swapValueRecord(m, c, base, m.kbU16(base + 4), recordPair);
						recordPair += size1 * 2;

						swapValueRecord(m, c, base, m.kbU16(base + 6), recordPair);
						recordPair += size2 * 2;
					}
				}
			},
			3 => {
				m.kbSwapU16At(base + 4);
				kbSwapArray16Context(m, c, base + 6, u16At(m, base + 4) * 2);

				const entryExits = base + 6;
				for (let entryExitIndex: int64 = 0; entryExitIndex < u16At(m, base + 4); entryExitIndex++) {
					const entryExit = entryExits + entryExitIndex * 4;

					if (m.kbU16(entryExit) != 0) {
						swapAnchor(m, c, base + u16At(m, entryExit));
					}

					if (m.kbU16(entryExit + 2) != 0) {
						swapAnchor(m, c, base + u16At(m, entryExit + 2));
					}
				}
			},
			4 | 6 => {
				kbSwapArray16Context(m, c, base + 4, 4);

				kbSwapCoverage(m, c, base + u16At(m, base + 4));
				swapMarkArray(m, c, base + u16At(m, base + 8));
				swapBaseArray(m, c, u16At(m, base + 6), base + u16At(m, base + 10));
			},
			5 => {
				kbSwapArray16Context(m, c, base + 4, 4);

				kbSwapCoverage(m, c, base + u16At(m, base + 4));
				swapMarkArray(m, c, base + u16At(m, base + 8));

				const ligatureArray = base + u16At(m, base + 10);
				if (!kbAlreadyVisited(c, ligatureArray)) {
					m.kbSwapU16At(ligatureArray);
					kbSwapArray16Context(m, c, ligatureArray + 2, u16At(m, ligatureArray));

					for (let attachIndex: int64 = 0; attachIndex < u16At(m, ligatureArray); attachIndex++) {
						const attach = kbGetLigatureAttach(m, ligatureArray, attachIndex);

						if (!kbAlreadyVisited(c, attach)) {
							m.kbSwapU16At(attach);

							const attachAnchorOffsets = attach + 2;
							kbSwapArray16Context(m, c, attachAnchorOffsets,
								kbUn(kbWrap32(u16At(m, attach) * u16At(m, base + 6))));

							for (let componentIndex: int64 = 0; componentIndex < u16At(m, attach); componentIndex++) {
								for (let markClass: int64 = 0; markClass < u16At(m, base + 6); markClass++) {
									const anchor = kbGetLigatureAttachAnchor(m, base, attach, markClass as int32,
										componentIndex);
									swapAnchor(m, c, anchor);
								}
							}
						}
					}
				}
			},
			7 => { swapSequenceContextSubtable(m, c, base); },
			8 => { swapChainedSequenceContextSubtable(m, c, base); },
			9 => {
				m.kbSwapU16At(base + 2);
				m.kbSwapU32At(base + 4);

				kbSwapGposLookupSubtable(m, c, m.kbU16(base + 2), base + m.kbU32(base + 4));
			},
			_ => {},
		}
	}
}
