import { kbGetLookup, kbGetLookupList, kbUnpackLookup } from "./access";
import {
	KB_BLOB_TABLE_ID_GDEF,
	KB_BLOB_TABLE_ID_GPOS,
	KB_BLOB_TABLE_ID_GSUB,
	KB_BLOB_TABLE_ID_HEAD,
	KB_BLOB_TABLE_ID_HHEA,
	KB_BLOB_TABLE_ID_HMTX,
	KB_BLOB_TABLE_ID_HVAR,
	kbBlobTableData,
	kbU16,
	kbU32,
	kbU8,
} from "./blob";
import { KbShapeConfig } from "./config";
import { kbDoSingleAdjustment } from "./gpos";
import { kbDoSubstitution } from "./gsub";
import { KB_GLYPH_CLASS_MARK, KB_GLYPH_SENTINEL } from "./glyph";
import { kbDllistReverseSublist } from "./dllist";
import { kbItemVariationStoreDelta, kbRound32 } from "./resolve";
import {
	KbScratch,
	kbBeginLookupApplication,
	kbBucketEntry,
	kbBucketGlyph,
	kbBucketLength,
	kbBucketedGlyphIsValid,
	kbEndLookupApplication,
	kbFreeGlyph,
	kbFreeGlyphBucket,
	kbSortGlyphBucket,
	kbUnbucketGlyph,
} from "./scratch";
import { kbSetGlyphPreserveLinksAndUserId } from "./normalize";
import {
	KB_DIRECTION_RTL,
	KB_GLYPH_FEATURE_MASK,
	KB_GLYPH_FLAG_GENERATED_BY_GSUB,
	KB_GLYPH_FLAG_PREF,
	KB_GLYPH_FLAG_RPHF,
	KB_SHAPER_ARABIC,
	KB_SHAPER_DEFAULT,
	KB_SHAPER_HEBREW,
	KB_SHAPER_MYANMAR,
	KB_SHAPER_USE,
	KB_UNICODE_FLAG_DEFAULT_IGNORABLE,
	KB_USE_GLYPH_FEATURE_MASK,
} from "./shapeTables";


export function kbBeginGsub(s: KbScratch): void {
	const storage = s.storage;
	const sortKeyInterval: uint64 = 0x10000;
	let runningSortKey: uint64 = sortKeyInterval;

	let glyph = storage.glyphs[KB_GLYPH_SENTINEL].next;
	while (glyph != KB_GLYPH_SENTINEL) {
		storage.glyphs[glyph].sortKey = (runningSortKey & 0xFFFFFFFF) as uint32;
		storage.glyphs[glyph].sortKeyInterval = sortKeyInterval as uint32;

		kbBucketGlyph(s, glyph, 0);

		runningSortKey += sortKeyInterval;
		glyph = storage.glyphs[glyph].next;
	}
}

function currentFeatureStageIndex(s: KbScratch): int32 {
	return (s.featureStagesRead as int32) - 1;
}

export function kbGsubFeatures(s: KbScratch, m: Span<uint8>, config: KbShapeConfig): void {
	const storage = s.storage;
	const lookupList = kbGetLookupList(m, m.kbBlobTableData(KB_BLOB_TABLE_ID_GSUB));

	const filterMask = config.shaper == KB_SHAPER_USE ? KB_USE_GLYPH_FEATURE_MASK : KB_GLYPH_FEATURE_MASK;

	const stageIndex = currentFeatureStageIndex(s);
	const first = config.featureStageFirstLookupIndices[stageIndex] as int32;
	const onePastLast = config.featureStageFirstLookupIndices[stageIndex + 1] as int32;
	for (let sequentialLookupIndex = first; sequentialLookupIndex < onePastLast; sequentialLookupIndex++) {
		const sequentialLookup = config.sequentialLookups[sequentialLookupIndex];
		const lookupIndex = sequentialLookup.lookupIndex as int32;
		const skipFlags = sequentialLookup.skipFlags;
		const glyphFilter = sequentialLookup.glyphFilter;

		if (kbBucketLength(s, sequentialLookupIndex) != 0) {
			const packedLookup = kbGetLookup(m, lookupList, lookupIndex as int64);
			const lookupType = m.kbU16(packedLookup);
			const lookupTypeIs8 = lookupType == 8;

			if (lookupType >= 4) {
				kbSortGlyphBucket(s, sequentialLookupIndex);
			}

			const count = kbBucketLength(s, sequentialLookupIndex);
			for (let step = 0; step < count; step++) {
				const entry = kbBucketEntry(s, sequentialLookupIndex, lookupTypeIs8 ? count - 1 - step : step);

				if (kbBucketedGlyphIsValid(entry)) {
					const glyph = entry.glyph;
					const featureValue = entry.featureValue;
					const glyphFlags = storage.glyphs[glyph].flags;
					const prev = storage.glyphs[glyph].prev;

					kbBeginLookupApplication(s, glyph);
					const effectiveGlyphFilter = glyphFilter & filterMask;

					if ((glyphFlags & effectiveGlyphFilter) == effectiveGlyphFilter) {
						s.frames[0] = {
							inputGlyph: glyph, startIndex: 0, lookupIndex, subtableIndex: 0, records: 0,
							recordCount: 0, recordIndex: 0,
						};
						s.frameCount = 1;

						while (s.frameCount != 0) {
							const generatedGlyphFlags = glyphFilter & (KB_GLYPH_FLAG_RPHF | KB_GLYPH_FLAG_PREF);
							kbDoSubstitution(s, lookupList, sequentialLookupIndex, featureValue as int32, false,
								skipFlags, generatedGlyphFlags);
						}
					}

					const end = kbEndLookupApplication(s);

					let matched = storage.glyphs[prev].next;
					while (matched != end) {
						if (storage.glyphs[matched].bucketedPlusOne != 0 &&
							(storage.glyphs[matched].bucketedBucketIndex as int32) == sequentialLookupIndex) {
							kbUnbucketGlyph(s, matched);
							kbBucketGlyph(s, matched, sequentialLookupIndex + 1);
						}
						matched = storage.glyphs[matched].next;
					}
				}
			}
		}

		kbFreeGlyphBucket(s, sequentialLookupIndex);
	}

	s.sequentialLookupIndexIndex = onePastLast as uint32;
}

export function kbGposMetrics(s: KbScratch, m: Span<uint8>, config: KbShapeConfig): void {
	const storage = s.storage;
	const clearMarkAdvances = config.shaper == KB_SHAPER_MYANMAR || config.shaper == KB_SHAPER_USE;

	const hea = m.kbBlobTableData(KB_BLOB_TABLE_ID_HHEA);
	const mtx = m.kbBlobTableData(KB_BLOB_TABLE_ID_HMTX);
	const hvar = m.kbBlobTableData(KB_BLOB_TABLE_ID_HVAR);
	const hvarStore = hvar != 0 ? hvar + m.kbU32(hvar + 4) : 0;

	const hasLongMetrics = hea != 0 && mtx != 0;
	const metricCount = hasLongMetrics ? m.kbU16(hea + 34) as int64 : 0;

	let defaultAdvance: int32 = 1024;
	const head = m.kbBlobTableData(KB_BLOB_TABLE_ID_HEAD);
	if (head != 0) {
		defaultAdvance = m.kbU16(head + 18) / 2;
	}

	let glyph = storage.glyphs[KB_GLYPH_SENTINEL].next;
	while (glyph != KB_GLYPH_SENTINEL) {
		storage.glyphs[glyph].markOrdering = 0;

		let advance = defaultAdvance;
		if (hasLongMetrics) {
			const id = storage.glyphs[glyph].id as int64;

			if ((storage.glyphs[glyph].flags & KB_GLYPH_FLAG_GENERATED_BY_GSUB) == 0 &&
				(storage.glyphs[glyph].unicodeFlags & KB_UNICODE_FLAG_DEFAULT_IGNORABLE) != 0) {
				advance = 0;
			} else if (id < metricCount) {
				advance = m.kbU16(mtx + id * 4);
			} else {
				advance = m.kbU16(mtx + (metricCount - 1) * 4);
			}
		}

		if (hvar != 0) {
			let outerIndex: int64 = 0;
			let innerIndex: int64 = storage.glyphs[glyph].id as int64;

			const advanceMapOffset = m.kbU32(hvar + 8);
			if (advanceMapOffset != 0) {
				const map = hvar + advanceMapOffset;
				let mapCount: int64 = 0;
				let entries: int64 = 0;

				const format = m.kbU8(map);
				if (format == 0) {
					mapCount = m.kbU16(map + 2);
					entries = map + 4;
				} else if (format == 1) {
					mapCount = m.kbU32(map + 2);
					entries = map + 6;
				}

				if (mapCount != 0) {
					const mapLookupIndex = innerIndex < mapCount ? innerIndex : mapCount - 1;
					const entryFormat = m.kbU8(map + 1);
					const bytesPerEntry = ((entryFormat >> 4) & 3) + 1;
					const bitsPerInnerIndex = (entryFormat & 0xF) + 1;

					const at = entries + mapLookupIndex * bytesPerEntry;
					let lookupEntry: int64 = 0;
					if (bytesPerEntry == 1) {
						lookupEntry = m.kbU8(at);
					} else if (bytesPerEntry == 2) {
						lookupEntry = m.kbU16(at);
					} else if (bytesPerEntry == 4) {
						lookupEntry = m.kbU32(at);
					}

					innerIndex = lookupEntry & (((1 as int64) << (bitsPerInnerIndex as int64)) - 1);
					outerIndex = lookupEntry >> (bitsPerInnerIndex as int64);
				}
			}

			const delta: float32 = s.hasVariationVector ? kbItemVariationStoreDelta(m, hvarStore, outerIndex, innerIndex,
				s.variationVectorNormalized) : 0;
			advance = (advance + kbRound32(delta)) & 0xFFFF;
		}

		if (!clearMarkAdvances || (storage.glyphs[glyph].classValue as int32) != KB_GLYPH_CLASS_MARK) {
			storage.glyphs[glyph].advanceX = advance;
		}

		glyph = storage.glyphs[glyph].next;
	}
}

export function kbGposFeatures(s: KbScratch, m: Span<uint8>, config: KbShapeConfig): void {
	const storage = s.storage;
	const gpos = m.kbBlobTableData(KB_BLOB_TABLE_ID_GPOS);
	const gdef = m.kbBlobTableData(KB_BLOB_TABLE_ID_GDEF);
	const lookupList = kbGetLookupList(m, gpos);

	const stageIndex = currentFeatureStageIndex(s);
	const first = config.featureStageFirstLookupIndices[stageIndex] as int32;
	const onePastLast = config.featureStageFirstLookupIndices[stageIndex + 1] as int32;
	for (let sequentialLookupIndex = first; sequentialLookupIndex < onePastLast; sequentialLookupIndex++) {
		const sequentialLookup = config.sequentialLookups[sequentialLookupIndex];
		const lookupIndex = sequentialLookup.lookupIndex as int32;
		const skipFlags = sequentialLookup.skipFlags;

		if (kbBucketLength(s, sequentialLookupIndex) != 0) {
			const packedLookup = kbGetLookup(m, lookupList, lookupIndex as int64);
			const lookup = kbUnpackLookup(m, gdef, packedLookup);

			if (m.kbU16(packedLookup) >= 2) {
				kbSortGlyphBucket(s, sequentialLookupIndex);
			}

			const count = kbBucketLength(s, sequentialLookupIndex);
			for (let entryIndex = 0; entryIndex < count; entryIndex++) {
				const entry = kbBucketEntry(s, sequentialLookupIndex, entryIndex);

				if (kbBucketedGlyphIsValid(entry)) {
					const glyph = entry.glyph;
					kbBeginLookupApplication(s, glyph);

					for (let subtableIndex = 0; subtableIndex < lookup.subtableCount; subtableIndex++) {
						const subtable = packedLookup + m.kbU16(lookup.subtableOffsets + (subtableIndex as int64) * 2);
						if (kbDoSingleAdjustment(s, lookupList, lookupIndex as int64, subtableIndex as int64,
							lookup, subtable, glyph, 0, skipFlags)) {
							break;
						}
					}

					const end = kbEndLookupApplication(s);

					let matched = glyph;
					while (matched != end) {
						if (storage.glyphs[matched].bucketedPlusOne != 0 &&
							(storage.glyphs[matched].bucketedBucketIndex as int32) == sequentialLookupIndex) {
							kbUnbucketGlyph(s, matched);
							kbBucketGlyph(s, matched, sequentialLookupIndex + 1);
						}
						matched = storage.glyphs[matched].next;
					}
				}
			}
		}

		kbFreeGlyphBucket(s, sequentialLookupIndex);
	}
}

export function kbPostGposFixup(s: KbScratch, config: KbShapeConfig): void {
	const storage = s.storage;
	const whitespace = config.whitespace;
	const clearMarkAdvances = config.shaper == KB_SHAPER_ARABIC || config.shaper == KB_SHAPER_DEFAULT ||
		config.shaper == KB_SHAPER_HEBREW;

	if (s.runDirection == KB_DIRECTION_RTL) {
		let markAttachAdvanceX: int32 = 0;
		let markAttachAdvanceY: int32 = 0;

		let glyph = storage.glyphs[KB_GLYPH_SENTINEL].next;
		while (glyph != KB_GLYPH_SENTINEL) {
			const attach = storage.glyphs[glyph].attachGlyph;
			if (attach != 0) {
				let attachAdvanceX = markAttachAdvanceX;
				let attachAdvanceY = markAttachAdvanceY;
				if ((storage.glyphs[attach].classValue as int32) != KB_GLYPH_CLASS_MARK) {
					attachAdvanceX = storage.glyphs[attach].advanceX;
					attachAdvanceY = storage.glyphs[attach].advanceY;
				}
				storage.glyphs[glyph].offsetX += attachAdvanceX;
				storage.glyphs[glyph].offsetY += attachAdvanceY;
				markAttachAdvanceX = attachAdvanceX;
				markAttachAdvanceY = attachAdvanceY;
			}
			glyph = storage.glyphs[glyph].next;
		}

		kbDllistReverseSublist(storage, KB_GLYPH_SENTINEL, KB_GLYPH_SENTINEL);
	}

	let glyph = storage.glyphs[KB_GLYPH_SENTINEL].next;
	while (glyph != KB_GLYPH_SENTINEL) {
		const next = storage.glyphs[glyph].next;
		let keep = false;

		if ((storage.glyphs[glyph].flags & KB_GLYPH_FLAG_GENERATED_BY_GSUB) == 0 &&
			(storage.glyphs[glyph].unicodeFlags & KB_UNICODE_FLAG_DEFAULT_IGNORABLE) != 0) {
			if (whitespace.id != 0) {
				keep = true;

				const glyphConfig = storage.glyphs[glyph].configPlusOne;
				kbSetGlyphPreserveLinksAndUserId(storage, glyph, whitespace);
				storage.glyphs[glyph].configPlusOne = glyphConfig;
			}
		} else {
			if (clearMarkAdvances && (storage.glyphs[glyph].classValue as int32) == KB_GLYPH_CLASS_MARK) {
				storage.glyphs[glyph].advanceX = 0;
				storage.glyphs[glyph].advanceY = 0;
			}
			keep = true;
		}

		if (!keep) {
			kbFreeGlyph(s, glyph);
		}

		glyph = next;
	}
}
