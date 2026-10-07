import {
	FaceSummary,
	SfntSequence,
	glyphIndex,
	loadFace,
	peekFace,
	summaryCovers,
	summarySequence,
} from "../void2d/face";

const DIR: string = "tests/fonts/cmap/";
const SELECTOR_TEXT: int32 = 0xFE0E;
const SELECTOR_EMOJI: int32 = 0xFE0F;
const SELECTOR_IVS: int32 = 0xE0100;

function peeked(name: string): FaceSummary {
	const r = peekFace(DIR + name);
	if (r.ok) { return r.value; }
	console.log(`sfntCmapCheck: ${name} was refused (${r.error.toString()})`);
	unreachable;
}

let failures: int32 = 0;

function fail(message: string): void {
	failures = failures + 1;
	console.log(`sfntCmapCheck: ${message}`);
}

function covers(name: string, yes: int32[], no: int32[]): void {
	const summary = peeked(name);
	for (const codepoint of yes) {
		if (!summaryCovers(summary, codepoint)) {
			fail(`${name} should cover U+${codepoint.toString(16)}`);
		}
	}
	for (const codepoint of no) {
		if (summaryCovers(summary, codepoint)) {
			fail(`${name} should not cover U+${codepoint.toString(16)}`);
		}
	}
}

test "format 0 stops at its declared length" {
	failures = 0;
	covers("format0Full.ttf", [0x41, 0x50, 0xFF], [0x42, 0x100]);
	covers("format0Short.ttf", [0x41, 0x4F], [0x50, 0xFF]);
	assert failures == 0;
}

test "format 6 covers its range and a zero glyph is not coverage" {
	failures = 0;
	covers("format6.ttf", [0x30, 0x31], [0x2F, 0x32, 0x33]);
	assert failures == 0;
}

test "format 4 reads deltas and the glyph id array, and a zero glyph is not coverage" {
	failures = 0;
	covers(
		"format4.ttf",
		[0x41, 0x43, 0x61, 0x200, 0x201],
		[0x40, 0x44, 0x62, 0x63, 0x202, 0xFFFF, 0x10041],
	);
	assert failures == 0;
}

test "format 4 without a terminal segment does not extend its last segment" {
	failures = 0;
	covers("format4NoTerminal.ttf", [0x41, 0x43, 0x61], [0x44, 0x62, 0x63, 0x1000, 0xFFFF]);
	assert failures == 0;
}

test "format 12 counts glyphs up from the group start and format 13 shares one glyph" {
	failures = 0;
	covers(
		"format12.ttf",
		[0x301, 0x3FF, 0x1F600, 0x1F602, 0x20000, 0x20002],
		[0x2FF, 0x300, 0x1F603, 0x1FFFF, 0x20003],
	);
	covers("format13.ttf", [0x100, 0x150, 0x1FF], [0xFF, 0x200, 0x300, 0x301]);
	assert failures == 0;
}

test "a subtable of a format the peek does not read covers nothing, as in stb_truetype" {
	for (const name of ["format2.ttf", "format10.ttf"]) {
		const summary = peeked(name);
		assert summary.drawable;
		assert !summaryCovers(summary, 0x41);
	}
}

test "the last Unicode or MS record wins, as stb_truetype chooses" {
	failures = 0;
	covers("choiceMsThenUnicode.ttf", [0x42], [0x41]);
	covers("choiceUnicodeThenMs.ttf", [0x41], [0x42]);
	covers("choiceUnicodeTwice.ttf", [0x43], [0x42]);
	covers("choiceMsFullThenBmp.ttf", [0x41], [0x42]);
	covers("choiceMsBmpThenFull.ttf", [0x42], [0x41]);
	covers("choiceMacThenMsFull.ttf", [0x41], [0x42]);
	assert failures == 0;
}

test "MS symbol, MS other and Mac records are never chosen" {
	const summary = peeked("choiceIgnored.ttf");
	assert !summary.drawable;
	for (const codepoint of [0x41, 0x42, 0x43]) {
		assert !summaryCovers(summary, codepoint);
	}
}

test "every record order agrees with the face stb_truetype loads" {
	failures = 0;
	const probes: int32[] = [
		0x2F, 0x30, 0x31, 0x32, 0x33, 0x40, 0x41, 0x42, 0x43, 0x44, 0x4F, 0x50, 0x61, 0x62,
		0xFF, 0x100, 0x150, 0x1FF, 0x200, 0x201, 0x202, 0x300, 0x301, 0x1F600, 0x1F602,
		0x1F603, 0x20002, 0x10041, 0xFFFF,
	];
	const names: string[] = [
		"format0Full.ttf", "format0Short.ttf", "format6.ttf", "format4.ttf", "format4NoTerminal.ttf",
		"format12.ttf",
		"format13.ttf", "choiceMsThenUnicode.ttf", "choiceUnicodeThenMs.ttf",
		"choiceUnicodeTwice.ttf", "choiceMsFullThenBmp.ttf", "choiceMsBmpThenFull.ttf",
		"choiceMacThenMsFull.ttf", "controlFormat4.ttf", "controlFormat12.ttf",
	];
	for (const name of names) {
		const summary = peeked(name);
		const face = try loadFace(DIR + name) catch -1;
		assert face >= 0;
		for (const codepoint of probes) {
			const expected: boolean = glyphIndex(face, codepoint) != 0;
			if (summaryCovers(summary, codepoint) != expected) {
				fail(`${name} U+${codepoint.toString(16)} stb_truetype ${expected}`);
			}
		}
	}
	assert failures == 0;
}

test "a variation sequence is looked up by selector, with specific entries before default ranges" {
	const s = peeked("sequences.ttf");
	assert summarySequence(s, 0x2700, SELECTOR_TEXT) == SfntSequence.Default;
	assert summarySequence(s, 0x2702, SELECTOR_TEXT) == SfntSequence.Default;
	assert summarySequence(s, 0x2703, SELECTOR_TEXT) == SfntSequence.None;
	assert summarySequence(s, 0x2764, SELECTOR_TEXT) == SfntSequence.Default;
	assert summarySequence(s, 0x2765, SELECTOR_TEXT) == SfntSequence.None;
	assert summarySequence(s, 0x1F600, SELECTOR_TEXT) == SfntSequence.Specific;
	assert summarySequence(s, 0x1F601, SELECTOR_TEXT) == SfntSequence.None;
	assert summarySequence(s, 0x2701, SELECTOR_EMOJI) == SfntSequence.Specific;
	assert summarySequence(s, 0x2700, SELECTOR_EMOJI) == SfntSequence.Default;
	assert summarySequence(s, 0x41, SELECTOR_IVS) == SfntSequence.Default;
	assert summarySequence(s, 0x41, SELECTOR_EMOJI) == SfntSequence.None;
	assert summarySequence(s, 0x2700, 0xFE00) == SfntSequence.None;
	assert summarySequence(s, 0x2700, 0xE0101) == SfntSequence.None;
	assert summarySequence(s, 0x2700, 0) == SfntSequence.None;
}

test "only a Unicode variation-sequence record of format 14 supplies sequences" {
	const names: string[] = [
		"sequenceNotFormat14.ttf", "sequenceWrongEncoding.ttf", "sequenceWrongPlatform.ttf",
	];
	for (const name of names) {
		const s = peeked(name);
		assert summaryCovers(s, 0x41);
		for (const codepoint of [0x2700, 0x2701, 0x1F600]) {
			assert summarySequence(s, codepoint, SELECTOR_TEXT) == SfntSequence.None;
			assert summarySequence(s, codepoint, SELECTOR_EMOJI) == SfntSequence.None;
		}
	}
}
