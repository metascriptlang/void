import {
	glyphIndex,
	glyphAdvance,
	glyphKern,
	faceMetrics,
} from "../void2d/face";
import {
	TextLayout,
	TextStyle,
	TextRun,
	Align,
	Truncate,
	LineOptions,
	PLAIN_LINES,
	NO_GLYPH,
	layoutRuns,
	shapeText,
	wrapText,
	TAB_STOP_SPACES,
	calcTextWidth,
} from "../void2d/textLayout";
import {
	FontId,
	DEFAULT_FONT,
	FontStyle,
	SizeAdjust,
	addFont,
	resolveFont,
	fontFace,
	fallbackProbes,
} from "../void2d/font";
import { rgba } from "../void2d/types";
import { approx } from "./helpers";
import { glyphLookups } from "../void2d/face";

let loadedFont: FontId = DEFAULT_FONT;
let fontLoaded: boolean = false;

function style(): TextStyle {
	if (!fontLoaded) {
		loadedFont = try addFont("assets/font.ttf") catch DEFAULT_FONT;
		fontLoaded = true;
	}
	return {
		font: loadedFont,
		size: 13.0,
		letterSpacing: 0.0,
		lineSpacing: 0.0,
		maxWidth: 0.0,
		align: Align.Left,
	};
}

function advanceOf(codepoint: int32): float32 {
	const s = style();
	const face = fontFace(s.font);
	return glyphAdvance(face, glyphIndex(face, codepoint), 13.0);
}

function kernOf(left: int32, right: int32): float32 {
	const s = style();
	const face = fontFace(s.font);
	return glyphKern(face, glyphIndex(face, left), glyphIndex(face, right), 13.0);
}

test "a pair is laid out by float advance plus its GPOS kern, never rounded" {
	const l = TextLayout.layout("AV", style());
	const kerned: float32 = advanceOf("A".code) + kernOf("A".code, "V".code);
	const expected: float32 = kerned + advanceOf("V".code);
	assert (l.glyphs.length as int32) == 2;
	assert approx(l.glyphs[1].x, kerned);
	assert approx(l.width, expected);
	assert l.width != Math.floor(l.width);
}

test "letter spacing is added after every glyph but not after the last" {
	const spaced = TextLayout.layout("AB", { ...style(), letterSpacing: 2.0 });
	const plain = TextLayout.layout("AB", style());
	assert approx(spaced.width, plain.width + 2.0);
}

test "letter spacing goes between graphemes, never between a letter and its mark" {
	const spaced = TextLayout.layout("e\u{301}x", { ...style(), letterSpacing: 4.0 });
	const plain = TextLayout.layout("e\u{301}x", style());
	assert approx(spaced.glyphs[1].x, plain.glyphs[1].x);
	assert approx(spaced.glyphs[2].x, plain.glyphs[2].x + 4.0);
}

test "a trailing space hangs outside the line width" {
	const hung = TextLayout.layout("ab ", style());
	assert approx(hung.width, TextLayout.layout("ab", style()).width);
}

test "wrapping breaks at the last space that fits and drops it from both lines" {
	const fits: float32 = calcTextWidth("aa bb", style());
	const l = TextLayout.layout("aa bb cc", { ...style(), maxWidth: fits });
	assert (l.lines.length as int32) == 2;
	assert l.splitText("aa bb cc") == "aa bb\ncc";
	assert approx(l.lines[0].width, fits);
	assert l.glyphs[l.lines[1].firstGlyph].x == 0.0;
	assert l.glyphs[l.lines[1].firstGlyph].line == 1;
}

test "a width a hair short of the line moves the last word down" {
	const fits: float32 = calcTextWidth("aa bb", style());
	const short: float32 = fits - (0.01 as float32);
	const l = TextLayout.layout("aa bb", { ...style(), maxWidth: short });
	assert l.splitText("aa bb") == "aa\nbb";
}

test "a word wider than the box overflows on its own line rather than splitting" {
	const l = TextLayout.layout("abcdefgh ij", { ...style(), maxWidth: 5.0 });
	assert l.splitText("abcdefgh ij") == "abcdefgh\nij";
	assert l.lines[0].width > 5.0;
}

test "ideographs wrap between any two, with no space to break at" {
	const two: float32 = calcTextWidth("你好", style());
	const l = TextLayout.layout("你好世界", { ...style(), maxWidth: two });
	assert l.splitText("你好世界") == "你好\n世界";
	assert l.lines[1].charStart == 2;
}

test "a word of any alphabet stays whole, as UAX #14 keeps it" {
	const greek: string = "Ελληνικά κείμενα";
	const word: float32 = calcTextWidth("Ελληνικά", style());
	const l = TextLayout.layout(greek, { ...style(), maxWidth: word });
	assert l.splitText(greek) == "Ελληνικά\nκείμενα";
}

test "a path wraps after a slash, and closing punctuation stays on its word" {
	const path: string = "src/void2d/text";
	const fits: float32 = calcTextWidth("src/void2d", style());
	const l = TextLayout.layout(path, { ...style(), maxWidth: fits });
	assert l.splitText(path) == "src/\nvoid2d/\ntext";
	const shout: string = "ok plz!";
	const p = TextLayout.layout(shout, { ...style(), maxWidth: calcTextWidth("ok plz", style()) });
	assert p.splitText(shout) == "ok\nplz!";
}

test "calcTextWidth ignores the wrap width" {
	const wrapped: TextStyle = { ...style(), maxWidth: 5.0 };
	assert approx(calcTextWidth("aa bb", wrapped), TextLayout.layout("aa bb", style()).width);
}

test "a newline is a hard break, and a trailing one opens an empty line" {
	const l = TextLayout.layout("ab\ncd\n", style());
	assert (l.lines.length as int32) == 3;
	assert l.lines[1].charStart == 3;
	assert l.lines[2].glyphCount == 0;
	assert l.splitText("ab\ncd\n") == "ab\ncd\n";
}

test "the empty line after a trailing newline sits at the end of the text" {
	const l = TextLayout.layout("ab\n", style());
	assert (l.lines.length as int32) == 2;
	assert l.lines[1].byteStart == 3;
	assert l.lines[1].byteEnd == 3;
	assert l.lines[1].indexStart == 3 && l.lines[1].indexEnd == 3;
	assert l.indexAt(50.0, l.lines[1].top + 1.0) == 3;
	assert approx(l.xForIndex(3), l.lines[1].x);
}

test "lines advance by the line height plus lineSpacing in pixels" {
	const s: TextStyle = { ...style(), lineSpacing: 4.0 };
	const l = TextLayout.layout("a\nb", s);
	const m = faceMetrics(fontFace(s.font), 13.0);
	const lineHeight: float32 = m.ascent + m.descent + m.lineGap;
	assert approx(l.lineHeight, lineHeight);
	assert approx(l.lines[1].top, lineHeight + 4.0);
	assert approx(l.lines[1].baseline, lineHeight + 4.0 + m.ascent);
	assert approx(l.height, 2.0 * lineHeight + 4.0);
}

test "Center and Right with no maxWidth align each line about the origin, as h2d does" {
	const l = TextLayout.layout("abc\na", { ...style(), align: Align.Center });
	assert approx(l.lines[0].x, -l.lines[0].width * 0.5);
	assert approx(l.lines[1].x, -l.lines[1].width * 0.5);
	assert approx(l.glyphs[l.lines[1].firstGlyph].x, l.lines[1].x);
	const r = TextLayout.layout("abc\na", { ...style(), align: Align.Right });
	assert approx(r.lines[1].x, -r.lines[1].width);
}

test "Center and Right with a maxWidth align each line inside it" {
	const box: float32 = 200.0;
	const c = TextLayout.layout("abc\na", { ...style(), maxWidth: box, align: Align.Center });
	assert approx(c.lines[0].x, (box - c.lines[0].width) * 0.5);
	assert approx(c.lines[1].x, (box - c.lines[1].width) * 0.5);
	const r = TextLayout.layout("abc\na", { ...style(), maxWidth: box, align: Align.Right });
	assert approx(r.lines[1].x, box - r.lines[1].width);
	assert approx(r.glyphs[r.lines[1].firstGlyph].x, r.lines[1].x);
}

test "the Multiline aligns work inside the widest line" {
	const c = TextLayout.layout("abc\na", { ...style(), align: Align.MultilineCenter });
	assert approx(c.lines[0].x, 0.0);
	assert approx(c.lines[1].x, (c.width - c.lines[1].width) * 0.5);
	const r = TextLayout.layout("abc\na", { ...style(), align: Align.MultilineRight });
	assert approx(r.lines[1].x, r.width - r.lines[1].width);
	const left = TextLayout.layout("abc\na", { ...style(), align: Align.Left });
	assert left.lines[1].x == 0.0;
}

test "multi-byte text keeps byte ranges, and the caret counts UTF-16 units" {
	const l = TextLayout.layout("é漢b", style());
	assert (l.glyphs.length as int32) == 3;
	assert l.glyphs[0].codepoint == 0xE9;
	assert l.glyphs[1].codepoint == 0x6F22;
	assert l.glyphs[1].byteStart == 2;
	assert l.glyphs[1].byteEnd == 5;
	assert l.glyphs[2].charIndex == 2;
	assert l.glyphs[1].index == 1 && l.glyphs[2].index == 2;
	assert approx(l.xForIndex(1), l.glyphs[1].x);
	assert approx(l.xForIndex(3), l.width);
	assert l.indexAt(l.glyphs[2].x + 0.1, 0.0) == 2;
	assert l.indexAt(1000.0, 0.0) == 3;
}

test "splitText cuts wrapped lines by byte range, so an astral codepoint stays whole" {
	const fits: float32 = calcTextWidth("a😀 bb", style());
	const l = TextLayout.layout("a😀 bb cc", { ...style(), maxWidth: fits });
	assert (l.lines.length as int32) == 2;
	assert l.splitText("a😀 bb cc") == "a😀 bb\ncc";
}

test "an empty string is one empty line one line tall" {
	const l = TextLayout.layout("", style());
	assert (l.lines.length as int32) == 1;
	assert l.width == 0.0;
	assert approx(l.height, l.lineHeight);
}

test "a carriage return draws nothing, advances nothing and breaks the kerning pair" {
	const l = TextLayout.layout("AV\rV", style());
	assert (l.glyphs.length as int32) == 4;
	assert l.glyphs[2].glyph == NO_GLYPH && l.glyphs[2].advance == 0.0;
	assert approx(l.glyphs[3].x, l.glyphs[2].x);
	assert approx(l.glyphs[2].x, l.glyphs[1].x + advanceOf("V".code));
}

test "a tab advances to the next stop, counted in spaces from the line start" {
	const stop: float32 = (TAB_STOP_SPACES as float32) * advanceOf(32);
	const l = TextLayout.layout("ab\tc\t\td", style());
	assert l.glyphs[2].glyph == NO_GLYPH;
	assert approx(l.glyphs[3].x, stop);
	assert approx(l.glyphs[6].x, 3.0 * stop);
	assert approx(l.width, 3.0 * stop + advanceOf("d".code));
}

test "a tab already on a stop moves a whole stop, and a trailing one adds no width" {
	const stop: float32 = (TAB_STOP_SPACES as float32) * advanceOf(32);
	const l = TextLayout.layout("\t\tx\t", style());
	assert approx(l.glyphs[2].x, 2.0 * stop);
	assert approx(l.width, 2.0 * stop + advanceOf("x".code));
}

test "control characters never probe the fallback faces" {
	const id: FontId = try addFont("assets/font.ttf") catch DEFAULT_FONT;
	assert id != DEFAULT_FONT;
	const fresh: TextStyle = { ...style(), font: id };
	TextLayout.layout("x", fresh);
	const before: int32 = fallbackProbes();
	TextLayout.layout("x\t\r\u0001\u001B\u001F\u007Fx", fresh);
	assert fallbackProbes() == before;
}

function runOf(len: int32, font: FontId): TextRun {
	const clear = rgba(0.0, 0.0, 0.0, 0.0);
	return {
		len: len, font: font, color: rgba(1.0, 1.0, 1.0, 1.0), background: clear,
		underline: clear, wavy: false, strikethrough: clear,
	};
}

test "a run boundary splits the kerning pair, as a style change splits GPUI's shaping run" {
	const whole = TextLayout.layout("AV", style());
	assert whole.glyphs[1].x < advanceOf("A".code) - 0.5;
	const runs: TextRun[] = [runOf(1, style().font), runOf(1, style().font)];
	const split = layoutRuns("AV", style(), runs);
	assert approx(split.glyphs[1].x, advanceOf("A".code));
	assert split.glyphs[0].run == 0 && split.glyphs[1].run == 1;
}

test "indices count UTF-16 units, so an astral codepoint spans two" {
	const font: FontId = style().font;
	const runs: TextRun[] = [runOf(1, font), runOf(2, font), runOf(1, font)];
	const l = layoutRuns("a\u{1F600}b", style(), runs);
	assert l.glyphs[0].index == 0 && l.glyphs[1].index == 1 && l.glyphs[2].index == 3;
	assert l.glyphs[1].run == 1 && l.glyphs[2].run == 2;
	assert l.lines[0].indexStart == 0 && l.lines[0].indexEnd == 4;
}

test "a run draws in its own font" {
	const bold = resolveFont({
		family: "Inter", weight: 700, style: FontStyle.Normal, features: [], fallbacks: [],
		sizeAdjust: SizeAdjust.None,
	});
	assert bold.ok;
	if (!bold.ok) { return; }
	const runs: TextRun[] = [runOf(1, style().font), runOf(1, bold.value)];
	const l = layoutRuns("HH", style(), runs);
	assert l.glyphs[0].face == fontFace(style().font);
	assert l.glyphs[1].face == fontFace(bold.value);
}

function wrapped(text: string, width: float32, options: LineOptions): TextLayout {
	const noRuns: TextRun[] = [];
	const noBreaks: int32[] = [];
	const wide: TextStyle = { ...style(), maxWidth: width };
	return wrapText(shapeText(text, wide, noRuns, noBreaks), wide, options);
}

test "End truncation keeps what fits beside an ellipsis" {
	const room: float32 = calcTextWidth("abcde", style());
	const l = wrapped("abcdefghij", room, { ...PLAIN_LINES, truncate: Truncate.End });
	const last: int32 = (l.glyphs.length as int32) - 1;
	assert (l.lines.length as int32) == 1;
	assert l.glyphs[last].codepoint == 0x2026;
	assert l.glyphs[0].codepoint == "a".code;
	assert l.lines[0].width <= room;
	assert l.glyphs[last].index == l.glyphs[last - 1].index + 1;
}

test "truncation keeps a cluster only when its marks fit too" {
	const room: float32 = 36.0;
	const l = wrapped("ae\u{20DD}xyz", room, { ...PLAIN_LINES, truncate: Truncate.End });
	assert l.lines[0].width <= room;
}

test "End truncation trims the spaces and punctuation before its ellipsis, as GPUI does" {
	const room: float32 = calcTextWidth("hello, w", style());
	const l = wrapped("hello, world", room, { ...PLAIN_LINES, truncate: Truncate.End });
	const last: int32 = (l.glyphs.length as int32) - 1;
	assert l.glyphs[last].codepoint == 0x2026;
	assert l.glyphs[last - 1].codepoint == "o".code;
}

test "Middle truncation gives two thirds of the room to the front, as GPUI's does" {
	const room: float32 = calcTextWidth("aaaaaaaaaaaa\u{2026}", style()) + 0.5;
	const middle: LineOptions = { ...PLAIN_LINES, truncate: Truncate.Middle };
	const l = wrapped("aaaaaaaaaaaaaaaaaaaaaaaa", room, middle);
	let head: int32 = 0;
	while (l.glyphs[head].codepoint != 0x2026) { head = head + 1; }
	const tail: int32 = (l.glyphs.length as int32) - head - 1;
	assert head == 8 && tail == 4;
}

test "Start truncation keeps the end, Middle keeps both ends" {
	const room: float32 = calcTextWidth("abcde", style());
	const start = wrapped("abcdefghij", room, { ...PLAIN_LINES, truncate: Truncate.Start });
	assert start.glyphs[0].codepoint == 0x2026;
	assert start.glyphs[(start.glyphs.length as int32) - 1].codepoint == "j".code;
	assert start.lines[0].width <= room + 0.01;
	const middle = wrapped("abcdefghij", room, { ...PLAIN_LINES, truncate: Truncate.Middle });
	const count: int32 = middle.glyphs.length as int32;
	assert middle.glyphs[0].codepoint == "a".code;
	assert middle.glyphs[count - 1].codepoint == "j".code;
	let dots: int32 = 0;
	for (const g of middle.glyphs) { if (g.codepoint == 0x2026) { dots = dots + 1; } }
	assert dots == 1 && middle.lines[0].width <= room + 0.01;
	const fits = wrapped("abc", room, { ...PLAIN_LINES, truncate: Truncate.End });
	assert (fits.glyphs.length as int32) == 3;
}

test "a hanging indent moves every continuation line, not the first" {
	const room: float32 = calcTextWidth("aa bb", style());
	const l = wrapped("aa bb cc dd", room, { ...PLAIN_LINES, hangingIndent: 12.0 });
	assert (l.lines.length as int32) >= 2;
	assert l.lines[0].x == 0.0 && l.glyphs[0].x == 0.0;
	assert l.lines[1].x == 12.0;
	assert approx(l.glyphs[l.lines[1].firstGlyph].x, 12.0);
}

test "force_width puts each base on the cell grid and keeps a mark on its base" {
	const l = wrapped("ae\u0301b", 0.0, { ...PLAIN_LINES, forceWidth: 10.0 });
	assert l.glyphs[0].x == 0.0;
	assert l.glyphs[1].x == 10.0;
	assert l.glyphs[3].x == 20.0;
	const plain = TextLayout.layout("ae\u0301b", style());
	assert approx(l.glyphs[2].x - l.glyphs[1].x, plain.glyphs[2].x - plain.glyphs[1].x);
	assert l.lines[0].width == 30.0;
}

test "splitAt cuts one line without shaping it again" {
	const l = TextLayout.layout("abcdef", style());
	const [left, right] = l.splitAt(3);
	assert (left.glyphs.length as int32) == 3 && (right.glyphs.length as int32) == 3;
	assert right.glyphs[0].x == 0.0 && right.glyphs[0].codepoint == "d".code;
	assert approx(right.glyphs[1].x, l.glyphs[4].x - l.glyphs[3].x);
	assert left.lines[0].indexEnd == 3 && right.lines[0].indexStart == 3;
	assert approx(left.width + right.width, l.width);
}

test "each half of splitAt keeps the bytes of its own text" {
	const text: string = "ab€cd";
	const [left, right] = TextLayout.layout(text, style()).splitAt(3);
	assert left.splitText(text) == "ab€";
	assert right.splitText(text) == "cd";
}

test "a shaping break splits the kerning pair at its index" {
	const noRuns: TextRun[] = [];
	const breaks: int32[] = [1];
	const l = wrapText(shapeText("AV", style(), noRuns, breaks), style(), PLAIN_LINES);
	assert approx(l.glyphs[1].x, advanceOf("A".code));
}

test "a width change wraps the shaped glyphs again and looks no glyph up" {
	const noRuns: TextRun[] = [];
	const noBreaks: int32[] = [];
	const wide: TextStyle = { ...style(), maxWidth: 400.0 };
	const shaped = shapeText("aa bb cc dd ee ff", wide, noRuns, noBreaks);
	const one = wrapText(shaped, wide, PLAIN_LINES);
	const room: float32 = calcTextWidth("aa bb", style());
	const before: uint32 = glyphLookups();
	const narrow = wrapText(shaped, { ...wide, maxWidth: room }, PLAIN_LINES);
	assert glyphLookups() == before;
	assert (one.lines.length as int32) == 1 && (narrow.lines.length as int32) > 1;
}

test "a tab on a wrapped line finds its stop from that line's start" {
	const stop: float32 = (TAB_STOP_SPACES as float32) * advanceOf(32);
	const l = wrapped("aa bb\tc", calcTextWidth("aa", style()) + 1.0, PLAIN_LINES);
	const second = l.lines[1];
	const tab = l.glyphs[second.firstGlyph + 2];
	assert tab.codepoint == 9;
	assert approx(tab.x + tab.advance, stop);
}

test "the caret, the hit test and the line box agree across lines" {
	const room: float32 = calcTextWidth("aa bb", style());
	const l = wrapped("aa bb cc", room, PLAIN_LINES);
	const second = l.lines[1];
	assert second.indexStart == 6;
	assert approx(l.xForIndex(6), l.glyphs[second.firstGlyph].x);
	assert l.lineBoxAt(7).top == second.top;
	assert l.indexAt(0.0, second.top + 1.0) == 6;
	assert l.indexAt(1000.0, second.top + 1.0) == second.indexEnd;
	assert l.indexAt(l.glyphs[1].x + 0.1, 0.0) == 1;
}

test "a wrapped row measures its tabs from its own start" {
	const room: float32 = calcTextWidth("yy\tzz", style()) - 1.0;
	const l = wrapped("xxxxx yy\tzz", room, PLAIN_LINES);
	assert (l.lines.length as int32) == 3;
	for (const line of l.lines) { assert line.width <= room; }
}

test "a tab at size 0 advances nothing and places every glyph at a number" {
	const l = TextLayout.layout("a\tb", { ...style(), size: 0.0 });
	for (const g of l.glyphs) { assert g.x == g.x && g.advance == g.advance; }
	assert l.width == l.width;
}

test "a click past a row that wraps with no separator keeps the caret on that row" {
	const l = wrapped("well-known", calcTextWidth("well-", style()) + 1.0, PLAIN_LINES);
	assert (l.lines.length as int32) == 2;
	const first = l.lines[0];
	assert first.indexEnd == 5 && l.lines[1].indexStart == 5;
	const index: int32 = l.indexAt(1000.0, first.top + 1.0);
	assert index == 5;
	assert l.lineBoxAt(index).top == first.top;
	assert approx(l.xForIndex(index), first.x + first.width);
}
