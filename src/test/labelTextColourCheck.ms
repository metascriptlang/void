import { Align } from "../void2d/textLayout";
import { FontId, addFont, addFallbackFont } from "../void2d/font";
import { ColourGlyph, colourTileBox, glyphIndex, loadFace } from "../void2d/face";
import {
	allocateLabelText,
	shapeLabel,
	placeLabel,
	glyphAtlas,
	glyphRasterizations,
	glyphRefusals,
	releaseLabelText,
} from "../void2d/labelText";
import { AtlasError, GlyphAtlas, PageKind, colourKey } from "../void2d/glyphAtlas";
import { Transform2D, trs2d, rgba, identity2d } from "../void2d/types";
import { Scene2D } from "../void2d/node";
import { add } from "../void2d/scene";
import { sync, draw } from "../void2d/render";
import { begin2d, finishRecording, frameEnd } from "../void2d/draw";
import {
	commandCount, commandField, uiInstanceCount, uiInstanceField, vertexCount,
	CMD_SAMPLER, CMD_PIPELINE, Pipeline, SOURCE_PREMULTIPLIED,
} from "../void2d/displayList";
import {
	REC_UI_AFFINE, REC_UI_PARAMS0, REC_UI_PARAMS1, REC_UI_COLOR_FILL,
} from "../void2d/instanceLayout";
import { InstanceMode } from "../void2d/instance";
import { void2dGlyphPageBlitRgba, void2dGlyphPageTexelRgba } from "../void2d/glyph.h";

const LATIN: string = "assets/font.ttf";
const EMOJI: string = "tests/fonts/NotoColorEmoji-subset.ttf";
const GRIN: string = "\u{1F600}";
const GLYPH_MODE: float32 = (InstanceMode.Glyph as int32) as float32;
const IMAGE_MODE: float32 = (InstanceMode.Image as int32) as float32;

let emojiFont: FontId = 0 as FontId;
let emojiFontReady: boolean = false;

function withEmoji(): FontId {
	if (!emojiFontReady) {
		emojiFont = try addFont(LATIN) catch emojiFont;
		addFallbackFont(emojiFont, EMOJI);
		emojiFontReady = true;
	}
	return emojiFont;
}

function shapedAt(text: string, size: float32): int32 {
	const index = allocateLabelText();
	shapeLabel(index, text, {
		font: withEmoji(),
		size: size,
		letterSpacing: 0.0,
		lineSpacing: 0.0,
		maxWidth: 0.0,
		align: Align.Left,
	});
	return index;
}

function nearest(value: float32): int32 {
	return Math.floor(value + 0.5) as int32;
}

function fraction(value: float32): float32 {
	return value - (Math.floor(value) as float32);
}

test "a colour glyph sits on a whole device pixel at DPI 1.0, 1.25 and 1.5" {
	const scales: float32[] = [1.0, 1.25, 1.5];
	const offsets: float32[] = [3.3, 4.6, 3.8, 4.2, 3.55, 4.9];
	for (const scale of scales) {
		for (let o: int32 = 0; o < 6; o = o + 2) {
			const index = shapedAt(`a${GRIN}b`, 16.0);
			const world: Transform2D = trs2d(offsets[o], offsets[o + 1], 0.0, 1.0, 1.0);
			const text = placeLabel(index, world, scale);
			assert text.placedValid;
			assert text.colourGlyphs == 1;
			assert (text.placed.length as int32) == 3;
			const g = text.layout.glyphs[1];
			const p = text.placed[1];
			const tile = glyphAtlas.tile(p.tile);
			assert glyphAtlas.pageKind(tile.page) == PageKind.Rgba;
			const x: int32 = nearest(fraction(world.tx * scale) + g.x * scale) + tile.left;
			const baseline: float32 = text.layout.lines[g.line].baseline;
			const y: int32 = nearest(fraction(world.ty * scale) + baseline * scale) + tile.top;
			assert p.x == (x as float32);
			assert p.y == (y as float32);
			assert p.w == (tile.width as float32) && p.h == (tile.height as float32);
			const mono = glyphAtlas.tile(text.placed[0].tile);
			assert glyphAtlas.pageKind(mono.page) == PageKind.Coverage;
			releaseLabelText(index);
		}
	}
}

test "the colour tile is the strike resized to the device size, with no subpixel variant" {
	const index = shapedAt(GRIN, 16.0);
	const text = placeLabel(index, identity2d(), 1.25);
	const tile = glyphAtlas.tile(text.placed[0].tile);
	const box = colourTileBox(text.layout.glyphs[0].face, text.layout.glyphs[0].glyph, 20.0);
	assert box.glyph == ColourGlyph.Present;
	assert tile.width == box.right - box.left && tile.height == box.bottom - box.top;
	assert tile.left == box.left && tile.top == box.top;
	releaseLabelText(index);
}

test "the same emoji at two fractional offsets is one tile" {
	const a = shapedAt(GRIN, 16.0);
	const b = shapedAt(GRIN, 16.0);
	const first = placeLabel(a, trs2d(3.0, 4.0, 0.0, 1.0, 1.0), 1.0);
	const before: int32 = glyphRasterizations();
	const second = placeLabel(b, trs2d(3.4, 4.0, 0.0, 1.0, 1.0), 1.0);
	assert first.placed[0].tile == second.placed[0].tile;
	assert glyphRasterizations() == before;
	assert glyphAtlas.tile(first.placed[0].tile).refs == 2;
	releaseLabelText(a);
	releaseLabelText(b);
}

test "a colour glyph over the texel limit is refused by name and no tile is cached for it" {
	const index = shapedAt(GRIN, 16.0);
	const refused: int32 = glyphRefusals();
	const text = placeLabel(index, trs2d(0.0, 0.0, 0.0, 400.0, 400.0), 1.0);
	assert glyphRefusals() == refused + 1;
	assert !text.placedValid;
	assert (text.placed.length as int32) == 0;
	releaseLabelText(index);
}

function recordLabel(text: string, alpha: float32): void {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const label = s.label(text, 16.0, rgba(1.0, 0.5, 0.25, 1.0)).setFont(withEmoji());
	const root = s.add(label.at(8.0, 8.0).setAlpha(alpha));
	begin2d(128.0, 64.0, 1.0);
	root.sync(identity2d(), true);
	root.draw(1.0, 128.0, 64.0);
	finishRecording();
}

function instancesOfMode(mode: float32): int32 {
	let count: int32 = 0;
	for (let i: int32 = 0; i < uiInstanceCount(); i++) {
		if (uiInstanceField(i, REC_UI_PARAMS0) == mode) { count = count + 1; }
	}
	return count;
}

test "an emoji records as an Image-mode instance marked premultiplied, text as Glyph mode" {
	recordLabel(`a${GRIN}b`, 1.0);
	assert instancesOfMode(GLYPH_MODE) == 2;
	assert instancesOfMode(IMAGE_MODE) == 1;
	for (let i: int32 = 0; i < uiInstanceCount(); i++) {
		if (uiInstanceField(i, REC_UI_PARAMS0) != IMAGE_MODE) { continue; }
		assert uiInstanceField(i, REC_UI_PARAMS1) == 0.0;
		assert uiInstanceField(i, REC_UI_PARAMS1 + 1) == 1.0;
		assert uiInstanceField(i, REC_UI_AFFINE) == 1.0;
		assert uiInstanceField(i, REC_UI_AFFINE + 3) == 1.0;
	}
	frameEnd();
}

test "an emoji ignores the text colour and takes only its alpha" {
	recordLabel(`a${GRIN}`, 0.5);
	const fill: int32 = REC_UI_COLOR_FILL;
	assert instancesOfMode(IMAGE_MODE) == 1;
	for (let i: int32 = 0; i < uiInstanceCount(); i++) {
		if (uiInstanceField(i, REC_UI_PARAMS0) == IMAGE_MODE) {
			assert uiInstanceField(i, fill) == 1.0 && uiInstanceField(i, fill + 1) == 1.0;
			assert uiInstanceField(i, fill + 2) == 1.0 && uiInstanceField(i, fill + 3) == 0.5;
		} else {
			assert uiInstanceField(i, fill + 1) < 1.0;
		}
	}
	frameEnd();
}

test "text and emoji alternating in one label record as one text block then one emoji block" {
	recordLabel(`a${GRIN}b${GRIN}c`, 1.0);
	assert uiInstanceCount() == 5;
	for (let i: int32 = 0; i < 3; i++) {
		assert uiInstanceField(i, REC_UI_PARAMS0) == GLYPH_MODE;
	}
	assert uiInstanceField(3, REC_UI_PARAMS0) == IMAGE_MODE;
	assert uiInstanceField(4, REC_UI_PARAMS0) == IMAGE_MODE;
	frameEnd();
}

test "the emoji run is recorded after the text run, whatever the order in the text" {
	recordLabel(`${GRIN}a${GRIN}`, 1.0);
	assert uiInstanceField(0, REC_UI_PARAMS0) == GLYPH_MODE;
	assert uiInstanceField(1, REC_UI_PARAMS0) == IMAGE_MODE;
	assert uiInstanceField(2, REC_UI_PARAMS0) == IMAGE_MODE;
	frameEnd();
}

test "under a colour add an emoji records on the vertex program as a premultiplied quad" {
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const label = s.label(GRIN, 16.0, rgba(1.0, 1.0, 1.0, 1.0)).setFont(withEmoji());
	const root = s.add(label.at(8.0, 8.0).setColorAdd(rgba(0.2, 0.0, 0.0, 0.0)));
	begin2d(128.0, 64.0, 1.0);
	root.sync(identity2d(), true);
	root.draw(1.0, 128.0, 64.0);
	finishRecording();
	assert uiInstanceCount() == 0;
	assert commandCount() == 1;
	assert commandField(0, CMD_PIPELINE) == ((Pipeline.Vertex as int32) as float32);
	assert commandField(0, CMD_SAMPLER) >= (SOURCE_PREMULTIPLIED as float32);
	assert vertexCount() == 6;
	frameEnd();
}

test "a colour tile whose rasterization is refused is discarded and its key is not cached" {
	const face = try loadFace(EMOJI) catch -1;
	assert face >= 0;
	const glyph: int32 = glyphIndex(face, 0x1F600);
	const box = colourTileBox(face, glyph, 20.0);
	assert box.glyph == ColourGlyph.Present;
	const atlas = GlyphAtlas.create(256, 4);
	const key = colourKey(face, glyph, 20.0);
	const width: int32 = box.right - box.left;
	const height: int32 = box.bottom - box.top;
	const wrong = atlas.acquireColour(key, width + 3, height, box.left, box.top);
	assert !wrong.ok;
	if (!wrong.ok) { assert wrong.error == AtlasError.ColourRefused; }
	assert !atlas.cached(key);
	assert atlas.rasterizations == 0;
	const right = atlas.acquireColour(key, width, height, box.left, box.top);
	assert right.ok;
	assert atlas.cached(key);
	assert atlas.rasterizations == 1;
	if (!right.ok) { return; }
	const t = atlas.tile(right.value);
	const handle: int32 = atlas.pageHandle(t.page) as int32;
	const sentinel: uint32[] = [0x12345678];
	assert void2dGlyphPageBlitRgba(handle, t.x, t.y, 1, 1, sentinel[0], 1) == 0;
	const again = atlas.acquireColour(key, width, height, box.left, box.top);
	assert again.ok;
	assert atlas.rasterizations == 1;
	assert void2dGlyphPageTexelRgba(handle, t.x, t.y) == 0x12345678;
}

function fontWith(first: string, second: string): FontId {
	const f = try addFont(LATIN) catch emojiFont;
	addFallbackFont(f, first);
	if (!second.equals("")) { addFallbackFont(f, second); }
	return f;
}

function colourCount(font: FontId, text: string): int32 {
	const index = allocateLabelText();
	shapeLabel(index, text, {
		font: font, size: 16.0, letterSpacing: 0.0, lineSpacing: 0.0, maxWidth: 0.0,
		align: Align.Left,
	});
	return placeLabel(index, identity2d(), 1.25).colourGlyphs;
}

test "the COLR and sbix fixtures place colour tiles beside the text" {
	assert colourCount(fontWith("tests/fonts/colrSynthetic.ttf", ""), `a${GRIN}b`) == 1;
	assert colourCount(fontWith("tests/fonts/sbixSynthetic.ttf", ""), `a${GRIN}b`) == 1;
}

test "VS15 draws the text face and VS16 the colour face of the same heart" {
	const pair = fontWith(EMOJI, "tests/fonts/textSymbol.ttf");
	assert colourCount(pair, "\u{2764}\u{FE0E}") == 0;
	assert colourCount(pair, "\u{2764}\u{FE0F}") == 1;
	assert colourCount(pair, "\u{2764}\u{FE0E} \u{2764}\u{FE0F}") == 1;
}
