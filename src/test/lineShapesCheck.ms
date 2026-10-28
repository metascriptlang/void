import { DEFAULT_FONT, FontId, addFont } from "../void2d/font";
import {
	Align,
	LineShapes,
	ShapedText,
	TextRun,
	TextStyle,
	UnderlineStyle,
	emptyLineShapes,
	shapeLines,
	shapeText,
} from "../void2d/textLayout";
import { TextDirection } from "../void2d/textDirection";
import { Color } from "../void2d/types";
import { shapedOf } from "./layoutHelpers";

const STYLE: TextStyle = {
	font: DEFAULT_FONT, size: 18.0, letterSpacing: 0.0, lineSpacing: 0.0, maxWidth: 0.0,
	align: Align.Left,
};
const CLEAR: Color = { r: 0.0, g: 0.0, b: 0.0, a: 0.0 };

function runOf(len: int32, font: FontId): TextRun {
	return {
		len: len, font: font, color: CLEAR, background: CLEAR, underline: CLEAR, wavy: false,
		underlineStyle: UnderlineStyle.Solid, strikethrough: CLEAR, overline: CLEAR,
	};
}

function byLines(
	text: string,
	style: TextStyle,
	runs: Readonly<Span<TextRun>>,
	breaks: Readonly<Span<int32>>,
	direction: TextDirection,
	ref cache: LineShapes,
): ShapedText {
	const shaped = shapeLines(text, style, runs, breaks, direction, cache);
	if (shaped.ok) { return shaped.value; }
	console.log(`lineShapesCheck: the text was refused: ${shaped.error.describe()}`);
	unreachable;
}

function sameShape(a: ShapedText, b: ShapedText): boolean {
	if (a.glyphs.length != b.glyphs.length || a.values.length != b.values.length) { return false; }
	for (let k: int32 = 0; k < (a.glyphs.length as int32); k++) {
		const x = a.glyphs[k];
		const y = b.glyphs[k];
		if (x.face != y.face || x.glyph != y.glyph || x.size != y.size ||
			x.codepoint != y.codepoint || x.x != y.x || x.advance != y.advance || x.line != y.line ||
			x.charIndex != y.charIndex || x.index != y.index || x.byteStart != y.byteStart ||
			x.byteEnd != y.byteEnd || x.run != y.run || x.clusterStart != y.clusterStart ||
			x.shapeStart != y.shapeStart || x.offsetX != y.offsetX || x.offsetY != y.offsetY) {
			console.log(`lineShapesCheck: glyph ${k} differs`);
			return false;
		}
	}
	for (let k: int32 = 0; k < (a.values.length as int32); k++) {
		if (a.values[k] != b.values[k]) { return false; }
	}
	if (a.bidi.levels.length != b.bidi.levels.length ||
		a.bidi.paragraphs.length != b.bidi.paragraphs.length) {
		console.log("lineShapesCheck: the BiDi runs differ in length");
		return false;
	}
	for (let k: int32 = 0; k < (a.bidi.levels.length as int32); k++) {
		if (a.bidi.levels[k] != b.bidi.levels[k] || a.bidi.resets[k] != b.bidi.resets[k]) {
			return false;
		}
	}
	for (let k: int32 = 0; k < (a.bidi.paragraphs.length as int32); k++) {
		if (a.bidi.paragraphs[k] != b.bidi.paragraphs[k]) { return false; }
	}
	return a.units == b.units && a.bytes == b.bytes && a.tabStop == b.tabStop;
}

function matchesWhole(
	text: string,
	runs: Readonly<Span<TextRun>>,
	breaks: Readonly<Span<int32>>,
	ref cache: LineShapes,
): boolean {
	const whole = shapedOf(text, STYLE, runs, breaks);
	return sameShape(byLines(text, STYLE, runs, breaks, TextDirection.Auto, cache), whole);
}

const TEXTS: string[] = [
	"",
	"one line",
	"two\nlines",
	"trailing newline\n",
	"\n\nblank lines\n\n",
	"tab\tstop on one line\nnone here",
	"crlf\r\nline",
	"emoji \u{1F600} and \u{1D11E} pairs\nnext \u{1F600}",
	"AVATAR kerned\nWAVE To",
];

test "the text shaped one line at a time joins into the text shaped whole" {
	const noRuns: Vec<TextRun> = new Array(0);
	const noBreaks: Vec<int32> = new Array(0);
	for (const text of TEXTS) {
		let cache: LineShapes = emptyLineShapes(STYLE);
		assert matchesWhole(text, noRuns, noBreaks, cache);
		assert matchesWhole(text, noRuns, noBreaks, cache);
	}
}

test "runs that cross lines, an empty run and shaping breaks keep their indices" {
	const text: string = "let total = 1;\nconst name = \"x\";\nreturn";
	const second: FontId = DEFAULT_FONT;
	let runs: Vec<TextRun> = new Array(0);
	runs.push(runOf(4, DEFAULT_FONT));
	runs.push(runOf(14, second));
	runs.push(runOf(0, second));
	runs.push(runOf(15, DEFAULT_FONT));
	runs.push(runOf(6, second));
	let breaks: Vec<int32> = new Array(0);
	breaks.push(2);
	breaks.push(20);
	let cache: LineShapes = emptyLineShapes(STYLE);
	assert matchesWhole(text, runs, breaks, cache);
	assert matchesWhole(text, runs, breaks, cache);
}

test "an edit reshapes only its line and the joined text still equals the whole" {
	const noRuns: Vec<TextRun> = new Array(0);
	const noBreaks: Vec<int32> = new Array(0);
	let cache: LineShapes = emptyLineShapes(STYLE);
	assert matchesWhole("alpha\nbeta\ngamma", noRuns, noBreaks, cache);
	const kept = cache.lines[2].shaped;
	assert matchesWhole("alpha\nbetas\ngamma", noRuns, noBreaks, cache);
	assert cache.lines[2].shaped === kept;
	assert matchesWhole("alpha\nbetas\ngamma\ndelta", noRuns, noBreaks, cache);
	assert matchesWhole("alphabetas\ngamma\ndelta", noRuns, noBreaks, cache);
}

test "a style change shapes every line again" {
	const noRuns: Vec<TextRun> = new Array(0);
	const noBreaks: Vec<int32> = new Array(0);
	let cache: LineShapes = emptyLineShapes(STYLE);
	assert matchesWhole("alpha\nbeta", noRuns, noBreaks, cache);
	const bigger: TextStyle = { ...STYLE, size: 30.0 };
	const lines = byLines("alpha\nbeta", bigger, noRuns, noBreaks, TextDirection.Auto, cache);
	assert sameShape(lines, shapedOf("alpha\nbeta", bigger, noRuns, noBreaks));
}

when (voidBidi) {
	const HEBREW_FACE: string = "tests/fonts/notoSansHebrewSubset.ttf";
	const MIXED: string = "plain line\n\u{5E9}\u{5DC}\u{5D5}\u{5DD} (12) end\n\n34 digits\n";

	test "BiDi paragraphs per line join into the paragraphs of the whole text" {
		const added = addFont(HEBREW_FACE);
		assert added.ok;
		const style: TextStyle = { ...STYLE, font: added.value };
		const noRuns: Vec<TextRun> = new Array(0);
		const noBreaks: Vec<int32> = new Array(0);
		for (const direction of [TextDirection.Auto, TextDirection.Rtl, TextDirection.Ltr]) {
			const whole = shapeText(MIXED, style, noRuns, noBreaks, direction);
			assert whole.ok;
			let cache: LineShapes = emptyLineShapes(style);
			assert sameShape(byLines(MIXED, style, noRuns, noBreaks, direction, cache), whole.value);
			assert sameShape(byLines(MIXED, style, noRuns, noBreaks, direction, cache), whole.value);
		}
	}
}
