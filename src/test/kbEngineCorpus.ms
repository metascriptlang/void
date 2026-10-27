import { KbFontBoundsError } from "../void2d/kb/blob";
import { KbShapeConfig } from "../void2d/kb/config";
import { KbFont, kbCodepointToGlyphId } from "../void2d/kb/font";
import { KB_DELETED_SORT_KEY, KB_GLYPH_SENTINEL, KbGlyphStorage, kbPushGlyph } from "../void2d/kb/glyph";
import { kbShapeDirectObserved } from "../void2d/kb/engine";
import { KB_BUCKETED_GLYPHS_PER_BLOCK, KbScratch, kbPlaceShapeScratch } from "../void2d/kb/scratch";
import { kbGetVariationInfo } from "../void2d/kb/shapeConfig";
import {
	KB_DIRECTION_LTR,
	KB_DIRECTION_RTL,
	KB_SCRIPT_ADLAM,
	KB_SCRIPT_ARABIC,
	KB_SCRIPT_BALINESE,
	KB_SCRIPT_BATAK,
	KB_SCRIPT_BENGALI,
	KB_SCRIPT_BRAHMI,
	KB_SCRIPT_BUGINESE,
	KB_SCRIPT_CHAM,
	KB_SCRIPT_DEFAULT,
	KB_SCRIPT_DEVANAGARI,
	KB_SCRIPT_DONT_KNOW,
	KB_SCRIPT_GUJARATI,
	KB_SCRIPT_GURMUKHI,
	KB_SCRIPT_HANGUL,
	KB_SCRIPT_HEBREW,
	KB_SCRIPT_JAVANESE,
	KB_SCRIPT_KANNADA,
	KB_SCRIPT_KHAROSHTHI,
	KB_SCRIPT_KHMER,
	KB_SCRIPT_LAO,
	KB_SCRIPT_LATIN,
	KB_SCRIPT_LIMBU,
	KB_SCRIPT_MALAYALAM,
	KB_SCRIPT_MANDAIC,
	KB_SCRIPT_MYANMAR,
	KB_SCRIPT_NKO,
	KB_SCRIPT_ODIA,
	KB_SCRIPT_SINHALA,
	KB_SCRIPT_SUNDANESE,
	KB_SCRIPT_SYRIAC,
	KB_SCRIPT_TAGALOG,
	KB_SCRIPT_TAI_THAM,
	KB_SCRIPT_TAMIL,
	KB_SCRIPT_TELUGU,
	KB_SCRIPT_THAI,
	KB_SCRIPT_TIBETAN,
} from "../void2d/kb/shapeTables";
import { kbConfigDigestStep, kbConfigNormalized, kbConfigPlaceOrUb, kbConfigVectors } from "./kbConfigCorpus";
import { KbRng } from "./kbLookupCorpus";

export struct KbEngineCase {
	script: uint32;
	language: uint32;
	direction: uint32;
	varied: boolean;
	codepoints: int32[];
}

// One text family: the script it is shaped under, the ranges its random texts draw from, and the
// codepoints that decide a shaper's branches (virama, medials, split vowels, joiners) drawn more often.
struct KbEnginePool {
	script: uint32;
	direction: uint32;
	ranges: int32[];
	specials: int32[];
}

function hexDigit(code: int32): int32 {
	return code >= 97 ? code - 87 : (code >= 65 ? code - 55 : code - 48);
}

function hex(text: string): int32[] {
	let result: int32[] = [];
	for (const part of text.split(" ")) {
		let value: int32 = 0;
		for (let i: int32 = 0; i < (part.length as int32); i++) {
			value = value * 16 + hexDigit(part.charCodeAt(i));
		}
		result.push(value);
	}
	return result;
}

function cat(a: int32[], b: int32[]): int32[] {
	let result: int32[] = [];
	for (const item of a) { result.push(item); }
	for (const item of b) { result.push(item); }
	return result;
}

function indicPool(script: uint32, base: int32, specials: int32[]): KbEnginePool {
	return {
		script, direction: KB_DIRECTION_LTR,
		ranges: [base, base + 0x7F, base + 0x15, base + 0x39, base + 0x3E, base + 0x4C, base + 0x04, base + 0x14],
		specials: cat([0x200D, 0x200C, 0x25CC, 0x20, base + 0x4D, base + 0x3C, base + 0x02, base + 0x03, base + 0x30],
			specials),
	};
}

function blockPool(script: uint32, first: int32, last: int32, specials: int32[]): KbEnginePool {
	return {
		script, direction: KB_DIRECTION_LTR, ranges: [first, last],
		specials: cat([0x200D, 0x200C, 0x25CC, 0x20], specials),
	};
}

function pools(): KbEnginePool[] {
	return [
		{ script: KB_SCRIPT_LATIN, direction: KB_DIRECTION_LTR,
			ranges: [0x41, 0x5A, 0x61, 0x7A, 0x300, 0x36F, 0xC0, 0x17F],
			specials: [0x66, 0x69, 0x6C, 0xFB01, 0x20, 0x2D, 0x3A, 0x200D, 0x200C, 0xAD, 0xA0, 0x41, 0x56, 0x54, 0x6F] },
		{ script: KB_SCRIPT_DEFAULT, direction: KB_DIRECTION_LTR,
			ranges: [0x1F300, 0x1F64F, 0x61, 0x7A, 0x4E00, 0x4E40],
			specials: [0x1F468, 0x200D, 0x1F469, 0x1F466, 0xFE0F, 0x1F3FB, 0x2764, 0x20, 0x1F1FA, 0x1F1F8, 0x23, 0x20E3] },
		{ script: KB_SCRIPT_DONT_KNOW, direction: KB_DIRECTION_LTR,
			ranges: [0x20, 0x7E, 0x900, 0x97F, 0x5D0, 0x5EA, 0x627, 0x64A, 0xE01, 0xE4E],
			specials: [0x200D, 0x200C, 0x20] },
		{ script: KB_SCRIPT_ARABIC, direction: KB_DIRECTION_RTL,
			ranges: [0x620, 0x64A, 0x64B, 0x65F, 0x671, 0x6D3, 0x610, 0x61A],
			specials: [0x640, 0x200D, 0x200C, 0x20, 0x654, 0x655, 0x670, 0x644, 0x627, 0x6D4, 0x622, 0x623, 0x625] },
		{ script: KB_SCRIPT_SYRIAC, direction: KB_DIRECTION_RTL,
			ranges: [0x710, 0x74A, 0x730, 0x74A],
			specials: [0x70F, 0x200D, 0x200C, 0x20, 0x710, 0x72C, 0x732, 0x71D, 0x715] },
		{ script: KB_SCRIPT_MANDAIC, direction: KB_DIRECTION_RTL, ranges: [0x840, 0x85B],
			specials: [0x200D, 0x20, 0x859, 0x85A, 0x85B] },
		{ script: KB_SCRIPT_NKO, direction: KB_DIRECTION_RTL, ranges: [0x7C0, 0x7FA, 0x7EB, 0x7F5],
			specials: [0x200D, 0x20, 0x7FA, 0x7EB] },
		{ script: KB_SCRIPT_ADLAM, direction: KB_DIRECTION_RTL, ranges: [0x1E900, 0x1E94B, 0x1E944, 0x1E94A],
			specials: [0x200D, 0x20] },
		{ script: KB_SCRIPT_HEBREW, direction: KB_DIRECTION_RTL,
			ranges: [0x5D0, 0x5EA, 0x591, 0x5C7],
			specials: [0x5BE, 0x20, 0x200D, 0x5B7, 0x5B8, 0x5C1, 0x5C2, 0x5BC, 0x5E9, 0x5D5, 0x5F2] },
		indicPool(KB_SCRIPT_DEVANAGARI, 0x900, [0x94D, 0x93E, 0x93F, 0x940, 0x941, 0x947, 0x94B, 0x94C, 0x930]),
		indicPool(KB_SCRIPT_BENGALI, 0x980, [0x9CD, 0x9C7, 0x9C8, 0x9CB, 0x9CC, 0x9B0, 0x9AF, 0x9BE]),
		indicPool(KB_SCRIPT_GURMUKHI, 0xA00, [0xA4D, 0xA3F, 0xA47, 0xA71, 0xA70, 0xA30, 0xA39]),
		indicPool(KB_SCRIPT_GUJARATI, 0xA80, [0xACD, 0xABF, 0xAC7, 0xAC8, 0xAB0, 0xA95]),
		indicPool(KB_SCRIPT_ODIA, 0xB00, [0xB4D, 0xB47, 0xB48, 0xB4B, 0xB30, 0xB15]),
		indicPool(KB_SCRIPT_TAMIL, 0xB80, [0xBCD, 0xBC6, 0xBC7, 0xBC8, 0xBCA, 0xBCB, 0xBCC, 0xB95]),
		indicPool(KB_SCRIPT_TELUGU, 0xC00, [0xC4D, 0xC46, 0xC47, 0xC4A, 0xC56, 0xC55, 0xC30]),
		indicPool(KB_SCRIPT_KANNADA, 0xC80, [0xCCD, 0xCC6, 0xCC7, 0xCCA, 0xCD5, 0xCD6, 0xCB0]),
		indicPool(KB_SCRIPT_MALAYALAM, 0xD00, [0xD4D, 0xD46, 0xD47, 0xD4A, 0xD3E, 0xD4E, 0xD31]),
		indicPool(KB_SCRIPT_SINHALA, 0xD80, [0xDCA, 0xDD9, 0xDDA, 0xDDC, 0xDCF, 0xDDD, 0xDDE, 0xDBB]),
		{ script: KB_SCRIPT_KHMER, direction: KB_DIRECTION_LTR,
			ranges: [0x1780, 0x17A2, 0x17A3, 0x17B5, 0x17B6, 0x17C5, 0x17C6, 0x17D3],
			specials: [0x17D2, 0x17C1, 0x17C2, 0x17C3, 0x17C4, 0x17C5, 0x17BB, 0x17CC, 0x17C9, 0x200C, 0x200D, 0x25CC,
				0x20, 0x179A, 0x17D3] },
		{ script: KB_SCRIPT_MYANMAR, direction: KB_DIRECTION_LTR,
			ranges: [0x1000, 0x1020, 0x103B, 0x103E, 0x102B, 0x1032, 0x1036, 0x103A, 0x1000, 0x109F],
			specials: [0x1039, 0x103A, 0x1031, 0x103B, 0x103C, 0x103D, 0x103E, 0x1004, 0x1037, 0x200C, 0x200D, 0x25CC,
				0x20, 0x1014, 0x102C, 0x102D] },
		{ script: KB_SCRIPT_HANGUL, direction: KB_DIRECTION_LTR,
			ranges: [0x1100, 0x115F, 0x1160, 0x11A7, 0x11A8, 0x11FF, 0xAC00, 0xD7A3, 0xA960, 0xA97C, 0xD7B0, 0xD7FB],
			specials: [0xAC00, 0xAC01, 0xD7A3, 0x302E, 0x302F, 0x20, 0x25CC, 0x1100, 0x1161, 0x11A8, 0x3131, 0x1160] },
		{ script: KB_SCRIPT_THAI, direction: KB_DIRECTION_LTR,
			ranges: [0xE01, 0xE2E, 0xE30, 0xE3A, 0xE40, 0xE4E],
			specials: [0xE33, 0xE4D, 0xE48, 0xE49, 0xE4A, 0xE4B, 0xE31, 0xE34, 0xE37, 0xE38, 0xE39, 0xE40, 0xE44, 0x20,
				0x25CC, 0xE2D, 0xE0D, 0xE10] },
		{ script: KB_SCRIPT_LAO, direction: KB_DIRECTION_LTR,
			ranges: [0xE81, 0xEAE, 0xEB0, 0xEBD, 0xEC0, 0xECD],
			specials: [0xEB3, 0xECD, 0xEC8, 0xEC9, 0xECA, 0xECB, 0xEBB, 0xEB4, 0xEB9, 0x20, 0x25CC, 0xEAB] },
		{ script: KB_SCRIPT_TIBETAN, direction: KB_DIRECTION_LTR,
			ranges: [0xF40, 0xF6C, 0xF71, 0xF84, 0xF90, 0xFBC],
			specials: [0xF71, 0xF72, 0xF74, 0xF7A, 0xF7C, 0xF80, 0xF0B, 0x20, 0x25CC, 0xFB1, 0xFB2, 0xF42, 0xF77, 0xF79] },
		blockPool(KB_SCRIPT_JAVANESE, 0xA980, 0xA9DF, [0xA9C0, 0xA9B6, 0xA9BF, 0xA9BC, 0xA9B4, 0xA9BA, 0xA9B5]),
		blockPool(KB_SCRIPT_BALINESE, 0x1B00, 0x1B7F, [0x1B44, 0x1B3E, 0x1B3F, 0x1B38, 0x1B35, 0x1B13, 0x1B04]),
		blockPool(KB_SCRIPT_BRAHMI, 0x11000, 0x1107F, [0x11046, 0x1103A, 0x11038, 0x11013, 0x11000]),
		blockPool(KB_SCRIPT_KHAROSHTHI, 0x10A00, 0x10A5F, [0x10A3F, 0x10A0A, 0x10A01, 0x10A38, 0x10A0D]),
		blockPool(KB_SCRIPT_TAI_THAM, 0x1A20, 0x1AAD, [0x1A60, 0x1A6E, 0x1A63, 0x1A55, 0x1A56, 0x1A74]),
		blockPool(KB_SCRIPT_SUNDANESE, 0x1B80, 0x1BBF, [0x1BAA, 0x1BA1, 0x1BA2, 0x1BA3, 0x1B8B]),
		blockPool(KB_SCRIPT_CHAM, 0xAA00, 0xAA5F, [0xAA36, 0xAA33, 0xAA34, 0xAA35, 0xAA29]),
		blockPool(KB_SCRIPT_BATAK, 0x1BC0, 0x1BFF, [0x1BF2, 0x1BF3, 0x1BEE, 0x1BE6, 0x1BD1]),
		blockPool(KB_SCRIPT_BUGINESE, 0x1A00, 0x1A1F, [0x1A17, 0x1A18, 0x1A19, 0x1A00]),
		blockPool(KB_SCRIPT_TAGALOG, 0x1700, 0x171F, [0x1714, 0x1712, 0x1713, 0x1703]),
		blockPool(KB_SCRIPT_LIMBU, 0x1900, 0x194F, [0x193B, 0x1920, 0x1927, 0x1939, 0x1904]),
	];
}

function fixed(script: uint32, direction: uint32, text: string): KbEngineCase {
	return { script, language: 0, direction, varied: false, codepoints: hex(text) };
}

function fixedCases(): KbEngineCase[] {
	const l = KB_DIRECTION_LTR;
	const r = KB_DIRECTION_RTL;
	return [
		fixed(KB_SCRIPT_LATIN, l, "66 69 20 66 66 69 20 66 6C 20 41 56 20 54 6F 20 FB01"),
		fixed(KB_SCRIPT_LATIN, l, "65 301 61 308 20 41 30A 6F 323 302 20 AD 66 AD 69"),
		fixed(KB_SCRIPT_ARABIC, r, "644 627 20 628 633 645 20 627 644 644 647 20 644 645 20 633 640 640 645 20 628 64E 65F"),
		fixed(KB_SCRIPT_ARABIC, r, "62A 64E 651 20 6A9 6CC 20 645 64B 651 64D 650 20 622 200D 628 200C 628"),
		fixed(KB_SCRIPT_SYRIAC, r, "710 72C 70F 712 713 20 71D 732 72A 71D 710"),
		fixed(KB_SCRIPT_HEBREW, r, "5E9 5C1 5B8 5DC 5D5 5B9 5DD 20 5D0 5B7 5BE 5D1 5D5 5D5 5F2 5B7"),
		fixed(KB_SCRIPT_DEVANAGARI, l,
			"915 94D 937 20 930 94D 915 20 915 93F 20 915 94D 930 20 915 94C 20 915 93C 20 915 94D 200D 20 915 94D 200C 937 20 25CC 93E 20 928 94D 928 93F 20 937 94D 924 94D 930 20 915 94B 902 20 930 94D 915 94D 930 94D 915"),
		fixed(KB_SCRIPT_BENGALI, l, "995 9CD 9B7 20 9B0 9CD 995 20 995 9C7 9BE 20 995 9CB 20 9A6 9CD 9AF 20 9B0 9CD 200D"),
		fixed(KB_SCRIPT_GURMUKHI, l, "A15 A4D A39 A3F A15 A4D A30 A15 A47 A02"),
		fixed(KB_SCRIPT_GUJARATI, l, "A95 ACD AB7 AB0 ACD A95 ABF A95 AC8"),
		fixed(KB_SCRIPT_ODIA, l, "B15 B4D B37 B48 B3E B30 B4D B15 B4B"),
		fixed(KB_SCRIPT_TAMIL, l, "B95 BCD B37 BCA BCB BCC B95 BC6 BBE B95 BC7 BBE"),
		fixed(KB_SCRIPT_TELUGU, l, "C15 C4D C37 C46 C56 C4A C30 C4D C15"),
		fixed(KB_SCRIPT_KANNADA, l, "C95 CCD CB7 CB0 CCD C95 CC6 CD5 CC0 CCA C95 CCB"),
		fixed(KB_SCRIPT_MALAYALAM, l, "D15 D4D D37 D46 D3E D0E D31 D4D D31 D15 D4A"),
		fixed(KB_SCRIPT_SINHALA, l, "D9A DCA DC2 DD9 DCF DDC DDA DD9 DCA D9A DDD"),
		fixed(KB_SCRIPT_KHMER, l, "1780 17D2 1798 17C1 17C4 1780 17BE 1780 17D2 179A 17C2 1785 17C9 17BB 17C1 17C7"),
		fixed(KB_SCRIPT_MYANMAR, l, "1000 103A 1004 103A 1039 1000 103B 103C 103D 103E 1031 102C 1014 1031 102C 103A 1019 103A"),
		fixed(KB_SCRIPT_HANGUL, l, "1100 1161 11A8 AC00 11A8 1100 1161 1112 1175 11B8 D55C AE00 3131 1100 1160 11A8 302E 1100 1161"),
		fixed(KB_SCRIPT_THAI, l, "E01 E33 E01 E48 E33 E1B E31 E01 E34 E49 E38 E01 E48 E31 E48 E48 E4D E32"),
		fixed(KB_SCRIPT_LAO, l, "EAB EB3 E81 EC8 EB3 EA1 EC9 EB1 EC0 E81 ECD EB2"),
		fixed(KB_SCRIPT_TIBETAN, l, "F40 FB1 F72 F74 F0B F56 F7C F42 FB7 F71 F72 F80 F77 F79"),
		fixed(KB_SCRIPT_JAVANESE, l, "A98F A9C0 A98F A9B6 A9BF A9B4"),
		fixed(KB_SCRIPT_BALINESE, l, "1B13 1B44 1B13 1B38 1B3E 1B3F"),
		fixed(KB_SCRIPT_BRAHMI, l, "11013 11046 11013 1103A 11038"),
		fixed(KB_SCRIPT_KHAROSHTHI, l, "10A00 10A3F 10A0A 10A01"),
		fixed(KB_SCRIPT_DEFAULT, l, "1F468 200D 1F469 200D 1F467 20 1F44D 1F3FB 20 2764 FE0F 20 1F1FA 1F1F8 20 23 20E3"),
	];
}

export function kbEngineCases(perPool: int32): KbEngineCase[] {
	let cases = fixedCases();
	const all = pools();
	for (let p: int32 = 0; p < all.length; p++) {
		const pool = all[p];
		const rng = new KbRng(0xE9 + (pool.script as uint32) * 131 + (p as uint32));
		const rangeCount = (pool.ranges.length as int32) / 2;
		for (let k: int32 = 0; k < perPool; k++) {
			const length = 1 + rng.below(16);
			let codepoints: int32[] = [];
			for (let i: int32 = 0; i < length; i++) {
				if (rng.below(3) != 0) {
					codepoints.push(pool.specials[rng.below(pool.specials.length as int32)]);
				} else {
					const range = rng.below(rangeCount);
					const low = pool.ranges[range * 2];
					const high = pool.ranges[range * 2 + 1];
					codepoints.push(low + rng.below(high - low + 1));
				}
			}
			const flip = k % 5 == 4;
			cases.push({
				script: pool.script, language: 0,
				direction: flip ? (pool.direction == KB_DIRECTION_LTR ? KB_DIRECTION_RTL : KB_DIRECTION_LTR) : pool.direction,
				varied: k % 4 == 3, codepoints,
			});
		}
	}
	return cases;
}

// The generic cases plus, per pool, texts drawn only from codepoints this font maps, so its GSUB and GPOS
// lookups are reached instead of the glyph 0 a block-wide draw mostly hits.
export function kbEngineFontCases(font: KbFont, perPool: int32): KbEngineCase[] {
	let cases = kbEngineCases(perPool);
	const all = pools();
	for (let p: int32 = 0; p < all.length; p++) {
		const pool = all[p];
		let present: int32[] = [];
		for (const special of pool.specials) {
			if (kbCodepointToGlyphId(font, special) != 0) {
				present.push(special);
				present.push(special);
			}
		}
		for (let r: int32 = 0; r < (pool.ranges.length as int32); r += 2) {
			for (let cp = pool.ranges[r]; cp <= pool.ranges[r + 1]; cp++) {
				if (kbCodepointToGlyphId(font, cp) != 0) { present.push(cp); }
			}
		}
		if (present.length < 2) { continue; }
		const rng = new KbRng(0x5EED + (pool.script as uint32) * 977 + (p as uint32));
		for (let k: int32 = 0; k < perPool; k++) {
			const length = 2 + rng.below(15);
			let codepoints: int32[] = [];
			for (let i: int32 = 0; i < length; i++) {
				codepoints.push(present[rng.below(present.length as int32)]);
			}
			cases.push({
				script: pool.script, language: 0, direction: pool.direction,
				varied: k % 4 == 3, codepoints,
			});
		}
	}
	return cases;
}

// The one non-default vector a variable font is shaped under; null for a font without axes.
export function kbEngineVariedVector(font: KbFont): float32[] | null {
	if (kbGetVariationInfo(font).axisCount == 0) { return null; }
	return kbConfigVectors(font)[2];
}

function wrap32(value: int64): int32 {
	return (((value & 0xFFFFFFFF) ^ 0x80000000) - 0x80000000) as int32;
}

// Mirrors the dump of out/tmp/kbEngineRef.c (tag zeroed): the scratch state, then the glyph list in order.
function dumpStep(out: int32[], s: KbScratch): void {
	const glyphs = s.storage.glyphs;
	let order: int32[] = [];
	let at = glyphs[KB_GLYPH_SENTINEL].next;
	while (at != KB_GLYPH_SENTINEL) {
		order.push(at);
		at = glyphs[at].next;
	}
	out.push(0);
	out.push(wrap32(s.nextGlyphUid as int64));
	out.push(wrap32(s.ip as int64));
	out.push(wrap32(s.featureStagesRead as int64));
	out.push(s.clusterAtStartOfWord ? 1 : 0);
	out.push(wrap32(s.sequentialLookupIndexIndex as int64));
	out.push(s.sequentialLookupCount);
	out.push(order.length as int32);
	for (let p: int32 = 0; p < order.length; p++) {
		const g = glyphs[order[p]];
		let attach: int32 = -1;
		if (g.attachGlyph != 0) {
			attach = -2;
			for (let q: int32 = 0; q < order.length; q++) {
				if (order[q] == g.attachGlyph) {
					attach = q;
					break;
				}
			}
		}
		out.push(g.id as int32);
		out.push(wrap32(g.codepoint as int64));
		out.push(g.uid as int32);
		out.push(g.userIdOrCodepointIndex);
		out.push(g.offsetX);
		out.push(g.offsetY);
		out.push(g.advanceX);
		out.push(g.advanceY);
		out.push(attach);
		out.push(g.classValue as int32);
		out.push(g.markAttachmentClass as int32);
		out.push(wrap32(g.flags as int64));
		out.push(wrap32(g.sortKey as int64));
		out.push(wrap32(g.sortKeyInterval as int64));
		out.push(g.ligatureUid as int32);
		out.push(g.ligatureComponentIndexPlusOne as int32);
		out.push(g.ligatureComponentCount as int32);
		out.push(g.joiningFeature as int32);
		out.push(g.joiningType as int32);
		out.push(g.unicodeFlags as int32);
		out.push(g.syllabicClass as int32);
		out.push(g.syllabicPosition as int32);
		out.push(g.useClass as int32);
		out.push(g.combiningClass as int32);
		out.push(g.markOrdering as int32);
		out.push(wrap32((g.decomposition & 0xFFFFFFFF) as int64));
		out.push(wrap32((g.decomposition >> 32) as int64));
		out.push(wrap32(g.parentInfo as int64));
		out.push(g.configPlusOne != 0 ? 1 : 0);
		out.push(g.bucketedPlusOne != 0 ? 1 : 0);
		out.push(g.bucketedPlusOne != 0 ? (g.bucketedBucketIndex as int32) : -1);
	}
	for (let i: int32 = 0; i < s.sequentialLookupCount; i++) {
		const blocks = s.bucketBlocks[i];
		let entries: int32 = 0;
		let valid: int32 = 0;
		for (let b: int32 = 0; b < blocks.length; b++) {
			const count = s.blockCounts[blocks[b]];
			entries += count;
			for (let e: int32 = 0; e < count; e++) {
				if (s.blockEntries[blocks[b] * KB_BUCKETED_GLYPHS_PER_BLOCK + e].sortKey != KB_DELETED_SORT_KEY) { valid++; }
			}
		}
		out.push(blocks.length as int32);
		out.push(entries);
		out.push(valid);
	}
}

// Every intermediate state and the final run, as one int stream; throws KbFontBoundsError where the C is
// undefined behaviour.
export function kbEnginePortRun(
	m: Span<uint8>,
	config: KbShapeConfig,
	codepoints: int32[],
	direction: uint32,
	normalized: int32[],
): int32[] {
	const storage = new KbGlyphStorage();
	for (let i: int32 = 0; i < codepoints.length; i++) {
		kbPushGlyph(storage, config.font, codepoints[i], 0, i);
	}
	const s = kbPlaceShapeScratch(config, storage);
	let out: int32[] = [];
	kbShapeDirectObserved(s, m, direction, normalized, (x: KbScratch): void => { dumpStep(out, x); });
	dumpStep(out, s);
	return out;
}

export function kbEngineDigestOf(font: KbFont, perPool: int32): uint32 {
	const cases = kbEngineFontCases(font, perPool);
	let h: uint32 = 2166136261;
	const vector = kbEngineVariedVector(font);
	const normalizedVaried: int32[] = vector === null ? [] : kbConfigNormalized(font, vector);
	for (const item of cases) {
		if (item.varied && vector === null) { continue; }
		const config = kbConfigPlaceOrUb(font, item.script, item.language, item.varied ? vector : null);
		if (config === null) {
			h = kbConfigDigestStep(h, [-1]);
			continue;
		}
		const m: Span<uint8> = font.blob[0..font.blob.length];
		try {
			h = kbConfigDigestStep(h, kbEnginePortRun(m, config, item.codepoints, item.direction,
				item.varied ? normalizedVaried : []));
		} catch (e) {
			if (e instanceof KbFontBoundsError) {
				h = kbConfigDigestStep(h, [-1]);
			} else {
				throw e;
			}
		}
	}
	return h;
}
