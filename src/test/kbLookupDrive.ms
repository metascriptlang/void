import { kbGetLookup, kbGetLookupList, kbUnpackLookup } from "../void2d/kb/access";
import {
	KB_BLOB_TABLE_ID_GDEF,
	KB_BLOB_TABLE_ID_GPOS,
	KB_BLOB_TABLE_ID_GSUB,
	kbBlobTableData,
	kbU16,
} from "../void2d/kb/blob";
import { KbFont } from "../void2d/kb/font";
import { kbDoSingleAdjustment } from "../void2d/kb/gpos";
import { kbDoSubstitution } from "../void2d/kb/gsub";
import {
	KB_GLYPH_SENTINEL,
	KbGlyphStorage,
	kbCodepointToGlyph,
	kbGlyphClasses,
	kbInsertGlyphBefore,
} from "../void2d/kb/glyph";
import {
	KbScratch,
	kbBeginLookupApplication,
	kbBucketGlyph,
	kbBucketedGlyphIsValid,
	kbEndLookupApplication,
	kbFreeGlyphBucket,
	kbPlaceScratch,
	kbSortGlyphBucket,
	kbUnbucketGlyph,
} from "../void2d/kb/scratch";
import {
	KB_SHAPER_DEFAULT,
} from "../void2d/kb/shapeTables";

export const KB_DRIVE_STRIDE: int32 = 26;

export function kbInt32Bits(value: uint32): int32 {
	return (value > 0x7FFFFFFF ? (value as int64) - 4294967296 : (value as int64)) as int32;
}

export function kbUint32Bits(value: int32): uint32 {
	return (value < 0 ? (value as int64) + 4294967296 : (value as int64)) as uint32;
}

export function kbMatrixBit(flat: int64): uint32 {
	return (1 as uint32) << ((flat % 32) as uint32);
}

export class KbDriveConfig {
	gpos: boolean = false;
	shaper: uint32 = KB_SHAPER_DEFAULT;
	lookupIndex: int32[] = [];
	skipFlags: uint32[] = [];
	matrix: uint32[] = [];
	variation: int32[] = [];
}

function bucketAll(s: KbScratch): void {
	let runningSortKey: uint32 = 0x10000;
	let glyph = s.storage.glyphs[KB_GLYPH_SENTINEL].next;
	while (glyph != KB_GLYPH_SENTINEL) {
		s.storage.glyphs[glyph].sortKey = runningSortKey;
		s.storage.glyphs[glyph].sortKeyInterval = 0x10000;
		kbBucketGlyph(s, glyph, 0);
		runningSortKey += 0x10000;
		glyph = s.storage.glyphs[glyph].next;
	}
}

function rebucketTouched(s: KbScratch, first: int32, onePastLast: int32, sequentialLookupIndex: int32): void {
	let matched = first;
	while (matched != onePastLast) {
		if (s.storage.glyphs[matched].bucketedPlusOne != 0 &&
			(s.storage.glyphs[matched].bucketedBucketIndex as int32) == sequentialLookupIndex) {
			kbUnbucketGlyph(s, matched);
			kbBucketGlyph(s, matched, sequentialLookupIndex + 1);
		}
		matched = s.storage.glyphs[matched].next;
	}
}

function runGsub(s: KbScratch, m: Span<uint8>, config: KbDriveConfig): void {
	const lookupList = kbGetLookupList(m, m.kbBlobTableData(KB_BLOB_TABLE_ID_GSUB));

	for (let sequentialLookupIndex: int32 = 0; sequentialLookupIndex < s.sequentialLookupCount;
		sequentialLookupIndex++) {
		const lookupIndex = config.lookupIndex[sequentialLookupIndex];
		const skipFlags = config.skipFlags[sequentialLookupIndex];
		const bucket = s.buckets[sequentialLookupIndex];

		if (bucket.entries.length != 0) {
			const lookupType = m.kbU16(kbGetLookup(m, lookupList, lookupIndex as int64));
			const lookupTypeIs8 = lookupType == 8;

			if (lookupType >= 4) {
				kbSortGlyphBucket(s, sequentialLookupIndex);
			}

			const count = bucket.entries.length;
			for (let step: int32 = 0; step < count; step++) {
				const entryIndex = lookupTypeIs8 ? count - 1 - step : step;
				const entry = bucket.entries[entryIndex];

				if (kbBucketedGlyphIsValid(entry)) {
					const glyph = entry.glyph;
					const featureValue = entry.featureValue;
					const prev = s.storage.glyphs[glyph].prev;

					kbBeginLookupApplication(s, glyph);

					s.frames[0] = {
						inputGlyph: glyph, startIndex: 0, lookupIndex, subtableIndex: 0, records: 0,
						recordCount: 0, recordIndex: 0,
					};
					s.frameCount = 1;
					while (s.frameCount != 0) {
						kbDoSubstitution(s, lookupList, sequentialLookupIndex, featureValue as int32, false,
							skipFlags, 0);
					}

					const onePastLast = kbEndLookupApplication(s);
					rebucketTouched(s, s.storage.glyphs[prev].next, onePastLast, sequentialLookupIndex);
				}
			}
		}

		kbFreeGlyphBucket(s, sequentialLookupIndex);
	}
}

function runGpos(s: KbScratch, m: Span<uint8>, config: KbDriveConfig): void {
	const lookupList = kbGetLookupList(m, m.kbBlobTableData(KB_BLOB_TABLE_ID_GPOS));
	const gdef = m.kbBlobTableData(KB_BLOB_TABLE_ID_GDEF);

	for (let sequentialLookupIndex: int32 = 0; sequentialLookupIndex < s.sequentialLookupCount;
		sequentialLookupIndex++) {
		const lookupIndex = config.lookupIndex[sequentialLookupIndex];
		const skipFlags = config.skipFlags[sequentialLookupIndex];
		const bucket = s.buckets[sequentialLookupIndex];

		if (bucket.entries.length != 0) {
			const packedLookup = kbGetLookup(m, lookupList, lookupIndex as int64);
			const lookup = kbUnpackLookup(m, gdef, packedLookup);

			if (m.kbU16(packedLookup) >= 2) {
				kbSortGlyphBucket(s, sequentialLookupIndex);
			}

			const count = bucket.entries.length;
			for (let entryIndex: int32 = 0; entryIndex < count; entryIndex++) {
				const entry = bucket.entries[entryIndex];

				if (kbBucketedGlyphIsValid(entry)) {
					const glyph = entry.glyph;
					kbBeginLookupApplication(s, glyph);

					for (let subtableIndex: int32 = 0; subtableIndex < lookup.subtableCount; subtableIndex++) {
						const subtable = packedLookup + m.kbU16(lookup.subtableOffsets + (subtableIndex as int64) * 2);
						if (kbDoSingleAdjustment(s, lookupList, lookupIndex as int64, subtableIndex as int64,
							lookup, subtable, glyph, 0, skipFlags)) {
							break;
						}
					}

					const onePastLast = kbEndLookupApplication(s);
					rebucketTouched(s, glyph, onePastLast, sequentialLookupIndex);
				}
			}
		}

		kbFreeGlyphBucket(s, sequentialLookupIndex);
	}
}

function dump(s: KbScratch): int32[] {
	const glyphs = s.storage.glyphs;
	let order: int32[] = [];
	let at = glyphs[KB_GLYPH_SENTINEL].next;
	while (at != KB_GLYPH_SENTINEL) {
		order.push(at);
		at = glyphs[at].next;
	}

	let out: int32[] = [order.length as int32, s.nextGlyphUid as int32, s.lookupOnePastLastGlyphIndex as int32];
	for (let p: int32 = 0; p < order.length; p++) {
		const g = glyphs[order[p]];
		let attachPos: int32 = -1;
		if (g.attachGlyph != 0) {
			attachPos = -2;
			for (let q: int32 = 0; q < order.length; q++) {
				if (order[q] == g.attachGlyph) {
					attachPos = q;
					break;
				}
			}
		}
		out.push(g.id as int32);
		out.push(g.codepoint as int32);
		out.push(g.uid as int32);
		out.push(g.userIdOrCodepointIndex);
		out.push(g.offsetX);
		out.push(g.offsetY);
		out.push(g.advanceX);
		out.push(g.advanceY);
		out.push(attachPos);
		out.push(g.classValue as int32);
		out.push(g.markAttachmentClass as int32);
		out.push(kbInt32Bits(g.flags));
		out.push(kbInt32Bits(g.sortKey));
		out.push(kbInt32Bits(g.sortKeyInterval));
		out.push(g.bucketedPlusOne != 0 ? (g.bucketedBucketIndex as int32) : -1);
		out.push(g.ligatureUid as int32);
		out.push(g.ligatureComponentIndexPlusOne as int32);
		out.push(g.ligatureComponentCount as int32);
		out.push(g.joiningFeature as int32);
		out.push(g.joiningType as int32);
		out.push(g.unicodeFlags as int32);
		out.push(g.markOrdering as int32);
		out.push(kbInt32Bits((g.decomposition & 0xFFFFFFFF) as uint32));
		out.push(kbInt32Bits((g.decomposition >> 32) as uint32));
		out.push(kbInt32Bits(g.parentInfo));
		out.push(g.configPlusOne != 0 ? 1 : 0);
	}
	return out;
}

export function kbDrive(
	font: KbFont,
	config: KbDriveConfig,
	codepoints: int32[],
	ids: int32[],
	advances: int32[],
): int32[] {
	const storage = new KbGlyphStorage();
	for (let i: int32 = 0; i < codepoints.length; i++) {
		let glyph = kbCodepointToGlyph(font, codepoints[i], 0, i);
		if (ids[i] >= 0) {
			glyph.id = ids[i] as uint16;
			const classes = kbGlyphClasses(font, ids[i]);
			glyph.classValue = classes.classValue as uint16;
			glyph.markAttachmentClass = classes.markAttachmentClass as uint16;
			if (classes.classValue == 2) { glyph.ligatureComponentCount = (2 + (ids[i] & 1)) as uint16; }
		}
		glyph.advanceX = advances[i];
		kbInsertGlyphBefore(storage, KB_GLYPH_SENTINEL, glyph);
	}

	const s = kbPlaceScratch(font, storage, config.shaper, 0, config.matrix,
		config.lookupIndex.length as int32);
	s.configGlyphCount = s.glyphIdCount as uint32;
	s.variationVectorNormalized = config.variation;
	s.hasVariationVector = config.variation.length > 0;

	bucketAll(s);
	if (config.gpos) {
		runGpos(s, font.blob, config);
	} else {
		runGsub(s, font.blob, config);
	}
	return dump(s);
}
