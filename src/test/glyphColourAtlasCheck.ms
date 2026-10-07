import { loadFace, glyphIndex } from "../void2d/face";
import {
	GlyphAtlas,
	GlyphKey,
	GlyphPage,
	AtlasError,
	PageKind,
} from "../void2d/glyphAtlas";
import {
	void2dGlyphPageBlitRgba,
	void2dGlyphPageTexel,
	void2dGlyphPageTexelRgba,
	void2dGlyphPageBytes,
	void2dGlyphRasterize,
} from "../void2d/glyph.h";

let loadedFace: int32 = -1;

function testFace(): int32 {
	if (loadedFace < 0) { loadedFace = try loadFace("assets/font.ttf") catch -1; }
	return loadedFace;
}

function colourKey(glyph: int32, variant: int32): GlyphKey {
	return { kind: PageKind.Rgba, face: 7, glyph: glyph, sizePx: 16.0, variant: variant };
}

function pagesOfKind(atlas: GlyphAtlas, kind: PageKind): int32 {
	let count: int32 = 0;
	for (let p = 0; p < atlas.pageCount(); p++) {
		if (atlas.pageKind(p as GlyphPage) == kind) { count = count + 1; }
	}
	return count;
}

test "the first Rgba page is allocated lazily and costs four bytes a texel" {
	const atlas = GlyphAtlas.create(64, 4);
	assert atlas.pageCount() == 0;
	assert atlas.residentBytes() == 0;
	const r = atlas.acquireBlank(colourKey(1, 0), 20, 18, 1, -17);
	assert r.ok;
	assert atlas.pageCount() == 1;
	assert pagesOfKind(atlas, PageKind.Rgba) == 1;
	assert atlas.residentBytes() == 64 * 64 * 4;
	if (r.ok) {
		const t = atlas.tile(r.value);
		assert t.width == 20 && t.height == 18;
		assert t.left == 1 && t.top == -17;
		assert void2dGlyphPageBytes(atlas.pageHandle(t.page) as int32) == 64 * 64 * 4;
	}
}

test "coverage and Rgba tiles never share a page and bytes add per kind" {
	const face = testFace();
	const atlas = GlyphAtlas.create(64, 4);
	const colour = atlas.acquireBlank(colourKey(1, 0), 10, 10, 0, -10);
	assert colour.ok;
	const coverage = atlas.acquire({
		kind: PageKind.Coverage,
		face: face,
		glyph: glyphIndex(face, "g".code),
		sizePx: 16.0,
		variant: 0,
	});
	assert coverage.ok;
	assert atlas.pageCount() == 2;
	assert pagesOfKind(atlas, PageKind.Rgba) == 1;
	assert pagesOfKind(atlas, PageKind.Coverage) == 1;
	assert atlas.residentBytes() == 64 * 64 * 5;
	if (colour.ok && coverage.ok) {
		assert atlas.tile(colour.value).page != atlas.tile(coverage.value).page;
	}
}

test "an Rgba key is one tile, shared by reference, with variant zero only" {
	const atlas = GlyphAtlas.create(64, 4);
	const first = atlas.acquireBlank(colourKey(2, 0), 8, 8, 0, -8);
	assert first.ok;
	assert atlas.cached(colourKey(2, 0));
	assert !atlas.cached(colourKey(3, 0));
	const again = atlas.acquireBlank(colourKey(2, 0), 8, 8, 0, -8);
	assert again.ok;
	if (first.ok && again.ok) {
		assert first.value == again.value;
		assert atlas.tile(first.value).refs == 2;
	}
	assert atlas.rasterizations == 1;
	const sub = atlas.acquireBlank(colourKey(2, 1), 8, 8, 0, -8);
	assert !sub.ok;
	if (!sub.ok) { assert sub.error == AtlasError.VariantOutOfRange; }
}

test "a coverage key is refused by acquireBlank and an Rgba key by acquire" {
	const atlas = GlyphAtlas.create(64, 4);
	const wrong = atlas.acquireBlank({
		kind: PageKind.Coverage, face: 0, glyph: 1, sizePx: 16.0, variant: 0,
	}, 8, 8, 0, 0);
	assert !wrong.ok;
	if (!wrong.ok) { assert wrong.error == AtlasError.KindNotBuilt; }
	const viaAcquire = atlas.acquire(colourKey(1, 0));
	assert !viaAcquire.ok;
	if (!viaAcquire.ok) { assert viaAcquire.error == AtlasError.KindNotBuilt; }
	assert atlas.pageCount() == 0;
}

test "a blit lands four channels per texel and reads back packed" {
	const atlas = GlyphAtlas.create(64, 4);
	const r = atlas.acquireBlank(colourKey(1, 0), 2, 2, 0, 0);
	assert r.ok;
	if (!r.ok) { return; }
	const t = atlas.tile(r.value);
	const handle: int32 = atlas.pageHandle(t.page) as int32;
	const source: uint32[] = [0x281E140A, 0x50463C32, 0xFFFFFFFF, 0x01000000];
	assert void2dGlyphPageBlitRgba(handle, t.x, t.y, 2, 2, source[0], 2) == 0;
	assert void2dGlyphPageTexelRgba(handle, t.x, t.y) == 0x281E140A;
	assert void2dGlyphPageTexelRgba(handle, t.x + 1, t.y) == 0x50463C32;
	assert void2dGlyphPageTexelRgba(handle, t.x, t.y + 1) == 0xFFFFFFFF;
	assert void2dGlyphPageTexelRgba(handle, t.x + 1, t.y + 1) == 0x01000000;
	assert void2dGlyphPageTexelRgba(handle, t.x + 2, t.y) == 0;
}

test "a blit outside the page or onto a coverage page is refused by name" {
	const face = testFace();
	const atlas = GlyphAtlas.create(64, 4);
	const r = atlas.acquireBlank(colourKey(1, 0), 4, 4, 0, 0);
	assert r.ok;
	const coverage = atlas.acquire({
		kind: PageKind.Coverage,
		face: face,
		glyph: glyphIndex(face, "g".code),
		sizePx: 16.0,
		variant: 0,
	});
	assert coverage.ok;
	if (!r.ok || !coverage.ok) { return; }
	const source: uint32[] = [0x04030201, 0x04030201];
	const colourHandle: int32 = atlas.pageHandle(atlas.tile(r.value).page) as int32;
	const coverageHandle: int32 = atlas.pageHandle(atlas.tile(coverage.value).page) as int32;
	assert void2dGlyphPageBlitRgba(colourHandle, 63, 0, 2, 1, source[0], 2) == 3;
	assert void2dGlyphPageBlitRgba(coverageHandle, 0, 0, 1, 1, source[0], 1) == 2;
	assert void2dGlyphPageTexel(colourHandle, 0, 0) == -1;
	assert void2dGlyphPageTexelRgba(coverageHandle, 0, 0) == 0;
}

test "a coverage tile aimed at an Rgba page draws nothing" {
	const face = testFace();
	const atlas = GlyphAtlas.create(64, 4);
	const r = atlas.acquireBlank(colourKey(1, 0), 20, 20, 0, 0);
	assert r.ok;
	if (!r.ok) { return; }
	const t = atlas.tile(r.value);
	const handle: int32 = atlas.pageHandle(t.page) as int32;
	void2dGlyphRasterize(face, glyphIndex(face, "g".code), 16.0, 0.0, handle, t.x, t.y, 20, 20);
	for (let y = 0; y < 20; y++) {
		for (let x = 0; x < 20; x++) {
			assert void2dGlyphPageTexelRgba(handle, t.x + x, t.y + y) == 0;
		}
	}
}

test "the pages of one kind are reclaimed without touching the other kind" {
	const atlas = GlyphAtlas.create(64, 1);
	const first = atlas.acquireBlank(colourKey(1, 0), 60, 60, 0, 0);
	assert first.ok;
	const second = atlas.acquireBlank(colourKey(2, 0), 60, 60, 0, 0);
	assert !second.ok;
	if (first.ok) { atlas.release(first.value); }
	const third = atlas.acquireBlank(colourKey(3, 0), 60, 60, 0, 0);
	assert third.ok;
	assert atlas.reclaims == 1;
	assert atlas.pageCount() == 1;
	assert atlas.residentBytes() == 64 * 64 * 4;
}

test "a blit reads each source row at its stride, not at the tile width" {
	const atlas = GlyphAtlas.create(64, 4);
	const r = atlas.acquireBlank(colourKey(1, 0), 2, 2, 0, 0);
	assert r.ok;
	if (!r.ok) { return; }
	const t = atlas.tile(r.value);
	const handle: int32 = atlas.pageHandle(t.page) as int32;
	const source: uint32[] = [0x11111111, 0x22222222, 0xEEEEEEEE, 0x33333333, 0x44444444, 0xEEEEEEEE];
	assert void2dGlyphPageBlitRgba(handle, t.x, t.y, 2, 2, source[0], 3) == 0;
	assert void2dGlyphPageTexelRgba(handle, t.x, t.y) == 0x11111111;
	assert void2dGlyphPageTexelRgba(handle, t.x + 1, t.y) == 0x22222222;
	assert void2dGlyphPageTexelRgba(handle, t.x, t.y + 1) == 0x33333333;
	assert void2dGlyphPageTexelRgba(handle, t.x + 1, t.y + 1) == 0x44444444;
	assert void2dGlyphPageBlitRgba(handle, t.x, t.y, 2, 2, source[0], 1) == 1;
}

test "a reclaimed Rgba page is cleared in all four bytes of every texel" {
	const atlas = GlyphAtlas.create(64, 1);
	const first = atlas.acquireBlank(colourKey(1, 0), 60, 60, 0, 0);
	assert first.ok;
	if (!first.ok) { return; }
	const t = atlas.tile(first.value);
	const handle: int32 = atlas.pageHandle(t.page) as int32;
	const source: uint32[] = [0xFFFFFFFF, 0xFFFFFFFF];
	assert void2dGlyphPageBlitRgba(handle, 0, 5, 2, 1, source[0], 2) == 0;
	assert void2dGlyphPageBlitRgba(handle, 62, 63, 1, 1, source[0], 1) == 0;
	assert void2dGlyphPageBlitRgba(handle, 0, 40, 2, 1, source[0], 2) == 0;
	atlas.release(first.value);
	const second = atlas.acquireBlank(colourKey(2, 0), 60, 60, 0, 0);
	assert second.ok;
	assert atlas.reclaims == 1;
	assert void2dGlyphPageTexelRgba(handle, 0, 5) == 0;
	assert void2dGlyphPageTexelRgba(handle, 0, 40) == 0;
	assert void2dGlyphPageTexelRgba(handle, 1, 40) == 0;
	assert void2dGlyphPageTexelRgba(handle, 62, 63) == 0;
}

test "a tile whose fill was refused is discarded and its key is not cached" {
	const atlas = GlyphAtlas.create(64, 4);
	const key = colourKey(1, 0);
	const first = atlas.acquireBlank(key, 8, 8, 0, -8);
	assert first.ok;
	assert atlas.cached(key);
	assert atlas.rasterizations == 1;
	if (!first.ok) { return; }
	atlas.discard(first.value);
	assert !atlas.cached(key);
	assert atlas.rasterizations == 0;
	const again = atlas.acquireBlank(key, 8, 8, 0, -8);
	assert again.ok;
	if (again.ok) {
		assert again.value == first.value;
		assert atlas.tile(again.value).refs == 1;
	}
	assert atlas.rasterizations == 1;
}

test "discarding a tile another holder shares only drops one reference" {
	const atlas = GlyphAtlas.create(64, 4);
	const key = colourKey(1, 0);
	const first = atlas.acquireBlank(key, 8, 8, 0, -8);
	const second = atlas.acquireBlank(key, 8, 8, 0, -8);
	assert first.ok && second.ok;
	if (!first.ok) { return; }
	atlas.discard(first.value);
	assert atlas.cached(key);
	assert atlas.tile(first.value).refs == 1;
	assert atlas.rasterizations == 1;
}
