import { glyphIndex, glyphInkBox } from "../void2d/face";
import { glyphBox } from "../void2d/glyphBoxes";
import {
	Font,
	FontFeature,
	FontId,
	FontStyle,
	SizeAdjust,
	fontFace,
	registerFace,
	resolveFont,
} from "../void2d/font";
import {
	SHAPE_CACHE_BUCKETS,
	SHAPE_CACHE_BUCKET_SIZE,
	ShapeKey,
	ShapedRun,
	shapeCacheGet,
	shapeCacheHits,
	shapeCachePut,
	shapeKeyHash,
} from "../void2d/shapeCache";
import { ShapeDirection } from "../void2d/shaper";
import { Align, TextLayout, TextStyle } from "../void2d/textLayout";
import { holdFontFile } from "./fontFile";
import { laid } from "./layoutHelpers";

const FIXTURE: string = "tests/fonts/shapeFixture.ttf";
const F: int32 = 0x66;

let familyCount: int32 = 0;

function fixture(features: FontFeature[]): FontId {
	familyCount = familyCount + 1;
	const family: string = `shape cache ${familyCount}`;
	holdFontFile(FIXTURE);
	registerFace(FIXTURE, family, 400, FontStyle.Normal);
	const fallbacks: string[] = [];
	const font: Font = {
		family: family, weight: 400, style: FontStyle.Normal, features: features,
		fallbacks: fallbacks, sizeAdjust: SizeAdjust.None,
	};
	const resolved = resolveFont(font);
	if (!resolved.ok) {
		console.log(`shape cache check: ${FIXTURE} did not resolve`);
		unreachable;
	}
	return resolved.value;
}

function layoutOf(font: FontId, text: string, spacing: float32): TextLayout {
	const style: TextStyle = {
		font: font, size: 10.0, letterSpacing: spacing, lineSpacing: 0.0, maxWidth: 0.0,
		align: Align.Left,
	};
	return laid(text, style);
}

function sameGlyphs(a: TextLayout, b: TextLayout): boolean {
	if (a.glyphs.length != b.glyphs.length) { return false; }
	for (let i = 0; i < (a.glyphs.length as int32); i++) {
		if (a.glyphs[i].glyph != b.glyphs[i].glyph || a.glyphs[i].x != b.glyphs[i].x) {
			return false;
		}
	}
	return true;
}

function keyOf(face: int32, values: int32[]): ShapeKey {
	let input: Vec<int32> = new Array(0);
	for (const v of values) { input.push(v); }
	return { face: face, direction: ShapeDirection.Ltr, features: new Array(0), input: input };
}

function glyphsOf(glyph: int32): ShapedRun {
	const run: ShapedRun = new ShapedRun();
	run.glyphs.push({
		glyph: glyph, advanceX: 1, advanceY: 0, offsetX: 0, offsetY: 0, index: 0, codepoint: 0,
		direction: ShapeDirection.Ltr, run: 0,
	});
	return run;
}

function bucket(key: ShapeKey): int64 {
	return shapeKeyHash(key) % (SHAPE_CACHE_BUCKETS as int64);
}

test "a run shaped again comes from the cache with the same glyphs" {
	const font = fixture([]);
	const before: int32 = shapeCacheHits();
	const first = layoutOf(font, "fi fi", 0.0);
	const second = layoutOf(font, "fi fi", 0.0);
	assert shapeCacheHits() > before;
	assert sameGlyphs(first, second);
	assert first.glyphs[0].glyph != glyphIndex(fontFace(font), F);
}

test "the same text with a feature turned off is shaped apart" {
	const ligated = layoutOf(fixture([]), "fi", 0.0);
	const off: FontFeature[] = [{ tag: "liga", value: 0 }];
	const font = fixture(off);
	const plain = layoutOf(font, "fi", 0.0);
	assert ligated.glyphs[0].glyph != glyphIndex(fontFace(font), F);
	assert plain.glyphs[0].glyph == glyphIndex(fontFace(font), F);
}

test "letter spacing that turns the optional ligatures off is shaped apart" {
	const font = fixture([]);
	const tight = layoutOf(font, "fi", 0.0);
	const spaced = layoutOf(font, "fi", 1.0);
	assert tight.glyphs[0].glyph != glyphIndex(fontFace(font), F);
	assert spaced.glyphs[0].glyph == glyphIndex(fontFace(font), F);
}

test "an entry with the same hash and another key is not returned" {
	const key = keyOf(-7, [1, 2, 3]);
	const hash = shapeKeyHash(key);
	shapeCachePut(key, hash, glyphsOf(5));
	assert shapeCacheGet(keyOf(-7, [1, 2, 4]), hash) == null;
	assert shapeCacheGet(keyOf(-8, [1, 2, 3]), hash) == null;
	const found = shapeCacheGet(key, hash);
	assert found != null && found.glyphs[0].glyph == 5;
}

test "a full bucket drops its least recently used run" {
	let keys: Vec<ShapeKey> = new Array(0);
	const target: int64 = bucket(keyOf(-9, [0]));
	for (let v = 0; (keys.length as int32) <= SHAPE_CACHE_BUCKET_SIZE; v++) {
		const key = keyOf(-9, [v]);
		if (bucket(key) == target) { keys.push(key); }
	}
	for (let i = 0; i < SHAPE_CACHE_BUCKET_SIZE; i++) {
		shapeCachePut(keys[i], shapeKeyHash(keys[i]), glyphsOf(i));
	}
	assert shapeCacheGet(keys[0], shapeKeyHash(keys[0])) != null;
	const last = SHAPE_CACHE_BUCKET_SIZE;
	shapeCachePut(keys[last], shapeKeyHash(keys[last]), glyphsOf(last));
	assert shapeCacheGet(keys[0], shapeKeyHash(keys[0])) != null;
	assert shapeCacheGet(keys[1], shapeKeyHash(keys[1])) == null;
	assert shapeCacheGet(keys[last], shapeKeyHash(keys[last])) != null;
}

test "an ink box read again, after other sizes took its slot, is the rasterizer's box" {
	const face: int32 = fontFace(fixture([]));
	const glyph: int32 = glyphIndex(face, F);
	for (let round = 0; round < 2; round++) {
		for (let size = 1; size <= 3000; size++) {
			const want = glyphBox(face, glyph, size as float32, 0.0);
			const [left, top, right, bottom] = glyphInkBox(face, glyph, size as float32);
			assert left == (want[0] as float32) && top == (want[1] as float32) &&
				right == (want[2] as float32) && bottom == (want[3] as float32);
		}
	}
}
