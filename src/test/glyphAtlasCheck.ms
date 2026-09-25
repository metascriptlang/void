import {
	loadFace,
	glyphIndex,
	pageTexel,
} from "../void2d/face";
import {
	GlyphAtlas,
	GlyphKey,
	AtlasError,
	quantizeX,
	snapBaseline,
	NO_GLYPH_PAGE,
} from "../void2d/glyphAtlas";

let loadedFace: int32 = -1;

function testFace(): int32 {
	if (loadedFace < 0) { loadedFace = try loadFace("assets/font.ttf") catch -1; }
	return loadedFace;
}

function keyFor(face: int32, codepoint: int32, sizePx: float32, variant: int32): GlyphKey {
	return {
		face: face,
		glyph: glyphIndex(face, codepoint),
		sizePx: sizePx,
		variant: variant,
	};
}

test "x quantizes to the nearest quarter device pixel, split into whole and variant" {
	assert quantizeX(10.0).whole == 10;
	assert quantizeX(10.0).variant == 0;
	assert quantizeX(10.24).whole == 10;
	assert quantizeX(10.24).variant == 1;
	assert quantizeX(10.5).variant == 2;
	assert quantizeX(10.74).variant == 3;
	assert quantizeX(10.875).whole == 11;
	assert quantizeX(10.875).variant == 0;
}

test "a negative device x keeps its variant in range" {
	assert quantizeX(-0.25).whole == -1;
	assert quantizeX(-0.25).variant == 3;
	assert quantizeX(-1.5).whole == -2;
	assert quantizeX(-1.5).variant == 2;
}

test "the baseline lands on the nearest whole device pixel" {
	assert snapBaseline(9.49) == 9;
	assert snapBaseline(9.5) == 10;
	assert snapBaseline(16.25) == 16;
	assert snapBaseline(-0.5) == 0;
}

test "the key separates face, glyph, size and variant" {
	const base: GlyphKey = { face: 0, glyph: 36, sizePx: 16.25, variant: 0 };
	const variant: GlyphKey = { ...base, variant: 1 };
	const larger: GlyphKey = { ...base, sizePx: 16.5 };
	const glyph: GlyphKey = { ...base, glyph: 37 };
	const face: GlyphKey = { ...base, face: 1 };
	const nearbySize: float32 = 16.251;
	const nearby: GlyphKey = { ...base, sizePx: nearbySize };
	assert base.packed() != variant.packed();
	assert base.packed() != larger.packed();
	assert base.packed() != glyph.packed();
	assert base.packed() != face.packed();
	assert base.packed() == nearby.packed();
}

test "one key rasterizes once and is shared by reference" {
	const face = testFace();
	const atlas = GlyphAtlas.create(256, 2);
	const key = keyFor(face, "g".code, 16.25, 1);
	const first = atlas.acquire(key);
	const second = atlas.acquire(key);
	assert first.ok;
	assert second.ok;
	if (first.ok && second.ok) {
		assert first.value == second.value;
		assert atlas.tile(first.value).refs == 2;
	}
	assert atlas.rasterizations == 1;
}

test "a glyph tile holds coverage and its variants are distinct tiles" {
	const face = testFace();
	const atlas = GlyphAtlas.create(256, 2);
	const zero = atlas.acquire(keyFor(face, "H".code, 13.0, 0));
	const three = atlas.acquire(keyFor(face, "H".code, 13.0, 3));
	assert zero.ok;
	assert three.ok;
	if (zero.ok && three.ok) {
		assert zero.value != three.value;
		const t = atlas.tile(zero.value);
		assert t.width > 0;
		assert t.height > 0;
		assert t.top < 0;
		let covered: int32 = 0;
		for (let y = 0; y < t.height; y++) {
			for (let x = 0; x < t.width; x++) {
				if (pageTexel(atlas.pageHandle(t.page), t.x + x, t.y + y) > 0) {
					covered = covered + 1;
				}
			}
		}
		assert covered > 0;
		assert pageTexel(atlas.pageHandle(t.page), t.x + t.width, t.y) == 0;
	}
	assert atlas.rasterizations == 2;
}

test "an empty glyph is cached without a tile on any page" {
	const face = testFace();
	const atlas = GlyphAtlas.create(256, 1);
	const space = atlas.acquire(keyFor(face, " ".code, 13.0, 0));
	assert space.ok;
	if (space.ok) {
		assert atlas.tile(space.value).page == NO_GLYPH_PAGE;
		assert atlas.tile(space.value).width == 0;
	}
	assert atlas.pageCount() == 0;
}

test "a glyph larger than a page is refused, not clipped" {
	const face = testFace();
	const atlas = GlyphAtlas.create(64, 1);
	const huge = atlas.acquire(keyFor(face, "W".code, 200.0, 0));
	assert !huge.ok;
	if (!huge.ok) { assert huge.error == AtlasError.TooLarge; }
}

function fillUntilFull(atlas: GlyphAtlas, face: int32): Vec<int32> {
	const out: Vec<int32> = new Array(0);
	for (let c = "A".code; c <= "Z".code; c++) {
		const r = atlas.acquire(keyFor(face, c, 40.0, 0));
		if (!r.ok) { return out; }
		out.push(r.value);
	}
	return out;
}

test "live tiles keep their page, so a full atlas fails loud" {
	const face = testFace();
	const atlas = GlyphAtlas.create(64, 1);
	const held = fillUntilFull(atlas, face);
	assert (held.length as int32) < 26;
	const next = atlas.acquire(keyFor(face, "Z".code, 41.0, 0));
	assert !next.ok;
	if (!next.ok) { assert next.error == AtlasError.Full; }
	assert atlas.reclaims == 0;
}

test "a page with no live tile is reclaimed whole and bytes stay bounded" {
	const face = testFace();
	const atlas = GlyphAtlas.create(64, 1);
	const held = fillUntilFull(atlas, face);
	const slots = atlas.tileSlots();
	for (const index of held) { atlas.release(index); }
	const next = atlas.acquire(keyFor(face, "Q".code, 41.0, 0));
	assert next.ok;
	assert atlas.reclaims == 1;
	assert atlas.pageCount() == 1;
	assert atlas.residentBytes() == 64 * 64;
	assert atlas.tileSlots() == slots;
	const again = atlas.acquire(keyFor(face, "A".code, 40.0, 0));
	assert again.ok;
	assert atlas.rasterizations == (held.length as int32) + 2;
}

test "a page drawn from in this frame is not reclaimed until the next frame" {
	const face = testFace();
	const atlas = GlyphAtlas.create(64, 1);
	atlas.beginFrame(7);
	const held = fillUntilFull(atlas, face);
	atlas.markDrawn(atlas.tile(held[0]).page);
	for (const index of held) { atlas.release(index); }
	const blocked = atlas.acquire(keyFor(face, "Q".code, 41.0, 0));
	assert !blocked.ok;
	if (!blocked.ok) { assert blocked.error == AtlasError.Full; }
	assert atlas.reclaims == 0;
	atlas.beginFrame(8);
	const next = atlas.acquire(keyFor(face, "Q".code, 41.0, 0));
	assert next.ok;
	assert atlas.reclaims == 1;
}
