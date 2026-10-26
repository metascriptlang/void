import { sfntSourceSize, sfntSourceRead } from "./sfntSource";

const MAX_TABLES: int64 = 512;
const MAX_CMAP: int64 = 0x4000000;

const TAG_TTCF: int64 = 0x74746366;
const TAG_OTTO: int64 = 0x4F54544F;
const TAG_TRUE: int64 = 0x74727565;
const TAG_CMAP: int64 = 0x636D6170;
const TAG_HEAD: int64 = 0x68656164;
const TAG_HHEA: int64 = 0x68686561;
const TAG_HMTX: int64 = 0x686D7478;
const TAG_GLYF: int64 = 0x676C7966;
const TAG_LOCA: int64 = 0x6C6F6361;
const TAG_CFF: int64 = 0x43464620;
const TAG_MAXP: int64 = 0x6D617870;
const TAG_HVGL: int64 = 0x6876676C;
const TAG_CFF2: int64 = 0x43464632;
const TAG_CBDT: int64 = 0x43424454;
const TAG_CBLC: int64 = 0x43424C43;
const TAG_SBIX: int64 = 0x73626978;
const TAG_COLR: int64 = 0x434F4C52;
const TAG_CPAL: int64 = 0x4350414C;

const FLAG_DRAWABLE: int32 = 1;
const FLAG_COLOUR_BITMAP: int32 = 2;
const FLAG_COLOUR_LAYERS: int32 = 4;
const FLAG_OS_OUTLINES: int32 = 8;

export enum SfntError {
	Unreadable,
	NotAnSfnt,
	OutOfMemory,
}

export enum SfntSequence {
	None,
	Default,
	Specific,
}

struct Summary {
	cmap: uint8[];
	length: int64;
	index: int64;
	sequences: int64;
	flags: int32;
}

let summaries: Summary[] = [];

function fits(this s: Summary, at: int64, n: int64): boolean {
	return at <= s.length && n <= s.length - at;
}

function u8(this s: Summary, at: int64): int64 {
	return s.fits(at, 1) ? (s.cmap[at] as int64) : 0;
}

function u16(this s: Summary, at: int64): int64 {
	if (!s.fits(at, 2)) { return 0; }
	return ((s.cmap[at] as int64) << 8) | (s.cmap[at + 1] as int64);
}

function i16(this s: Summary, at: int64): int64 {
	const v = s.u16(at);
	return v >= 0x8000 ? v - 0x10000 : v;
}

function u24(this s: Summary, at: int64): int64 {
	if (!s.fits(at, 3)) { return 0; }
	return ((s.cmap[at] as int64) << 16) | ((s.cmap[at + 1] as int64) << 8) |
		(s.cmap[at + 2] as int64);
}

function u32(this s: Summary, at: int64): int64 {
	if (!s.fits(at, 4)) { return 0; }
	return ((s.cmap[at] as int64) << 24) | ((s.cmap[at + 1] as int64) << 16) |
		((s.cmap[at + 2] as int64) << 8) | (s.cmap[at + 3] as int64);
}

function fileU32(p: uint8[], at: int32): int64 {
	return ((p[at] as int64) << 24) | ((p[at + 1] as int64) << 16) |
		((p[at + 2] as int64) << 8) | (p[at + 3] as int64);
}

function validSummary(summary: int32): boolean {
	return summary >= 0 && summary < (summaries.length as int32);
}

function glyphInFormat4(s: Summary, map: int64, codepoint: int64): int64 {
	const segcount = s.u16(map + 6) >> 1;
	let searchRange = s.u16(map + 8) >> 1;
	let entrySelector = s.u16(map + 10);
	const rangeShift = s.u16(map + 12) >> 1;
	const endCount = map + 14;
	let search = endCount;
	if (!s.fits(map, 16 + segcount * 8)) { return 0; }
	if (codepoint >= s.u16(search + rangeShift * 2)) {
		search += rangeShift * 2;
	}
	search -= 2;
	while (entrySelector != 0) {
		searchRange >>= 1;
		if (codepoint > s.u16(search + searchRange * 2)) {
			search += searchRange * 2;
		}
		entrySelector -= 1;
	}
	search += 2;
	const item = ((search - endCount) >> 1) & 0xffff;
	if (item >= segcount) { return 0; }
	const start = s.u16(map + 14 + segcount * 2 + 2 + 2 * item);
	const last = s.u16(endCount + 2 * item);
	if (codepoint < start || codepoint > last) { return 0; }
	const offset = s.u16(map + 14 + segcount * 6 + 2 + 2 * item);
	if (offset == 0) {
		const delta = s.i16(map + 14 + segcount * 4 + 2 + 2 * item);
		return (codepoint + delta) & 0xffff;
	}
	return s.u16(offset + (codepoint - start) * 2 + map + 14 + segcount * 6 + 2 + 2 * item);
}

function glyphInGroups(s: Summary, map: int64, codepoint: int64, sharedGlyph: boolean): int64 {
	let low: int64 = 0;
	let high = s.u32(map + 12);
	if (!s.fits(map, 16 + high * 12)) { return 0; }
	while (low < high) {
		const mid = low + ((high - low) >> 1);
		const startChar = s.u32(map + 16 + mid * 12);
		const endChar = s.u32(map + 16 + mid * 12 + 4);
		if (codepoint < startChar) {
			high = mid;
		} else if (codepoint > endChar) {
			low = mid + 1;
		} else {
			const startGlyph = s.u32(map + 16 + mid * 12 + 8);
			if (sharedGlyph) { return startGlyph; }
			return (startGlyph + (codepoint - startChar)) & 0xffffffff;
		}
	}
	return 0;
}

function stbCompatibleGlyph(s: Summary, codepoint: int64): int64 {
	const map = s.index;
	if (map == 0 || codepoint < 0) { return 0; }
	const format = s.u16(map);
	if (format == 0) {
		const bytes = s.u16(map + 2);
		if (codepoint < bytes - 6) { return s.u8(map + 6 + codepoint); }
		return 0;
	}
	if (format == 6) {
		const first = s.u16(map + 6);
		const count = s.u16(map + 8);
		if (!s.fits(map, 10 + count * 2)) { return 0; }
		if (codepoint >= first && codepoint < first + count) {
			return s.u16(map + 10 + (codepoint - first) * 2);
		}
		return 0;
	}
	if (format == 4) { return glyphInFormat4(s, map, codepoint); }
	if (format == 12) { return glyphInGroups(s, map, codepoint, false); }
	if (format == 13) { return glyphInGroups(s, map, codepoint, true); }
	return 0;
}

function chooseIndex(s: Summary): int64 {
	let chosen: int64 = 0;
	const records = s.u16(2);
	for (let i: int64 = 0; i < records; i++) {
		const record = 4 + 8 * i;
		if (!s.fits(record, 8)) { break; }
		const platform = s.u16(record);
		const encoding = s.u16(record + 2);
		const offset = s.u32(record + 4);
		if (platform == 3 && (encoding == 1 || encoding == 10)) { chosen = offset; }
		if (platform == 0) { chosen = offset; }
	}
	return s.fits(chosen, 2) ? chosen : 0;
}

function chooseSequences(s: Summary): int64 {
	const records = s.u16(2);
	for (let i: int64 = 0; i < records; i++) {
		const record = 4 + 8 * i;
		if (!s.fits(record, 8)) { break; }
		if (s.u16(record) == 0 && s.u16(record + 2) == 5) {
			const offset = s.u32(record + 4);
			if (s.fits(offset, 10) && s.u16(offset) == 14) { return offset; }
		}
	}
	return 0;
}

function sequenceInDefault(s: Summary, table: int64, codepoint: int64): boolean {
	let low: int64 = 0;
	let high = s.u32(table);
	if (!s.fits(table, 4 + high * 4)) { return false; }
	while (low < high) {
		const mid = low + ((high - low) >> 1);
		const start = s.u24(table + 4 + mid * 4);
		const last = start + s.u8(table + 4 + mid * 4 + 3);
		if (codepoint < start) {
			high = mid;
		} else if (codepoint > last) {
			low = mid + 1;
		} else {
			return true;
		}
	}
	return false;
}

function sequenceInSpecific(s: Summary, table: int64, codepoint: int64): boolean {
	let low: int64 = 0;
	let high = s.u32(table);
	if (!s.fits(table, 4 + high * 5)) { return false; }
	while (low < high) {
		const mid = low + ((high - low) >> 1);
		const value = s.u24(table + 4 + mid * 5);
		if (codepoint < value) {
			high = mid;
		} else if (codepoint > value) {
			low = mid + 1;
		} else {
			return s.u16(table + 4 + mid * 5 + 3) != 0;
		}
	}
	return false;
}

// Where a peek reads from: the bytes of a held face given directly, or the path through the
// source seam (held bytes by name, else the file).
struct Source {
	path: string;
	bytes: uint8[];
	direct: boolean;
	size: int64;
}

function read(this src: Source, at: int64, into: Span<uint8>): boolean {
	if (src.direct) {
		const length = into.length as int64;
		if (at > src.size || length > src.size - at) { return false; }
		for (let i: int64 = 0; i < length; i++) { into[i] = src.bytes[at + i]; }
		return true;
	}
	return sfntSourceRead(src.path, at, into);
}

function readRange(this src: Source, at: int64, length: int64): uint8[] | null {
	let buf: uint8[] = new Array<uint8>(length as int32);
	if (!src.read(at, buf)) { return null; }
	return buf;
}

struct TableSpan {
	offset: int64;
	length: int64;
	found: boolean;
}

function findTable(directory: uint8[], tables: int32, fileSize: int64, tag: int64): TableSpan {
	for (let i: int32 = 0; i < tables; i++) {
		const record: int32 = 16 * i;
		if (fileU32(directory, record) != tag) { continue; }
		const offset = fileU32(directory, record + 8);
		const length = fileU32(directory, record + 12);
		if (offset > fileSize || length > fileSize - offset) { continue; }
		return { offset: offset, length: length, found: true };
	}
	return { offset: 0, length: 0, found: false };
}

function has(directory: uint8[], tables: int32, fileSize: int64, tag: int64): boolean {
	return findTable(directory, tables, fileSize, tag).found;
}

function peekSource(src: Source, index: int32): Result<int32, SfntError> {
	const fileSize = src.size;
	let fontStart: int64 = 0;
	if (fileSize < 12) { return Result.err(SfntError.NotAnSfnt); }
	let head = src.readRange(0, 12);
	if (head == null) { return Result.err(SfntError.NotAnSfnt); }
	if (fileU32(head, 0) == TAG_TTCF) {
		if (index < 0 || (index as int64) >= fileU32(head, 8)) {
			return Result.err(SfntError.NotAnSfnt);
		}
		const offset = src.readRange(12 + 4 * (index as int64), 4);
		if (offset == null) { return Result.err(SfntError.NotAnSfnt); }
		fontStart = fileU32(offset, 0);
		if (fontStart > fileSize || 12 > fileSize - fontStart) {
			return Result.err(SfntError.NotAnSfnt);
		}
		head = src.readRange(fontStart, 12);
		if (head == null) { return Result.err(SfntError.NotAnSfnt); }
	} else if (index != 0) {
		return Result.err(SfntError.NotAnSfnt);
	}
	const version = fileU32(head, 0);
	if (!(version == 0x00010000 || version == TAG_OTTO || version == TAG_TRUE)) {
		return Result.err(SfntError.NotAnSfnt);
	}
	const tables: int32 = ((head[4] as int32) << 8) | (head[5] as int32);
	if (tables == 0 || (tables as int64) > MAX_TABLES) { return Result.err(SfntError.NotAnSfnt); }
	if (fontStart + 12 > fileSize || 16 * (tables as int64) > fileSize - fontStart - 12) {
		return Result.err(SfntError.NotAnSfnt);
	}
	const directory = src.readRange(fontStart + 12, 16 * (tables as int64));
	if (directory == null) { return Result.err(SfntError.NotAnSfnt); }
	const cmapSpan = findTable(directory, tables, fileSize, TAG_CMAP);
	const headFound = has(directory, tables, fileSize, TAG_HEAD);
	const hheaFound = has(directory, tables, fileSize, TAG_HHEA);
	const hmtxFound = has(directory, tables, fileSize, TAG_HMTX);
	const glyfFound = has(directory, tables, fileSize, TAG_GLYF);
	const locaFound = has(directory, tables, fileSize, TAG_LOCA);
	const cffFound = has(directory, tables, fileSize, TAG_CFF);
	if (!cmapSpan.found || cmapSpan.length > MAX_CMAP) { return Result.err(SfntError.NotAnSfnt); }
	const cmap = src.readRange(cmapSpan.offset, cmapSpan.length);
	if (cmap == null) { return Result.err(SfntError.NotAnSfnt); }
	let summary: Summary = {
		cmap: cmap, length: cmapSpan.length, index: 0, sequences: 0, flags: 0,
	};
	summary.index = chooseIndex(summary);
	summary.sequences = chooseSequences(summary);
	if (summary.index != 0 && headFound && hheaFound && hmtxFound &&
		(glyfFound ? locaFound : cffFound)) {
		summary.flags |= FLAG_DRAWABLE;
	}
	if (summary.index != 0 && headFound && hheaFound && hmtxFound &&
		has(directory, tables, fileSize, TAG_MAXP) &&
		(has(directory, tables, fileSize, TAG_HVGL) || has(directory, tables, fileSize, TAG_CFF2))) {
		summary.flags |= FLAG_OS_OUTLINES;
	}
	if ((has(directory, tables, fileSize, TAG_CBDT) && has(directory, tables, fileSize, TAG_CBLC)) ||
		has(directory, tables, fileSize, TAG_SBIX)) {
		summary.flags |= FLAG_COLOUR_BITMAP;
	}
	if (has(directory, tables, fileSize, TAG_COLR) && has(directory, tables, fileSize, TAG_CPAL)) {
		summary.flags |= FLAG_COLOUR_LAYERS;
	}
	summaries.push(summary);
	return Result.ok((summaries.length as int32) - 1);
}

// Reads the font at `path` (held bytes of that name, else the file) and returns its summary id.
export function sfntPeek(path: string, index: int32): Result<int32, SfntError> {
	const size = sfntSourceSize(path);
	if (size < 0) { return Result.err(SfntError.Unreadable); }
	return peekSource({ path: path, bytes: [], direct: false, size: size }, index);
}

export function sfntPeekBytes(bytes: uint8[], index: int32): Result<int32, SfntError> {
	return peekSource(
		{ path: "", bytes: bytes, direct: true, size: bytes.length as int64 }, index,
	);
}

export function sfntCovers(summary: int32, codepoint: int32): boolean {
	if (!validSummary(summary)) { return false; }
	return stbCompatibleGlyph(summaries[summary], codepoint as int64) != 0;
}

export function sfntSequence(summary: int32, codepoint: int32, selector: int32): SfntSequence {
	if (!validSummary(summary) || codepoint < 0 || selector < 0) { return SfntSequence.None; }
	const s = summaries[summary];
	const table = s.sequences;
	if (table == 0) { return SfntSequence.None; }
	let low: int64 = 0;
	let high = s.u32(table + 6);
	if (!s.fits(table, 10 + high * 11)) { return SfntSequence.None; }
	while (low < high) {
		const mid = low + ((high - low) >> 1);
		const record = table + 10 + mid * 11;
		const found = s.u24(record);
		if ((selector as int64) < found) {
			high = mid;
		} else if ((selector as int64) > found) {
			low = mid + 1;
		} else {
			const defaults = s.u32(record + 3);
			const specifics = s.u32(record + 7);
			if (specifics != 0 && sequenceInSpecific(s, table + specifics, codepoint as int64)) {
				return SfntSequence.Specific;
			}
			if (defaults != 0 && sequenceInDefault(s, table + defaults, codepoint as int64)) {
				return SfntSequence.Default;
			}
			return SfntSequence.None;
		}
	}
	return SfntSequence.None;
}

export function sfntFlags(summary: int32): int32 {
	return validSummary(summary) ? summaries[summary].flags : 0;
}

export function sfntSummariesRead(): int32 {
	return summaries.length as int32;
}
