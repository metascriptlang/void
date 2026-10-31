import { DEFAULT_FONT, FontId, addFont } from "../void2d/font";
import {
	Align,
	LineOptions,
	LineShapes,
	PLAIN_LINES,
	TextLayout,
	TextRun,
	TextStyle,
	Truncate,
	UnderlineStyle,
	emptyLineShapes,
	shapeLines,
	shapeText,
	wrapLines,
	wrapOnGrid,
} from "../void2d/textLayout";
import { TextDirection } from "../void2d/textDirection";
import { Color } from "../void2d/types";

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

let reused: TextLayout = {
	glyphs: new Array(0),
	bidi: {
		levels: new Array(0), resets: new Array(0), logicalX: new Array(0),
		lineLevels: new Array(0),
	},
	lines: new Array(0),
	ascent: 0.0,
	descent: 0.0,
	lineHeight: 0.0,
	width: 0.0,
	height: 0.0,
	decoration: {
		underlineTop: 0.0, underlineThickness: 0.0, strikethroughTop: 0.0,
		strikethroughThickness: 0.0,
	},
};

function byLines(
	text: string,
	style: TextStyle,
	options: LineOptions,
	cells: Readonly<Span<uint8>>,
	runs: Readonly<Span<TextRun>>,
	breaks: Readonly<Span<int32>>,
	direction: TextDirection,
	ref cache: LineShapes,
): TextLayout {
	const shaped = shapeLines(text, style, runs, breaks, direction, cache);
	if (!shaped.ok) {
		console.log(`lineShapesCheck: the text was refused: ${shaped.error.describe()}`);
		unreachable;
	}
	const noConstraints: Vec<uint8> = new Array(0);
	wrapLines(cache, style, options, cells, noConstraints, reused);
	return reused;
}

function sameLayout(a: TextLayout, b: TextLayout): boolean {
	if (a.glyphs.length != b.glyphs.length || a.lines.length != b.lines.length) {
		console.log(`lineShapesCheck: ${a.glyphs.length} glyphs in ${a.lines.length} rows, ` +
			`the whole has ${b.glyphs.length} in ${b.lines.length}`);
		return false;
	}
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
	for (let k: int32 = 0; k < (a.lines.length as int32); k++) {
		const x = a.lines[k];
		const y = b.lines[k];
		if (x.firstGlyph != y.firstGlyph || x.glyphCount != y.glyphCount || x.x != y.x ||
			x.top != y.top || x.baseline != y.baseline || x.height != y.height ||
			x.width != y.width || x.charStart != y.charStart || x.charEnd != y.charEnd ||
			x.indexStart != y.indexStart || x.indexEnd != y.indexEnd ||
			x.byteStart != y.byteStart || x.byteEnd != y.byteEnd) {
			console.log(`lineShapesCheck: row ${k} differs`);
			return false;
		}
	}
	if (a.bidi.levels.length != b.bidi.levels.length ||
		a.bidi.lineLevels.length != b.bidi.lineLevels.length) {
		console.log("lineShapesCheck: the BiDi levels differ in length");
		return false;
	}
	for (let k: int32 = 0; k < (a.bidi.levels.length as int32); k++) {
		if (a.bidi.levels[k] != b.bidi.levels[k] || a.bidi.resets[k] != b.bidi.resets[k] ||
			a.bidi.logicalX[k] != b.bidi.logicalX[k]) {
			console.log(`lineShapesCheck: BiDi slot ${k} differs`);
			return false;
		}
	}
	for (let k: int32 = 0; k < (a.bidi.lineLevels.length as int32); k++) {
		if (a.bidi.lineLevels[k] != b.bidi.lineLevels[k]) { return false; }
	}
	return a.width == b.width && a.height == b.height && a.ascent == b.ascent &&
		a.lineHeight == b.lineHeight;
}

function wholeLayout(
	text: string,
	style: TextStyle,
	options: LineOptions,
	cells: Readonly<Span<uint8>>,
	runs: Readonly<Span<TextRun>>,
	breaks: Readonly<Span<int32>>,
	direction: TextDirection,
): TextLayout {
	const shaped = shapeText(text, style, runs, breaks, direction);
	if (!shaped.ok) {
		console.log(`lineShapesCheck: the text was refused: ${shaped.error.describe()}`);
		unreachable;
	}
	const noConstraints: Vec<uint8> = new Array(0);
	return wrapOnGrid(shaped.value, style, options, cells, noConstraints);
}

function laysOutWhole(
	text: string,
	style: TextStyle,
	options: LineOptions,
	cells: Readonly<Span<uint8>>,
	runs: Readonly<Span<TextRun>>,
	breaks: Readonly<Span<int32>>,
	direction: TextDirection,
	ref cache: LineShapes,
): boolean {
	return sameLayout(
		byLines(text, style, options, cells, runs, breaks, direction, cache),
		wholeLayout(text, style, options, cells, runs, breaks, direction),
	);
}

function matchesWhole(
	text: string,
	runs: Readonly<Span<TextRun>>,
	breaks: Readonly<Span<int32>>,
	ref cache: LineShapes,
): boolean {
	const noCells: Vec<uint8> = new Array(0);
	return laysOutWhole(
		text, STYLE, PLAIN_LINES, noCells, runs, breaks, TextDirection.Auto, cache,
	);
}

function oneCellEach(text: string): Vec<uint8> {
	let cells: Vec<uint8> = new Array(0);
	for (let k: int32 = 0; k < (text.asBytes().length as int32); k++) { cells.push(1); }
	return cells;
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

test "the text laid out one line at a time equals the text laid out whole" {
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

test "an edit lays out only its line again and the layout still equals the whole" {
	const noRuns: Vec<TextRun> = new Array(0);
	const noBreaks: Vec<int32> = new Array(0);
	let cache: LineShapes = emptyLineShapes(STYLE);
	assert matchesWhole("alpha\nbeta\ngamma", noRuns, noBreaks, cache);
	const kept = cache.lines[2].shaped;
	const keptRows = cache.lines[2].wrap;
	assert matchesWhole("alpha\nbetas\ngamma", noRuns, noBreaks, cache);
	assert cache.lines[2].shaped === kept;
	assert cache.lines[2].wrap === keptRows;
	assert matchesWhole("alpha\nbetas\ngamma\ndelta", noRuns, noBreaks, cache);
	assert matchesWhole("alphabetas\ngamma\ndelta", noRuns, noBreaks, cache);
}

test "an edit that keeps a line's length shapes that line again" {
	const noRuns: Vec<TextRun> = new Array(0);
	const noBreaks: Vec<int32> = new Array(0);
	let cache: LineShapes = emptyLineShapes(STYLE);
	assert matchesWhole("alpha\nbeta\ngamma", noRuns, noBreaks, cache);
	assert matchesWhole("alpha\nbetz\ngamma", noRuns, noBreaks, cache);
	assert matchesWhole("alpha\nzeta\ngamma", noRuns, noBreaks, cache);
	assert matchesWhole("alpha\nzeta\ngammo", noRuns, noBreaks, cache);
}

test "a line inserted above keeps the shapes of the lines below it" {
	const noRuns: Vec<TextRun> = new Array(0);
	const noBreaks: Vec<int32> = new Array(0);
	let cache: LineShapes = emptyLineShapes(STYLE);
	assert matchesWhole("alpha\nbeta\ngamma", noRuns, noBreaks, cache);
	const beta = cache.lines[1].shaped;
	const gamma = cache.lines[2].shaped;
	assert matchesWhole("new\nalpha\nbeta\ngamma", noRuns, noBreaks, cache);
	assert cache.lines[2].shaped === beta;
	assert cache.lines[3].shaped === gamma;
	assert matchesWhole("alpha\nbeta\ngamma", noRuns, noBreaks, cache);
	assert cache.lines[1].shaped === beta;
}

test "a line whose runs or shaping breaks change shapes again although its text is kept" {
	const text: string = "alpha\nbeta\ngamma";
	let runs: Vec<TextRun> = new Array(0);
	runs.push(runOf(6, DEFAULT_FONT));
	runs.push(runOf(5, DEFAULT_FONT));
	runs.push(runOf(5, DEFAULT_FONT));
	const noBreaks: Vec<int32> = new Array(0);
	let cache: LineShapes = emptyLineShapes(STYLE);
	assert matchesWhole(text, runs, noBreaks, cache);
	const alpha = cache.lines[0].shaped;
	const beta = cache.lines[1].shaped;
	let split: Vec<TextRun> = new Array(0);
	split.push(runOf(6, DEFAULT_FONT));
	split.push(runOf(2, DEFAULT_FONT));
	split.push(runOf(3, DEFAULT_FONT));
	split.push(runOf(5, DEFAULT_FONT));
	assert matchesWhole(text, split, noBreaks, cache);
	assert cache.lines[0].shaped === alpha;
	assert cache.lines[1].shaped !== beta;
	const splitBeta = cache.lines[1].shaped;
	let breaks: Vec<int32> = new Array(0);
	breaks.push(8);
	assert matchesWhole(text, split, breaks, cache);
	assert cache.lines[0].shaped === alpha;
	assert cache.lines[1].shaped !== splitBeta;
	const brokenBeta = cache.lines[1].shaped;
	let moved: Vec<int32> = new Array(0);
	moved.push(9);
	assert matchesWhole(text, split, moved, cache);
	assert cache.lines[1].shaped !== brokenBeta;
	const movedBeta = cache.lines[1].shaped;
	let resplit: Vec<TextRun> = new Array(0);
	resplit.push(runOf(6, DEFAULT_FONT));
	resplit.push(runOf(3, DEFAULT_FONT));
	resplit.push(runOf(2, DEFAULT_FONT));
	resplit.push(runOf(5, DEFAULT_FONT));
	assert matchesWhole(text, resplit, moved, cache);
	assert cache.lines[0].shaped === alpha;
	assert cache.lines[1].shaped !== movedBeta;
}

test "a style change shapes every line again" {
	const noRuns: Vec<TextRun> = new Array(0);
	const noBreaks: Vec<int32> = new Array(0);
	const noCells: Vec<uint8> = new Array(0);
	let cache: LineShapes = emptyLineShapes(STYLE);
	assert matchesWhole("alpha\nbeta", noRuns, noBreaks, cache);
	const bigger: TextStyle = { ...STYLE, size: 30.0 };
	assert laysOutWhole(
		"alpha\nbeta", bigger, PLAIN_LINES, noCells, noRuns, noBreaks, TextDirection.Auto, cache,
	);
}

const PROSE: string = "the quick brown fox jumps over the lazy dog\n\nshort\n" +
	"a second paragraph that wraps more than once at this width\ttab\n";

test "wrapped, indented, truncated and aligned rows equal the whole text's rows" {
	const noRuns: Vec<TextRun> = new Array(0);
	const noBreaks: Vec<int32> = new Array(0);
	const noCells: Vec<uint8> = new Array(0);
	const hanging: LineOptions = { ...PLAIN_LINES, hangingIndent: 12.0 };
	for (const align of [Align.Left, Align.Right, Align.Center, Align.MultilineCenter]) {
		const style: TextStyle = { ...STYLE, maxWidth: 160.0, lineSpacing: 3.0, align: align };
		let cache: LineShapes = emptyLineShapes(style);
		for (const options of [PLAIN_LINES, hanging]) {
			assert laysOutWhole(
				PROSE, style, options, noCells, noRuns, noBreaks, TextDirection.Auto, cache,
			);
		}
	}
	for (const truncate of [Truncate.End, Truncate.Start, Truncate.Middle]) {
		const style: TextStyle = { ...STYLE, maxWidth: 120.0 };
		let cache: LineShapes = emptyLineShapes(style);
		const options: LineOptions = { ...PLAIN_LINES, truncate: truncate };
		assert laysOutWhole(
			PROSE, style, options, noCells, noRuns, noBreaks, TextDirection.Auto, cache,
		);
	}
}

test "a width change wraps every line again from its kept shape" {
	const noRuns: Vec<TextRun> = new Array(0);
	const noBreaks: Vec<int32> = new Array(0);
	const noCells: Vec<uint8> = new Array(0);
	const narrow: TextStyle = { ...STYLE, maxWidth: 140.0 };
	let cache: LineShapes = emptyLineShapes(narrow);
	assert laysOutWhole(
		PROSE, narrow, PLAIN_LINES, noCells, noRuns, noBreaks, TextDirection.Auto, cache,
	);
	const kept = cache.lines[0].shaped;
	const wide: TextStyle = { ...narrow, maxWidth: 300.0 };
	assert laysOutWhole(
		PROSE, wide, PLAIN_LINES, noCells, noRuns, noBreaks, TextDirection.Auto, cache,
	);
	assert cache.lines[0].shaped === kept;
}

test "a grid of cells per byte lays out per line as the whole grid" {
	const noRuns: Vec<TextRun> = new Array(0);
	const noBreaks: Vec<int32> = new Array(0);
	const grid: LineOptions = { ...PLAIN_LINES, forceWidth: 9.0 };
	const text: string = "$ ls -la\ntotal 48\ndrwxr-xr-x  2 user  staff  64 Oct 29 .\n";
	let cache: LineShapes = emptyLineShapes(STYLE);
	const cells: Vec<uint8> = oneCellEach(text);
	assert laysOutWhole(text, STYLE, grid, cells, noRuns, noBreaks, TextDirection.Auto, cache);
	const wrapping: TextStyle = { ...STYLE, maxWidth: 200.0 };
	assert laysOutWhole(text, wrapping, grid, cells, noRuns, noBreaks, TextDirection.Auto, cache);
}

when (voidBidi) {
	const HEBREW_FACE: string = "tests/fonts/notoSansHebrewSubset.ttf";
	const MIXED: string = "plain line\n\u{5E9}\u{5DC}\u{5D5}\u{5DD} (12) end\n\n34 digits\n";

	test "BiDi rows per line equal the rows of the whole text" {
		const added = addFont(HEBREW_FACE);
		assert added.ok;
		const style: TextStyle = { ...STYLE, font: added.value };
		const noRuns: Vec<TextRun> = new Array(0);
		const noBreaks: Vec<int32> = new Array(0);
		const noCells: Vec<uint8> = new Array(0);
		for (const direction of [TextDirection.Auto, TextDirection.Rtl, TextDirection.Ltr]) {
			let cache: LineShapes = emptyLineShapes(style);
			assert laysOutWhole(
				MIXED, style, PLAIN_LINES, noCells, noRuns, noBreaks, direction, cache,
			);
			assert laysOutWhole(
				MIXED, style, PLAIN_LINES, noCells, noRuns, noBreaks, direction, cache,
			);
			assert laysOutWhole(
				"plain line\n34 digits", style, PLAIN_LINES, noCells, noRuns, noBreaks, direction,
				cache,
			);
		}
	}
}
