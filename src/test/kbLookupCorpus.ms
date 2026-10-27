import { kbGetLookup, kbGetLookupList } from "../void2d/kb/access";
import {
	KB_BLOB_HEADER_GLYPH_COUNT,
	KB_BLOB_TABLE_ID_GPOS,
	KB_BLOB_TABLE_ID_GSUB,
	KbFontBoundsError,
	kbBlobTableData,
	kbU16,
	kbU32,
} from "../void2d/kb/blob";
import { KbFont } from "../void2d/kb/font";
import {
	KbGlyphStorage,
	kbGlyphClasses,
	kbInsertGlyphBefore,
	kbZeroGlyph,
} from "../void2d/kb/glyph";
import { kbGlyphIncludedInLookupSubtable, kbPlaceScratch } from "../void2d/kb/scratch";
import { KbDriveConfig, kbDrive, kbMatrixBit, kbUint32Bits } from "./kbLookupDrive";

export class KbRng {
	state: uint32;
	constructor(seed: uint32) { this.state = seed == 0 ? 0x9E3779B9 : seed; }
	next(): uint32 {
		let x = this.state;
		x ^= x << 13;
		x ^= x >> 17;
		x ^= x << 5;
		this.state = x;
		return x;
	}
	below(n: int32): int32 { return (this.next() % (n as uint32)) as int32; }
}

export function kbLookupMix(a: uint32, b: uint32): uint32 {
	let h: uint32 = (a * 2654435761) ^ (b + 0x9E3779B9 + (a << 6) + (a >> 2));
	h ^= h >> 15;
	h *= 2246822519;
	h ^= h >> 13;
	return h;
}

function kbGlyphCountOf(m: Span<uint8>): int32 {
	return m.kbU32(KB_BLOB_HEADER_GLYPH_COUNT) as int32;
}

function kbSubtableCounts(m: Span<uint8>, gpos: boolean, want: int32): int32[] {
	let counts: int32[] = [];
	const table = m.kbBlobTableData(gpos ? KB_BLOB_TABLE_ID_GPOS : KB_BLOB_TABLE_ID_GSUB);
	const lookupList = kbGetLookupList(m, table);
	const lookupCount: int32 = lookupList == 0 ? 0 : m.kbU16(lookupList);
	const count = want < lookupCount ? want : lookupCount;
	for (let i: int32 = 0; i < count; i++) {
		counts.push(m.kbU16(kbGetLookup(m, lookupList, i as int64) + 4));
	}
	return counts;
}

export function kbLookupConfig(
	font: KbFont,
	gpos: boolean,
	shaper: int32,
	want: int32,
	seed: uint32,
	density: int32,
): KbDriveConfig {
	const config = new KbDriveConfig();
	config.gpos = gpos;
	config.shaper = shaper;

	const counts = kbSubtableCounts(font.blob, gpos, want);
	const count = counts.length as int32;
	if (count <= 0) { return config; }

	for (let i: int32 = 0; i < count; i++) {
		config.lookupIndex.push(i);
		config.skipFlags.push(kbLookupMix(seed, (i as uint32) + 77) & 7);
	}

	const glyphCount = kbGlyphCountOf(font.blob);
	const bitsPerRow: int64 = ((count as int64) + 31) & ~(31 as int64);
	const words = (glyphCount * bitsPerRow / 32) as int32;
	for (let i: int32 = 0; i < words; i++) { config.matrix.push(0); }

	const storage = new KbGlyphStorage();
	const probe = kbInsertGlyphBefore(storage, 0, kbZeroGlyph());
	const scratch = kbPlaceScratch(font, storage, shaper, glyphCount as uint32, [], count);

	for (let i: int32 = 0; i < count; i++) {
		const subtableCount = counts[i];
		for (let g: int32 = 0; g < glyphCount; g++) {
			let bit = false;
			if (density == 0) {
				storage.glyphs[probe].id = g as uint16;
				if (scratch.glyphLookupSubtableMatrix == 0) {
					bit = true;
				} else {
					for (let sub: int32 = 0; sub < subtableCount && !bit; sub++) {
						bit = kbGlyphIncludedInLookupSubtable(scratch, gpos, i as int64, sub as int64, probe);
					}
				}
			} else {
				bit = (kbLookupMix(seed, (i as uint32) * 100003 + (g as uint32)) % 100) < (density as uint32);
			}
			if (bit) {
				const flat = (g as int64) * bitsPerRow + (i as int64);
				const word = (flat / 32) as int32;
				config.matrix[word] = config.matrix[word] | kbMatrixBit(flat);
			}
		}
	}
	return config;
}

export function kbLookupText(rng: KbRng, out: int32[]): void {
	const kind = rng.below(9);
	const length = 1 + rng.below(5);
	for (let i: int32 = 0; i < length; i++) {
		if (kind == 0) {
			const words: int32[] = [0x66, 0x66, 0x69, 0x66, 0x6C, 0x41, 0x56, 0x54, 0x6F, 0x57, 0x61, 0x79, 0x20, 0x31, 0x2F, 0x32];
			out.push(words[rng.below(words.length as int32)]);
		} else if (kind == 1) {
			out.push(0x30 + rng.below(10));
		} else if (kind == 2) {
			out.push(0x61 + rng.below(26));
			const marks = rng.below(3);
			for (let k: int32 = 0; k < marks; k++) { out.push(0x300 + rng.below(0x70)); }
		} else if (kind == 3) {
			const roll = rng.below(10);
			if (roll == 0) {
				out.push(0x644);
				out.push(0x627);
			} else if (roll < 3) {
				out.push(0x64B + rng.below(9));
			} else {
				out.push(0x621 + rng.below(42));
			}
		} else if (kind == 4) {
			const roll = rng.below(8);
			if (roll == 0) {
				out.push(0x94D);
			} else if (roll < 3) {
				out.push(0x93E + rng.below(15));
			} else {
				out.push(0x915 + rng.below(37));
			}
		} else if (kind == 5) {
			out.push(rng.below(3) == 0 ? 0x5B0 + rng.below(14) : 0x5D0 + rng.below(27));
		} else if (kind == 6) {
			out.push(0x4E00 + rng.below(0x5000));
		} else if (kind == 7) {
			const roll = rng.below(6);
			out.push(roll == 0 ? 0x200D : roll == 1 ? 0x1F3FB + rng.below(5) : 0x1F600 + rng.below(80));
		} else {
			const roll = rng.below(8);
			out.push(roll == 0 ? 0x200C : roll == 1 ? 0x200D : roll == 2 ? 0x34F : roll == 3 ? 0xFE0F :
				roll == 4 ? 0xE0E01 : roll == 5 ? 0xE0020 + rng.below(90) : 0x20 + rng.below(0x5F));
		}
	}
}

export class KbCorpus {
	rows: int32[][] = [];
	marks: int32[] = [];
}

export function kbLookupCorpus(font: KbFont, config: KbDriveConfig): KbCorpus {
	const glyphCount = kbGlyphCountOf(font.blob);
	const corpus = new KbCorpus();
	const rowCount = config.lookupIndex.length as int32;
	const bitsPerRow: int64 = ((rowCount as int64) + 31) & ~(31 as int64);
	const step = rowCount > 24 ? (rowCount / 24) : 1;
	for (let row: int32 = 0; row < rowCount; row += step) {
		let ids: int32[] = [];
		for (let g: int32 = 0; g < glyphCount && ids.length < 400; g++) {
			const flat = (g as int64) * bitsPerRow + (row as int64);
			const word = config.matrix[(flat / 32) as int32];
			if ((word & kbMatrixBit(flat)) != 0) { ids.push(g); }
		}
		if (ids.length > 0) { corpus.rows.push(ids); }
	}
	for (let g: int32 = 0; g < glyphCount && corpus.marks.length < 600; g++) {
		if (kbGlyphClasses(font, g).classValue == 3) { corpus.marks.push(g); }
	}
	return corpus;
}

export function kbLookupSequence(
	rng: KbRng,
	corpus: KbCorpus,
	glyphCount: int32,
	codepoints: int32[],
	ids: int32[],
	advances: int32[],
): void {
	const length = 1 + rng.below(10);
	let stream: int32[] = [];
	let row = corpus.rows.length > 0 ? rng.below(corpus.rows.length as int32) : 0;
	while (codepoints.length < length) {
		const roll = rng.below(100);
		if (roll < 35 || roll >= 90) {
			if (stream.length == 0) { kbLookupText(rng, stream); }
			codepoints.push(stream[0]);
			stream = stream.slice(1, stream.length);
			ids.push(-1);
		} else if (roll < 60 && corpus.rows.length > 0) {
			if (rng.below(2) == 0) { row = rng.below(corpus.rows.length as int32); }
			const rowIds = corpus.rows[row];
			codepoints.push(0xE000);
			ids.push(rowIds[rng.below(rowIds.length as int32)]);
		} else if (roll < 75) {
			codepoints.push(0xE000);
			ids.push(rng.below(glyphCount + 8));
		} else if (corpus.marks.length > 0) {
			codepoints.push(0xE000);
			ids.push(corpus.marks[rng.below(corpus.marks.length as int32)]);
		} else {
			codepoints.push(0xE000);
			ids.push(rng.below(glyphCount));
		}
		advances.push(rng.below(800));
	}
}

export function kbLookupVariation(rng: KbRng): int32[] {
	let vector: int32[] = [];
	for (let i: int32 = 0; i < 32; i++) { vector.push(rng.below(32769) - 16384); }
	return vector;
}

export function kbDriveOrUb(
	font: KbFont,
	config: KbDriveConfig,
	codepoints: int32[],
	ids: int32[],
	advances: int32[],
): int32[] {
	try {
		return kbDrive(font, config, codepoints, ids, advances);
	} catch (e) {
		if (e instanceof KbFontBoundsError) { return [-1]; }
		throw e;
	}
}

export function kbLookupDigestStep(h: uint32, dump: int32[]): uint32 {
	let result = h;
	result = (result ^ (dump.length as uint32)) * 16777619;
	for (let i: int32 = 0; i < dump.length; i++) {
		result = (result ^ kbUint32Bits(dump[i])) * 16777619;
	}
	return result;
}

export function kbLookupWordCodepoints(word: string): int32[] {
	let out: int32[] = [];
	for (let i: int32 = 0; i < (word.length as int32); i++) { out.push(word.charCodeAt(i)); }
	return out;
}

export function kbLookupDigestOf(
	font: KbFont,
	words: string[],
	seeds: int32,
	perSeed: int32,
	want: int32,
): uint32 {
	let h: uint32 = 2166136261;
	const glyphCount = kbGlyphCountOf(font.blob);
	for (let mode: int32 = 0; mode < 2; mode++) {
		for (let seed: int32 = 0; seed < seeds; seed++) {
			const density = seed == 0 ? 0 : (seed % 3 == 1 ? 30 : 80);
			const config = kbLookupConfig(font, mode == 1, seed % 9, want, (seed + 1) as uint32 * 7919,
				density);
			if (config.lookupIndex.length == 0) { continue; }
			const rng = new KbRng((seed * 2654435761 + 12345) as uint32);
			if (seed % 2 == 1) { config.variation = kbLookupVariation(rng); }
			const corpus = kbLookupCorpus(font, config);

			for (let w: int32 = 0; w < (words.length as int32); w++) {
				const codepoints = kbLookupWordCodepoints(words[w]);
				let ids: int32[] = [];
				let advances: int32[] = [];
				for (let i: int32 = 0; i < codepoints.length; i++) {
					ids.push(-1);
					advances.push(rng.below(800));
				}
				h = kbLookupDigestStep(h, kbDriveOrUb(font, config, codepoints, ids, advances));
			}
			for (let q: int32 = 0; q < perSeed; q++) {
				let codepoints: int32[] = [];
				let ids: int32[] = [];
				let advances: int32[] = [];
				kbLookupSequence(rng, corpus, glyphCount, codepoints, ids, advances);
				h = kbLookupDigestStep(h, kbDriveOrUb(font, config, codepoints, ids, advances));
			}
		}
	}
	return h;
}
