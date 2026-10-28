import {
	KB_BLOB_HEADER_GLYPH_COUNT,
	KB_BLOB_HEADER_GLYPH_LOOKUP_MATRIX_OFFSET,
	KB_BLOB_HEADER_GLYPH_LOOKUP_SUBTABLE_MATRIX_OFFSET,
	KB_BLOB_HEADER_GPOS_LOOKUP_INDEX_OFFSET,
	KB_BLOB_HEADER_LOOKUP_COUNT,
	KB_BLOB_HEADER_LOOKUP_SUBTABLE_COUNT,
	KB_BLOB_HEADER_LOOKUP_SUBTABLE_INDEX_OFFSETS_OFFSET,
	KB_BLOB_HEADER_MAGIC,
	KB_BLOB_HEADER_SIZE,
	KB_BLOB_HEADER_TABLES,
	KB_BLOB_HEADER_VERSION,
	KB_BLOB_TABLE_ID_AVAR,
	KB_BLOB_TABLE_ID_CMAP,
	KB_BLOB_TABLE_ID_COUNT,
	KB_BLOB_TABLE_ID_FVAR,
	KB_BLOB_TABLE_ID_GDEF,
	KB_BLOB_TABLE_ID_GPOS,
	KB_BLOB_TABLE_ID_GSUB,
	KB_BLOB_TABLE_ID_HEAD,
	KB_BLOB_TABLE_ID_HHEA,
	KB_BLOB_TABLE_ID_HMTX,
	KB_BLOB_TABLE_ID_HVAR,
	KB_BLOB_TABLE_ID_MAXP,
	KB_BLOB_TABLE_ID_MVAR,
	KB_BLOB_TABLE_ID_NAME,
	KB_BLOB_TABLE_ID_OS2,
	KB_BLOB_TABLE_ID_VHEA,
	KB_BLOB_TABLE_ID_VMTX,
	KB_BLOB_TABLE_ID_VVAR,
	KB_BLOB_VERSION_CURRENT,
	KB_FOURCC_KBTS,
	KB_FOURCC_OTTO,
	KB_FOURCC_TTCF,
	KB_FOURCC_V1,
	KB_LOAD_FONT_ERROR_INVALID_FONT,
	KB_LOAD_FONT_ERROR_NEED_TO_CREATE_BLOB,
	KB_LOAD_FONT_ERROR_NONE,
	KB_LOAD_FONT_ERROR_OUT_OF_BOUNDS,
	KB_SIZE_AVAR,
	KB_SIZE_CMAP,
	KB_SIZE_CMAP_0,
	KB_SIZE_CMAP_2,
	KB_SIZE_CMAP_12_13,
	KB_SIZE_CMAP_14,
	KB_SIZE_ENCODING_RECORD,
	KB_SIZE_FVAR,
	KB_SIZE_GDEF,
	KB_SIZE_HEA,
	KB_SIZE_HEAD,
	KB_SIZE_HVAR_VVAR_COMMON,
	KB_SIZE_INSTANCE_RECORD,
	KB_SIZE_MVAR,
	KB_SIZE_MVAR_VALUE_RECORD,
	KB_SIZE_NAME,
	KB_SIZE_VARIATION_AXIS_RECORD,
	KB_SIZE_VVAR,
	KbFontBoundsError,
	kbAlign,
	kbBoundsFail,
	kbGlyphLookupMatrixIndex,
	kbSwap16,
	kbWrap32,
} from "./blob";
import {
	KbCmapSubtablePointer,
	kbGetChainedClassSequenceRule,
	kbGetChainedClassSequenceRuleSet,
	kbGetChainedSequenceRule,
	kbGetClassSequenceRule,
	kbGetClassSequenceRuleSet,
	kbGetCmapSubtable,
	kbGetLigature,
	kbGetLigatureSet,
	kbGetLookup,
	kbGetLookupList,
	kbGetSequenceRule,
	kbGetSequenceRuleSet,
	kbLookupBeginsWithCoverage,
	kbUnpackChainedSequenceContext3,
	kbUnpackChainedSequenceRule,
	kbUnpackLookup,
	kbUnpackReverseChainSubstitution,
} from "./access";
import {
	KbSwapContext,
	kbNewSwapContext,
	kbSwapArray16Context,
	kbSwapArray32Context,
	kbSwapClassDefinition,
	kbSwapCoverage,
	kbSwapDeltaSetIndexMap,
	kbSwapGposLookupSubtable,
	kbSwapGsubGposCommon,
	kbSwapGsubLookupSubtable,
	kbSwapItemVariationStore,
	kbSwapLookup,
} from "./swap";

const KB_BLOB_SIZE_LIMIT: int64 = 256 * 1024 * 1024;
const KB_CLASSES_INCLUDED_WORDS: int32 = 32;
const KB_CLASSES_INCLUDED_LENGTH: int64 = 1024;

const KB_TAG_HEAD: int64 = 0x64616568;
const KB_TAG_CMAP: int64 = 0x70616D63;
const KB_TAG_GDEF: int64 = 0x46454447;
const KB_TAG_GSUB: int64 = 0x42555347;
const KB_TAG_GPOS: int64 = 0x534F5047;
const KB_TAG_HHEA: int64 = 0x61656868;
const KB_TAG_VHEA: int64 = 0x61656876;
const KB_TAG_HMTX: int64 = 0x78746D68;
const KB_TAG_VMTX: int64 = 0x78746D76;
const KB_TAG_MAXP: int64 = 0x7078616D;
const KB_TAG_OS2: int64 = 0x322F534F;
const KB_TAG_NAME: int64 = 0x656D616E;
const KB_TAG_FVAR: int64 = 0x72617666;
const KB_TAG_AVAR: int64 = 0x72617661;
const KB_TAG_MVAR: int64 = 0x5241564D;
const KB_TAG_HVAR: int64 = 0x52415648;
const KB_TAG_VVAR: int64 = 0x52415656;

const KB_CMAP_FORMAT_PRECEDENCE: int32[] = [1, 0, 1, 0, 2, 0, 1, 0, 3, 0, 3, 0, 4, 5];

export class KbFont {
	blob: uint8[] = [];
	hasBlob: boolean = false;
	cmap: int64 = 0;
	cmap14: int64 = 0;
	error: int32 = 0;
}

export class KbLoadFontState {
	tableOffsets: int64[] = [];
	tableLengths: int64[] = [];
	lookupCount: int64 = 0;
	lookupSubtableCount: int64 = 0;
	glyphCount: int64 = 0;
	scratchSize: int64 = 0;
	glyphLookupMatrixSizeInBytes: int64 = 0;
	glyphLookupSubtableMatrixSizeInBytes: int64 = 0;
	totalSize: int64 = 0;
}

export function kbNewLoadFontState(): KbLoadFontState {
	const state = new KbLoadFontState();
	state.tableOffsets = new Array<int64>(KB_BLOB_TABLE_ID_COUNT);
	state.tableLengths = new Array<int64>(KB_BLOB_TABLE_ID_COUNT);
	return state;
}

function u16At(m: Span<uint8>, at: int64): int64 {
	return m.kbU16(at) as int64;
}

function fileU16(data: Readonly<Span<uint8>>, at: int64): int64 {
	return data.kbFileU16(at) as int64;
}

function tagToTableId(tag: int64): int32 {
	match (tag) {
		KB_TAG_HEAD => { return KB_BLOB_TABLE_ID_HEAD; },
		KB_TAG_CMAP => { return KB_BLOB_TABLE_ID_CMAP; },
		KB_TAG_GDEF => { return KB_BLOB_TABLE_ID_GDEF; },
		KB_TAG_GSUB => { return KB_BLOB_TABLE_ID_GSUB; },
		KB_TAG_GPOS => { return KB_BLOB_TABLE_ID_GPOS; },
		KB_TAG_HHEA => { return KB_BLOB_TABLE_ID_HHEA; },
		KB_TAG_VHEA => { return KB_BLOB_TABLE_ID_VHEA; },
		KB_TAG_HMTX => { return KB_BLOB_TABLE_ID_HMTX; },
		KB_TAG_VMTX => { return KB_BLOB_TABLE_ID_VMTX; },
		KB_TAG_MAXP => { return KB_BLOB_TABLE_ID_MAXP; },
		KB_TAG_OS2 => { return KB_BLOB_TABLE_ID_OS2; },
		KB_TAG_NAME => { return KB_BLOB_TABLE_ID_NAME; },
		KB_TAG_FVAR => { return KB_BLOB_TABLE_ID_FVAR; },
		KB_TAG_AVAR => { return KB_BLOB_TABLE_ID_AVAR; },
		KB_TAG_MVAR => { return KB_BLOB_TABLE_ID_MVAR; },
		KB_TAG_HVAR => { return KB_BLOB_TABLE_ID_HVAR; },
		KB_TAG_VVAR => { return KB_BLOB_TABLE_ID_VVAR; },
		_ => { return 0; },
	}
}

function selectCmapSubtable(
	m: Span<uint8>,
	cmap: int64,
	tableEnd: int64,
	font: KbFont,
): KbCmapSubtablePointer {
	let result: KbCmapSubtablePointer = { platformId: 0, encodingId: 0, at: 0 };

	const preferredFormat = 1;
	for (let it: int64 = 0; it < u16At(m, cmap + 2); it++) {
		const subtable = kbGetCmapSubtable(m, cmap, it);
		if (subtable.at + 2 <= tableEnd) {
			let format = m.kbU16(subtable.at);

			if (format > 0xFF && (format >> 8) <= 14) {
				format = kbSwap16(format);
				m.kbSetU16(subtable.at, format);
			}

			if (format == 14) {
				if (subtable.at + KB_SIZE_CMAP_14 * 2 <= tableEnd) {
					font.cmap14 = subtable.at;
				}
			} else if (result.at == 0) {
				result = subtable;
			} else if (format < 14) {
				const precedence = KB_CMAP_FORMAT_PRECEDENCE[format];
				const preferredPrecedence = KB_CMAP_FORMAT_PRECEDENCE[preferredFormat];

				if (precedence > preferredPrecedence ||
					(precedence == preferredPrecedence && subtable.platformId == 3)) {
					result = subtable;
				}
			}
		}
	}

	return result;
}

function selectCmapSubtableFromBlob(m: Span<uint8>, font: KbFont): KbCmapSubtablePointer {
	let result: KbCmapSubtablePointer = { platformId: 0, encodingId: 0, at: 0 };
	if (m.kbBlobTableLength(KB_BLOB_TABLE_ID_CMAP) >= KB_SIZE_CMAP) {
		const tableEnd = m.kbBlobTableOffset(KB_BLOB_TABLE_ID_CMAP) +
			m.kbBlobTableLength(KB_BLOB_TABLE_ID_CMAP);
		result = selectCmapSubtable(m, m.kbBlobTableOffset(KB_BLOB_TABLE_ID_CMAP), tableEnd, font);
	}
	return result;
}

function loadFontUnchecked(
	font: KbFont,
	state: KbLoadFontState,
	data: Readonly<Span<uint8>>,
	fontIndex: int32,
): int32 {
	let result = KB_LOAD_FONT_ERROR_NONE;
	const size = data.length as int64;

	if (size >= 4) {
		const fileEnd = size;
		let magic = data.kbU32(0);
		let directoryOffset: int64 = 0;

		if (magic == KB_FOURCC_TTCF) {
			magic = 0;

			if (size >= 12) {
				const fontCount = data.kbFileU32(8);

				if (((fontIndex as int64) & 0xFFFFFFFF) < fontCount && size >= 12 + 4 * fontCount) {
					directoryOffset = data.kbFileU32(12 + (fontIndex as int64) * 4);
					magic = KB_FOURCC_V1;
				}
			}
		}

		if (magic == KB_FOURCC_OTTO || magic == KB_FOURCC_V1) {
			result = KB_LOAD_FONT_ERROR_NEED_TO_CREATE_BLOB;

			const directoryTableCount = fileU16(data, directoryOffset + 4);
			const tables = directoryOffset + 12;

			const directoryTableCapacity: int64 = fileEnd - tables >= 0 ?
				(fileEnd - tables) / 16 : 0x7FFFFFFFFFFFFFFF;
			if (directoryTableCount <= directoryTableCapacity) {
				for (let tableIndex: int64 = 0; tableIndex < directoryTableCount; tableIndex++) {
					const table = tables + tableIndex * 16;
					const tableOffset = data.kbFileU32(table + 8);
					const tableLength = data.kbFileU32(table + 12);

					const tableEnd = tableOffset + tableLength;
					if (tableOffset >= tables + directoryTableCount * 16 && tableEnd <= fileEnd) {
						const tableId = tagToTableId(data.kbU32(table));

						if (tableId != 0) {
							state.tableOffsets[tableId] = tableOffset;
							state.tableLengths[tableId] = tableLength;
						}
					}
				}
			}

			{
				let totalLookupCount: int64 = 0;
				let totalSubtableCount: int64 = 0;

				const gsubGposTableIds: int32[] = [KB_BLOB_TABLE_ID_GSUB, KB_BLOB_TABLE_ID_GPOS];
				for (let gsubGposTableIndex = 0; gsubGposTableIndex < 2; gsubGposTableIndex++) {
					const tableId = gsubGposTableIds[gsubGposTableIndex];
					const length = state.tableLengths[tableId];

					if (length != 0) {
						const gsubGpos = state.tableOffsets[tableId];
						const scriptListOffset = fileU16(data, gsubGpos + 4);
						const featureListOffset = fileU16(data, gsubGpos + 6);
						const lookupListOffset = fileU16(data, gsubGpos + 8);

						if (scriptListOffset == 0 && featureListOffset == 0 && lookupListOffset == 0) {
							state.tableOffsets[tableId] = 0;
							state.tableLengths[tableId] = 0;
						} else if (scriptListOffset + 2 > length || featureListOffset + 2 > length ||
							lookupListOffset + 2 > length) {
							return KB_LOAD_FONT_ERROR_INVALID_FONT;
						} else {
							const lookupList = gsubGpos + fileU16(data, gsubGpos + 8);
							const lookupOffsets = lookupList + 2;
							const lookupCount = fileU16(data, lookupList);

							for (let lookupIndex: int64 = 0; lookupIndex < lookupCount; lookupIndex++) {
								const lookup = lookupList + fileU16(data, lookupOffsets + lookupIndex * 2);
								totalSubtableCount += fileU16(data, lookup + 4);
							}

							totalLookupCount += lookupCount;
						}
					}
				}

				state.lookupCount = totalLookupCount & 0xFFFFFFFF;
				state.lookupSubtableCount = totalSubtableCount & 0xFFFFFFFF;
			}

			{
				let glyphCount: int64 = 0;

				if (state.tableLengths[KB_BLOB_TABLE_ID_MAXP] != 0) {
					glyphCount = fileU16(data, state.tableOffsets[KB_BLOB_TABLE_ID_MAXP] + 4);
				}

				state.glyphCount = glyphCount;
			}

			const scratchSize = ((state.tableLengths[KB_BLOB_TABLE_ID_GSUB] +
				state.tableLengths[KB_BLOB_TABLE_ID_GPOS] +
				state.tableLengths[KB_BLOB_TABLE_ID_GDEF]) & 0xFFFFFFFF) * 4 / 2;

			let glyphLookupMatrixSizeInWords: int64 = 0;
			if (state.lookupCount != 0 && state.glyphCount != 0) {
				const lastIndex = kbGlyphLookupMatrixIndex(state.lookupCount - 1, state.glyphCount - 1,
					state.glyphCount);
				glyphLookupMatrixSizeInWords = lastIndex.word + 1;
			}

			let glyphLookupSubtableMatrixSizeInWords: int64 = 0;
			if (state.lookupSubtableCount != 0 && state.glyphCount != 0) {
				const lastIndex = kbGlyphLookupMatrixIndex(state.lookupSubtableCount - 1,
					state.glyphCount - 1, state.glyphCount);
				glyphLookupSubtableMatrixSizeInWords = lastIndex.word + 1;
			}

			let bump = kbAlign(0, 4) + KB_BLOB_HEADER_SIZE;
			for (let tableId = 0; tableId < KB_BLOB_TABLE_ID_COUNT; tableId++) {
				bump = kbAlign(bump, 4) + state.tableLengths[tableId];
			}
			bump = kbAlign(bump, 4) + glyphLookupMatrixSizeInWords * 4;
			bump = kbAlign(bump, 4) + glyphLookupSubtableMatrixSizeInWords * 4;
			bump = kbAlign(bump, 4) + state.lookupCount * 4;

			const outputSize = bump + 4;
			if (outputSize > KB_BLOB_SIZE_LIMIT) { throw kbBoundsFail("blob size", outputSize); }

			state.scratchSize = scratchSize & 0xFFFFFFFF;
			state.glyphLookupMatrixSizeInBytes = (glyphLookupMatrixSizeInWords * 4) & 0xFFFFFFFF;
			state.glyphLookupSubtableMatrixSizeInBytes =
				(glyphLookupSubtableMatrixSizeInWords * 4) & 0xFFFFFFFF;
			state.totalSize = outputSize;
		} else if (magic == KB_FOURCC_KBTS) {
			if (data.kbU32(KB_BLOB_HEADER_VERSION) != KB_BLOB_VERSION_CURRENT) {
				result = KB_LOAD_FONT_ERROR_INVALID_FONT;
			}

			font.blob = new Array<uint8>(data.length as int32);
			for (let i: int64 = 0; i < size; i++) {
				font.blob[i] = data[i];
			}
			font.hasBlob = true;

			const m: Span<uint8> = font.blob[0..font.blob.length];
			const preferredSubtable = selectCmapSubtableFromBlob(m, font);
			font.cmap = preferredSubtable.at;
		}
	}

	return result;
}

export function kbLoadFont(
	font: KbFont,
	state: KbLoadFontState,
	data: Readonly<Span<uint8>>,
	fontIndex: int32,
): int32 {
	try {
		return loadFontUnchecked(font, state, data, fontIndex);
	} catch (e) {
		if (e instanceof KbFontBoundsError) { return KB_LOAD_FONT_ERROR_OUT_OF_BOUNDS; }
		throw e;
	}
}

function setMatrixBit(
	m: Span<uint8>,
	matrix: int64,
	row: int64,
	glyphId: int64,
	glyphCount: int64,
): void {
	const index = kbGlyphLookupMatrixIndex(row, glyphId, glyphCount);
	const at = matrix + index.word * 4;
	m.kbSetU32(at, m.kbU32(at) | ((1 as int64) << index.bit));
}

function markMatrixCoverage(
	m: Span<uint8>,
	matrix: int64,
	row: int64,
	glyphCount: int64,
	coverage: int64,
): void {
	if (coverage != 0) {
		const format = m.kbU16(coverage);
		if (format == 1) {
			const glyphIds = coverage + 4;
			for (let glyphIndex: int64 = 0; glyphIndex < u16At(m, coverage + 2); glyphIndex++) {
				const glyphId = u16At(m, glyphIds + glyphIndex * 2);
				if (glyphId < glyphCount) {
					setMatrixBit(m, matrix, row, glyphId, glyphCount);
				}
			}
		} else if (format == 2) {
			const ranges = coverage + 4;
			for (let rangeIndex: int64 = 0; rangeIndex < u16At(m, coverage + 2); rangeIndex++) {
				const range = ranges + rangeIndex * 6;
				for (let glyphId = u16At(m, range); glyphId < u16At(m, range + 2) + 1; glyphId++) {
					if (glyphId < glyphCount) {
						setMatrixBit(m, matrix, row, glyphId, glyphCount);
					}
				}
			}
		}
	}
}

function classIncluded(classesIncluded: int32[], classId: int64): boolean {
	if (classId >= KB_CLASSES_INCLUDED_LENGTH) {
		throw kbBoundsFail("class past ClassesIncluded", classId);
	}
	return (classesIncluded[classId / 32] & (1 << ((classId % 32) as int32))) != 0;
}

function includeClass(classesIncluded: int32[], classId: int64): void {
	if (classId < KB_CLASSES_INCLUDED_LENGTH) {
		classesIncluded[classId / 32] |= 1 << ((classId % 32) as int32);
	}
}

function markMatrixClassDef(
	m: Span<uint8>,
	matrix: int64,
	row: int64,
	glyphCount: int64,
	classDefBase: int64,
	classesIncluded: int32[],
): void {
	if (classDefBase != 0) {
		const format = m.kbU16(classDefBase);
		if (format == 1) {
			const glyphClasses = classDefBase + 6;
			for (let glyphIndex: int64 = 0; glyphIndex < u16At(m, classDefBase + 4); glyphIndex++) {
				const glyphId = u16At(m, classDefBase + 2) + glyphIndex;
				const glyphClass = u16At(m, glyphClasses + glyphIndex * 2);

				if (glyphId >= KB_CLASSES_INCLUDED_LENGTH || classIncluded(classesIncluded, glyphClass)) {
					setMatrixBit(m, matrix, row, glyphId, glyphCount);
				}
			}
		} else if (format == 2) {
			const ranges = classDefBase + 4;
			for (let rangeIndex: int64 = 0; rangeIndex < u16At(m, classDefBase + 2); rangeIndex++) {
				const range = ranges + rangeIndex * 6;
				const rangeClass = u16At(m, range + 4);

				if (rangeClass >= KB_CLASSES_INCLUDED_LENGTH || classIncluded(classesIncluded, rangeClass)) {
					let onePastLastGlyphId = u16At(m, range + 2) + 1;
					if (onePastLastGlyphId > glyphCount) {
						onePastLastGlyphId = glyphCount;
					}

					for (let glyphId = u16At(m, range); glyphId < onePastLastGlyphId; glyphId++) {
						setMatrixBit(m, matrix, row, glyphId, glyphCount);
					}
				}
			}
		}
	}
}

struct KbTableHeader {
	at: int64;
	end: int64;
	tooShort: boolean;
}

function blobTableHeaderChecked(m: Span<uint8>, tableId: int32, headerSize: int64): KbTableHeader {
	let result: KbTableHeader = { at: 0, end: 0, tooShort: false };
	const length = m.kbBlobTableLength(tableId);
	if (length != 0) {
		if (length >= headerSize) {
			result.at = m.kbBlobTableOffset(tableId);
			result.end = result.at + length;
		} else {
			result.tooShort = true;
		}
	}
	return result;
}

function swapCmapSubtable(m: Span<uint8>, font: KbFont, cmap: int64, tableEnd: int64): boolean {
	let tableValid = false;
	m.kbSwapU16At(cmap);
	m.kbSwapU16At(cmap + 2);

	const records = cmap + KB_SIZE_CMAP;

	if (records + u16At(m, cmap + 2) * KB_SIZE_ENCODING_RECORD <= tableEnd) {
		for (let it: int64 = 0; it < u16At(m, cmap + 2); it++) {
			const record = records + it * KB_SIZE_ENCODING_RECORD;
			m.kbSwapU16At(record + 2);
			m.kbSwapU16At(record);
			m.kbSwapU32At(record + 4);
		}

		const preferredSubtable = selectCmapSubtable(m, cmap, tableEnd, font);
		if (preferredSubtable.at != 0) {
			const subtable = preferredSubtable.at;
			const subtableFormat = m.kbU16(subtable);
			match (subtableFormat) {
				0 => {
					if (subtable + KB_SIZE_CMAP_0 <= tableEnd) {
						m.kbSwapU16At(subtable + 2);
						m.kbSwapU16At(subtable + 4);
						tableValid = true;
					}
				},
				2 => {
					if (m.kbSwapArray16(subtable + 2, 258, tableEnd)) {
						let subHeaderCount: int64 = 0;
						for (let it: int64 = 0; it < 256; it++) {
							const subHeaderIndex = u16At(m, subtable + 6 + it * 2);
							if (subHeaderIndex + 1 > subHeaderCount) {
								subHeaderCount = subHeaderIndex + 1;
							}
						}

						const subHeaders = subtable + KB_SIZE_CMAP_2;
						if (m.kbSwapArray16(subHeaders, 4 * subHeaderCount, tableEnd)) {
							const glyphIds = subHeaders + subHeaderCount * 8;

							let glyphIdCount: int64 = 0;
							for (let it: int64 = 0; it < subHeaderCount; it++) {
								const subHeader = subHeaders + it * 8;

								const onePastLastGlyphId = subHeader + 6 +
									(u16At(m, subHeader + 6) / 2 + u16At(m, subHeader + 2)) * 2;
								const difference = (onePastLastGlyphId - glyphIds) / 2;
								if (difference > glyphIdCount) {
									glyphIdCount = difference;
								}
							}

							if (m.kbSwapArray16(glyphIds, glyphIdCount, tableEnd)) {
								tableValid = true;
							}
						}
					}
				},
				4 => {
					if (m.kbSwapArray16(subtable + 2, 5, tableEnd) &&
						m.kbSwapArray16(subtable + 14, u16At(m, subtable + 6) * 2 + 1, tableEnd)) {
						const segmentCount = u16At(m, subtable + 6) / 2;
						const endCodes = subtable + 14;
						const startCodes = endCodes + (segmentCount + 1) * 2;
						const idDeltas = startCodes + segmentCount * 2;
						const idRangeOffsets = idDeltas + segmentCount * 2;
						const glyphIds = idRangeOffsets + segmentCount * 2;

						let glyphIdCount: int64 = 0;

						for (let segmentIndex: int64 = 0; segmentIndex < segmentCount; segmentIndex++) {
							let offset = u16At(m, idRangeOffsets + segmentIndex * 2);
							const startCode = u16At(m, startCodes + segmentIndex * 2);
							const endCode = u16At(m, endCodes + segmentIndex * 2);

							if (startCode == 0xFFFF && endCode == 0xFFFF) {
								m.kbSetU16(idRangeOffsets + segmentIndex * 2, 0);
								offset = 0;
							}

							if (offset != 0) {
								const onePastIdLookup = idRangeOffsets + segmentIndex * 2 +
									(endCode - startCode + 1) * 2 + (offset / 2) * 2;
								const difference = (onePastIdLookup - glyphIds) / 2;
								if (difference > glyphIdCount) {
									glyphIdCount = difference;
								}
							}
						}

						if (m.kbSwapArray16(glyphIds, glyphIdCount, tableEnd)) {
							tableValid = true;
						}
					}
				},
				6 => {
					if (m.kbSwapArray16(subtable + 2, 4, tableEnd) &&
						m.kbSwapArray16(subtable + 10, u16At(m, subtable + 8), tableEnd)) {
						tableValid = true;
					}
				},
				12 => {
					if (m.kbSwapArray32(subtable + 4, 3, tableEnd) &&
						m.kbSwapArray32(subtable + KB_SIZE_CMAP_12_13, (m.kbU32(subtable + 12) * 3) & 0xFFFFFFFF,
							tableEnd)) {
						tableValid = true;
					}
				},
				_ => {},
			}

			font.cmap = subtable;
		}
	}

	return tableValid;
}

function swapHeadAndTables(m: Span<uint8>, font: KbFont): boolean {
	let invalid = false;

	const head = blobTableHeaderChecked(m, KB_BLOB_TABLE_ID_HEAD, KB_SIZE_HEAD);
	invalid = invalid || head.tooShort;
	if (head.at != 0) {
		m.kbSwapArray16Unchecked(head.at, 2);
		m.kbSwapArray32Unchecked(head.at + 4, 2);
		m.kbSwapArray16Unchecked(head.at + 16, 2);
		m.kbSwapArray16Unchecked(head.at + 36, 9);
	}

	font.hasBlob = true;

	const cmap = blobTableHeaderChecked(m, KB_BLOB_TABLE_ID_CMAP, KB_SIZE_CMAP);
	invalid = invalid || cmap.tooShort;
	if (cmap.at != 0) {
		if (!swapCmapSubtable(m, font, cmap.at, cmap.end)) {
			invalid = true;
		}
	}

	const gdefLength = m.kbBlobTableLength(KB_BLOB_TABLE_ID_GDEF);
	if (gdefLength != 0) {
		const gdef = m.kbBlobTableOffset(KB_BLOB_TABLE_ID_GDEF);
		const tableEnd = gdef + gdefLength;

		if (m.kbSwapArray16(gdef, 6, tableEnd)) {
			if (u16At(m, gdef + 2) >= 2) {
				if (gdefLength >= 14) {
					m.kbSwapU16At(gdef + 12);

					if (u16At(m, gdef + 2) == 3) {
						if (gdefLength >= KB_SIZE_GDEF) {
							m.kbSwapU32At(gdef + 14);
						} else {
							invalid = true;
						}
					}
				} else {
					invalid = true;
				}
			}
		} else {
			invalid = true;
		}
	}

	const heaTableIds: int32[] = [KB_BLOB_TABLE_ID_HHEA, KB_BLOB_TABLE_ID_VHEA];
	for (let heaTableIndex = 0; heaTableIndex < 2; heaTableIndex++) {
		const heaLength = m.kbBlobTableLength(heaTableIds[heaTableIndex]);
		if (heaLength != 0) {
			const hea = m.kbBlobTableOffset(heaTableIds[heaTableIndex]);
			if (!m.kbSwapArray16(hea, KB_SIZE_HEA / 2, hea + heaLength)) {
				invalid = true;
			}
		}
	}

	const mtxTableIds: int32[] = [KB_BLOB_TABLE_ID_HMTX, KB_BLOB_TABLE_ID_VMTX];
	for (let mtxTableIndex = 0; mtxTableIndex < 2; mtxTableIndex++) {
		const mtxLength = m.kbBlobTableLength(mtxTableIds[mtxTableIndex]);
		if (mtxLength != 0) {
			m.kbSwapArray16Unchecked(m.kbBlobTableOffset(mtxTableIds[mtxTableIndex]), mtxLength / 2);
		}
	}

	const maxpLength = m.kbBlobTableLength(KB_BLOB_TABLE_ID_MAXP);
	if (maxpLength != 0) {
		if (maxpLength >= 6) {
			const maxp = m.kbBlobTableOffset(KB_BLOB_TABLE_ID_MAXP);
			const tableEnd = maxp + maxpLength;

			m.kbSwapU16At(maxp);
			m.kbSwapU16At(maxp + 2);

			let u16Count: int64 = 0;
			if (u16At(m, maxp) == 0 && u16At(m, maxp + 2) == 0x5000) {
				u16Count = 1;
			} else if (u16At(m, maxp) == 1 && u16At(m, maxp + 2) == 0) {
				u16Count = 14;
			}

			if (m.kbSwapArray16(maxp + 4, u16Count, tableEnd)) {
				m.kbSetU32(KB_BLOB_HEADER_GLYPH_COUNT, m.kbU16(maxp + 4));
			} else {
				invalid = true;
			}
		} else {
			invalid = true;
		}
	}

	const os2Length = m.kbBlobTableLength(KB_BLOB_TABLE_ID_OS2);
	if (os2Length != 0) {
		const os2 = m.kbBlobTableOffset(KB_BLOB_TABLE_ID_OS2);

		if (os2Length >= 68) {
			m.kbSwapArray16Unchecked(os2, 16);
			m.kbSwapArray32Unchecked(os2 + 42, 4);
			m.kbSwapArray16Unchecked(os2 + 62, 3);

			const version = u16At(m, os2);

			if (os2Length >= 78) {
				m.kbSwapArray16Unchecked(os2 + 68, 5);

				if (version >= 1) {
					if (os2Length >= 86) {
						m.kbSwapArray32Unchecked(os2 + 78, 2);

						if (version >= 2) {
							if (os2Length >= 96) {
								m.kbSwapArray16Unchecked(os2 + 86, 5);

								if (version >= 5) {
									if (os2Length >= 100) {
										m.kbSwapArray16Unchecked(os2 + 96, 2);
									} else {
										invalid = true;
									}
								}
							} else {
								invalid = true;
							}
						}
					} else {
						invalid = true;
					}
				}
			}
		} else {
			invalid = true;
		}
	}

	const name = blobTableHeaderChecked(m, KB_BLOB_TABLE_ID_NAME, KB_SIZE_NAME);
	invalid = invalid || name.tooShort;
	if (name.at != 0) {
		m.kbSwapArray16Unchecked(name.at, 3);

		const nameRecords = name.at + KB_SIZE_NAME;

		const u16Count = u16At(m, name.at + 2) * 6;
		if (!m.kbSwapArray16(nameRecords, u16Count, name.end)) {
			invalid = true;
		}
	}

	return invalid;
}

function swapVariationTables(
	m: Span<uint8>,
	c: KbSwapContext,
): boolean {
	let invalid = false;

	const fvar = blobTableHeaderChecked(m, KB_BLOB_TABLE_ID_FVAR, KB_SIZE_FVAR);
	invalid = invalid || fvar.tooShort;
	if (fvar.at != 0) {
		m.kbSwapArray16Unchecked(fvar.at, 8);

		const axes = fvar.at + u16At(m, fvar.at + 4);
		const axisCount = u16At(m, fvar.at + 8);

		const instances = axes + axisCount * KB_SIZE_VARIATION_AXIS_RECORD;
		const instanceCount = u16At(m, fvar.at + 12);
		const instanceSize = u16At(m, fvar.at + 14);

		if (instances + kbWrap32(u16At(m, fvar.at + 12) * u16At(m, fvar.at + 14)) <= fvar.end) {
			for (let axisIndex: int64 = 0; axisIndex < axisCount; axisIndex++) {
				const axis = axes + axisIndex * KB_SIZE_VARIATION_AXIS_RECORD;

				m.kbSwapArray32Unchecked(axis + 4, 3);
				m.kbSwapArray16Unchecked(axis + 16, 2);
			}

			const instancesContainPostscriptNameId = instanceSize >= KB_SIZE_INSTANCE_RECORD + 4 * axisCount + 2;

			for (let instanceIndex: int64 = 0; instanceIndex < instanceCount; instanceIndex++) {
				const instance = instances + instanceIndex * instanceSize;
				const instanceCoordinates = instance + KB_SIZE_INSTANCE_RECORD;

				m.kbSwapU16At(instance);
				m.kbSwapArray32Unchecked(instanceCoordinates, axisCount);

				if (instancesContainPostscriptNameId) {
					m.kbSwapU16At(instanceCoordinates + axisCount * 4);
				}
			}
		} else {
			invalid = true;
		}
	}

	const avar = blobTableHeaderChecked(m, KB_BLOB_TABLE_ID_AVAR, KB_SIZE_AVAR);
	invalid = invalid || avar.tooShort;
	if (avar.at != 0) {
		m.kbSwapArray16Unchecked(avar.at, 4);

		let at = avar.at + KB_SIZE_AVAR;
		for (let axisIndex: int64 = 0; axisIndex < u16At(m, avar.at + 6); axisIndex++) {
			const segmentMaps = at;

			if (segmentMaps + 2 <= avar.end) {
				m.kbSwapU16At(segmentMaps);

				const axisValueMaps = segmentMaps + 2;
				if (m.kbSwapArray16(axisValueMaps, 2 * u16At(m, segmentMaps), avar.end)) {
					at = axisValueMaps + u16At(m, segmentMaps) * 4;
				} else {
					invalid = true;
					break;
				}
			} else {
				invalid = true;
				break;
			}
		}
	}

	const hvarVvarIds: int32[] = [KB_BLOB_TABLE_ID_HVAR, KB_BLOB_TABLE_ID_VVAR];
	const hvarVvarSizes: int64[] = [KB_SIZE_HVAR_VVAR_COMMON, KB_SIZE_VVAR];
	for (let tableIdIndex = 0; tableIdIndex < 2; tableIdIndex++) {
		const tableId = hvarVvarIds[tableIdIndex];
		const hvarVvar = blobTableHeaderChecked(m, tableId, hvarVvarSizes[tableIdIndex]);
		invalid = invalid || hvarVvar.tooShort;

		if (hvarVvar.at != 0) {
			const at = hvarVvar.at;
			m.kbSwapArray16Unchecked(at, 2);
			m.kbSwapArray32Unchecked(at + 4, 4);

			kbSwapItemVariationStore(m, c, at + m.kbU32(at + 4));

			if (m.kbU32(at + 8) != 0) {
				kbSwapDeltaSetIndexMap(m, c, at + m.kbU32(at + 8));
			}
			if (m.kbU32(at + 12) != 0) {
				kbSwapDeltaSetIndexMap(m, c, at + m.kbU32(at + 12));
			}
			if (m.kbU32(at + 16) != 0) {
				kbSwapDeltaSetIndexMap(m, c, at + m.kbU32(at + 16));
			}

			if (tableId == KB_BLOB_TABLE_ID_VVAR) {
				m.kbSwapU32At(at + 20);

				if (m.kbU32(at + 20) != 0) {
					kbSwapDeltaSetIndexMap(m, c, at + m.kbU32(at + 20));
				}
			}
		}
	}

	const mvar = blobTableHeaderChecked(m, KB_BLOB_TABLE_ID_MVAR, KB_SIZE_MVAR);
	invalid = invalid || mvar.tooShort;
	if (mvar.at != 0) {
		m.kbSwapArray16Unchecked(mvar.at, 6);

		const valueRecordCount = u16At(m, mvar.at + 8);
		const valueRecordSize = u16At(m, mvar.at + 6);

		let valueRecordAt = mvar.at + KB_SIZE_MVAR;
		if (valueRecordSize >= KB_SIZE_MVAR_VALUE_RECORD &&
			valueRecordAt + valueRecordCount * valueRecordSize <= mvar.end) {
			for (let valueRecordIndex: int64 = 0; valueRecordIndex < valueRecordCount; valueRecordIndex++) {
				m.kbSwapArray16Unchecked(valueRecordAt + 4, 2);

				valueRecordAt += valueRecordSize;
			}

			kbSwapItemVariationStore(m, c, mvar.at + u16At(m, mvar.at + 10));
		} else {
			invalid = true;
		}
	}

	return invalid;
}

function swapGdefDefinitions(m: Span<uint8>, c: KbSwapContext): void {
	if (m.kbBlobTableLength(KB_BLOB_TABLE_ID_GDEF) != 0) {
		const gdef = m.kbBlobTableOffset(KB_BLOB_TABLE_ID_GDEF);

		if (u16At(m, gdef + 4) != 0) {
			kbSwapClassDefinition(m, c, gdef + u16At(m, gdef + 4));
		}

		if (u16At(m, gdef + 10) != 0) {
			kbSwapClassDefinition(m, c, gdef + u16At(m, gdef + 10));
		}

		if (u16At(m, gdef + 2) >= 2 && u16At(m, gdef + 12) != 0) {
			const markGlyphSets = gdef + u16At(m, gdef + 12);
			kbSwapArray16Context(m, c, markGlyphSets, 2);
			if (m.kbU16(markGlyphSets) == 1) {
				const coverageOffsets = markGlyphSets + 4;
				kbSwapArray32Context(m, c, coverageOffsets, u16At(m, markGlyphSets + 2));

				for (let markGlyphSetIndex: int64 = 0; markGlyphSetIndex < u16At(m, markGlyphSets + 2);
					markGlyphSetIndex++) {
					const coverageOffset = m.kbU32(coverageOffsets + markGlyphSetIndex * 4);
					kbSwapCoverage(m, c, markGlyphSets + coverageOffset);
				}
			}
		}

		if (u16At(m, gdef + 2) >= 3 && m.kbU32(gdef + 14) != 0) {
			kbSwapItemVariationStore(m, c, gdef + m.kbU32(gdef + 14));
		}
	}
}

function swapLookupLists(m: Span<uint8>, c: KbSwapContext): void {
	const gdef = m.kbBlobTableData(KB_BLOB_TABLE_ID_GDEF);

	const tableIds: int32[] = [KB_BLOB_TABLE_ID_GSUB, KB_BLOB_TABLE_ID_GPOS];
	for (let tableIdIndex = 0; tableIdIndex < 2; tableIdIndex++) {
		const gsubGpos = m.kbBlobTableData(tableIds[tableIdIndex]);
		const inGpos = tableIds[tableIdIndex] == KB_BLOB_TABLE_ID_GPOS;

		if (gsubGpos != 0) {
			kbSwapGsubGposCommon(m, c, gsubGpos);

			const lookupList = kbGetLookupList(m, gsubGpos);
			m.kbSwapU16At(lookupList);
			kbSwapArray16Context(m, c, lookupList + 2, u16At(m, lookupList));

			for (let lookupIndex: int64 = 0; lookupIndex < u16At(m, lookupList); lookupIndex++) {
				const packedLookup = kbGetLookup(m, lookupList, lookupIndex);

				if (kbSwapLookup(m, c, packedLookup)) {
					const lookup = kbUnpackLookup(m, gdef, packedLookup);

					for (let subtableIndex: int64 = 0; subtableIndex < (lookup.subtableCount as int64);
						subtableIndex++) {
						const base = packedLookup + u16At(m, lookup.subtableOffsets + subtableIndex * 2);

						if (inGpos) {
							kbSwapGposLookupSubtable(m, c, lookup.type, base);
						} else {
							kbSwapGsubLookupSubtable(m, c, lookup.type, base);
						}
					}
				}
			}
		}
	}
}

function bakeSequenceContext(
	m: Span<uint8>,
	base: int64,
	subtableMatrix: int64,
	runningSubtableIndex: int64,
	glyphCount: int64,
): int64 {
	let coverage: int64 = 0;
	const format = m.kbU16(base);
	if (format == 1) {
		for (let setIndex: int64 = 0; setIndex < u16At(m, base + 4); setIndex++) {
			const set = kbGetSequenceRuleSet(m, base, setIndex);

			if (set != 0) {
				for (let ruleIndex: int64 = 0; ruleIndex < u16At(m, set); ruleIndex++) {
					const rule = kbGetSequenceRule(m, set, ruleIndex);

					const sequenceGlyphIds = rule + 4;
					for (let inputIndex: int64 = 1; inputIndex < u16At(m, rule); inputIndex++) {
						const glyphId = u16At(m, sequenceGlyphIds + (inputIndex - 1) * 2);
						setMatrixBit(m, subtableMatrix, runningSubtableIndex, glyphId, glyphCount);
					}
				}
			}
		}
	} else if (format == 2) {
		const classDefBase = base + u16At(m, base + 4);

		const classesIncluded: int32[] = new Array<int32>(KB_CLASSES_INCLUDED_WORDS);

		for (let setIndex: int64 = 0; setIndex < u16At(m, base + 6); setIndex++) {
			const set = kbGetClassSequenceRuleSet(m, base, setIndex);
			if (set != 0) {
				for (let ruleIndex: int64 = 0; ruleIndex < u16At(m, set); ruleIndex++) {
					const rule = kbGetClassSequenceRule(m, set, ruleIndex);
					const sequenceClasses = rule + 4;

					for (let sequenceIndex: int64 = 1; sequenceIndex < u16At(m, rule); sequenceIndex++) {
						includeClass(classesIncluded, u16At(m, sequenceClasses + (sequenceIndex - 1) * 2));
					}
				}
			}
		}

		markMatrixClassDef(m, subtableMatrix, runningSubtableIndex, glyphCount, classDefBase,
			classesIncluded);
	} else if (format == 3) {
		const coverageOffsets = base + 6;

		for (let coverageIndex: int64 = 1; coverageIndex < u16At(m, base + 2); coverageIndex++) {
			const substCoverage = base + u16At(m, coverageOffsets + coverageIndex * 2);

			markMatrixCoverage(m, subtableMatrix, runningSubtableIndex, glyphCount, substCoverage);
		}

		coverage = base + u16At(m, coverageOffsets);
	}
	return coverage;
}

function bakeChainedSequenceContext(
	m: Span<uint8>,
	base: int64,
	subtableMatrix: int64,
	runningSubtableIndex: int64,
	glyphCount: int64,
): int64 {
	let coverage: int64 = 0;
	const format = m.kbU16(base);
	if (format == 1) {
		const ruleSetOffsets = base + 6;

		for (let setIndex: int64 = 0; setIndex < u16At(m, base + 4); setIndex++) {
			const set = base + u16At(m, ruleSetOffsets + setIndex * 2);
			for (let ruleIndex: int64 = 0; ruleIndex < u16At(m, set); ruleIndex++) {
				const rule = kbGetChainedClassSequenceRule(m, set, ruleIndex);
				const unpacked = kbUnpackChainedSequenceRule(m, rule, false);

				for (let backtrackIndex: int64 = 0; backtrackIndex < (unpacked.backtrackCount as int64);
					backtrackIndex++) {
					const glyphId = u16At(m, unpacked.backtrack + backtrackIndex * 2);
					setMatrixBit(m, subtableMatrix, runningSubtableIndex, glyphId, glyphCount);
				}

				for (let inputIndex: int64 = 1; inputIndex < (unpacked.inputCount as int64); inputIndex++) {
					const glyphId = u16At(m, unpacked.input + (inputIndex - 1) * 2);
					setMatrixBit(m, subtableMatrix, runningSubtableIndex, glyphId, glyphCount);
				}

				for (let lookaheadIndex: int64 = 0; lookaheadIndex < (unpacked.lookaheadCount as int64);
					lookaheadIndex++) {
					const glyphId = u16At(m, unpacked.lookahead + lookaheadIndex * 2);
					setMatrixBit(m, subtableMatrix, runningSubtableIndex, glyphId, glyphCount);
				}
			}
		}
	} else if (format == 2) {
		const backtrackClassDefOffset = u16At(m, base + 4);
		const inputClassDefOffset = u16At(m, base + 6);
		const lookaheadClassDefOffset = u16At(m, base + 8);
		let backtrackClassDefinition: int64 = 0;
		if (backtrackClassDefOffset != 0) {
			backtrackClassDefinition = base + backtrackClassDefOffset;
		}
		let inputClassDefinition: int64 = 0;
		if (inputClassDefOffset != 0) {
			inputClassDefinition = base + inputClassDefOffset;
		}
		let lookaheadClassDefinition: int64 = 0;
		if (lookaheadClassDefOffset != 0) {
			lookaheadClassDefinition = base + lookaheadClassDefOffset;
		}

		const backtrackClassesIncluded: int32[] = new Array<int32>(KB_CLASSES_INCLUDED_WORDS);
		const inputClassesIncluded: int32[] = new Array<int32>(KB_CLASSES_INCLUDED_WORDS);
		const lookaheadClassesIncluded: int32[] = new Array<int32>(KB_CLASSES_INCLUDED_WORDS);

		for (let setIndex: int64 = 0; setIndex < u16At(m, base + 10); setIndex++) {
			const set = kbGetChainedClassSequenceRuleSet(m, base, setIndex);
			if (set != 0) {
				for (let ruleIndex: int64 = 0; ruleIndex < u16At(m, set); ruleIndex++) {
					const rule = kbGetChainedSequenceRule(m, set, ruleIndex);
					const unpacked = kbUnpackChainedSequenceRule(m, rule, false);

					for (let backtrackIndex: int64 = 0; backtrackIndex < (unpacked.backtrackCount as int64);
						backtrackIndex++) {
						includeClass(backtrackClassesIncluded, u16At(m, unpacked.backtrack + backtrackIndex * 2));
					}

					for (let inputIndex: int64 = 1; inputIndex < (unpacked.inputCount as int64); inputIndex++) {
						includeClass(inputClassesIncluded, u16At(m, unpacked.input + (inputIndex - 1) * 2));
					}

					for (let lookaheadIndex: int64 = 0; lookaheadIndex < (unpacked.lookaheadCount as int64);
						lookaheadIndex++) {
						includeClass(lookaheadClassesIncluded, u16At(m, unpacked.lookahead + lookaheadIndex * 2));
					}
				}
			}
		}

		markMatrixClassDef(m, subtableMatrix, runningSubtableIndex, glyphCount, backtrackClassDefinition,
			backtrackClassesIncluded);
		markMatrixClassDef(m, subtableMatrix, runningSubtableIndex, glyphCount, inputClassDefinition,
			inputClassesIncluded);
		markMatrixClassDef(m, subtableMatrix, runningSubtableIndex, glyphCount, lookaheadClassDefinition,
			lookaheadClassesIncluded);
	} else if (format == 3) {
		const unpacked = kbUnpackChainedSequenceContext3(m, base, false);

		coverage = base + u16At(m, unpacked.inputCoverageOffsets);

		for (let index: int64 = 0; index < (unpacked.backtrackCount as int64); index++) {
			const subCoverage = base + u16At(m, unpacked.backtrackCoverageOffsets + index * 2);
			markMatrixCoverage(m, subtableMatrix, runningSubtableIndex, glyphCount, subCoverage);
		}

		for (let index: int64 = 1; index < (unpacked.inputCount as int64); index++) {
			const subCoverage = base + u16At(m, unpacked.inputCoverageOffsets + index * 2);
			markMatrixCoverage(m, subtableMatrix, runningSubtableIndex, glyphCount, subCoverage);
		}

		for (let index: int64 = 0; index < (unpacked.lookaheadCount as int64); index++) {
			const subCoverage = base + u16At(m, unpacked.lookaheadCoverageOffsets + index * 2);
			markMatrixCoverage(m, subtableMatrix, runningSubtableIndex, glyphCount, subCoverage);
		}
	}
	return coverage;
}

function bakeMatrices(m: Span<uint8>, state: KbLoadFontState, bumpAfterTables: int64): void {
	const glyphCount = m.kbU32(KB_BLOB_HEADER_GLYPH_COUNT);
	const lookupCount = m.kbU32(KB_BLOB_HEADER_LOOKUP_COUNT);

	const glyphLookupMatrix = kbAlign(bumpAfterTables, 4);
	const glyphLookupSubtableMatrix = kbAlign(glyphLookupMatrix + state.glyphLookupMatrixSizeInBytes, 4);
	const lookupSubtableIndexOffsets = kbAlign(glyphLookupSubtableMatrix +
		state.glyphLookupSubtableMatrixSizeInBytes, 4);

	const gdef = m.kbBlobTableData(KB_BLOB_TABLE_ID_GDEF);

	let gposLookupIndexOffset: int64 = 0;
	let runningLookupIndex: int64 = 0;
	let runningSubtableIndex: int64 = 0;

	const tableIds: int32[] = [KB_BLOB_TABLE_ID_GSUB, KB_BLOB_TABLE_ID_GPOS];
	for (let tableIdIndex = 0; tableIdIndex < 2; tableIdIndex++) {
		const tableId = tableIds[tableIdIndex];

		if (m.kbBlobTableLength(tableId) != 0) {
			const shapingTable = m.kbBlobTableOffset(tableId);
			const inGpos = tableId == KB_BLOB_TABLE_ID_GPOS;

			const lookupList = kbGetLookupList(m, shapingTable);
			for (let lookupIndex: int64 = 0; lookupIndex < u16At(m, lookupList); lookupIndex++) {
				const packedLookup = kbGetLookup(m, lookupList, lookupIndex);
				const lookup = kbUnpackLookup(m, gdef, packedLookup);

				m.kbSetU32(lookupSubtableIndexOffsets + runningLookupIndex * 4, runningSubtableIndex);

				for (let subtableIndex: int64 = 0; subtableIndex < (lookup.subtableCount as int64);
					subtableIndex++) {
					let lookupType = lookup.type;
					let base = packedLookup + u16At(m, lookup.subtableOffsets + subtableIndex * 2);

					let extensionSteps: int64 = 0;
					while ((!inGpos && lookupType == 7) || (inGpos && lookupType == 9)) {
						const extension = base;

						lookupType = m.kbU16(extension + 2);
						base = extension + m.kbU32(extension + 4);

						extensionSteps += 1;
						if (extensionSteps > (m.length as int64)) {
							throw kbBoundsFail("extension chain does not end", base);
						}
					}

					let coverage: int64 = 0;

					if (kbLookupBeginsWithCoverage(inGpos, lookupType, m.kbU16(base))) {
						coverage = base + u16At(m, base + 2);
					}

					if (!inGpos && lookupType == 4) {
						for (let setIndex: int64 = 0; setIndex < u16At(m, base + 4); setIndex++) {
							const set = kbGetLigatureSet(m, base, setIndex);
							for (let ligatureIndex: int64 = 0; ligatureIndex < u16At(m, set); ligatureIndex++) {
								const ligature = kbGetLigature(m, set, ligatureIndex);
								const ids = ligature + 4;

								for (let idIndex: int64 = 1; idIndex < u16At(m, ligature + 2); idIndex++) {
									const glyphId = u16At(m, ids + (idIndex - 1) * 2);
									setMatrixBit(m, glyphLookupSubtableMatrix, runningSubtableIndex, glyphId,
										glyphCount);
								}
							}
						}
					} else if ((!inGpos && lookupType == 5) || (inGpos && lookupType == 7)) {
						const contextCoverage = bakeSequenceContext(m, base, glyphLookupSubtableMatrix,
							runningSubtableIndex, glyphCount);
						if (contextCoverage != 0) { coverage = contextCoverage; }
					} else if ((!inGpos && lookupType == 6) || (inGpos && lookupType == 8)) {
						const contextCoverage = bakeChainedSequenceContext(m, base, glyphLookupSubtableMatrix,
							runningSubtableIndex, glyphCount);
						if (contextCoverage != 0) { coverage = contextCoverage; }
					} else if (!inGpos && lookupType == 8) {
						const unpacked = kbUnpackReverseChainSubstitution(m, base, false);

						for (let backtrackIndex: int64 = 0; backtrackIndex < (unpacked.backtrackCount as int64);
							backtrackIndex++) {
							const subCoverage = base + u16At(m, unpacked.backtrackCoverageOffsets + backtrackIndex * 2);
							markMatrixCoverage(m, glyphLookupSubtableMatrix, runningSubtableIndex, glyphCount,
								subCoverage);
						}

						for (let lookaheadIndex: int64 = 0; lookaheadIndex < (unpacked.lookaheadCount as int64);
							lookaheadIndex++) {
							const subCoverage = base + u16At(m, unpacked.lookaheadCoverageOffsets + lookaheadIndex * 2);
							markMatrixCoverage(m, glyphLookupSubtableMatrix, runningSubtableIndex, glyphCount,
								subCoverage);
						}
					}

					markMatrixCoverage(m, glyphLookupMatrix, runningLookupIndex, glyphCount, coverage);
					markMatrixCoverage(m, glyphLookupSubtableMatrix, runningSubtableIndex, glyphCount, coverage);

					runningSubtableIndex += 1;
				}

				runningLookupIndex += 1;
			}

			if (!inGpos) {
				gposLookupIndexOffset = runningLookupIndex;
			}
		}
	}

	m.kbSetU32(KB_BLOB_HEADER_GPOS_LOOKUP_INDEX_OFFSET, gposLookupIndexOffset);
	m.kbSetU32(KB_BLOB_HEADER_GLYPH_LOOKUP_MATRIX_OFFSET, glyphLookupMatrix);
	m.kbSetU32(KB_BLOB_HEADER_GLYPH_LOOKUP_SUBTABLE_MATRIX_OFFSET, glyphLookupSubtableMatrix);
	m.kbSetU32(KB_BLOB_HEADER_LOOKUP_SUBTABLE_INDEX_OFFSETS_OFFSET, lookupSubtableIndexOffsets);
}

function placeBlobUnchecked(
	font: KbFont,
	state: KbLoadFontState,
	data: Readonly<Span<uint8>>,
): int32 {
	let result = KB_LOAD_FONT_ERROR_NONE;

	if (state.totalSize != 0) {
		font.blob = new Array<uint8>(state.totalSize as int32);
		const m: Span<uint8> = font.blob[0..font.blob.length];

		let bump = KB_BLOB_HEADER_SIZE;

		m.kbSetU32(KB_BLOB_HEADER_MAGIC, KB_FOURCC_KBTS);
		m.kbSetU32(KB_BLOB_HEADER_VERSION, KB_BLOB_VERSION_CURRENT);
		m.kbSetU32(KB_BLOB_HEADER_LOOKUP_COUNT, state.lookupCount);
		m.kbSetU32(KB_BLOB_HEADER_LOOKUP_SUBTABLE_COUNT, state.lookupSubtableCount);

		for (let tableId = 0; tableId < KB_BLOB_TABLE_ID_COUNT; tableId++) {
			const inOffset = state.tableOffsets[tableId];
			const inLength = state.tableLengths[tableId];
			const outTable = KB_BLOB_HEADER_TABLES + (tableId as int64) * 8;

			const tableBase = kbAlign(bump, 4);
			bump = tableBase + inLength;
			m.kbSetU32(outTable, tableBase);
			m.kbSetU32(outTable + 4, inLength);

			for (let i: int64 = 0; i < inLength; i++) {
				m[tableBase + i] = data[inOffset + i];
			}
		}

		if (swapHeadAndTables(m, font)) {
			result = KB_LOAD_FONT_ERROR_INVALID_FONT;
		}

		const c = kbNewSwapContext(state.totalSize, state.scratchSize / 4);

		if (swapVariationTables(m, c)) {
			result = KB_LOAD_FONT_ERROR_INVALID_FONT;
		}

		swapGdefDefinitions(m, c);
		swapLookupLists(m, c);

		if (result == KB_LOAD_FONT_ERROR_NONE && m.kbBlobTableLength(KB_BLOB_TABLE_ID_MAXP) != 0) {
			bakeMatrices(m, state, bump);
		}
	}

	return result;
}

export function kbPlaceBlob(
	font: KbFont,
	state: KbLoadFontState,
	data: Readonly<Span<uint8>>,
): int32 {
	let result = KB_LOAD_FONT_ERROR_NONE;
	try {
		result = placeBlobUnchecked(font, state, data);
	} catch (e) {
		if (e instanceof KbFontBoundsError) {
			result = KB_LOAD_FONT_ERROR_OUT_OF_BOUNDS;
		} else {
			throw e;
		}
	}
	if (result != KB_LOAD_FONT_ERROR_NONE) {
		font.hasBlob = false;
	}
	font.error = result;
	return result;
}

export function kbFontFromMemory(data: Readonly<Span<uint8>>, fontIndex: int32): KbFont {
	const font = new KbFont();
	if (data.length > 0) {
		const state = kbNewLoadFontState();
		const error = kbLoadFont(font, state, data, fontIndex);

		if (error == KB_LOAD_FONT_ERROR_NEED_TO_CREATE_BLOB) {
			kbPlaceBlob(font, state, data);
		} else if (error == KB_LOAD_FONT_ERROR_OUT_OF_BOUNDS) {
			font.error = error;
		}
	}
	return font;
}

export function kbFontIsValid(font: KbFont): boolean {
	return font.error == 0;
}

export function kbFreeFont(font: KbFont): void {
	font.blob = [];
	font.hasBlob = false;
}

export function kbCodepointToGlyphId(font: KbFont, iCodepoint: int32): int32 {
	let result: int32 = 0;
	let codepoint: int64 = (iCodepoint as int64) & 0xFFFFFFFF;

	const cmapBase = font.cmap;
	if (cmapBase != 0) {
		const m: Span<uint8> = font.blob[0..font.blob.length];
		const cmapFormat = m.kbU16(cmapBase);
		match (cmapFormat) {
			0 => {
				if (codepoint < 256) {
					result = m.kbU8(cmapBase + 6 + codepoint);
				}
			},
			2 => {
				const subHeaders = cmapBase + KB_SIZE_CMAP_2;

				let high = (codepoint >> 8) & 0xFF;

				if ((codepoint & 0xFF00) == 0) {
					high = codepoint & 0xFF;
				}

				const subHeaderIndex = u16At(m, cmapBase + 6 + high * 2) / 8;
				const subHeader = subHeaders + subHeaderIndex * 8;

				if (subHeaderIndex == 0) {
					codepoint = high;
				} else {
					codepoint = codepoint & 0xFF;
				}

				const offset = (codepoint - u16At(m, subHeader)) & 0xFFFFFFFF;
				if (offset < u16At(m, subHeader + 2)) {
					const glyphIds = subHeader + 6 + u16At(m, subHeader + 6);
					let glyphId = u16At(m, glyphIds + offset * 2);

					if (glyphId != 0) {
						glyphId += m.kbS16(subHeader + 4) as int64;
					}

					result = (glyphId & 0xFFFF) as int32;
				}
			},
			4 => {
				let segmentCount = u16At(m, cmapBase + 6) / 2;
				const endCodes = cmapBase + 14;
				const startCodes = endCodes + (segmentCount + 1) * 2;
				const idDeltas = startCodes + segmentCount * 2;
				const idRangeOffsets = idDeltas + segmentCount * 2;
				let segmentIndexOffset: int64 = 0;

				if (segmentCount != 0) {
					while (segmentCount > 1) {
						const halfCount = segmentCount / 2;
						segmentIndexOffset = u16At(m, endCodes + (segmentIndexOffset + halfCount - 1) * 2) < codepoint ?
							segmentIndexOffset + halfCount : segmentIndexOffset;
						segmentCount -= halfCount;
					}
				}

				const start = u16At(m, startCodes + segmentIndexOffset * 2);
				if (codepoint >= start && codepoint <= u16At(m, endCodes + segmentIndexOffset * 2)) {
					const delta = m.kbS16(idDeltas + segmentIndexOffset * 2) as int64;
					const rangeOffset = u16At(m, idRangeOffsets + segmentIndexOffset * 2);

					let glyphId = delta & 0xFFFF;
					if (rangeOffset != 0) {
						glyphId = (glyphId + u16At(m, idRangeOffsets + segmentIndexOffset * 2 +
							(codepoint - start) * 2 + (rangeOffset / 2) * 2)) & 0xFFFF;
					} else {
						glyphId = (glyphId + (codepoint & 0xFFFF)) & 0xFFFF;
					}
					result = glyphId as int32;
				}
			},
			6 => {
				const glyphIds = cmapBase + 10;

				const offset = (codepoint - u16At(m, cmapBase + 6)) & 0xFFFFFFFF;
				if (offset < u16At(m, cmapBase + 8)) {
					result = m.kbU16(glyphIds + offset * 2);
				}
			},
			12 => {
				let groups = cmapBase + KB_SIZE_CMAP_12_13;

				let glyphId: int64 = 0;
				let groupCount = m.kbU32(cmapBase + 12);
				if (groupCount != 0) {
					while (groupCount > 1) {
						const halfCount = groupCount / 2;
						groups = m.kbU32(groups + (halfCount - 1) * 12 + 4) < codepoint ? groups + halfCount * 12 : groups;
						groupCount -= halfCount;
					}
				}

				if (codepoint >= m.kbU32(groups) && codepoint <= m.kbU32(groups + 4)) {
					const offset = codepoint - m.kbU32(groups);
					glyphId = m.kbU32(groups + 8) + offset;
				}

				result = kbWrap32(glyphId) as int32;
			},
			_ => {},
		}
	}

	return result;
}
