import {
	KbTaggedPointer,
	kbGetDefaultLangsys,
	kbGetFeature,
	kbGetLangsys,
	kbGetLookupList,
	kbGetScript,
} from "./access";
import {
	KB_BLOB_HEADER_GLYPH_COUNT,
	KB_BLOB_HEADER_GLYPH_LOOKUP_MATRIX_OFFSET,
	KB_BLOB_HEADER_GPOS_LOOKUP_INDEX_OFFSET,
	KB_BLOB_HEADER_LOOKUP_COUNT,
	KB_BLOB_TABLE_ID_AVAR,
	KB_BLOB_TABLE_ID_FVAR,
	KB_BLOB_TABLE_ID_GPOS,
	KB_BLOB_TABLE_ID_GSUB,
	KB_BLOB_TABLE_ID_NAME,
	KB_SIZE_AVAR,
	kbBlobTableData,
	kbBoundsFail,
	kbGlyphLookupMatrixIndex,
	kbS16,
	kbU16,
	kbU32,
	kbU8,
} from "./blob";
import {
	KbFeatureOverride,
	KbIndicScriptProperties,
	KbSequentialLookup,
	KbShapeConfig,
	KbVariationAxisInfo,
	KbVariationInfo,
} from "./config";
import {
	KB_FEATURE_ID_abvf,
	KB_FEATURE_ID_abvs,
	KB_FEATURE_ID_akhn,
	KB_FEATURE_ID_blwf,
	KB_FEATURE_ID_blws,
	KB_FEATURE_ID_calt,
	KB_FEATURE_ID_ccmp,
	KB_FEATURE_ID_cfar,
	KB_FEATURE_ID_cjct,
	KB_FEATURE_ID_clig,
	KB_FEATURE_ID_fin2,
	KB_FEATURE_ID_fin3,
	KB_FEATURE_ID_fina,
	KB_FEATURE_ID_half,
	KB_FEATURE_ID_haln,
	KB_FEATURE_ID_init,
	KB_FEATURE_ID_isol,
	KB_FEATURE_ID_liga,
	KB_FEATURE_ID_locl,
	KB_FEATURE_ID_mark,
	KB_FEATURE_ID_med2,
	KB_FEATURE_ID_medi,
	KB_FEATURE_ID_mkmk,
	KB_FEATURE_ID_mset,
	KB_FEATURE_ID_nukt,
	KB_FEATURE_ID_pref,
	KB_FEATURE_ID_pres,
	KB_FEATURE_ID_psts,
	KB_FEATURE_ID_pstf,
	KB_FEATURE_ID_rkrf,
	KB_FEATURE_ID_rlig,
	KB_FEATURE_ID_rphf,
	KB_FEATURE_ID_vatu,
	KB_FEATURE_TAG_blwf,
	KB_FEATURE_TAG_half,
	KB_FEATURE_TAG_locl,
	KB_FEATURE_TAG_pref,
	KB_FEATURE_TAG_pstf,
	KB_FEATURE_TAG_rclt,
	KB_FEATURE_TAG_rphf,
	KB_FEATURE_TAG_vatu,
	kbFeatureTagToId,
} from "./fontTables";
import { KbFont } from "./font";
import {
	KB_FREE_GLYPH_SENTINEL,
	KbGlyph,
	KbGlyphConfig,
	KbGlyphStorage,
	kbCodepointToGlyph,
	kbGlyphIsValid,
	kbPopGlyphList,
	kbPushGlyphList,
	kbZeroGlyph,
} from "./glyph";
import { kbRound32 } from "./resolve";
import {
	KB_GLYPH_FEATURE_MASK,
	KB_INDIC_SCRIPT_ABOVE_BASE_MATRA_POSITION,
	KB_INDIC_SCRIPT_BELOW_BASE_MATRA_POSITION,
	KB_INDIC_SCRIPT_BLWF_POST_ONLY,
	KB_INDIC_SCRIPT_REPH_ENCODING,
	KB_INDIC_SCRIPT_REPH_POSITION,
	KB_INDIC_SCRIPT_RIGHT_SIDE_MATRA_POSITION,
	KB_INDIC_SCRIPT_VIRAMA_CODEPOINT,
	KB_MAX_SIMULTANEOUS_FEATURES,
	KB_MAX_VARIATION_AXIS_COUNT,
	KB_OP_KIND_GPOS_FEATURES,
	KB_OP_KIND_GSUB_FEATURES,
	KB_OP_KIND_GSUB_FEATURES_WITH_USER,
	KB_OP_LIST_ARABIC_NO_RCLT,
	KB_SCRIPT_LAO,
	KB_SCRIPT_SHAPERS,
	KB_SCRIPT_TAGS,
	KB_SCRIPT_THAI,
	KB_SHAPER_ARABIC,
	KB_SHAPER_INDIC,
	KB_SHAPER_KHMER,
	KB_SHAPER_MYANMAR,
	KB_SHAPER_OP_LISTS,
	KbOpList,
	KB_SHAPER_USE,
	KB_SKIP_FLAG_ZWJ,
	KB_SKIP_FLAG_ZWNJ,
	KB_SUBSTITUTION_RESULT_FLAG_MATCHED_SUBSTITUTION,
	KB_SUBSTITUTION_RESULT_FLAG_TRIED_TO_INSERT_WHILE_CHECK_ONLY,
	KB_SYLLABLE_FEATURE_SET,
} from "./shapeTables";
import {
	KB_LOOKUP_STACK_SIZE,
	KbScratch,
	kbBeginLookupApplication,
	kbEndLookupApplication,
	kbUnbucketGlyph,
} from "./scratch";
import { kbDoSubstitution } from "./gsub";

const FIXED_16_16_SCALE: float32 = 0.0000152587890625;
const FIXED_2_14_SCALE: float32 = 0.00006103515625;
const FIXED_ONE: float32 = 65536.0;
const HALF: float32 = 0.5;

const FOURCC_DFLT: int64 = 0x544C4644;
const FOURCC_DFLT_LOWER: int64 = 0x746C6664;
const FOURCC_LATN: int64 = 0x6E74616C;

export const KB_SHAPING_TABLE_GSUB: int32 = 0;
export const KB_SHAPING_TABLE_GPOS: int32 = 1;

struct KbFeatureHit {
	tag: uint32;
	feature: int64;
}

struct KbBakedFeature {
	indices: int64;
	count: int32;
	id: uint32;
	skipFlags: uint32;
	glyphFilter: uint32;
}

export class KbMurmur {
	state: int64 = 0;
	bytesHashed: int64 = 0;
}

function wrapS16(value: int32): int32 {
	return ((value & 0xFFFF) ^ 0x8000) - 0x8000;
}

function kbS32(m: Readonly<Span<uint8>>, at: int64): int32 {
	const value = m.kbU32(at);
	return (value >= 2147483648 ? value - 4294967296 : value) as int32;
}

function fixed16_16ToFloat(value: int32): float32 {
	return ((value >> 16) as float32) + ((value & 0xFFFF) as float32) * FIXED_16_16_SCALE;
}

function fixed2_14ToFloat(value: int32): float32 {
	return (value as float32) * FIXED_2_14_SCALE;
}

function floor32(x: float32): int32 {
	if (!(x >= -2147483648.0 && x < 2147483648.0)) {
		throw kbBoundsFail("float out of int32 range in Floor32", 0);
	}
	let result = x as int32;
	if ((result as float32) != x && x < 0) {
		result -= 1;
	}
	return result;
}

function containsFeature(set: uint64[], id: uint32): boolean {
	return (set[(id >> 6) as int32] & ((1 as uint64) << ((id & 63) as uint64))) != 0;
}

function addFeature(set: uint64[], id: uint32): void {
	set[(id >> 6) as int32] |= (1 as uint64) << ((id & 63) as uint64);
}

function mul32(a: int64, b: int64): int64 {
	return (a * (b & 0xFFFF) + (((a * (b >> 16)) & 0xFFFF) << 16)) & 0xFFFFFFFF;
}

function rotl32(x: int64, n: int64): int64 {
	return ((x << n) | (x >> (32 - n))) & 0xFFFFFFFF;
}

function murmurBegin(murmur: KbMurmur, seed: int64): void {
	murmur.state = seed & 0xFFFFFFFF;
	murmur.bytesHashed = 0;
}

export function kbMurmurAbsorb(murmur: KbMurmur, value: int64): void {
	const k = mul32(rotl32(mul32(value, 0xCC9E2D51), 15), 0x1B873593);
	murmur.state = (mul32(rotl32(murmur.state ^ k, 13), 5) + 0xE6546B64) & 0xFFFFFFFF;
	murmur.bytesHashed = (murmur.bytesHashed + 4) & 0xFFFFFFFF;
}

function murmurFinalize(murmur: KbMurmur): uint32 {
	const hxl = murmur.state ^ murmur.bytesHashed;
	let result = mul32(hxl ^ (hxl >> 16), 0x85EBCA6B);
	result = mul32(result ^ (result >> 13), 0xC2B2AE35);
	result ^= result >> 16;
	return result as uint32;
}

export function kbSkipFlags(featureId: uint32, shaper: uint32): uint32 {
	match (featureId) {
		KB_FEATURE_ID_nukt | KB_FEATURE_ID_akhn | KB_FEATURE_ID_rphf | KB_FEATURE_ID_rkrf |
		KB_FEATURE_ID_pref | KB_FEATURE_ID_blwf | KB_FEATURE_ID_abvf | KB_FEATURE_ID_half |
		KB_FEATURE_ID_pstf | KB_FEATURE_ID_vatu | KB_FEATURE_ID_cjct | KB_FEATURE_ID_pres |
		KB_FEATURE_ID_abvs | KB_FEATURE_ID_blws | KB_FEATURE_ID_psts | KB_FEATURE_ID_haln |
		KB_FEATURE_ID_cfar => {
			if (shaper == KB_SHAPER_USE) { return KB_SKIP_FLAG_ZWNJ; }
			if (shaper == KB_SHAPER_INDIC || shaper == KB_SHAPER_KHMER) { return 0; }
			return KB_SKIP_FLAG_ZWNJ | KB_SKIP_FLAG_ZWJ;
		},
		KB_FEATURE_ID_init => {
			if (shaper == KB_SHAPER_INDIC) { return 0; }
			if (shaper == KB_SHAPER_ARABIC) { return KB_SKIP_FLAG_ZWNJ; }
			return KB_SKIP_FLAG_ZWNJ | KB_SKIP_FLAG_ZWJ;
		},
		KB_FEATURE_ID_ccmp | KB_FEATURE_ID_locl | KB_FEATURE_ID_isol | KB_FEATURE_ID_fina |
		KB_FEATURE_ID_fin2 | KB_FEATURE_ID_fin3 | KB_FEATURE_ID_medi | KB_FEATURE_ID_med2 |
		KB_FEATURE_ID_calt | KB_FEATURE_ID_liga | KB_FEATURE_ID_clig | KB_FEATURE_ID_rlig |
		KB_FEATURE_ID_mset => {
			if (shaper == KB_SHAPER_ARABIC) { return KB_SKIP_FLAG_ZWNJ; }
			return KB_SKIP_FLAG_ZWNJ | KB_SKIP_FLAG_ZWJ;
		},
		KB_FEATURE_ID_mark | KB_FEATURE_ID_mkmk => { return 0; },
		_ => { return KB_SKIP_FLAG_ZWNJ | KB_SKIP_FLAG_ZWJ; },
	}
}

export function kbGetVariationInfo(font: KbFont): KbVariationInfo {
	let result: KbVariationInfo = { axisCount: 0, instanceCount: 0 };
	const m: Span<uint8> = font.blob[0..font.blob.length];
	const fvar = m.kbBlobTableData(KB_BLOB_TABLE_ID_FVAR);
	if (fvar != 0) {
		result.axisCount = m.kbU16(fvar + 8);
		result.instanceCount = m.kbU16(fvar + 12);
	}
	return result;
}

export function kbGetVariationAxisInfo(font: KbFont, axisIndex: int32): KbVariationAxisInfo {
	let result: KbVariationAxisInfo = {
		valid: false, tag: 0, minimumValue: 0, defaultValue: 0, maximumValue: 0, flags: 0,
		nameStringId: 0,
	};
	const m: Span<uint8> = font.blob[0..font.blob.length];
	const fvar = m.kbBlobTableData(KB_BLOB_TABLE_ID_FVAR);
	if (fvar != 0 && axisIndex >= 0 && axisIndex < m.kbU16(fvar + 8)) {
		const axis = fvar + m.kbU16(fvar + 4) + (axisIndex as int64) * 20;
		result.valid = true;
		result.tag = m.kbU32(axis) as uint32;
		result.minimumValue = fixed16_16ToFloat(kbS32(m, axis + 4));
		result.defaultValue = fixed16_16ToFloat(kbS32(m, axis + 8));
		result.maximumValue = fixed16_16ToFloat(kbS32(m, axis + 12));
		result.flags = m.kbU16(axis + 16) as uint16;
		result.nameStringId = m.kbU16(axis + 18) as uint16;
	}
	return result;
}

export function kbNormalizeVariationVector(
	font: KbFont,
	variationVector: float32[],
	normalized: int32[],
): void {
	const m: Span<uint8> = font.blob[0..font.blob.length];
	const fvar = m.kbBlobTableData(KB_BLOB_TABLE_ID_FVAR);
	const avar = m.kbBlobTableData(KB_BLOB_TABLE_ID_AVAR);
	if (fvar == 0) { return; }

	const axes = fvar + m.kbU16(fvar + 4);
	const axisCount = m.kbU16(fvar + 8);
	let segmentMaps: int64 = avar != 0 ? avar + KB_SIZE_AVAR : 0;

	for (let axisIndex = 0; axisIndex < axisCount; axisIndex++) {
		const axis = axes + (axisIndex as int64) * 20;
		const positionMapCount = avar != 0 ? m.kbU16(segmentMaps) : 0;
		const valueMaps = segmentMaps + 2;

		const axisMin = fixed16_16ToFloat(kbS32(m, axis + 4));
		const axisDefault = fixed16_16ToFloat(kbS32(m, axis + 8));
		const axisMax = fixed16_16ToFloat(kbS32(m, axis + 12));

		let inputCoord = variationVector[axisIndex];
		if (inputCoord < axisMin) {
			inputCoord = axisMin;
		} else if (inputCoord > axisMax) {
			inputCoord = axisMax;
		}

		let normalizedFloat: float32 = 0;
		if (inputCoord < axisDefault) {
			normalizedFloat = -(axisDefault - inputCoord) / (axisDefault - axisMin);
		} else if (inputCoord > axisDefault) {
			normalizedFloat = (inputCoord - axisDefault) / (axisMax - axisDefault);
		}

		normalizedFloat = (floor32(normalizedFloat * FIXED_ONE + HALF) as float32) / FIXED_ONE;
		const normalizedFixed = wrapS16(((normalizedFloat * FIXED_ONE) as int32 + 2) >> 2);

		if (positionMapCount != 0) {
			let last = valueMaps;
			let from0 = fixed2_14ToFloat(m.kbS16(last));
			for (let positionMapIndex = 1; positionMapIndex < positionMapCount; positionMapIndex++) {
				const current = valueMaps + (positionMapIndex as int64) * 4;
				const from1 = fixed2_14ToFloat(m.kbS16(current));

				if (from1 >= normalizedFloat) {
					const to0 = fixed2_14ToFloat(m.kbS16(last + 2));
					const to1 = fixed2_14ToFloat(m.kbS16(current + 2));
					const lerpFactor = (normalizedFloat - from0) / (from1 - from0);
					let remappedFloat = to0 + (to1 - to0) * lerpFactor;
					remappedFloat = kbRound32(remappedFloat * FIXED_ONE) as float32;
					normalized[axisIndex] = wrapS16(((remappedFloat as int32) + 2) >> 2);
					break;
				}

				from0 = from1;
				last = current;
			}
		} else {
			normalized[axisIndex] = normalizedFixed;
		}

		segmentMaps = avar != 0 ? valueMaps + (positionMapCount as int64) * 4 : 0;
	}
}

function enabledFeatureHits(
	m: Readonly<Span<uint8>>,
	gsubGpos: int64,
	langsys: int64,
	enabled: uint64[],
): KbFeatureHit[] {
	let hits: KbFeatureHit[] = [];
	if (gsubGpos == 0 || langsys == 0) { return hits; }

	const featureList = gsubGpos + m.kbU16(gsubGpos + 6);
	const count = m.kbU16(langsys + 4);
	for (let i = 0; i < count; i++) {
		const feature = kbGetFeature(m, featureList, m.kbU16(langsys + 6 + (i as int64) * 2));
		if (containsFeature(enabled, kbFeatureTagToId(feature.tag as uint32))) {
			hits.push({ tag: feature.tag as uint32, feature: feature.at });
		}
	}
	return hits;
}

function substitutedFeature(
	m: Readonly<Span<uint8>>,
	featureVariations: int64,
	normalized: int32[],
	axisCount: int32,
	featureIndex: int64,
	feature: int64,
): int64 {
	let result = feature;
	const recordCount = m.kbU32(featureVariations + 4);
	for (let variationIndex: int64 = 0; variationIndex < recordCount; variationIndex++) {
		const record = featureVariations + 8 + variationIndex * 8;
		const conditionSet = featureVariations + m.kbU32(record);
		const conditionCount = m.kbU16(conditionSet);

		for (let conditionIndex = 0; conditionIndex < conditionCount; conditionIndex++) {
			const condition = conditionSet + m.kbU32(conditionSet + 2 + (conditionIndex as int64) * 4);
			const axisIndex = m.kbU16(condition + 2);

			if (axisIndex < axisCount) {
				const input = normalized[axisIndex];
				if (input >= m.kbS16(condition + 4) && input <= m.kbS16(condition + 6)) {
					const substitution = featureVariations + m.kbU32(record + 4);
					const substitutionCount = m.kbU16(substitution + 4);

					for (let substitutionIndex = 0; substitutionIndex < substitutionCount;
						substitutionIndex++) {
						const substitutionRecord = substitution + 6 + (substitutionIndex as int64) * 6;
						const recordFeatureIndex = m.kbU16(substitutionRecord) as int64;

						if (recordFeatureIndex == featureIndex) {
							result = substitution + m.kbU32(substitutionRecord + 2);
							break;
						} else if (recordFeatureIndex > featureIndex) {
							break;
						}
					}
				}
			}
		}
	}
	return result;
}

export function kbDummyScratch(font: KbFont, storage: KbGlyphStorage): KbScratch {
	const result = new KbScratch(font, storage);
	for (let i = 0; i < KB_LOOKUP_STACK_SIZE; i++) {
		result.frames.push({
			inputGlyph: 0, startIndex: 0, lookupIndex: 0, subtableIndex: 0, records: 0,
			recordCount: 0, recordIndex: 0,
		});
	}
	return result;
}

function takeGlyphSlot(storage: KbGlyphStorage): int32 {
	let result = storage.glyphs[KB_FREE_GLYPH_SENTINEL].next;
	if (result != KB_FREE_GLYPH_SENTINEL) {
		storage.glyphs[storage.glyphs[result].prev].next = storage.glyphs[result].next;
		storage.glyphs[storage.glyphs[result].next].prev = storage.glyphs[result].prev;
	} else {
		result = storage.glyphs.length as int32;
		storage.glyphs.push(kbZeroGlyph());
	}
	return result;
}

function releaseGlyphSlot(storage: KbGlyphStorage, slot: int32): void {
	storage.glyphs[slot].next = KB_FREE_GLYPH_SENTINEL;
	storage.glyphs[slot].prev = storage.glyphs[KB_FREE_GLYPH_SENTINEL].prev;
	storage.glyphs[storage.glyphs[slot].prev].next = slot;
	storage.glyphs[KB_FREE_GLYPH_SENTINEL].prev = slot;
}

function startFrame(s: KbScratch, glyph: int32, lookupIndex: int32): void {
	s.frames[0] = {
		inputGlyph: glyph, startIndex: 0, lookupIndex, subtableIndex: 0, records: 0,
		recordCount: 0, recordIndex: 0,
	};
	s.frameCount = 1;
}

function featureLookupIndices(s: KbScratch, lookupList: int64, feature: int64): int32[] {
	let result: int32[] = [];
	if (lookupList != 0 && feature != 0) {
		const m: Span<uint8> = s.font.blob[0..s.font.blob.length];
		const count = m.kbU16(feature + 2);
		for (let i = 0; i < count; i++) {
			result.push(m.kbU16(feature + 4 + (i as int64) * 2));
		}
	}
	return result;
}

export function kbSubstitute1(
	s: KbScratch,
	lookupList: int64,
	feature: int64,
	skipFlags: uint32,
	glyph: KbGlyph,
	sequentialLookupIndex: int32,
): KbGlyph {
	const storage = s.storage;
	const lookupIndices = featureLookupIndices(s, lookupList, feature);
	const result = takeGlyphSlot(storage);
	const tempSentinel = takeGlyphSlot(storage);

	storage.glyphs[result] = glyph;
	storage.glyphs[tempSentinel].prev = result;
	storage.glyphs[tempSentinel].next = result;
	storage.glyphs[result].prev = tempSentinel;
	storage.glyphs[result].next = tempSentinel;
	const list = kbPushGlyphList(storage, result, result);

	let done = false;
	for (let i = 0; i < lookupIndices.length && !done; i++) {
		startFrame(s, result, lookupIndices[i]);
		while (s.frameCount != 0) {
			const flags = kbDoSubstitution(s, lookupList, sequentialLookupIndex, 0, false,
				skipFlags, 0);
			if ((flags & KB_SUBSTITUTION_RESULT_FLAG_TRIED_TO_INSERT_WHILE_CHECK_ONLY) != 0) {
				done = true;
				break;
			}
		}
	}
	s.frameCount = 0;

	kbPopGlyphList(storage, list);
	const out = storage.glyphs[result];
	// The C works on a stack copy; an entry it bucketed afresh points at that stack and nothing reads it
	// again, so the slot must not leave one live. The copied entry of the original is left alone.
	if (storage.glyphs[result].bucketedPlusOne != glyph.bucketedPlusOne) {
		kbUnbucketGlyph(s, result);
	}
	releaseGlyphSlot(storage, result);
	releaseGlyphSlot(storage, tempSentinel);
	return out;
}

export function kbWouldSubstitute(
	s: KbScratch,
	lookupList: int64,
	feature: int64,
	skipFlags: uint32,
	glyphs: KbGlyph[],
	first: int32,
	count: int32,
): boolean {
	if (count < 1 || count > 4) {
		throw kbBoundsFail("WouldSubstitute glyph count outside 1..4", count);
	}
	const storage = s.storage;
	const lookupIndices = featureLookupIndices(s, lookupList, feature);
	let result = false;

	const tempSentinel = takeGlyphSlot(storage);
	let slots: int32[] = [];
	for (let i = 0; i < count; i++) {
		slots.push(takeGlyphSlot(storage));
	}
	for (let i = 0; i < count; i++) {
		storage.glyphs[slots[i]] = glyphs[first + i];
		storage.glyphs[slots[i]].prev = i == 0 ? tempSentinel : slots[i - 1];
		storage.glyphs[slots[i]].next = i == count - 1 ? tempSentinel : slots[i + 1];
	}
	storage.glyphs[tempSentinel].next = slots[0];
	storage.glyphs[tempSentinel].prev = slots[count - 1];

	const list = kbPushGlyphList(storage, slots[0], slots[count - 1]);

	for (let i = 0; i < lookupIndices.length && !result; i++) {
		let current = slots[0];
		while (kbGlyphIsValid(current) && !result) {
			startFrame(s, current, lookupIndices[i]);
			kbBeginLookupApplication(s, current);

			while (s.frameCount != 0) {
				const flags = kbDoSubstitution(s, lookupList, 0, 0, true, skipFlags, 0);
				if ((flags & KB_SUBSTITUTION_RESULT_FLAG_MATCHED_SUBSTITUTION) != 0) {
					result = true;
					break;
				}
			}
			if (!result) {
				current = kbEndLookupApplication(s);
			}
		}
	}
	s.frameCount = 0;

	kbPopGlyphList(storage, list);
	for (let i = 0; i < count; i++) {
		releaseGlyphSlot(storage, slots[i]);
	}
	releaseGlyphSlot(storage, tempSentinel);
	return result;
}

export function kbIdSequentialLookupMatrixWord(
	sequentialLookupIndex: int64,
	glyphIndex: int64,
	sequentialLookupCount: int64,
): int64 {
	const bitsPerRow = (sequentialLookupCount + 31) & ~(31 as int64);
	return (glyphIndex * bitsPerRow + sequentialLookupIndex) / 32;
}

function idSequentialLookupMatrixBit(
	sequentialLookupIndex: int64,
	glyphIndex: int64,
	sequentialLookupCount: int64,
): int64 {
	const bitsPerRow = (sequentialLookupCount + 31) & ~(31 as int64);
	return (glyphIndex * bitsPerRow + sequentialLookupIndex) % 32;
}

struct KbLangsysChoice {
	langsys: int64[];
	indic3: boolean;
}

struct KbSequentialBake {
	sequentialLookups: KbSequentialLookup[];
	idSequentialLookupMatrix: uint32[];
	featureStageFirstLookupIndices: uint16[];
	glyphCount: uint32;
	lookupCount: uint32;
}

function tableLookupList(font: KbFont, tableId: int32): int64 {
	const m: Span<uint8> = font.blob[0..font.blob.length];
	return kbGetLookupList(m, m.kbBlobTableData(tableId));
}

function hashFontName(font: KbFont, murmur: KbMurmur): void {
	const m: Span<uint8> = font.blob[0..font.blob.length];
	const name = m.kbBlobTableData(KB_BLOB_TABLE_ID_NAME);
	if (name == 0) { return; }

	const stringBase = name + m.kbU16(name + 4);
	let offset: int64 = 0;
	let length: int64 = 0;
	const recordCount = m.kbU16(name + 2);
	for (let recordIndex = 0; recordIndex < recordCount; recordIndex++) {
		const record = name + 6 + (recordIndex as int64) * 12;
		if (m.kbU16(record) == 3) {
			const nameId = m.kbU16(record + 6);
			if (nameId == 3 || nameId == 4) {
				length = m.kbU16(record + 8);
				offset = m.kbU16(record + 10);
				break;
			}
		}
	}

	if (length != 0) {
		let at = stringBase + offset;
		let left = length;
		while (left >= 4) {
			kbMurmurAbsorb(murmur, m.kbU32(at));
			at += 4;
			left -= 4;
		}
		if (left != 0) {
			let lastBytes: int64 = 0;
			for (let i: int64 = 0; i < left; i++) {
				lastBytes |= (m.kbU8(at + i) as int64) << (i * 8);
			}
			kbMurmurAbsorb(murmur, lastBytes);
		}
	}
}

function chooseLangsys(font: KbFont, script: uint32, language: uint32): KbLangsysChoice {
	const m: Span<uint8> = font.blob[0..font.blob.length];
	const shapingTables: int64[] = [
		m.kbBlobTableData(KB_BLOB_TABLE_ID_GSUB), m.kbBlobTableData(KB_BLOB_TABLE_ID_GPOS),
	];
	const scriptTag = KB_SCRIPT_TAGS[script] as int64;
	let result: KbLangsysChoice = { langsys: [0, 0], indic3: false };

	for (let shapingTableIndex = 0; shapingTableIndex < 2; shapingTableIndex++) {
		const shapingTable = shapingTables[shapingTableIndex];
		if (shapingTable == 0) { continue; }

		const scriptList = shapingTable + m.kbU16(shapingTable + 4);
		const scriptCount = m.kbU16(scriptList);
		let chosenLangsys: int64 = 0;
		let latinFallbackTag = FOURCC_LATN;

		for (let scriptIndex = 0; scriptIndex < scriptCount; scriptIndex++) {
			const thisScript: KbTaggedPointer = kbGetScript(m, scriptList, scriptIndex);
			const tag = thisScript.tag;

			const indic3 = (tag >> 24) == 0x33;
			const matchMask: int64 = indic3 ? 0xFFFFFF : 0xFFFFFFFF;
			const isDefault = tag == FOURCC_DFLT || tag == FOURCC_DFLT_LOWER;
			const perfectMatch = ((tag ^ scriptTag) & matchMask) == 0;
			if (scriptIndex == 0 || perfectMatch || isDefault || tag == latinFallbackTag) {
				let langsys = kbGetDefaultLangsys(m, thisScript.at);
				const langsysCount = m.kbU16(thisScript.at + 2);
				for (let langsysIndex = 0; langsysIndex < langsysCount; langsysIndex++) {
					const pointer = kbGetLangsys(m, thisScript.at, langsysIndex);
					if (pointer.tag == (language as int64)) {
						langsys = pointer.at;
						break;
					}
				}

				latinFallbackTag = isDefault ? 0 : latinFallbackTag;

				chosenLangsys = langsys;
				if (shapingTableIndex == KB_SHAPING_TABLE_GSUB) {
					result.indic3 = indic3;
				}
				if (perfectMatch) { break; }
			}
		}
		result.langsys[shapingTableIndex] = chosenLangsys;
	}
	return result;
}

function bakeSequentialLookups(
	font: KbFont,
	opList: KbOpList,
	features: uint64[],
	shaper: uint32,
	langsysList: int64[],
	hasVariationVector: boolean,
	normalized: int32[],
	axisCount: int32,
	murmur: KbMurmur,
): KbSequentialBake {
	const m: Span<uint8> = font.blob[0..font.blob.length];
	const shapingTables: int64[] = [
		m.kbBlobTableData(KB_BLOB_TABLE_ID_GSUB), m.kbBlobTableData(KB_BLOB_TABLE_ID_GPOS),
	];
	const maxAxisCount = KB_MAX_VARIATION_AXIS_COUNT as int32;

	let result: KbSequentialBake = {
		sequentialLookups: [], idSequentialLookupMatrix: [], featureStageFirstLookupIndices: [],
		glyphCount: 0, lookupCount: 0,
	};
	for (let i = 0; i <= opList.stageFeatureCounts.length; i++) {
		result.featureStageFirstLookupIndices.push(0);
	}
	if (shapingTables[0] == 0 && shapingTables[1] == 0) { return result; }

	const glyphCount = m.kbU32(KB_BLOB_HEADER_GLYPH_COUNT);
	const glyphLookupMatrix = m.kbU32(KB_BLOB_HEADER_GLYPH_LOOKUP_MATRIX_OFFSET);
	const gposLookupIndexOffset = m.kbU32(KB_BLOB_HEADER_GPOS_LOOKUP_INDEX_OFFSET);

	let sequentialLookupCount: int64 = 0;

	for (let iter = 0; iter < 2; iter++) {
		let thisSequentialLookupCount: int64 = 0;
		let featureStageIndex = 0;

		for (let opIndex = 0; opIndex < opList.ops.length; opIndex++) {
			const op = opList.ops[opIndex];
			const userFeaturesAllowed = op == KB_OP_KIND_GSUB_FEATURES_WITH_USER ||
				op == KB_OP_KIND_GPOS_FEATURES;
			if (op != KB_OP_KIND_GSUB_FEATURES && op != KB_OP_KIND_GSUB_FEATURES_WITH_USER &&
				op != KB_OP_KIND_GPOS_FEATURES) {
				continue;
			}

			const stageBase = featureStageIndex * 4;
			const stageFeatures: uint64[] = [
				opList.stageFlags[stageBase], opList.stageFlags[stageBase + 1],
				opList.stageFlags[stageBase + 2], opList.stageFlags[stageBase + 3],
			];
			const shapingTableIndex = op == KB_OP_KIND_GPOS_FEATURES ?
				KB_SHAPING_TABLE_GPOS : KB_SHAPING_TABLE_GSUB;
			const gsubGpos = shapingTables[shapingTableIndex];
			const langsys = langsysList[shapingTableIndex];
			let bakedFeatureLookupIndexCount: int64 = 0;
			let baked: KbBakedFeature[] = [];

			if (gsubGpos != 0 && langsys != 0) {
				const featureList = gsubGpos + m.kbU16(gsubGpos + 6);
				let featureVariations: int64 = 0;

				if (m.kbU16(gsubGpos + 2) == 1 && m.kbU32(gsubGpos + 10) != 0 &&
					hasVariationVector && axisCount < maxAxisCount) {
					featureVariations = gsubGpos + m.kbU32(gsubGpos + 10);
				}

				const featureIndexCount = m.kbU16(langsys + 4);
				for (let featureIndexIndex = 0; featureIndexIndex < featureIndexCount;
					featureIndexIndex++) {
					const featureIndex = m.kbU16(langsys + 6 + (featureIndexIndex as int64) * 2);
					const feature = kbGetFeature(m, featureList, featureIndex);
					let featureAt = feature.at;

					if (featureVariations != 0) {
						featureAt = substitutedFeature(m, featureVariations, normalized, axisCount,
							featureIndex, featureAt);
					}

					const featureId = kbFeatureTagToId(feature.tag as uint32);
					const lookupIndexCount = m.kbU16(featureAt + 2);
					if (lookupIndexCount != 0 &&
						((userFeaturesAllowed && !containsFeature(features, featureId)) ||
						containsFeature(stageFeatures, featureId))) {
						kbMurmurAbsorb(murmur, featureAt);

						let glyphFilter: uint32 = 0;
						if (shaper != KB_SHAPER_MYANMAR && featureId >= 1 && featureId <= 32) {
							const shift: uint32 = featureId - 1;
							glyphFilter = ((1 as uint32) << shift) & KB_GLYPH_FEATURE_MASK;
						}
						baked.push({
							indices: featureAt + 4, count: lookupIndexCount, id: featureId,
							skipFlags: kbSkipFlags(featureId, shaper), glyphFilter,
						});
						bakedFeatureLookupIndexCount += lookupIndexCount;

						if (baked.length >= (KB_MAX_SIMULTANEOUS_FEATURES as int32)) { break; }
					}
				}

				let lookupIndicesRead: int32[] = [];
				for (let i = 0; i < baked.length; i++) {
					lookupIndicesRead.push(0);
				}

				let lastLowestLookupIndex = 0xFFFF;
				let lookupIndicesLeft = bakedFeatureLookupIndexCount;
				while (lookupIndicesLeft != 0) {
					let lowestLookupIndex = 0xFFFF;

					for (let i = 0; i < baked.length; i++) {
						if (lookupIndicesRead[i] < baked[i].count) {
							const nextIndex = m.kbU16(baked[i].indices + (lookupIndicesRead[i] as int64) * 2);
							if (nextIndex < lowestLookupIndex) {
								lowestLookupIndex = nextIndex;
							}
						}
					}

					let glyphFilter: uint32 = 0;
					let skipFlags: uint32 = 0;
					let defaultEnabled = false;
					for (let i = 0; i < baked.length; i++) {
						if (lookupIndicesRead[i] < baked[i].count) {
							const nextIndex = m.kbU16(baked[i].indices + (lookupIndicesRead[i] as int64) * 2);
							if (nextIndex == lowestLookupIndex) {
								glyphFilter |= baked[i].glyphFilter;
								skipFlags |= baked[i].skipFlags;
								lookupIndicesRead[i] += 1;
								lookupIndicesLeft -= 1;
								if (containsFeature(stageFeatures, baked[i].id)) {
									defaultEnabled = true;
								}
							}
						}
					}

					if (lowestLookupIndex != lastLowestLookupIndex) {
						if (iter != 0 && defaultEnabled) {
							const flatLookupIndex = shapingTableIndex == KB_SHAPING_TABLE_GSUB ?
								lowestLookupIndex as int64 :
								(lowestLookupIndex as int64) + gposLookupIndexOffset;
							for (let glyphIndex: int64 = 0; glyphIndex < glyphCount; glyphIndex++) {
								const index = kbGlyphLookupMatrixIndex(flatLookupIndex, glyphIndex, glyphCount);
								const word = m.kbU32(glyphLookupMatrix + index.word * 4);
								if ((word & ((1 as int64) << index.bit)) != 0) {
									const sequentialWord = kbIdSequentialLookupMatrixWord(thisSequentialLookupCount,
										glyphIndex, sequentialLookupCount);
									const sequentialBit = idSequentialLookupMatrixBit(thisSequentialLookupCount,
										glyphIndex, sequentialLookupCount);
									result.idSequentialLookupMatrix[sequentialWord as int32] |=
										((1 as uint32) << (sequentialBit as uint32));
								}
							}
						}

						if (iter != 0) {
							result.sequentialLookups[thisSequentialLookupCount as int32] = {
								glyphFilter, skipFlags, lookupIndex: lowestLookupIndex as uint16,
							};
						}
						thisSequentialLookupCount += 1;
					}

					lastLowestLookupIndex = lowestLookupIndex;
				}
			}

			if (iter != 0) {
				result.featureStageFirstLookupIndices[featureStageIndex + 1] =
					(thisSequentialLookupCount & 0xFFFF) as uint16;
			}

			featureStageIndex += 1;
		}

		if (iter == 0) {
			sequentialLookupCount = thisSequentialLookupCount;
			for (let i: int64 = 0; i < sequentialLookupCount; i++) {
				result.sequentialLookups.push({ glyphFilter: 0, skipFlags: 0, lookupIndex: 0 });
			}

			const lastSequentialLookupIndex = sequentialLookupCount != 0 ? sequentialLookupCount - 1 : 0;
			const lastGlyphIndex = glyphCount != 0 ? glyphCount - 1 : 0;
			const sizeInWords = kbIdSequentialLookupMatrixWord(lastSequentialLookupIndex,
				lastGlyphIndex, sequentialLookupCount) + 1;
			for (let i: int64 = 0; i < sizeInWords; i++) {
				result.idSequentialLookupMatrix.push(0);
			}
		}
	}

	result.glyphCount = glyphCount as uint32;
	result.lookupCount = m.kbU32(KB_BLOB_HEADER_LOOKUP_COUNT) as uint32;
	return result;
}

function syllableFeatureHits(font: KbFont, langsys: int64): KbFeatureHit[] {
	const m: Span<uint8> = font.blob[0..font.blob.length];
	return enabledFeatureHits(m, m.kbBlobTableData(KB_BLOB_TABLE_ID_GSUB), langsys,
		KB_SYLLABLE_FEATURE_SET);
}

export function kbPlaceShapeConfig(
	font: KbFont,
	script: uint32,
	language: uint32,
	variationVector: float32[] | null,
	blobSeed: int64,
): KbShapeConfig {
	const axisCount = kbGetVariationInfo(font).axisCount;
	const maxAxisCount = KB_MAX_VARIATION_AXIS_COUNT as int32;
	let normalized: int32[] = [];
	for (let i = 0; i < (axisCount > maxAxisCount ? axisCount : maxAxisCount); i++) {
		normalized.push(0);
	}
	if (variationVector !== null) {
		kbNormalizeVariationVector(font, variationVector, normalized);
	}

	const murmur = new KbMurmur();
	murmurBegin(murmur, blobSeed);
	hashFontName(font, murmur);

	const choice = chooseLangsys(font, script, language);
	const indicScriptProperties: KbIndicScriptProperties = {
		viramaCodepoint: KB_INDIC_SCRIPT_VIRAMA_CODEPOINT[script],
		blwfPostOnly: KB_INDIC_SCRIPT_BLWF_POST_ONLY[script],
		rephPosition: KB_INDIC_SCRIPT_REPH_POSITION[script],
		rephEncoding: KB_INDIC_SCRIPT_REPH_ENCODING[script],
		rightSideMatraPosition: KB_INDIC_SCRIPT_RIGHT_SIDE_MATRA_POSITION[script],
		aboveBaseMatraPosition: KB_INDIC_SCRIPT_ABOVE_BASE_MATRA_POSITION[script],
		belowBaseMatraPosition: KB_INDIC_SCRIPT_BELOW_BASE_MATRA_POSITION[script],
	};
	const shaper = choice.indic3 ? KB_SHAPER_USE : (KB_SCRIPT_SHAPERS[script] as uint32);
	let opList = KB_SHAPER_OP_LISTS[shaper];

	let features: uint64[] = [0, 0, 0, 0];
	for (let stageIndex = 0; stageIndex < opList.stageFeatureCounts.length; stageIndex++) {
		for (let wordIndex = 0; wordIndex < 4; wordIndex++) {
			features[wordIndex] |= opList.stageFlags[stageIndex * 4 + wordIndex];
		}
	}

	let blwf: int64 = 0;
	let pref: int64 = 0;
	let pstf: int64 = 0;
	let locl: int64 = 0;
	let rphf: int64 = 0;
	let half: int64 = 0;
	let vatu: int64 = 0;
	let rclt: int64 = 0;
	for (const hit of syllableFeatureHits(font, choice.langsys[KB_SHAPING_TABLE_GSUB])) {
		match (hit.tag) {
			KB_FEATURE_TAG_blwf => { blwf = hit.feature; },
			KB_FEATURE_TAG_pref => { pref = hit.feature; },
			KB_FEATURE_TAG_pstf => { pstf = hit.feature; },
			KB_FEATURE_TAG_locl => { locl = hit.feature; },
			KB_FEATURE_TAG_rphf => { rphf = hit.feature; },
			KB_FEATURE_TAG_half => { half = hit.feature; },
			KB_FEATURE_TAG_vatu => { vatu = hit.feature; },
			KB_FEATURE_TAG_rclt => { rclt = hit.feature; },
			_ => {},
		}
	}

	if (shaper == KB_SHAPER_ARABIC && rclt == 0) {
		opList = KB_OP_LIST_ARABIC_NO_RCLT;
	}

	let virama = kbZeroGlyph();
	if (indicScriptProperties.viramaCodepoint != 0) {
		const dummyStorage = new KbGlyphStorage();
		const dummy = kbDummyScratch(font, dummyStorage);
		const base = kbCodepointToGlyph(font, indicScriptProperties.viramaCodepoint as int32, 0, 0);
		virama = kbSubstitute1(dummy, tableLookupList(font, KB_BLOB_TABLE_ID_GSUB), locl,
			KB_SKIP_FLAG_ZWNJ | KB_SKIP_FLAG_ZWJ, base, 0);
	}

	let nikhahit = kbZeroGlyph();
	let saraAa = kbZeroGlyph();
	if (script == KB_SCRIPT_THAI || script == KB_SCRIPT_LAO) {
		const thai = script == KB_SCRIPT_THAI;
		nikhahit = kbCodepointToGlyph(font, thai ? 0xE4D : 0xECD, 0, 0);
		saraAa = kbCodepointToGlyph(font, thai ? 0xE32 : 0xEB2, 0, 0);
	}
	const dottedCircle = kbCodepointToGlyph(font, 0x25CC, 0, 0);
	const whitespace = kbCodepointToGlyph(font, 0x20, 0, 0);

	const bake = bakeSequentialLookups(font, opList, features, shaper, choice.langsys,
		variationVector !== null, normalized, axisCount, murmur);

	const config = new KbShapeConfig(font);
	config.script = script;
	config.language = language;
	config.langsys = choice.langsys;
	config.opList = opList;
	config.features = features;
	config.shaper = shaper;
	config.uid[0] = murmurFinalize(murmur);
	config.indicScriptProperties = indicScriptProperties;
	config.blwf = blwf;
	config.pref = pref;
	config.pstf = pstf;
	config.locl = locl;
	config.rphf = rphf;
	config.half = half;
	config.vatu = vatu;
	config.glyphCount = bake.glyphCount;
	config.lookupCount = bake.lookupCount;
	config.featureStageFirstLookupIndices = bake.featureStageFirstLookupIndices;
	config.sequentialLookups = bake.sequentialLookups;
	config.idSequentialLookupMatrix = bake.idSequentialLookupMatrix;
	config.virama = virama;
	config.dottedCircle = dottedCircle;
	config.whitespace = whitespace;
	config.nikhahit = nikhahit;
	config.saraAa = saraAa;
	return config;
}

export function kbPlaceGlyphConfig(
	config: KbShapeConfig,
	overrides: KbFeatureOverride[],
): KbGlyphConfig {
	const m: Span<uint8> = config.font.blob[0..config.font.blob.length];
	const result = new KbGlyphConfig();

	const stageCount = config.opList.stageFeatureCounts.length;
	const sequentialLookupCount = config.featureStageFirstLookupIndices[stageCount] as int64;
	const lastSequentialLookupIndex = sequentialLookupCount != 0 ? sequentialLookupCount - 1 : 0;
	const rowWords = kbIdSequentialLookupMatrixWord(lastSequentialLookupIndex, 0,
		sequentialLookupCount) + 1;
	for (let i: int64 = 0; i < rowWords; i++) {
		result.enabledLookupBits.push(0);
		result.disabledLookupBits.push(0);
	}

	let overridden: uint64[] = [0, 0, 0, 0];
	for (const override of overrides) {
		addFeature(overridden, kbFeatureTagToId(override.tag));
	}

	const gsubSequentialLookupCount = config.featureStageFirstLookupIndices[stageCount - 1] as int64;
	for (let shapingTable = 0; shapingTable < 2; shapingTable++) {
		const gsubGpos = m.kbBlobTableData(shapingTable == KB_SHAPING_TABLE_GSUB ?
			KB_BLOB_TABLE_ID_GSUB : KB_BLOB_TABLE_ID_GPOS);

		let firstSequentialLookupIndex: int64 = 0;
		let onePastLastSequentialLookupIndex = gsubSequentialLookupCount;
		if (shapingTable == KB_SHAPING_TABLE_GPOS) {
			firstSequentialLookupIndex = onePastLastSequentialLookupIndex;
			onePastLastSequentialLookupIndex = sequentialLookupCount;
		}

		const lookupList = kbGetLookupList(m, gsubGpos);
		const hits = enabledFeatureHits(m, gsubGpos, config.langsys[shapingTable], overridden);

		for (const hit of hits) {
			let found = -1;
			for (let i = 0; i < overrides.length; i++) {
				if (overrides[i].tag == hit.tag) {
					found = i;
					break;
				}
			}
			if (found < 0 || lookupList == 0) { continue; }

			const overrideValue = overrides[found].value;
			const lookupCount = m.kbU16(hit.feature + 2);
			for (let lookupIndexIndex = 0; lookupIndexIndex < lookupCount; lookupIndexIndex++) {
				const lookupIndex = m.kbU16(hit.feature + 4 + (lookupIndexIndex as int64) * 2);

				let foundSequentialLookupIndex: int64 = -1;
				for (let i = firstSequentialLookupIndex; i < onePastLastSequentialLookupIndex; i++) {
					if ((config.sequentialLookups[i as int32].lookupIndex as int32) == lookupIndex) {
						foundSequentialLookupIndex = i;
						break;
					}
				}

				if (foundSequentialLookupIndex >= 0) {
					const word = (foundSequentialLookupIndex / 32) as int32;
					const bit = (foundSequentialLookupIndex % 32) as uint32;
					if (overrideValue != 0) {
						result.enabledLookupBits[word] |= (1 as uint32) << bit;

						if (overrideValue > 1 &&
							result.nonBinaryEnabledLookups.length < (KB_MAX_SIMULTANEOUS_FEATURES as int32)) {
							result.nonBinaryEnabledLookups.push({
								sequentialLookupIndex: (foundSequentialLookupIndex & 0xFFFF) as int32,
								value: overrideValue & 0xFFFF,
							});
						}
					} else {
						result.disabledLookupBits[word] |= (1 as uint32) << bit;
					}
				}
			}
		}
	}
	return result;
}
