import "../void2d/textOutlineSwitch";
import { Align } from "../void2d/textLayout";
import { DEFAULT_FONT } from "../void2d/font";
import {
	allocateLabelText,
	releaseLabelText,
	shapeLabel,
	placeLabel,
	setLabelOutline,
	glyphAtlas,
	glyphRefusals,
	glyphRefusalReports,
	TextRegime,
	labelTexts,
	LabelText,
} from "../void2d/labelText";
import { AtlasError, GlyphTile, quantizeX, snapBaseline } from "../void2d/glyphAtlas";
import { Transform2D, trs2d, rgba } from "../void2d/types";
import { Scene2D } from "../void2d/node";
import { PageKind } from "../void2d/glyphAtlas";
when (voidSdfText) {
	import { setSdfRegime } from "../void2d/labelText";
}
import "../void2d/scene";

const RED = rgba(1.0, 0.0, 0.0, 1.0);
const CLEAR = rgba(1.0, 0.0, 0.0, 0.0);
const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));

function shaped(text: string, size: float32): int32 {
	const index = allocateLabelText();
	shapeLabel(index, text, {
		font: DEFAULT_FONT,
		size: size,
		letterSpacing: 0.0,
		lineSpacing: 0.0,
		maxWidth: 0.0,
		align: Align.Left,
	});
	return index;
}

function inked(text: LabelText): int32 {
	let count: int32 = 0;
	for (const p of text.placed) {
		if (p.w > 0.0 && p.h > 0.0) { count = count + 1; }
	}
	return count;
}

function outlineRefs(text: LabelText): int32 {
	let refs: int32 = 0;
	for (const p of text.placedOutline) { refs = refs + glyphAtlas.tile(p.tile).refs; }
	return refs;
}

function laneOf(key: uint64): int32 {
	return ((key >> 24) & 255) as int32;
}

function outlineTiles(index: int32): int32 {
	const text = placeLabel(index, trs2d(0.0, 0.0, 0.0, 1.0, 1.0), 1.0);
	return text.placedOutline.length as int32;
}

function snapped(width: float32, dpi: float32): float32 {
	const device: float32 = width * dpi;
	const whole: float32 = Math.floor(device + 0.5) as float32;
	return whole < 1.0 ? 1.0 : whole;
}

test "an outlined label places one outline tile per inked glyph beside its fill" {
	const densities: float32[] = [1.0, 1.25, 1.5];
	for (const dpi of densities) {
		const index = shaped("Hello, wor ld", 13.0);
		setLabelOutline(index, 2.0, RED);
		const text = placeLabel(index, trs2d(3.3, 4.6, 0.0, 1.0, 1.0), dpi);
		assert text.regime == TextRegime.PixelExact;
		assert text.placedValid;
		assert (text.placedOutline.length as int32) == inked(text);
		assert (text.placedOutline.length as int32) == 11;
		const lane: int32 = (snapped(2.0, dpi) * 4.0) as int32;
		for (const p of text.placedOutline) {
			assert laneOf(glyphAtlas.tile(p.tile).key) == lane;
		}
		releaseLabelText(index);
	}
}

test "each outline sits on the same pen position as its fill and holds it" {
	const index = shaped("Rag", 13.0);
	setLabelOutline(index, 2.0, RED);
	const text = placeLabel(index, trs2d(0.0, 0.0, 0.0, 1.0, 1.0), 1.25);
	assert (text.placedOutline.length as int32) == 3;
	const width: float32 = snapped(2.0, 1.25);
	for (let i = 0; i < 3; i++) {
		const fill = text.placed[i];
		const outline = text.placedOutline[i];
		assert outline.x <= fill.x - width && outline.y <= fill.y - width;
		assert outline.x + outline.w >= fill.x + fill.w + width;
		assert outline.y + outline.h >= fill.y + fill.h + width;
	}
	const g = text.layout.glyphs[1];
	const q = quantizeX(g.x * 1.25);
	const baseline = snapBaseline(text.layout.lines[0].baseline * 1.25);
	const tile: GlyphTile = glyphAtlas.tile(text.placedOutline[1].tile);
	assert text.placedOutline[1].x == ((q.whole + tile.left) as float32);
	assert text.placedOutline[1].y == ((baseline + tile.top) as float32);
	releaseLabelText(index);
}

test "a colour change places nothing again and a width change releases the old tiles" {
	const index = shaped("steady", 13.0);
	setLabelOutline(index, 2.0, RED);
	placeLabel(index, trs2d(0.0, 0.0, 0.0, 1.0, 1.0), 1.0);
	const first = labelTexts[index].placedOutline[0].tile;
	const tilesBefore = glyphAtlas.rasterizations;
	const heldBefore = glyphAtlas.tile(first).refs;
	setLabelOutline(index, 2.0, rgba(0.0, 1.0, 0.0, 0.5));
	const same = placeLabel(index, trs2d(0.0, 0.0, 0.0, 1.0, 1.0), 1.0);
	assert glyphAtlas.rasterizations == tilesBefore;
	assert same.placedOutline[0].tile == first;
	assert glyphAtlas.tile(first).refs == heldBefore;
	setLabelOutline(index, 3.0, rgba(0.0, 1.0, 0.0, 0.5));
	const wider = placeLabel(index, trs2d(0.0, 0.0, 0.0, 1.0, 1.0), 1.0);
	assert wider.placedOutline[0].tile != first;
	assert glyphAtlas.tile(first).refs == heldBefore - 1;
	assert glyphAtlas.rasterizations > tilesBefore;
	releaseLabelText(index);
}

test "releasing a label drops its outline tile references" {
	const index = shaped("Qz", 13.0);
	setLabelOutline(index, 1.0, RED);
	const text = placeLabel(index, trs2d(0.0, 0.0, 0.0, 1.0, 1.0), 1.0);
	const tileIndex = text.placedOutline[0].tile;
	const held = glyphAtlas.tile(tileIndex).refs;
	releaseLabelText(index);
	assert glyphAtlas.tile(tileIndex).refs == held - 1;
}

test "a translation sweep acquires nothing once the four variants are cached" {
	const index = shaped("sweep", 13.0);
	setLabelOutline(index, 2.0, RED);
	for (let step = 0; step < 4; step++) {
		placeLabel(index, trs2d((step as float32) * 0.25, 0.0, 0.0, 1.0, 1.0), 1.0);
	}
	const settled = glyphAtlas.rasterizations;
	const generated = glyphAtlas.outlineRasterizations;
	for (let step = 4; step < 64; step++) {
		const text = placeLabel(index, trs2d((step as float32) * 0.25, 0.0, 0.0, 1.0, 1.0), 1.0);
		assert text.placedValid;
	}
	assert glyphAtlas.rasterizations == settled;
	assert glyphAtlas.outlineRasterizations == generated;
	releaseLabelText(index);
}

test "a zero width, a clear colour and no setting place no outline tile at all" {
	const index = shaped("none", 13.0);
	const before = glyphAtlas.outlineRasterizations;
	assert outlineTiles(index) == 0;
	setLabelOutline(index, 0.0, RED);
	assert outlineTiles(index) == 0;
	setLabelOutline(index, 2.0, CLEAR);
	const clear = placeLabel(index, trs2d(0.0, 0.0, 0.0, 1.0, 1.0), 1.0);
	assert (clear.placedOutline.length as int32) == 0;
	assert glyphAtlas.outlineRasterizations == before;
	setLabelOutline(index, 2.0, RED);
	const shown = placeLabel(index, trs2d(0.0, 0.0, 0.0, 1.0, 1.0), 1.0);
	assert (shown.placedOutline.length as int32) == 4;
	setLabelOutline(index, 0.0, RED);
	assert outlineTiles(index) == 0;
	releaseLabelText(index);
}

test "a rotated label places its outline tiles at the device size of its fill" {
	const index = shaped("Rot", 13.0);
	setLabelOutline(index, 2.0, RED);
	const world: Transform2D = trs2d(0.0, 0.0, 0.5, 2.0, 2.0);
	const text = placeLabel(index, world, 1.0);
	assert text.regime == TextRegime.Bitmap;
	assert (text.placedOutline.length as int32) == 3;
	const fill = glyphAtlas.tile(text.placed[0].tile);
	const outline = glyphAtlas.tile(text.placedOutline[0].tile);
	assert laneOf(outline.key) == 16;
	assert outline.width >= fill.width + 8;
	assert outline.height >= fill.height + 8;
	releaseLabelText(index);
}

test "an outline wider than the lane is refused by name and reported once" {
	const index = shaped("wide", 13.0);
	setLabelOutline(index, 70.0, RED);
	const refusals = glyphRefusals();
	const reports = glyphRefusalReports();
	const at = trs2d(0.0, 0.0, 0.0, 1.0, 1.0);
	assert !placeLabel(index, at, 1.0).placedValid;
	assert glyphRefusals() == refusals + 1 && glyphRefusalReports() == reports + 1;
	placeLabel(index, at, 1.0);
	assert glyphRefusals() == refusals + 2 && glyphRefusalReports() == reports + 1;
	assert AtlasError.OutlineTooWide.toString() == "OutlineTooWide";
	assert (labelTexts[index].placedOutline.length as int32) == 0;
	assert (labelTexts[index].placed.length as int32) == 4;
	releaseLabelText(index);
}

test "the node setter stores the width and colour on the label" {
	const n = s.label("node", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	const payload: int32 = n.scene.payloads[n.id.index];
	n.setOutline(2.5, RED);
	assert labelTexts[payload].outlineWidth == 2.5;
	assert labelTexts[payload].outlineColor.r == 1.0;
	n.setOutline(0.0, RED);
	assert labelTexts[payload].outlineWidth == 0.0;
	n.dispose();
}

when (voidSprites) {
	test "a sprite glyph draws no outline and the font glyphs beside it still do" {
		const index = shaped("a\u{2588}b\u{2588}", 13.0);
		setLabelOutline(index, 2.0, RED);
		const text = placeLabel(index, trs2d(0.0, 0.0, 0.0, 1.0, 1.0), 1.0);
		assert text.placedValid;
		assert (text.placed.length as int32) == 4;
		assert (text.placedOutline.length as int32) == 2;
		releaseLabelText(index);
	}
}

when (voidSdfText) {
	test "a turned label places an SDF outline tile per glyph at the width in texels" {
		setSdfRegime(true);
		defer setSdfRegime(false);
		const index = shaped("Turned", 13.0);
		setLabelOutline(index, 2.0, RED);
		const text = placeLabel(index, trs2d(0.0, 0.0, 0.5, 1.0, 1.0), 1.0);
		assert text.regime == TextRegime.Sdf;
		assert text.placedValid;
		assert (text.placedOutline.length as int32) == 6;
		for (const p of text.placedOutline) {
			const tile = glyphAtlas.tile(p.tile);
			assert glyphAtlas.pageKind(tile.page) == PageKind.Sdf;
			assert laneOf(tile.key) == 39;
		}
		const larger = shaped("Big", 26.0);
		setLabelOutline(larger, 2.0, RED);
		const big = placeLabel(larger, trs2d(0.0, 0.0, 0.5, 1.0, 1.0), 1.0);
		assert (big.placedOutline.length as int32) == 3;
		for (const p of big.placedOutline) {
			assert laneOf(glyphAtlas.tile(p.tile).key) == 20;
		}
		releaseLabelText(larger);
		releaseLabelText(index);
	}

	test "a zoom sweep generates no outline tile after the first frame and a width change one set" {
		setSdfRegime(true);
		defer setSdfRegime(false);
		const index = shaped("zoom", 13.0);
		setLabelOutline(index, 2.0, RED);
		placeLabel(index, trs2d(0.0, 0.0, 0.0, 1.5, 1.5), 1.0);
		const settled = glyphAtlas.outlineRasterizations;
		const coverage = glyphAtlas.rasterizations;
		for (let step = 0; step < 40; step++) {
			const zoom: float32 = 1.1 + (step as float32) * 0.07;
			const text = placeLabel(index, trs2d(0.0, 0.0, 0.0, zoom, zoom), 1.0);
			assert text.placedValid && text.regime == TextRegime.Sdf;
		}
		assert glyphAtlas.outlineRasterizations == settled;
		assert glyphAtlas.rasterizations == coverage;
		setLabelOutline(index, 3.0, RED);
		placeLabel(index, trs2d(0.0, 0.0, 0.0, 2.0, 2.0), 1.0);
		assert glyphAtlas.outlineRasterizations == settled + 3;
		releaseLabelText(index);
	}

	test "a label at translation only keeps the pixel-exact outline under the SDF regime" {
		setSdfRegime(true);
		defer setSdfRegime(false);
		const index = shaped("flat", 13.0);
		setLabelOutline(index, 2.0, RED);
		const text = placeLabel(index, trs2d(0.0, 0.0, 0.0, 1.0, 1.0), 1.0);
		assert text.regime == TextRegime.PixelExact;
		for (const p of text.placedOutline) {
			assert glyphAtlas.pageKind(glyphAtlas.tile(p.tile).page) == PageKind.Coverage;
		}
		releaseLabelText(index);
	}
}
