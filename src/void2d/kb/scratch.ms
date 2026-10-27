import {
	KB_BLOB_HEADER_GLYPH_COUNT,
	KB_BLOB_HEADER_GLYPH_LOOKUP_SUBTABLE_MATRIX_OFFSET,
	KB_BLOB_HEADER_GPOS_LOOKUP_INDEX_OFFSET,
	KB_BLOB_HEADER_LOOKUP_SUBTABLE_COUNT,
	KB_BLOB_HEADER_LOOKUP_SUBTABLE_INDEX_OFFSETS_OFFSET,
	KB_BLOB_TABLE_ID_GDEF,
	kbBlobTableData,
	kbGlyphLookupMatrixIndex,
	kbU16,
	kbU32,
} from "./blob";
import { KbShapeConfig } from "./config";
import { KbFont } from "./font";
import {
	KB_DELETED_SORT_KEY,
	KB_FREE_GLYPH_SENTINEL,
	KbGlyphList,
	KbGlyphStorage,
	kbGlyphClasses,
} from "./glyph";
import {
	KB_GLYPH_FLAG_FIRST_IN_MULTIPLE_SUBSTITUTION,
} from "./shapeTables";

export const KB_LOOKUP_STACK_SIZE: int32 = 32;

export struct KbBucketed {
	glyph: int32;
	sortKey: uint32;
	featureValue: uint16;
}

export const KB_BUCKETED_GLYPHS_PER_BLOCK: int32 = 64;

export struct KbGsubFrame {
	inputGlyph: int32;
	startIndex: uint32;
	lookupIndex: int32;
	subtableIndex: int32;
	records: int64;
	recordCount: int32;
	recordIndex: int32;
}

export class KbScratch {
	font: KbFont;
	storage: KbGlyphStorage;

	shaper: uint32 = 0;
	configGlyphCount: uint32 = 0;
	sequentialLookupCount: int32 = 0;
	idSequentialLookupMatrix: uint32[] = [];

	glyphIdCount: int64 = 0;
	lookupSubtableCount: int64 = 0;
	gposLookupIndexOffset: int64 = 0;
	glyphLookupSubtableMatrix: int64 = 0;
	lookupSubtableIndexOffsets: int64 = 0;
	gdefItemVariationStore: int64 = 0;
	variationVectorNormalized: int32[] = [];
	hasVariationVector: boolean = false;

	blockEntries: KbBucketed[] = [];
	blockCounts: int32[] = [];
	bucketBlocks: int32[][] = [];
	freeBlocks: int32[] = [];

	cluster: KbGlyphList = { sentinelPrev: 0, sentinelNext: 0, oneBeforeFirst: 0, onePastLast: 0 };
	lookupOnePastLastGlyph: int32 = 0;
	lookupOnePastLastGlyphIndex: uint32 = 0;
	nextGlyphUid: uint32 = 0;

	frames: KbGsubFrame[] = [];
	frameCount: int32 = 0;

	config: KbShapeConfig | null = null;
	realCluster: boolean = false;
	clusterAtStartOfWord: boolean = false;
	ip: uint32 = 0;
	opKind: uint8 = 0;
	runDirection: uint32 = 0;
	sequentialLookupIndexIndex: uint32 = 0;
	featureStagesRead: uint32 = 0;

	constructor(font: KbFont, storage: KbGlyphStorage) {
		this.font = font;
		this.storage = storage;
	}
}

export function kbPlaceScratch(
	font: KbFont,
	storage: KbGlyphStorage,
	shaper: uint32,
	configGlyphCount: uint32,
	idSequentialLookupMatrix: uint32[],
	sequentialLookupCount: int32,
): KbScratch {
	const result = new KbScratch(font, storage);
	result.shaper = shaper;
	result.configGlyphCount = configGlyphCount;
	result.idSequentialLookupMatrix = idSequentialLookupMatrix;
	result.sequentialLookupCount = sequentialLookupCount;

	const m: Span<uint8> = font.blob[0..font.blob.length];
	result.glyphIdCount = m.kbU32(KB_BLOB_HEADER_GLYPH_COUNT);
	result.lookupSubtableCount = m.kbU32(KB_BLOB_HEADER_LOOKUP_SUBTABLE_COUNT);
	result.gposLookupIndexOffset = m.kbU32(KB_BLOB_HEADER_GPOS_LOOKUP_INDEX_OFFSET);
	result.glyphLookupSubtableMatrix = m.kbU32(KB_BLOB_HEADER_GLYPH_LOOKUP_SUBTABLE_MATRIX_OFFSET);
	result.lookupSubtableIndexOffsets =
		m.kbU32(KB_BLOB_HEADER_LOOKUP_SUBTABLE_INDEX_OFFSETS_OFFSET);

	const gdef = m.kbBlobTableData(KB_BLOB_TABLE_ID_GDEF);
	if (gdef != 0 && m.kbU16(gdef) == 1 && m.kbU16(gdef + 2) >= 3 && m.kbU32(gdef + 14) != 0) {
		result.gdefItemVariationStore = gdef + m.kbU32(gdef + 14);
	}

	for (let i = 0; i < sequentialLookupCount; i++) {
		result.bucketBlocks.push([]);
	}
	for (let i = 0; i < KB_LOOKUP_STACK_SIZE; i++) {
		result.frames.push({
			inputGlyph: 0, startIndex: 0, lookupIndex: 0, subtableIndex: 0, records: 0,
			recordCount: 0, recordIndex: 0,
		});
	}
	return result;
}

export function kbPlaceShapeScratch(config: KbShapeConfig, storage: KbGlyphStorage): KbScratch {
	const stageCount = config.opList.stageFeatureCounts.length as int32;
	const result = kbPlaceScratch(config.font, storage, config.shaper, config.glyphCount,
		config.idSequentialLookupMatrix, config.featureStageFirstLookupIndices[stageCount] as int32);
	result.config = config;
	return result;
}

export function kbGlyphIncludedInLookupSubtable(
	s: KbScratch,
	gpos: boolean,
	lookupIndex: int64,
	subtableIndex: int64,
	glyph: int32,
): boolean {
	if (s.glyphLookupSubtableMatrix == 0) { return true; }

	const m: Span<uint8> = s.font.blob[0..s.font.blob.length];
	const flatLookupIndex = gpos ? lookupIndex + s.gposLookupIndexOffset : lookupIndex;
	const flatSubtableIndex = m.kbU32(s.lookupSubtableIndexOffsets + flatLookupIndex * 4) + subtableIndex;

	const id = s.storage.glyphs[glyph].id as int64;
	if (id < s.glyphIdCount) {
		const index = kbGlyphLookupMatrixIndex(flatSubtableIndex, id, s.glyphIdCount);
		const word = m.kbU32(s.glyphLookupSubtableMatrix + index.word * 4);
		if ((word & ((1 as int64) << index.bit)) == 0) { return false; }
	}
	return true;
}

export function kbBeginLookupApplication(s: KbScratch, glyph: int32): void {
	s.lookupOnePastLastGlyph = s.storage.glyphs[glyph].next;
	s.lookupOnePastLastGlyphIndex = 0;
}

export function kbEndLookupApplication(s: KbScratch): int32 {
	return s.lookupOnePastLastGlyph;
}

export function kbSetLookupOnePastLastGlyph(s: KbScratch, index: int64, glyph: int32): void {
	if (index > (s.lookupOnePastLastGlyphIndex as int64)) {
		s.lookupOnePastLastGlyphIndex = index as uint32;
		s.lookupOnePastLastGlyph = glyph;
	}
}

export function kbNextGlyphUid(s: KbScratch): uint16 {
	s.nextGlyphUid = ((s.nextGlyphUid as int64 + 1) & 0xFFFFFFFF) as uint32;
	return (s.nextGlyphUid & 0xFFFF) as uint16;
}

export function kbUnbucketGlyph(s: KbScratch, glyph: int32): void {
	const bucketedPlusOne = s.storage.glyphs[glyph].bucketedPlusOne;
	if (bucketedPlusOne != 0) {
		s.blockEntries[bucketedPlusOne - 1].sortKey = KB_DELETED_SORT_KEY;
		s.storage.glyphs[glyph].bucketedPlusOne = 0;
	}
}

export function kbBucketedGlyphIsValid(entry: KbBucketed): boolean {
	return entry.sortKey != KB_DELETED_SORT_KEY;
}

// The C keeps bucket entries in 64-entry blocks recycled last-freed-first, and a glyph's Bucketed
// pointer outlives its bucket, so ShapeDirect can write a deletion into an entry another bucket now
// owns. Blocks are kept so that write lands where the C's lands.
function newBucketedGlyphBlock(s: KbScratch): int32 {
	if (s.freeBlocks.length > 0) {
		const block = s.freeBlocks.pop() as int32;
		s.blockCounts[block] = 0;
		return block;
	}
	const block = s.blockCounts.length as int32;
	s.blockCounts.push(0);
	for (let i = 0; i < KB_BUCKETED_GLYPHS_PER_BLOCK; i++) {
		s.blockEntries.push({ glyph: 0, sortKey: 0, featureValue: 0 });
	}
	return block;
}

export function kbBucketLength(s: KbScratch, bucketIndex: int32): int32 {
	const blocks = s.bucketBlocks[bucketIndex];
	if (blocks.length == 0) { return 0; }
	return ((blocks.length as int32) - 1) * KB_BUCKETED_GLYPHS_PER_BLOCK +
		s.blockCounts[blocks[blocks.length - 1]];
}

function bucketEntryIndex(s: KbScratch, bucketIndex: int32, position: int32): int32 {
	return s.bucketBlocks[bucketIndex][position / KB_BUCKETED_GLYPHS_PER_BLOCK] *
		KB_BUCKETED_GLYPHS_PER_BLOCK + position % KB_BUCKETED_GLYPHS_PER_BLOCK;
}

export function kbBucketEntry(s: KbScratch, bucketIndex: int32, position: int32): KbBucketed {
	return s.blockEntries[bucketEntryIndex(s, bucketIndex, position)];
}

function insertGlyphIntoBucket(
	s: KbScratch,
	bucketIndex: int32,
	glyph: int32,
	featureValue: uint16,
): void {
	const blocks = s.bucketBlocks[bucketIndex];
	if (blocks.length == 0 ||
		s.blockCounts[blocks[blocks.length - 1]] == KB_BUCKETED_GLYPHS_PER_BLOCK) {
		blocks.push(newBucketedGlyphBlock(s));
	}
	const block = blocks[blocks.length - 1];
	const entry = block * KB_BUCKETED_GLYPHS_PER_BLOCK + s.blockCounts[block];
	s.blockCounts[block] = s.blockCounts[block] + 1;
	s.blockEntries[entry] = { glyph, sortKey: s.storage.glyphs[glyph].sortKey, featureValue };
	s.storage.glyphs[glyph].bucketedPlusOne = entry + 1;
	s.storage.glyphs[glyph].bucketedBucketIndex = bucketIndex as uint16;
}

function lsbPositionOrBitWidth32(value: uint32): int32 {
	if (value == 0) { return 32; }
	let at: int32 = 0;
	while (((value >> (at as uint32)) & 1) == 0) { at++; }
	return at;
}

export function kbBucketGlyph(
	s: KbScratch,
	glyph: int32,
	minimumSequentialLookupIndex: int32,
): boolean {
	let result = false;
	const sequentialLookupCount = s.sequentialLookupCount as int64;

	if ((minimumSequentialLookupIndex as int64) < sequentialLookupCount) {
		const id = s.storage.glyphs[glyph].id as int64;
		const bitsPerRow = (sequentialLookupCount + 31) & ~(31 as int64);
		const onePastLastWordIndex = (id * bitsPerRow + sequentialLookupCount - 1) / 32 + 1;

		if (id < (s.configGlyphCount as int64)) {
			const configPlusOne = s.storage.glyphs[glyph].configPlusOne;
			const flatIndex = id * bitsPerRow + (minimumSequentialLookupIndex as int64);
			const matrixWord = flatIndex / 32;
			const matrixBit = (flatIndex % 32) as int32;

			if (configPlusOne == 0) {
				let at = matrixWord;
				const beforeFirstMask: uint32 = (((1 as int64) << (matrixBit as int64)) - 1) as uint32;
				let bits: uint32 = s.idSequentialLookupMatrix[at] & ~beforeFirstMask;
				at++;
				let offset: int64 = 0;

				let wordIndex = matrixWord + 1;
				while (wordIndex < onePastLastWordIndex && bits == 0) {
					bits = s.idSequentialLookupMatrix[at];
					at++;
					wordIndex++;
					offset += 32;
				}

				if (bits != 0) {
					offset += (lsbPositionOrBitWidth32(bits) - matrixBit) as int64;
					insertGlyphIntoBucket(s, (minimumSequentialLookupIndex as int64 + offset) as int32,
						glyph, 1);
					result = true;
				}
			} else {
				const config = s.storage.configs[configPlusOne - 1];
				const rowWord = (minimumSequentialLookupIndex as int64) / 32;
				let at = matrixWord;
				let atRow = rowWord;
				const beforeFirstMask: uint32 = (((1 as int64) << (matrixBit as int64)) - 1) as uint32;

				let bits: uint32 = ((s.idSequentialLookupMatrix[at] | config.enabledLookupBits[atRow]) &
					~config.disabledLookupBits[atRow]) & ~beforeFirstMask;
				at++;
				atRow++;
				let offset: int64 = 0;

				let wordIndex = matrixWord + 1;
				while (wordIndex < onePastLastWordIndex && bits == 0) {
					bits = (s.idSequentialLookupMatrix[at] | config.enabledLookupBits[atRow]) &
						~config.disabledLookupBits[atRow];
					at++;
					atRow++;
					wordIndex++;
					offset += 32;
				}

				if (bits != 0) {
					offset += (lsbPositionOrBitWidth32(bits) - matrixBit) as int64;
					const sequentialLookupIndex = (minimumSequentialLookupIndex as int64 + offset) as int32;
					let featureValue: uint16 = 1;
					for (let i = 0; i < config.nonBinaryEnabledLookups.length; i++) {
						if (config.nonBinaryEnabledLookups[i].sequentialLookupIndex == sequentialLookupIndex) {
							featureValue = config.nonBinaryEnabledLookups[i].value as uint16;
							break;
						}
					}
					insertGlyphIntoBucket(s, sequentialLookupIndex, glyph, featureValue);
					result = true;
				}
			}
		} else {
			insertGlyphIntoBucket(s, minimumSequentialLookupIndex, glyph, 1);
		}
	}
	return result;
}

export function kbGsubMutate(
	s: KbScratch,
	glyph: int32,
	currentSequentialLookupIndex: int32,
	newId: uint16,
	flags: uint32,
): void {
	s.storage.glyphs[glyph].id = newId;
	const classes = kbGlyphClasses(s.font, newId as int32);
	s.storage.glyphs[glyph].classValue = classes.classValue as uint16;
	s.storage.glyphs[glyph].markAttachmentClass = classes.markAttachmentClass as uint16;
	s.storage.glyphs[glyph].flags = (s.storage.glyphs[glyph].flags & ~KB_GLYPH_FLAG_FIRST_IN_MULTIPLE_SUBSTITUTION) | flags;

	kbUnbucketGlyph(s, glyph);
	kbBucketGlyph(s, glyph, currentSequentialLookupIndex + 1);
}

export function kbSortGlyphBucket(s: KbScratch, sequentialLookupIndex: int32): void {
	const total = kbBucketLength(s, sequentialLookupIndex);
	if (total == 0) { return; }

	let deletedCount: int32 =
		kbBucketEntry(s, sequentialLookupIndex, 0).sortKey == KB_DELETED_SORT_KEY ? 1 : 0;

	for (let forwardIndex = 1; forwardIndex < total; forwardIndex++) {
		const bucketed = kbBucketEntry(s, sequentialLookupIndex, forwardIndex);
		const sortKey = bucketed.sortKey;

		let backwardIndex = forwardIndex;
		while (backwardIndex > 0) {
			const nextBackwardIndex = backwardIndex - 1;
			const from = bucketEntryIndex(s, sequentialLookupIndex, nextBackwardIndex);
			if (s.blockEntries[from].sortKey > sortKey) {
				const to = bucketEntryIndex(s, sequentialLookupIndex, backwardIndex);
				s.blockEntries[to] = s.blockEntries[from];
				if (s.blockEntries[from].sortKey != KB_DELETED_SORT_KEY) {
					s.storage.glyphs[s.blockEntries[to].glyph].bucketedPlusOne = to + 1;
				}
			} else {
				break;
			}
			backwardIndex = nextBackwardIndex;
		}

		const to = bucketEntryIndex(s, sequentialLookupIndex, backwardIndex);
		s.blockEntries[to] = bucketed;
		if (sortKey != KB_DELETED_SORT_KEY) {
			s.storage.glyphs[bucketed.glyph].bucketedPlusOne = to + 1;
		}

		if (sortKey == KB_DELETED_SORT_KEY) { deletedCount++; }
	}

	const blocks = s.bucketBlocks[sequentialLookupIndex];
	while (blocks.length > 0) {
		const block = blocks[blocks.length - 1];
		const count = s.blockCounts[block];
		if (deletedCount >= count) {
			deletedCount -= count;
			blocks.pop();
			s.freeBlocks.push(block);
		} else {
			s.blockCounts[block] = count - deletedCount;
			break;
		}
	}
}

export function kbFreeGlyphBucket(s: KbScratch, sequentialLookupIndex: int32): void {
	const blocks = s.bucketBlocks[sequentialLookupIndex];
	for (let i = 0; i < blocks.length; i++) {
		s.freeBlocks.push(blocks[i]);
	}
	s.bucketBlocks[sequentialLookupIndex] = [];
}

export function kbFreeGlyph(s: KbScratch, glyph: int32): int32 {
	if (glyph == s.lookupOnePastLastGlyph) {
		s.lookupOnePastLastGlyph = s.storage.glyphs[glyph].next;
	}
	if (glyph == s.cluster.sentinelPrev) {
		s.cluster.sentinelPrev = s.storage.glyphs[glyph].prev;
	}
	if (glyph == s.cluster.sentinelNext) {
		s.cluster.sentinelNext = s.storage.glyphs[glyph].next;
	}

	kbUnbucketGlyph(s, glyph);

	s.storage.glyphs[s.storage.glyphs[glyph].prev].next = s.storage.glyphs[glyph].next;
	s.storage.glyphs[s.storage.glyphs[glyph].next].prev = s.storage.glyphs[glyph].prev;

	s.storage.glyphs[glyph].next = KB_FREE_GLYPH_SENTINEL;
	s.storage.glyphs[glyph].prev = s.storage.glyphs[KB_FREE_GLYPH_SENTINEL].prev;
	s.storage.glyphs[s.storage.glyphs[glyph].prev].next = glyph;
	s.storage.glyphs[KB_FREE_GLYPH_SENTINEL].prev = glyph;
	return glyph;
}
