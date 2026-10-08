import {
	FaceError,
	ColourGlyph,
	loadFace,
	colourBuilt,
	hasColourTables,
	colourTileBox,
} from "../void2d/face";
import {
	GlyphAtlas,
	GlyphKey,
	AtlasError,
	PageKind,
} from "../void2d/glyphAtlas";

test "with the colour module off an Rgba tile is refused by name and no page is made" {
	const key: GlyphKey = {
		kind: PageKind.Rgba, face: 0, glyph: 1, sizePx: 16.0, variant: 0, outline: 0,
	};
	const atlas = GlyphAtlas.create(64, 4);
	defer atlas.dispose();
	const r = atlas.acquireBlank(key, 8, 8, 0, 0);
	assert !r.ok;
	if (!r.ok) { assert r.error == AtlasError.KindNotBuilt; }
	assert atlas.pageCount() == 0;
	assert atlas.residentBytes() == 0;
}

test "with the colour module off a CBDT-only face is not a font and no face holds colour tables" {
	assert !colourBuilt();
	const r = loadFace("tests/fonts/NotoColorEmoji-subset.ttf");
	assert !r.ok;
	if (!r.ok) { assert r.error == FaceError.NotAFont; }
	const outline = try loadFace("assets/font.ttf") catch -1;
	assert outline >= 0;
	assert !hasColourTables(outline);
	assert colourTileBox(outline, 36, 16.0).glyph == ColourGlyph.Absent;
}
