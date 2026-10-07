import { loadFace, glyphIndex } from "../void2d/face";
import {
	GlyphAtlas,
	GlyphKey,
	GlyphTile,
	GlyphPage,
	AtlasError,
	PageKind,
	NO_GLYPH_PAGE,
	acquireSdf,
	sdfKey,
} from "../void2d/glyphAtlas";
import { void2dGlyphSdfGenerations } from "../void2d/glyph.h";

let loadedFace: int32 = -1;

function testFace(): int32 {
	if (loadedFace < 0) { loadedFace = try loadFace("assets/font.ttf") catch -1; }
	return loadedFace;
}

function pagesOfKind(atlas: GlyphAtlas, kind: PageKind): int32 {
	let count: int32 = 0;
	for (let p = 0; p < atlas.pageCount(); p++) {
		if (atlas.pageKind(p as GlyphPage) == kind) { count = count + 1; }
	}
	return count;
}

test "the SDF key carries no size and no variant" {
	const key = sdfKey(1, 36);
	assert key.sizePx == 0.0;
	assert key.variant == 0;
	const coverage: GlyphKey = {
		kind: PageKind.Coverage, face: 1, glyph: 36, sizePx: 0.0, variant: 0,
	};
	assert key.packed() != coverage.packed();
	assert key.packed() == 0x0001002400000010;
}

test "one glyph acquired at sixty-four zooms is one tile and one generation" {
	const face = testFace();
	const atlas = GlyphAtlas.create(256, 4);
	const glyph: int32 = glyphIndex(face, "g".code);
	const before: uint32 = void2dGlyphSdfGenerations();
	let first: int32 = -1;
	for (let zoom = 0; zoom < 64; zoom++) {
		const r = atlas.acquireSdf(face, glyph);
		assert r.ok;
		if (r.ok) {
			if (first < 0) { first = r.value; }
			assert r.value == first;
		}
	}
	assert atlas.generations == 1;
	assert atlas.rasterizations == 0;
	assert void2dGlyphSdfGenerations() == before + 1;
	assert atlas.tileSlots() == 1;
	assert atlas.tile(first).refs == 64;
	for (let i = 0; i < 64; i++) { atlas.release(first); }
	assert atlas.tile(first).refs == 0;
}

test "an SDF tile lands on an SDF page, padded, with its box origin kept" {
	const face = testFace();
	const atlas = GlyphAtlas.create(256, 4);
	const r = atlas.acquireSdf(face, glyphIndex(face, "I".code));
	assert r.ok;
	if (r.ok) {
		const t: GlyphTile = atlas.tile(r.value);
		assert atlas.pageKind(t.page) == PageKind.Sdf;
		assert t.width > 8 && t.height > 8;
		assert t.left < 0 && t.top < 0;
	}
	assert pagesOfKind(atlas, PageKind.Coverage) == 0;
	assert pagesOfKind(atlas, PageKind.Sdf) == 1;
}

test "a space has a tile with no page and costs no generation" {
	const face = testFace();
	const atlas = GlyphAtlas.create(256, 4);
	const r = atlas.acquireSdf(face, glyphIndex(face, " ".code));
	assert r.ok;
	if (r.ok) {
		const t: GlyphTile = atlas.tile(r.value);
		assert t.page == NO_GLYPH_PAGE;
		assert t.width == 0 && t.height == 0;
	}
	assert atlas.generations == 0;
	assert atlas.pageCount() == 0;
}

test "a coverage zoom sweep adds no SDF page and an SDF glyph adds no coverage tile" {
	const face = testFace();
	const atlas = GlyphAtlas.create(512, 8);
	const glyph: int32 = glyphIndex(face, "g".code);
	const sdf = atlas.acquireSdf(face, glyph);
	assert sdf.ok;
	for (let step = 0; step < 32; step++) {
		const r = atlas.acquire({
			kind: PageKind.Coverage,
			face: face,
			glyph: glyph,
			sizePx: 8.0 + (step as float32) * 2.0,
			variant: 0,
		});
		assert r.ok;
	}
	assert atlas.generations == 1;
	assert atlas.rasterizations == 32;
	assert pagesOfKind(atlas, PageKind.Sdf) == 1;
	assert pagesOfKind(atlas, PageKind.Coverage) >= 1;
}

test "SDF pages and coverage pages reclaim independently" {
	const face = testFace();
	const atlas = GlyphAtlas.create(64, 2);
	const coverage = atlas.acquire({
		kind: PageKind.Coverage,
		face: face,
		glyph: glyphIndex(face, "g".code),
		sizePx: 16.0,
		variant: 0,
	});
	assert coverage.ok;
	let held: Vec<int32> = new Array(0);
	let full: boolean = false;
	let refused: int32 = -1;
	for (let codepoint = 33; codepoint < 127 && !full; codepoint++) {
		const glyph: int32 = glyphIndex(face, codepoint);
		const r = atlas.acquireSdf(face, glyph);
		if (r.ok) {
			held.push(r.value);
		} else {
			full = true;
			refused = glyph;
			assert r.error == AtlasError.Full;
		}
	}
	assert full;
	assert atlas.reclaims == 0;
	for (const index of held) { atlas.release(index); }
	const again = atlas.acquireSdf(face, refused);
	assert again.ok;
	assert atlas.reclaims == 1;
	assert pagesOfKind(atlas, PageKind.Sdf) == 1;
	if (coverage.ok) {
		assert atlas.tile(coverage.value).refs == 1;
		assert atlas.tile(coverage.value).page != NO_GLYPH_PAGE;
		assert atlas.pageKind(atlas.tile(coverage.value).page) == PageKind.Coverage;
	}
}

test "a generic acquire still refuses an SDF key by name" {
	const atlas = GlyphAtlas.create(64, 2);
	const r = atlas.acquire(sdfKey(0, 36));
	assert !r.ok;
	if (!r.ok) { assert r.error == AtlasError.KindNotBuilt; }
}
