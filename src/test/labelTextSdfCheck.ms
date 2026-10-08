import { Align } from "../void2d/textLayout";
import { DEFAULT_FONT, FontId, addFont } from "../void2d/font";
import {
	allocateLabelText,
	releaseLabelText,
	shapeLabel,
	placeLabel,
	glyphAtlas,
	glyphRasterizations,
	regimeOf,
	setSdfRegime,
	TextRegime,
} from "../void2d/labelText";
import { PageKind } from "../void2d/glyphAtlas";
import { trs2d } from "../void2d/types";
import { SDF_EM } from "../void2d/textSdf";
import { approx } from "./helpers";

function shapedAt(text: string, size: float32): int32 {
	return shapedIn(text, size, DEFAULT_FONT);
}

function shapedIn(text: string, size: float32, font: FontId): int32 {
	const index = allocateLabelText();
	shapeLabel(index, text, {
		font: font,
		size: size,
		letterSpacing: 0.0,
		lineSpacing: 0.0,
		maxWidth: 0.0,
		align: Align.Left,
	});
	return index;
}

test "without the switch a rotated or zoomed label keeps today's regimes" {
	setSdfRegime(false);
	assert regimeOf(trs2d(3.0, 4.0, 0.0, 1.0, 1.0)) == TextRegime.PixelExact;
	assert regimeOf(trs2d(3.0, 4.0, 0.0, 2.0, 2.0)) == TextRegime.PixelExact;
	assert regimeOf(trs2d(0.0, 0.0, 0.5, 1.0, 1.0)) == TextRegime.Bitmap;
	assert regimeOf(trs2d(0.0, 0.0, 0.0, 1.0, 2.0)) == TextRegime.Bitmap;
}

test "the regime leaves pixel-exact only when the matrix is more than a translation" {
	setSdfRegime(true);
	defer setSdfRegime(false);
	assert regimeOf(trs2d(0.0, 0.0, 0.0, 1.0, 1.0)) == TextRegime.PixelExact;
	assert regimeOf(trs2d(10.3, -7.7, 0.0, 1.0, 1.0)) == TextRegime.PixelExact;
	assert regimeOf(trs2d(0.0, 0.0, 0.0, 1.0001, 1.0001)) == TextRegime.Sdf;
	assert regimeOf(trs2d(0.0, 0.0, 0.0, 0.5, 0.5)) == TextRegime.Sdf;
	assert regimeOf(trs2d(0.0, 0.0, 0.0, 1.0, 2.0)) == TextRegime.Sdf;
	assert regimeOf(trs2d(0.0, 0.0, 0.01, 1.0, 1.0)) == TextRegime.Sdf;
	assert regimeOf(trs2d(0.0, 0.0, 0.0, -1.0, 1.0)) == TextRegime.Sdf;
}

test "an SDF placement is the tile's box in local units at the field's size" {
	setSdfRegime(true);
	defer setSdfRegime(false);
	const index = shapedAt("A", 13.0);
	const text = placeLabel(index, trs2d(0.0, 0.0, 0.5, 2.0, 2.0), 1.0);
	assert text.regime == TextRegime.Sdf;
	assert text.placedValid;
	assert (text.placed.length as int32) == 1;
	const p = text.placed[0];
	const tile = glyphAtlas.tile(p.tile);
	const k: float32 = 13.0 / SDF_EM;
	assert glyphAtlas.pageKind(tile.page) == PageKind.Sdf;
	assert approx(p.w, (tile.width as float32) * k);
	assert approx(p.h, (tile.height as float32) * k);
	assert approx(p.x, text.layout.glyphs[0].x + (tile.left as float32) * k);
	assert approx(p.y, text.layout.lines[0].baseline + (tile.top as float32) * k);
	releaseLabelText(index);
}

test "a sixty-four step zoom and a sixty-four step turn acquire nothing after the first frame" {
	setSdfRegime(true);
	defer setSdfRegime(false);
	const index = shapedAt("Zoom and turn", 14.0);
	const first = placeLabel(index, trs2d(0.0, 0.0, 0.0, 0.5, 0.5), 1.0);
	assert first.regime == TextRegime.Sdf;
	const x: float32 = first.placed[0].x;
	const y: float32 = first.placed[0].y;
	const w: float32 = first.placed[0].w;
	const kept: float32 = 123.0;
	first.placed[0].u0 = kept;
	const rasterized = glyphRasterizations();
	const generated = glyphAtlas.generations;
	const slots = glyphAtlas.tileSlots();
	for (let step = 0; step < 64; step++) {
		const zoom: float32 = 0.53 + (step as float32) * 0.0537;
		const text = placeLabel(index, trs2d(5.0, 6.0, 0.0, zoom, zoom), 1.0);
		assert text.placedValid;
		assert text.placed[0].x == x && text.placed[0].y == y && text.placed[0].w == w;
		assert text.placed[0].u0 == kept;
	}
	for (let step = 0; step < 64; step++) {
		const turn: float32 = (step as float32) * 0.0981;
		const text = placeLabel(index, trs2d(5.0, 6.0, turn, 3.0, 3.0), 1.0);
		assert text.placedValid;
		assert text.placed[0].x == x && text.placed[0].y == y && text.placed[0].w == w;
		assert text.placed[0].u0 == kept;
	}
	assert glyphRasterizations() == rasterized;
	assert glyphAtlas.generations == generated;
	assert glyphAtlas.tileSlots() == slots;
	releaseLabelText(index);
}

test "a label that returns to a translation re-places on the coverage atlas and drops the field" {
	setSdfRegime(true);
	defer setSdfRegime(false);
	const index = shapedAt("Back", 13.0);
	const turned = placeLabel(index, trs2d(0.0, 0.0, 0.3, 1.0, 1.0), 1.0);
	assert turned.regime == TextRegime.Sdf;
	const field = turned.placed[0].tile;
	const held = glyphAtlas.tile(field).refs;
	const before = glyphRasterizations();
	const flat = placeLabel(index, trs2d(2.0, 3.0, 0.0, 1.0, 1.0), 1.0);
	assert flat.regime == TextRegime.PixelExact;
	assert glyphRasterizations() > before;
	assert glyphAtlas.tile(field).refs == held - 1;
	assert glyphAtlas.pageKind(glyphAtlas.tile(flat.placed[0].tile).page) == PageKind.Coverage;
	releaseLabelText(index);
}

test "two labels of one glyph share one field tile whatever their matrices" {
	setSdfRegime(true);
	defer setSdfRegime(false);
	const left = shapedAt("Q", 10.0);
	const right = shapedAt("Q", 40.0);
	const a = placeLabel(left, trs2d(0.0, 0.0, 0.0, 3.0, 3.0), 1.0);
	const b = placeLabel(right, trs2d(0.0, 0.0, 1.0, 0.5, 0.5), 1.0);
	assert a.placed[0].tile == b.placed[0].tile;
	assert glyphAtlas.tile(a.placed[0].tile).refs >= 2;
	assert approx(b.placed[0].w * 10.0, a.placed[0].w * 40.0);
	releaseLabelText(left);
	releaseLabelText(right);
}

test "a label whose scale starts at zero is placed once the scale grows" {
	setSdfRegime(true);
	defer setSdfRegime(false);
	const index = shapedAt("A", 13.0);
	const hidden = placeLabel(index, trs2d(0.0, 0.0, 0.0, 0.0, 0.0), 1.0);
	assert hidden.regime == TextRegime.Sdf;
	assert (hidden.placed.length as int32) == 1;
	const x: float32 = hidden.placed[0].x;
	const w: float32 = hidden.placed[0].w;
	const grown = placeLabel(index, trs2d(0.0, 0.0, 0.0, 2.0, 2.0), 1.0);
	assert (grown.placed.length as int32) == 1;
	assert grown.placed[0].x == x && grown.placed[0].w == w;
	releaseLabelText(index);
}

test "the DPI scale does not move an SDF placement" {
	setSdfRegime(true);
	defer setSdfRegime(false);
	const one = shapedAt("Ag", 13.0);
	const two = shapedAt("Ag", 13.0);
	const a = placeLabel(one, trs2d(0.0, 0.0, 0.4, 1.5, 1.5), 1.0);
	const b = placeLabel(two, trs2d(0.0, 0.0, 0.4, 1.5, 1.5), 2.0);
	assert a.regime == TextRegime.Sdf && b.regime == TextRegime.Sdf;
	assert (a.placed.length as int32) == 2 && (b.placed.length as int32) == 2;
	for (let i = 0; i < 2; i++) {
		assert a.placed[i].x == b.placed[i].x && a.placed[i].y == b.placed[i].y;
		assert a.placed[i].w == b.placed[i].w && a.placed[i].h == b.placed[i].h;
		assert a.placed[i].tile == b.placed[i].tile;
	}
	releaseLabelText(one);
	releaseLabelText(two);
}

test "a cubic outline falls back to coverage for that glyph and keeps the rest on the field" {
	setSdfRegime(true);
	defer setSdfRegime(false);
	const font = try addFont("tests/fonts/cffSynthetic.otf") catch DEFAULT_FONT;
	assert font != DEFAULT_FONT;
	const index = shapedIn("AB", 20.0, font);
	const first = placeLabel(index, trs2d(0.0, 0.0, 0.3, 2.0, 2.0), 1.0);
	assert first.regime == TextRegime.Sdf;
	assert first.placedValid;
	assert first.refused == 0;
	assert (first.placed.length as int32) == 2;
	assert glyphAtlas.pageKind(first.placed[0].page) == PageKind.Coverage;
	assert glyphAtlas.pageKind(first.placed[1].page) == PageKind.Sdf;
	const sharp: float32 = glyphAtlas.tile(first.placed[0].tile).height as float32;
	const zoomed = placeLabel(index, trs2d(0.0, 0.0, 0.3, 4.0, 4.0), 1.0);
	assert zoomed.placedValid && zoomed.refused == 0;
	assert glyphAtlas.pageKind(zoomed.placed[0].page) == PageKind.Coverage;
	assert (glyphAtlas.tile(zoomed.placed[0].tile).height as float32) > sharp * 1.5;
	const rasterized = glyphRasterizations();
	const steady = placeLabel(index, trs2d(0.0, 0.0, 0.3, 4.0, 4.0), 1.0);
	assert steady.placedValid;
	assert glyphRasterizations() == rasterized;
	releaseLabelText(index);
}

when (voidSprites) {
	test "a sprite has no outline, so the SDF regime draws it from its coverage tile" {
		setSdfRegime(true);
		defer setSdfRegime(false);
		const index = shapedAt("\u{2588}\u{2500}A", 13.0);
		const text = placeLabel(index, trs2d(0.0, 0.0, 0.3, 2.0, 2.0), 1.0);
		assert text.regime == TextRegime.Sdf;
		assert text.placedValid && text.refused == 0;
		assert (text.placed.length as int32) == 3;
		assert glyphAtlas.pageKind(text.placed[0].page) == PageKind.Coverage;
		assert glyphAtlas.pageKind(text.placed[1].page) == PageKind.Coverage;
		assert glyphAtlas.pageKind(text.placed[2].page) == PageKind.Sdf;
		releaseLabelText(index);
	}
}
