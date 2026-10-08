import { loadFace, glyphIndex } from "../void2d/face";
import { GlyphAtlas, GlyphKey, PageKind } from "../void2d/glyphAtlas";
import {
	void2dGlyphPageCreate,
	void2dGlyphPageGeneration,
	void2dGlyphPageLiveCount,
	void2dGlyphPageRelease,
	void2dGlyphPageSize,
} from "../void2d/glyph.h";

const RENDERER_PAGE_VIEWS: int32 = 64;

function keyFor(face: int32, sizePx: float32): GlyphKey {
	return {
		kind: PageKind.Coverage, face: face, glyph: glyphIndex(face, "g".code), sizePx: sizePx,
		variant: 0, outline: 0,
	};
}

test "an atlas disposed returns its pages, so more atlases than page slots never refuse" {
	const face: int32 = try loadFace("assets/font.ttf") catch -1;
	assert face >= 0;
	const before: int32 = void2dGlyphPageLiveCount();
	for (let n = 0; n < RENDERER_PAGE_VIEWS * 3; n++) {
		const atlas = GlyphAtlas.create(64, 1);
		assert atlas.acquire(keyFor(face, 16.0)).ok;
		assert atlas.pageCount() == 1;
		assert void2dGlyphPageLiveCount() == before + 1;
		atlas.dispose();
		assert void2dGlyphPageLiveCount() == before;
	}
}

test "a released page handle is reused with a new generation and refused a second release" {
	const first: int32 = void2dGlyphPageCreate(64, PageKind.Coverage as int32);
	assert first >= 0;
	const made: uint32 = void2dGlyphPageGeneration(first);
	assert made != 0;
	assert void2dGlyphPageRelease(first) == 0;
	assert void2dGlyphPageGeneration(first) == 0;
	assert void2dGlyphPageRelease(first) == -1;
	const again: int32 = void2dGlyphPageCreate(128, PageKind.Coverage as int32);
	assert again == first;
	assert void2dGlyphPageGeneration(again) != made;
	assert void2dGlyphPageSize(again) == 128;
	assert void2dGlyphPageRelease(again) == 0;
}
