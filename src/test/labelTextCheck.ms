import { Align, TextRun, Truncate } from "../void2d/textLayout";
import { DEFAULT_FONT, fontFace } from "../void2d/font";
import { decorationMetrics, glyphLookups } from "../void2d/face";
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
	labelTexts,
	setLabelRuns,
	DecorationKind,
} from "../void2d/labelText";
import { quantizeX, snapBaseline } from "../void2d/glyphAtlas";
import { Transform2D, trs2d, rgba, identity2d } from "../void2d/types";
import { begin2d, frameEnd } from "../void2d/draw";
import { label, setTextRuns } from "../void2d/node";
import { renderTargetsAlive, segmentBox } from "../void2d/render";
import { approx } from "./helpers";

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
	assert text.pixelExact;
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
	assert !text.pixelExact;
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

test "drawing a label fences its glyph page for the frame the bracket belongs to" {
	begin2d(200.0, 100.0, 1.0);
	const frame = glyphAtlas.frame;
	const n = label("fence", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	n.sync(identity2d(), false);
	n.draw(1.0, 200.0, 100.0);
	const page = glyphAtlas.tile(placeLabel(n.payload, n.cachedWorld, 1.0).placed[0].tile).page;
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
		underline: CLEAR, wavy: false, strikethrough: CLEAR,
	};
}

test "run decorations: a background fills the line box, lines sit on the face's metrics" {
	const index = allocateLabelText();
	const runs: TextRun[] = [
		{ ...plainRun(3), background: rgba(0.0, 0.0, 1.0, 1.0) },
		{ ...plainRun(3), underline: rgba(0.0, 1.0, 0.0, 1.0), wavy: true },
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
		{ ...plainRun(2), color: rgba(0.8, 0.5, 1.0, 1.0), underline: squiggle, wavy: true },
		{ ...plainRun(3), underline: squiggle, wavy: true },
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
	const cells = label("", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	cells.setForceWidth(10.0);
	assert cells.calcTextWidth("abc") == 30.0;
	const text: string = "aa bb cc dd";
	const n = label("", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	n.maxWidth = n.calcTextWidth("aa bb") + 1.0;
	assert n.splitText(text) == "aa bb\ncc dd";
	n.setHangingIndent(n.calcTextWidth("aa "));
	assert n.splitText(text) == "aa bb\ncc\ndd";
	cells.dispose();
	n.dispose();
}

test "setTextRuns styles a label, and each placed glyph carries its run" {
	const n = label("ab", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	const runs: TextRun[] = [plainRun(1), plainRun(1)];
	n.setTextRuns(runs);
	n.sync(identity2d(), false);
	assert n.textWidth() > 0.0;
	const placed = placeLabel(n.payload, identity2d(), 1.0).placed;
	assert placed[0].run == 0 && placed[1].run == 1;
	n.dispose();
}

test "a label wraps again on a width change without looking a glyph up" {
	const n = label("aa bb cc dd", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	n.maxWidth = 400.0;
	n.sync(identity2d(), false);
	const one: float32 = n.textHeight();
	const before: uint32 = glyphLookups();
	n.maxWidth = 30.0;
	const many: float32 = n.textHeight();
	assert glyphLookups() == before;
	assert many > one;
	n.dispose();
}

test "a label's line options reach its layout, and its hit tests read it" {
	const n = label("aa bb cc dd", 13.0, rgba(1.0, 1.0, 1.0, 1.0));
	n.maxWidth = 30.0;
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
