import "../void2d/textOutlineSwitch";
import {
	void2dGlyphBox,
	void2dGlyphOutlineBox,
	void2dGlyphOutlineGenerations,
} from "../void2d/glyph.h";

when (voidSdfText) {
	import { void2dGlyphSdfBox, void2dGlyphSdfOutlineBox } from "../void2d/glyph.h";
	import { acquireSdf, acquireSdfOutline, SDF_OUTLINE_PER_TEXEL } from "../void2d/glyphAtlas";
	import { SDF_EM, SDF_EDGE } from "../void2d/textSdf";
}
import { loadFace, glyphIndex, pageTexel } from "../void2d/face";
import {
	GlyphAtlas,
	GlyphKey,
	GlyphTile,
	AtlasError,
	PageKind,
	COVERAGE_OUTLINE_PER_PX,
	acquireOutline,
} from "../void2d/glyphAtlas";

const UNITS: float32 = 2048.0;
const STEM_LEFT: float32 = 180.0;
const STEM_RIGHT: float32 = 370.0;
const STEM_TOP: float32 = 1490.0;

let loadedFace: int32 = -1;
let cffFace: int32 = -1;

function testFace(): int32 {
	if (loadedFace < 0) { loadedFace = try loadFace("assets/font.ttf") catch -1; }
	return loadedFace;
}

function cubicFace(): int32 {
	if (cffFace < 0) { cffFace = try loadFace("tests/fonts/cffSynthetic.otf") catch -1; }
	return cffFace;
}

function keyOf(face: int32, glyph: int32, size: float32, variant: int32, lane: int32): GlyphKey {
	return {
		kind: PageKind.Coverage, face: face, glyph: glyph, sizePx: size, variant: variant,
		outline: lane,
	};
}

function laneOf(widthPx: float32): int32 {
	return Math.floor(widthPx * COVERAGE_OUTLINE_PER_PX + 0.5) as int32;
}

function texel(atlas: GlyphAtlas, t: GlyphTile, col: int32, row: int32): int32 {
	return pageTexel(atlas.pageHandle(t.page), t.x + col, t.y + row);
}

function stemDistance(cx: float32, cy: float32, scale: float32): float32 {
	const x0: float32 = STEM_LEFT * scale;
	const x1: float32 = STEM_RIGHT * scale;
	const y0: float32 = -STEM_TOP * scale;
	const y1: float32 = 0.0;
	const dx: float32 = Math.max(Math.max(x0 - cx, cx - x1), 0.0) as float32;
	const dy: float32 = Math.max(Math.max(y0 - cy, cy - y1), 0.0) as float32;
	if (dx > 0.0 || dy > 0.0) { return -(Math.sqrt(dx * dx + dy * dy) as float32); }
	const across: float32 = Math.min(cx - x0, x1 - cx) as float32;
	const along: float32 = Math.min(cy - y0, y1 - cy) as float32;
	return Math.min(across, along) as float32;
}

function expectedTexel(distance: float32, width: float32): int32 {
	const covered: float32 = 0.5 + distance + width;
	if (covered <= 0.0) { return 0; }
	if (covered >= 1.0) { return 255; }
	return Math.floor(covered * 255.0 + 0.5) as int32;
}

function worstStemError(size: float32, variant: int32, widthPx: float32): int32 {
	const face = testFace();
	const atlas = GlyphAtlas.create(1024, 2);
	defer atlas.dispose();
	const lane: int32 = laneOf(widthPx);
	const r = atlas.acquireOutline(keyOf(face, glyphIndex(face, "I".code), size, variant, lane));
	let worst: int32 = 255;
	if (r.ok) {
		worst = 0;
		const t: GlyphTile = atlas.tile(r.value);
		const scale: float32 = size / UNITS;
		const shift: float32 = (variant as float32) / 4.0;
		const width: float32 = (lane as float32) / COVERAGE_OUTLINE_PER_PX;
		for (let row = 0; row < t.height; row++) {
			for (let col = 0; col < t.width; col++) {
				const cx: float32 = ((t.left + col) as float32) + 0.5 - shift;
				const cy: float32 = ((t.top + row) as float32) + 0.5;
				const want: int32 = expectedTexel(stemDistance(cx, cy, scale), width);
				const got: int32 = texel(atlas, t, col, row);
				const off: int32 = got > want ? got - want : want - got;
				if (off > worst) { worst = off; }
			}
		}
	}
	return worst;
}

test "the outline box is the fill box grown by ceil(width) + 1 on every side" {
	const face = testFace();
	const sizes: float32[] = [13.0, 26.0];
	const widths: float32[] = [0.5, 1.0, 2.0, 3.5];
	let compared: int32 = 0;
	for (const codepoint of ["I".code, "g".code, "W".code, "@".code]) {
		const glyph: int32 = glyphIndex(face, codepoint);
		for (const size of sizes) {
			for (let variant = 0; variant < 4; variant++) {
				const shift: float32 = (variant as float32) / 4.0;
				const fill = void2dGlyphBox(face, glyph, size, shift);
				const fx0: int32 = fill[0];
				const fy0: int32 = fill[1];
				const fx1: int32 = fill[2];
				const fy1: int32 = fill[3];
				for (const width of widths) {
					const outline = void2dGlyphOutlineBox(face, glyph, size, shift, width);
					const pad: int32 = (Math.ceil(width) as int32) + 1;
					assert outline[0] == fx0 - pad && outline[1] == fy0 - pad;
					assert outline[2] == fx1 + pad && outline[3] == fy1 + pad;
					assert outline[4] == 0;
					compared = compared + 1;
				}
			}
		}
	}
	assert compared == 4 * 2 * 4 * 4;
}

test "a glyph with no ink has an empty outline box and a space costs no tile" {
	const face = testFace();
	const space = void2dGlyphOutlineBox(face, glyphIndex(face, " ".code), 13.0, 0.0, 2.0);
	assert space[0] == 0 && space[1] == 0 && space[2] == 0 && space[3] == 0;
	const atlas = GlyphAtlas.create(256, 2);
	defer atlas.dispose();
	const r = atlas.acquireOutline(keyOf(face, glyphIndex(face, " ".code), 13.0, 0, 8));
	assert r.ok;
	if (r.ok) { assert atlas.tile(r.value).width == 0; }
	assert atlas.pageCount() == 0;
}

test "an I stem at an integer width matches the exact rectangle distance within one level" {
	assert worstStemError(40.0, 0, 3.0) <= 1;
	assert worstStemError(40.0, 0, 1.0) <= 1;
	assert worstStemError(26.0, 0, 2.0) <= 1;
}

test "the quarter-pixel shift moves the outline with the fill" {
	assert worstStemError(40.0, 1, 3.0) <= 1;
	assert worstStemError(40.0, 2, 2.0) <= 1;
	assert worstStemError(40.0, 3, 0.5) <= 1;
}

test "the outer corner is rounded, not mitred" {
	const face = testFace();
	const atlas = GlyphAtlas.create(1024, 2);
	defer atlas.dispose();
	const r = atlas.acquireOutline(keyOf(face, glyphIndex(face, "I".code), 40.0, 0, laneOf(4.0)));
	assert r.ok;
	if (r.ok) {
		const t: GlyphTile = atlas.tile(r.value);
		const scale: float32 = 40.0 / UNITS;
		const cornerX: float32 = STEM_LEFT * scale;
		const cornerY: float32 = -STEM_TOP * scale;
		const col: int32 = (Math.floor(cornerX - 3.4) as int32) - t.left;
		const row: int32 = (Math.floor(cornerY - 3.4) as int32) - t.top;
		assert texel(atlas, t, col, row) == 0;
		assert texel(atlas, t, col + 3, row + 3) > 0;
	}
}

test "the same key is one tile and a new width is another" {
	const face = testFace();
	const glyph: int32 = glyphIndex(face, "g".code);
	const atlas = GlyphAtlas.create(512, 2);
	defer atlas.dispose();
	const a = atlas.acquireOutline(keyOf(face, glyph, 16.0, 1, 8));
	const b = atlas.acquireOutline(keyOf(face, glyph, 16.0, 1, 8));
	const c = atlas.acquireOutline(keyOf(face, glyph, 16.0, 1, 12));
	assert a.ok && b.ok && c.ok;
	if (a.ok && b.ok && c.ok) {
		assert a.value == b.value;
		assert a.value != c.value;
		assert atlas.tile(a.value).refs == 2;
	}
	assert atlas.outlineRasterizations == 2;
	assert void2dGlyphOutlineGenerations() >= 2;
}

test "a lane of zero, a bad variant and a plain acquire are refused by name" {
	const face = testFace();
	const glyph: int32 = glyphIndex(face, "g".code);
	const atlas = GlyphAtlas.create(256, 2);
	defer atlas.dispose();
	const none = atlas.acquireOutline(keyOf(face, glyph, 16.0, 0, 0));
	assert !none.ok;
	if (!none.ok) { assert none.error == AtlasError.KindNotBuilt; }
	const bad = atlas.acquireOutline(keyOf(face, glyph, 16.0, 4, 8));
	assert !bad.ok;
	if (!bad.ok) { assert bad.error == AtlasError.VariantOutOfRange; }
	const plain = atlas.acquire(keyOf(face, glyph, 16.0, 0, 8));
	assert !plain.ok;
	if (!plain.ok) { assert plain.error == AtlasError.KindNotBuilt; }
	assert atlas.pageCount() == 0;
}

test "a cubic glyph gets an outline tile that holds its fill" {
	const face = cubicFace();
	assert face >= 0;
	const glyph: int32 = glyphIndex(face, "A".code);
	const atlas = GlyphAtlas.create(1024, 4);
	defer atlas.dispose();
	const outline = atlas.acquireOutline(keyOf(face, glyph, 40.0, 0, laneOf(2.0)));
	const fill = atlas.acquire(keyOf(face, glyph, 40.0, 0, 0));
	assert outline.ok && fill.ok;
	if (outline.ok && fill.ok) {
		const o: GlyphTile = atlas.tile(outline.value);
		const f: GlyphTile = atlas.tile(fill.value);
		assert o.width > f.width && o.height > f.height;
		let fillInk: int32 = 0;
		let outlineInk: int32 = 0;
		for (let row = 0; row < f.height; row++) {
			for (let col = 0; col < f.width; col++) {
				const covered: int32 = texel(atlas, f, col, row);
				fillInk = fillInk + covered;
				const at: int32 = texel(atlas, o, f.left + col - o.left, f.top + row - o.top);
				if (covered > 0) { assert at + 1 >= covered; }
			}
		}
		for (let row = 0; row < o.height; row++) {
			for (let col = 0; col < o.width; col++) {
				outlineInk = outlineInk + texel(atlas, o, col, row);
			}
		}
		assert fillInk > 0;
		assert outlineInk > fillInk + fillInk / 8;
	}
}

when (voidSdfText) {
	function sdfByte(distance: float32, texels: float32): int32 {
		const value: float32 = (SDF_EDGE as float32) + 31.875 * (distance + texels);
		if (value < 0.0) { return 0; }
		if (value > 255.0) { return 255; }
		return value as int32;
	}

	function worstSdfStemError(lane: int32): int32 {
		const face = testFace();
		const atlas = GlyphAtlas.create(1024, 2);
		defer atlas.dispose();
		const r = atlas.acquireSdfOutline(face, glyphIndex(face, "I".code), lane);
		let worst: int32 = 255;
		if (r.ok) {
			worst = 0;
			const t: GlyphTile = atlas.tile(r.value);
			const scale: float32 = SDF_EM / UNITS;
			const texels: float32 = (lane as float32) / SDF_OUTLINE_PER_TEXEL;
			for (let row = 0; row < t.height; row++) {
				for (let col = 0; col < t.width; col++) {
					const cx: float32 = ((t.left + col) as float32) + 0.5;
					const cy: float32 = ((t.top + row) as float32) + 0.5;
					const want: int32 = sdfByte(stemDistance(cx, cy, scale), texels);
					const got: int32 = pageTexel(atlas.pageHandle(t.page), t.x + col, t.y + row);
					const off: int32 = got > want ? got - want : want - got;
					if (off > worst) { worst = off; }
				}
			}
		}
		return worst;
	}

	test "an SDF outline tile is the field shifted by the width, byte for byte on an I stem" {
		assert worstSdfStemError(8) <= 1;
		assert worstSdfStemError(24) <= 1;
		assert worstSdfStemError(36) <= 1;
	}

	test "an SDF outline tile is the SDF box grown by ceil(width) + 2 and lives on an SDF page" {
		const face = testFace();
		const atlas = GlyphAtlas.create(1024, 2);
		defer atlas.dispose();
		for (const codepoint of ["I".code, "g".code, "W".code, "@".code]) {
			const glyph: int32 = glyphIndex(face, codepoint);
			const base = void2dGlyphSdfBox(face, glyph);
			const bx0: int32 = base[0];
			const by0: int32 = base[1];
			const bx1: int32 = base[2];
			const by1: int32 = base[3];
			for (const lane of [4, 12, 25]) {
				const grown = void2dGlyphSdfOutlineBox(face, glyph, (lane as float32) / 8.0);
				const extra: int32 = (Math.ceil((lane as float32) / 8.0) as int32) + 2;
				assert grown[0] == bx0 - extra && grown[1] == by0 - extra;
				assert grown[2] == bx1 + extra && grown[3] == by1 + extra;
			}
			const r = atlas.acquireSdfOutline(face, glyph, 12);
			assert r.ok;
			if (r.ok) { assert atlas.pageKind(atlas.tile(r.value).page) == PageKind.Sdf; }
		}
	}

	test "the outline tile is another key than the field and costs no base generation" {
		const face = testFace();
		const glyph: int32 = glyphIndex(face, "g".code);
		const atlas = GlyphAtlas.create(1024, 2);
		defer atlas.dispose();
		const field = atlas.acquireSdf(face, glyph);
		const outline = atlas.acquireSdfOutline(face, glyph, 16);
		const again = atlas.acquireSdfOutline(face, glyph, 16);
		const wider = atlas.acquireSdfOutline(face, glyph, 17);
		assert field.ok && outline.ok && again.ok && wider.ok;
		if (field.ok && outline.ok && again.ok && wider.ok) {
			assert field.value != outline.value && outline.value == again.value;
			assert wider.value != outline.value;
			assert atlas.tile(outline.value).width > atlas.tile(field.value).width;
		}
		assert atlas.generations == 1;
		assert atlas.outlineRasterizations == 2;
	}

	test "a cubic glyph has no SDF outline and a lane outside the key is refused by name" {
		const face = cubicFace();
		const atlas = GlyphAtlas.create(1024, 2);
		defer atlas.dispose();
		const cubic = atlas.acquireSdfOutline(face, glyphIndex(face, "A".code), 16);
		assert !cubic.ok;
		if (!cubic.ok) { assert cubic.error == AtlasError.SdfCubicOutline; }
		const plain = testFace();
		const none = atlas.acquireSdfOutline(plain, glyphIndex(plain, "g".code), 0);
		assert !none.ok;
		if (!none.ok) { assert none.error == AtlasError.OutlineTooWide; }
		const over = atlas.acquireSdfOutline(plain, glyphIndex(plain, "g".code), 256);
		assert !over.ok;
		if (!over.ok) { assert over.error == AtlasError.OutlineTooWide; }
		assert atlas.pageCount() == 0;
	}
}
