import {
	glyphIndex,
	glyphAdvance,
	glyphKern,
	faceMetrics,
} from "../void2d/face";
import {
	TextLayout,
	TextStyle,
	NO_GLYPH,
	TAB_STOP_SPACES,
	calcTextWidth,
} from "../void2d/textLayout";
import { addFont, fontFace, fallbackProbes } from "../void2d/font";
import { approx } from "./helpers";

let loadedFont: int32 = -1;

function style(): TextStyle {
	if (loadedFont < 0) { loadedFont = addFont("assets/font.ttf"); }
	return {
		font: loadedFont,
		size: 13.0,
		letterSpacing: 0.0,
		lineSpacing: 0.0,
		maxWidth: 0.0,
		align: 0.0,
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
	assert l.byteForX(1, 50.0) == 3;
	assert approx(l.xForByte(3), l.lines[1].x);
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

test "align shifts each line by its own width about the origin" {
	const l = TextLayout.layout("abc\na", { ...style(), align: 0.5 });
	assert approx(l.lines[0].x, -l.lines[0].width * 0.5);
	assert approx(l.lines[1].x, -l.lines[1].width * 0.5);
	assert approx(l.glyphs[l.lines[1].firstGlyph].x, l.lines[1].x);
}

test "multi-byte text keeps byte ranges for the caret" {
	const l = TextLayout.layout("é漢b", style());
	assert (l.glyphs.length as int32) == 3;
	assert l.glyphs[0].codepoint == 0xE9;
	assert l.glyphs[1].codepoint == 0x6F22;
	assert l.glyphs[1].byteStart == 2;
	assert l.glyphs[1].byteEnd == 5;
	assert l.glyphs[2].charIndex == 2;
	assert approx(l.xForByte(2), l.glyphs[1].x);
	assert approx(l.xForByte(6), l.width);
	assert l.byteForX(0, l.glyphs[2].x + 0.1) == 5;
	assert l.byteForX(0, 1000.0) == 6;
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
	const fresh: TextStyle = { ...style(), font: addFont("assets/font.ttf") };
	TextLayout.layout("x", fresh);
	const before: int32 = fallbackProbes();
	TextLayout.layout("x\t\r\u0001\u001B\u001F\u007Fx", fresh);
	assert fallbackProbes() == before;
}
