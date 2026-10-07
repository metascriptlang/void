import {
	FaceSummary,
	SfntError,
	SfntSequence,
	peekFace,
	summaryCovers,
	summarySequence,
} from "../void2d/face";

const DIR: string = "tests/fonts/cmap/";
const SELECTOR: int32 = 0xFE0F;
const PROBES: int32[] = [0x0, 0x1, 0x41, 0x43, 0x61, 0x1F600, 0x1F601, 0x1F602, 0xFFFF];

function peeked(name: string): FaceSummary {
	const r = peekFace(DIR + name);
	if (r.ok) { return r.value; }
	console.log(`sfntBoundsCheck: ${name} was refused (${r.error.toString()})`);
	unreachable;
}

function coversAny(summary: FaceSummary): boolean {
	for (const codepoint of PROBES) {
		if (summaryCovers(summary, codepoint)) { return true; }
	}
	return false;
}

test "the controls are covered, so the refusals below are not an empty font" {
	const bmp = peeked("controlFormat4.ttf");
	assert bmp.drawable;
	assert summaryCovers(bmp, 0x41);
	assert summaryCovers(bmp, 0x43);
	assert !summaryCovers(bmp, 0x44);
	const full = peeked("controlFormat12.ttf");
	assert full.drawable;
	assert summaryCovers(full, 0x1F600);
	assert summaryCovers(full, 0x1F602);
	assert !summaryCovers(full, 0x1F603);
	const sequences = peeked("controlFormat14.ttf");
	assert summarySequence(sequences, 0x2700, SELECTOR) == SfntSequence.Default;
	assert summarySequence(sequences, 0x2702, SELECTOR) == SfntSequence.Default;
	assert summarySequence(sequences, 0x2703, SELECTOR) == SfntSequence.None;
	assert summarySequence(sequences, 0x1F600, SELECTOR) == SfntSequence.Specific;
}

test "an index subtable that starts outside the cmap is refused, so the face is not drawable" {
	const names: string[] = [
		"offsetNear2G.ttf",
		"offsetNegative.ttf",
		"offsetAtEnd.ttf",
		"offsetLastByte.ttf",
		"truncatedInRecords.ttf",
		"recordCountHuge.ttf",
	];
	for (const name of names) {
		const summary = peeked(name);
		assert !summary.drawable;
		assert !coversAny(summary);
	}
}

test "a subtable whose declared count runs past the cmap covers nothing" {
	const names: string[] = [
		"format4SegcountHuge.ttf",
		"format6CountHuge.ttf",
		"format12GroupsHuge.ttf",
		"truncatedFormat4.ttf",
		"truncatedFormat12.ttf",
	];
	for (const name of names) {
		const summary = peeked(name);
		assert summary.drawable;
		assert !coversAny(summary);
	}
}

test "a variation selector table whose counts or offsets leave the cmap gives no sequence" {
	const names: string[] = ["format14OffsetsOutside.ttf", "format14CountHuge.ttf"];
	for (const name of names) {
		const summary = peeked(name);
		for (const codepoint of [0x2700, 0x1F600, 0x41]) {
			assert summarySequence(summary, codepoint, SELECTOR) == SfntSequence.None;
		}
	}
}

test "a cut-off specific-sequence table is refused while the default table beside it holds" {
	const summary = peeked("truncatedFormat14.ttf");
	assert summarySequence(summary, 0x1F600, SELECTOR) == SfntSequence.None;
	assert summarySequence(summary, 0x2700, SELECTOR) == SfntSequence.Default;
}

test "a table directory entry whose offset and length wrap 32 bits is refused" {
	const r = peekFace(DIR + "directoryWraps.ttf");
	assert !r.ok;
	assert r.error == SfntError.NotAnSfnt;
}

test "a collection whose first font starts outside the file is refused" {
	for (const name of ["collectionOffsetHuge.ttc", "collectionOffsetNegative.ttc"]) {
		const r = peekFace(DIR + name);
		assert !r.ok;
		assert r.error == SfntError.NotAnSfnt;
	}
}
