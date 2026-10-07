import {
	GlyphAtlas,
	GlyphKey,
	AtlasError,
	PageKind,
} from "../void2d/glyphAtlas";

test "with the colour module off an Rgba tile is refused by name and no page is made" {
	const key: GlyphKey = { kind: PageKind.Rgba, face: 0, glyph: 1, sizePx: 16.0, variant: 0 };
	const atlas = GlyphAtlas.create(64, 4);
	const r = atlas.acquireBlank(key, 8, 8, 0, 0);
	assert !r.ok;
	if (!r.ok) { assert r.error == AtlasError.KindNotBuilt; }
	assert atlas.pageCount() == 0;
	assert atlas.residentBytes() == 0;
}
