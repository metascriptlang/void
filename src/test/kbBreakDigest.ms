import { readFile } from "std/fs";
import {
	KbBreak,
	KbBreakState,
	kbBreakAddCodepoint,
	kbBreakBegin,
	kbBreakEnd,
	kbBreakNext,
} from "../void2d/kb/break";
import {
	kbBidirectionalClass,
	kbGraphemeBreakClass,
	kbLineBreakClass,
	kbScriptExtension,
	kbUnicodeFlags,
	kbWordBreakClass,
} from "../void2d/kb/unicode";

export const KB_BREAK_NAMES: string[] = [
	"pairs",
	"triples",
	"representatives",
	"mixed",
	"brackets",
	"increments",
	"ucdGrapheme",
	"ucdLine",
];

const UCD_GRAPHEME_ROWS: string = "tests/oracle/ucd/GraphemeBreakTest-18.0.0.txt";
const UCD_LINE_ROWS: string = "tests/oracle/ucd/LineBreakTest-18.0.0.txt";
const FNV_PRIME: uint32 = 16777619;

const CURATED: int32[] = [
	0x03, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x20, 0x21, 0x22, 0x24, 0x25, 0x26, 0x27, 0x28, 0x29, 0x2C,
	0x2D, 0x2E, 0x2F, 0x30, 0x31, 0x39, 0x3A, 0x3B, 0x3C, 0x3E, 0x3F, 0x41, 0x5B, 0x5D, 0x5F, 0x61,
	0x7B, 0x7D, 0x85, 0xA0, 0xA2, 0xA9, 0xAB, 0xAD, 0xB0, 0xB7, 0xBB, 0xE9, 0x300, 0x301, 0x308,
	0x345, 0x3B1, 0x430, 0x5B0, 0x5BE, 0x5D0, 0x5D1, 0x5F3, 0x5F4, 0x600, 0x60C, 0x61C, 0x627,
	0x628, 0x64B, 0x660, 0x661, 0x66B, 0x66C, 0x6F1, 0x710, 0x915, 0x93E, 0x94D, 0x937, 0xE01,
	0xE31, 0xE3F, 0xE40, 0x1000, 0x1039, 0x1100, 0x1161, 0x11A8, 0x1780, 0x17D2, 0x2010, 0x2011,
	0x2012, 0x2014, 0x2018, 0x2019, 0x201A, 0x201C, 0x201D, 0x201E, 0x2024, 0x2026, 0x2028, 0x2029,
	0x2030, 0x2039, 0x203A, 0x203C, 0x2060, 0x2066, 0x2067, 0x2068, 0x2069, 0x20AC, 0x20E3, 0x2640,
	0x2764, 0x3000, 0x3001, 0x3002, 0x3005, 0x3041, 0x3042, 0x30A0, 0x30A1, 0x30FB, 0x30FC, 0x4E00,
	0x4E8C, 0xAC00, 0xAC01, 0xD800, 0xFE0E, 0xFE0F, 0xFEFF, 0xFF08, 0xFF09, 0xFF21, 0xFFFE,
	0x1F1E6, 0x1F1E7, 0x1F1E8, 0x1F1E9, 0x1F3F4, 0x1F3FB, 0x1F44D, 0x1F466, 0x1F468, 0x1F469,
	0x1F600, 0x20000, 0xE0067, 0xE007F, 0x10FFFF, 0x110000, 0x200B, 0x200C, 0x200D, 0x200E,
	0x200F, 0x202A, 0x202B, 0x202C, 0x202D, 0x202E, -1, 0x7FFFFFFF,
];

const BRACKETS: int32[] = [
	0x28, 0x29, 0x5B, 0x5D, 0x7B, 0x7D, 0xAB, 0xBB, 0x2018, 0x2019, 0x201C, 0x201D, 0x2329,
	0x232A, 0x3008, 0x3009, 0x300C, 0x300D, 0xFF08, 0xFF09, 0x27E8, 0x27E9,
];

const OPENING: int32[] = [0x28, 0x5B, 0x7B, 0x300A, 0x300C, 0x3010, 0xFF08, 0x27E8];
const CLOSING: int32[] = [0x29, 0x5D, 0x7D, 0x300B, 0x300D, 0x3011, 0xFF09, 0x27E9];

export struct KbBreakCase {
	direction: uint32;
	style: uint8;
	config: uint32;
	endMode: int32;
	codepoints: Vec<int32>;
	increments: Vec<int32>;
}

struct Random {
	state: uint32;
}

function next(this ref random: Random, bound: uint32): uint32 {
	let x = random.state;
	x ^= x << 13;
	x ^= x >> 17;
	x ^= x << 5;
	random.state = x;
	return x % bound;
}

function oneOf(this ref random: Random, list: int32[]): int32 {
	return list[random.next(list.length as uint32) as int32];
}

export function kbFold(hash: uint32, value: uint32): uint32 {
	return (hash ^ value) * FNV_PRIME;
}

function foldWide(hash: uint32, value: uint64): uint32 {
	return kbFold(kbFold(hash, (value & 0xFFFFFFFF) as uint32), (value >> 32) as uint32);
}

function foldOffset(hash: uint32, value: int32): uint32 {
	return kbFold(hash, value as uint32);
}

export function kbBreakStateHash(state: KbBreakState): uint32 {
	let h: uint32 = 2166136261;
	for (let i: int32 = 0; i < 8; i++) {
		h = foldOffset(h, state.breaks[i].position);
		h = kbFold(h, state.breaks[i].flags);
		h = kbFold(h, state.breaks[i].direction);
		h = kbFold(h, state.breaks[i].paragraphDirection);
		h = kbFold(h, state.breaks[i].script);
	}
	h = kbFold(h, state.breakCount);
	h = kbFold(h, state.paragraphDirection);
	h = kbFold(h, state.userParagraphDirection);
	h = kbFold(h, state.currentPosition);
	h = kbFold(h, state.paragraphStartPosition);
	h = kbFold(h, state.lastScriptBreakPosition);
	h = kbFold(h, state.lastDirectionBreakPosition);
	h = kbFold(h, state.lastScriptBreakScript);
	h = kbFold(h, state.lastDirectionBreakDirection);
	h = foldOffset(h, state.scriptPositionOffset);
	h = kbFold(h, state.scriptCount);
	for (let i: int32 = 0; i < 23; i++) { h = kbFold(h, state.scriptSet[i]); }
	for (let i: int32 = 0; i < 64; i++) {
		h = kbFold(h, state.brackets[i].codepoint);
		h = kbFold(h, state.brackets[i].position);
		h = kbFold(h, state.brackets[i].direction);
		h = kbFold(h, state.brackets[i].script);
	}
	h = kbFold(h, state.bracketCount);
	h = kbFold(h, state.flags);
	h = kbFold(h, state.flagState);
	h = foldOffset(h, state.positionOffset2);
	h = foldOffset(h, state.positionOffset3);
	h = kbFold(h, state.wordBreakHistory);
	h = kbFold(h, state.wordBreaks);
	h = kbFold(h, state.wordUnbreaks);
	h = foldOffset(h, state.wordBreak2PositionOffset);
	h = foldWide(h, state.lineBreaks);
	h = foldWide(h, state.lineUnbreaksAsync);
	h = foldWide(h, state.lineUnbreaks);
	h = kbFold(h, state.lineBreakHistory);
	h = foldOffset(h, state.lineBreak2PositionOffset);
	h = foldOffset(h, state.lineBreak3PositionOffset);
	h = kbFold(h, state.lastDirection);
	h = kbFold(h, state.bidirectionalClass2);
	h = kbFold(h, state.bidirectionalClass1);
	h = foldOffset(h, state.bidirectional1PositionOffset);
	h = foldOffset(h, state.bidirectional2PositionOffset);
	h = kbFold(h, state.japaneseLineBreakStyle);
	h = kbFold(h, state.configFlags);
	h = kbFold(h, state.graphemeBreakState);
	h = kbFold(h, state.lastLineBreakClass);
	h = kbFold(h, state.lastWordBreakClass);
	h = kbFold(h, state.lastWordBreakClassIncludingIgnored);
	return h;
}

function drained(ref state: KbBreakState, hash: uint32): uint32 {
	let h = hash;
	let found: KbBreak = { position: 0, flags: 0, direction: 0, paragraphDirection: 0, script: 0 };
	while (state.kbBreakNext(out found)) {
		h = foldOffset(h, found.position);
		h = kbFold(h, found.flags);
		h = kbFold(h, found.direction);
		h = kbFold(h, found.paragraphDirection);
		h = kbFold(h, found.script);
	}
	return kbFold(h, 0xFFFFFFFF);
}

export function kbBreakRun(input: KbBreakCase, everyStep: boolean, hash: uint32): uint32 {
	let state = kbBreakBegin(input.direction, input.style, input.config);
	let h = kbFold(hash, input.codepoints.length as uint32);
	h = drained(state, h);
	const last = (input.codepoints.length as int32) - 1;
	for (let i: int32 = 0; i <= last; i++) {
		state.kbBreakAddCodepoint(input.codepoints[i], input.increments[i], input.endMode == 0 && i == last);
		h = drained(state, h);
		if (everyStep) { h = kbFold(h, kbBreakStateHash(state)); }
	}
	if (input.endMode == 2) {
		state.kbBreakEnd();
		h = drained(state, h);
	}
	return kbFold(h, kbBreakStateHash(state));
}

function plainCase(
	ref random: Random,
	codepoints: Vec<int32>,
	increments: Vec<int32>,
): KbBreakCase {
	return {
		direction: random.next(3),
		style: random.next(3) as uint8,
		config: random.next(2),
		endMode: random.next(3) as int32,
		codepoints: codepoints,
		increments: increments,
	};
}

function ones(count: int32): Vec<int32> {
	let out: Vec<int32> = new Array(0);
	for (let i: int32 = 0; i < count; i++) { out.push(1); }
	return out;
}

export function kbRepresentatives(): int32[] {
	let seen = new Set<uint64>();
	let out: int32[] = [];
	for (let codepoint: uint32 = 0; codepoint < 0x110000; codepoint++) {
		const key: uint64 = (kbLineBreakClass(codepoint) as uint64) |
			((kbWordBreakClass(codepoint) as uint64) << 8) |
			((kbGraphemeBreakClass(codepoint) as uint64) << 16) |
			((kbBidirectionalClass(codepoint) as uint64) << 24) |
			((kbUnicodeFlags(codepoint) as uint64) << 32) |
			((kbScriptExtension(codepoint) as uint64) << 40);
		if (!seen.has(key)) {
			seen.add(key);
			out.push(codepoint as int32);
		}
	}
	return out;
}

function ucdSequences(path: string): Vec<Vec<int32>> {
	let out: Vec<Vec<int32>> = new Array(0);
	const text = readFile(path);
	if (!text.ok) { throw new Error(`cannot read ${path}`); }
	for (const line of text.value.split("\n")) {
		if (line.byteLength == 0 || line.startsWith("#")) { continue; }
		const tokens = line.split(" ");
		let row: Vec<int32> = new Array(0);
		for (let i = 1; i < (tokens.length as int32); i += 2) {
			let value: int32 = 0;
			for (let j = 0; j < (tokens[i].byteLength as int32); j++) {
				value = value * 16 + "0123456789ABCDEF".indexOf(tokens[i].byteSlice(j, j + 1));
			}
			row.push(value);
		}
		out.push(row);
	}
	return out;
}

export function kbBreakCases(family: int32, representatives: int32[]): Vec<KbBreakCase> {
	let random: Random = { state: 2463534242 + (family as uint32) * 7919 };
	let out: Vec<KbBreakCase> = new Array(0);
	if (family == 0) {
		for (const first of CURATED) {
			for (const second of CURATED) {
				let codepoints: Vec<int32> = new Array(0);
				codepoints.push(first);
				codepoints.push(second);
				out.push(plainCase(random, codepoints, ones(2)));
			}
		}
	} else if (family == 1) {
		for (let n: int32 = 0; n < 30000; n++) {
			let codepoints: Vec<int32> = new Array(0);
			for (let i: int32 = 0; i < 3; i++) {
				codepoints.push(random.next(4) == 0 ? random.oneOf(representatives) : random.oneOf(CURATED));
			}
			out.push(plainCase(random, codepoints, ones(3)));
		}
	} else if (family == 2) {
		for (let n: int32 = 0; n < 20000; n++) {
			let codepoints: Vec<int32> = new Array(0);
			const length = 1 + (random.next(12) as int32);
			for (let i: int32 = 0; i < length; i++) { codepoints.push(random.oneOf(representatives)); }
			out.push(plainCase(random, codepoints, ones(length)));
		}
	} else if (family == 3) {
		for (let n: int32 = 0; n < 20000; n++) {
			let codepoints: Vec<int32> = new Array(0);
			const length = 1 + (random.next(60) as int32);
			for (let i: int32 = 0; i < length; i++) {
				const pick = random.next(10);
				if (pick < 5) {
					codepoints.push(random.oneOf(CURATED));
				} else if (pick < 8) {
					codepoints.push(random.oneOf(representatives));
				} else {
					codepoints.push(random.next(0x110000) as int32);
				}
			}
			out.push(plainCase(random, codepoints, ones(length)));
		}
	} else if (family == 4) {
		for (let n: int32 = 0; n < 6000; n++) {
			let codepoints: Vec<int32> = new Array(0);
			if (n % 25 == 0) {
				const deep = 62 + (random.next(8) as int32);
				let which: int32[] = [];
				for (let i: int32 = 0; i < deep; i++) {
					which.push(random.next(OPENING.length as uint32) as int32);
					codepoints.push(OPENING[which[i]]);
				}
				const between = 3 + (random.next(6) as int32);
				for (let i: int32 = 0; i < between; i++) { codepoints.push(random.oneOf(CURATED)); }
				for (let i: int32 = deep - 1; i >= 0; i--) { codepoints.push(CLOSING[which[i]]); }
			}
			const length = 1 + (random.next(n % 50 == 0 ? 220 : 40) as int32);
			for (let i: int32 = 0; i < length; i++) {
				const pick = random.next(10);
				if (pick < 5) {
					codepoints.push(random.oneOf(BRACKETS));
				} else if (pick < 8) {
					codepoints.push(random.oneOf(CURATED));
				} else {
					codepoints.push(random.oneOf(representatives));
				}
			}
			out.push(plainCase(random, codepoints, ones(codepoints.length as int32)));
		}
	} else if (family == 5) {
		for (let n: int32 = 0; n < 8000; n++) {
			let codepoints: Vec<int32> = new Array(0);
			let increments: Vec<int32> = new Array(0);
			const length = 1 + (random.next(25) as int32);
			for (let i: int32 = 0; i < length; i++) {
				codepoints.push(random.next(3) == 0 ? random.oneOf(representatives) : random.oneOf(CURATED));
				const pick = random.next(20);
				increments.push(pick == 0 ? 70000 + (random.next(70000) as int32) : (random.next(5) as int32));
			}
			out.push(plainCase(random, codepoints, increments));
		}
	} else if (family == 6 || family == 7) {
		const rows = ucdSequences(family == 6 ? UCD_GRAPHEME_ROWS : UCD_LINE_ROWS);
		for (const row of rows) {
			let input = plainCase(random, row, ones(row.length as int32));
			input.direction = 0;
			input.style = 1;
			input.config = 0;
			input.endMode = 0;
			out.push(input);
		}
	} else {
		throw new Error(`no kb break family ${family}`);
	}
	return out;
}

export function kbBreakDigest(family: int32, representatives: int32[]): uint32 {
	const cases = kbBreakCases(family, representatives);
	const everyStep = family == 0 || family == 1 || family == 6 || family == 7;
	let h: uint32 = 2166136261;
	for (const input of cases) { h = kbBreakRun(input, everyStep, h); }
	return h;
}
