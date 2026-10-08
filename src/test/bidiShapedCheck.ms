import { glyphIndex } from "../void2d/face";
import { FontId, addFont, fontFace } from "../void2d/font";
import {
	Align,
	LineOptions,
	PLAIN_LINES,
	ShapedText,
	TextErrorKind,
	TextLayout,
	TextStyle,
	TextRun,
	setTextShaping,
	textShapingOn,
	wrapText,
} from "../void2d/textLayout";
import { TextDirection } from "../void2d/textDirection";
import { Color } from "../void2d/types";
import { approx } from "./helpers";
import { laid, laidRuns, shapedIn } from "./layoutHelpers";

const ARABIC_FACE: string = "tests/fonts/notoSansArabicSubset.ttf";
const HEBREW_FACE: string = "tests/fonts/notoSansHebrewSubset.ttf";
const MARHABA: string = "\u{645}\u{631}\u{62D}\u{628}\u{627}";
const HEBREW_WORD: string = "\u{5E9}\u{5DC}\u{5D5}\u{5DD}";
const SALAAM: string = "\u{627}\u{644}\u{633}\u{644}\u{627}\u{645} " +
	"\u{639}\u{644}\u{64A}\u{643}\u{645}";

function fontOf(path: string): FontId {
	const added = addFont(path);
	if (added.ok) { return added.value; }
	console.log(`${path} did not load`);
	unreachable;
}

function styleOf(font: FontId, spacing: float32): TextStyle {
	return {
		font: font, size: 20.0, letterSpacing: spacing, lineSpacing: 0.0, maxWidth: 0.0,
		align: Align.Left,
	};
}

function shapingOn(): boolean {
	const was: boolean = textShapingOn();
	setTextShaping(true);
	return was;
}

function advancesOf(shaped: ShapedText): Vec<float32> {
	let out: Vec<float32> = new Array(0);
	for (const g of shaped.glyphs) { out.push(g.advance); }
	return out;
}

test "an Arabic word is shaped right to left and joined, then reflected as a block" {
	const was = shapingOn();
	const style = styleOf(fontOf(ARABIC_FACE), 0.0);
	const shaped = shapedIn(MARHABA, style, TextDirection.Auto);
	assert shaped.bidi.paragraphs[0] == 1;
	const l = wrapText(shaped, style, PLAIN_LINES);
	assert (l.bidi.lineLevels.length as int32) == 1;
	const joined = glyphIndex(fontFace(style.font), 0x645);
	assert l.glyphs[0].glyph != joined;
	assert l.glyphs[0].x > l.glyphs[1].x && l.glyphs[1].x > l.glyphs[2].x;
	assert approx(l.glyphs[0].x + l.glyphs[0].advance, l.lines[0].width);
	setTextShaping(was);
}

test "a mark glyph that kb positioned in its visual pen lands on the base it belongs to" {
	const was = shapingOn();
	const style = styleOf(fontOf(ARABIC_FACE), 0.0);
	const shaped = shapedIn(MARHABA, style, TextDirection.Auto);
	const l = wrapText(shaped, style, PLAIN_LINES);
	let marks: int32 = 0;
	for (let k = 1; k < (l.glyphs.length as int32); k++) {
		if (l.glyphs[k].charIndex != l.glyphs[k - 1].charIndex) { continue; }
		marks = marks + 1;
		assert l.glyphs[k].advance == 0.0;
		assert approx(l.glyphs[k].x, l.glyphs[k - 1].x);
	}
	assert marks > 0;
	setTextShaping(was);
}

test "mixed text is shaped as its level runs, each in its own direction" {
	const was = shapingOn();
	const font = fontOf(HEBREW_FACE);
	const style = styleOf(font, 0.0);
	const whole = shapedIn("ab " + HEBREW_WORD + " cd", style, TextDirection.Auto);
	const before = shapedIn("ab ", style, TextDirection.Auto);
	const hebrew = shapedIn(HEBREW_WORD, style, TextDirection.Rtl);
	const after = shapedIn(" cd", style, TextDirection.Auto);
	const parts: Vec<float32> = advancesOf(whole);
	let at: int32 = 0;
	for (const advance of advancesOf(before)) {
		assert approx(parts[at], advance);
		at = at + 1;
	}
	for (const advance of advancesOf(hebrew)) {
		assert approx(parts[at], advance);
		at = at + 1;
	}
	for (const advance of advancesOf(after)) {
		assert approx(parts[at], advance);
		at = at + 1;
	}
	assert at == (parts.length as int32);
	setTextShaping(was);
}

test "letter spacing leaves the letters of a joining script joined and unspaced" {
	const was = shapingOn();
	const font = fontOf(ARABIC_FACE);
	const plain = wrapText(shapedIn(MARHABA, styleOf(font, 0.0), TextDirection.Auto),
		styleOf(font, 0.0), PLAIN_LINES);
	const spaced = wrapText(shapedIn(MARHABA, styleOf(font, 3.0), TextDirection.Auto),
		styleOf(font, 3.0), PLAIN_LINES);
	assert plain.glyphs.length == spaced.glyphs.length;
	for (let i = 0; i < (plain.glyphs.length as int32); i++) {
		assert plain.glyphs[i].glyph == spaced.glyphs[i].glyph;
		assert approx(plain.glyphs[i].advance, spaced.glyphs[i].advance);
	}
	assert approx(plain.width, spaced.width);
	setTextShaping(was);
}

test "with the shaper off Arabic is refused by name and Hebrew is laid out" {
	const was = textShapingOn();
	setTextShaping(false);
	const arabic = TextLayout.layout(MARHABA, styleOf(fontOf(ARABIC_FACE), 0.0));
	assert !arabic.ok;
	if (!arabic.ok) { assert arabic.error.kind == TextErrorKind.ArabicNeedsShaper; }
	assert TextLayout.layout(HEBREW_WORD, styleOf(fontOf(HEBREW_FACE), 0.0)).ok;
	setTextShaping(was);
}

function plainRun(len: int32, font: FontId): TextRun {
	const ink: Color = { r: 1.0, g: 1.0, b: 1.0, a: 1.0 };
	const clear: Color = { r: 0.0, g: 0.0, b: 0.0, a: 0.0 };
	return {
		len: len, font: font, color: ink, background: clear, underline: clear, wavy: false,
		strikethrough: clear,
	};
}

function placedAsWithoutRuns(
	text: string, style: TextStyle, runs: Readonly<Span<TextRun>>,
): boolean {
	const plain = laid(text, style);
	const styled = laidRuns(text, style, runs);
	if (plain.glyphs.length != styled.glyphs.length) { return false; }
	for (let i = 0; i < (plain.glyphs.length as int32); i++) {
		if (plain.glyphs[i].glyph != styled.glyphs[i].glyph) { return false; }
		if (!approx(plain.glyphs[i].x, styled.glyphs[i].x)) { return false; }
	}
	return true;
}

test "style runs over a right-to-left line leave every glyph where the line without runs puts it" {
	const was = shapingOn();
	const font = fontOf(ARABIC_FACE);
	const runs: TextRun[] = [plainRun(6, font), plainRun(1, font), plainRun(5, font)];
	assert placedAsWithoutRuns(SALAAM, styleOf(font, 0.0), runs);
	setTextShaping(was);
}

test "style runs that cut right-to-left words inside them keep the words in visual order" {
	const was = shapingOn();
	const font = fontOf(HEBREW_FACE);
	const phrase: string = HEBREW_WORD + " " + HEBREW_WORD + " " + HEBREW_WORD;
	const runs: TextRun[] = [plainRun(2, font), plainRun(5, font), plainRun(7, font)];
	assert placedAsWithoutRuns(phrase, styleOf(font, 0.0), runs);
	setTextShaping(was);
}
