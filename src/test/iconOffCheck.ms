import { AtlasError, GlyphAtlas, PageKind, maskKey } from "../void2d/glyphAtlas";

test "with the SVG module off a mask tile is refused by name and no page is made" {
	const atlas = GlyphAtlas.create(64, 4);
	defer atlas.dispose();
	const alpha: Vec<uint8> = [255, 255, 255, 255];
	const r = atlas.acquireMask(maskKey(1, 2, 2), 2, 2, alpha);
	assert !r.ok;
	if (!r.ok) { assert r.error == AtlasError.KindNotBuilt; }
	assert atlas.pageCount() == 0;
	assert atlas.residentBytes() == 0;
	assert maskKey(1, 2, 2).kind == PageKind.Mask;
}
