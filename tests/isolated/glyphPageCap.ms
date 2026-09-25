// Run in a process of its own (scripts/gate.sh): it exhausts glyph.c's process-wide page table,
// which would starve every test that ran after it in src/test/index.ms.

import { loadFace, glyphIndex } from "../../src/void2d/face";
import { GlyphAtlas, AtlasError, NO_GLYPH_PAGE_HANDLE } from "../../src/void2d/glyphAtlas";

const RENDERER_PAGE_VIEWS: int32 = 64;

test "the renderer binds at most 64 glyph pages, and an atlas refused one fails loud" {
	let made: int32 = 0;
	for (let i = 0; i < RENDERER_PAGE_VIEWS + 4; i++) {
		const atlas = GlyphAtlas.create(8, 1);
		if (atlas.ensurePage() != NO_GLYPH_PAGE_HANDLE) { made = made + 1; }
	}
	assert made == RENDERER_PAGE_VIEWS;
	const face: int32 = try loadFace("assets/font.ttf") catch -1;
	const late = GlyphAtlas.create(64, 4);
	const r = late.acquire({
		face: face,
		glyph: glyphIndex(face, "H".code),
		sizePx: 13.0,
		variant: 0,
	});
	assert !r.ok;
	if (!r.ok) { assert r.error == AtlasError.Full; }
	assert late.pageCount() == 0;
}
