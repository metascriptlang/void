import { NodeRef, Scene2D, setFont, setSelectionRange, setTextRuns } from "../void2d/node";
import "../void2d/scene";
import { textWidth } from "../void2d/render";
import { DecorationKind, labelTexts, setLabelSelection } from "../void2d/labelText";
import { TextRun, setTextShaping, textShapingOn } from "../void2d/textLayout";
import { FontId, addFont } from "../void2d/font";
import { Color, rgba } from "../void2d/types";
import { approx } from "./helpers";

const MIXED: string = "abc \u{5D0}\u{5D1}\u{5D2} def";
const SELECTED: Color = rgba(0.3, 0.5, 0.9, 0.5);

function hebrewFont(): FontId {
	const added = addFont("tests/fonts/notoSansHebrewSubset.ttf");
	if (added.ok) { return added.value; }
	console.log("the Hebrew subset did not load");
	unreachable;
}

function plainShaping(): boolean {
	const was: boolean = textShapingOn();
	setTextShaping(false);
	return was;
}

function labelOf(s: Scene2D, text: string): NodeRef {
	const n = s.label(text, 16.0, rgba(1.0, 1.0, 1.0, 1.0));
	n.setFont(hebrewFont());
	return n;
}

function payloadOf(n: NodeRef): int32 { return n.scene.payloads[n.id.index]; }

function spansOf(n: NodeRef, row: int32): Vec<float32> {
	n.textWidth();
	const entry = labelTexts[payloadOf(n)];
	let out: Vec<float32> = new Array(0);
	for (let s = entry.selectionRowFirst[row]; s < entry.selectionRowFirst[row + 1]; s++) {
		out.push(entry.selectionSpans[s]);
	}
	return out;
}

test "a selection across a direction change is two rectangles on one row" {
	const was = plainShaping();
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const n = labelOf(s, MIXED);
	n.setSelectionRange({ start: 5, length: 4 }, SELECTED);
	const spans = spansOf(n, 0);
	assert (spans.length as int32) == 4;
	const layout = n.textLayout();
	const blockLeft: float32 = layout.glyphs[6].x;
	assert approx(spans[0], blockLeft);
	assert approx(spans[1], layout.glyphs[5].x + layout.glyphs[5].advance);
	assert approx(spans[2], layout.glyphs[7].x);
	assert approx(spans[3], layout.glyphs[8].x + layout.glyphs[8].advance);
	assert spans[1] < layout.glyphs[4].x + layout.glyphs[4].advance;
	assert spans[1] <= spans[2];
	n.dispose();
	setTextShaping(was);
}

test "a selection inside one run of a mixed row is one rectangle" {
	const was = plainShaping();
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const n = labelOf(s, MIXED);
	n.setSelectionRange({ start: 4, length: 3 }, SELECTED);
	const spans = spansOf(n, 0);
	assert (spans.length as int32) == 2;
	const layout = n.textLayout();
	assert approx(spans[0], layout.glyphs[6].x);
	assert approx(spans[1], layout.glyphs[4].x + layout.glyphs[4].advance);
	n.dispose();
	setTextShaping(was);
}

test "a selection of left-to-right text is the one span it was" {
	const was = plainShaping();
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const n = labelOf(s, "abc def");
	n.setSelectionRange({ start: 2, length: 3 }, SELECTED);
	const spans = spansOf(n, 0);
	assert (spans.length as int32) == 2;
	const layout = n.textLayout();
	assert spans[0] == layout.glyphs[2].x && spans[1] == layout.glyphs[5].x;
	n.dispose();
	setTextShaping(was);
}

test "a selected line break shows its tail on the paragraph-end side" {
	const was = plainShaping();
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const rtl = labelOf(s, "\u{5D0}\u{5D1}\u{5D2}\nabc");
	rtl.setSelectionRange({ start: 0, length: 4 }, SELECTED);
	const rtlSpans = spansOf(rtl, 0);
	assert (rtlSpans.length as int32) == 2;
	assert approx(rtlSpans[0], -4.0) && approx(rtlSpans[1], rtl.textLayout().lines[0].width);
	const ltr = labelOf(s, "abc\n\u{5D0}\u{5D1}\u{5D2}");
	ltr.setSelectionRange({ start: 0, length: 4 }, SELECTED);
	const ltrSpans = spansOf(ltr, 0);
	assert (ltrSpans.length as int32) == 2;
	assert approx(ltrSpans[0], 0.0) && approx(ltrSpans[1], ltr.textLayout().lines[0].width + 4.0);
	rtl.dispose();
	ltr.dispose();
	setTextShaping(was);
}

test "run decorations are walked in visual order, so a reflected run gets two segments" {
	const was = plainShaping();
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const font = hebrewFont();
	const n = labelOf(s, "ab \u{5D0}\u{5D1}\u{5D2} cd");
	const clear: Color = rgba(0.0, 0.0, 0.0, 0.0);
	const first: Color = rgba(1.0, 0.0, 0.0, 1.0);
	const second: Color = rgba(0.0, 1.0, 0.0, 1.0);
	const third: Color = rgba(0.0, 0.0, 1.0, 1.0);
	const runs: TextRun[] = [
		{ len: 4, font: font, color: clear, background: first, underline: clear, wavy: false,
			strikethrough: clear },
		{ len: 1, font: font, color: clear, background: second, underline: clear, wavy: false,
			strikethrough: clear },
		{ len: 4, font: font, color: clear, background: third, underline: clear, wavy: false,
			strikethrough: clear },
	];
	n.setTextRuns(runs);
	n.textWidth();
	const boxes = labelTexts[payloadOf(n)].decorations;
	let backgrounds: Vec<Color> = new Array(0);
	let lefts: Vec<float32> = new Array(0);
	for (const d of boxes) {
		if (d.kind != DecorationKind.Background) { continue; }
		backgrounds.push(d.color);
		lefts.push(d.x);
	}
	assert (backgrounds.length as int32) == 5;
	assert backgrounds[0].r == 1.0 && backgrounds[1].b == 1.0 && backgrounds[2].g == 1.0;
	assert backgrounds[3].r == 1.0 && backgrounds[4].b == 1.0;
	for (let i = 1; i < 5; i++) { assert lefts[i] > lefts[i - 1]; }
	n.dispose();
	setTextShaping(was);
}
