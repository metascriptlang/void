import { loadFace } from "../void2d/face";
import {
	ShapeDirection,
	ShapedGlyph,
	shaperBegin,
	shaperBreak,
	shaperCodepoint,
	shaperCompiled,
	shaperEnd,
	shaperFeature,
	shaperGlyph,
} from "../void2d/shaper";

const INTER: string = "assets/font.ttf";

function interFace(): int32 {
	return try loadFace(INTER) catch -1;
}

function shape(face: int32, text: string, breakAt: int32, off: string): ShapedGlyph[] {
	shaperBegin(face, ShapeDirection.Unknown);
	if (off.length > 0) { shaperFeature(off, 0); }
	for (let i: int32 = 0; i < text.length; i++) {
		if (i == breakAt) { shaperBreak(); }
		shaperCodepoint(text.charCodeAt(i) as int32);
	}
	const n: int32 = shaperEnd();
	const glyphs: ShapedGlyph[] = [];
	for (let k: int32 = 0; k < n; k++) { glyphs.push(shaperGlyph(k)); }
	return glyphs;
}

test "the module flag is the one the bridge is built under" {
	assert shaperCompiled();
}

test "a kerned pair comes back as HarfBuzz shapes it, in font units" {
	const g = shape(interFace(), "AV", -1, "");
	assert g.length == 2;
	assert g[0].glyph == 2 && g[0].advanceX == 1273 && g[0].index == 0;
	assert g[1].glyph == 456 && g[1].advanceX == 1413 && g[1].index == 1;
	assert g[0].offsetX == 0 && g[0].offsetY == 0 && g[0].advanceY == 0;
	assert g[0].direction == ShapeDirection.Ltr;
	assert g[0].codepoint == 0x41;
}

test "a contextual substitution takes two codepoints to one glyph and keeps the first index" {
	const g = shape(interFace(), "->", -1, "");
	assert g.length == 1;
	assert g[0].glyph == 1805 && g[0].advanceX == 1954 && g[0].index == 0;
}

test "turning calt off through a feature gives the glyph per codepoint again" {
	const g = shape(interFace(), "->", -1, "calt");
	assert g.length == 2;
	assert g[0].glyph == 1459 && g[0].advanceX == 942 && g[0].index == 0;
	assert g[1].glyph == 1517 && g[1].advanceX == 1355 && g[1].index == 1;
}

test "a manual break splits the substitution and starts a new run" {
	const g = shape(interFace(), "->", 1, "");
	assert g.length == 2;
	assert g[0].glyph == 1459 && g[0].run == 0;
	assert g[1].glyph == 1517 && g[1].run == 1 && g[1].index == 1;
}

test "a pass leaves nothing behind for the next one" {
	const first = shape(interFace(), "->", 1, "calt");
	assert first.length == 2;
	const second = shape(interFace(), "->", -1, "");
	assert second.length == 1;
	assert second[0].glyph == 1805 && second[0].run == 0;
}
