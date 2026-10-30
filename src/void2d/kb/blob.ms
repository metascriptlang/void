export class KbFontBoundsError extends Error {
	constructor(message: string) { super(message); }
}

export const KB_LOAD_FONT_ERROR_NONE: int32 = 0;
export const KB_LOAD_FONT_ERROR_NEED_TO_CREATE_BLOB: int32 = 1;
export const KB_LOAD_FONT_ERROR_INVALID_FONT: int32 = 2;
export const KB_LOAD_FONT_ERROR_OUT_OF_MEMORY: int32 = 3;
export const KB_LOAD_FONT_ERROR_COULD_NOT_OPEN_FILE: int32 = 4;
export const KB_LOAD_FONT_ERROR_READ_ERROR: int32 = 5;
export const KB_LOAD_FONT_ERROR_OUT_OF_BOUNDS: int32 = 6;

export const KB_BLOB_VERSION_CURRENT: int64 = 2;

export const KB_BLOB_TABLE_ID_NONE: int32 = 0;
export const KB_BLOB_TABLE_ID_HEAD: int32 = 1;
export const KB_BLOB_TABLE_ID_CMAP: int32 = 2;
export const KB_BLOB_TABLE_ID_GDEF: int32 = 3;
export const KB_BLOB_TABLE_ID_GSUB: int32 = 4;
export const KB_BLOB_TABLE_ID_GPOS: int32 = 5;
export const KB_BLOB_TABLE_ID_HHEA: int32 = 6;
export const KB_BLOB_TABLE_ID_VHEA: int32 = 7;
export const KB_BLOB_TABLE_ID_HMTX: int32 = 8;
export const KB_BLOB_TABLE_ID_VMTX: int32 = 9;
export const KB_BLOB_TABLE_ID_MAXP: int32 = 10;
export const KB_BLOB_TABLE_ID_OS2: int32 = 11;
export const KB_BLOB_TABLE_ID_NAME: int32 = 12;
export const KB_BLOB_TABLE_ID_FVAR: int32 = 13;
export const KB_BLOB_TABLE_ID_AVAR: int32 = 14;
export const KB_BLOB_TABLE_ID_MVAR: int32 = 15;
export const KB_BLOB_TABLE_ID_HVAR: int32 = 16;
export const KB_BLOB_TABLE_ID_VVAR: int32 = 17;
export const KB_BLOB_TABLE_ID_COUNT: int32 = 18;

export const KB_BLOB_HEADER_MAGIC: int64 = 0;
export const KB_BLOB_HEADER_VERSION: int64 = 4;
export const KB_BLOB_HEADER_LOOKUP_COUNT: int64 = 8;
export const KB_BLOB_HEADER_LOOKUP_SUBTABLE_COUNT: int64 = 12;
export const KB_BLOB_HEADER_GLYPH_COUNT: int64 = 16;
export const KB_BLOB_HEADER_GPOS_LOOKUP_INDEX_OFFSET: int64 = 20;
export const KB_BLOB_HEADER_GLYPH_LOOKUP_MATRIX_OFFSET: int64 = 24;
export const KB_BLOB_HEADER_GLYPH_LOOKUP_SUBTABLE_MATRIX_OFFSET: int64 = 28;
export const KB_BLOB_HEADER_LOOKUP_SUBTABLE_INDEX_OFFSETS_OFFSET: int64 = 32;
export const KB_BLOB_HEADER_SUBTABLE_INFOS_OFFSET: int64 = 36;
export const KB_BLOB_HEADER_TABLES: int64 = 40;
export const KB_BLOB_HEADER_SIZE: int64 = 184;

export const KB_FOURCC_KBTS: int64 = 0x7374626B;
export const KB_FOURCC_TTCF: int64 = 0x66637474;
export const KB_FOURCC_OTTO: int64 = 0x4F54544F;
export const KB_FOURCC_V1: int64 = 0x00000100;

export const KB_SIZE_SCRIPT_LIST: int64 = 2;
export const KB_SIZE_SCRIPT_RECORD: int64 = 6;
export const KB_SIZE_OT_SCRIPT: int64 = 4;
export const KB_SIZE_LANGSYS_RECORD: int64 = 6;
export const KB_SIZE_LANGSYS: int64 = 6;
export const KB_SIZE_FEATURE_LIST: int64 = 2;
export const KB_SIZE_FEATURE_RECORD: int64 = 6;
export const KB_SIZE_FEATURE: int64 = 4;
export const KB_SIZE_LOOKUP_LIST: int64 = 2;
export const KB_SIZE_LOOKUP: int64 = 6;
export const KB_SIZE_COVERAGE: int64 = 4;
export const KB_SIZE_RANGE_RECORD: int64 = 6;
export const KB_SIZE_CLASS_DEFINITION_1: int64 = 6;
export const KB_SIZE_CLASS_DEFINITION_2: int64 = 4;
export const KB_SIZE_CLASS_RANGE_RECORD: int64 = 6;
export const KB_SIZE_SEQUENCE_LOOKUP_RECORD: int64 = 4;
export const KB_SIZE_SEQUENCE_RULE: int64 = 4;
export const KB_SIZE_SEQUENCE_RULE_SET: int64 = 2;
export const KB_SIZE_SEQUENCE_CONTEXT_1: int64 = 6;
export const KB_SIZE_SEQUENCE_CONTEXT_2: int64 = 8;
export const KB_SIZE_SEQUENCE_CONTEXT_3: int64 = 6;
export const KB_SIZE_CLASS_SEQUENCE_RULE_SET: int64 = 2;
export const KB_SIZE_CLASS_SEQUENCE_RULE: int64 = 4;
export const KB_SIZE_CHAINED_SEQUENCE_CONTEXT_1: int64 = 6;
export const KB_SIZE_CHAINED_SEQUENCE_RULE_SET: int64 = 2;
export const KB_SIZE_CHAINED_SEQUENCE_RULE: int64 = 2;
export const KB_SIZE_CHAINED_SEQUENCE_CONTEXT_2: int64 = 12;
export const KB_SIZE_CHAINED_SEQUENCE_CONTEXT_3: int64 = 4;
export const KB_SIZE_DEVICE: int64 = 6;
export const KB_SIZE_FEATURE_VARIATIONS: int64 = 8;
export const KB_SIZE_FEATURE_VARIATION_RECORD: int64 = 8;
export const KB_SIZE_CONDITION_SET: int64 = 2;
export const KB_SIZE_FEATURE_TABLE_SUBSTITUTION: int64 = 6;
export const KB_SIZE_FEATURE_TABLE_SUBSTITUTION_RECORD: int64 = 6;
export const KB_SIZE_SINGLE_SUBSTITUTION: int64 = 6;
export const KB_SIZE_MULTIPLE_SUBSTITUTION: int64 = 6;
export const KB_SIZE_SEQUENCE: int64 = 2;
export const KB_SIZE_ALTERNATE_SUBSTITUTION: int64 = 6;
export const KB_SIZE_ALTERNATE_SET: int64 = 2;
export const KB_SIZE_LIGATURE_SUBSTITUTION: int64 = 6;
export const KB_SIZE_LIGATURE_SET: int64 = 2;
export const KB_SIZE_LIGATURE: int64 = 4;
export const KB_SIZE_EXTENSION: int64 = 8;
export const KB_SIZE_REVERSE_CHAIN_SUBSTITUTION: int64 = 6;
export const KB_SIZE_MARK_GLYPH_SETS: int64 = 4;
export const KB_SIZE_ANCHOR: int64 = 10;
export const KB_SIZE_MARK_RECORD: int64 = 4;
export const KB_SIZE_MARK_ARRAY: int64 = 2;
export const KB_SIZE_SINGLE_ADJUSTMENT_1: int64 = 6;
export const KB_SIZE_SINGLE_ADJUSTMENT_2: int64 = 8;
export const KB_SIZE_PAIR_VALUE_RECORD: int64 = 2;
export const KB_SIZE_PAIR_SET: int64 = 2;
export const KB_SIZE_PAIR_ADJUSTMENT_1: int64 = 10;
export const KB_SIZE_PAIR_ADJUSTMENT_2: int64 = 16;
export const KB_SIZE_ENTRY_EXIT: int64 = 4;
export const KB_SIZE_CURSIVE_ATTACHMENT: int64 = 6;
export const KB_SIZE_BASE_ARRAY: int64 = 2;
export const KB_SIZE_MARK_TO_BASE_ATTACHMENT: int64 = 12;
export const KB_SIZE_LIGATURE_ATTACH: int64 = 2;
export const KB_SIZE_LIGATURE_ARRAY: int64 = 2;
export const KB_SIZE_MARK_TO_LIGATURE_ATTACHMENT: int64 = 12;
export const KB_SIZE_CMAP: int64 = 4;
export const KB_SIZE_ENCODING_RECORD: int64 = 8;
export const KB_SIZE_CMAP_0: int64 = 262;
export const KB_SIZE_CMAP_2: int64 = 518;
export const KB_SIZE_SUB_HEADER: int64 = 8;
export const KB_SIZE_CMAP_4: int64 = 14;
export const KB_SIZE_CMAP_6: int64 = 10;
export const KB_SIZE_CMAP_12_13: int64 = 16;
export const KB_SIZE_CMAP_14: int64 = 10;
export const KB_SIZE_SEQUENTIAL_MAP_GROUP: int64 = 12;
export const KB_SIZE_GDEF: int64 = 18;
export const KB_SIZE_HEAD: int64 = 54;
export const KB_SIZE_HEA: int64 = 36;
export const KB_SIZE_NAME: int64 = 6;
export const KB_SIZE_NAME_RECORD: int64 = 12;
export const KB_SIZE_FVAR: int64 = 16;
export const KB_SIZE_VARIATION_AXIS_RECORD: int64 = 20;
export const KB_SIZE_INSTANCE_RECORD: int64 = 4;
export const KB_SIZE_FIXED16_16: int64 = 4;
export const KB_SIZE_AVAR: int64 = 8;
export const KB_SIZE_SEGMENT_MAPS: int64 = 2;
export const KB_SIZE_AXIS_VALUE_MAP: int64 = 4;
export const KB_SIZE_HVAR_VVAR_COMMON: int64 = 20;
export const KB_SIZE_VVAR: int64 = 24;
export const KB_SIZE_MVAR: int64 = 12;
export const KB_SIZE_MVAR_VALUE_RECORD: int64 = 8;
export const KB_SIZE_DELTA_SET_INDEX_MAP: int64 = 2;
export const KB_SIZE_VARIATION_REGION_LIST: int64 = 4;
export const KB_SIZE_REGION_AXIS_COORDINATES: int64 = 6;
export const KB_SIZE_ITEM_VARIATION_DATA: int64 = 6;

export const KB_LOOKUP_FLAG_USE_MARK_FILTERING_SET: int32 = 1 << 4;

export const KB_VALUE_FORMAT_X_PLACEMENT: int32 = 1 << 0;
export const KB_VALUE_FORMAT_Y_PLACEMENT: int32 = 1 << 1;
export const KB_VALUE_FORMAT_X_ADVANCE: int32 = 1 << 2;
export const KB_VALUE_FORMAT_Y_ADVANCE: int32 = 1 << 3;
export const KB_VALUE_FORMAT_X_PLACEMENT_DEVICE: int32 = 1 << 4;
export const KB_VALUE_FORMAT_Y_PLACEMENT_DEVICE: int32 = 1 << 5;
export const KB_VALUE_FORMAT_X_ADVANCE_DEVICE: int32 = 1 << 6;
export const KB_VALUE_FORMAT_Y_ADVANCE_DEVICE: int32 = 1 << 7;

export function kbBoundsFail(what: string, at: int64): KbFontBoundsError {
	return new KbFontBoundsError(`${what} at ${at}`);
}

export function kbU8(this m: Readonly<Span<uint8>>, at: int64): int32 {
	if (at < 0 || at >= (m.length as int64)) { throw kbBoundsFail("u8 read", at); }
	return m[at] as int32;
}

export function kbU16(this m: Readonly<Span<uint8>>, at: int64): int32 {
	if (at < 0 || at + 2 > (m.length as int64)) { throw kbBoundsFail("u16 read", at); }
	return (m[at] as int32) | ((m[at + 1] as int32) << 8);
}

export function kbS16(this m: Readonly<Span<uint8>>, at: int64): int32 {
	const value = m.kbU16(at);
	return value >= 0x8000 ? value - 0x10000 : value;
}

export function kbU32(this m: Readonly<Span<uint8>>, at: int64): int64 {
	if (at < 0 || at + 4 > (m.length as int64)) { throw kbBoundsFail("u32 read", at); }
	return (m[at] as int64) | ((m[at + 1] as int64) << 8) | ((m[at + 2] as int64) << 16) |
		((m[at + 3] as int64) << 24);
}

export function kbSetU8(this m: Span<uint8>, at: int64, value: int32): void {
	if (at < 0 || at >= (m.length as int64)) { throw kbBoundsFail("u8 write", at); }
	m[at] = (value & 0xFF) as uint8;
}

export function kbSetU16(this m: Span<uint8>, at: int64, value: int32): void {
	if (at < 0 || at + 2 > (m.length as int64)) { throw kbBoundsFail("u16 write", at); }
	m[at] = (value & 0xFF) as uint8;
	m[at + 1] = ((value >> 8) & 0xFF) as uint8;
}

export function kbSetU32(this m: Span<uint8>, at: int64, value: int64): void {
	if (at < 0 || at + 4 > (m.length as int64)) { throw kbBoundsFail("u32 write", at); }
	m[at] = (value & 0xFF) as uint8;
	m[at + 1] = ((value >> 8) & 0xFF) as uint8;
	m[at + 2] = ((value >> 16) & 0xFF) as uint8;
	m[at + 3] = ((value >> 24) & 0xFF) as uint8;
}

export function kbFileU8(this f: Readonly<Span<uint8>>, at: int64): int32 {
	return f.kbU8(at);
}

export function kbFileU16(this f: Readonly<Span<uint8>>, at: int64): int32 {
	return kbSwap16(f.kbU16(at));
}

export function kbFileU32(this f: Readonly<Span<uint8>>, at: int64): int64 {
	return kbSwap32(f.kbU32(at));
}

export function kbSwap16(value: int32): int32 {
	return ((value & 0xFF) << 8) | ((value >> 8) & 0xFF);
}

export function kbSwap32(value: int64): int64 {
	return ((value & 0xFF) << 24) | ((value & 0xFF00) << 8) | ((value >> 8) & 0xFF00) |
		((value >> 24) & 0xFF);
}

export function kbWrap32(value: int64): int64 {
	return ((value & 0xFFFFFFFF) ^ 0x80000000) - 0x80000000;
}

export function kbUn(value: int64): int64 {
	if (value < 0) { throw kbBoundsFail("negative count read as a huge unsigned", value); }
	return value;
}

export function kbPopCount32(value: int32): int64 {
	let rest = value & 0xFFFF;
	let count: int64 = 0;
	while (rest != 0) {
		count += (rest & 1) as int64;
		rest >>= 1;
	}
	return count;
}

export function kbAlign(at: int64, align: int64): int64 {
	return (at + align - 1) & ~(align - 1);
}

export function kbSwapU16At(this m: Span<uint8>, at: int64): void {
	m.kbSetU16(at, kbSwap16(m.kbU16(at)));
}

export function kbSwapU32At(this m: Span<uint8>, at: int64): void {
	m.kbSetU32(at, kbSwap32(m.kbU32(at)));
}

export function kbSwapArray16Unchecked(this m: Span<uint8>, at: int64, count: int64): void {
	for (let i: int64 = 0; i < count; i++) {
		const p = at + i * 2;
		const low = m.kbU8(p);
		const high = m.kbU8(p + 1);
		m.kbSetU8(p, high);
		m.kbSetU8(p + 1, low);
	}
}

export function kbSwapArray32Unchecked(this m: Span<uint8>, at: int64, count: int64): void {
	for (let i: int64 = 0; i < count; i++) {
		const p = at + i * 4;
		const b0 = m.kbU8(p);
		const b1 = m.kbU8(p + 1);
		const b2 = m.kbU8(p + 2);
		const b3 = m.kbU8(p + 3);
		m.kbSetU8(p, b3);
		m.kbSetU8(p + 1, b2);
		m.kbSetU8(p + 2, b1);
		m.kbSetU8(p + 3, b0);
	}
}

export function kbSwapArray16(this m: Span<uint8>, at: int64, count: int64, end: int64): boolean {
	if (at + count * 2 > end) { return false; }
	m.kbSwapArray16Unchecked(at, count);
	return true;
}

export function kbSwapArray32(this m: Span<uint8>, at: int64, count: int64, end: int64): boolean {
	if (at + count * 4 > end) { return false; }
	m.kbSwapArray32Unchecked(at, count);
	return true;
}

export function kbBlobTableOffset(this m: Readonly<Span<uint8>>, tableId: int32): int64 {
	return m.kbU32(KB_BLOB_HEADER_TABLES + (tableId as int64) * 8);
}

export function kbBlobTableLength(this m: Readonly<Span<uint8>>, tableId: int32): int64 {
	return m.kbU32(KB_BLOB_HEADER_TABLES + (tableId as int64) * 8 + 4);
}

export function kbBlobTableData(this m: Readonly<Span<uint8>>, tableId: int32): int64 {
	return m.kbBlobTableLength(tableId) != 0 ? m.kbBlobTableOffset(tableId) : 0;
}

export struct KbMatrixIndex {
	word: int64;
	bit: int64;
}

export function kbGlyphLookupMatrixIndex(
	rowIndex: int64,
	glyphIndex: int64,
	glyphCount: int64,
): KbMatrixIndex {
	const flat = rowIndex * glyphCount + glyphIndex;
	return { word: flat / 32, bit: flat % 32 };
}

