import { Scene2D } from "../void2d/node";
import "../void2d/scene";
import { setTextDirection, textDirection, setFont } from "../void2d/node";
import { textLayout } from "../void2d/render";
import {
	Align,
	LineOptions,
	PLAIN_LINES,
	ShapedText,
	TextErrorKind,
	TextLayout,
	TextStyle,
	Truncate,
	setTextShaping,
	textShapingOn,
	wrapText,
} from "../void2d/textLayout";
import { TextDirection } from "../void2d/textDirection";
import { FontId, addFont, fontFace } from "../void2d/font";
import { glyphIndex } from "../void2d/face";
import { rgba } from "../void2d/types";
import { approx } from "./helpers";
import { shapedIn } from "./layoutHelpers";

const HEBREW_FACE: string = "tests/fonts/notoSansHebrewSubset.ttf";
const ALEF_BET_GIMEL: string = "\u{5D0}\u{5D1}\u{5D2}";

function hebrewFont(): FontId {
	const added = addFont(HEBREW_FACE);
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

function restoreShaping(was: boolean): void {
	setTextShaping(was);
}

function laidIn(
	text: string, style: TextStyle, direction: TextDirection, options: LineOptions,
): TextLayout {
	return wrapText(shapedIn(text, style, direction), style, options);
}

function reflected(shaped: ShapedText, first: int32, end: int32, i: int32): float32 {
	const left: float32 = shaped.glyphs[first].x;
	const right: float32 = shaped.glyphs[end - 1].x + shaped.glyphs[end - 1].advance;
	return left + right - (shaped.glyphs[i].x + shaped.glyphs[i].advance);
}

test "text with no right-to-left codepoint keeps empty levels and its logical pen" {
	const was = plainShaping();
	const font = hebrewFont();
	const style = styleOf(font, 0.0);
	const shaped = shapedIn("abc def", style, TextDirection.Auto);
	assert (shaped.bidi.levels.length as int32) == 0;
	const l = wrapText(shaped, style, PLAIN_LINES);
	assert (l.bidi.levels.length as int32) == 0 && (l.bidi.lineLevels.length as int32) == 0;
	for (let i = 0; i < (l.glyphs.length as int32); i++) {
		assert l.glyphs[i].x == shaped.glyphs[i].x;
	}
	restoreShaping(was);
}

test "a Hebrew word alone is a right-to-left paragraph and its slots are reflected" {
	const was = plainShaping();
	const style = styleOf(hebrewFont(), 0.0);
	const shaped = shapedIn(ALEF_BET_GIMEL, style, TextDirection.Auto);
	assert shaped.bidi.paragraphs[0] == 1;
	const l = wrapText(shaped, style, PLAIN_LINES);
	for (let i = 0; i < 3; i++) {
		assert approx(l.glyphs[i].x, reflected(shaped, 0, 3, i));
		assert l.slotLevels(0)[i] == 1;
	}
	assert l.glyphs[0].x > l.glyphs[1].x && l.glyphs[1].x > l.glyphs[2].x;
	assert approx(l.glyphs[0].x + l.glyphs[0].advance, l.lines[0].width);
	assert approx(l.glyphs[2].x, 0.0);
	assert l.bidi.lineLevels[0] == 1;
	restoreShaping(was);
}

test "a Hebrew run inside a left-to-right paragraph is reflected inside its own extent" {
	const was = plainShaping();
	const style = styleOf(hebrewFont(), 0.0);
	const shaped = shapedIn("abc \u{5D0}\u{5D1}\u{5D2} def", style, TextDirection.Auto);
	assert shaped.bidi.paragraphs[0] == 0;
	const l = wrapText(shaped, style, PLAIN_LINES);
	for (let i = 0; i < 11; i++) {
		if (i >= 4 && i <= 6) {
			assert approx(l.glyphs[i].x, reflected(shaped, 4, 7, i));
			assert l.slotLevels(0)[i] == 1;
		} else {
			assert l.glyphs[i].x == shaped.glyphs[i].x;
			assert l.slotLevels(0)[i] == 0;
		}
	}
	restoreShaping(was);
}

test "a forced right-to-left paragraph puts the Hebrew letter left of the Latin word" {
	const was = plainShaping();
	const style = styleOf(hebrewFont(), 0.0);
	const shaped = shapedIn("abc \u{5D0}", style, TextDirection.Rtl);
	assert shaped.bidi.paragraphs[0] == 1;
	const l = wrapText(shaped, style, PLAIN_LINES);
	assert l.slotLevels(0)[0] == 2 && l.slotLevels(0)[3] == 1 && l.slotLevels(0)[4] == 1;
	assert l.glyphs[4].x < l.glyphs[3].x && l.glyphs[3].x < l.glyphs[0].x;
	assert l.glyphs[0].x < l.glyphs[1].x && l.glyphs[1].x < l.glyphs[2].x;
	restoreShaping(was);
}

test "a left-to-right run alone in a right-to-left paragraph keeps its pen" {
	const was = plainShaping();
	const style = styleOf(hebrewFont(), 0.0);
	const shaped = shapedIn("abc (def)", style, TextDirection.Rtl);
	const l = wrapText(shaped, style, PLAIN_LINES);
	for (let i = 0; i < 9; i++) {
		assert l.slotLevels(0)[i] == 2;
		assert approx(l.glyphs[i].x, shaped.glyphs[i].x);
	}
	restoreShaping(was);
}

test "each wrapped line gets L1 and L2 of its own, so a split Hebrew phrase reads right to left" {
	const was = plainShaping();
	const font = hebrewFont();
	const text: string = "\u{5D0}\u{5D1}\u{5D2} \u{5D3}\u{5D4}\u{5D5} \u{5D6}\u{5D7}\u{5D8}";
	const whole = shapedIn(text, styleOf(font, 0.0), TextDirection.Auto);
	const room: float32 = whole.glyphs[6].x + whole.glyphs[6].advance + 1.0;
	const l = laidIn(text, styleOf(font, room), TextDirection.Auto, PLAIN_LINES);
	assert (l.lines.length as int32) == 2;
	assert l.bidi.lineLevels[0] == 1 && l.bidi.lineLevels[1] == 1;
	assert approx(l.glyphs[0].x + l.glyphs[0].advance, l.lines[0].width);
	assert approx(l.glyphs[7].x + l.glyphs[7].advance, l.lines[1].width);
	assert l.glyphs[0].x > l.glyphs[6].x;
	assert l.glyphs[7].x > l.glyphs[9].x;
	assert approx(l.glyphs[9].x, 0.0);
	restoreShaping(was);
}

test "L1 puts a space that ends a wrapped line back at the paragraph level, after the Hebrew run" {
	const was = plainShaping();
	const font = hebrewFont();
	const text: string = "abc \u{5D0}\u{5D1}\u{5D2}  \u{5D3}\u{5D4}";
	const whole = shapedIn(text, styleOf(font, 0.0), TextDirection.Auto);
	const room: float32 = whole.glyphs[9].x + 1.0;
	const l = laidIn(text, styleOf(font, room), TextDirection.Auto, PLAIN_LINES);
	assert (l.lines.length as int32) == 2;
	assert l.slotLevels(0)[7] == 0 && l.slotLevels(0)[4] == 1;
	assert approx(l.glyphs[7].x, whole.glyphs[7].x);
	for (let i = 4; i < 7; i++) {
		assert approx(l.glyphs[i].x, reflected(whole, 4, 7, i));
	}
	restoreShaping(was);
}

test "trailing whitespace hangs on the paragraph-end side of each direction" {
	const was = plainShaping();
	const font = hebrewFont();
	const hebrew = shapedIn("\u{5D0}\u{5D1}\u{5D2}  ", styleOf(font, 0.0), TextDirection.Auto);
	const rtl = wrapText(hebrew, styleOf(font, 0.0), PLAIN_LINES);
	const space: float32 = hebrew.glyphs[3].advance;
	assert approx(rtl.glyphs[3].x, -space);
	assert approx(rtl.glyphs[4].x, (-2.0 as float32) * space);
	assert approx(rtl.lines[0].width, hebrew.glyphs[2].x + hebrew.glyphs[2].advance);
	const latin = shapedIn("abc  ", styleOf(font, 0.0), TextDirection.Auto);
	const ltr = wrapText(latin, styleOf(font, 0.0), PLAIN_LINES);
	assert ltr.glyphs[3].x == latin.glyphs[3].x && ltr.glyphs[4].x == latin.glyphs[4].x;
	restoreShaping(was);
}

test "Truncate.End puts the ellipsis at the paragraph end, the left of a Hebrew paragraph" {
	const was = plainShaping();
	const font = hebrewFont();
	const options: LineOptions = { ...PLAIN_LINES, truncate: Truncate.End };
	const hebrew: string = "\u{5D0}\u{5D1}\u{5D2}\u{5D3}\u{5D4}\u{5D5}\u{5D6}\u{5D7}";
	const room: float32 = shapedIn(hebrew, styleOf(font, 0.0), TextDirection.Auto).glyphs[4].x;
	const l = laidIn(hebrew, styleOf(font, room), TextDirection.Auto, options);
	const last: int32 = (l.glyphs.length as int32) - 1;
	assert l.glyphs[last].codepoint == 0x2026;
	for (let i = 0; i < last; i++) { assert l.glyphs[last].x < l.glyphs[i].x; }
	const latin = laidIn("abcdefgh", styleOf(font, room), TextDirection.Auto, options);
	const end: int32 = (latin.glyphs.length as int32) - 1;
	assert latin.glyphs[end].codepoint == 0x2026;
	for (let i = 0; i < end; i++) { assert latin.glyphs[end].x > latin.glyphs[i].x; }
	restoreShaping(was);
}

test "forceWidth puts a reordered line on the grid, mirrored" {
	const was = plainShaping();
	const options: LineOptions = { ...PLAIN_LINES, forceWidth: 10.0 };
	const l = laidIn(ALEF_BET_GIMEL, styleOf(hebrewFont(), 0.0), TextDirection.Auto, options);
	assert Math.abs(l.glyphs[0].x - 20.0) < 1.0 && Math.abs(l.glyphs[1].x - 10.0) < 1.0;
	assert Math.abs(l.glyphs[2].x) < 1.0;
	assert l.glyphs[0].x > l.glyphs[1].x && l.glyphs[1].x > l.glyphs[2].x;
	assert l.lines[0].width == 30.0;
	restoreShaping(was);
}

test "tab stops are measured on the logical pen, so the line is as wide as its logical layout" {
	const was = plainShaping();
	const font = hebrewFont();
	const text: string = "\u{5D0}\u{5D1}\t\u{5D2}";
	const shaped = shapedIn(text, styleOf(font, 0.0), TextDirection.Auto);
	const l = wrapText(shaped, styleOf(font, 0.0), PLAIN_LINES);
	assert approx(l.lines[0].width, shaped.glyphs[3].x + shaped.glyphs[3].advance);
	assert approx(l.glyphs[2].advance, shaped.glyphs[2].advance);
	restoreShaping(was);
}

test "a paired bracket in an odd-level run is drawn with its mirror glyph" {
	const was = plainShaping();
	const font = hebrewFont();
	const face: int32 = fontFace(font);
	const rtl = laidIn("\u{5D0}(\u{5D1})", styleOf(font, 0.0), TextDirection.Auto, PLAIN_LINES);
	assert rtl.glyphs[1].codepoint == 0x28 && rtl.glyphs[1].glyph == glyphIndex(face, 0x29);
	assert rtl.glyphs[3].codepoint == 0x29 && rtl.glyphs[3].glyph == glyphIndex(face, 0x28);
	const ltr = laidIn("a(b)", styleOf(font, 0.0), TextDirection.Auto, PLAIN_LINES);
	assert ltr.glyphs[1].glyph == glyphIndex(face, 0x28);
	assert ltr.glyphs[3].glyph == glyphIndex(face, 0x29);
	restoreShaping(was);
}

test "every newline-ended paragraph has its own level, the empty one after a final newline too" {
	const was = plainShaping();
	const style = styleOf(hebrewFont(), 0.0);
	const shaped = shapedIn("\u{5D0}\n", style, TextDirection.Auto);
	assert (shaped.bidi.paragraphs.length as int32) == 2;
	assert shaped.bidi.paragraphs[0] == 1 && shaped.bidi.paragraphs[1] == 0;
	const mixed = shapedIn("abc\n\u{5D0}\u{5D1}", style, TextDirection.Auto);
	assert mixed.bidi.paragraphs[0] == 0 && mixed.bidi.paragraphs[1] == 1;
	const l = wrapText(mixed, style, PLAIN_LINES);
	assert l.bidi.lineLevels[0] == 0 && l.bidi.lineLevels[1] == 1;
	restoreShaping(was);
}

test "an Arabic-script letter without the shaper is refused by name, a Hebrew letter is laid out" {
	const was = plainShaping();
	const style = styleOf(hebrewFont(), 0.0);
	const arabic = TextLayout.layout("ab\u{645}", style);
	assert !arabic.ok;
	if (!arabic.ok) {
		assert arabic.error.kind == TextErrorKind.ArabicNeedsShaper;
		assert arabic.error.index == 2;
	}
	assert TextLayout.layout(ALEF_BET_GIMEL, style).ok;
	restoreShaping(was);
}

test "a label takes its paragraph direction from setTextDirection" {
	const was = plainShaping();
	const s = Scene2D.create(rgba(0.0, 0.0, 0.0, 1.0));
	const n = s.label("abc \u{5D0}\u{5D1}", 16.0, rgba(1.0, 1.0, 1.0, 1.0));
	n.setFont(hebrewFont());
	assert n.textDirection() == TextDirection.Auto;
	assert n.textLayout().bidi.lineLevels[0] == 0;
	n.setTextDirection(TextDirection.Rtl);
	assert n.textDirection() == TextDirection.Rtl;
	assert n.textLayout().bidi.lineLevels[0] == 1;
	n.setTextDirection(TextDirection.Auto);
	assert n.textLayout().bidi.lineLevels[0] == 0;
	n.dispose();
	restoreShaping(was);
}
