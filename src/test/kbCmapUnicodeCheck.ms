import { glyphIndex, loadFace } from "../void2d/face";
import { ShapeDirection, shaperBegin, shaperCodepoint, shaperEnd, shaperGlyph } from "../void2d/shaper";

const FIXTURE: string = "tests/fonts/cmap/unicodeThenMacRoman.ttf";

function shapedGlyph(face: int32, codepoint: int32): int32 {
	shaperBegin(face, ShapeDirection.Unknown);
	shaperCodepoint(codepoint);
	const n: int32 = shaperEnd();
	if (n != 1) { return -1; }
	return shaperGlyph(0).glyph;
}

test "a Unicode subtable ahead of a Mac Roman one is the shaper's cmap, as the stb reader chooses" {
	const face: int32 = try loadFace(FIXTURE) catch -1;
	assert face >= 0;
	assert glyphIndex(face, 0x273B) == 1;
	assert shapedGlyph(face, 0x273B) == glyphIndex(face, 0x273B);
	assert shapedGlyph(face, 0x41) == glyphIndex(face, 0x41);
}
