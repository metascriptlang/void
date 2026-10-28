import { Align, NO_GLYPH, TextRun, TextStyle, Truncate, UnderlineStyle } from "../void2d/textLayout";
import { DEFAULT_FONT, FontId, addFont, fontFace } from "../void2d/font";
import {
	decorationMetrics, faceMetrics, glyphAdvance, glyphIndex, glyphInkBox, glyphLookups,
} from "../void2d/face";

when (voidSprites) {
	import { spriteCellFor } from "../void2d/font";
	import { isSpriteFace } from "../void2d/face";
}

import {
	allocateLabelText,
	releaseLabelText,
	shapeLabel,
	placeLabel,
	glyphAtlas,
	glyphRasterizations,
	glyphRefusals,
	glyphRefusalReports,
	isPixelExact,
	TextRegime,
	labelTexts,
	setLabelRuns,
	setLabelLines,
	setLabelCellWidths,
	labelLines,
	DecorationKind,
} from "../void2d/labelText";
import { quantizeX, snapBaseline } from "../void2d/glyphAtlas";
import { Transform2D, trs2d, rgba, identity2d, emptyBounds } from "../void2d/types";
import { begin2d, frameEnd } from "../void2d/draw";
import { Changed, NodeRef, Scene2D } from "../void2d/node";
import "../void2d/scene";
import { renderTargetsAlive, segmentBox } from "../void2d/render";
import { approx } from "./helpers";
import { nodeSplit, nodeWidth } from "./nodeTextHelpers";

const s: Scene2D = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));

function payloadOf(n: NodeRef): int32 { return n.scene.payloads[n.id.index]; }

function shaped(text: string): int32 {
	return shapedAt(text, 13.0);
}

function shapedAt(text: string, size: float32): int32 {
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

function isWhole(v: float32): boolean {
	return v == (Math.floor(v) as float32);
}

test "pixel-exact placement puts every glyph sprite on whole device pixels" {
	const index = shaped("void2d, 13 px");
	const world: Transform2D = trs2d(10.3, 7.7, 0.0, 1.0, 1.0);
	const text = placeLabel(index, world, 1.25);
	assert text.regime == TextRegime.PixelExact;
	assert (text.placed.length as int32) > 0;
	for (const p of text.placed) {
		assert isWhole(p.x);
		assert isWhole(p.y);
		assert isWhole(p.w);
		assert isWhole(p.h);
	}
	releaseLabelText(index);
}

test "the placement uses the same quarter-pixel variant and snapped baseline the atlas keys on" {
	const index = shaped("iiii");
	const world: Transform2D = trs2d(0.0, 0.0, 0.0, 1.0, 1.0);
	const text = placeLabel(index, world, 1.5);
	const g = text.layout.glyphs[1];
	const q = quantizeX(g.x * 1.5);
	const baseline = snapBaseline(text.layout.lines[0].baseline * 1.5);
	const tile = glyphAtlas.tile(text.placed[1].tile);
	assert text.placed[1].x == ((q.whole + tile.left) as float32);
	assert text.placed[1].y == ((baseline + tile.top) as float32);
	releaseLabelText(index);
}

test "a whole-pixel move reuses the placement and rasterizes nothing" {
	const index = shaped("steady state");
	placeLabel(index, trs2d(4.25, 3.0, 0.0, 1.0, 1.0), 1.0);
	const before = glyphRasterizations();
	const moved = placeLabel(index, trs2d(9.25, 12.0, 0.0, 1.0, 1.0), 1.0);
	assert glyphRasterizations() == before;
	assert moved.key.fracX == 0.25;
	releaseLabelText(index);
}

test "a rotated label is the transformed regime, sized by the affine's area scale" {
	const index = shaped("A");
	const world: Transform2D = trs2d(0.0, 0.0, 0.5, 2.0, 2.0);
	assert !isPixelExact(world);
	const text = placeLabel(index, world, 1.0);
	assert text.regime == TextRegime.Bitmap;
	const tile = glyphAtlas.tile(text.placed[0].tile);
	assert Math.abs(text.placed[0].w * 2.0 - (tile.width as float32)) < 0.001;
	releaseLabelText(index);
}

test "releasing a label drops its tile references" {
	const index = shaped("Qz");
	const text = placeLabel(index, trs2d(0.0, 0.0, 0.0, 1.0, 1.0), 1.0);
	const tileIndex = text.placed[0].tile;
	const held = glyphAtlas.tile(tileIndex).refs;
	releaseLabelText(index);
	assert glyphAtlas.tile(tileIndex).refs == held - 1;
}

test "a label that leaves its parent releases its tiles and places them again when added back" {
	begin2d(200.0, 100.0, 1.0);
	const parent = s.group();
	const box = parent.addChild(s.group());
	const n = box.addChild(s.label("Qz", 13.0, rgba(1.0, 1.0, 1.0, 1.0)));
	parent.sync(identity2d(), true);
	parent.draw(1.0, 200.0, 100.0);
	assert (labelTexts[payloadOf(n)].placed.length as int32) > 0;
	const tileIndex = labelTexts[payloadOf(n)].placed[0].tile;
	const held = glyphAtlas.tile(tileIndex).refs;
	parent.removeChild(box);
	assert (labelTexts[payloadOf(n)].placed.length as int32) == 0;
	assert glyphAtlas.tile(tileIndex).refs == held - 1;
	parent.addChild(box);
	parent.sync(identity2d(), true);
	parent.draw(1.0, 200.0, 100.0);
	assert glyphAtlas.tile(tileIndex).refs == held;
	parent.removeChildren();
	assert glyphAtlas.tile(tileIndex).refs == held - 1;
	frameEnd();
	n.dispose();
}

test "drawing a label fences its glyph page for the frame the bracket belongs to" {
	begin2d(200.0, 100.0, 1.0);
	const frame = glyphAtlas.frame;
	const n = s.label("fence", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	n.sync(identity2d(), false);
	n.draw(1.0, 200.0, 100.0);
	const placed = placeLabel(payloadOf(n), n.scene.worlds[n.id.index], 1.0).placed;
	const page = glyphAtlas.tile(placed[0].tile).page;
	assert glyphAtlas.pages[page as int32].drawnFrame == frame;
	frameEnd();
	begin2d(200.0, 100.0, 1.0);
	assert glyphAtlas.frame == frame + 1;
	n.dispose();
}

test "a placement that loses a glyph stays invalid, is retried, and is reported once per label" {
	const oversized: float32 = 3000.0;
	const first = shapedAt("W ", oversized);
	const second = shapedAt("M ", oversized);
	const refusals = glyphRefusals();
	const reports = glyphRefusalReports();
	const at = trs2d(0.0, 0.0, 0.0, 1.0, 1.0);
	assert !placeLabel(first, at, 1.0).placedValid;
	assert glyphRefusals() == refusals + 1 && glyphRefusalReports() == reports + 1;
	placeLabel(first, at, 1.0);
	assert glyphRefusals() == refusals + 2 && glyphRefusalReports() == reports + 1;
	placeLabel(second, at, 1.0);
	assert glyphRefusals() == refusals + 3 && glyphRefusalReports() == reports + 2;
	releaseLabelText(first);
	releaseLabelText(second);
}

const CLEAR = rgba(0.0, 0.0, 0.0, 0.0);

function plainRun(len: int32): TextRun {
	return {
		len: len, font: DEFAULT_FONT, color: rgba(1.0, 1.0, 1.0, 1.0), background: CLEAR,
		underline: CLEAR, strikethrough: CLEAR,
	};
}

function shapedFourRuns(): int32 {
	const index = shaped("abcdefgh");
	setLabelRuns(index, [plainRun(2), plainRun(2), plainRun(2), plainRun(2)]);
	shapeLabel(index, "abcdefgh", labelTexts[index].style);
	return index;
}

test "pending reshape survives four runs becoming three and an alike update" {
	const index = shapedFourRuns();
	const entry = labelTexts[index];
	const blue = rgba(0.0, 0.0, 1.0, 1.0);
	const runs: TextRun[] = [plainRun(3), plainRun(3), { ...plainRun(2), background: blue }];
	assert setLabelRuns(index, runs);
	assert setLabelRuns(index, runs);
	assert entry.reshape && entry.layout.glyphs[7].run == 3;
	shapeLabel(index, "abcdefgh", entry.style);
	assert !entry.reshape && entry.layout.glyphs[7].run == 2;
	assert (entry.decorations.length as int32) == 1;
	assert entry.decorations[0].color == blue;
	assert entry.decorations[0].x == entry.layout.glyphs[6].x;
	releaseLabelText(index);
}

test "pending reshape survives four runs becoming two then three and an alike update" {
	const index = shapedFourRuns();
	const entry = labelTexts[index];
	assert setLabelRuns(index, [plainRun(4), plainRun(4)]);
	const runs: TextRun[] = [plainRun(3), plainRun(3), plainRun(2)];
	assert setLabelRuns(index, runs);
	assert setLabelRuns(index, runs);
	assert entry.reshape && entry.layout.glyphs[7].run == 3;
	shapeLabel(index, "abcdefgh", entry.style);
	assert !entry.reshape;
	assert entry.layout.glyphs[2].run == 0 && entry.layout.glyphs[3].run == 1;
	assert entry.layout.glyphs[5].run == 1 && entry.layout.glyphs[6].run == 2;
	assert entry.layout.glyphs[7].run == 2;
	releaseLabelText(index);
}

test "an alike run update after reshaping stays paint only" {
	const index = shapedFourRuns();
	const entry = labelTexts[index];
	assert setLabelRuns(index, [plainRun(3), plainRun(3), plainRun(2)]);
	shapeLabel(index, "abcdefgh", entry.style);
	const lookups: uint32 = glyphLookups();
	const blue = rgba(0.0, 0.0, 1.0, 1.0);
	const runs: TextRun[] = [{ ...plainRun(3), background: blue }, plainRun(3), plainRun(2)];
	assert !setLabelRuns(index, runs);
	assert !entry.reshape && glyphLookups() == lookups;
	assert entry.layout.glyphs[7].run == 2;
	assert (entry.decorations.length as int32) == 1;
	assert entry.decorations[0].color == blue;
	assert approx(entry.decorations[0].w,
		entry.layout.glyphs[2].x + entry.layout.glyphs[2].advance - entry.layout.glyphs[0].x);
	releaseLabelText(index);
}

function samePlaced(a: int32, b: int32): boolean {
	const x = labelTexts[a].placed;
	const y = labelTexts[b].placed;
	if (x.length != y.length) { return false; }
	for (let i = 0; i < (x.length as int32); i++) {
		if (x[i].tile != y[i].tile || x[i].x != y[i].x || x[i].y != y[i].y) { return false; }
		if (x[i].w != y[i].w || x[i].h != y[i].h || x[i].run != y[i].run) { return false; }
		if (x[i].u0 != y[i].u0 || x[i].v1 != y[i].v1) { return false; }
	}
	return true;
}

function placedFresh(text: string, runs: TextRun[], world: Transform2D, scale: float32): int32 {
	const index = shaped(text);
	setLabelRuns(index, runs);
	shapeLabel(index, text, labelTexts[index].style);
	placeLabel(index, world, scale);
	return index;
}

function markPlaced(index: int32): void {
	for (let i = 0; i < (labelTexts[index].placed.length as int32); i++) {
		labelTexts[index].placed[i].u0 = -1.0;
	}
}

function markedOf(index: int32): int32 {
	let marked: int32 = 0;
	for (const p of labelTexts[index].placed) {
		if (p.u0 == -1.0) { marked = marked + 1; }
	}
	return marked;
}

test "an edit places only its line again and the placement equals a fresh one" {
	const world: Transform2D = trs2d(4.25, 3.5, 0.0, 1.0, 1.0);
	const index = placedFresh("alpha\nbeta\ngamma", [plainRun(16)], world, 1.25);
	const gammaTile = labelTexts[index].placed[9].tile;
	const held = glyphAtlas.tile(gammaTile).refs;
	const betaTile = labelTexts[index].placed[5].tile;
	const heldBeta = glyphAtlas.tile(betaTile).refs;
	markPlaced(index);
	const runs: TextRun[] = [plainRun(3), plainRun(14)];
	setLabelRuns(index, runs);
	shapeLabel(index, "alpha\nbetas\ngamma", labelTexts[index].style);
	placeLabel(index, world, 1.25);
	assert markedOf(index) == 5;
	assert labelTexts[index].placed[10].u0 == -1.0 && labelTexts[index].placed[10].run == 1;
	assert glyphAtlas.tile(gammaTile).refs == held;
	const fresh = placedFresh("alpha\nbetas\ngamma", runs, world, 1.25);
	for (let i = 10; i < 15; i++) { labelTexts[index].placed[i].u0 = labelTexts[fresh].placed[i].u0; }
	assert samePlaced(index, fresh);
	releaseLabelText(fresh);
	releaseLabelText(index);
	assert glyphAtlas.tile(gammaTile).refs == held - 1;
	assert glyphAtlas.tile(betaTile).refs == heldBeta - 1;
}

test "a new line moves the lines below it and they are placed again where they now sit" {
	const world: Transform2D = trs2d(0.0, 0.0, 0.0, 1.0, 1.0);
	const index = placedFresh("alpha\nbeta\ngamma", [plainRun(16)], world, 1.0);
	markPlaced(index);
	setLabelRuns(index, [plainRun(20)]);
	shapeLabel(index, "alpha\nbeta\nnew\ngamma", labelTexts[index].style);
	placeLabel(index, world, 1.0);
	assert markedOf(index) == 9;
	const fresh = placedFresh("alpha\nbeta\nnew\ngamma", [plainRun(20)], world, 1.0);
	for (let i = 0; i < 9; i++) { labelTexts[index].placed[i].u0 = labelTexts[fresh].placed[i].u0; }
	assert samePlaced(index, fresh);
	releaseLabelText(fresh);
	releaseLabelText(index);
}

test "a line that wraps into more rows moves the next line down, which is placed again" {
	const world: Transform2D = trs2d(0.0, 0.0, 0.0, 1.0, 1.0);
	const index = shaped("alpha\nbeta");
	const style: TextStyle = { ...labelTexts[index].style, maxWidth: 60.0 };
	shapeLabel(index, "alpha\nbeta", style);
	placeLabel(index, world, 1.0);
	markPlaced(index);
	shapeLabel(index, "alpha alpha alpha\nbeta", style);
	placeLabel(index, world, 1.0);
	assert markedOf(index) == 0;
	const fresh = shaped("alpha alpha alpha\nbeta");
	shapeLabel(fresh, "alpha alpha alpha\nbeta", style);
	placeLabel(fresh, world, 1.0);
	assert samePlaced(index, fresh);
	releaseLabelText(fresh);
	releaseLabelText(index);
}

test "run decorations: a background fills the line box, lines sit on the face's metrics" {
	const index = allocateLabelText();
	const runs: TextRun[] = [
		{ ...plainRun(3), background: rgba(0.0, 0.0, 1.0, 1.0) },
		{ ...plainRun(3), underline: rgba(0.0, 1.0, 0.0, 1.0), underlineStyle: UnderlineStyle.Wavy },
		{ ...plainRun(2), strikethrough: rgba(1.0, 0.0, 0.0, 1.0) },
	];
	setLabelRuns(index, runs);
	shapeLabel(index, "abcdefgh", {
		font: DEFAULT_FONT,
		size: 13.0,
		letterSpacing: 0.0,
		lineSpacing: 0.0,
		maxWidth: 0.0,
		align: Align.Left,
	});
	const e = labelTexts[index];
	const g = e.layout.glyphs;
	const line = e.layout.lines[0];
	const deco = decorationMetrics(fontFace(DEFAULT_FONT), 13.0);
	assert (e.decorations.length as int32) == 3;
	assert e.decorations[0].kind == DecorationKind.Background;
	assert e.decorations[0].x == g[0].x && e.decorations[0].y == line.top;
	assert approx(e.decorations[0].w, g[2].x + g[2].advance - g[0].x);
	assert e.decorations[0].h == line.height;
	assert e.decorations[1].kind == DecorationKind.WavyUnderline;
	assert e.decorations[1].x == g[3].x;
	assert approx(e.decorations[1].y, line.baseline + deco.underlineTop);
	assert e.decorations[1].h == deco.underlineThickness;
	assert e.decorations[2].kind == DecorationKind.Strikethrough;
	assert approx(e.decorations[2].y, line.baseline + deco.strikethroughTop);
	assert g[7].run == 2 && g[0].run == 0;
	releaseLabelText(index);
}

test "a decoration runs on across the runs that share it, as GPUI's does" {
	const index = allocateLabelText();
	const squiggle = rgba(1.0, 0.2, 0.2, 1.0);
	const runs: TextRun[] = [
		{ ...plainRun(2), color: rgba(0.8, 0.5, 1.0, 1.0), underline: squiggle, underlineStyle: UnderlineStyle.Wavy },
		{ ...plainRun(3), underline: squiggle, underlineStyle: UnderlineStyle.Wavy },
		{ ...plainRun(2), underline: squiggle },
		plainRun(1),
	];
	setLabelRuns(index, runs);
	shapeLabel(index, "abcdefgh", {
		font: DEFAULT_FONT,
		size: 13.0,
		letterSpacing: 0.0,
		lineSpacing: 0.0,
		maxWidth: 0.0,
		align: Align.Left,
	});
	const e = labelTexts[index];
	const g = e.layout.glyphs;
	assert (e.decorations.length as int32) == 2;
	assert e.decorations[0].kind == DecorationKind.WavyUnderline;
	assert approx(e.decorations[0].w, g[4].x + g[4].advance - g[0].x);
	assert e.decorations[1].kind == DecorationKind.Underline && e.decorations[1].x == g[5].x;
	releaseLabelText(index);
}

test "a styled underline keeps its kind and pattern cell, an overline sits on the ascent" {
	const index = allocateLabelText();
	const ink = rgba(0.0, 1.0, 0.0, 1.0);
	const runs: TextRun[] = [
		{ ...plainRun(2), underline: ink, underlineStyle: UnderlineStyle.Double },
		{ ...plainRun(2), underline: ink, underlineStyle: UnderlineStyle.Dotted },
		{ ...plainRun(2), underline: ink, underlineStyle: UnderlineStyle.Wavy },
		{ ...plainRun(2), overline: ink },
	];
	setLabelRuns(index, runs);
	shapeLabel(index, "abcdefgh", {
		font: DEFAULT_FONT,
		size: 13.0,
		letterSpacing: 0.0,
		lineSpacing: 0.0,
		maxWidth: 0.0,
		align: Align.Left,
	});
	const e = labelTexts[index];
	const line = e.layout.lines[0];
	const face = fontFace(DEFAULT_FONT);
	const deco = decorationMetrics(face, 13.0);
	assert (e.decorations.length as int32) == 4;
	assert e.decorations[0].kind == DecorationKind.DoubleUnderline;
	assert approx(e.decorations[0].y, line.baseline + deco.underlineTop - deco.underlineThickness);
	assert approx(e.decorations[0].h, deco.underlineThickness * 3.0);
	assert e.decorations[0].cell == 0.0;
	assert e.decorations[1].kind == DecorationKind.DottedUnderline;
	assert approx(e.decorations[1].cell, glyphAdvance(face, glyphIndex(face, "0".code), 13.0));
	assert e.decorations[2].kind == DecorationKind.WavyUnderline;
	assert e.decorations[3].kind == DecorationKind.Overline;
	assert approx(e.decorations[3].y, line.baseline - faceMetrics(face, 13.0).ascent);
	assert e.decorations[3].h == deco.underlineThickness;

	setLabelLines(index, { ...labelLines(index), forceWidth: 10.0 });
	setLabelRuns(index, [{ ...plainRun(8), underline: ink, underlineStyle: UnderlineStyle.Dashed }]);
	shapeLabel(index, "abcdefgh", e.style);
	assert (labelTexts[index].decorations.length as int32) == 1;
	assert labelTexts[index].decorations[0].kind == DecorationKind.DashedUnderline;
	assert labelTexts[index].decorations[0].cell == 10.0;
	releaseLabelText(index);
}

test "a decoration lands on device pixels at DPI 1.25, a stroke at least one pixel thick" {
	const world = trs2d(0.0, 0.0, 0.0, 1.0, 1.0);
	const [x, y, w, h] = segmentBox(10.3, 50.3, 20.1, 0.5, true, world, 1.25);
	assert approx(x * 1.25, 13.0) && approx((x + w) * 1.25, 63.0);
	assert approx(y * 1.25, 25.0) && approx(h * 1.25, 1.0);
	const [bx, by, bw, bh] = segmentBox(10.3, 50.3, 20.1, 16.2, false, world, 1.25);
	assert approx(by * 1.25, 25.0) && approx((by + bh) * 1.25, 45.0);
	assert approx(bx * 1.25, 13.0) && approx(bw * 1.25, 50.0);
}

test "calcTextWidth and splitText lay other text out with the label's line options" {
	const cells = s.label("", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	cells.setForceWidth(10.0);
	assert nodeWidth(cells, "abc") == 30.0;
	const text: string = "aa bb cc dd";
	const n = s.label("", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	n.setMaxWidth(nodeWidth(n, "aa bb") + 1.0);
	assert nodeSplit(n, text) == "aa bb\ncc dd";
	n.setHangingIndent(nodeWidth(n, "aa "));
	assert nodeSplit(n, text) == "aa bb\ncc\ndd";
	cells.dispose();
	n.dispose();
}

function gridLabel(text: string, widths: Readonly<Span<uint8>>, maxWidth: float32): int32 {
	const index = allocateLabelText();
	setLabelLines(index, { ...labelLines(index), forceWidth: 10.0 });
	setLabelCellWidths(index, widths);
	shapeLabel(index, text, {
		font: DEFAULT_FONT,
		size: 13.0,
		letterSpacing: 0.0,
		lineSpacing: 0.0,
		maxWidth: maxWidth,
		align: Align.Left,
	});
	return index;
}

test "a wide cell of the grid takes two cells of a forced-width label" {
	const widths: uint8[] = [2, 0, 0, 2, 0, 0, 1];
	const index = gridLabel("\u{4F60}\u{597D}a", widths, 0.0);
	const g = labelTexts[index].layout.glyphs;
	assert (g.length as int32) == 3;
	assert g[0].x == 0.0 && g[1].x == 20.0 && g[2].x == 40.0;
	assert g[0].advance == 20.0 && g[1].advance == 20.0 && g[2].advance == 10.0;
	assert labelTexts[index].layout.lines[0].width == 50.0;
	releaseLabelText(index);
}

test "a forced-width label wraps by the grid's cell widths" {
	const widths: uint8[] = [2, 0, 0, 2, 0, 0, 1];
	const index = gridLabel("\u{4F60}\u{597D}a", widths, 35.0);
	const l = labelTexts[index].layout;
	assert (l.lines.length as int32) == 2;
	assert l.glyphs[1].line == 1 && l.glyphs[1].x == 0.0 && l.glyphs[2].x == 20.0;
	releaseLabelText(index);
}

test "cell widths that do not cover the text leave one cell per cluster" {
	const widths: uint8[] = [2, 0, 0];
	const index = gridLabel("\u{4F60}\u{597D}a", widths, 0.0);
	const g = labelTexts[index].layout.glyphs;
	assert g[1].x == 10.0 && g[2].x == 20.0;
	releaseLabelText(index);
}

test "a run background over trailing spaces stays inside the label's bounds" {
	const n = s.label("ab  ", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	const runs: TextRun[] = [{ ...plainRun(4), background: rgba(0.0, 0.0, 1.0, 1.0) }];
	n.setTextRuns(runs);
	n.sync(identity2d(), false);
	let bounds = emptyBounds();
	n.getBounds(bounds);
	const spaces = n.textLayout().glyphs[3];
	assert spaces.x + spaces.advance <= bounds.xMax;
	n.dispose();
}

test "setTextRuns styles a label, and each placed glyph carries its run" {
	const n = s.label("ab", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	const runs: TextRun[] = [plainRun(1), plainRun(1)];
	n.setTextRuns(runs);
	n.sync(identity2d(), false);
	assert n.textWidth() > 0.0;
	const placed = placeLabel(payloadOf(n), identity2d(), 1.0).placed;
	assert placed[0].run == 0 && placed[1].run == 1;
	n.dispose();
}

test "a run change that keeps each run's length and font repaints without shaping again" {
	const n = s.label("abcd", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	const green = rgba(0.0, 1.0, 0.0, 1.0);
	const before: TextRun[] = [plainRun(2), { ...plainRun(2), underline: green }];
	n.setTextRuns(before);
	n.sync(identity2d(), false);
	s.clearChanges();
	const lookups: uint32 = glyphLookups();
	const red = rgba(1.0, 0.0, 0.0, 1.0);
	const after: TextRun[] = [{ ...plainRun(2), color: red }, { ...plainRun(2), underline: red }];
	n.setTextRuns(after);
	const e = labelTexts[payloadOf(n)];
	assert !e.stale && !e.reshape;
	assert s.changed[n.id.index].has(Changed.Paint) && !s.changed[n.id.index].has(Changed.Text);
	assert e.runs[0].color == red;
	assert (e.decorations.length as int32) == 1 && e.decorations[0].color == red;
	n.sync(identity2d(), false);
	assert glyphLookups() == lookups;
	n.dispose();
}

function hebrewFont(): FontId {
	const added = addFont("tests/fonts/notoSansHebrewSubset.ttf");
	if (added.ok) { return added.value; }
	console.log("the Hebrew subset did not load");
	unreachable;
}

test "a run change of a length or a font shapes the label again" {
	const n = s.label("abcd", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	const halves: TextRun[] = [plainRun(2), plainRun(2)];
	n.setTextRuns(halves);
	n.sync(identity2d(), false);
	s.clearChanges();
	const lengths: TextRun[] = [plainRun(1), plainRun(3)];
	n.setTextRuns(lengths);
	assert labelTexts[payloadOf(n)].reshape && s.changed[n.id.index].has(Changed.Text);
	n.sync(identity2d(), false);
	s.clearChanges();
	const fonts: TextRun[] = [plainRun(1), { ...plainRun(3), font: hebrewFont() }];
	n.setTextRuns(fonts);
	assert labelTexts[payloadOf(n)].reshape && s.changed[n.id.index].has(Changed.Text);
	n.dispose();
}

function inkHeld(n: NodeRef): boolean {
	const layout = n.textLayout();
	let xMin: float32 = 0.0;
	let xMax: float32 = 0.0;
	for (const line of layout.lines) {
		if (line.x < xMin) { xMin = line.x; }
		if (line.x + line.width > xMax) { xMax = line.x + line.width; }
	}
	let yMin: float32 = 0.0;
	let yMax: float32 = layout.height;
	for (const g of layout.glyphs) {
		if (g.glyph == NO_GLYPH) { continue; }
		const [left, top, right, bottom] = glyphInkBox(g.face, g.glyph, g.size);
		if (right <= left || bottom <= top) { continue; }
		const baseline: float32 = layout.lines[g.line].baseline + g.offsetY;
		const penX: float32 = g.x + g.offsetX;
		if (penX + left < xMin) { xMin = penX + left; }
		if (penX + right > xMax) { xMax = penX + right; }
		if (baseline + top < yMin) { yMin = baseline + top; }
		if (baseline + bottom > yMax) { yMax = baseline + bottom; }
	}
	const b = n.scene.bounds[n.id.index];
	return approx(b.xMin, xMin) && approx(b.yMin, yMin) && approx(b.xMax, xMax) &&
		approx(b.yMax, yMax);
}

test "a label's bounds hold the ink of every glyph on its aligned rows, across an edit" {
	const n = s.label("jolly\n\nzeta\nbeta gamma delta epsilon", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	n.setTextAlign(Align.Center);
	n.setMaxWidth(80.0);
	n.sync(identity2d(), false);
	assert inkHeld(n);
	n.setText("jolly\n\nzeta\nbeta gamma delta epsilon eta theta");
	n.sync(identity2d(), false);
	assert inkHeld(n);
	n.setText("jolly\nbeta\n\nzeta");
	n.sync(identity2d(), false);
	assert inkHeld(n);
	n.dispose();
}

test "a label wraps again on a width change without looking a glyph up" {
	const n = s.label("aa bb cc dd", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	n.setMaxWidth(400.0);
	n.sync(identity2d(), false);
	const one: float32 = n.textHeight();
	const before: uint32 = glyphLookups();
	n.setMaxWidth(30.0);
	const many: float32 = n.textHeight();
	assert glyphLookups() == before;
	assert many > one;
	n.dispose();
}

test "a label's line options reach its layout, and its hit tests read it" {
	const n = s.label("aa bb cc dd", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	n.setMaxWidth(30.0);
	n.setHangingIndent(6.0);
	n.sync(identity2d(), false);
	assert n.textLayout().lines[1].x == 6.0;
	assert n.lineBoxAt(3).top == n.textLayout().lines[1].top;
	assert n.indexAt(0.0, n.textLayout().lines[1].top + 1.0) == 3;
	assert n.xForIndex(3) == 6.0;
	n.setTruncate(Truncate.End);
	const truncated = n.textLayout();
	assert (truncated.lines.length as int32) == 1;
	assert truncated.glyphs[(truncated.glyphs.length as int32) - 1].codepoint == 0x2026;
	n.dispose();
}

when (voidSprites) {
	function spacedLabel(text: string, letterSpacing: float32): int32 {
		const index = allocateLabelText();
		shapeLabel(index, text, {
			font: DEFAULT_FONT,
			size: 13.0,
			letterSpacing: letterSpacing,
			lineSpacing: 0.0,
			maxWidth: 0.0,
			align: Align.Left,
		});
		return index;
	}

	function fracOf(value: float32): float32 {
		return value - (Math.floor(value) as float32);
	}

	function variantOf(key: uint64): uint64 {
		return key & (15 as uint64);
	}

	test "a sprite glyph is placed on a whole pixel with variant 0 whatever the pen fraction" {
		const index = spacedLabel("a\u{2588}b\u{2588}c\u{2800}d\u{2593}", 0.37);
		const world: Transform2D = trs2d(0.3, 0.4, 0.0, 1.0, 1.0);
		const text = placeLabel(index, world, 1.25);
		assert text.regime == TextRegime.PixelExact;
		assert text.placed.length == text.layout.glyphs.length;
		let spriteGlyphs: int32 = 0;
		let fractional: int32 = 0;
		for (let i = 0; i < (text.placed.length as int32); i++) {
			const g = text.layout.glyphs[i];
			const tile = glyphAtlas.tile(text.placed[i].tile);
			if (isSpriteFace(g.face)) {
				spriteGlyphs = spriteGlyphs + 1;
				assert variantOf(tile.key) == (0 as uint64);
				const pen: float32 = fracOf(world.tx * 1.25) + g.x * 1.25;
				assert text.placed[i].x == ((snapBaseline(pen) + tile.left) as float32);
			} else if (variantOf(tile.key) != (0 as uint64)) {
				fractional = fractional + 1;
			}
		}
		assert spriteGlyphs == 4;
		assert fractional > 0;
		releaseLabelText(index);
	}

	test "a label of sprites rasterizes each sprite once and nothing on a whole-pixel move" {
		const index = spacedLabel("\u{2588}\u{2588}\u{2588}\u{2800}\u{2500}\u{2500}", 0.0);
		const world: Transform2D = trs2d(0.0, 0.0, 0.0, 1.0, 1.0);
		const before = glyphRasterizations();
		const text = placeLabel(index, world, 1.0);
		assert glyphRasterizations() - before <= 3;
		const after = glyphRasterizations();
		placeLabel(index, trs2d(5.0, 3.0, 0.0, 1.0, 1.0), 1.0);
		assert glyphRasterizations() == after;
		assert text.refused == 0;
		releaseLabelText(index);
	}

	const SEAM_ROWS: int32 = 3;
	const SEAM_COLUMNS: int32 = 7;

	function seamLabel(text: string, forceWidth: float32, lineSpacing: float32): int32 {
		const index = allocateLabelText();
		setLabelLines(index, { ...labelLines(index), forceWidth: forceWidth });
		shapeLabel(index, text, {
			font: DEFAULT_FONT,
			size: 14.0,
			letterSpacing: 0.0,
			lineSpacing: lineSpacing,
			maxWidth: 0.0,
			align: Align.Left,
		});
		return index;
	}

	function seamBlock(): string {
		const row: string = "\u{2588}\u{2588}\u{2588}\u{2588}\u{2588}\u{2588}\u{2588}";
		return row + "\n" + row + "\n" + row;
	}

	test "sprite cells of a forced-width label join with no gap at every DPI, across and down" {
		const primary = fontFace(DEFAULT_FONT);
		const metrics = faceMetrics(primary, 14.0);
		const lineHeight: float32 = metrics.ascent + metrics.descent + metrics.lineGap;
		const scales: float32[] = [1.0, 1.25, 1.5];
		for (const dpl of scales) {
			const cell = spriteCellFor(DEFAULT_FONT, 14.0 * dpl);
			const pitch: float32 = (cell.height as float32) / dpl;
			const index = seamLabel(seamBlock(), (cell.width as float32) / dpl, pitch - lineHeight);
			const text = placeLabel(index, trs2d(8.0, 8.0, 0.0, 1.0, 1.0), dpl);
			assert text.placedValid;
			assert (text.placed.length as int32) == SEAM_ROWS * SEAM_COLUMNS;
			for (let r = 0; r < SEAM_ROWS; r++) {
				for (let c = 0; c < SEAM_COLUMNS; c++) {
					const at: int32 = r * SEAM_COLUMNS + c;
					const p = text.placed[at];
					assert p.w == (cell.width as float32) && p.h == (cell.height as float32);
					if (c + 1 < SEAM_COLUMNS) {
						assert text.placed[at + 1].x == p.x + p.w;
						assert text.placed[at + 1].y == p.y;
					}
					if (r + 1 < SEAM_ROWS) {
						assert text.placed[at + SEAM_COLUMNS].y == p.y + p.h;
						assert text.placed[at + SEAM_COLUMNS].x == p.x;
					}
				}
			}
			releaseLabelText(index);
		}
	}

	test "a sprite takes its cell even when its advance is within a pixel of the grid" {
		const cell = spriteCellFor(DEFAULT_FONT, 14.0 * 1.25);
		const index = seamLabel(seamBlock(), (cell.width as float32) / 1.25, 0.0);
		const text = placeLabel(index, trs2d(8.0, 8.0, 0.0, 1.0, 1.0), 1.25);
		for (let c = 0; c < SEAM_COLUMNS; c++) {
			assert text.layout.glyphs[c].x == (c as float32) * ((cell.width as float32) / 1.25);
		}
		releaseLabelText(index);
	}
}
