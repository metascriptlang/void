import "../void2d/textSdfSwitch";
import {
	void2dGlyphBox,
	void2dGlyphSdfBox,
	void2dGlyphSdfRasterize,
	void2dGlyphSdfGenerations,
	void2dGlyphSdfStbDiff,
	void2dGlyphPageCreate,
	void2dGlyphPageTexel,
} from "../void2d/glyph.h";
import { loadFace, syntheticFace, glyphIndex } from "../void2d/face";
import { SDF_EDGE, SDF_PAD } from "../void2d/textSdf";

const SDF_PAGE_KIND: int32 = 1;
const PAGE_SIZE: int32 = 1024;
const CELL: int32 = 64;
const COLUMNS: int32 = 16;

let page: int32 = -1;
let nextCell: int32 = 0;
let plainFace: int32 = -1;
let cjkFace: int32 = -1;

function sdfPage(): int32 {
	if (page < 0) { page = void2dGlyphPageCreate(PAGE_SIZE, SDF_PAGE_KIND); }
	return page;
}

function plain(): int32 {
	if (plainFace < 0) { plainFace = try loadFace("assets/font.ttf") catch -1; }
	return plainFace;
}

function cjk(): int32 {
	if (cjkFace < 0) { cjkFace = try loadFace("tests/fonts/NotoSansSC-subset.ttf") catch -1; }
	return cjkFace;
}

struct Tile {
	x: int32;
	y: int32;
	w: int32;
	h: int32;
	left: int32;
	top: int32;
}

const EMPTY_TILE: Tile = { x: 0, y: 0, w: 0, h: 0, left: 0, top: 0 };

function generate(face: int32, glyph: int32): Tile {
	const box: Ptr<int32> = void2dGlyphSdfBox(face, glyph);
	const w: int32 = box[2] - box[0];
	const h: int32 = box[3] - box[1];
	if (w <= 0 || h <= 0) { return EMPTY_TILE; }
	const cell: int32 = nextCell;
	nextCell = nextCell + 1;
	const x: int32 = (cell % COLUMNS) * CELL;
	const y: int32 = (cell / COLUMNS) * CELL;
	void2dGlyphSdfRasterize(face, glyph, sdfPage(), x, y, w, h);
	return { x: x, y: y, w: w, h: h, left: box[0], top: box[1] };
}

function texel(t: Tile, col: int32, row: int32): int32 {
	return void2dGlyphPageTexel(sdfPage(), t.x + col, t.y + row);
}

function insideTexels(t: Tile): int32 {
	let count: int32 = 0;
	for (let row = 0; row < t.h; row++) {
		for (let col = 0; col < t.w; col++) {
			if (texel(t, col, row) > SDF_EDGE) { count = count + 1; }
		}
	}
	return count;
}

function centroidX(t: Tile, rowFrom: int32, rowTo: int32): float32 {
	let sum: float32 = 0.0;
	let count: int32 = 0;
	for (let row = rowFrom; row < rowTo; row++) {
		for (let col = 0; col < t.w; col++) {
			if (texel(t, col, row) > SDF_EDGE) {
				sum = sum + ((t.left + col) as float32);
				count = count + 1;
			}
		}
	}
	return count > 0 ? sum / (count as float32) : 0.0;
}

test "the port is byte for byte stbtt_GetGlyphSDF on 95 ASCII glyphs of a plain face" {
	const face = plain();
	let compared: int32 = 0;
	for (let codepoint = 32; codepoint < 127; codepoint++) {
		const glyph: int32 = glyphIndex(face, codepoint);
		const t = generate(face, glyph);
		if (t.w == 0) { continue; }
		compared = compared + 1;
		assert void2dGlyphSdfStbDiff(face, glyph, sdfPage(), t.x, t.y) == 0;
	}
	assert compared == 94;
}

test "the port is byte for byte stbtt_GetGlyphSDF on 40 CJK glyphs of a plain face" {
	const face = cjk();
	let compared: int32 = 0;
	for (let codepoint = 0x4e00; codepoint < 0xa000 && compared < 40; codepoint++) {
		const glyph: int32 = glyphIndex(face, codepoint);
		if (glyph == 0) { continue; }
		const t = generate(face, glyph);
		if (t.w == 0) { continue; }
		compared = compared + 1;
		assert void2dGlyphSdfStbDiff(face, glyph, sdfPage(), t.x, t.y) == 0;
	}
	assert compared == 40;
}

test "the box is the coverage box at 32 px per em with the pad on every side" {
	const face = plain();
	for (const codepoint of ["I".code, "g".code, "W".code, "@".code]) {
		const glyph: int32 = glyphIndex(face, codepoint);
		const coverage: Ptr<int32> = void2dGlyphBox(face, glyph, 32.0, 0.0);
		const left: int32 = coverage[0];
		const top: int32 = coverage[1];
		const right: int32 = coverage[2];
		const bottom: int32 = coverage[3];
		const box: Ptr<int32> = void2dGlyphSdfBox(face, glyph);
		assert box[0] == left - SDF_PAD;
		assert box[1] == top - SDF_PAD;
		assert box[2] == right + SDF_PAD;
		assert box[3] == bottom + SDF_PAD;
		assert box[4] == 0;
	}
}

test "a space has no tile and nothing is generated for it" {
	const face = plain();
	const before: uint32 = void2dGlyphSdfGenerations();
	const box: Ptr<int32> = void2dGlyphSdfBox(face, glyphIndex(face, " ".code));
	assert box[0] == 0 && box[1] == 0 && box[2] == 0 && box[3] == 0 && box[4] == 0;
	assert void2dGlyphSdfGenerations() == before;
}

test "each generated glyph counts once toward the generation budget" {
	const face = plain();
	const before: uint32 = void2dGlyphSdfGenerations();
	generate(face, glyphIndex(face, "a".code));
	generate(face, glyphIndex(face, "b".code));
	generate(face, glyphIndex(face, " ".code));
	assert void2dGlyphSdfGenerations() == before + 2;
}

test "the field is inside the outline above the edge byte and outside below it" {
	const face = plain();
	const t = generate(face, glyphIndex(face, "I".code));
	assert t.w > 0;
	assert texel(t, 0, 0) < SDF_EDGE;
	assert texel(t, t.w - 1, t.h - 1) < SDF_EDGE;
	assert texel(t, t.w / 2, t.h / 2) > SDF_EDGE;
	assert texel(t, 0, t.h / 2) < SDF_EDGE;
}

test "a synthetic bold face is a heavier field than the plain face it came from" {
	const face = plain();
	const bold = try syntheticFace(face, true, false) catch -1;
	assert bold >= 0;
	const regular = generate(face, glyphIndex(face, "I".code));
	const heavy = generate(bold, glyphIndex(bold, "I".code));
	assert heavy.w > regular.w;
	assert insideTexels(heavy) > insideTexels(regular);
	assert texel(heavy, heavy.w / 2, heavy.h / 2) > SDF_EDGE;
	assert texel(heavy, 0, 0) < SDF_EDGE;
}

test "a synthetic italic face leans the field to the right as it rises" {
	const face = plain();
	const italic = try syntheticFace(face, false, true) catch -1;
	assert italic >= 0;
	const upright = generate(face, glyphIndex(face, "I".code));
	const leaning = generate(italic, glyphIndex(italic, "I".code));
	const uprightLean: float32 = centroidX(upright, 0, upright.h / 2) -
		centroidX(upright, upright.h / 2, upright.h);
	const leaningLean: float32 = centroidX(leaning, 0, leaning.h / 2) -
		centroidX(leaning, leaning.h / 2, leaning.h);
	assert uprightLean > -0.5 && uprightLean < 0.5;
	assert leaningLean > uprightLean + 1.0;
}

test "a synthetic face has no stb reference to compare against" {
	const face = plain();
	const bold = try syntheticFace(face, true, false) catch -1;
	const glyph: int32 = glyphIndex(bold, "I".code);
	const t = generate(bold, glyph);
	assert void2dGlyphSdfStbDiff(bold, glyph, sdfPage(), t.x, t.y) == -2;
}
