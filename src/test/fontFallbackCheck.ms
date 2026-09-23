import { loadFace, glyphIndex, glyphAdvance } from "../void2d/face";
import {
	addFallback,
	faceForCodepoint,
	fallbackFacesLoaded,
	fallbackProbes,
} from "../void2d/fontFallback";
import { TextLayout } from "../void2d/textLayout";
import { approx } from "./helpers";

const LATIN: string = "assets/font.ttf";
const CJK: string = "tests/fonts/NotoSansSC-subset.ttf";

function freshPrimary(): int32 {
	return loadFace(LATIN);
}

test "the primary face lacks a hanzi the fallback has" {
	const primary = freshPrimary();
	assert glyphIndex(primary, 0x4F60) == 0;
	const cjk = loadFace(CJK);
	assert cjk >= 0;
	assert glyphIndex(cjk, 0x4F60) != 0;
}

test "a covered codepoint stays on the primary and a miss moves to the fallback" {
	const primary = freshPrimary();
	addFallback(primary, CJK);
	assert faceForCodepoint(primary, "A".code) == primary;
	const face = faceForCodepoint(primary, 0x4F60);
	assert face != primary;
	assert glyphIndex(face, 0x4F60) != 0;
}

test "the fallback face loads on the first real miss, and only once" {
	const primary = freshPrimary();
	addFallback(primary, CJK);
	const before = fallbackFacesLoaded();
	faceForCodepoint(primary, "B".code);
	assert fallbackFacesLoaded() == before;
	faceForCodepoint(primary, 0x597D);
	faceForCodepoint(primary, 0x4E16);
	assert fallbackFacesLoaded() == before + 1;
}

test "a codepoint no face has is resolved once and then cached as a miss" {
	const primary = freshPrimary();
	addFallback(primary, CJK);
	const thai: int32 = 0x0E01;
	assert faceForCodepoint(primary, thai) == primary;
	const probes = fallbackProbes();
	assert faceForCodepoint(primary, thai) == primary;
	assert fallbackProbes() == probes;
}

test "a mixed run takes each glyph from its own face and kerns only within one" {
	const primary = freshPrimary();
	addFallback(primary, CJK);
	const l = TextLayout.layout("A你V", {
		face: primary, size: 13.0, letterSpacing: 0.0, lineSpacing: 0.0, maxWidth: 0.0, align: 0.0,
	});
	const cjk = l.glyphs[1].face;
	assert l.glyphs[0].face == primary;
	assert cjk != primary;
	assert l.glyphs[2].face == primary;
	const aWidth = glyphAdvance(primary, l.glyphs[0].glyph, 13.0);
	assert approx(l.glyphs[1].x, aWidth);
	assert approx(l.glyphs[2].x, aWidth + glyphAdvance(cjk, l.glyphs[1].glyph, 13.0));
}
