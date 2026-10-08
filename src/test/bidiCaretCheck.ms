import {
	Align,
	LineOptions,
	PLAIN_LINES,
	ShapedText,
	TextLayout,
	TextStyle,
	indexAt,
	lineBoxAt,
	setTextShaping,
	slotLevels,
	splitAt,
	textShapingOn,
	wrapText,
	xForIndex,
} from "../void2d/textLayout";
import { TextDirection } from "../void2d/textDirection";
import { FontId, addFont } from "../void2d/font";
import { approx } from "./helpers";
import { shapedIn } from "./layoutHelpers";

const MIXED: string = "abc \u{5D0}\u{5D1}\u{5D2} def";
const HEBREW_PHRASE: string = "\u{5D0}\u{5D1}\u{5D2} \u{5D3}\u{5D4}\u{5D5} \u{5D6}\u{5D7}\u{5D8}";

function hebrewFont(): FontId {
	const added = addFont("tests/fonts/notoSansHebrewSubset.ttf");
	if (added.ok) { return added.value; }
	console.log("the Hebrew subset did not load");
	unreachable;
}

function styleOf(font: FontId, maxWidth: float32): TextStyle {
	return {
		font: font, size: 16.0, letterSpacing: 0.0, lineSpacing: 0.0, maxWidth: maxWidth,
		align: Align.Left,
	};
}

function plainShaping(): boolean {
	const was: boolean = textShapingOn();
	setTextShaping(false);
	return was;
}

function laidIn(text: string, style: TextStyle, direction: TextDirection): TextLayout {
	return wrapText(shapedIn(text, style, direction), style, PLAIN_LINES);
}

function rightEdge(shaped: ShapedText, i: int32, first: int32, end: int32): float32 {
	const left: float32 = shaped.glyphs[first].x;
	const right: float32 = shaped.glyphs[end - 1].x + shaped.glyphs[end - 1].advance;
	return left + right - shaped.glyphs[i].x;
}

function holdsRoundTrip(l: TextLayout): boolean {
	let ok: boolean = true;
	for (const line of l.lines) {
		for (let k = line.firstGlyph; k < line.firstGlyph + line.glyphCount; k++) {
			if (!l.glyphs[k].clusterStart) { continue; }
			const index: int32 = l.glyphs[k].index;
			if (l.lineBoxAt(index).top != line.top) { continue; }
			if (l.indexAt(l.xForIndex(index), line.top + 1.0) != index) { ok = false; }
		}
		if (l.indexAt(l.xForIndex(line.indexEnd), line.top + 1.0) != line.indexEnd) { ok = false; }
	}
	return ok;
}

test "the strong caret of a left-to-right paragraph at each kind of boundary" {
	const was = plainShaping();
	const style = styleOf(hebrewFont(), 0.0);
	const whole = shapedIn(MIXED, style, TextDirection.Auto);
	const l = wrapText(whole, style, PLAIN_LINES);
	assert approx(l.xForIndex(3), whole.glyphs[3].x);
	assert approx(l.xForIndex(4), whole.glyphs[4].x);
	assert approx(l.xForIndex(5), rightEdge(whole, 5, 4, 7));
	assert approx(l.xForIndex(7), whole.glyphs[7].x);
	assert approx(l.xForIndex(8), whole.glyphs[8].x);
	assert approx(l.xForIndex(11), l.lines[0].width);
	assert approx(l.xForIndex(0), 0.0);
	setTextShaping(was);
}

test "the strong caret of a right-to-left paragraph starts at the right and ends at the left" {
	const was = plainShaping();
	const style = styleOf(hebrewFont(), 0.0);
	const l = laidIn(HEBREW_PHRASE, style, TextDirection.Auto);
	assert approx(l.xForIndex(0), l.lines[0].width);
	assert approx(l.xForIndex(11), 0.0);
	assert l.xForIndex(1) < l.xForIndex(0) && l.xForIndex(2) < l.xForIndex(1);
	setTextShaping(was);
}

test "indexAt returns the logical boundary whose strong caret is nearest" {
	const was = plainShaping();
	const style = styleOf(hebrewFont(), 0.0);
	const l = laidIn(MIXED, style, TextDirection.Auto);
	const y: float32 = 1.0;
	assert l.indexAt(l.xForIndex(5) + 0.4, y) == 5;
	assert l.indexAt(l.xForIndex(6) - 0.4, y) == 6;
	assert l.indexAt(-20.0, y) == 0;
	assert l.indexAt(l.lines[0].width + 20.0, y) == 11;
	setTextShaping(was);
}

test "indexAt of xForIndex gives the index back at every boundary of mixed lines" {
	const was = plainShaping();
	const font = hebrewFont();
	assert holdsRoundTrip(laidIn(MIXED, styleOf(font, 0.0), TextDirection.Auto));
	assert holdsRoundTrip(laidIn(HEBREW_PHRASE, styleOf(font, 0.0), TextDirection.Auto));
	assert holdsRoundTrip(laidIn("abc \u{5D0}\u{5D1} def", styleOf(font, 0.0), TextDirection.Rtl));
	assert holdsRoundTrip(laidIn("abc  \u{5D0}\u{5D1}  ", styleOf(font, 0.0), TextDirection.Auto));
	const whole = shapedIn(HEBREW_PHRASE, styleOf(font, 0.0), TextDirection.Auto);
	const room: float32 = whole.glyphs[6].x + whole.glyphs[6].advance + 1.0;
	assert holdsRoundTrip(laidIn(HEBREW_PHRASE, styleOf(font, room), TextDirection.Auto));
	setTextShaping(was);
}

test "an x exactly between two strong carets goes to the later index, as on the plain path" {
	const was = plainShaping();
	const l = laidIn(MIXED, styleOf(hebrewFont(), 0.0), TextDirection.Auto);
	let ties: int32 = 0;
	for (let i = 0; i < 3; i++) {
		const a: float32 = l.xForIndex(i);
		const b: float32 = l.xForIndex(i + 1);
		const middle: float32 = a + (b - a) * 0.5;
		if (middle - a != b - middle) { continue; }
		ties = ties + 1;
		assert l.indexAt(middle, 1.0) == i + 1;
	}
	assert ties > 0;
	setTextShaping(was);
}

test "two boundaries on one x are not told apart: the click goes to the later boundary" {
	const was = plainShaping();
	const l = laidIn("\u{5D0}1", styleOf(hebrewFont(), 0.0), TextDirection.Ltr);
	assert l.xForIndex(0) == l.xForIndex(1);
	assert approx(l.xForIndex(0), 0.0);
	assert l.indexAt(0.0, 1.0) == 1;
	assert l.indexAt(l.xForIndex(0), 1.0) != 0;
	setTextShaping(was);
}

test "a left-to-right run in a right-to-left paragraph answers like the plain path" {
	const was = plainShaping();
	const font = hebrewFont();
	const plain = laidIn("abc def", styleOf(font, 0.0), TextDirection.Auto);
	const forced = laidIn("abc def", styleOf(font, 0.0), TextDirection.Rtl);
	assert (plain.bidi.levels.length as int32) == 0 && (forced.bidi.levels.length as int32) > 0;
	for (let i = 1; i < 6; i++) {
		assert approx(forced.xForIndex(i), plain.xForIndex(i));
		assert forced.indexAt(plain.xForIndex(i), 1.0) == plain.indexAt(plain.xForIndex(i), 1.0);
		const between: float32 = (plain.xForIndex(i) + plain.xForIndex(i + 1)) * 0.5;
		assert forced.indexAt(between + 0.3, 1.0) == plain.indexAt(between + 0.3, 1.0);
		assert forced.indexAt(between - 0.3, 1.0) == plain.indexAt(between - 0.3, 1.0);
	}
	setTextShaping(was);
}

test "splitAt of a bidi line cuts at a logical index and reorders each half" {
	const was = plainShaping();
	const style = styleOf(hebrewFont(), 0.0);
	const whole = shapedIn(MIXED, style, TextDirection.Auto);
	const l = wrapText(whole, style, PLAIN_LINES);
	const halves = l.splitAt(4);
	const left = halves[0];
	const right = halves[1];
	assert (left.glyphs.length as int32) == 4 && (right.glyphs.length as int32) == 7;
	for (let i = 0; i < 4; i++) { assert approx(left.glyphs[i].x, whole.glyphs[i].x); }
	const heb: float32 = whole.glyphs[6].x + whole.glyphs[6].advance - whole.glyphs[4].x;
	assert approx(right.glyphs[0].x, heb - right.glyphs[0].advance);
	assert approx(right.glyphs[2].x, 0.0);
	assert approx(right.glyphs[3].x, heb);
	assert right.slotLevels(0)[0] == 1 && right.slotLevels(0)[3] == 0;
	assert right.bidi.lineLevels[0] == 0 && left.bidi.lineLevels[0] == 0;
	setTextShaping(was);
}

test "splitAt inside a Hebrew run gives each half its own reflection" {
	const was = plainShaping();
	const style = styleOf(hebrewFont(), 0.0);
	const whole = shapedIn(HEBREW_PHRASE, style, TextDirection.Auto);
	const l = wrapText(whole, style, PLAIN_LINES);
	const halves = l.splitAt(5);
	const left = halves[0];
	const right = halves[1];
	assert (left.glyphs.length as int32) == 5;
	assert left.bidi.lineLevels[0] == 1 && right.bidi.lineLevels[0] == 1;
	assert left.glyphs[0].x > left.glyphs[4].x && approx(left.glyphs[4].x, 0.0);
	assert right.glyphs[0].x > right.glyphs[5].x && approx(right.glyphs[5].x, 0.0);
	assert approx(right.glyphs[0].x + right.glyphs[0].advance, right.lines[0].width);
	setTextShaping(was);
}

test "a click past either end of a right-to-left line lands on its logical end and start" {
	const was = plainShaping();
	const l = laidIn(HEBREW_PHRASE, styleOf(hebrewFont(), 0.0), TextDirection.Auto);
	assert l.indexAt(-20.0, 1.0) == l.lines[0].indexEnd;
	assert l.indexAt(l.lines[0].width + 20.0, 1.0) == 0;
	setTextShaping(was);
}

test "the empty line after a final newline of a right-to-left paragraph answers a caret" {
	const was = plainShaping();
	const l = laidIn("\u{5D0}\u{5D1}\n", styleOf(hebrewFont(), 0.0), TextDirection.Auto);
	assert (l.lines.length as int32) == 2;
	const last = l.lines[1];
	assert l.lineBoxAt(last.indexStart).top == last.top;
	assert l.indexAt(0.0, last.top + 1.0) == last.indexStart;
	assert l.indexAt(l.xForIndex(last.indexStart), last.top + 1.0) == last.indexStart;
	setTextShaping(was);
}

test "digits in a right-to-left paragraph run left to right, strong carets at their edges" {
	const was = plainShaping();
	const l = laidIn("\u{5D0} 123 \u{5D1}", styleOf(hebrewFont(), 0.0), TextDirection.Auto);
	assert l.xForIndex(5) < l.xForIndex(3) && l.xForIndex(3) < l.xForIndex(4);
	assert l.xForIndex(4) < l.xForIndex(2) && l.xForIndex(2) < l.xForIndex(1);
	assert holdsRoundTrip(l);
	setTextShaping(was);
}

test "an aligned mixed line keeps its carets on the drawn glyphs" {
	const was = plainShaping();
	const font = hebrewFont();
	for (const align of [Align.Right, Align.Center]) {
		const style: TextStyle = { ...styleOf(font, 300.0), align: align };
		const l = laidIn(MIXED, style, TextDirection.Auto);
		assert l.lines[0].x > 0.0;
		assert approx(l.xForIndex(0), l.lines[0].x);
		assert approx(l.xForIndex(11), l.lines[0].x + l.lines[0].width);
		assert holdsRoundTrip(l);
		const rtl = laidIn(HEBREW_PHRASE, style, TextDirection.Auto);
		assert approx(rtl.xForIndex(0), rtl.lines[0].x + rtl.lines[0].width);
		assert holdsRoundTrip(rtl);
	}
	setTextShaping(was);
}
