import { loadFace, glyphIndex } from "../void2d/face";
import {
	GlyphAtlas,
	GlyphKey,
	AtlasError,
	PageKind,
	OUTLINE_LANE_MAX,
	COVERAGE_OUTLINE_PER_PX,
	SDF_OUTLINE_PER_TEXEL,
	SIZE_QUANTA_MAX,
	maskKey,
} from "../void2d/glyphAtlas";
import {
	outlineLane,
	deviceOutlineWidth,
} from "../void2d/textOutline";

function laneWidth(lane: int32, perUnit: float32): float32 {
	return (lane as float32) / perUnit;
}

function keyOf(kind: PageKind, size: float32, variant: int32, outline: int32): GlyphKey {
	return { kind: kind, face: 3, glyph: 77, sizePx: size, variant: variant, outline: outline };
}

test "the packed key is unique over outline, size, variant and kind" {
	const sizes: float32[] = [8.0, 13.0, 13.015625, 26.0, 1023.0];
	const kinds: PageKind[] = [PageKind.Coverage, PageKind.Rgba];
	let seen: Map<uint64, int32> = new Map<uint64, int32>();
	let count: int32 = 0;
	for (const kind of kinds) {
		for (const size of sizes) {
			for (let variant = 0; variant < 4; variant++) {
				for (let outline = 0; outline <= OUTLINE_LANE_MAX; outline = outline + 5) {
					const packed: uint64 = keyOf(kind, size, variant, outline).packed();
					assert !seen.get(packed).present;
					seen.set(packed, count);
					count = count + 1;
				}
			}
		}
	}
	assert count == 2 * 5 * 4 * 52;
}

test "the outline lane sits above the size and does not move a key without an outline" {
	const plain: GlyphKey = {
		kind: PageKind.Coverage, face: 1, glyph: 36, sizePx: 16.25, variant: 3, outline: 0,
	};
	assert plain.packed() == 0x0001002400041003;
	const nine: GlyphKey = { ...plain, outline: 9 };
	const top: GlyphKey = { ...plain, outline: 255 };
	assert nine.packed() == 0x0001002409041003;
	assert top.packed() == 0x00010024FF041003;
}

test "a size over sixteen bits of quanta is refused before packing" {
	assert keyOf(PageKind.Coverage, 1023.984375, 0, 0).fitsKey();
	assert !keyOf(PageKind.Coverage, 1024.0, 0, 0).fitsKey();
	assert !keyOf(PageKind.Coverage, 1100.0, 0, 0).fitsKey();
	assert !keyOf(PageKind.Coverage, -1.0, 0, 0).fitsKey();
	assert !keyOf(PageKind.Coverage, 16.0, 0, OUTLINE_LANE_MAX + 1).fitsKey();
	assert !keyOf(PageKind.Coverage, 16.0, 0, -1).fitsKey();
	assert keyOf(PageKind.Coverage, 1023.984375, 0, 0).sizeQuanta() == SIZE_QUANTA_MAX;
}

test "an oversize glyph with ink is refused by name and one with none shares an empty tile" {
	const face = try loadFace("assets/font.ttf") catch -1;
	assert face >= 0;
	const atlas = GlyphAtlas.create(1024, 2);
	const ink = keyOf(PageKind.Coverage, 1100.0, 0, 0);
	const huge = atlas.acquire({ ...ink, face: face, glyph: glyphIndex(face, "W".code) });
	assert !huge.ok;
	if (!huge.ok) { assert huge.error == AtlasError.TooLarge; }
	assert !atlas.cached({ ...ink, face: face, glyph: glyphIndex(face, "W".code) });
	assert atlas.tileSlots() == 0;
	const space: GlyphKey = { ...ink, face: face, glyph: glyphIndex(face, " ".code) };
	const first = atlas.acquire(space);
	const second = atlas.acquire(space);
	assert first.ok && second.ok;
	if (first.ok && second.ok) {
		assert first.value == second.value;
		assert atlas.tile(first.value).refs == 2;
		assert atlas.tile(first.value).width == 0;
	}
	assert atlas.tileSlots() == 1;
}

test "releasing the shared empty tile leaves it to be retained again" {
	const face = try loadFace("assets/font.ttf") catch -1;
	assert face >= 0;
	const atlas = GlyphAtlas.create(1024, 2);
	const space: GlyphKey = {
		kind: PageKind.Coverage, face: face, glyph: glyphIndex(face, " ".code),
		sizePx: 1100.0, variant: 0, outline: 0,
	};
	const first = atlas.acquire(space);
	const second = atlas.acquire(space);
	assert first.ok && second.ok;
	if (first.ok && second.ok) {
		atlas.release(first.value);
		atlas.release(second.value);
		assert atlas.tile(first.value).refs == 0;
		atlas.release(second.value);
		assert atlas.tile(first.value).refs == 0;
		const third = atlas.acquire(space);
		assert third.ok;
		if (third.ok) {
			assert third.value == first.value;
			assert atlas.tile(third.value).refs == 1;
		}
	}
	assert atlas.tileSlots() == 1;
}

test "a mask key counts its width in whole units, not in sixty-fourths" {
	assert maskKey(4, 1023, 8).fitsKey();
	assert maskKey(4, 8192, 8192).fitsKey();
	assert maskKey(4, 8192, 8192).packed() != maskKey(4, 8192, 8191).packed();
	assert !maskKey(4, 65536, 8).fitsKey();
}

test "a lane unit is a quarter device pixel for coverage and an eighth texel for a field" {
	assert COVERAGE_OUTLINE_PER_PX == 4.0;
	assert SDF_OUTLINE_PER_TEXEL == 8.0;
	const two = outlineLane(2.0, COVERAGE_OUTLINE_PER_PX);
	assert two.ok;
	if (two.ok) { assert two.value == 8; }
	const half = outlineLane(0.5, SDF_OUTLINE_PER_TEXEL);
	assert half.ok;
	if (half.ok) { assert half.value == 4; }
	assert laneWidth(8, COVERAGE_OUTLINE_PER_PX) == 2.0;
	assert laneWidth(4, SDF_OUTLINE_PER_TEXEL) == 0.5;
}

test "zero stays zero and any other width keeps at least one lane unit" {
	const none = outlineLane(0.0, COVERAGE_OUTLINE_PER_PX);
	assert none.ok;
	if (none.ok) { assert none.value == 0; }
	const hair = outlineLane(0.01, COVERAGE_OUTLINE_PER_PX);
	assert hair.ok;
	if (hair.ok) { assert hair.value == 1; }
}

test "a width past the lane is refused by name at the last quantum" {
	const top = outlineLane(63.75, COVERAGE_OUTLINE_PER_PX);
	assert top.ok;
	if (top.ok) { assert top.value == OUTLINE_LANE_MAX; }
	const over = outlineLane(64.0, COVERAGE_OUTLINE_PER_PX);
	assert !over.ok;
	if (!over.ok) { assert over.error == AtlasError.OutlineTooWide; }
	const field = outlineLane(32.0, SDF_OUTLINE_PER_TEXEL);
	assert !field.ok;
	if (!field.ok) { assert field.error == AtlasError.OutlineTooWide; }
}

test "a pixel-exact outline snaps to whole device pixels with a floor of one" {
	assert deviceOutlineWidth(2.0, 1.25, true) == 3.0;
	assert deviceOutlineWidth(0.4, 1.0, true) == 1.0;
	assert deviceOutlineWidth(0.0, 1.25, true) == 0.0;
	assert deviceOutlineWidth(2.0, 1.25, false) == 2.5;
}
