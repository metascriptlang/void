import { glyphInkBox, faceMetrics } from "../void2d/face";
import {
	Align,
	LaidGlyph,
	LineOptions,
	PLAIN_LINES,
	TextLayout,
	TextRun,
	TextStyle,
	wrapOnGrid,
} from "../void2d/textLayout";
import { DEFAULT_FONT, FontId, addFont, fontFace } from "../void2d/font";
import { NerdAlign, NerdConstraint, NerdSize } from "../void2d/nerdFontTable";
import { cellConstraint, isSymbol } from "../void2d/nerdFont";
import {
	allocateLabelText,
	labelLines,
	labelTexts,
	setLabelConstraintWidths,
	setLabelLines,
	shapeLabel,
} from "../void2d/labelText";
import { approx } from "./helpers";
import { shapedOf } from "./layoutHelpers";
import { holdFontFile } from "./fontFile";

const CELL: float32 = 6.0;
const SIZE: float32 = 20.0;
const ARROW: string = "→";
const GAUGE: string = "";
const THREE_BYTES_ONE_CELL: uint8[] = [1, 0, 0];
const THREE_BYTES_TWO_CELLS: uint8[] = [2, 0, 0];

let rowFont: FontId = DEFAULT_FONT;
let rowLoaded: boolean = false;

function row(): TextStyle {
	if (!rowLoaded) {
		holdFontFile("assets/font.ttf");
		rowFont = try addFont("assets/font.ttf") catch DEFAULT_FONT;
		rowLoaded = true;
	}
	return {
		font: rowFont, size: SIZE, letterSpacing: 0.0, lineSpacing: 0.0, maxWidth: 944.0,
		align: Align.Left,
	};
}

function laidWith(text: string, widths: Readonly<Span<uint8>>): TextLayout {
	const noRuns: TextRun[] = [];
	const noBreaks: int32[] = [];
	const cells: LineOptions = { ...PLAIN_LINES, forceWidth: CELL };
	const noCells: uint8[] = [];
	return wrapOnGrid(shapedOf(text, row(), noRuns, noBreaks), row(), cells, noCells, widths);
}

function laidPlain(text: string): TextLayout {
	const none: uint8[] = [];
	return laidWith(text, none);
}

function inked(g: LaidGlyph): [float32, float32, float32, float32] {
	const box = glyphInkBox(g.face, g.glyph, 1024.0);
	const k: float32 = g.size / 1024.0;
	return [
		g.x + g.offsetX + box[0] * k, g.offsetY + box[1] * k,
		g.x + g.offsetX + box[2] * k, g.offsetY + box[3] * k,
	];
}

function constraintOf(codepoint: int32): NerdConstraint {
	const c = cellConstraint(codepoint);
	if (c == null) {
		console.log(`nerdFontCheck: U+${codepoint.toString(16)} has no constraint`);
		unreachable;
	}
	return c;
}

function sizeOf(codepoint: int32): NerdSize {
	const c = cellConstraint(codepoint);
	if (c == null) { return NerdSize.None; }
	return c.size;
}

test "the table gives a cover, a fit-to-cover, a stretch and a symbol's default fit" {
	assert cellConstraint("A".code) == null;
	assert sizeOf(0x2192) == NerdSize.Fit;
	assert sizeOf(0x2630) == NerdSize.Cover;
	assert sizeOf(0xEE09) == NerdSize.Cover;
	assert sizeOf(0xE000) == NerdSize.FitCover1;
	assert sizeOf(0xE0B8) == NerdSize.Stretch;
	assert sizeOf(0xF1AF0) == NerdSize.FitCover1;
	assert sizeOf(0xF1AF1) == NerdSize.Fit;
	assert isSymbol(0x1F600) && !isSymbol(0x1F650) && isSymbol(0x1F680) && !isSymbol(0x2189);
}

test "a fit symbol shrinks into its constraint cells and keeps the left edge on the cell" {
	const plain = laidPlain(ARROW);
	const [plainLeft, plainTop, plainRight, plainBottom] = inked(plain.glyphs[0]);
	assert plainRight - plainLeft > 2.0 * CELL + 1.0;
	const one = laidWith(ARROW, THREE_BYTES_ONE_CELL);
	const [left, top, right, bottom] = inked(one.glyphs[0]);
	assert approx(right - left, CELL);
	assert approx(left, 0.0);
	assert approx((top + bottom) / 2.0, (plainTop + plainBottom) / 2.0);
	const two = laidWith(ARROW, THREE_BYTES_TWO_CELLS);
	const [wideLeft, wideTop, wideRight, wideBottom] = inked(two.glyphs[0]);
	assert approx(wideRight - wideLeft, 2.0 * CELL);
	assert approx(wideLeft, 0.0);
}

test "a cover symbol fills its padded cell, centred, by the box of its scale group" {
	const own = faceMetrics(fontFace(row().font), SIZE);
	const height: float32 = own.ascent + own.descent + own.lineGap;
	const plain = laidPlain(GAUGE);
	const [plainLeft, plainTop, plainRight, plainBottom] = inked(plain.glyphs[0]);
	const gaugeConstraint: NerdConstraint = constraintOf(0xEE09);
	const groupWidth: float32 = (plainRight - plainLeft) / gaugeConstraint.relWidth;
	const groupHeight: float32 = (plainBottom - plainTop) / gaugeConstraint.relHeight;
	const k: float32 = Math.min(
		(1.0 - 0.03) * CELL / groupWidth, (1.0 - 0.03) * height / groupHeight,
	);
	const placed = laidWith(GAUGE, THREE_BYTES_ONE_CELL);
	const [left, top, right, bottom] = inked(placed.glyphs[0]);
	assert approx(right - left, k * (plainRight - plainLeft));
	assert approx(bottom - top, k * (plainBottom - plainTop));
	assert approx(left, (CELL - (right - left)) / 2.0);
	assert approx(bottom, (own.descent + own.lineGap) - (height - groupHeight * k) / 2.0);
	assert placed.glyphs[0].size != plain.glyphs[0].size;
}

test "a text glyph keeps its size and place when constraint widths are given" {
	const bare = laidPlain("Wi, x");
	const widths: uint8[] = [1, 1, 1, 1, 1];
	const given = laidWith("Wi, x", widths);
	assert (given.glyphs.length as int32) == (bare.glyphs.length as int32);
	for (let k = 0; k < (bare.glyphs.length as int32); k++) {
		assert given.glyphs[k].size == bare.glyphs[k].size;
		assert given.glyphs[k].x == bare.glyphs[k].x;
		assert given.glyphs[k].offsetX == bare.glyphs[k].offsetX;
		assert given.glyphs[k].offsetY == bare.glyphs[k].offsetY;
	}
}

test "a symbol with no constraint width keeps the cluster fit it has without the call" {
	const bare = laidPlain(ARROW);
	const zero: uint8[] = [0, 0, 0];
	const given = laidWith(ARROW, zero);
	assert given.glyphs[0].size == bare.glyphs[0].size;
	assert given.glyphs[0].offsetX == bare.glyphs[0].offsetX;
}

test "a label takes the constraint widths and draws its symbol into them" {
	const index = allocateLabelText();
	setLabelLines(index, { ...labelLines(index), forceWidth: CELL });
	shapeLabel(index, ARROW, row());
	const bare: float32 = labelTexts[index].layout.glyphs[0].size;
	setLabelConstraintWidths(index, THREE_BYTES_ONE_CELL);
	shapeLabel(index, ARROW, row());
	const [left, top, right, bottom] = inked(labelTexts[index].layout.glyphs[0]);
	assert labelTexts[index].layout.glyphs[0].size != bare;
	assert approx(right - left, CELL);
}
